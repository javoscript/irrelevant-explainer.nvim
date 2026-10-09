local M = {}
local api, uv = vim.api, vim.uv

-- Stable object serialization: fingerprints must not depend on Lua hash order.
local function canonical(value)
  if type(value) ~= "table" then return vim.json.encode(value) end
  local keys, parts = {}, {}
  for key in pairs(value) do keys[#keys + 1] = key end
  table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
  for _, key in ipairs(keys) do parts[#parts + 1] = canonical(key) .. ":" .. canonical(value[key]) end
  return "{" .. table.concat(parts, ",") .. "}"
end
local function hash(value) return vim.fn.sha256(canonical(value)) end

-- A collection owns one outstanding operation. All resumes (including CPU
-- batches) happen on later event-loop turns; cancellation kills the process or
-- cancels the filesystem request, closes descriptors, and silences callbacks.
local function run(work, callback, max_bytes)
  local job = { cancelled = false }
  local thread, resume
  local function close_fd()
    if job.fd then
      local fd = job.fd
      job.fd = nil
      uv.fs_close(fd, function() end)
    end
  end
  local function await(start) return coroutine.yield(start) end
  local io = {}
  function io.pause() await(function(done) done(true) end) end
  function io.batch(index) if index % 32 == 0 then io.pause() end end
  -- Neovim window/buffer calls can invoke Lua autocmds. Execute these outside
  -- the collection coroutine, on Neovim's main Lua stack.
  function io.main(fn)
    local ok, value = await(function(done) done(pcall(fn)) end)
    assert(ok, value)
    return value
  end
  function io.hash(value) return io.main(function() return hash(value) end) end
  function io.size(size)
    if size > max_bytes then
      if io.snapshot then
        error(string.format("Review snapshot requires at least %d UTF-8 bytes; review.max_snapshot_bytes is %d. Nothing was omitted.", size, max_bytes), 0)
      end
      error(string.format("Complete prompt requires at least %d UTF-8 bytes; context.max_bytes is %d. "
        .. "The budget includes complete old/new file contents, patches and request overhead, not only changed lines. "
        .. "Nothing was omitted. Increase the budget, filter the comparison, or request file/hunk scope.", size, max_bytes), 0)
    end
  end
  function io.git(cwd, args, unset_config)
    local command = { "git", "--no-optional-locks", "-c", "core.quotepath=false" }
    vim.list_extend(command, args)
    local result = await(function(done)
      local process = vim.system(command, { cwd = cwd, text = false, timeout = 30000,
        env = { GIT_EXTERNAL_DIFF = "" } }, function(value) done(value) end)
      job.abort = function() process:kill(15) end
    end)
    if unset_config and result.code == 1 and result.stdout == "" and result.stderr == "" then return "" end
    assert(result.code == 0, "Git collection failed: " .. (result.stderr or "process failed"))
    return result.stdout
  end
  local function fs(method, ...)
    local args = { ... }
    local err, value = await(function(done)
      if method == "fs_read" then job.reading = true end
      args[#args + 1] = function(failure, result)
        if method == "fs_read" then job.reading = false end
        job.abort = nil
        if job.cancelled then close_fd(); return end
        done(failure, result)
      end
      local request = uv[method](unpack(args))
      if method ~= "fs_close" then
        job.abort = function() if request then pcall(uv.cancel, request) end end
      end
    end)
    return value, err
  end
  function io.realpath(path) return fs("fs_realpath", path) or path end
  function io.stat(path)
    local stat, err = fs("fs_lstat", path)
    if not stat then
      assert(tostring(err):find("ENOENT", 1, true), "cannot stat required content: " .. path .. ": " .. tostring(err))
      return nil
    end
    return stat
  end
  function io.disk(path)
    local stat = io.stat(path)
    if not stat then return nil end
    assert(stat.type == "file", "unsupported nonregular file: " .. path)
    if not io.unbounded then io.size(stat.size) end
    local fd
    -- An open can finish after cancellation. Its callback must still close the
    -- returned descriptor, even though the coroutine will never resume.
    local open_err
    open_err, fd = await(function(done)
      local request = uv.fs_open(path, "r", 438, function(failure, descriptor)
        if job.cancelled then if descriptor then uv.fs_close(descriptor, function() end) end; return end
        job.fd = descriptor
        done(failure, descriptor)
      end)
      job.abort = function() if request then pcall(uv.cancel, request) end end
    end)
    assert(fd, "cannot read required content: " .. path .. ": " .. tostring(open_err))
    local bytes, read_err = fs("fs_read", fd, stat.size, 0)
    job.fd = nil -- The close request, not cancellation, now owns this descriptor.
    local _, close_err = fs("fs_close", fd)
    assert(not close_err, "cannot close required content: " .. path .. ": " .. tostring(close_err))
    assert(bytes and #bytes == stat.size, "cannot read complete required content: " .. path .. ": " .. tostring(read_err))
    return bytes, stat
  end
  job.cancel = function()
    if job.cancelled then return end
    job.cancelled = true
    if job.abort then pcall(job.abort); job.abort = nil end
    -- A read may already be running despite uv.cancel(). Its completion owns
    -- the final close, so never race a read against descriptor reuse.
    if not job.reading then close_fd() end
  end
  thread = coroutine.create(function() return work(io) end)
  resume = function(...)
    if job.cancelled then return end
    job.abort = nil
    local ok, value = coroutine.resume(thread, ...)
    if not ok or coroutine.status(thread) == "dead" then
      if ok and io.validate then
        local valid, err = pcall(io.validate)
        if not valid then ok, value = false, err end
      end
      if job.cancelled then return end
      job.cancel()
      callback(ok and value or nil, not ok and ("Diff collection failed: " .. tostring(value)) or nil)
    else
      local started, err = pcall(value, function(...)
        job.abort = nil
        if job.cancelled then return end
        local args = { n = select("#", ...), ... }
        vim.schedule(function() resume(unpack(args, 1, args.n)) end)
      end)
      if not started then job.cancel(); callback(nil, "Diff collection failed: " .. tostring(err)) end
    end
  end
  vim.schedule(resume)
  return job
end

local function lines(bytes)
  if bytes == "" then return {} end
  local result = vim.split(bytes, "\n", { plain = true })
  if result[#result] == "" then table.remove(result) end
  return result
end

local function buffer_bytes(buf, underlying, io)
  if not io.unbounded then io.size(#buf.bytes) end
  local content = buf.lines
  -- Revision buffers do not reliably preserve the blob's end-of-line flag.
  -- Preserve raw bytes only when the buffer actually displays that version,
  -- never merely because 'modified' is false (e.g. stale external disk edit).
  if not buf.modified and underlying then
    local expected = lines(underlying)
    if #expected == 0 then expected = { "" } end
    expected = vim.tbl_map(function(line) return line:gsub("\r$", "") end, expected)
    if vim.deep_equal(content, expected) then return underlying end
  end
  return buf.bytes
end

-- Freeze mutable editor inputs before the first asynchronous Git read. Buffer
-- handles are lookup hints only, never content identity or request ownership.
local function freeze(state)
  state.buffers, state.local_buffers = {}, {}
  local mutable = state.pair.new.type ~= "commit" or state.pair.old.type ~= "commit"
  if not mutable then return state end
  local root = uv.fs_realpath(state.cwd) or state.cwd
  for _, buf in ipairs(api.nvim_list_bufs()) do
    if api.nvim_buf_is_loaded(buf) then
      local stage = false
      for _, id in pairs(state.stage_buffers) do if id == buf then stage = true; break end end
      local name = api.nvim_buf_get_name(buf)
      local working = state.pair.new.type == "local" and vim.bo[buf].buftype == ""
        and ((uv.fs_realpath(name) or name):sub(1, #root + 1) == root .. "/")
      if stage or working then
        local content = api.nvim_buf_get_lines(buf, 0, -1, false)
        local separator = vim.bo[buf].fileformat == "dos" and "\r\n" or "\n"
        local bytes = table.concat(content, separator) .. (vim.bo[buf].endofline and separator or "")
        if api.nvim_buf_call(buf, function() return vim.fn.wordcount().bytes == 0 end) then bytes = "" end
        state.buffers[buf] = { lines = content, bytes = bytes, modified = vim.bo[buf].modified }
        if working then state.local_buffers[#state.local_buffers + 1] = { id = buf, name = name } end
      end
    end
  end
  return state
end

local function revision_args(pair)
  if pair.new.type == "commit" then return { pair.old.commit, pair.new.commit } end
  if pair.new.type == "stage" then return { "--cached", pair.old.commit } end
  if pair.old.type == "commit" then return { pair.old.commit } end
  return {}
end

local function with_paths(args, paths)
  args[#args + 1] = "--"
  vim.list_extend(args, paths)
  return args
end

local function names(bytes)
  return vim.split(bytes, "\0", { plain = true, trimempty = true })
end

local function doc_priority(path)
  path = path:lower()
  if path:match("^openspec/") then return 1 end
  if path:match("adr") or path:match("decision") or path:match("requirement") or path:match("spec") then
    if path:match("%.md$") or path:match("%.rst$") or path:match("%.txt$") or path:match("%.adoc$") then return 2 end
  end
  return 3
end

local function gather(state, io, strategy)
  local git, hash = io.git, io.hash
  local cwd, pair, paths = state.cwd, state.pair, state.path_args
  local mutable = pair.old.type ~= "commit" or pair.new.type ~= "commit"
  local show_untracked = state.show_untracked
  if show_untracked and pair.old.type == "stage" and pair.new.type == "local" then
    -- Diffview's explicit true still defers to Git config; only "no" disables
    -- inclusion. Unset config exits 1 and defaults to inclusion.
    local setting = git(cwd, { "config", "status.showUntrackedFiles" }, true)
    show_untracked = vim.trim(setting:match("[^\n]*") or "") ~= "no"
  end
  local guards, candidates, renames, statuses = {}, {}, {}, {}
  local tracked = {}
  local raw = git(cwd, with_paths(vim.list_extend({ "diff", "--no-ext-diff", "--no-textconv", "--name-status",
    "-z", "-M", "--ignore-submodules=none" }, revision_args(pair)), paths))
  guards.changes = hash(raw)
  local tokens, i, number = names(raw), 1, 0
  while i <= #tokens do
    number = number + 1
    io.batch(number)
    local status, oldpath = tokens[i], tokens[i + 1]
    assert(oldpath and status:sub(1, 1) ~= "U", "unresolved comparison conflicts")
    local path = oldpath
    if status:match("^[RC]") then path = tokens[i + 2]; i = i + 1 end
    assert(path, "incomplete Git change manifest")
    candidates[oldpath], candidates[path] = true, true
    statuses[path] = status
    if status:sub(1, 1) == "R" then renames[path] = oldpath end
    i = i + 2
  end
  local index = {}
  if mutable then
    -- Full index guard, not merely the stale displayed list or focused path.
    local index_raw = git(cwd, { "ls-files", "--stage", "-z" })
    guards.index = hash(index_raw)
    for number, token in ipairs(names(index_raw)) do
      io.batch(number)
      local mode, oid, stage, path = token:match("^(%d+) (%x+) (%d+)\t(.*)$")
      assert(stage == "0", "unmerged index is unsupported")
      index[path] = { mode = mode, oid = oid }
    end
    for number, path in ipairs(names(git(cwd, with_paths({ "ls-files", "--cached", "-z" }, paths)))) do
      io.batch(number)
      tracked[path] = true
      if state.stage_buffers[path] then candidates[path] = true end
    end
    if pair.new.type == "local" and show_untracked then
      for number, path in ipairs(names(git(cwd, with_paths({ "ls-files", "--others", "--exclude-standard", "-z" }, paths)))) do
        io.batch(number)
        candidates[path] = true
      end
    end
  end
  -- Existing displayed entries are mandatory, even if Git says they disappeared.
  for number, entry in ipairs(state.entries) do
    io.batch(number)
    candidates[entry.path], candidates[entry.oldpath] = true, true
    if entry.oldpath ~= entry.path then renames[entry.path] = entry.oldpath end
  end
  local local_buffers = {}
  if pair.new.type == "local" then
    local buffer_root = io.realpath(cwd)
    local buffers = state.local_buffers
    for number, buffer in ipairs(buffers) do
      io.batch(number)
      local name = io.realpath(buffer.name)
      if name:sub(1, #buffer_root + 1) == buffer_root .. "/" then
        local path = name:sub(#buffer_root + 2)
        -- Git already reports saved changes. Only loaded tracked buffers can
        -- add unsaved changes outside that manifest; don't read every quiet
        -- tracked file (or reject a large unchanged lockfile as prompt data).
        if tracked[path] then candidates[path] = true end
        if candidates[path] then
          assert(not local_buffers[path] or local_buffers[path] == buffer.id, "ambiguous working buffers")
          local_buffers[path] = buffer.id
        end
      end
    end
  end
  local trees = {}
  for _, side in ipairs({ "old", "new" }) do
    local rev = pair[side]
    if rev.type == "commit" then
      local tree = {}
      for number, token in ipairs(names(git(cwd, { "ls-tree", "-r", "-z", rev.commit }))) do
        io.batch(number)
        local mode, kind, oid, path = token:match("^(%d+) (%w+) (%x+)\t(.*)$")
        tree[path] = { mode = mode, kind = kind, oid = oid }
      end
      trees[side] = tree
      if rev.track_head then guards[side .. "_head"] = vim.trim(git(cwd, { "rev-parse", "HEAD" })) end
    end
  end
  local cache = { old = {}, new = {} }
  local function version(side, path)
    if cache[side][path] then return cache[side][path] end
    local rev, bytes, mode, oid = pair[side]
    io.pause()
    if rev.type == "local" then
      local stat
      bytes, stat = io.disk(cwd .. "/" .. path)
      mode = stat and (bit.band(stat.mode, 73) ~= 0 and "100755" or "100644") or nil
      guards["disk:" .. path] = bytes == nil and "absent" or hash(bytes)
    else
      local source = rev.type == "stage" and index or trees[side]
      local item = source[path]
      if item then
        assert(item.mode == "100644" or item.mode == "100755", "unsupported Git file mode at " .. path)
        mode, oid = item.mode, item.oid
        if not io.unbounded then
          io.size(assert(tonumber(git(cwd, { "cat-file", "-s", oid })), "missing blob size"))
        end
        bytes = git(cwd, { "cat-file", "blob", oid })
        if not io.unbounded then io.size(#bytes) end
      end
    end
    local buf = rev.type == "local" and local_buffers[path]
      or (rev.type == "stage" and state.stage_buffers[path])
    buf = buf and state.buffers[buf]
    if bytes == nil and buf and not buf.modified then buf = nil end
    local underlying_identity = bytes ~= nil and hash(bytes) or "absent"
    if buf then
      assert(bytes ~= nil, "loaded buffer has no required underlying version: " .. path)
      bytes = io.main(function()
        local overlaid = buffer_bytes(buf, bytes, io)
        guards["buffer:" .. side .. ":" .. path] = { bytes = buf.bytes, modified = buf.modified,
          overlaid = overlaid ~= bytes }
        return overlaid
      end)
    end
    local value = { path = path, side = side, present = bytes ~= nil, mode = mode, oid = oid,
      binary = bytes ~= nil and bytes:find("\0", 1, true) ~= nil,
      identity = bytes ~= nil and hash(bytes) or "absent" }
    value.supplied_from = buf and "loaded-buffer" or rev.type == "local" and "filesystem" or "git-blob"
    value.underlying_identity = underlying_identity
    value.overlaid = value.identity ~= underlying_identity
    value.bytes = bytes
    if value.present and not value.binary then
      value.lines, value.endofline = lines(bytes), bytes:sub(-1) == "\n"
    end
    cache[side][path] = value
    return value
  end
  local sorted, consumed = {}, {}
  for path in pairs(candidates) do sorted[#sorted + 1] = path end
  table.sort(sorted)
  for _, oldpath in pairs(renames) do consumed[oldpath] = true end
  local sizes, present, regular = {}, {}, {}
  local function size_for(side, path)
    local key = side .. ":" .. path
    if sizes[key] then return sizes[key] end
    local rev, size = pair[side], 0
    if rev.type == "local" then
      local stat = io.stat(cwd .. "/" .. path)
      if strategy == "focused" then
        guards["stat:" .. path] = stat and { stat.size, stat.mode, stat.ino, stat.mtime, stat.ctime } or "absent"
      end
      present[key], regular[key] = stat ~= nil, not stat or stat.type == "file"
      size = stat and stat.size or 0
    else
      local item = (rev.type == "stage" and index or trees[side])[path]
      present[key], regular[key] = item ~= nil, not item or item.mode == "100644" or item.mode == "100755"
      if item then size = assert(tonumber(git(cwd, { "cat-file", "-s", item.oid })), "missing blob size") end
    end
    local buf = rev.type == "local" and local_buffers[path] or rev.type == "stage" and state.stage_buffers[path]
    buf = buf and state.buffers[buf]
    if buf then
      size = math.max(size, io.main(function()
        if strategy == "focused" then
          guards["buffer:" .. side .. ":" .. path] = { bytes = buf.bytes, modified = buf.modified }
        end
        return #buf.bytes
      end))
    end
    sizes[key] = size
    return size
  end
  local comparison = { identities = vim.deepcopy(pair), selection = { kind = state.selected.kind,
    path_args = vim.deepcopy(paths), show_untracked = show_untracked,
    label = "Selected coherent " .. state.selected.kind .. " comparison; other Diffview sets excluded" }, manifest = {} }
  local omitted = 0
  if strategy == "focused" then
    for _, path in ipairs(sorted) do
      -- Guard mutable omitted versions without opening their content. Keep the
      -- full index/name manifest and all loaded-buffer ticks as well.
      if pair.new.type == "local" then size_for("new", path) end
      if pair.old.type == "stage" and state.stage_buffers[path] then size_for("old", path) end
      if pair.new.type == "stage" and state.stage_buffers[path] then size_for("new", path) end
      if consumed[path] then size_for("new", path) end
      if path ~= state.selected.path and (not consumed[path] or renames[path] or present["new:" .. path]) then
        omitted = omitted + 1
      end
    end
    table.sort(sorted, function(a, b)
      if a == b then return false end
      if a == state.selected.path then return true end
      if b == state.selected.path then return false end
      if doc_priority(a) ~= doc_priority(b) then return doc_priority(a) < doc_priority(b) end
      return a < b
    end)
  elseif io.auto then
    -- Size-only preflight prevents auto from reading every unrelated changed
    -- blob just to discover that a complete review cannot possibly fit.
    local minimum = io.main(function()
      return #assert(require("irrelevant_explainer.prompt").build({ mode = "diff", files = {}, target = {},
        comparison = comparison, context = { strategy = "review", radius = io.radius, omitted_files = 0 } }, math.huge, nil, io.prompts))
    end)
    for _, path in ipairs(sorted) do
      io.size(minimum)
      local oldpath = renames[path] or path
      -- Quiet loaded tracked buffers may not be changed at all. Their actual
      -- overlays are checked by version(), not guessed into a review budget.
      if statuses[path] or not tracked[path] or path == state.selected.path then
        local new_size = size_for("new", path)
        if not consumed[path] or renames[path] or present["new:" .. path] then
          local old_size = consumed[path] and not renames[path] and 0 or size_for("old", oldpath)
          minimum = minimum + old_size + new_size
          -- Guaranteed metadata lower bound; no speculative text is counted.
          minimum = minimum + io.main(function()
            return #vim.json.encode({ path = path, oldpath = oldpath, full_text = true,
              old = { path = oldpath, side = "old", identity = "absent", underlying_identity = "absent", binary = false },
              new = { path = path, side = "new", identity = "absent", underlying_identity = "absent", binary = false } })
          end)
          io.size(minimum)
        end
      end
    end
  end
  local manifest, files, supplied_bytes, encoded_bytes = {}, {}, 0, 0
  for number, path in ipairs(sorted) do
    io.batch(number)
    local include = strategy ~= "focused" or path == state.selected.path or doc_priority(path) < 3
    if include and strategy == "focused" and path ~= state.selected.path then
      include = size_for("old", renames[path] or path) + size_for("new", path) <= (io.optional_capacity or io.max_bytes)
        and regular["old:" .. (renames[path] or path)] and regular["new:" .. path]
    end
    io.unbounded = strategy == "focused" and path == state.selected.path and io.hunk
    -- A rename source may have been re-created as a distinct added file.
    -- Never let rename de-duplication silently hide that supplied version.
    local reused = include and consumed[path] and not renames[path] and version("new", path).present
    if include and (not consumed[path] or renames[path] or reused) then
      local oldpath = renames[path] or path
      local old = reused and { path = path, side = "old", present = false, binary = false, identity = "absent" }
        or version("old", oldpath)
      local new = version("new", path)
      if old.identity ~= new.identity or old.mode ~= new.mode or oldpath ~= path then
        supplied_bytes = supplied_bytes + #(old.bytes or "") + #(new.bytes or "")
        if strategy ~= "focused" then io.size(supplied_bytes) end
        io.pause()
        local status = oldpath ~= path and "R" or not old.present and "A" or not new.present and "D" or "M"
        local item = { path = path, oldpath = oldpath, status = status, git_status = statuses[path],
          old = vim.deepcopy(old), new = vim.deepcopy(new), full_text = true }
        item.kind, item.comparison = state.selected.kind, vim.deepcopy(pair)
        item.file_id = "file-" .. hash({ path, oldpath, item.kind })
        item.old.bytes, item.new.bytes = nil, nil
        if old.binary or new.binary then
          item.binary, item.text_unavailable = true, "binary version (NUL bytes)"
        else
          local a, b = old.bytes or "", new.bytes or ""
          io.main(function()
            if not io.snapshot and not (io.unbounded and io.hunk) then
              item.patch = "--- " .. vim.json.encode(old.present and oldpath or "/dev/null") .. "\n+++ "
                .. vim.json.encode(new.present and path or "/dev/null") .. "\n"
                .. vim.diff(a, b, { result_type = "unified", ctxlen = 3, algorithm = "myers" })
            end
            item.hunks = vim.diff(a, b, { result_type = "indices", algorithm = "myers" })
          end)
          if #(old.lines or {}) == 0 and #(new.lines or {}) == 0 then
            item.text_unavailable = "both versions have no text lines"
          end
        end
        local accepted = strategy ~= "focused" or io.main(function() return io.accept(item, comparison, omitted) end)
        if accepted then manifest[#manifest + 1] = item end
        if strategy ~= "focused" then
          local added_bytes = io.main(function()
            local metadata = vim.deepcopy(item)
            metadata.old.lines, metadata.new.lines = nil, nil
            local size = #vim.json.encode(metadata)
            for _, v in ipairs({ item.old, item.new }) do
              if v.lines then size = size + #vim.json.encode(v) end
            end
            return size
          end)
          encoded_bytes = encoded_bytes + added_bytes
          for _, v in ipairs({ item.old, item.new }) do
            if v.lines then files[#files + 1] = vim.deepcopy(v) end
          end
          io.size(encoded_bytes) -- Lower bound; prompt.build checks ALL overhead.
        end
      end
    end
  end
  local focused
  for _, item in ipairs(manifest) do
    if item.path == state.selected.path and item.oldpath == state.selected.oldpath then focused = item end
  end
  assert(focused, "selected file is no longer changed in the comparison; refresh Diffview")
  for _, side in ipairs(state.detached and {} or { "old", "new" }) do
    local pane, v = state.panes[side], focused[side]
    assert(pane.path == v.path, "displayed pane has the wrong source path")
    if not v.present or v.binary then
      assert(pane.nulled or pane.binary, "absent/binary source pane is not coherent")
    else
      local displayed = pane.lines
      if #v.lines == 0 then displayed = (#displayed == 1 and displayed[1] == "") and {} or displayed end
      -- Neovim decodes DOS line endings when displaying buffers.
      local expected = vim.tbl_map(function(line) return line:gsub("\r$", "") end, v.lines)
      assert(not pane.nulled and not pane.binary and vim.deep_equal(displayed, expected),
        "displayed source does not match required " .. side .. " version; wait for loading or refresh Diffview")
    end
  end
  comparison.manifest = manifest
  return comparison, files, focused, guards
end

local function target_for(state, focused, scope, retained, row)
  if retained then
    assert(retained.path == focused.path and retained.oldpath == focused.oldpath and retained.scope == scope,
      "retained target no longer matches selected file")
    if retained.hunk then
      local found = false
      for _, hunk in ipairs(focused.hunks or {}) do
        if vim.deep_equal(hunk, retained.hunk) then found = true; break end
      end
      assert(found, "retained hunk changed during collection; retry")
    end
    return vim.deepcopy(retained)
  end
  local target = { scope = scope, file_id = focused.file_id, anchors = {}, path = focused.path, oldpath = focused.oldpath }
  local hunk
  if scope == "file" then target.hunks = vim.deepcopy(focused.hunks) end
  if scope == "hunk" then
    assert(not focused.binary, "binary files have no textual hunks")
    local side = state.source == state.windows.old and "old" or "new"
    local offset = side == "old" and 1 or 3
    for _, candidate in ipairs(focused.hunks) do
      local start, count = candidate[offset], candidate[offset + 1]
      if (count > 0 and row >= start and row < start + count) or (count == 0 and row == math.max(1, start)) then
        assert(not hunk, "cursor is ambiguous between adjacent hunks; follow the changed side")
        hunk = candidate
      end
    end
    assert(hunk, "cursor is not on a changed hunk; use file scope or move to the changed side")
    target.hunk = vim.deepcopy(hunk)
  end
  for _, side in ipairs({ "old", "new" }) do
    local v, offset = focused[side], side == "old" and 1 or 3
    local first = hunk and hunk[offset] or 1
    local count = hunk and hunk[offset + 1] or (v.lines and #v.lines or 0)
    if count > 0 then target.anchors[#target.anchors + 1] = {
      path = v.path, side = side, start_line = first, end_line = first + count - 1 } end
  end
  assert(#target.anchors > 0, "selected target has no available text lines")
  return target
end

local function excerpt(item, target, radius)
  local copy, files = vim.deepcopy(item), {}
  if target.scope == "hunk" then
    copy.full_text, copy.patch, copy.hunks = false, nil, { vim.deepcopy(target.hunk) }
    copy.patch_coverage = "Selected hunk only; original-coordinate old/new chunks supply the text"
  end
  for _, side in ipairs({ "old", "new" }) do
    local version = copy[side]
    if version.lines then
      version.line_count = #version.lines
      if target.scope == "hunk" then
        local offset = side == "old" and 1 or 3
        local start, count = target.hunk[offset], target.hunk[offset + 1]
        local first = math.max(1, start - radius + (count == 0 and 1 or 0))
        local last = math.min(#version.lines, start + math.max(1, count) - 1 + radius)
        local chunk = { start_line = first, lines = {} }
        for line = first, last do chunk.lines[#chunk.lines + 1] = version.lines[line] end
        version.chunks = #chunk.lines > 0 and { chunk } or {}
        version.supplied_ranges = #chunk.lines > 0 and { { start_line = first, end_line = last } } or {}
        version.lines = nil
      else
        version.supplied_ranges = #version.lines > 0 and { { start_line = 1, end_line = #version.lines } } or {}
      end
      files[#files + 1] = vim.deepcopy(version)
    end
  end
  return copy, files
end

local function current(win, max_bytes, snapshot)
  -- Explicit review bounds complete panes before the adapter copies them.
  -- Focused/auto can explain a small hunk even when its source file is huge.
  for _, candidate in ipairs(api.nvim_tabpage_list_wins(api.nvim_win_get_tabpage(win))) do
    if candidate == win or vim.wo[candidate].diff then
      local buf = api.nvim_win_get_buf(candidate)
      assert(not max_bytes or api.nvim_buf_get_offset(buf, api.nvim_buf_line_count(buf)) <= max_bytes,
        snapshot and "Review snapshot exceeds review.max_snapshot_bytes; required pane is too large. Nothing was omitted."
          or "Complete prompt exceeds context.max_bytes; required pane is too large. Nothing was omitted.")
    end
  end
  local state, err = require("irrelevant_explainer.diffview").current(win)
  assert(state, err)
  return state
end

local function content(value)
  local copy = vim.deepcopy({ value.cwd, value.files, value.comparison, value.context, value.target })
  for _, file in ipairs(copy[2]) do file.supplied_from = nil end
  for _, file in ipairs(copy[3].manifest) do file.old.supplied_from, file.new.supplied_from = nil, nil end
  return copy
end

local function same_guards(before, after)
  for _, guards in ipairs({ before, after }) do
    for key, guard in pairs(guards) do
      local other = (guards == before and after or before)[key]
      if key:sub(1, 7) ~= "buffer:" then
        if not vim.deep_equal(guard, other) then return false end
      elseif other then
        if guard.bytes ~= other.bytes then return false end
      elseif guard.modified or guard.overlaid then return false end
    end
  end
  return true
end

local function editor_guards(state)
  local result = {}
  local root = uv.fs_realpath(state.cwd) or state.cwd
  for _, buffer in ipairs(state.local_buffers) do
    local name = uv.fs_realpath(buffer.name) or buffer.name
    if name:sub(1, #root + 1) == root .. "/" then
      result["buffer:new:" .. name:sub(#root + 2)] = state.buffers[buffer.id]
    end
  end
  for _, side in ipairs({ "old", "new" }) do
    if state.pair[side].type == "stage" then
      for path, buf in pairs(state.stage_buffers) do result["buffer:" .. side .. ":" .. path] = state.buffers[buf] end
    end
  end
  return result
end

local function capture(state, scope, retained, row, io, requested)
  assert(scope == "file" or scope == "hunk" or scope == "review", "diff scope must be file, hunk or review")
  local hash = io.hash
  local function pass(value, strategy)
    local selected, original_target, target_file_count
    io.optional_capacity, io.unbounded = nil, false
    local function surroundings(candidate, radius)
      local supplied, files = excerpt(original_target, candidate.target, radius)
      candidate.comparison.manifest[1] = supplied
      for index = target_file_count + 1, #candidate.files do files[#files + 1] = candidate.files[index] end
      candidate.files, candidate.context.radius = files, radius
    end
    local function capacity()
      local minimal = vim.deepcopy(selected)
      surroundings(minimal, 0)
      local _, _, bytes = require("irrelevant_explainer.prompt").build(minimal, math.huge, nil, io.prompts)
      io.optional_capacity = io.max_bytes - bytes
    end
    io.accept = function(item, comparison, omitted)
      if item.path == value.selected.path then
        original_target = item
        local target = target_for(value, item, scope, retained, row)
        local radius = io.radius
        while true do
          local supplied, files = excerpt(item, target, radius)
          selected = { mode = "diff", target = target, files = files, comparison = vim.deepcopy(comparison),
            context = { strategy = "focused", radius = radius, requested_radius = io.radius,
              -- Count exclusions instead of serializing an unbounded path list.
              omitted_files = omitted,
              omission_policy = "Only target and affordable changed OpenSpec/ADR/decision/requirements docs supplied. "
                .. "Omitted paths are logical destination entries (changed or loaded candidates); "
                .. "their content was not supplied or inspected for rationale. Rename source text may be supplied on the old side." } }
          selected.comparison.manifest = { supplied }
          local prompt, err = require("irrelevant_explainer.prompt").build(selected, io.max_bytes, nil, io.prompts)
          if prompt then target_file_count = #files; capacity(); break end
          if radius == 0 or scope == "file" then error(err) end
          radius = math.floor(radius / 2)
        end
        return true
      end
      assert(selected, "selected target must be gathered first")
      if item.binary then return false end
      local candidate = vim.deepcopy(selected)
      local supplied, files = excerpt(item, { scope = "file" }, 0)
      candidate.comparison.manifest[#candidate.comparison.manifest + 1] = supplied
      vim.list_extend(candidate.files, files)
      candidate.context.omitted_files = candidate.context.omitted_files - 1
      while not require("irrelevant_explainer.prompt").build(candidate, io.max_bytes, nil, io.prompts) do
        if scope == "file" or candidate.context.radius == 0 then return false end
        surroundings(candidate, math.floor(candidate.context.radius / 2))
      end
      selected = candidate
      capacity()
      return true
    end
    local comparison, files, focused, guards = gather(value, io, strategy)
    if strategy == "review" then
      local target
      if scope == "review" then
        target = { scope = "review", files = {} }
        for _, item in ipairs(comparison.manifest) do
          if not item.text_unavailable then target.files[#target.files + 1] = target_for(value, item, "file") end
        end
        assert(#target.files > 0, "comparison has no eligible textual targets; no review can be generated")
      else target = io.main(function() return target_for(value, focused, scope, retained, row) end) end
      selected = { mode = "diff", files = files, comparison = comparison,
        target = target,
        context = { strategy = "review", radius = io.radius, omitted_files = 0 } }
    end
    io.main(function()
      if io.snapshot then
        io.size(#canonical({ context = vim.json.decode(require("irrelevant_explainer.prompt").context(selected)), target = selected.target }))
      else
        local prompt, err = require("irrelevant_explainer.prompt").build(selected, io.max_bytes, nil, io.prompts)
        assert(prompt, err)
      end
    end)
    return selected, guards
  end
  local strategy = requested == "focused" and "focused" or "review"
  local ok, snapshot, guards = pcall(pass, state, strategy)
  if not ok and requested == "auto" and tostring(snapshot):find("Complete prompt", 1, true) then
    strategy = "focused"
    snapshot, guards = pass(state, strategy)
  elseif not ok then error(snapshot, 0) end
  local function state_now() return freeze(require("irrelevant_explainer.diffview").detached(state)) end
  local again = io.main(state_now)
  io.pause()
  local second, second_guards = pass(again, strategy)
  assert(vim.deep_equal(content(snapshot), content(second)) and same_guards(guards, second_guards),
    "review changed during collection; retry")
  -- Run the final editor guard on the main stack in the SAME turn as delivery,
  -- not before a scheduled coroutine resume. Nonfocused overlays are guarded
  -- too: they can change after their last read in the second pass.
  io.validate = function()
    local latest = editor_guards(state_now())
    for key, guard in pairs(second_guards) do
      if key:sub(1, 7) == "buffer:" then
        local other = latest[key]
        assert(other and other.bytes == guard.bytes or not other and not guard.modified and not guard.overlaid,
          "review changed during collection; retry")
      end
    end
    local previous = editor_guards(again)
    for key, other in pairs(latest) do
      if other.modified and not previous[key] then error("review changed during collection; retry") end
    end
  end
  snapshot.cwd, snapshot.windows, snapshot.source = state.cwd, state.windows, state.source
  snapshot.source_buf = state.panes[state.source == state.windows.old and "old" or "new"].buf
  local context_identity = content(snapshot)
  context_identity[5] = nil -- Target and display/transport provenance are not context identity.
  snapshot.review_fingerprint = hash(context_identity)
  snapshot.fingerprint = hash({ snapshot.review_fingerprint, snapshot.target })
  snapshot.max_bytes = io.max_bytes
  snapshot.snapshot_max_bytes = io.snapshot and io.max_bytes or nil
  snapshot.capture = { state = state, guards = guards, target = vim.deepcopy(snapshot.target), prompts = io.prompts }
  return snapshot
end

function M.collect_async(win, scope, callback, options)
  options = options or {}
  local config = require("irrelevant_explainer").config.context
  local prompts = vim.deepcopy(options.prompts or require("irrelevant_explainer").config.prompts)
  local max_bytes, strategy, radius = options.max_bytes or config.max_bytes, options.diff or config.diff, options.radius or config.radius
  if scope == "review" then strategy = "review" end
  local snapshot_max_bytes = scope == "review"
    and (options.snapshot_max_bytes or require("irrelevant_explainer").config.review.max_snapshot_bytes) or nil
  max_bytes = snapshot_max_bytes or max_bytes
  local ok, state, row = pcall(function()
    assert(type(max_bytes) == "number" and max_bytes > 0 and max_bytes < math.huge and max_bytes % 1 == 0,
      "invalid context.max_bytes")
    assert(vim.tbl_contains({ "auto", "review", "focused" }, strategy), "invalid context.diff")
    assert(type(radius) == "number" and radius >= 0 and radius < math.huge and radius % 1 == 0, "invalid context.radius")
    win = (not win or win == 0) and api.nvim_get_current_win() or win
    local value = options.state and require("irrelevant_explainer.diffview").detached(options.state)
      or current(win, strategy == "review" and max_bytes or nil, snapshot_max_bytes ~= nil)
    return freeze(value), options.state and 1 or api.nvim_win_get_cursor(value.source)[1]
  end)
  local job = run(function(io)
    assert(ok, state)
    io.max_bytes, io.radius, io.auto, io.hunk = max_bytes, radius, strategy == "auto", scope == "hunk"
    io.prompts = prompts
    io.snapshot = snapshot_max_bytes ~= nil
    return capture(state, scope, options.target, row, io, strategy)
  end, callback, max_bytes)
  -- Reuse the captured view for pending UI/ownership without collecting twice.
  job.state = ok and state or nil
  return job
end

function M.fresh_async(snapshot, callback)
  snapshot = snapshot.provenance or snapshot
  return M.collect_async(snapshot.source, snapshot.target.scope, function(current)
    callback(current ~= nil and vim.deep_equal(content(current), content(snapshot))
      and same_guards(snapshot.capture.guards, current.capture.guards))
  end, { state = snapshot.capture.state, target = snapshot.capture.target, max_bytes = snapshot.max_bytes,
    prompts = snapshot.capture.prompts,
    snapshot_max_bytes = snapshot.snapshot_max_bytes,
    diff = snapshot.context and snapshot.context.strategy or "review",
    radius = snapshot.context and (snapshot.context.requested_radius or snapshot.context.radius) or 20 })
end

-- Returning to a file may recreate clean revision/working buffers. Recollect
-- under the original coverage, keeping strict race guards during this read,
-- but compare content rather than the old display's buffer/window identities.
function M.restore_async(snapshot, source, callback)
  return M.fresh_async(snapshot, function(fresh)
    if not fresh then callback(nil); return end
    local ok, state = pcall(current, source)
    if not ok or snapshot.target.scope ~= "review" and
      (state.selected.path ~= snapshot.target.path or state.selected.oldpath ~= snapshot.target.oldpath) then
      callback(nil); return
    end
    local rebound = vim.deepcopy(snapshot)
    rebound.windows, rebound.source = state.windows, state.source
    rebound.source_buf = state.panes[state.source == state.windows.old and "old" or "new"].buf
    -- The content check is detached; attachment additionally verifies that the
    -- newly displayed revision buffers really contain the retained versions.
    for _, item in ipairs(snapshot.comparison.manifest) do
      if item.path == state.selected.path and item.oldpath == state.selected.oldpath then
        for _, side in ipairs({ "old", "new" }) do
          local version, pane = item[side], state.panes[side]
          if version.lines then
            local expected = vim.tbl_map(function(line) return line:gsub("\r$", "") end, version.lines)
            if #expected == 0 then expected = { "" } end
            if not vim.deep_equal(expected, pane.lines) then callback(nil); return end
          elseif not version.present or version.binary then
            if not pane.nulled and not pane.binary then callback(nil); return end
          elseif version.chunks then
            local captured = snapshot.capture.state.panes[side]
            if not captured or not vim.deep_equal(captured.lines, pane.lines) then callback(nil); return end
          end
        end
      end
    end
    rebound.capture.state, rebound.capture.target = state, vim.deepcopy(rebound.target)
    callback(rebound)
  end)
end

-- Offline compatibility helpers only. Sessions never use these event-loop
-- waiting wrappers; they own and cancel collect_async/fresh_async jobs.
local function offline(start)
  local done, result, err = false
  local job = start(function(value, failure) result, err, done = value, failure, true end)
  if not vim.wait(120000, function() return done end, 5) then
    job.cancel(); return nil, "Diff collection timed out"
  end
  return result, err
end
function M.collect(win, scope, options)
  return offline(function(callback) return M.collect_async(win, scope, callback, options) end)
end
function M.fresh(snapshot)
  local ok, result = pcall(function()
    if snapshot.mode ~= "diff" then return false end
    return offline(function(callback) return M.fresh_async(snapshot, callback) end)
  end)
  return ok and result == true
end

return M
