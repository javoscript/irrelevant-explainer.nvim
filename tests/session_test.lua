local api = vim.api
local plugin, sessions, agent = require("explainr"), require("explainr.session"), require("explainr.agent")
local fixture = vim.fn.getcwd() .. "/tests/fixtures/agent.py"
local function config(mode, limit)
  plugin.setup({ ai = { command = { "python3", fixture, mode or "explain" } }, context = { max_bytes = limit or 262144 } })
end
local function fixture_buffer(run)
  plugin.close(); vim.cmd("silent! only!")
  local previous = api.nvim_get_current_buf()
  local buf = api.nvim_create_buf(false, false)
  api.nvim_set_current_buf(buf)
  api.nvim_buf_set_lines(buf, 0, -1, false, { "local outside = 1", "local function inner()", "  return outside", "end", "tail" })
  vim.bo[buf].filetype = "lua"
  local notifications, calls = {}, 0
  local old_notify, old_run = vim.notify, agent.run
  vim.notify = function(err) notifications[#notifications + 1] = err end
  agent.run = function(...) calls = calls + 1; return old_run(...) end
  local ok, err = xpcall(function() run(buf, api.nvim_get_current_win(), function() return calls end, notifications) end, debug.traceback)
  plugin.close(); vim.wait(60)
  vim.notify, agent.run = old_notify, old_run
  api.nvim_set_current_buf(previous); api.nvim_buf_delete(buf, { force = true })
  assert(ok, err)
end
local function ready(s)
  assert(vim.wait(3000, function() return s.pane.status:find("Ready", 1, true) ~= nil end), s.pane.status)
end
local function stale(s)
  api.nvim_exec_autocmds("TextChanged", {})
  assert(vim.wait(3000, function() return s.pane.status:find("Stale", 1, true) ~= nil end), s.pane.status)
  T.eq(nil, s.pane.result)
end

T.test("public code commands produce aligned notes and cached detail without inference", function()
  fixture_buffer(function(buf, win, calls)
    config(); vim.cmd("normal! 2GV2j" .. string.char(27))
    api.nvim_win_set_cursor(win, { 3, 2 })
    vim.cmd("'<,'>ExplainrCode selection")
    local s = sessions.current(); ready(s)
    local rows = api.nvim_buf_get_lines(s.pane.buf, 0, 4, false)
    T.eq("", rows[1]); T.eq("", rows[3])
    assert(rows[2]:find("Fixture start", 1, true)); assert(rows[4]:find("Fixture end", 1, true))
    T.eq(2, s.snapshot.target.anchors[1].start_line); T.eq(4, s.snapshot.target.anchors[1].end_line)
    api.nvim_set_current_win(s.pane.win); api.nvim_win_set_cursor(s.pane.win, { 2, 0 })
    api.nvim_exec_autocmds("CursorMoved", { buffer = s.pane.buf })
    T.eq({ 2, 2 }, api.nvim_win_get_cursor(win)) -- Ordinary motion preserves source column.
    vim.cmd("normal n"); T.eq({ 4, 0 }, api.nvim_win_get_cursor(win))
    vim.cmd("normal p"); T.eq({ 2, 0 }, api.nvim_win_get_cursor(win))
    vim.cmd("normal K"); T.eq(1, calls()); T.eq(true, vim.wo[s.pane.detail_win].linebreak)
    local float_buf = api.nvim_win_get_buf(s.pane.detail_win)
    local lines = api.nvim_buf_get_lines(float_buf, 0, -1, false)
    assert(table.concat(lines, "\n"):find("Full fixture explanation", 1, true))
    vim.cmd("ExplainrClose"); T.eq(nil, sessions.current())
    T.eq(false, api.nvim_win_is_valid(s.pane.win))
    api.nvim_set_current_win(win); vim.cmd("ExplainrCode")
    local file = sessions.current(); ready(file); T.eq(2, calls())
    T.eq("file", file.snapshot.target.scope)
    vim.cmd("ExplainrCode file"); local cached = sessions.current(); ready(cached)
    T.eq(file, cached); T.eq(file.pane.win, cached.pane.win); T.eq(1, #cached.batches)
    T.eq("Ready · cached", cached.pane.status); T.eq(2, calls())
    vim.cmd("ExplainrRefresh"); ready(sessions.current()); T.eq(3, calls())
    T.eq({ "local outside = 1", "local function inner()", "  return outside", "end", "tail" }, api.nvim_buf_get_lines(buf, 0, -1, false))
  end)
end)

T.test("code edits before and after completion invalidate notes without auto inference", function()
  fixture_buffer(function(buf, _, calls)
    config("explain-slow"); local s = plugin.code("file")
    api.nvim_buf_set_lines(buf, 0, 1, false, { "edited while waiting" }); stale(s)
    vim.wait(500); T.eq(1, calls()); T.eq(nil, s.pane.result)
    config(); s = plugin.refresh(); ready(s)
    api.nvim_buf_set_lines(buf, 0, 1, false, { "edited after completion" }); stale(s)
    T.eq(2, calls()); T.eq(nil, s.invocation)
    T.eq(nil, s.pane.result)
  end)
end)

T.test("supersession cancellation closure and failed refresh preserve accepted results", function()
  fixture_buffer(function(_, win, calls, errors)
    config("explain-slow"); local old = plugin.code("file")
    plugin.cancel(); T.eq(nil, old.invocation); assert(old.pane.status:find("Cancelled"))
    local pending = plugin.refresh()
    config(); local newer = plugin.code("file"); ready(newer)
    vim.wait(500); T.eq(pending, newer); T.eq(3, calls()); T.eq("Ready", newer.pane.status)
    local accepted = vim.deepcopy(newer.pane.result)
    config("explain-invalid"); local bad = plugin.refresh()
    assert(vim.wait(3000, function() return bad.pane.status:find("Failed", 1, true) ~= nil end))
    T.eq(accepted, bad.pane.result); T.eq(nil, bad.pane.pending); assert(errors[#errors]:find("range is absent", 1, true))
    config("nonzero"); local failure = plugin.refresh()
    assert(vim.wait(3000, function() return failure.pane.status:find("Failed", 1, true) ~= nil end))
    T.eq(accepted, failure.pane.result); assert(errors[#errors]:find("authentication required", 1, true))
    config("explain-slow"); local closing = plugin.refresh()
    api.nvim_win_close(win, true)
    assert(vim.wait(1000, function() return closing.closed end)); vim.wait(500)
    T.eq(nil, sessions.current()); T.eq(nil, closing.invocation)
    T.eq(false, api.nvim_win_is_valid(closing.pane.win))
    T.eq(false, pcall(api.nvim_get_autocmds, { group = "ExplainrSession" .. closing.pane.win }))
  end)
end)

T.test("budget and selection errors launch no commands; visual refresh keeps exact retained region", function()
  fixture_buffer(function(buf, _, calls, errors)
    config(nil, 80); local s = plugin.code("file")
    T.eq(0, calls()); T.eq(nil, s.invocation); assert(errors[1]:find("Complete prompt", 1, true))
    api.nvim_buf_set_lines(buf, 4, 5, false, { "" })
    config(); local missing = plugin.code("selection", { type = "v", pos1 = { 0, 5, 1, 0 }, pos2 = { 0, 5, 1, 0 }, exclusive = true })
    T.eq(nil, missing); T.eq(0, calls())
    local selected = plugin.code("selection", { type = "v", pos1 = { buf, 1, 7, 0 }, pos2 = { buf, 1, 14, 0 }, exclusive = false })
    ready(selected); T.eq("outside ", selected.snapshot.target.text)
    api.nvim_buf_set_mark(buf, "<", 3, 0, {}); api.nvim_buf_set_mark(buf, ">", 4, 0, {})
    local refreshed = plugin.refresh(); ready(refreshed)
    T.eq("outside ", refreshed.snapshot.target.text); T.eq(2, calls())
  end)
end)

T.test("explicit selections and Ex visual commands preserve their selected scope", function()
  fixture_buffer(function(buf, win, calls)
    api.nvim_buf_set_lines(buf, 0, -1, false, { "class Account:", "    def cancel(self):", "        permitted = True", "        return permitted", "", "outside = 1" })
    vim.bo[buf].filetype = "python"; config()
    local s = plugin.code("selection", { type = "V", pos1 = { buf, 1, 1, 0 }, pos2 = { buf, 4, 1, 0 } }); ready(s)
    T.eq(1, s.snapshot.target.anchors[1].start_line); T.eq(4, s.snapshot.target.anchors[1].end_line)
    s = plugin.code("selection", { type = "V", pos1 = { buf, 2, 1, 0 }, pos2 = { buf, 4, 1, 0 } }); ready(s)
    T.eq(2, s.snapshot.target.anchors[1].start_line); T.eq(4, s.snapshot.target.anchors[1].end_line)
    plugin.close(); api.nvim_set_current_win(win)
    vim.cmd("normal! 2GVj" .. string.char(27))
    vim.cmd("'<,'>ExplainrCode selection"); s = sessions.current(); ready(s)
    T.eq(2, s.snapshot.target.anchors[1].start_line); T.eq(3, s.snapshot.target.anchors[1].end_line)
    T.eq("    def cancel(self):\n        permitted = True", s.snapshot.target.text)
    T.eq(3, calls())
  end)
end)

T.test("retired code scopes reject command and Lua calls before reuse without dropping accepted notes", function()
  fixture_buffer(function(_, _, calls, errors)
    config()
    T.eq({ "file", "selection" }, vim.fn.getcompletion("ExplainrCode ", "cmdline"))
    T.eq({ "file", "hunk", "review" }, vim.fn.getcompletion("ExplainrDiff ", "cmdline"))
    local s = plugin.code(); ready(s)
    T.eq("file", s.snapshot.target.scope)
    local accepted = vim.deepcopy(s.pane.result)
    local prompt, builds = require("explainr.prompt"), 0
    local build = prompt.build
    prompt.build = function(...) builds = builds + 1; return build(...) end
    local ok, err = xpcall(function()
      for _, scope in ipairs({ "function", "class" }) do
        for _, command in ipairs({ false, true }) do
          api.nvim_set_current_win(s.pane.win)
          if command then vim.cmd("ExplainrCode " .. scope)
          else T.eq(nil, plugin.code(scope)) end
          assert(errors[#errors]:find("unsupported code scope: " .. scope, 1, true))
          assert(errors[#errors]:find("scopes were removed; use file or selection", 1, true))
          T.eq(s, sessions.current()); T.eq(accepted, s.pane.result); T.eq(1, #s.batches)
          T.eq(1, calls()); T.eq(nil, s.invocation)
        end
      end
      T.eq(4, #errors)
      T.eq(0, builds) -- Prompt building precedes result-cache lookup in session.launch.
    end, debug.traceback)
    prompt.build = build
    assert(ok, err)
  end)
end)

T.test("changing custom decoder identity invalidates results even with the same argv", function()
  fixture_buffer(function(_, _, calls, errors)
    local command = { "python3", fixture, "explain" }
    plugin.setup({ ai = { command = command, output = function(stdout) return stdout end } })
    local first = plugin.code("file"); ready(first); T.eq(1, calls())
    local accepted = vim.deepcopy(first.pane.result)
    plugin.setup({ ai = { command = command, output = function() return nil, "different decoder contract" end } })
    local changed = plugin.code("file")
    assert(vim.wait(3000, function() return changed.pane.status:find("Failed", 1, true) ~= nil end))
    T.eq(2, calls()); T.eq(accepted, changed.pane.result); T.eq(first, changed)
    T.eq("different decoder contract", errors[#errors])
  end)
end)

T.test("diff results and cache wait for coalesced freshness; stale and cancelled checks cannot install results", function()
  fixture_buffer(function(_, win)
    config()
    local diff = require("explainr.diff")
    local old_collect, old_fresh, old_agent = diff.collect_async, diff.fresh_async, agent.run
    local captured = assert(require("explainr.code").collect(win, "file"))
    captured.mode, captured.windows = "diff", { old = win, new = win }
    captured.source = win
    captured.fingerprint = "async-session-regression:" .. captured.fingerprint
    captured.review_fingerprint = captured.fingerprint
    for _, value in ipairs(captured.files) do value.side = "new" end
    for _, value in ipairs(captured.target.anchors) do value.side = "new" end
    local collections, checks, launches, cancelled = {}, {}, {}, 0
    local function job()
      return { cancel = function() cancelled = cancelled + 1 end }
    end
    diff.collect_async = function(_, _, callback)
      collections[#collections + 1] = callback
      return job()
    end
    diff.fresh_async = function(_, callback)
      checks[#checks + 1] = callback
      return job()
    end
    agent.run = function(_, _, _, callback)
      launches[#launches + 1] = callback
      return job()
    end
    local function collect()
      collections[#collections](vim.deepcopy(captured))
    end
    local answer = '{"version":1,"notes":[]}'
    local ok, err = xpcall(function()
      local first = plugin.diff("file"); collect(); T.eq(1, #launches)
      -- A burst of events starts one check. A result arriving later requires
      -- a trailing pass, rather than trusting the already-running pass.
      for _ = 1, 5 do api.nvim_exec_autocmds("TextChanged", {}) end
      assert(vim.wait(1000, function() return #checks == 1 end))
      launches[1](answer); T.eq(1, #checks); T.eq(nil, first.pane.result)
      checks[1](true); T.eq(2, #checks); T.eq(nil, first.pane.result)
      checks[2](false); assert(first.pane.status:find("Stale")); T.eq(nil, first.pane.result)

      local second = plugin.diff("file"); collect()
      T.eq(2, #launches) -- The stale result must not have populated the cache.
      launches[2](answer); T.eq(nil, second.pane.result)
      checks[3](true); T.eq("Ready · no notes", second.pane.status)
      local accepted = vim.deepcopy(second.pane.result)

      local cached = plugin.diff("file"); collect()
      T.eq(second, cached); T.eq(2, #launches); T.eq(accepted, cached.pane.result)
      assert(cached.pane.status:find("Pending"))
      plugin.cancel(); local count = cancelled
      assert(count > 0); checks[4](true) -- Deliberately misbehaving late callback.
      assert(cached.pane.status:find("Cancelled")); T.eq(accepted, cached.pane.result)

      local pending = plugin.refresh(); collect(); launches[3](answer)
      local replacement = plugin.diff("file"); collect()
      T.eq(pending, replacement); checks[5](true)
      T.eq(accepted, replacement.pane.result)
      T.eq("Ready · no notes", replacement.pane.status); T.eq(3, #launches)
      T.eq(0, #replacement.queue) -- Identical pending target was deduplicated, not superseded.

      local closing = plugin.refresh(); collect(); launches[4](answer)
      plugin.close(); checks[6](true)
      T.eq(accepted, closing.pane.result); T.eq(nil, sessions.current())
    end, debug.traceback)
    plugin.close()
    diff.collect_async, diff.fresh_async, agent.run = old_collect, old_fresh, old_agent
    assert(ok, err)
  end)
end)

T.test("code scopes accumulate in one pane; cached repeats and refresh replace only their target", function()
  fixture_buffer(function(buf, win, calls)
    config(); api.nvim_win_set_cursor(win, { 3, 0 })
    local region = { type = "V", pos1 = { buf, 2, 1, 0 }, pos2 = { buf, 4, 1, 0 } }
    local s = plugin.code("selection", region); ready(s)
    local first = vim.deepcopy(s.batches[1])
    local pane_win = s.pane.win
    T.eq(s, plugin.code("file")); ready(s)
    T.eq(pane_win, s.pane.win); T.eq(2, #s.batches); T.eq(4, #s.pane.result.notes)
    T.eq(first, s.batches[1])
    local selection = { type = "V", pos1 = { buf, 2, 1, 0 }, pos2 = { buf, 3, 1, 0 } }
    T.eq(s, plugin.code("selection", selection)); ready(s)
    T.eq(3, #s.batches); T.eq(6, #s.pane.result.notes); T.eq(3, calls())
    local selected = vim.deepcopy(s.batches[3])
    T.eq(s, plugin.code("selection", region)); ready(s)
    T.eq("Ready · cached", s.pane.status); T.eq(3, calls()); T.eq(6, #s.pane.result.notes)
    api.nvim_win_set_cursor(win, { 5, 0 })
    T.eq(s, plugin.refresh()); ready(s)
    T.eq(2, s.snapshot.target.anchors[1].start_line); T.eq(4, s.snapshot.target.anchors[1].end_line)
    T.eq(4, calls()); T.eq(3, #s.batches); T.eq(selected, s.batches[3])
    -- Neither callers mutating the view nor UI detail operations mutate batches.
    s.pane.result.notes[1].detail = "view-only mutation"
    T.eq(first.result.notes[1].detail, s.batches[1].result.notes[1].detail)
    api.nvim_set_current_win(s.pane.win); api.nvim_win_set_cursor(s.pane.win, { 2, 0 })
    s.pane:detail()
    api.nvim_win_set_cursor(s.pane.win, { api.nvim_buf_line_count(s.pane.detail_buf), 0 })
    local target = assert(s.pane:detail_target())
    T.eq(s, plugin.code("file")); ready(s)
    T.eq(target.line, api.nvim_win_get_cursor(target.win)[1]); T.eq(nil, s.pane.detail_buf)
    T.eq(win, s.source); T.eq(3, #s.batches); T.eq(4, calls())
    T.eq(nil, s.pane.pending)
  end)
end)

T.test("failed collection and budget preserve accepted code, but fresh edits discard old batches without retry", function()
  fixture_buffer(function(buf, win, calls, errors)
    config(); local s = plugin.code("file"); ready(s)
    local accepted = vim.deepcopy(s.pane.result)
    api.nvim_win_set_cursor(win, { 5, 0 })
    T.eq(nil, plugin.code("selection", { type = "V", pos1 = { buf, 5, 1, 0 }, pos2 = { buf, 6, 1, 0 } }))
    T.eq(accepted, s.pane.result)
    T.eq(1, calls()); assert(errors[#errors]:find("selection position is unset or outside the buffer", 1, true))
    config(nil, 80); T.eq(s, plugin.code("file"))
    T.eq(accepted, s.pane.result); T.eq(nil, s.pane.pending); T.eq(1, calls())
    api.nvim_buf_set_lines(buf, 0, 1, false, { "local changed = 2" })
    -- No TextChanged dispatch between edit and request: the newest capture is
    -- fresh, even though all retained captures have the previous changedtick.
    config(); T.eq(s, plugin.code("file")); ready(s)
    T.eq(2, calls()); T.eq(1, #s.batches)
    T.eq("local changed = 2", s.batches[1].snapshot.files[1].lines[1])
    plugin.cancel(); T.eq(2, #s.pane.result.notes)
    api.nvim_buf_set_lines(buf, 0, 1, false, { "changed after cancel" }); stale(s)
    T.eq(2, calls()) -- Cancellation doesn't turn off retained-evidence checks.
  end)
end)

T.test("switching source buffers creates a new session without annotations from the previous buffer", function()
  fixture_buffer(function(_, win, calls)
    config(); local first = plugin.code("file"); ready(first)
    api.nvim_set_current_win(first.pane.win)
    first.pane:detail(1)
    api.nvim_win_set_cursor(first.pane.win, { api.nvim_buf_line_count(first.pane.detail_buf), 0 })
    local other = api.nvim_create_buf(false, false)
    api.nvim_buf_set_lines(other, 0, -1, false, { "other file", "second", "third", "fourth", "fifth" })
    api.nvim_win_set_buf(win, other)
    api.nvim_win_set_cursor(win, { 3, 2 })
    local second = plugin.code("file"); ready(second)
    T.eq({ 3, 2 }, api.nvim_win_get_cursor(win))
    T.eq(true, first.closed); assert(first ~= second); T.eq(1, #second.batches)
    T.eq(other, second.snapshot.source_buf); T.eq(2, calls())
    plugin.close(); api.nvim_buf_delete(other, { force = true })
  end)
end)

T.test("new pending code requests cancel prior jobs and ignore their deliberately late output", function()
  fixture_buffer(function(buf, _, _, errors)
    config()
    local old_agent, launches = agent.run, {}
    agent.run = function(request, config_value, _, callback)
      local job = { request = request, config = config_value, callback = callback }
      job.cancel = function() job.cancelled = true end
      launches[#launches + 1] = job
      return job
    end
    local function answer(job, summary)
      local target = vim.json.decode(job.request:match("FOCUSED TARGET JSON:\n(.*)"))
      job.callback({ version = 1, notes = { { summary = summary, detail = summary,
        anchors = { target.anchors[1] }, intent_basis = "unknown", evidence = {} } } })
    end
    local ok, err = xpcall(function()
      local s = plugin.code("file"); answer(launches[1], "accepted")
      local accepted = vim.deepcopy(s.pane.result)
      local function selection(line)
        return { type = "V", pos1 = { buf, line, 1, 0 }, pos2 = { buf, line, 1, 0 } }
      end
      T.eq(s, plugin.code("selection", selection(2)))
      T.eq(accepted, s.pane.result); T.eq("selection", s.pane.pending.scope)
      T.eq(s.snapshot, s.pane.pending.snapshot)
      T.eq(s, plugin.code("selection", selection(4)))
      T.eq(true, launches[2].cancelled); answer(launches[2], "late superseded")
      T.eq(accepted, s.pane.result); T.eq(4, s.pane.pending.snapshot.target.anchors[1].start_line)
      plugin.cancel(); T.eq(true, launches[3].cancelled); T.eq(nil, s.pane.pending)
      answer(launches[3], "late cancelled"); T.eq(accepted, s.pane.result)
      T.eq(s, plugin.code("selection", selection(5)))
      launches[4].callback(nil, "provider failed")
      T.eq(accepted, s.pane.result); T.eq(nil, s.pane.pending); T.eq("provider failed", errors[#errors])
      T.eq(s, plugin.code("selection", selection(3))); answer(launches[5], "new accepted")
      T.eq(2, #s.batches); T.eq(2, #s.pane.result.notes)
      T.eq("new accepted", s.pane.result.notes[2].summary)
    end, debug.traceback)
    plugin.close(); agent.run = old_agent
    assert(ok, err)
  end)
end)

-- Controlled two-sided comparisons exercise session ownership without Git,
-- Diffview, or a provider. Jobs still expose the real adapter's state shape.
local function diff_fixture(run)
  fixture_buffer(function(buf, win, _, errors)
    config()
    vim.cmd("aboveleft vsplit")
    local old_win, old_buf = api.nvim_get_current_win(), api.nvim_create_buf(false, false)
    api.nvim_buf_set_lines(old_buf, 0, -1, false, api.nvim_buf_get_lines(buf, 0, -1, false))
    api.nvim_win_set_buf(old_win, old_buf); api.nvim_set_current_win(win)
    local base = assert(require("explainr.code").collect(win, "file"))
    local diff = require("explainr.diff")
    local old_collect, old_fresh, old_agent = diff.collect_async, diff.fresh_async, agent.run
    local f = { collections = {}, checks = {}, launches = {}, checked = 0, errors = errors, win = win, old_win = old_win }
    f.state = { cwd = base.cwd, windows = { old = old_win, new = win }, source = win,
      pair = { old = { type = "commit", commit = "abc" }, new = { type = "local" } },
      selected = { path = base.files[1].path, oldpath = base.files[1].path, kind = "working" },
      panes = { old = { buf = old_buf, lines = base.files[1].lines, tick = 1 },
        new = { buf = buf, lines = base.files[1].lines, tick = 1 } } }
    local function job()
      local value = {}
      value.cancel = function() value.cancelled = true end
      return value
    end
    diff.collect_async = function(source, scope, callback, options)
      local value = job()
      value.state = vim.deepcopy(f.state); value.state.source = source
      value.source, value.scope, value.callback, value.options = source, scope, callback, vim.deepcopy(options)
      f.collections[#f.collections + 1] = value
      return value
    end
    diff.fresh_async = function(snapshot, callback)
      local value = job()
      value.snapshot, value.callback = snapshot, callback
      f.checks[#f.checks + 1] = value
      return value
    end
    agent.run = function(request, captured_config, _, callback)
      local value = job()
      value.request, value.config, value.callback = request, captured_config, callback
      f.launches[#f.launches + 1] = value
      return value
    end
    function f.snapshot(row, epoch, context, collection)
      local value = vim.deepcopy(base)
      value.mode, value.windows = "diff", vim.deepcopy(f.state.windows)
      value.source = f.collections[collection or #f.collections].source
      value.source_buf = f.state.panes[value.source == old_win and "old" or "new"].buf
      value.files = {}
      for _, side in ipairs({ "old", "new" }) do
        local file = vim.deepcopy(base.files[1]); file.side = side
        value.files[#value.files + 1] = file
      end
      value.target = { scope = "hunk", path = base.files[1].path, oldpath = base.files[1].path,
        hunk = { row, 1, row, 1 }, anchors = {} }
      for _, side in ipairs({ "old", "new" }) do
        value.target.anchors[#value.target.anchors + 1] = { path = base.files[1].path, side = side, start_line = row, end_line = row }
      end
      value.context = context or { strategy = "review", omitted_files = 0 }
      value.capture = { state = vim.deepcopy(f.state), target = vim.deepcopy(value.target), epoch = epoch or "initial" }
      value.capture.state.source = value.source
      value.review_fingerprint = base.fingerprint .. ":" .. (epoch or "initial") .. ":" .. vim.inspect(value.context)
      value.fingerprint = value.review_fingerprint .. ":" .. row
      return value
    end
    function f.collect(snapshot, index) f.collections[index or #f.collections].callback(snapshot) end
    function f.answer(summary, index)
      local value = f.launches[index or #f.launches]
      local target = vim.json.decode(value.request:match("FOCUSED TARGET JSON:\n(.*)"))
      value.callback({ version = 1, notes = { { summary = summary, detail = summary,
        anchors = target.anchors, intent_basis = "documented", evidence = { target.anchors[1] } } } })
    end
    function f.drain(fresh)
      while f.checked < #f.checks do
        f.checked = f.checked + 1
        local value = f.checks[f.checked]
        if not value.cancelled then value.callback(not fresh or fresh(value.snapshot)) end
      end
    end
    local ok, err = xpcall(function() run(f) end, debug.traceback)
    plugin.close(); diff.collect_async, diff.fresh_async, agent.run = old_collect, old_fresh, old_agent
    api.nvim_win_close(old_win, true); api.nvim_buf_delete(old_buf, { force = true })
    assert(ok, err)
  end)
end

T.test("automatic mode updates owned headers across tabs without disturbing detail or queued manual work", function()
  diff_fixture(function(f)
    local s = plugin.diff("hunk")
    local function header(p)
      return api.nvim_eval_statusline(vim.wo[p.win].winbar, { winid = p.win, use_winbar = true }).str
    end
    T.eq(nil, s.pane.snapshot); assert(not header(s.pane):find("Auto", 1, true))
    T.eq(true, plugin.toggle_auto_explain())
    assert(header(s.pane):find("Auto", 1, true)); T.eq(nil, f.collections[1].cancelled)
    f.collect(f.snapshot(2)); f.answer("accepted"); f.drain()
    api.nvim_set_current_win(s.pane.win); s.pane:detail(1)
    local detail, selected, result = s.pane.detail_buf, s.pane.detail_index, vim.deepcopy(s.pane.result)
    local tick = api.nvim_buf_get_changedtick(detail)
    local views = { api.nvim_win_call(s.pane.win, vim.fn.winsaveview), api.nvim_win_call(f.win, vim.fn.winsaveview) }
    -- A second diff session is still collecting, with a snapshot-free header.
    vim.cmd("tabnew")
    local other = plugin.diff("hunk")
    T.eq(nil, other.pane.snapshot); assert(header(other.pane):find("Auto", 1, true))
    local collection, status = other.collection, other.pane.status
    -- A third tab contains ordinary code; the setting must not advertise code automation.
    vim.cmd("tabnew")
    api.nvim_buf_set_lines(0, 0, -1, false, { "ordinary manual code" })
    local code = plugin.code("file")
    local code_job = f.launches[#f.launches]
    local tab, win = api.nvim_get_current_tabpage(), api.nvim_get_current_win()
    for _, enabled in ipairs({ false, true, false }) do
      T.eq(enabled, plugin.toggle_auto_explain())
      T.eq(enabled, header(s.pane):find("Auto", 1, true) ~= nil)
      T.eq(enabled, header(other.pane):find("Auto", 1, true) ~= nil)
      assert(not header(code.pane):find("Auto", 1, true))
      T.eq(tab, api.nvim_get_current_tabpage()); T.eq(win, api.nvim_get_current_win())
      T.eq(detail, s.pane.detail_buf); T.eq(selected, s.pane.detail_index); T.eq(tick, api.nvim_buf_get_changedtick(detail))
      T.eq(views, { api.nvim_win_call(s.pane.win, vim.fn.winsaveview), api.nvim_win_call(f.win, vim.fn.winsaveview) })
      T.eq(result, s.pane.result); T.eq(status, other.pane.status); T.eq(collection, other.collection)
      T.eq(nil, collection.cancelled); T.eq(nil, code_job.cancelled)
      T.eq(2, #f.launches); T.eq(2, #f.collections)
    end
    -- Explicit setup resets the mode and keeps existing headers synchronized.
    for _, enabled in ipairs({ true, false }) do
      plugin.setup({ diff = { auto_explain = enabled } })
      T.eq(enabled, header(s.pane):find("Auto", 1, true) ~= nil)
      T.eq(enabled, header(other.pane):find("Auto", 1, true) ~= nil)
      assert(not header(code.pane):find("Auto", 1, true))
      T.eq(detail, s.pane.detail_buf); T.eq(tick, api.nvim_buf_get_changedtick(detail))
      T.eq(tab, api.nvim_get_current_tabpage()); T.eq(win, api.nvim_get_current_win())
      T.eq(2, #f.launches); T.eq(nil, collection.cancelled); T.eq(nil, code_job.cancelled)
    end
    -- Edits in code mode still invalidate, never re-request.
    f.answer("code accepted")
    T.eq(true, plugin.toggle_auto_explain())
    api.nvim_buf_set_lines(api.nvim_get_current_buf(), 0, -1, false, { "changed code" })
    api.nvim_exec_autocmds("TextChanged", {})
    assert(vim.wait(1000, function() return code.pane.status:match("^Stale") end))
    T.eq(2, #f.launches)
    plugin.close(); vim.cmd("tabclose!")
    plugin.close(); vim.cmd("tabclose!"); api.nvim_set_current_tabpage(s.tab)
    api.nvim_set_current_win(f.win)
    plugin.diff("hunk"); f.collect(f.snapshot(4))
    local active = f.launches[#f.launches]
    plugin.diff("hunk"); local queued = s.queue[1]
    T.eq(false, plugin.toggle_auto_explain())
    T.eq(nil, active.cancelled); T.eq(nil, queued.collection.cancelled)
    f.collect(f.snapshot(5)); f.answer("first manual"); f.drain(); f.answer("queued manual"); f.drain()
    T.eq(3, #s.batches); T.eq("Ready", s.pane.status)
    T.eq(s, plugin.refresh()); T.eq(nil, s.collection.cancelled)
    T.eq("hunk", s.scope)
  end)
end)

T.test("paired diff sides accumulate with per-batch coverage and cached results follow the merge path", function()
  diff_fixture(function(f)
    local s = plugin.diff("hunk")
    T.eq(f.state.windows, s.pane.pending.windows); T.eq(nil, s.pane.pending.snapshot)
    local focused = { strategy = "focused", radius = 2, omitted_files = 7 }
    f.collect(f.snapshot(2, nil, focused)); f.answer("focused batch"); f.drain()
    T.eq(1, #s.batches); T.eq(focused, s.batches[1].snapshot.context)
    api.nvim_set_current_win(f.old_win); api.nvim_win_set_cursor(f.old_win, { 4, 0 })
    T.eq(s, plugin.diff("hunk")); T.eq(f.old_win, s.pane.pending.source); T.eq(4, s.pane.pending.row)
    f.collect(f.snapshot(4)); f.answer("review batch"); f.drain()
    T.eq(2, #s.batches); T.eq(2, #s.pane.result.notes)
    T.eq(focused, s.batches[1].snapshot.context); T.eq("review", s.batches[2].snapshot.context.strategy)
    T.eq(f.old_win, s.source); T.eq(f.old_win, s.pane.snapshot.source)
    -- UI may follow a different side without mutating accepted snapshots.
    -- An invocation from overview resolves the followed source.
    s.pane.source = f.win; api.nvim_set_current_win(s.pane.win)
    T.eq(s, plugin.diff("hunk")); T.eq(f.win, s.pane.pending.source)
    f.collect(f.snapshot(2, nil, focused)); T.eq(2, #f.launches)
    T.eq(2, #s.pane.result.notes); assert(s.pane.pending)
    local before = #f.checks; f.drain(); assert(#f.checks >= before + 1)
    T.eq("Ready · cached", s.pane.status); T.eq(2, #s.batches); T.eq(nil, s.pane.pending)
    T.eq(s, plugin.refresh()); T.eq(f.win, f.collections[#f.collections].source)
    T.eq(nil, f.collections[#f.collections].options.target) -- Recapture live diff coordinates.
    f.collect(f.snapshot(2, nil, focused)); f.answer("replacement batch"); f.drain()
    T.eq(3, #f.launches); T.eq(2, #s.batches)
    T.eq("replacement batch", s.pane.result.notes[1].summary)
    T.eq("review batch", s.pane.result.notes[2].summary)
  end)
end)

T.test("fresh diff additions discard stale retained evidence without rejecting the new capture", function()
  diff_fixture(function(f)
    local s = plugin.diff("hunk"); f.collect(f.snapshot(2, "old-evidence")); f.answer("old evidence"); f.drain()
    T.eq(s, plugin.diff("hunk")); f.collect(f.snapshot(4, "new-evidence")); f.answer("fresh evidence")
    local start = #f.checks
    f.drain(function(snapshot) return snapshot.capture.epoch == "new-evidence" end)
    assert(#f.checks > start) -- Old evidence, not merely latest evidence, was validated.
    T.eq("Ready", s.pane.status); T.eq(1, #s.batches)
    T.eq("fresh evidence", s.pane.result.notes[1].summary); T.eq(nil, s.pane.pending)
    -- Retained evidence must also be checked before installing a cached batch.
    T.eq(s, plugin.diff("hunk")); f.collect(f.snapshot(2, "old-evidence"))
    T.eq(2, #f.launches); f.drain(function(snapshot) return snapshot.capture.epoch == "old-evidence" end)
    T.eq("Ready · cached", s.pane.status); T.eq(1, #s.batches)
    T.eq("old evidence", s.pane.result.notes[1].summary)
  end)
end)

T.test("stale accepted evidence during collection does not cancel a request with no new snapshot yet", function()
  diff_fixture(function(f)
    local s = plugin.diff("hunk"); f.collect(f.snapshot(2, "old")); f.answer("accepted"); f.drain()
    T.eq(s, plugin.diff("hunk")); local collection = f.collections[#f.collections]
    api.nvim_exec_autocmds("TextChanged", {})
    assert(vim.wait(1000, function() return s.checking ~= nil end))
    f.drain(function() return false end)
    T.eq(nil, s.pane.result); assert(s.pane.pending); T.eq(nil, collection.cancelled)
    T.eq(collection, s.collection); T.eq(nil, s.pane.pending.snapshot)
    f.collect(f.snapshot(4, "fresh")); f.answer("fresh request"); f.drain()
    T.eq("Ready", s.pane.status); T.eq(1, #s.batches)
    T.eq("fresh request", s.pane.result.notes[1].summary); T.eq(2, #f.launches)
    api.nvim_exec_autocmds("TextChanged", {})
    assert(vim.wait(1000, function() return s.checking ~= nil end))
    f.drain(function() return false end)
    assert(s.pane.status:find("Stale")); T.eq(nil, s.pane.result); T.eq(2, #f.launches)
  end)
end)

T.test("all retained diff captures are watched and pending data is checked after slow older evidence", function()
  diff_fixture(function(f)
    local s = plugin.diff("hunk"); f.collect(f.snapshot(1, "first")); f.answer("first"); f.drain()
    plugin.diff("hunk"); f.collect(f.snapshot(2, "second")); f.answer("second"); f.drain()
    plugin.diff("hunk"); f.collect(f.snapshot(3, "latest")); f.answer("latest"); f.drain()
    T.eq(3, #s.batches)
    api.nvim_exec_autocmds("TextChanged", {})
    assert(vim.wait(1000, function() return s.checking ~= nil end))
    local checked = {}
    f.drain(function(snapshot)
      checked[snapshot.capture.epoch] = true
      return snapshot.capture.epoch ~= "second"
    end)
    T.eq({ first = true, second = true, latest = true }, checked)
    T.eq({ "first", "latest" }, vim.tbl_map(function(n) return n.summary end, s.pane.result.notes))
    assert(s.pane.status:find("Stale"))

    plugin.diff("hunk"); f.collect(f.snapshot(1, "fresh")); f.answer("fresh"); f.drain()
    plugin.diff("hunk"); f.collect(f.snapshot(4, "pending")); f.answer("pending")
    local old_check = f.checks[#f.checks]
    T.eq("fresh", old_check.snapshot.capture.epoch)
    -- Simulate new data becoming stale during that outstanding older read.
    f.drain(function(snapshot) return snapshot.capture.epoch ~= "pending" end)
    T.eq({ "fresh", "latest" }, vim.tbl_map(function(n) return n.summary end, s.pane.result.notes))
    T.eq(nil, s.pane.pending); assert(s.pane.status:find("Stale"))
  end)
end)

T.test("diff collection failure retains batches and cancelled collections cannot launch late results", function()
  diff_fixture(function(f)
    local s = plugin.diff("hunk"); f.collect(f.snapshot(2)); f.answer("accepted"); f.drain()
    local accepted = vim.deepcopy(s.pane.result)
    T.eq(s, plugin.diff("hunk")); local superseded = f.collections[#f.collections]
    T.eq(s, plugin.refresh()); T.eq(true, superseded.cancelled)
    superseded.callback(f.snapshot(4)); T.eq(1, #f.launches)
    f.collections[#f.collections].callback(nil, "ordinary collection failure")
    T.eq(accepted, s.pane.result); T.eq(nil, s.pane.pending); f.drain()
    T.eq(f.state.selected.path .. ": ordinary collection failure", f.errors[#f.errors])
    T.eq(s, plugin.diff("hunk")); local cancelled = f.collections[#f.collections]
    plugin.cancel(); cancelled.callback(f.snapshot(4))
    T.eq(1, #f.launches); T.eq(accepted, s.pane.result); T.eq(nil, s.pane.pending)
    -- Refreshing an uncollected newer request must not reuse the previous
    -- batch's target merely because pane.snapshot still supplies live layout.
    T.eq(s, plugin.refresh()); T.eq(nil, f.collections[#f.collections].options.target)
    plugin.cancel()
  end)
end)

T.test("pending hunks append in request order across collection and inference, preserving captured configuration", function()
  diff_fixture(function(f)
    api.nvim_win_set_cursor(f.win, { 2, 0 })
    local s = plugin.diff("hunk")
    local first = s.pending
    config("explain-slow")
    api.nvim_set_current_win(f.old_win); api.nvim_win_set_cursor(f.old_win, { 4, 0 })
    T.eq(s, plugin.diff("hunk"))
    T.eq(first, s.pending); T.eq(nil, f.collections[1].cancelled)
    T.eq(4, s.queue[1].row); T.eq(f.old_win, s.queue[1].source)
    T.eq(0, #f.launches)
    f.collect(f.snapshot(2, nil, nil, 1), 1)
    T.eq(1, #f.launches)
    api.nvim_set_current_win(f.win); api.nvim_win_set_cursor(f.win, { 5, 0 })
    T.eq(s, plugin.diff("hunk")); T.eq(nil, f.launches[1].cancelled)
    T.eq(2, #s.queue)
    -- Later collection finishes first; inference still respects request order.
    f.collect(f.snapshot(5, nil, nil, 3), 3)
    config("explain-invalid")
    api.nvim_win_set_cursor(f.old_win, { 1, 0 })
    api.nvim_win_set_cursor(f.win, { 1, 0 })
    f.answer("first"); f.drain()
    T.eq(1, #s.batches); T.eq("first", s.pane.result.notes[1].summary)
    T.eq(1, #f.launches); T.eq(f.collections[2], s.collection)
    T.eq(4, s.pending.row); T.eq(1, #s.queue)
    f.collect(f.snapshot(4, nil, nil, 2), 2)
    T.eq(2, #f.launches); T.eq("explain-slow", f.launches[2].config.command[3])
    T.eq(4, s.snapshot.target.anchors[1].start_line)
    f.answer("second"); f.drain()
    T.eq(2, #s.batches); T.eq(3, #f.launches)
    T.eq("explain-slow", f.launches[3].config.command[3]); T.eq(5, s.snapshot.target.anchors[1].start_line)
    f.answer("third"); f.drain()
    T.eq(3, #s.batches); T.eq(0, #s.queue); T.eq(nil, s.pane.pending)
    T.eq({ "first", "second", "third" }, vim.tbl_map(function(n) return n.summary end, s.pane.result.notes))
    T.eq("Ready", s.pane.status)
  end)
end)

T.test("promoting automatic work keeps explicit FIFO order despite out-of-order collection", function()
  diff_fixture(function(f)
    local s = plugin.diff("hunk"); f.collect(f.snapshot(1))
    sessions.start("diff", "file", { automatic = true })
    local automatic = s.automatic
    f.collect(f.snapshot(2, nil, nil, 2), 2)
    plugin.diff("file") -- Explicitly request the automatic candidate.
    plugin.diff("hunk") -- A later explicit request collects first.
    f.collect(f.snapshot(3, nil, nil, 4), 4)
    f.collect(f.snapshot(2, nil, nil, 3), 3)
    T.eq(nil, s.automatic); T.eq(automatic, s.queue[1]); T.eq(2, #s.queue)
    f.answer("first"); f.drain()
    T.eq(2, s.pending.snapshot.target.anchors[1].start_line)
    f.answer("promoted"); f.drain()
    T.eq(3, s.pending.snapshot.target.anchors[1].start_line)
    f.answer("last"); f.drain()
    T.eq(3, #f.launches)
  end)
end)

T.test("hunk queue skips collection and agent failures, then merges cached targets without duplicate notes", function()
  diff_fixture(function(f)
    local s = plugin.diff("hunk"); f.collect(f.snapshot(2)); f.answer("accepted"); f.drain()
    plugin.diff("hunk"); f.collect(f.snapshot(3))
    plugin.diff("hunk"); f.collections[3].callback(nil, "queued collection failed")
    plugin.diff("hunk"); f.collect(f.snapshot(2)) -- Cached target queued after failure.
    plugin.diff("hunk"); f.collect(f.snapshot(4))
    f.launches[2].callback(nil, "agent failed"); f.drain()
    T.eq({ f.state.selected.path .. ": agent failed", f.state.selected.path .. ": queued collection failed" }, f.errors)
    T.eq(1, #s.batches); T.eq("accepted", s.pane.result.notes[1].summary)
    T.eq(3, #f.launches); T.eq(4, s.pending.snapshot.target.anchors[1].start_line)
    f.answer("last"); f.drain()
    T.eq(2, #s.batches); T.eq({ "accepted", "last" }, vim.tbl_map(function(n) return n.summary end, s.pane.result.notes))
    T.eq("Ready", s.pane.status)
  end)
end)

T.test("cancel refresh close and stale comparison discard active and queued hunks, silencing late callbacks", function()
  diff_fixture(function(f)
    for _, action in ipairs({ "cancel", "refresh", "close", "stale" }) do
      local s = plugin.diff("hunk"); f.collect(f.snapshot(2, action))
      local active = f.launches[#f.launches]
      plugin.diff("hunk"); f.collect(f.snapshot(4, action))
      plugin.diff("hunk"); local collecting = f.collections[#f.collections]
      local queued_snapshot = f.snapshot(5, action)
      local calls = #f.launches
      if action == "stale" then
        api.nvim_exec_autocmds("TextChanged", {})
        assert(vim.wait(1000, function() return s.checking ~= nil end))
        f.drain(function() return false end)
      else plugin[action]() end
      T.eq(true, active.cancelled); T.eq(true, collecting.cancelled)
      T.eq(0, #s.queue); T.eq(0, #(s.pane.queued or {}))
      collecting.callback(queued_snapshot); active.callback(nil, "late failure")
      T.eq(calls, #f.launches); T.eq({}, f.errors)
      if action ~= "refresh" then T.eq(nil, s.pane.pending) end
      plugin.close()
    end
  end)
end)

T.test("Diffview closure owns its background session, cancels immediately, and leaves other tabs alone", function()
  diff_fixture(function(f)
    local lib, original = {}, package.loaded["diffview.lib"]
    local closing = false
    local view = { closing = { check = function() return closing end } }
    local s = plugin.diff("hunk"); f.collect(f.snapshot(2, "closure")); f.answer("accepted"); f.drain()
    lib.tabpage_to_view = function(tab) if tab == s.tab then return view end end
    lib.get_current_view = function() return nil end
    package.loaded["diffview.lib"] = lib
    local ok, err = xpcall(function()
      plugin.diff("hunk"); f.collect(f.snapshot(4, "closure"))
      local active = f.launches[#f.launches]
      plugin.diff("hunk"); local queued = f.collections[#f.collections]
      api.nvim_set_current_win(s.pane.win); s.pane:detail(1)
      local detail, summary = s.pane.detail_buf, s.pane.buf
      api.nvim_exec_autocmds("TextChanged", {})
      assert(vim.wait(1000, function() return s.checking ~= nil end))
      local checking = f.checks[#f.checks]
      api.nvim_exec_autocmds("User", { pattern = "DiffviewViewClosed" })
      vim.wait(30)
      T.eq(nil, s.closed) -- A different view may close while this tab is active.
      api.nvim_exec_autocmds("WinResized", {})
      vim.cmd("tabnew")
      local other_tab = api.nvim_get_current_tabpage()
      local other = plugin.code("file")
      local other_job = f.launches[#f.launches]
      -- The event contains no tab/view payload. The current tab is not proof
      -- of ownership, nor should a different view's closure kill this session.
      api.nvim_exec_autocmds("User", { pattern = "DiffviewViewClosed" })
      T.eq(nil, s.closed); T.eq(nil, other.closed)
      closing = true
      api.nvim_exec_autocmds("User", { pattern = "DiffviewViewClosed" })
      T.eq(true, s.closed); T.eq(true, active.cancelled); T.eq(true, queued.cancelled)
      T.eq(true, checking.cancelled); T.eq(nil, s.checking)
      T.eq(nil, s.timer); T.eq(nil, s.pending); T.eq(0, #s.queue)
      T.eq(nil, sessions.sessions[s.tab]); T.eq(other, sessions.current())
      T.eq(nil, other_job.cancelled); T.eq(other_tab, api.nvim_get_current_tabpage())
      T.eq(false, api.nvim_buf_is_valid(detail)); T.eq(false, api.nvim_buf_is_valid(summary))
      local calls = #f.launches
      queued.callback(f.snapshot(5)); active.callback(nil, "late closed failure")
      checking.callback(true)
      vim.wait(30)
      T.eq(calls, #f.launches); T.eq({}, f.errors)
      T.eq(other, sessions.current())
    end, debug.traceback)
    package.loaded["diffview.lib"] = original
    plugin.close()
    if api.nvim_get_current_tabpage() ~= s.tab then vim.cmd("tabclose!") end
    api.nvim_set_current_tabpage(s.tab)
    assert(ok, err)
  end)
end)

T.test("diff revision and mode changes cancel ownership while recreated display bindings do not", function()
  diff_fixture(function(f)
    local s = plugin.diff("hunk"); f.collect(f.snapshot(2)); f.answer("initial"); f.drain()
    plugin.diff("hunk"); local active = f.collections[#f.collections]
    plugin.diff("hunk"); local queued = f.collections[#f.collections]
    f.state.pair.old.commit = "def"
    local revised = plugin.diff("hunk"); T.eq(true, s.closed); T.eq(nil, revised.pane.result)
    T.eq(true, active.cancelled); T.eq(true, queued.cancelled); T.eq(0, #s.queue)
    active.callback(f.snapshot(4)); queued.callback(f.snapshot(5)); T.eq(1, #f.launches)
    f.collect(f.snapshot(2, "revision")); f.answer("revised"); f.drain(); T.eq(1, #revised.batches)
    f.state.windows.old, f.state.windows.new = f.state.windows.new, f.state.windows.old
    local layout = plugin.diff("hunk"); T.eq(revised, layout); T.eq(nil, revised.closed)
    f.collect(f.snapshot(2, "layout")); f.answer("layout"); f.drain()
    f.state.panes.old.buf = f.state.panes.new.buf
    local buffers = plugin.diff("hunk"); T.eq(layout, buffers); T.eq(nil, layout.closed)
    f.collect(f.snapshot(2, "buffers")); f.answer("buffers"); f.drain()
    local code = plugin.code("file"); T.eq(true, buffers.closed); T.eq(nil, code.pane.result)
    f.answer("code"); T.eq(1, #code.batches); T.eq("code", code.batches[1].snapshot.mode)
  end)
end)

T.test("captured config and context preferences key caching without dropping unrelated accepted batches", function()
  fixture_buffer(function(buf, win, calls)
    config(); api.nvim_win_set_cursor(win, { 3, 0 })
    local s = plugin.code("selection", { type = "V", pos1 = { buf, 2, 1, 0 }, pos2 = { buf, 4, 1, 0 } }); ready(s)
    local selection_batch = vim.deepcopy(s.batches[1])
    config("explain-slow"); T.eq(s, plugin.code("file"))
    plugin.setup({ ai = { command = { "python3", fixture, "explain-invalid" } }, context = { radius = 1 } })
    ready(s); T.eq(2, #s.batches); T.eq(selection_batch, s.batches[1]); T.eq(2, calls())
    -- Returning to the config captured by the pending request hits its cache.
    config("explain-slow"); T.eq(s, plugin.code("file")); ready(s)
    T.eq("Ready · cached", s.pane.status); T.eq(2, calls())
    plugin.setup({ ai = { command = { "python3", fixture, "explain-slow" } }, context = { radius = 1 } })
    T.eq(s, plugin.code("file")); ready(s); T.eq(3, calls()); T.eq(2, #s.batches)
    T.eq(selection_batch, s.batches[1])
  end)
end)
