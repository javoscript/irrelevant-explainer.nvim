-- Always run filesystem tests in a fresh editor with an isolated cache home.
if vim.env.EXPLAINR_CACHE_CHILD ~= "1" then
  T.test("persistent cache isolated child suite", function()
    local temp = vim.fn.tempname()
    vim.fn.mkdir(temp, "p", 448)
    temp = assert(vim.uv.fs_realpath(temp))
    local result = vim.system({ vim.v.progpath, "--headless", "-u", "NONE", "-i", "NONE", "-n",
      "-c", "luafile tests/run.lua" }, { text = true, env = {
      XDG_CACHE_HOME = temp, EXPLAINR_CACHE_CHILD = "1", EXPLAINR_TEST = "tests/cache_test.lua",
    } }):wait(30000)
    vim.fn.delete(temp, "rf")
    assert(result.code == 0, (result.stdout or "") .. (result.stderr or ""))
    print(result.stdout or "", result.stderr or "")
  end)
  return
end

local cache, uv = require("explainr.cache"), vim.uv
local source, key, key2, key3 = string.rep("a", 64), string.rep("b", 64), string.rep("c", 64), string.rep("d", 64)
local root = vim.fn.stdpath("cache") .. "/explainr/results/v1"
local dir = root .. "/" .. source
local path = dir .. "/" .. key .. ".json"
local config = { cache = { enabled = true, max_bytes = 1024, namespace = "test" } }
local function wait(start)
  local count, result = 0, nil
  local op = start(function(value)
    assert(not vim.in_fast_event())
    count, result = count + 1, value
  end)
  T.eq(0, count)
  assert(type(op.cancel) == "function")
  assert(vim.wait(5000, function() return count > 0 end, 1), "callback timed out")
  T.eq(1, count)
  return result
end
local function write(value, k, cfg)
  return wait(function(cb) return cache.write(source, k or key, value, cfg or config, cb) end)
end
local function read(k, cfg)
  return wait(function(cb) return cache.read(source, k or key, cfg or config, cb) end)
end
local function clear(cfg)
  return wait(function(cb) return cache.clear(cfg or config, cb) end)
end
local function raw(file, text)
  local fd = assert(uv.fs_open(file, "w", 384))
  assert(uv.fs_write(fd, text, 0)); assert(uv.fs_close(fd))
end
local function reset()
  vim.fn.delete(vim.fn.stdpath("cache") .. "/explainr", "rf")
end
local function clean()
  T.eq({}, vim.fn.glob(dir .. "/.tmp-*", false, true))
  T.eq(nil, uv.fs_lstat(root .. "/.lock"))
end

T.test("cache opaque roundtrip, private permissions, opt-out and explicit clear", function()
  reset()
  T.eq(nil, read())
  local value = { arbitrary = { "α", false, vim.NIL }, notes = {}, version = 999 }
  T.eq(true, write(value)); T.eq(value, read())
  for _, directory in ipairs({ root, dir, root .. "/..", root .. "/../.." }) do
    T.eq(448, bit.band(assert(uv.fs_stat(directory)).mode, 511))
  end
  T.eq(384, bit.band(assert(uv.fs_stat(path)).mode, 511))
  local off = { cache = { enabled = false } }
  T.eq(nil, read(nil, off)); T.eq(nil, write("disabled", nil, off)); T.eq(value, read())
  local epoch = cache.epoch()
  T.eq(true, clear(off)); T.eq(epoch + 1, cache.epoch()); T.eq(nil, read())
  clean()
end)

T.test("cache truncation and bound before JSON decoding or temporary writes", function()
  reset(); write("old")
  raw(path, '{"truncated":')
  T.eq(nil, read())
  raw(path, string.rep("x", 1025))
  local decode, calls = vim.json.decode, 0
  vim.json.decode = function(...) calls = calls + 1; return decode(...) end
  local ok, err = pcall(function() T.eq(nil, read()) end)
  vim.json.decode = decode
  assert(ok, err); T.eq(0, calls)
  T.eq(nil, write(string.rep("x", 1023))) -- JSON quotes count toward the cap.
  T.eq(1025, uv.fs_stat(path).size)
  T.eq(true, write(string.rep("x", 1022)))
  T.eq(1024, uv.fs_stat(path).size)
  T.eq(string.rep("x", 1022), read()); clean()
end)

