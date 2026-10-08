-- Disposable opaque JSON records. Identity, schemas and admission belong to callers.
-- Keys are lowercase SHA-256 hex strings; namespace/decoder_key are caller identity
-- inputs, not additional directories. Operations expose cancel() (dot or colon).
-- Read callbacks receive a value or nil; optional write/clear callbacks receive
-- true on success, nil on a skip/failure. All callbacks are scheduled.
local M = {}
local uv = vim.uv or vim.loop
local generation, serial, last_warning = 0, 0, nil
local DEFAULT_LIMIT = 104857600

local function warn()
  local now = uv.hrtime()
  if not last_warning or now - last_warning > 60000000000 then
    last_warning = now
    vim.schedule(function()
      vim.notify("Explainr: persistent cache unavailable; continuing without it", vim.log.levels.WARN)
    end)
  end
end

-- Resume only on the main loop, including error and cancellation cleanup.
local function async(name, ...)
  local co = coroutine.running()
  local args = { ... }
  args[#args + 1] = function(err, value)
    vim.schedule(function()
      local ok = coroutine.resume(co, err, value)
      if not ok then warn() end
    end)
  end
  local ok, request = pcall(uv[name], unpack(args))
  if not ok or not request then error("filesystem unavailable", 0) end
  local err, value = coroutine.yield()
  return value, err
end

local function checked(name, ...)
  local value, err = async(name, ...)
  if err then error("filesystem unavailable", 0) end
  return value
end

local function pause()
  local co = coroutine.running()
  vim.defer_fn(function() coroutine.resume(co) end, 10)
  coroutine.yield()
end

local function same(a, b)
  return a and b and a.dev == b.dev and a.ino == b.ino
end

local function private(stat, kind)
  return stat and stat.type == kind and (not uv.getuid or stat.uid == uv.getuid())
    and (kind ~= "file" or stat.nlink == 1) and bit.band(stat.mode, 63) == 0
end

local function directory(path, owned, create)
  local stat, err = async("fs_lstat", path)
  if not stat and err and err:find("ENOENT", 1, true) and not create then return false end
  if not stat and err and err:find("ENOENT", 1, true) and create then
    local _, mkdir_err = async("fs_mkdir", path, 448)
    if mkdir_err and not mkdir_err:find("EEXIST", 1, true) then error("directory unavailable", 0) end
    stat = checked("fs_lstat", path)
  end
  if not stat or stat.type ~= "directory" then error("unsafe directory", 0) end
  if owned and not private(stat, "directory") then error("nonprivate directory", 0) end
  return true
end

local function parents(root, create)
  -- Check every component: even the owned parents must never be symlinks.
  local path = ""
  for part in root:gmatch("[^/]+") do
    path = path .. "/" .. part
    if not directory(path, false, create) then return nil end
  end
  if not directory(root .. "/explainr", true, create)
    or not directory(root .. "/explainr/results", true, create)
    or not directory(root .. "/explainr/results/v1", true, create) then return nil end
  return root .. "/explainr/results/v1"
end

local function hash(value)
  return type(value) == "string" and #value == 64 and value:match("^[a-f0-9]+$")
end

local function open_read(state, path, limit)
  local stat = async("fs_lstat", path)
  if not stat then return nil end
  if not private(stat, "file") then warn(); return nil end
  if stat.size > limit then return nil end
  -- O_NOFOLLOW is an extra guard where available; lstat/fstat also verify identity.
  local flags = bit.bor(uv.constants.O_RDONLY, uv.constants.O_NOFOLLOW or 0, uv.constants.O_NONBLOCK or 0)
  local fd = async("fs_open", path, flags, 384)
  if not fd then return nil end
  state.fd = fd
  local actual = checked("fs_fstat", fd)
  if not same(stat, actual) or not private(actual, "file") or actual.size > limit then
    checked("fs_close", fd); state.fd = nil
    return nil
  end
  local parts, offset = {}, 0
  while offset < actual.size do
    local part = checked("fs_read", fd, math.min(65536, actual.size - offset), offset)
    if #part == 0 then break end
    parts[#parts + 1], offset = part, offset + #part
  end
  checked("fs_close", fd); state.fd = nil
  if offset ~= actual.size then return nil end
  return table.concat(parts), stat
end

local function dead(pid)
  if not pid or pid < 1 or pid % 1 ~= 0 then return false end
  local ok, err = uv.kill(pid, 0)
  return not ok and type(err) == "string" and err:find("ESRCH", 1, true) ~= nil
end

local function recover(state, lock)
  local stat = async("fs_lstat", lock)
  if not private(stat, "file") or os.time() - stat.mtime.sec < 30 then return end
  -- A separate exclusive guard prevents two stale-owner recoverers unlinking
  -- a newly acquired lock. An orphaned recovery guard conservatively disables recovery.
  local fd = async("fs_open", lock .. ".recovery", "wx", 384)
  if not fd then return end
  state.recovery = lock .. ".recovery"
  state.fd = fd
  checked("fs_close", fd); state.fd = nil
  local text, observed = open_read(state, lock, 64)
  if text and same(stat, observed) and dead(tonumber(text)) then
    local current = async("fs_lstat", lock)
    if same(current, observed) then checked("fs_unlink", lock) end
  end
  checked("fs_unlink", state.recovery); state.recovery = nil
end

local function acquire(state, root)
  local lock = root .. "/.lock"
  local deadline = uv.hrtime() + 500000000
  repeat
    if state.cancelled or state.epoch ~= generation then return false end
    local fd, err = async("fs_open", lock, "wx", 384)
    if fd then
      state.lock, state.fd = lock, fd
      state.lock_stat = checked("fs_fstat", fd)
      local owner = tostring(uv.os_getpid())
      if checked("fs_write", fd, owner, 0) ~= #owner then error("lock write failed", 0) end
      checked("fs_close", fd); state.fd = nil
      return true
    end
    if not err or not err:find("EEXIST", 1, true) then error("lock unavailable", 0) end
    recover(state, lock)
    pause()
  until uv.hrtime() >= deadline
  warn()
  return false
end

local function entries(root)
  local result = {}
  local scan = checked("fs_scandir", root)
  while true do
    local name = uv.fs_scandir_next(scan)
    if not name then break end
    if hash(name) then
      local dir = root .. "/" .. name
      local stat = checked("fs_lstat", dir)
      if not private(stat, "directory") then error("unsafe source directory", 0) end
      local children = checked("fs_scandir", dir)
      while true do
        local child = uv.fs_scandir_next(children)
        if not child then break end
        local owner = child:match("^%.tmp%-(%d+)%-%d+%-%d+$")
        if owner and dead(tonumber(owner)) then
          local temp = dir .. "/" .. child
          if private(checked("fs_lstat", temp), "file") then checked("fs_unlink", temp) end
        end
        if child:match("%.json$") and hash(child:sub(1, -6)) then
          local path = dir .. "/" .. child
          local item = checked("fs_lstat", path)
          if not private(item, "file") then error("unsafe entry", 0) end
          result[#result + 1] = { path = path, size = item.size, time = item.mtime.sec + item.mtime.nsec / 1e9 }
        end
      end
    end
  end
  return result
end

local function live(state)
  return not state.cancelled and state.epoch == generation
end

local function start(config, callback, work)
  config = config or {}
  local options = config.cache or config
  local state = { epoch = generation }
  function state.cancel() state.cancelled = true end
  local co = coroutine.create(function()
    local ok, value = pcall(function()
      if not live(state) then return end
      return work(state, options)
    end)
    -- Cancellation does not abandon descriptors, temporary files or the lock.
    local function cleanup(name, value)
      local succeeded, _, err = pcall(async, name, value)
      if not succeeded or err then warn() end
    end
    if state.fd then cleanup("fs_close", state.fd) end
    if state.temp then cleanup("fs_unlink", state.temp) end
    if state.recovery then cleanup("fs_unlink", state.recovery) end
    if state.lock then
      local stat = async("fs_lstat", state.lock)
      if same(stat, state.lock_stat) then cleanup("fs_unlink", state.lock) end
    end
    if not ok then warn(); value = nil end
    vim.schedule(function()
      if state.epoch ~= generation then value = nil end
      if not state.cancelled and callback then callback(value) end
    end)
  end)
  vim.schedule(function()
    local ok = coroutine.resume(co)
    if not ok then warn() end
  end)
  return state
end

local function limit(options)
  local value = options.max_bytes or DEFAULT_LIMIT
  if type(value) ~= "number" or value <= 0 or value == math.huge or value % 1 ~= 0 then
    error("invalid size bound", 0)
  end
  return value
end

function M.epoch() return generation end

function M.read(source_hash, request_key, config, callback)
  return start(config, callback, function(state, options)
    if options.enabled == false or not hash(source_hash) or not hash(request_key) then return end
    local bound = limit(options)
    local root = parents(vim.fn.stdpath("cache"), false)
    if not root or not acquire(state, root) then return end
    if not directory(root .. "/" .. source_hash, true, false) then return end
    local path = root .. "/" .. source_hash .. "/" .. request_key .. ".json"
    local text = open_read(state, path, bound)
    if not text or not live(state) then return end
    local ok, value = pcall(vim.json.decode, text)
    if not ok then return end
    -- mtime is access time for LRU; the caller's opaque record is never modified.
    local seconds, micros = uv.gettimeofday()
    local now = seconds + micros / 1e6
    checked("fs_utime", path, now, now)
    if live(state) then return value end
  end)
end

function M.write(source_hash, request_key, value, config, callback)
  return start(config, callback, function(state, options)
    if options.enabled == false or not hash(source_hash) or not hash(request_key) then return end
    local bound = limit(options)
    local text = vim.json.encode(value)
    if #text > bound then return end
    local root = parents(vim.fn.stdpath("cache"), true)
    if not acquire(state, root) or not live(state) then return end
    local dir = root .. "/" .. source_hash
    directory(dir, true, true)
    local path = dir .. "/" .. request_key .. ".json"
    local prior, err = async("fs_lstat", path)
    if prior and not private(prior, "file") then error("unsafe entry", 0) end
    if not prior and err and not err:find("ENOENT", 1, true) then error("entry unavailable", 0) end
    local records, total = entries(root), #text
    for _, record in ipairs(records) do if record.path ~= path then total = total + record.size end end
    table.sort(records, function(a, b)
      if a.time == b.time then return a.path < b.path end
      return a.time < b.time
    end)
    serial = serial + 1
    local temp = dir .. "/.tmp-" .. uv.os_getpid() .. "-" .. string.format("%.0f", uv.hrtime()) .. "-" .. serial
    local fd = checked("fs_open", temp, "wx", 384)
    state.temp, state.fd = temp, fd
    local offset = 0
    while offset < #text do
      if not live(state) then return end
      local count = checked("fs_write", fd, text:sub(offset + 1, offset + 65536), offset)
      if count == 0 then error("short write", 0) end
      offset = offset + count
    end
    checked("fs_fsync", fd)
    checked("fs_close", fd); state.fd = nil
    for _, record in ipairs(records) do
      if not live(state) then return end
      if total <= bound then break end
      if record.path ~= path then
        checked("fs_unlink", record.path)
        total = total - record.size
      end
    end
    if not live(state) then return end
    checked("fs_rename", temp, path); state.temp = nil
    return true
  end)
end

function M.clear(config, callback)
  generation = generation + 1
  return start(config, callback, function(state)
    local root = parents(vim.fn.stdpath("cache"), true)
    if not acquire(state, root) then return end
    for _, record in ipairs(entries(root)) do
      if not live(state) then return end
      checked("fs_unlink", record.path)
    end
    return true
  end)
end

return M
