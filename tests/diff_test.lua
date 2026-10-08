local diff, adapter = require("explainr.diff"), require("explainr.diffview")
local api = vim.api

local function repo(run)
  local root = vim.fn.tempname() .. " spaces;$'"
  vim.fn.mkdir(root, "p")
  local buffers, windows, original = {}, {}, adapter.current
  local original_detached = adapter.detached
  adapter.detached = function(captured)
    local now = assert(adapter.current(captured.source), "closed source")
    assert(now.cwd == captured.cwd and vim.deep_equal(now.pair, captured.pair)
      and now.selected.kind == captured.selected.kind and vim.deep_equal(now.path_args, captured.path_args)
      and now.show_untracked == captured.show_untracked, "Diffview comparison changed during collection")
    local value = vim.deepcopy(captured)
    value.stage_buffers, value.detached = now.stage_buffers, true
    return value
  end
  local function git(...)
    local result = vim.system(vim.list_extend({ "git" }, { ... }), { cwd = root }):wait()
    assert(result.code == 0, result.stderr)
    return vim.trim(result.stdout)
  end
  local function write(path, bytes)
    vim.fn.mkdir(vim.fn.fnamemodify(root .. "/" .. path, ":h"), "p")
    local fd = assert(vim.uv.fs_open(root .. "/" .. path, "w", 420))
    assert(vim.uv.fs_write(fd, bytes, 0)); vim.uv.fs_close(fd)
  end
  local function buf(path, text)
    local id = api.nvim_create_buf(false, false)
    buffers[#buffers + 1] = id
    if path then api.nvim_buf_set_name(id, root .. "/" .. path) end
    api.nvim_buf_set_lines(id, 0, -1, false, vim.split(text:gsub("\n$", ""), "\n", { plain = true }))
    vim.bo[id].endofline = text:sub(-1) == "\n"
    vim.bo[id].modified = false
    return id
  end
  local state
  local function display(pair, path, before, after, oldpath)
    local old, new = buf(nil, before or ""), buf(pair.new.type == "local" and path or nil, after or "")
    for _, id in ipairs({ old, new }) do
      vim.cmd("botright vsplit")
      local win = api.nvim_get_current_win()
      api.nvim_win_set_buf(win, id)
      windows[#windows + 1] = win
    end
    state = { cwd = root, pair = pair, selected = { path = path, oldpath = oldpath or path, status = "M", kind = "working" },
      path_args = {}, entries = {}, show_untracked = true, stage_buffers = {},
      windows = { old = windows[#windows - 1], new = windows[#windows] }, source = windows[#windows] }
    state.entries = { vim.deepcopy(state.selected) }
    if pair.old.type == "stage" and before then state.stage_buffers[oldpath or path] = old end
    if pair.new.type == "stage" and after then state.stage_buffers[path] = new end
    adapter.current = function(win)
      if not api.nvim_win_is_valid(state.source) then return nil, "closed source" end
      local result = vim.deepcopy(state)
      if win and win ~= 0 then result.source = win end
      result.panes = {}
      for _, side in ipairs({ "old", "new" }) do
        local id = api.nvim_win_get_buf(result.windows[side])
        result.panes[side] = { buf = id, path = side == "old" and result.selected.oldpath or result.selected.path,
          nulled = (side == "old" and before == nil) or (side == "new" and after == nil), binary = false,
          lines = api.nvim_buf_get_lines(id, 0, -1, false), tick = api.nvim_buf_get_changedtick(id) }
      end
      return result
    end
    return state, old, new
  end
  local function commit()
    git("add", "--all"); git("commit", "-qm", "fixture")
    return git("rev-parse", "HEAD")
  end
  local function collect(scope, win)
    local s, err = diff.collect(win or 0, scope or "file")
    assert(s, err)
    return s
  end
  git("init", "-q"); git("config", "user.name", "Offline fixture"); git("config", "user.email", "offline@example.invalid")
  local ok, err = xpcall(function() run({ root = root, git = git, write = write, commit = commit,
    display = display, collect = collect, buf = buf }) end, debug.traceback)
  adapter.current = original
  adapter.detached = original_detached
  for _, win in ipairs(windows) do if api.nvim_win_is_valid(win) then api.nvim_win_close(win, true) end end
  for _, id in ipairs(buffers) do if api.nvim_buf_is_valid(id) then api.nvim_buf_delete(id, { force = true }) end end
  vim.fn.delete(root, "rf")
  assert(ok, err)
end

local function rev(commit) return { type = "commit", commit = commit, track_head = false } end
local function manifest(s, path)
  for _, item in ipairs(s.comparison.manifest) do if item.path == path then return item end end
end
local function file(s, path, side)
  for _, item in ipairs(s.files) do if item.path == path and item.side == side then return item end end
end

T.test("diff two commits exclude local edits and include full cross-file spec ADR and tests", function()
  repo(function(r)
    r.write("policy.lua", "owner\nunchanged\n")
    r.write("openspec/spec.md", "Only owners cancel\n")
    r.write("doc/adr.rst", "Rationale stays outside the changed paragraph\nold rule\n")
    r.write("tests/policy.txt", "expect owner\n")
    local a = r.commit()
    r.write("policy.lua", "owner or editor\nunchanged\n")
    r.write("openspec/spec.md", "Only owners cancel (strict)\n")
    r.write("doc/adr.rst", "Rationale stays outside the changed paragraph\nnew rule\n")
    r.write("tests/policy.txt", "expect owner, reject editor\n")
    local b = r.commit()
    r.write("policy.lua", "UNRELATED local\n"); r.write("unrelated.txt", "ignore\n")
    r.display({ old = rev(a), new = rev(b) }, "policy.lua", "owner\nunchanged\n", "owner or editor\nunchanged\n")
    local s = r.collect()
    T.eq(4, #s.comparison.manifest); T.eq(8, #s.files)
    T.eq({ "owner or editor", "unchanged" }, file(s, "policy.lua", "new").lines)
    T.eq({ { 1, 1, 1, 1 } }, s.target.hunks)
    T.eq(2, s.target.anchors[2].end_line) -- Relevant unchanged sections remain valid targets.
    T.eq("Rationale stays outside the changed paragraph", file(s, "doc/adr.rst", "old").lines[1])
    for _, item in ipairs(s.comparison.manifest) do assert(item.patch and item.full_text) end
    T.eq(nil, manifest(s, "unrelated.txt")); T.eq(true, diff.fresh(s))
    T.eq(s.fingerprint, r.collect().fingerprint)
    local validated, err = require("explainr.model").validate({ version = 1, notes = { {
      summary = "Permission mismatch", detail = "Editors contradict the owner-only requirement.", intent_basis = "documented",
      anchors = { { path = "policy.lua", side = "new", start_line = 1, end_line = 1 } },
      evidence = { { path = "openspec/spec.md", side = "new", start_line = 1, end_line = 1 },
        { path = "doc/adr.rst", side = "old", start_line = 1, end_line = 1 } } } } }, s)
    assert(validated, err)
    api.nvim_win_set_cursor(s.source, { 1, 0 })
    local h = r.collect("hunk")
    api.nvim_win_set_cursor(s.source, { 2, 0 })
    T.eq(true, diff.fresh(h)) -- Cursor movement never retargets captured hunks.
    T.eq({ 1, 1, 1, 1 }, h.target.hunk)
    T.eq(nil, h.target.hunks)
    T.eq(s.review_fingerprint, h.review_fingerprint)
    assert(s.fingerprint ~= h.fingerprint)
    local corrupt = vim.deepcopy(s); corrupt.files[1].lines[1] = "tampered"
    T.eq(false, diff.fresh(corrupt))
    r.write("policy.lua", "more unrelated local\n"); T.eq(true, diff.fresh(s))
  end)
end)

T.test("diff working comparison overlays unsaved focused and previously unchanged nonfocused buffers", function()
  repo(function(r)
    r.write("code.lua", "base\n"); r.write("doc.md", "rationale\n"); r.write("quiet.txt", "same\n")
    r.commit(); r.write("code.lua", "working\n")
    local state, _, new = r.display({ old = { type = "stage", stage = 0 }, new = { type = "local" } },
      "code.lua", "base\n", "working\n")
    api.nvim_buf_set_lines(new, 0, -1, false, { "unsaved" })
    local other = r.buf("doc.md", "rationale\n")
    api.nvim_buf_set_lines(other, 0, -1, false, { "unsaved rationale" })
    T.eq(vim.uv.fs_realpath(r.root .. "/code.lua"), vim.uv.fs_realpath(api.nvim_buf_get_name(new)))
    T.eq(true, vim.bo[new].modified)
    local s = r.collect()
    T.eq({ "unsaved" }, file(s, "code.lua", "new").lines)
    assert(manifest(s, "code.lua").patch:find("+unsaved", 1, true))
    T.eq({ "unsaved rationale" }, file(s, "doc.md", "new").lines)
    T.eq(true, file(s, "doc.md", "new").overlaid)
    vim.bo[other].modified = false -- A cleared flag must not hide actual loaded bytes.
    s = r.collect(); T.eq({ "unsaved rationale" }, file(s, "doc.md", "new").lines)
    T.eq(nil, manifest(s, "quiet.txt")); T.eq(true, diff.fresh(s))
    api.nvim_buf_set_lines(other, 0, -1, false, { "later rationale" }); T.eq(false, diff.fresh(s))
    s = r.collect(); r.write("doc.md", "disk changed underneath unsaved\n"); T.eq(false, diff.fresh(s))
    s = r.collect(); r.write("quiet.txt", "newly changed nonfocused\n"); T.eq(false, diff.fresh(s))
    s = r.collect(); r.write("new doc.md", "new untracked decision\n"); T.eq(false, diff.fresh(s))
    s = r.collect(); r.git("add", "--", "quiet.txt"); T.eq(false, diff.fresh(s))
    s = r.collect(); state.selected.path = "doc.md"; state.selected.oldpath = "doc.md"
    T.eq(true, diff.fresh(s)) -- Navigation does not change the captured target.
  end)
end)

T.test("diff staged identities exclude working changes and overlay editable stage buffers", function()
  repo(function(r)
    r.write("code.lua", "base\n"); r.write("doc.md", "rationale\n"); local a = r.commit()
    r.write("code.lua", "staged\n"); r.git("add", "--", "code.lua"); r.write("code.lua", "working only\n")
    local state, _, new = r.display({ old = rev(a), new = { type = "stage", stage = 0 } }, "code.lua", "base\n", "staged\n")
    local s = r.collect()
    T.eq("stage", s.comparison.identities.new.type)
    T.eq({ "staged" }, file(s, "code.lua", "new").lines)
    r.write("code.lua", "different working only\n"); T.eq(true, diff.fresh(s))
    api.nvim_buf_set_lines(new, 0, -1, false, { "unsaved stage" })
    T.eq(false, diff.fresh(s)); s = r.collect()
    assert(manifest(s, "code.lua").patch:find("+unsaved stage", 1, true))
    local stage_doc = r.buf(nil, "rationale\n"); state.stage_buffers["doc.md"] = stage_doc
    api.nvim_buf_set_lines(stage_doc, 0, -1, false, { "unsaved stage rationale" })
    s = r.collect(); T.eq({ "unsaved stage rationale" }, file(s, "doc.md", "new").lines)
    r.write("doc.md", "index update\n"); r.git("add", "--", "doc.md"); T.eq(false, diff.fresh(s))
  end)
end)

T.test("diff rename add delete empty binary and missing end-of-line preserve version identities", function()
  repo(function(r)
    r.write("old name.lua", "rename me\n"); r.write("deleted.lua", "deleted code\n")
    r.write("code.lua", "before\n"); r.write("binary.bin", "a\0b")
    local a = r.commit()
    r.git("mv", "--", "old name.lua", "new name.lua"); r.git("rm", "--", "deleted.lua")
    r.write("added.lua", "new code\n"); r.write("empty.txt", ""); r.write("binary.bin", "c\0d")
    r.write("code.lua", "after without newline"); local b = r.commit()
    r.display({ old = rev(a), new = rev(b) }, "code.lua", "before\n", "after without newline")
    local s = r.collect()
    local rename = assert(manifest(s, "new name.lua"))
    T.eq("R", rename.status); T.eq("old name.lua", rename.old.path); T.eq("new name.lua", rename.new.path)
    T.eq(false, manifest(s, "added.lua").old.present)
    T.eq(false, manifest(s, "deleted.lua").new.present)
    T.eq(true, manifest(s, "empty.txt").new.present); T.eq({}, manifest(s, "empty.txt").new.lines)
    T.eq(true, manifest(s, "binary.bin").binary); T.eq(nil, file(s, "binary.bin", "new"))
    assert(manifest(s, "code.lua").patch:find("No newline", 1, true))
    T.eq(false, file(s, "code.lua", "new").endofline)
  end)
end)

T.test("diff deletion-only hunk and new-file anchors never cite absent versions", function()
  repo(function(r)
    r.write("deleted.lua", "delete\nthis\n"); local a = r.commit()
    r.git("rm", "--", "deleted.lua"); r.write("added.lua", "added\n"); local b = r.commit()
    local state = r.display({ old = rev(a), new = rev(b) }, "deleted.lua", "delete\nthis\n", nil)
    local s = r.collect("hunk", state.windows.old)
    T.eq({ { path = "deleted.lua", side = "old", start_line = 1, end_line = 2 } }, s.target.anchors)
    T.eq(state.windows.old, s.source)
    r.display({ old = rev(a), new = rev(b) }, "added.lua", nil, "added\n")
    s = r.collect("hunk")
    T.eq({ { path = "added.lua", side = "new", start_line = 1, end_line = 1 } }, s.target.anchors)
  end)
end)

T.test("diff explicit path filter preserves selected comparison without implicit review widening", function()
  repo(function(r)
    r.write("focus.lua", "a\n"); r.write("hidden.md", "a\n"); r.commit()
    r.write("focus.lua", "b\n"); r.write("hidden.md", "b\n")
    local state = r.display({ old = { type = "stage", stage = 0 }, new = { type = "local" } }, "focus.lua", "a\n", "b\n")
    state.path_args = { "focus.lua" }
    local s = r.collect(); T.eq(1, #s.comparison.manifest)
    T.eq({ "focus.lua" }, s.comparison.selection.path_args)
    r.write("hidden.md", "out of selected scope\n"); T.eq(true, diff.fresh(s))
  end)
end)

T.test("diff rename source recreation is retained and collection races fail coherently", function()
  repo(function(r)
    r.write("old.lua", "rename source\nunchanged\n"); r.write("focus.lua", "a\n"); local a = r.commit()
    r.git("mv", "--", "old.lua", "new.lua")
    r.write("old.lua", "entirely unrelated replacement\n"); r.write("focus.lua", "b\n"); local b = r.commit()
    local state = r.display({ old = rev(a), new = rev(b) }, "focus.lua", "a\n", "b\n")
    -- Preserve the explicit rename identity already displayed by the view,
    -- even if a later source recreation makes Git's -M report M + A.
    state.entries[#state.entries + 1] = { path = "new.lua", oldpath = "old.lua", status = "R", kind = "working" }
    local s = r.collect()
    T.eq(3, #s.comparison.manifest)
    T.eq("R", manifest(s, "new.lua").status); T.eq("A", manifest(s, "old.lua").status)
    T.eq(false, manifest(s, "old.lua").old.present)
    T.eq({ "entirely unrelated replacement" }, file(s, "old.lua", "new").lines)
    local original, calls = adapter.current, 0
    adapter.current = function(win)
      calls = calls + 1
      local state = original(win)
      if calls == 3 then state.path_args = { "switched comparison filter" } end
      return state
    end
    local collected, message = diff.collect(0, "file")
    adapter.current = original
    T.eq(nil, collected); assert(message:find("changed during collection", 1, true), message)
    T.eq(true, diff.fresh(s))
    api.nvim_win_close(s.source, true); T.eq(false, diff.fresh(s))
  end)
end)

T.test("diff missing required blob and incoherent panes fail rather than omit text", function()
  repo(function(r)
    r.write("code.lua", "base\n"); local a = r.commit(); r.write("code.lua", "new\n"); local b = r.commit()
    local _, _, new = r.display({ old = rev(a), new = rev(b) }, "code.lua", "base\n", "new\n")
    api.nvim_buf_set_lines(new, 0, -1, false, { "wrong loaded revision" })
    local s, err = diff.collect(0, "file")
    T.eq(nil, s); assert(err:find("displayed source", 1, true), err)
    api.nvim_buf_set_lines(new, 0, -1, false, { "new" })
    local system = vim.system
    vim.system = function(cmd, opts, callback)
      if vim.tbl_contains(cmd, "cat-file") then
        vim.schedule(function() callback({ code = 1, stderr = "fixture required blob missing" }) end)
        return { kill = function() end }
      end
      return system(cmd, opts, callback)
    end
    local ok, result, message = pcall(diff.collect, 0, "file")
    vim.system = system
    assert(ok); T.eq(nil, result); assert(message:find("required blob missing", 1, true), message)
  end)
end)

T.test("async Git startup and polling yield; cancellation and late checks never launch or render", function()
  repo(function(r)
    r.write("focus.lua", "old\nunchanged\n"); local a = r.commit()
    r.write("focus.lua", "new\nunchanged\n"); local b = r.commit()
    local state = r.display({ old = rev(a), new = rev(b) }, "focus.lua", "old\nunchanged\n", "new\nunchanged\n")
    local plugin, sessions, agent = require("explainr"), require("explainr.session"), require("explainr.agent")
    plugin.close(); plugin.setup()
    local system, old_run, old_notify = vim.system, agent.run, vim.notify
    local held, gates, kills, launches, heartbeats = true, {}, 0, {}, 0
    local timer = vim.uv.new_timer()
    timer:start(5, 5, vim.schedule_wrap(function() heartbeats = heartbeats + 1 end))
    vim.notify = function() end
    vim.system = function(command, opts, callback)
      assert(callback, "production collection used a blocking process")
      local process = system(command, opts, function(result)
        if held and vim.tbl_contains(command, "--name-status") then
          gates[#gates + 1] = function() callback(result) end
        else callback(result) end
      end)
      return { kill = function(_, signal) kills = kills + 1; process:kill(signal) end,
        wait = function() error("runtime blocking wait") end }
    end
    agent.run = function(_, _, _, callback)
      launches[#launches + 1] = callback
      return { cancel = function() end }
    end
    local function gate()
      assert(vim.wait(3000, function() return #gates > 0 end), "Git never reached delayed completion")
    end
    local function release()
      held = false
      local pending = gates; gates = {}
      for _, callback in ipairs(pending) do callback() end
    end
    local ok, err = xpcall(function()
      api.nvim_win_set_cursor(state.source, { 1, 0 })
      local pending = plugin.diff("hunk")
      T.eq(pending, sessions.current()); T.eq(nil, pending.snapshot)
      assert(api.nvim_win_is_valid(pending.pane.win)); assert(pending.pane.status:find("Pending"))
      gate()
      assert(vim.wait(1000, function() return heartbeats >= 8 end), "startup blocked editor heartbeat")
      plugin.cancel(); assert(kills > 0); T.eq(nil, pending.collection)
      release(); vim.wait(80)
      T.eq(0, #launches); T.eq(nil, pending.pane.result); assert(pending.pane.status:find("Cancelled"))

      held = true
      local collecting = plugin.refresh(); gate()
      api.nvim_win_set_cursor(state.source, { 2, 0 }) -- Not a changed line.
      release()
      assert(vim.wait(3000, function() return #launches == 1 end), collecting.pane.status)
      T.eq({ 1, 1, 1, 1 }, collecting.snapshot.target.hunk)
      T.eq(1, collecting.snapshot.target.anchors[1].start_line)

      held = true
      assert(vim.wait(2500, function() return collecting.checking ~= nil end), "poll never started")
      gate()
      local before, job = heartbeats, collecting.checking
      -- More than one polling interval cannot start another check/job.
      assert(vim.wait(1300, function() return heartbeats >= before + 220 end), "poll blocked editor heartbeat")
      T.eq(job, collecting.checking); T.eq(1, #gates)
      launches[1]('{"version":1,"notes":[]}')
      T.eq(nil, collecting.pane.result)
      plugin.cancel(); release(); vim.wait(100)
      T.eq(nil, collecting.pane.result); assert(collecting.pane.status:find("Cancelled"))

      -- Another explicit target queues; only Refresh/Close cancel collection.
      api.nvim_win_set_cursor(state.source, { 1, 0 }); held = true
      local old = plugin.refresh(); gate()
      local old_job, generation = old.collection, old.generation
      local replacement = plugin.diff("file")
      T.eq(old, replacement); T.eq(generation, replacement.generation)
      T.eq(old_job, replacement.collection); T.eq(1, #replacement.queue)
      plugin.refresh(); assert(replacement.generation > generation)
      assert(old_job ~= replacement.collection); T.eq(0, #replacement.queue); gate()
      plugin.close(); T.eq(true, replacement.closed)
      release(); vim.wait(100)
      T.eq(1, #launches); T.eq(nil, sessions.current())
    end, debug.traceback)
    plugin.close(); release(); timer:stop(); timer:close(); vim.wait(30)
    vim.system, agent.run, vim.notify = system, old_run, old_notify
    assert(ok, err)
  end)
end)

T.test("async collection rejects oversized required files before reading blob or diffing text", function()
  repo(function(r)
    r.write("focus.lua", "old\n"); r.write("huge.txt", "small\n"); local a = r.commit()
    r.write("focus.lua", "new\n"); r.write("huge.txt", string.rep("x", 20000)); local b = r.commit()
    local state = r.display({ old = rev(a), new = rev(b) }, "focus.lua", "old\n", "new\n")
    local system, reads = vim.system, 0
    vim.system = function(command, opts, callback)
      if vim.tbl_contains(command, "blob") then reads = reads + 1 end
      return system(command, opts, callback)
    end
    local done, result, message = false
    diff.collect_async(state.source, "file", function(value, err) result, message, done = value, err, true end,
      { max_bytes = 10000, diff = "review" })
    local finished = vim.wait(3000, function() return done end)
    vim.system = system
    assert(finished); T.eq(nil, result); assert(message:find("Complete prompt", 1, true), message)
    T.eq(3, reads) -- focused old/new and huge old only; huge new never read.

    r.git("reset", "--hard", a)
    r.write("focus.lua", "new\n"); r.write("huge.txt", string.rep("x", 20000))
    state = r.display({ old = { type = "stage", stage = 0 }, new = { type = "local" } },
      "focus.lua", "old\n", "new\n")
    local fs_read, largest = vim.uv.fs_read, 0
    vim.uv.fs_read = function(fd, size, ...)
      largest = math.max(largest, size)
      return fs_read(fd, size, ...)
    end
    done = false
    diff.collect_async(state.source, "file", function(value, err) result, message, done = value, err, true end,
      { max_bytes = 10000, diff = "review" })
    finished = vim.wait(3000, function() return done end)
    vim.uv.fs_read = fs_read
    assert(finished); T.eq(nil, result); assert(message:find("Complete prompt", 1, true), message)
    assert(largest < 10000, "oversized filesystem content was read")
  end)
end)

T.test("final collection guard catches nonfocused overlays edited after the second read", function()
  repo(function(r)
    r.write("focus.lua", "old\n"); r.write("doc.md", "rationale\n"); r.commit()
    r.write("focus.lua", "new\n")
    r.display({ old = { type = "stage", stage = 0 }, new = { type = "local" } }, "focus.lua", "old\n", "new\n")
    local document = r.buf("doc.md", "rationale\n")
    local original, calls = adapter.current, 0
    adapter.current = function(win)
      calls = calls + 1
      local state = original(win)
      if calls == 3 then api.nvim_buf_set_lines(document, 0, -1, false, { "late rationale" }) end
      return state
    end
    local result, err = diff.collect(0, "file")
    adapter.current = original
    T.eq(nil, result); assert(err:find("changed during collection", 1, true), err)
  end)
end)

T.test("working review skips large unchanged files but retains new saved and unsaved changes", function()
  repo(function(r)
    r.write("focus.lua", "old\n"); r.write("quiet.lock", string.rep("x", 500000))
    r.write("other.lua", "same\n"); r.commit(); r.write("focus.lua", "new\n")
    r.display({ old = { type = "stage", stage = 0 }, new = { type = "local" } }, "focus.lua", "old\n", "new\n")
    local snapshot = r.collect()
    T.eq(1, #snapshot.comparison.manifest); T.eq(nil, manifest(snapshot, "quiet.lock"))
    r.write("other.lua", "saved change\n")
    T.eq(false, diff.fresh(snapshot))
    snapshot = r.collect(); T.eq({ "saved change" }, file(snapshot, "other.lua", "new").lines)
    local loaded = r.buf("quiet.lock", "unsaved\n")
    -- The underlying giant version is now required; fail before inference,
    -- rather than treating an unsaved overlay as an unchanged file.
    local result, err = diff.collect(0, "file", { diff = "review" })
    T.eq(nil, result); assert(err:find("Complete prompt", 1, true), err)
    api.nvim_buf_delete(loaded, { force = true })
  end)
end)

T.test("working untracked policy follows explicit disable and asynchronous Git config", function()
  repo(function(r)
    r.write("focus.lua", "old\n"); r.commit(); r.write("focus.lua", "new\n")
    r.write("decision.md", "new requirement\n")
    local state = r.display({ old = { type = "stage", stage = 0 }, new = { type = "local" } },
      "focus.lua", "old\n", "new\n")
    local snapshot = r.collect()
    T.eq(true, snapshot.comparison.selection.show_untracked); assert(manifest(snapshot, "decision.md"))
    r.git("config", "status.showUntrackedFiles", "no")
    T.eq(false, diff.fresh(snapshot))
    snapshot = r.collect()
    T.eq(false, snapshot.comparison.selection.show_untracked); T.eq(nil, manifest(snapshot, "decision.md"))
    r.git("config", "status.showUntrackedFiles", "false")
    snapshot = r.collect()
    T.eq(true, snapshot.comparison.selection.show_untracked); assert(manifest(snapshot, "decision.md"))
    state.show_untracked = false
    snapshot = r.collect()
    T.eq(false, snapshot.comparison.selection.show_untracked); T.eq(nil, manifest(snapshot, "decision.md"))
  end)
end)

T.test("collection keeps native encoding and editor APIs on the main Lua stack", function()
  repo(function(r)
    r.write("focus.lua", "old\n"); r.commit(); r.write("focus.lua", "new\n")
    r.display({ old = { type = "stage", stage = 0 }, new = { type = "local" } }, "focus.lua", "old\n", "new\n")
    local encode, close = vim.json.encode, vim.uv.fs_close
    local originals = {}
    for _, name in ipairs({ "nvim_list_bufs", "nvim_buf_get_name", "nvim_get_option_value", "nvim_buf_get_lines" }) do
      originals[name] = api[name]
      api[name] = function(...)
        assert(coroutine.running() == nil, name .. " ran on the collection coroutine")
        return originals[name](...)
      end
    end
    vim.json.encode = function(...)
      assert(coroutine.running() == nil, "native encoding ran on the collection coroutine")
      return encode(...)
    end
    vim.uv.fs_close = function(...)
      assert(coroutine.running() == nil, "native close callback created on the collection coroutine")
      return close(...)
    end
    local ok, snapshot = pcall(r.collect)
    for name, original in pairs(originals) do api[name] = original end
    vim.json.encode, vim.uv.fs_close = encode, close
    assert(ok, snapshot)
    T.eq({ "new" }, file(snapshot, "focus.lua", "new").lines)
  end)
end)

T.test("cancelling a pending filesystem read closes its descriptor only after completion", function()
  repo(function(r)
    r.write("focus.lua", "old\n"); r.commit(); r.write("focus.lua", "new\n")
    r.display({ old = { type = "stage", stage = 0 }, new = { type = "local" } }, "focus.lua", "old\n", "new\n")
    local uv = vim.uv
    local read, close = uv.fs_read, uv.fs_close
    local release, descriptor, job
    local closes, callbacks, closed = 0, 0, false
    uv.fs_read = function(fd, size, offset, callback)
      return read(fd, size, offset, function(err, bytes)
        descriptor = fd
        release = function() callback(err, bytes) end
      end)
    end
    uv.fs_close = function(fd, callback)
      if fd ~= descriptor then return close(fd, callback) end
      closes = closes + 1
      return close(fd, function(...)
        closed = true
        callback(...)
      end)
    end
    local ok, err = xpcall(function()
      job = diff.collect_async(0, "file", function() callbacks = callbacks + 1 end, { diff = "focused" })
      assert(vim.wait(3000, function() return release ~= nil end), "collection never reached filesystem read")
      job.cancel()
      T.eq(0, closes) -- A premature close could let another job reuse the fd.
      release(); release = nil
      assert(vim.wait(1000, function() return closed end), "cancelled read leaked its descriptor")
      job.cancel(); vim.wait(30)
      T.eq(1, closes); T.eq(0, callbacks)
    end, debug.traceback)
    if job then job.cancel() end
    if release then release() end
    uv.fs_read, uv.fs_close = read, close
    assert(ok, err)
  end)
end)

T.test("auto keeps affordable review and exact serialized UTF-8 boundary", function()
  repo(function(r)
    r.write("focus.lua", "old é中\n"); r.commit(); r.write("focus.lua", "new é中\n")
    local state = r.display({ old = { type = "stage", stage = 0 }, new = { type = "local" } },
      "focus.lua", "old é中\n", "new é中\n")
    local review = assert(diff.collect(state.source, "hunk", { diff = "review" }))
    local prompt = require("explainr.prompt")
    local text, _, bytes = prompt.build(review, 100000)
    assert(#text > vim.fn.strchars(text))
    local auto = assert(diff.collect(state.source, "hunk", { diff = "auto", max_bytes = bytes }))
    T.eq("review", auto.context.strategy); T.eq(review.files, auto.files)
    T.eq(review.fingerprint, auto.fingerprint); T.eq(true, diff.fresh(auto))
    T.eq(text, assert(prompt.build(auto, bytes)))
    local result, err = diff.collect(state.source, "hunk", { diff = "review", max_bytes = bytes - 1 })
    T.eq(nil, result); assert(err:find("Nothing was omitted", 1, true), err)
  end)
end)

T.test("many unrelated changes fail review but auto preflights before reading their blobs", function()
  repo(function(r)
    r.write("focus.lua", "old\n")
    local directory = "src/" .. string.rep("long-directory-", 12) .. "/"
    local omitted_paths = {}
    for index = 1, 60 do
      omitted_paths[index] = directory .. string.format("unrelated%03d.lua", index)
      r.write(omitted_paths[index], "old\n")
    end
    assert(#vim.json.encode(omitted_paths) > 10000) -- Even listing exclusions cannot fit.
    local a = r.commit(); r.write("focus.lua", "new\n")
    for _, path in ipairs(omitted_paths) do r.write(path, "new\n") end
    local b = r.commit()
    local state = r.display({ old = rev(a), new = rev(b) }, "focus.lua", "old\n", "new\n")
    local result, err = diff.collect(state.source, "hunk", { diff = "review", max_bytes = 10000 })
    T.eq(nil, result); assert(err:find("Complete prompt", 1, true), err)
    local system, reads = vim.system, 0
    vim.system = function(command, options, callback)
      if vim.tbl_contains(command, "blob") then reads = reads + 1 end
      return system(command, options, callback)
    end
    local ok, snapshot, message = pcall(diff.collect, state.source, "hunk", { diff = "auto", max_bytes = 10000 })
    vim.system = system
    assert(ok and snapshot, message or snapshot)
    T.eq(4, reads) -- Only target old/new, twice for coherence.
    T.eq("focused", snapshot.context.strategy); T.eq(60, snapshot.context.omitted_files)
    local request = assert(require("explainr.prompt").build(snapshot, snapshot.max_bytes))
    assert(not request:find(directory, 1, true))
    T.eq(snapshot.fingerprint, assert(diff.collect(state.source, "hunk", { diff = "auto", max_bytes = 10000 })).fingerprint)
    T.eq(true, diff.fresh(snapshot))
  end)
end)

T.test("auto skips huge unrelated and oversized optional docs but preserves affordable OpenSpec ADR rationale", function()
  repo(function(r)
    r.write("focus.lua", "owner\n"); r.write("huge.lua", "small\n")
    r.write("openspec/spec.md", "Only owners cancel\nold rule\n")
    r.write("docs/adr.md", "Protect owner decisions\nold rule\n")
    r.write("openspec/huge.md", "small\n")
    local a = r.commit()
    r.write("focus.lua", "owner or editor\n"); r.write("huge.lua", string.rep("x", 100000))
    r.write("openspec/spec.md", "Only owners cancel\nnew strict rule\n")
    r.write("docs/adr.md", "Protect owner decisions\nnew strict rule\n")
    r.write("openspec/huge.md", string.rep("x", 100000)); local b = r.commit()
    local state = r.display({ old = rev(a), new = rev(b) }, "focus.lua", "owner\n", "owner or editor\n")
    T.eq(nil, diff.collect(state.source, "hunk", { diff = "review", max_bytes = 12000 }))
    local system, reads = vim.system, 0
    vim.system = function(command, options, callback)
      if vim.tbl_contains(command, "blob") then reads = reads + 1 end
      return system(command, options, callback)
    end
    local ok, s, err = pcall(diff.collect, state.source, "hunk", { diff = "auto", max_bytes = 12000 })
    vim.system = system
    assert(ok and s, err or s); T.eq(12, reads)
    T.eq("focused", s.context.strategy)
    T.eq(2, s.context.omitted_files)
    T.eq("openspec/spec.md", s.comparison.manifest[2].path)
    T.eq("Only owners cancel", file(s, "openspec/spec.md", "new").lines[1])
    T.eq("Protect owner decisions", file(s, "docs/adr.md", "new").lines[1])
    local note = { summary = "Permission mismatch", detail = "Supplied policy conflicts with this target.", intent_basis = "documented",
      anchors = { { path = "focus.lua", side = "new", start_line = 1, end_line = 1 } },
      evidence = { { path = "openspec/spec.md", side = "new", start_line = 1, end_line = 1 } } }
    assert(require("explainr.model").validate({ version = 1, notes = { note } }, s))
    T.eq(true, diff.fresh(s))
  end)
end)

T.test("huge selected versions use compact hunk excerpts and reject omitted same-file citations", function()
  repo(function(r)
    local before = {}
    for index = 1, 2000 do before[index] = string.format("line %04d %s", index, string.rep("x", 80)) end
    local old = table.concat(before, "\n") .. "\n"
    r.write("focus.lua", old); local a = r.commit()
    before[1000], before[1800] = "selected é中", "OTHER HUNK NOT SUPPLIED"
    local new = table.concat(before, "\n") .. "\n"
    r.write("focus.lua", new); local b = r.commit()
    local state = r.display({ old = rev(a), new = rev(b) }, "focus.lua", old, new)
    api.nvim_win_set_cursor(state.source, { 1000, 0 })
    T.eq(nil, diff.collect(state.source, "hunk", { diff = "review", max_bytes = 9000 }))
    local s = assert(diff.collect(state.source, "hunk", { diff = "auto", radius = 2, max_bytes = 9000 }))
    T.eq("focused", s.context.strategy); T.eq({ 1000, 1, 1000, 1 }, s.target.hunk)
    local supplied = file(s, "focus.lua", "new")
    T.eq(nil, supplied.lines); T.eq(2000, supplied.line_count)
    T.eq(998, supplied.chunks[1].start_line); T.eq(5, #supplied.chunks[1].lines)
    local prompt = assert(require("explainr.prompt").build(s, s.max_bytes))
    assert(not prompt:find("OTHER HUNK NOT SUPPLIED", 1, true))
    local n = { summary = "Selected change", detail = "Visible change only.", intent_basis = "unknown", evidence = {},
      anchors = { { path = "focus.lua", side = "new", start_line = 1000, end_line = 1000 } } }
    assert(require("explainr.model").validate({ version = 1, notes = { n } }, s))
    n.evidence = { { path = "focus.lua", side = "new", start_line = 1800, end_line = 1800 } }
    T.eq(nil, require("explainr.model").validate({ version = 1, notes = { n } }, s))
    api.nvim_win_set_cursor(state.source, { 1800, 0 }); T.eq(true, diff.fresh(s))
    local config = require("explainr").config.context
    local strategy, radius = config.diff, config.radius
    config.diff, config.radius = "review", 100
    local fresh = diff.fresh(s)
    config.diff, config.radius = strategy, radius
    T.eq(true, fresh) -- Freshness retains the original strategy and radius.
    local tampered = vim.deepcopy(s); tampered.context.omitted_files = 99
    T.eq(false, diff.fresh(tampered))
    local other = assert(diff.collect(state.source, "hunk", { diff = "focused", radius = 2, max_bytes = 9000 }))
    assert(other.review_fingerprint ~= s.review_fingerprint)
    T.eq(nil, diff.collect(state.source, "file", { diff = "focused", max_bytes = 9000 }))
  end)
end)

T.test("focused surroundings shrink before rejection and mandatory UTF-8 target has an exact honest boundary", function()
  repo(function(r)
    local before = {}
    for index = 1, 80 do before[index] = string.format("line %02d %s", index, string.rep("é中", 60)) end
    local old = table.concat(before, "\n") .. "\n"
    r.write("focus.lua", old); local a = r.commit(); before[40] = "new é中"
    local new = table.concat(before, "\n") .. "\n"; r.write("focus.lua", new); local b = r.commit()
    local state = r.display({ old = rev(a), new = rev(b) }, "focus.lua", old, new)
    api.nvim_win_set_cursor(state.source, { 40, 0 })
    local minimal = assert(diff.collect(state.source, "hunk", { diff = "focused", radius = 0, max_bytes = 100000 }))
    local prompt = require("explainr.prompt")
    local text, _, bytes = prompt.build(minimal, 100000)
    -- Leave a little room for surroundings, independent of instruction length.
    local s = assert(diff.collect(state.source, "hunk", { diff = "focused", radius = 20, max_bytes = bytes + 1024 }))
    assert(s.context.radius < 20); T.eq({ 40, 1, 40, 1 }, s.target.hunk)
    T.eq(true, diff.fresh(s))
    local exact = assert(diff.collect(state.source, "hunk", { diff = "focused", radius = 0, max_bytes = bytes }))
    T.eq(text, assert(prompt.build(exact, bytes)))
    local result, err = diff.collect(state.source, "hunk", { diff = "focused", radius = 0, max_bytes = bytes - 1 })
    T.eq(nil, result); assert(err:find("No target was truncated", 1, true), err)
    T.eq(nil, diff.collect(state.source, "hunk", { diff = "auto", radius = 0, max_bytes = bytes - 1 }))
  end)
end)

T.test("focused file scope retains entire target and optional docs are omitted deterministically under budget", function()
  repo(function(r)
    r.write("focus.lua", "old\nunchanged\n"); r.write("docs/adr.md", "old\n"); r.write("openspec/spec.md", "old\n")
    local a = r.commit(); r.write("focus.lua", "new\nunchanged\n")
    r.write("docs/adr.md", "new\n"); r.write("openspec/spec.md", "new\n"); local b = r.commit()
    local state = r.display({ old = rev(a), new = rev(b) }, "focus.lua", "old\nunchanged\n", "new\nunchanged\n")
    local complete = assert(diff.collect(state.source, "file", { diff = "focused", max_bytes = 100000 }))
    T.eq({ "new", "unchanged" }, file(complete, "focus.lua", "new").lines)
    T.eq(2, complete.target.anchors[2].end_line)
    T.eq({ { 1, 1, 1, 1 } }, complete.target.hunks) -- Focused file fallback keeps the same change priority.
    local prompt = require("explainr.prompt")
    local reduced = vim.deepcopy(complete)
    reduced.context.omitted_files = 1
    reduced.comparison.manifest[3] = nil
    reduced.files[5], reduced.files[6] = nil, nil
    local _, _, budget = prompt.build(reduced, 100000)
    local s = assert(diff.collect(state.source, "file", { diff = "focused", max_bytes = budget }))
    T.eq(1, s.context.omitted_files)
    T.eq("openspec/spec.md", s.comparison.manifest[2].path)
    T.eq(s.fingerprint, assert(diff.collect(state.source, "file", { diff = "focused", max_bytes = budget })).fingerprint)
  end)
end)

T.test("focused mutable freshness retains overlays full index manifest and omitted-file stat guards", function()
  repo(function(r)
    r.write("focus.lua", "old\nunchanged\n"); r.write("huge.lua", "small\n"); r.write("openspec/spec.md", "owner\n")
    r.commit(); r.write("focus.lua", "new\nunchanged\n"); r.write("huge.lua", string.rep("x", 100000))
    local state, _, new = r.display({ old = { type = "stage", stage = 0 }, new = { type = "local" } },
      "focus.lua", "old\nunchanged\n", "new\nunchanged\n")
    local doc = r.buf("openspec/spec.md", "owner\n")
    api.nvim_buf_set_lines(doc, 0, -1, false, { "strict owner" })
    api.nvim_buf_set_lines(new, 0, -1, false, { "unsaved new", "unchanged" })
    local function collect() return assert(diff.collect(state.source, "hunk", { diff = "auto", max_bytes = 10000 })) end
    local s = collect(); T.eq("focused", s.context.strategy)
    T.eq({ "unsaved new", "unchanged" }, file(s, "focus.lua", "new").chunks[1].lines)
    T.eq("strict owner", file(s, "openspec/spec.md", "new").lines[1])
    api.nvim_win_set_cursor(state.source, { 2, 0 }); T.eq(true, diff.fresh(s))
    api.nvim_win_set_cursor(state.source, { 1, 0 })
    api.nvim_buf_set_lines(doc, 0, -1, false, { "later owner" }); T.eq(false, diff.fresh(s))
    s = collect(); r.write("huge.lua", string.rep("y", 100000)); T.eq(false, diff.fresh(s))
    s = collect(); r.write("new.lua", "new untracked\n"); T.eq(false, diff.fresh(s))
    s = collect(); r.git("add", "--", "new.lua"); T.eq(false, diff.fresh(s))
    s = collect(); api.nvim_buf_set_lines(new, 0, -1, false, { "later new", "unchanged" }); T.eq(false, diff.fresh(s))
  end)
end)

T.test("focused async collection cancels delayed Git and captures invocation cursor before movement", function()
  repo(function(r)
    r.write("focus.lua", "old\nunchanged\n"); local a = r.commit(); r.write("focus.lua", "new\nunchanged\n"); local b = r.commit()
    local state = r.display({ old = rev(a), new = rev(b) }, "focus.lua", "old\nunchanged\n", "new\nunchanged\n")
    local system, release, held, callbacks, kills = vim.system, nil, true, 0, 0
    vim.system = function(command, options, callback)
      local process = system(command, options, function(value)
        if held and vim.tbl_contains(command, "--name-status") then release = function() callback(value) end
        else callback(value) end
      end)
      return { kill = function(_, signal) kills = kills + 1; process:kill(signal) end }
    end
    local job
    local ok, err = xpcall(function()
      job = diff.collect_async(state.source, "hunk", function() callbacks = callbacks + 1 end, { diff = "focused" })
      assert(vim.wait(3000, function() return release ~= nil end))
      job.cancel(); held = false; release(); release = nil; vim.wait(50)
      T.eq(0, callbacks); assert(kills > 0)
      held = true
      local snapshot, message
      job = diff.collect_async(state.source, "hunk", function(value, failure) snapshot, message = value, failure; callbacks = callbacks + 1 end,
        { diff = "focused" })
      assert(vim.wait(3000, function() return release ~= nil end))
      api.nvim_win_set_cursor(state.source, { 2, 0 }); held = false; release(); release = nil
      assert(vim.wait(3000, function() return callbacks == 1 end)); assert(snapshot, message)
      T.eq({ 1, 1, 1, 1 }, snapshot.target.hunk); T.eq(true, diff.fresh(snapshot))
    end, debug.traceback)
    if job then job.cancel() end
    held = false; if release then release() end
    vim.system = system
    assert(ok, err)
  end)
end)

T.test("focused changed requirements outrank optional nearby source surroundings", function()
  repo(function(r)
    local content = {}
    for index = 1, 80 do content[index] = string.format("line %02d %s", index, string.rep("x", 50)) end
    local before = table.concat(content, "\n") .. "\n"
    r.write("focus.lua", before); r.write("openspec/spec.md", "Owner-only cancellation\nold policy\n"); local a = r.commit()
    content[40] = "allow editors"; local after = table.concat(content, "\n") .. "\n"
    r.write("focus.lua", after); local b = r.commit()
    local state = r.display({ old = rev(a), new = rev(b) }, "focus.lua", before, after)
    api.nvim_win_set_cursor(state.source, { 40, 0 })
    local solo = assert(diff.collect(state.source, "hunk", { diff = "focused", radius = 20, max_bytes = 100000 }))
    local _, _, bytes = require("explainr.prompt").build(solo, 100000)
    r.write("openspec/spec.md", "Owner-only cancellation\nnew strict policy\n"); local c = r.commit()
    state = r.display({ old = rev(a), new = rev(c) }, "focus.lua", before, after)
    api.nvim_win_set_cursor(state.source, { 40, 0 })
    local s = assert(diff.collect(state.source, "hunk", { diff = "focused", radius = 20, max_bytes = bytes + 300 }))
    assert(s.context.radius < 20); T.eq(0, s.context.omitted_files)
    T.eq("Owner-only cancellation", file(s, "openspec/spec.md", "new").lines[1])
    T.eq(true, diff.fresh(s))
  end)
end)

T.test("focused insertion deletion zero-count sides and renames retain original coordinates", function()
  repo(function(r)
    r.write("old.lua", "one\ntwo\nthree\nfour\nfive\n"); local a = r.commit()
    r.git("mv", "--", "old.lua", "new.lua")
    r.write("new.lua", "one\ninsert\ntwo\nthree\nfour\nfive\n"); local b = r.commit()
    local state = r.display({ old = rev(a), new = rev(b) }, "new.lua", "one\ntwo\nthree\nfour\nfive\n",
      "one\ninsert\ntwo\nthree\nfour\nfive\n", "old.lua")
    api.nvim_win_set_cursor(state.source, { 2, 0 })
    local s = assert(diff.collect(state.source, "hunk", { diff = "focused", radius = 1 }))
    T.eq({ 1, 0, 2, 1 }, s.target.hunk); T.eq(0, s.context.omitted_files)
    T.eq({ "one", "two" }, file(s, "old.lua", "old").chunks[1].lines)
    T.eq({ "one", "insert", "two" }, file(s, "new.lua", "new").chunks[1].lines)
    T.eq({ { path = "new.lua", side = "new", start_line = 2, end_line = 2 } }, s.target.anchors)
    r.write("new.lua", "one\nthree\nfour\nfive\n"); local c = r.commit()
    state = r.display({ old = rev(b), new = rev(c) }, "new.lua", "one\ninsert\ntwo\nthree\nfour\nfive\n",
      "one\nthree\nfour\nfive\n")
    api.nvim_win_set_cursor(state.windows.old, { 2, 0 })
    local deleted = assert(diff.collect(state.windows.old, "hunk", { diff = "focused", radius = 0 }))
    T.eq({ 2, 2, 1, 0 }, deleted.target.hunk)
    T.eq({ "insert", "two" }, file(deleted, "new.lua", "old").chunks[1].lines)
    T.eq({}, file(deleted, "new.lua", "new").chunks)
    T.eq({ { path = "new.lua", side = "old", start_line = 2, end_line = 3 } }, deleted.target.anchors)
    T.eq(true, diff.fresh(deleted))
  end)
end)

T.test("focused final editor guard also catches omitted overlays changed after the second pass", function()
  repo(function(r)
    r.write("focus.lua", "old\n"); r.write("other.lua", "same\n"); r.commit(); r.write("focus.lua", "new\n")
    r.display({ old = { type = "stage", stage = 0 }, new = { type = "local" } }, "focus.lua", "old\n", "new\n")
    local other = r.buf("other.lua", "same\n")
    local original, calls = adapter.current, 0
    adapter.current = function(win)
      calls = calls + 1
      local value = original(win)
      if calls == 3 then api.nvim_buf_set_lines(other, 0, -1, false, { "late omitted overlay" }) end
      return value
    end
    local ok, snapshot, err = pcall(diff.collect, 0, "hunk", { diff = "focused" })
    adapter.current = original
    assert(ok); T.eq(nil, snapshot); assert(err:find("changed during collection", 1, true), err)
  end)
end)

T.test("genuinely oversized selected hunk is rejected in auto and focused without truncating target", function()
  repo(function(r)
    r.write("focus.lua", "old\n"); local a = r.commit()
    local target = string.rep("mandatory changed é中 " .. string.rep("x", 100) .. "\n", 2000)
    r.write("focus.lua", target); local b = r.commit()
    local state = r.display({ old = rev(a), new = rev(b) }, "focus.lua", "old\n", target)
    for _, strategy in ipairs({ "auto", "focused" }) do
      local result, err = diff.collect(state.source, "hunk", { diff = strategy, radius = 20, max_bytes = 10000 })
      T.eq(nil, result); assert(err:find("Mandatory target", 1, true) and err:find("No target was truncated", 1, true), err)
    end
  end)
end)

T.test("review has deterministic targets for all text entries and metadata IDs for binary and empty files", function()
  repo(function(r)
    r.write("a.lua", "old\n"); local a = r.commit()
    r.write("a.lua", "new\n"); r.write("b.lua", "added\n")
    r.write("binary.dat", "a\0b"); r.write("empty.txt", ""); local b = r.commit()
    local state = r.display({ old = rev(a), new = rev(b) }, "a.lua", "old\n", "new\n")
    local snapshot = assert(diff.collect(state.source, "review", { diff = "focused" }))
    T.eq("review", snapshot.context.strategy); T.eq(0, snapshot.context.omitted_files)
    T.eq(4, #snapshot.comparison.manifest); T.eq(2, #snapshot.target.files)
    local ids = {}
    for _, item in ipairs(snapshot.comparison.manifest) do
      assert(type(item.file_id) == "string" and not ids[item.file_id]); ids[item.file_id] = true
    end
    for _, target in ipairs(snapshot.target.files) do
      T.eq("file", target.scope); T.eq(manifest(snapshot, target.path).file_id, target.file_id)
      assert(#target.anchors > 0)
    end
    assert(manifest(snapshot, "binary.dat").text_unavailable)
    assert(manifest(snapshot, "empty.txt").text_unavailable)
    local again = assert(diff.collect(state.source, "review", { diff = "auto" }))
    T.eq(snapshot.target, again.target)
    local _, _, size = require("explainr.prompt").build(snapshot, math.huge)
    for _, strategy in ipairs({ "focused", "auto" }) do
      local missing, err = diff.collect(state.source, "review", { diff = strategy, max_bytes = size - 1 })
      T.eq(nil, missing); assert(err:find("Complete prompt", 1, true), err)
    end
  end)
end)

T.test("metadata-only review fails before inference", function()
  repo(function(r)
    r.write("keep", "same\n"); local a = r.commit(); r.write("empty", ""); local b = r.commit()
    r.display({ old = rev(a), new = rev(b) }, "empty", nil, "")
    local snapshot, err = diff.collect(0, "review")
    T.eq(nil, snapshot); assert(err:find("no eligible textual targets", 1, true), err)
  end)
end)

T.test("invocation capture survives A to B before collection and fixed revisions ignore mutable edits", function()
  repo(function(r)
    r.write("a.lua", "a old\n"); r.write("b.lua", "b old\n"); local a = r.commit()
    r.write("a.lua", "a new\n"); r.write("b.lua", "b new\n"); local b = r.commit()
    local state = r.display({ old = rev(a), new = rev(b) }, "a.lua", "a old\n", "a new\n")
    local done, snapshot, failure
    diff.collect_async(state.source, "hunk", function(value, err) snapshot, failure, done = value, err, true end)
    state.selected.path, state.selected.oldpath = "b.lua", "b.lua"
    api.nvim_win_set_buf(state.windows.old, r.buf(nil, "b old\n"))
    api.nvim_win_set_buf(state.windows.new, r.buf(nil, "b new\n"))
    assert(vim.wait(10000, function() return done end, 5)); assert(snapshot, failure)
    T.eq("a.lua", snapshot.target.path); T.eq(true, diff.fresh(snapshot))
    r.write("unrelated", "working\n"); r.git("add", "unrelated")
    T.eq(true, diff.fresh(snapshot))
    state.selected.kind = "staged"; T.eq(false, diff.fresh(snapshot)); state.selected.kind = "working"
    state.path_args = { "b.lua" }; T.eq(false, diff.fresh(snapshot))
  end)
end)

T.test("detached working and stage freshness accepts recreated clean buffers but rejects discarded overlays", function()
  repo(function(r)
    r.write("a.lua", "old\n"); local a = r.commit(); r.write("a.lua", "new\n")
    for _, staged in ipairs({ false, true }) do
      if staged then r.git("add", "a.lua") end
      local pair = staged and { old = rev(a), new = { type = "stage", stage = 0 } }
        or { old = { type = "stage", stage = 0 }, new = { type = "local" } }
      local state, _, new = r.display(pair, "a.lua", "old\n", "new\n")
      local snapshot = r.collect()
      api.nvim_win_set_buf(state.windows.new, r.buf(nil, "loading\n"))
      api.nvim_buf_delete(new, { force = true })
      local recreated = r.buf(staged and nil or "a.lua", "new\n")
      api.nvim_win_set_buf(state.windows.new, recreated)
      if staged then state.stage_buffers["a.lua"] = recreated end
      T.eq(true, diff.fresh(snapshot))
      api.nvim_buf_set_lines(recreated, 0, -1, false, { "unsaved" })
      T.eq(false, diff.fresh(snapshot))
      snapshot = r.collect()
      api.nvim_win_set_buf(state.windows.new, r.buf(nil, "loading\n"))
      api.nvim_buf_delete(recreated, { force = true })
      if staged then state.stage_buffers["a.lua"] = nil end
      T.eq(false, diff.fresh(snapshot))
    end
  end)
end)

T.test("normalized review files preserve shared provenance on restore and invalidate with shared evidence", function()
  repo(function(r)
    r.write("a.lua", "old\n"); r.write("doc.md", "old rationale\n"); r.commit()
    r.write("a.lua", "new\n"); r.write("doc.md", "new rationale\n")
    local state = r.display({ old = { type = "stage", stage = 0 }, new = { type = "local" } }, "a.lua", "old\n", "new\n")
    local review = r.collect("review")
    local normalized = vim.deepcopy(review)
    normalized.target, normalized.provenance = review.target.files[1], review
    local done, restored
    diff.restore_async(normalized, state.source, function(value) restored, done = value, true end)
    assert(vim.wait(10000, function() return done end, 5)); assert(restored)
    T.eq("file", restored.target.scope); T.eq(review, restored.provenance)
    T.eq(state.windows, restored.windows); T.eq(state.source, restored.source)
    r.write("doc.md", "changed shared rationale\n")
    T.eq(false, diff.fresh(normalized))
  end)
end)

T.test("navigation during working collection preserves captured unsaved text and rejects its discard", function()
  for _, discard in ipairs({ false, true }) do
    repo(function(r)
      r.write("a.lua", "old\n"); r.write("b.lua", "old b\n"); r.commit()
      r.write("a.lua", "saved\n"); r.write("b.lua", "new b\n")
      local state, _, new = r.display({ old = { type = "stage", stage = 0 }, new = { type = "local" } },
        "a.lua", "old\n", "saved\n")
      api.nvim_buf_set_lines(new, 0, -1, false, { "captured unsaved" })
      local done, snapshot, failure
      diff.collect_async(state.source, "file", function(value, err) snapshot, failure, done = value, err, true end)
      state.selected.path, state.selected.oldpath = "b.lua", "b.lua"
      api.nvim_win_set_buf(state.windows.old, r.buf(nil, "old b\n"))
      api.nvim_win_set_buf(state.windows.new, r.buf("b.lua", "new b\n"))
      if discard then api.nvim_buf_delete(new, { force = true }) end
      assert(vim.wait(10000, function() return done end, 5))
      if discard then
        T.eq(nil, snapshot); assert(failure:find("changed during collection", 1, true), failure)
      else
        assert(snapshot, failure); T.eq("a.lua", snapshot.target.path)
        T.eq({ "captured unsaved" }, file(snapshot, "a.lua", "new").lines)
        T.eq(true, diff.fresh(snapshot))
      end
    end)
  end
end)

T.test("adapter selects exact renamed comparison entry without guessing a working path", function()
  local original = package.loaded["diffview.lib"]
  local revs = { a = { type = 2, commit = "abc" }, b = { type = 2, commit = "def" } }
  local entries = {
    { path = "new.lua", oldpath = "old.lua", kind = "working", status = "R", revs = revs },
    { path = "new.lua", oldpath = "other.lua", kind = "working", status = "R", revs = revs },
    { path = "new.lua", oldpath = "old.lua", kind = "staged", status = "R", revs = revs },
  }
  local selected
  local view = { valid = true, closing = { check = function() return false end }, cur_entry = entries[1],
    files = { iter = function() return ipairs(entries) end }, set_file = function(_, entry) selected = entry end }
  package.loaded["diffview.lib"] = { get_current_view = function() return view end }
  local ok, err = xpcall(function()
    local target = { path = "new.lua", oldpath = "old.lua", kind = "working",
      comparison = { old = rev("abc"), new = rev("def") } }
    assert(adapter.select(api.nvim_get_current_win(), target)); T.eq(entries[1], selected)
    selected = nil; target.oldpath = "missing.lua"
    T.eq(false, adapter.select(api.nvim_get_current_win(), target)); T.eq(nil, selected)
    target.oldpath = "old.lua"; target.comparison.new.commit = "123"
    T.eq(false, adapter.select(api.nvim_get_current_win(), target)); T.eq(nil, selected)
  end, debug.traceback)
  package.loaded["diffview.lib"] = original
  assert(ok, err)
end)