T.test("cache multi-chunk UTF-8 entries and optional callbacks", function()
  reset()
  local value = { text = string.rep("α😀", 40000) }
  local cfg = { cache = { max_bytes = #vim.json.encode(value) } }
  T.eq(true, write(value, key, cfg)); T.eq(value, read(key, cfg))
  local opened, original = false, uv.fs_rename
  uv.fs_rename = function(...)
    opened = true
    return original(...)
  end
  cache.write(source, key, "no callback", config)
  assert(vim.wait(3000, function() return opened end, 1))
  uv.fs_rename = original
  assert(vim.wait(3000, function() return not uv.fs_lstat(root .. "/.lock") end, 1))
  T.eq("no callback", read())
  cache.clear(config)
  assert(vim.wait(3000, function() return not uv.fs_lstat(path) end, 1))
  assert(vim.wait(3000, function() return not uv.fs_lstat(root .. "/.lock") end, 1))
  clean()
end)

T.test("cache global size limit uses least recent access and preserves oversized replacement", function()
  reset()
  local cfg = { cache = { max_bytes = 16 } }
  write("111111", key, cfg); write("222222", key2, cfg)
  assert(uv.fs_utime(path, 1, 1))
  T.eq("111111", read(key, cfg))
  assert(uv.fs_utime(dir .. "/" .. key2 .. ".json", 2, 2))
  write("333333", key3, cfg)
  T.eq("111111", read(key, cfg)); T.eq(nil, read(key2, cfg)); T.eq("333333", read(key3, cfg))
  T.eq(nil, write(string.rep("z", 20), key, cfg)); T.eq("111111", read(key, cfg))
  local total = 0
  for _, file in ipairs(vim.fn.glob(dir .. "/*.json", false, true)) do total = total + uv.fs_stat(file).size end
  T.eq(16, total); clean()
end)

T.test("cache rejects entry symlinks, directories, hardlinks, and public permissions", function()
  reset(); write("safe")
  local outside = vim.env.XDG_CACHE_HOME .. "/outside"
  raw(outside, '"outside"')
  assert(uv.fs_unlink(path)); assert(uv.fs_symlink(outside, path))
  T.eq(nil, read()); T.eq(nil, write("bad")); T.eq(nil, clear())
  T.eq({ '"outside"' }, vim.fn.readfile(outside))
  assert(uv.fs_unlink(path)); assert(uv.fs_mkdir(path, 448))
  T.eq(nil, read()); T.eq(nil, write("bad"))
  assert(uv.fs_rmdir(path)); assert(uv.fs_link(outside, path))
  T.eq(nil, read()); T.eq(nil, write("bad")); assert(uv.fs_unlink(path))
  write("safe"); assert(uv.fs_chmod(path, 420))
  T.eq(nil, read()); T.eq(nil, write("bad")); assert(uv.fs_chmod(path, 384))
  T.eq("safe", read()); clean()
end)

T.test("cache rejects symlink and nonprivate owned parent directories", function()
  reset(); write("safe")
  assert(uv.fs_chmod(dir, 493))
  T.eq(nil, read()); T.eq(nil, write("bad")); assert(uv.fs_chmod(dir, 448))
  local moved = root .. "/saved"
  assert(uv.fs_rename(dir, moved)); assert(uv.fs_symlink(moved, dir))
  T.eq(nil, read()); T.eq(nil, write("bad")); T.eq(nil, clear())
  assert(uv.fs_unlink(dir)); assert(uv.fs_rename(moved, dir))
  local results = vim.fn.stdpath("cache") .. "/explainr/results"
  assert(uv.fs_rename(results, results .. "-saved")); assert(uv.fs_symlink(results .. "-saved", results))
  T.eq(nil, read()); T.eq(nil, write("bad")); T.eq(nil, clear())
  assert(uv.fs_unlink(results)); assert(uv.fs_rename(results .. "-saved", results))
  T.eq("safe", read()); clean()
end)

T.test("cache bounded live-lock contention, stale-owner recovery and orphan temporary cleanup", function()
  reset(); write("safe")
  local lock = root .. "/.lock"
  raw(lock, tostring(uv.os_getpid())); assert(uv.fs_utime(lock, 1, 1))
  local started = uv.hrtime()
  T.eq(nil, write("blocked"))
  assert((uv.hrtime() - started) / 1e6 < 1500)
  assert(uv.fs_stat(lock)); assert(uv.fs_unlink(lock))
  -- Reap a real child, obtaining a definitely dead owner rather than guessing a PID.
  local child = vim.system({ vim.v.progpath, "--headless", "-u", "NONE", "-i", "NONE", "+qa" })
  local pid = child.pid; T.eq(0, child:wait().code)
  raw(lock, tostring(pid)); assert(uv.fs_utime(lock, 1, 1))
  local temp = dir .. "/.tmp-" .. pid .. "-123-1"
  raw(temp, "incomplete")
  T.eq(true, write("recovered")); T.eq("recovered", read())
  T.eq(nil, uv.fs_lstat(temp)); clean()
  raw(lock, "not-an-owner"); assert(uv.fs_utime(lock, 1, 1))
  T.eq(nil, write("blocked")); assert(uv.fs_stat(lock)); assert(uv.fs_unlink(lock))
end)

T.test("cache cancellation suppresses callbacks and clear immediately invalidates queued writes", function()
  reset(); write("safe")
  local calls = 0
  cache.read(source, key, config, function() calls = calls + 1 end):cancel()
  cache.write(source, key, "cancelled", config, function() calls = calls + 1 end):cancel()
  vim.wait(50, function() return false end, 1); T.eq(0, calls); T.eq("safe", read())
  local completed = 0
  cache.write(source, key, "pre-clear", config, function() completed = completed + 1 end)
  local epoch = cache.epoch()
  local op = cache.clear(config, function() completed = completed + 1 end)
  T.eq(epoch + 1, cache.epoch()); assert(op)
  assert(vim.wait(3000, function() return completed == 2 end, 1))
  T.eq(nil, read()); clean()
end)

T.test("cache in-flight clear and cancellation clean temporary files", function()
  reset(); write("old")
  local original, triggered, cleared = uv.fs_fsync, false, false
  uv.fs_fsync = function(fd, cb)
    if not triggered then
      triggered = true
      cache.clear(config, function() cleared = true end)
    end
    return original(fd, cb)
  end
  local ok, err = pcall(function() T.eq(nil, write("new")) end)
  uv.fs_fsync = original
  assert(ok, err); assert(triggered)
  assert(vim.wait(3000, function() return cleared end, 1)); T.eq(nil, read()); clean()
  local operation, calls = nil, 0
  uv.fs_fsync = function(fd, cb) operation:cancel(); return original(fd, cb) end
  operation = cache.write(source, key, "cancelled", config, function() calls = calls + 1 end)
  assert(vim.wait(3000, function() return operation.cancelled end, 1))
  uv.fs_fsync = original
  assert(vim.wait(3000, function() return not uv.fs_lstat(root .. "/.lock") end, 1))
  T.eq(0, calls); T.eq(nil, read()); clean()
end)

T.test("cache failed replacement preserves old entry with bounded diagnostics", function()
  reset(); write("old")
  local rename, notify, warnings = uv.fs_rename, vim.notify, 0
  vim.notify = function() warnings = warnings + 1 end
  uv.fs_rename = function(_, _, cb) vim.schedule(function() cb("EACCES") end); return true end
  local ok, err = pcall(function()
    T.eq(nil, write("new")); T.eq(nil, write("new-again"))
    T.eq("old", read()); clean()
  end)
  uv.fs_rename, vim.notify = rename, notify
  assert(ok, err); assert(warnings <= 1)
  local outside = vim.fn.stdpath("cache") .. "/unrelated"
  raw(outside, "keep")
  T.eq(true, clear()); T.eq({ "keep" }, vim.fn.readfile(outside)); clean()
end)

T.test("cache pruning and write failures remain misses and clean partial writes", function()
  reset(); write("old")
  local unlink = uv.fs_unlink
  uv.fs_unlink = function(file, cb)
    if file == path then vim.schedule(function() cb("EACCES") end); return true end
    return unlink(file, cb)
  end
  local ok, err = pcall(function()
    local cfg = { cache = { max_bytes = 8 } }
    T.eq(nil, write("new-new", key2, cfg)) -- Oversized before pruning.
    T.eq(nil, write("new", key2, cfg)) -- The old entry cannot be evicted.
    T.eq("old", read()); T.eq(nil, read(key2)); clean()
    T.eq(nil, clear()); T.eq("old", read())
  end)
  uv.fs_unlink = unlink
  assert(ok, err)
  local fs_write = uv.fs_write
  uv.fs_write = function(fd, data, offset, cb)
    if data == '"replacement"' then vim.schedule(function() cb("ENOSPC") end); return true end
    return fs_write(fd, data, offset, cb)
  end
  ok, err = pcall(function() T.eq(nil, write("replacement")); T.eq("old", read()); clean() end)
  uv.fs_write = fs_write
  assert(ok, err)
end)

T.test("cache cancellation during read and lock wait does not deliver a late value", function()
  reset(); write("old")
  local fs_read, operation, calls = uv.fs_read, nil, 0
  uv.fs_read = function(fd, size, offset, cb)
    operation:cancel()
    return fs_read(fd, size, offset, cb)
  end
  operation = cache.read(source, key, config, function() calls = calls + 1 end)
  assert(vim.wait(3000, function() return operation.cancelled end, 1))
  uv.fs_read = fs_read
  assert(vim.wait(3000, function() return not uv.fs_lstat(root .. "/.lock") end, 1))
  T.eq(0, calls); clean()
  raw(root .. "/.lock", tostring(uv.os_getpid()))
  operation = cache.write(source, key, "blocked", config, function() calls = calls + 1 end)
  vim.defer_fn(function() operation:cancel() end, 20)
  vim.wait(100, function() return false end, 1)
  T.eq(0, calls); assert(uv.fs_unlink(root .. "/.lock"))
  T.eq("old", read()); clean()
end)

T.test("cache concurrent processes replace and clear only complete JSON records", function()
  reset(); write("initial")
  local function process(value, clearing)
    local code = string.format([[
      vim.opt.rtp:prepend(vim.fn.getcwd())
      local c = require('explainr.cache')
      local s, k = string.rep('a',64), string.rep('b',64)
      local done = false
      local cb = function() done = true end
      if %s then c.clear({}, cb) else c.write(s,k,%q,{},cb) end
      assert(vim.wait(5000,function() return done end,1))
    ]], tostring(clearing or false), value)
    return vim.system({ vim.v.progpath, "--headless", "-u", "NONE", "-i", "NONE", "-n",
      "-c", "lua " .. code, "-c", "qa!" }, { text = true })
  end
  local a, b, c = process("writer-a"), process("writer-b"), process("", true)
  for _ = 1, 10 do
    local value = read()
    assert(value == nil or value == "initial" or value == "writer-a" or value == "writer-b")
  end
  local results = {}
  for _, child in ipairs({ a, b, c }) do
    results[#results + 1] = child:wait(5000)
  end
  for _, result in ipairs(results) do assert(result.code == 0, result.stderr) end
  local value = read()
  assert(value == nil or value == "writer-a" or value == "writer-b")
  local count = 0
  for i = 1, 8 do cache.write(source, key, { n = i }, config, function() count = count + 1 end) end
  assert(vim.wait(5000, function() return count == 8 end, 1))
  assert(type(read().n) == "number"); clean()
end)
