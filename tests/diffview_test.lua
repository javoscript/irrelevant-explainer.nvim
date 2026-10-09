local api = vim.api
local adapter, diff = require("irrelevant_explainer.diffview"), require("irrelevant_explainer.diff")

T.test("diff modules and code mode load without optional Diffview dependency", function()
  assert(not package.loaded["diffview.lib"], "Diffview was eagerly loaded")
  local previous, buf = api.nvim_get_current_buf(), api.nvim_create_buf(false, false)
  api.nvim_set_current_buf(buf)
  api.nvim_buf_set_lines(buf, 0, -1, false, { "ordinary code" })
  local s, err = require("irrelevant_explainer.code").collect(0, "file")
  api.nvim_set_current_buf(previous); api.nvim_buf_delete(buf, { force = true })
  assert(s, err)
  assert(not package.loaded["diffview.lib"])
end)

local runtime = vim.env.IRRELEVANT_EXPLAINER_DIFFVIEW_PATH or (vim.fn.stdpath("data") .. "/lazy/diffview.nvim")
if vim.fn.isdirectory(runtime .. "/lua/diffview") ~= 1 then
  print("SKIP real Diffview runtime tests: missing dependency at " .. runtime .. " (set IRRELEVANT_EXPLAINER_DIFFVIEW_PATH)")
  return
end
-- Keep optional-plugin globals/autocmds/module loading out of the ordinary
-- suite. In particular its code-mode dependency assertion must stay useful.
if vim.env.IRRELEVANT_EXPLAINER_DIFFVIEW_CHILD ~= "1" then
  T.test("real Diffview runtime in isolated offline Neovim", function()
    -- Script (-l) mode does not resize the allocated screen grid when columns
    -- changes. Diffview's explicit redraw requires normal editor startup.
    local result = vim.system({ vim.v.progpath, "--headless", "-u", "NONE", "-i", "NONE", "-n",
      "-c", "luafile tests/run.lua" }, {
      cwd = vim.fn.getcwd(), env = { IRRELEVANT_EXPLAINER_TEST = "tests/diffview_test.lua", IRRELEVANT_EXPLAINER_DIFFVIEW_CHILD = "1",
        IRRELEVANT_EXPLAINER_DIFFVIEW_PATH = runtime } }):wait(240000)
    print((result.stdout or "") .. (result.stderr or ""))
    assert(result.code == 0 and result.signal == 0,
      string.format("isolated real Diffview tests failed (code=%s, signal=%s)", result.code, result.signal))
  end)
  return
end
vim.opt.runtimepath:append(runtime)
local plenary = vim.env.IRRELEVANT_EXPLAINER_PLENARY_PATH or (vim.fn.stdpath("data") .. "/lazy/plenary.nvim")
if vim.fn.isdirectory(plenary .. "/lua/plenary") == 1 then vim.opt.runtimepath:append(plenary) end

T.test("real Diffview roles revisions async guard file switches and notes source stay coherent", function()
  local root = vim.fn.tempname() .. " diffview;$'"
  vim.fn.mkdir(root, "p"); root = vim.uv.fs_realpath(root)
  local start, start_buf = api.nvim_get_current_win(), api.nvim_get_current_buf()
  local start_cwd, old_columns = vim.fn.getcwd(), vim.o.columns
  vim.o.columns = 160
  local function git(...)
    local result = vim.system(vim.list_extend({ "git" }, { ... }), { cwd = root }):wait()
    assert(result.code == 0, result.stderr)
    return vim.trim(result.stdout)
  end
  local function write(path, bytes)
    local fd = assert(vim.uv.fs_open(root .. "/" .. path, "w", 420))
    assert(vim.uv.fs_write(fd, bytes, 0)); vim.uv.fs_close(fd)
  end
  local dv, lib
  local function open(args, path, kind)
    dv.open(args)
    local state, last_error
    assert(vim.wait(10000, function()
      local view = lib.get_current_view()
      if not view or not view.cur_layout or not view.cur_layout.b then return false end
      local win = view.cur_layout.b.id
      state, last_error = adapter.current(win)
      return state and state.selected.path == path and (not kind or state.selected.kind == kind)
    end, 20), last_error or "Diffview never loaded")
    return state, lib.get_current_view()
  end
  local function collect(win, scope)
    local snapshot, err = diff.collect(win, scope or "file")
    assert(snapshot, err)
    return snapshot
  end
  local function options(state)
    local result = {}
    for _, side in ipairs({ "old", "new" }) do
      result[side] = {}
      for _, key in ipairs({ "diff", "scrollbind", "cursorbind", "wrap", "foldmethod", "foldenable", "winbar" }) do
        result[side][key] = api.nvim_get_option_value(key, { win = state.windows[side] })
      end
    end
    return result
  end
  local ok, err = xpcall(function()
    git("init", "-q"); git("config", "user.name", "Offline fixture"); git("config", "user.email", "offline@example.invalid")
    write("code.lua", "base\nunchanged\n"); write("doc.md", "rationale\nbase\n")
    git("add", "--all"); git("commit", "-qm", "base"); local a = git("rev-parse", "HEAD")
    write("code.lua", "committed\nunchanged\n"); write("doc.md", "rationale\ncommitted\n")
    git("add", "--all"); git("commit", "-qm", "new"); local b = git("rev-parse", "HEAD")
    write("code.lua", "unrelated local\nunchanged\n")
    dv, lib = require("diffview"), require("diffview.lib")
    dv.setup({ watch_index = false, use_icons = false })
    api.nvim_set_current_dir(root)
    local state, view = open({ a .. ".." .. b, "--selected-file=" .. root .. "/code.lua" }, "code.lua")
    local roles = {}
    api.nvim_win_call(state.source, function()
      require("diffview.actions").view_windo(function(_, symbol) roles[symbol] = api.nvim_get_current_win() end)()
    end)
    T.eq(roles.a, state.windows.old); T.eq(roles.b, state.windows.new)
    local before_options = options(state)
    local s = collect(state.windows.new)
    T.eq(a, s.comparison.identities.old.commit); T.eq(b, s.comparison.identities.new.commit)
    T.eq(state.windows.new, s.source)
    T.eq(state.panes.new.buf, s.source_buf)
    T.eq(true, diff.fresh(s)); T.eq(before_options, options(state))
    -- A notes window is never registered into a Diffview layout; revalidate
    -- using the retained source ID while the notes window has keyboard focus.
    vim.cmd("botright vsplit")
    local notes = api.nvim_get_current_win()
    local notes_buf = api.nvim_create_buf(false, true)
    api.nvim_win_set_buf(notes, notes_buf)
    local followed = assert(adapter.current(s.source))
    T.eq(s.source, followed.source); T.eq(nil, adapter.current(notes))
    T.eq(true, diff.fresh(s)); T.eq(notes, api.nvim_get_current_win())
    api.nvim_win_close(notes, true); api.nvim_buf_delete(notes_buf, { force = true })
    -- Guard private metadata changes and partial/asynchronous pane states.
    local original_rev = view.cur_entry.revs.a
    for _, unsupported in ipairs({ { type = 4 }, { type = 3, stage = 2 } }) do
      view.cur_entry.revs.a = unsupported
      local unavailable, message = adapter.current(s.source)
      T.eq(nil, unavailable); assert(message:find("unsupported", 1, true), message)
    end
    view.cur_entry.revs.a = original_rev
    local item = view.cur_layout.b.file
    local file_buf = item.bufnr
    item.bufnr = state.panes.old.buf
    local unavailable, message = adapter.current(s.source)
    T.eq(nil, unavailable); assert(message:find("loading", 1, true), message)
    item.bufnr = file_buf
    local conflict_kind = view.cur_entry.kind; view.cur_entry.kind = "conflicting"
    unavailable, message = adapter.current(s.source)
    T.eq(nil, unavailable); assert(message:find("conflict", 1, true), message)
    view.cur_entry.kind = conflict_kind
    local document
    for _, entry in view.files:iter() do if entry.path == "doc.md" then document = entry end end
    local document_rev = document.revs.a
    document.revs.a = document.revs.b
    unavailable, message = adapter.current(s.source)
    T.eq(nil, unavailable); assert(message:find("ambiguous mixed pairs", 1, true), message)
    document.revs.a = document_rev
    view:set_file(assert(document), false, true)
    assert(vim.wait(10000, function()
      local next_state = adapter.current(view.cur_layout.b.id)
      return next_state and next_state.selected.path == "doc.md"
    end, 20))
    T.eq(true, diff.fresh(s)) -- Selection changes display, not comparison content.
    dv.close(); T.eq(false, diff.fresh(s))
    -- Both staged and working sets are in this real view, but their endpoint
    -- pairs must never be combined or replaced with a default `git diff`.
    write("code.lua", "staged\nunchanged\n"); git("add", "--", "code.lua")
    write("code.lua", "working\nunchanged\n")
    state, view = open({ "--selected-file=" .. root .. "/code.lua" }, "code.lua", "working")
    local wait, marker = vim.wait, false
    vim.schedule(function() marker = true end)
    vim.wait = function() error("adapter snapshot must not pump editor events") end
    local immediate, immediate_error = adapter.current(state.source)
    vim.wait = wait
    assert(immediate, immediate_error); T.eq(false, marker)
    T.eq(true, immediate.show_untracked)
    s = collect(state.source)
    T.eq("stage", s.comparison.identities.old.type); T.eq("local", s.comparison.identities.new.type)
    T.eq("staged", s.comparison.manifest[1].old.lines[1]); T.eq("working", s.comparison.manifest[1].new.lines[1])
    api.nvim_buf_set_lines(state.panes.new.buf, 0, 1, false, { "unsaved working" })
    T.eq(false, diff.fresh(s)); s = collect(state.source)
    T.eq("unsaved working", s.comparison.manifest[1].new.lines[1])
    local staged
    for _, entry in view.files:iter() do if entry.path == "code.lua" and entry.kind == "staged" then staged = entry end end
    assert(staged, "real Diffview did not expose staged set")
    view:set_file(staged, false, true)
    assert(vim.wait(10000, function()
      state = adapter.current(view.cur_layout.b.id)
      return state and state.selected.kind == "staged"
    end, 20))
    T.eq(false, diff.fresh(s)); s = collect(state.source)
    T.eq("commit", s.comparison.identities.old.type); T.eq("stage", s.comparison.identities.new.type)
    T.eq("committed", s.comparison.manifest[1].old.lines[1]); T.eq("staged", s.comparison.manifest[1].new.lines[1])
    api.nvim_buf_set_lines(state.panes.new.buf, 0, 1, false, { "unsaved index" })
    T.eq(false, diff.fresh(s)); s = collect(state.source)
    T.eq("unsaved index", s.comparison.manifest[1].new.lines[1])
    print("REAL Diffview verified a=" .. state.windows.old .. " b=" .. state.windows.new
      .. "; notes follow retained source; commits + staged + working + unsaved index")
    dv.close()
  end, debug.traceback)
  if not ok then print(err) end
  if dv then pcall(dv.close) end
  if api.nvim_win_is_valid(start) then api.nvim_set_current_win(start); api.nvim_win_set_buf(start, start_buf) end
  api.nvim_set_current_dir(start_cwd); vim.o.columns = old_columns
  for _, buf in ipairs(api.nvim_list_bufs()) do
    if api.nvim_buf_is_valid(buf) and api.nvim_buf_get_name(buf):find(root, 1, true) then
      api.nvim_buf_delete(buf, { force = true })
    end
  end
  vim.fn.delete(root, "rf")
  assert(ok, err)
end)

T.test("real Diffview navigation and explorer keymaps work in pending notes and recreated details", function()
  local plugin = require("irrelevant_explainer")
  local old_leader, old_columns = vim.g.mapleader, vim.o.columns
  vim.g.mapleader, vim.o.columns = ",", 220
  local fixture = dofile("tests/review.lua").open(true)
  local actions = require("diffview.actions")
  local function lhs(key) return key:gsub("<leader>", vim.g.mapleader) end
  local function mapping(pane, key)
    return api.nvim_win_call(pane.win, function() return vim.fn.maparg(lhs(key), "n", false, true) end)
  end
  local function press(pane, key)
    api.nvim_set_current_win(pane.win)
    api.nvim_feedkeys(api.nvim_replace_termcodes(lhs(key), true, false, true), "xt", false)
  end
  local function prepare()
    plugin.close(); fixture:switch("policy.lua")
    local session = plugin.explain("file")
    T.eq(nil, session.pane.pending.snapshot)
    return session
  end
  local function ready(session)
    assert(vim.wait(5000, function() return session.pane.status:match("^Ready") ~= nil end), session.pane.status)
  end
  -- Fixture cwd is a disposable repository; the process fixture lives in ours.
  plugin.setup({ ai = { command = { "python3", fixture.cwd .. "/tests/fixtures/agent.py", "explain" }, output = "plain" } })
  local ok, err = xpcall(function()
    vim.v.errmsg = ""
    for _, expanded in ipairs({ false, true }) do
      local session = prepare()
      for _, key in ipairs({ "<Tab>", "<S-Tab>", "<leader>e", "<leader>b" }) do assert(next(mapping(session.pane, key))) end
      ready(session)
      local pane = session.pane
      api.nvim_set_current_win(pane.win); api.nvim_win_set_cursor(pane.win, { 1, 0 })
      if expanded then press(pane, "<CR>"); assert(pane.detail_buf) end
      press(pane, "<leader>e"); assert(fixture.view.panel:is_focused())
      press(pane, "<leader>b"); T.eq(false, fixture.view.panel:is_open())
      press(pane, "<leader>b"); assert(fixture.view.panel:is_open())
      press(pane, "<Tab>")
      assert(vim.wait(5000, function() return fixture.view.cur_entry.path ~= "policy.lua" end))
      assert(vim.wait(5000, function() return pane.status:match("^No explanations") ~= nil end), pane.status)
      T.eq(nil, pane.result); T.eq(nil, pane.detail_buf)
      assert(vim.wait(5000, function()
        local state = adapter.current(pane.source)
        return state and state.selected.path ~= "policy.lua"
          and api.nvim_buf_line_count(api.nvim_win_get_buf(pane.source)) == api.nvim_buf_line_count(pane.buf)
      end), "replacement sources and notes did not finish loading")
      T.eq("", vim.v.errmsg)
      press(pane, "<S-Tab>")
      assert(vim.wait(5000, function() return fixture.view.cur_entry.path == "policy.lua" end))
      ready(session); T.eq("Ready · restored", pane.status); assert(pane.result)
      T.eq(nil, require("diffview.vcs.file").File.attached[pane.buf])
    end
    plugin.close(); fixture:switch("policy.lua")
    local focused = 0
    require("diffview").setup({ watch_index = false, use_icons = false, keymaps = {
      view = {
        ["<tab>"] = false, ["<s-tab>"] = false,
        { "n", "]f", actions.select_next_entry }, { "n", "[f", actions.select_prev_entry },
        { "n", "<leader>e", function() focused = focused + 1; actions.focus_files() end },
        { "n", "<CR>", actions.select_next_entry },
      },
      diff2 = { { "n", "<leader>b", "<Cmd>lua require('diffview.actions').toggle_files()<CR>",
        { nowait = false, silent = false, desc = "Custom explorer toggle" } } },
    } })
    local session = prepare(); ready(session)
    local pane = session.pane
    T.eq({}, mapping(pane, "<Tab>")); T.eq({}, mapping(pane, "<S-Tab>")); T.eq({}, mapping(pane, "gf"))
    T.eq(actions.select_next_entry, mapping(pane, "]f").callback)
    T.eq(actions.select_prev_entry, mapping(pane, "[f").callback)
    local toggle = mapping(pane, "<leader>b")
    T.eq("Custom explorer toggle", toggle.desc); T.eq(0, toggle.nowait); T.eq(0, toggle.silent)
    api.nvim_set_current_win(pane.win); api.nvim_win_set_cursor(pane.win, { 1, 0 })
    press(pane, "<CR>"); assert(pane.detail_buf); T.eq("policy.lua", fixture.view.cur_entry.path)
    T.eq({}, mapping(pane, "<Tab>")); T.eq({}, mapping(pane, "<S-Tab>"))
    press(pane, "<leader>e"); T.eq(1, focused); assert(fixture.view.panel:is_focused())
    press(pane, "<leader>b"); T.eq(false, fixture.view.panel:is_open())
    press(pane, "<leader>b"); assert(fixture.view.panel:is_open())
    press(pane, "n"); assert(pane.detail_buf)
    T.eq("Custom explorer toggle", mapping(pane, "<leader>b").desc)
    press(pane, "K"); T.eq(nil, pane.detail_buf)
    press(pane, "]f"); assert(vim.wait(5000, function() return fixture.view.cur_entry.path ~= "policy.lua" end))
    press(pane, "[f"); assert(vim.wait(5000, function() return fixture.view.cur_entry.path == "policy.lua" end))
    plugin.close(); fixture:switch("policy.lua")
    local code = require("irrelevant_explainer.session").start("code", "file"); ready(code)
    T.eq({}, mapping(code.pane, "<Tab>")); T.eq({}, mapping(code.pane, "<leader>e"))
    T.eq("", vim.v.errmsg)
  end, debug.traceback)
  fixture:close(); vim.g.mapleader, vim.o.columns = old_leader, old_columns
  assert(ok, err)
end)

T.test("real Diffview closure cancels expanded session work immediately in foreground and background tabs", function()
  local plugin, sessions, agent = require("irrelevant_explainer"), require("irrelevant_explainer.session"), require("irrelevant_explainer.agent")
  local old_run, schedule, old_columns = agent.run, vim.schedule, vim.o.columns
  local jobs, deferred, errors = {}, {}, {}
  agent.run = function(prompt, _, _, callback)
    local job = { target = vim.json.decode(prompt:match("FOCUSED TARGET JSON:\n(.*)")), callback = callback }
    job.cancel = function() job.cancelled = true end
    jobs[#jobs + 1] = job
    return job
  end
  local function answer(job)
    job.callback({ version = 1, notes = { { summary = "Read the permission change", detail = "Preserve the owner check.",
      intent_basis = "unknown", anchors = { job.target.anchors[1] }, evidence = {} } } })
  end
  vim.o.columns = 220
  local fixture, other
  local ok, err = xpcall(function()
    for _, background in ipairs({ false, true }) do
      fixture = dofile("tests/review.lua").open(true)
      plugin.setup({ cache = { enabled = false } })
      vim.cmd("runtime plugin/diffview.lua")
      vim.v.errmsg = ""
      local before = #jobs
      local s = plugin.explain("file")
      assert(vim.wait(5000, function() return #jobs == before + 1 end))
      answer(jobs[#jobs])
      assert(vim.wait(5000, function() return s.pane.status:match("^Ready") end), s.pane.status)
      local accepted = vim.deepcopy(s.pane.result)
      api.nvim_win_set_cursor(fixture.state.source, { 4, 0 })
      plugin.explain("hunk")
      assert(vim.wait(5000, function() return #jobs == before + 2 end))
      local active = jobs[#jobs]
      api.nvim_win_set_cursor(fixture.state.source, { 8, 0 })
      plugin.explain("hunk")
      local queued = s.queue[1].collection
      assert(queued)
      api.nvim_set_current_win(s.pane.win); s.pane:detail(1)
      local detail, summary = s.pane.detail_buf, s.pane.buf
      assert(detail)
      if background then
        vim.cmd("tabnew")
        api.nvim_buf_set_lines(0, 0, -1, false, { "unrelated tab" })
        other = plugin.explain("file")
      end
      local current = api.nvim_get_current_tabpage()
      local other_job = background and jobs[#jobs]
      -- Hold session/UI callbacks only: Diffview itself still runs normally.
      -- This proves cancellation is owned by the closure event, not a later
      -- WinClosed cleanup or freshness poll, and replays queued geometry late.
      vim.schedule = function(callback)
        local source = debug.getinfo(callback, "S").source
        if source:find("/irrelevant_explainer/ui.lua", 1, true) or source:find("/irrelevant_explainer/session.lua", 1, true) then
          deferred[#deferred + 1] = callback
        else schedule(callback) end
      end
      api.nvim_exec_autocmds("WinResized", {})
      if background then
        fixture.view:close()
        require("diffview.lib").dispose_view(fixture.view)
      else vim.cmd("DiffviewClose") end
      T.eq(true, s.closed); T.eq(nil, s.pending); T.eq(nil, s.invocation); T.eq(nil, s.timer)
      T.eq(true, active.cancelled); T.eq(true, queued.cancelled)
      T.eq(0, #s.queue); T.eq(nil, sessions.sessions[s.tab])
      T.eq(false, api.nvim_buf_is_valid(detail)); T.eq(false, api.nvim_buf_is_valid(summary))
      T.eq(0, vim.fn.exists("#IrrelevantExplainerPane" .. s.pane.win))
      T.eq(0, vim.fn.exists("#IrrelevantExplainerSession" .. s.pane.win))
      if background then
        T.eq(current, api.nvim_get_current_tabpage()); T.eq(other, sessions.current())
        T.eq(nil, other.closed); T.eq(nil, other_job.cancelled)
      end
      vim.schedule = schedule
      active.callback(nil, "late closed failure")
      for _, callback in ipairs(deferred) do
        local success, failure = xpcall(callback, debug.traceback)
        if not success then errors[#errors + 1] = failure end
      end
      deferred = {}
      vim.wait(30)
      T.eq(accepted, s.pane.result); T.eq({}, errors); T.eq("", vim.v.errmsg)
      if other then plugin.close(); vim.cmd("tabclose!"); other = nil end
      fixture:close(); fixture = nil
    end
  end, debug.traceback)
  vim.schedule = schedule
  if other then sessions.close(other); vim.cmd("tabclose!") end
  if fixture then fixture:close() end
  agent.run, vim.o.columns = old_run, old_columns
  assert(ok, err)
end)

local function replacement_reader(geometry_first)
  local plugin, sessions, agent = require("irrelevant_explainer"), require("irrelevant_explainer.session"), require("irrelevant_explainer.agent")
  local old_run, schedule, old_columns = agent.run, vim.schedule, vim.o.columns
  local jobs, deferred, errors = {}, {}, {}
  agent.run = function(prompt, _, _, callback)
    local job = { target = vim.json.decode(prompt:match("FOCUSED TARGET JSON:\n(.*)")), callback = callback }
    job.cancel = function() job.cancelled = true end
    jobs[#jobs + 1] = job
    return job
  end
  local function answer(job)
    job.callback({ version = 1, notes = { { summary = "Read " .. job.target.path, detail = "Read the captured file.",
      intent_basis = "unknown", anchors = { job.target.anchors[1] }, evidence = {} } } })
  end
  vim.o.columns = 220
  local fixture = dofile("tests/review.lua").open(true)
  local ok, err = xpcall(function()
    plugin.setup({ cache = { enabled = false } })
    local s = plugin.explain("file")
    assert(vim.wait(5000, function() return #jobs == 1 end))
    answer(jobs[1])
    assert(vim.wait(5000, function() return s.pane.status:match("^Ready") end), s.pane.status)
    api.nvim_win_set_cursor(fixture.state.source, { 4, 0 }); plugin.explain("hunk")
    assert(vim.wait(5000, function() return #jobs == 2 end))
    local active = jobs[2]
    api.nvim_set_current_win(s.pane.win); s.pane:detail(1)
    local detail = s.pane.detail_buf
    local overview_lines = api.nvim_buf_line_count(s.pane.buf)
    api.nvim_win_set_cursor(s.pane.win, { api.nvim_buf_line_count(detail), 0 })
    vim.wait(100)
    assert(vim.wait(5000, function() return not s.checking end))
    s.timer:stop() -- No polling can bypass the deliberately held follow event.
    vim.v.errmsg = ""
    vim.schedule = function(callback)
      local source = debug.getinfo(callback, "S").source
      if source:find("/irrelevant_explainer/ui.lua", 1, true) or source:find("/irrelevant_explainer/session.lua", 1, true) then
        deferred[#deferred + 1] = { callback = callback, ui = source:find("/irrelevant_explainer/ui.lua", 1, true) ~= nil }
      else schedule(callback) end
    end
    api.nvim_exec_autocmds("WinResized", {})
    fixture:switch("openspec/spec.md")
    T.eq("policy.lua", s.snapshot.target.path); T.eq(detail, s.pane.detail_buf)
    local cursors = {}
    for _, win in pairs(fixture.state.windows) do
      api.nvim_win_set_cursor(win, { 1, 2 }); cursors[win] = api.nvim_win_get_cursor(win)
    end
    -- Replay geometry while the old reader is still expanded and follow is
    -- deliberately deferred. Window IDs are unchanged; buffer IDs are not.
    if geometry_first then
      for _, item in ipairs(deferred) do
        if item.ui then
          local success, failure = xpcall(item.callback, debug.traceback)
          if not success then errors[#errors + 1] = failure end
        end
      end
      T.eq(overview_lines, api.nvim_buf_line_count(s.pane.buf))
    end
    T.eq({}, errors)
    for win, cursor in pairs(cursors) do T.eq(cursor, api.nvim_win_get_cursor(win)) end
    -- An explicit request must also beat the deferred follow safely. Invoke
    -- from notes so it resolves the retained source, not a Markdown cursor.
    api.nvim_set_current_win(s.pane.win)
    local replacement = plugin.explain("file")
    T.eq(s, replacement); T.eq(nil, s.closed); T.eq(nil, active.cancelled)
    T.eq(nil, s.pane.detail_buf)
    T.eq(1, replacement.queue[1].row); T.eq(nil, replacement.pane.result)
    for win, cursor in pairs(cursors) do T.eq(cursor, api.nvim_win_get_cursor(win)) end
    vim.schedule = schedule
    for _, item in ipairs(deferred) do
      if not geometry_first or not item.ui then item.callback() end
    end
    answer(active) -- Off-screen success is retained, then B starts.
    assert(vim.wait(5000, function() return #jobs == 3 end), replacement.pane.status)
    T.eq("openspec/spec.md", jobs[3].target.path)
    answer(jobs[3])
    assert(vim.wait(5000, function() return replacement.pane.status:match("^Ready") end), replacement.pane.status)
    T.eq(replacement, sessions.current()); T.eq(1, #replacement.batches)
    T.eq(false, api.nvim_buf_is_valid(detail)); T.eq("", vim.v.errmsg)
  end, debug.traceback)
  vim.schedule = schedule
  fixture:close(); agent.run, vim.o.columns = old_run, old_columns
  assert(ok, err)
end

T.test("real Diffview new request collapses an old reader without navigating replacement panes before follow", function()
  replacement_reader(false)
end)

T.test("real Diffview queued geometry rejects replacement buffers before deferred follow", function()
  replacement_reader(true)
end)

T.test("Diffview restores per-file explanations without inference and rejects changed review context", function()
  local plugin, agent = require("irrelevant_explainer"), require("irrelevant_explainer.agent")
  local old_run, calls = agent.run, 0
  local old_restore = diff.restore_async
  agent.run = function(...) calls = calls + 1; return old_run(...) end
  local old_columns = vim.o.columns
  vim.o.columns = 220
  local fixture
  local function ready(session, path)
    assert(vim.wait(5000, function()
      return session.pane.status:match("^Ready") ~= nil
        and (not path or session.snapshot and session.snapshot.target.path == path)
    end), session.pane.status)
  end
  local ok, err = xpcall(function()
    for _, case in ipairs({ { true, "review", "hunk" }, { true, "focused", "hunk" }, { false, "review", "file" } }) do
      fixture = dofile("tests/review.lua").open(case[1])
      if case[2] == "focused" then fixture:write("tests/policy.txt", string.rep("Unrelated test context\n", 20000)) end
      plugin.setup({ ai = { command = { "python3", fixture.cwd .. "/tests/fixtures/agent.py", "explain" }, output = "plain" },
        context = { diff = case[2], radius = 2 } })
      api.nvim_win_set_cursor(fixture.state.source, { 4, 0 })
      local session = plugin.explain(case[3]); ready(session)
      if case[3] == "hunk" then
        api.nvim_set_current_win(fixture.state.windows.old); api.nvim_win_set_cursor(fixture.state.windows.old, { 9, 0 })
        T.eq(session, plugin.explain("hunk")); ready(session); T.eq(2, #session.batches)
      end
      local accepted, snapshots = vim.deepcopy(session.pane.result), vim.deepcopy(session.batches)
      local original_batches = session.batches
      local count = calls
      fixture:switch("openspec/spec.md")
      assert(vim.wait(5000, function() return session.pane.status:match("^No explanations") ~= nil end), session.pane.status)
      T.eq(nil, session.pane.result); T.eq(count, calls)
      -- A clean reload advances changedtick without changing the code/context.
      if case[1] then
        local buf = snapshots[1].snapshot.capture.state.panes.new.buf
        api.nvim_buf_set_lines(buf, 0, -1, false, api.nvim_buf_get_lines(buf, 0, -1, false))
        vim.bo[buf].modified = false
      end
      local document = plugin.explain("file"); ready(document)
      local document_result = vim.deepcopy(document.pane.result)
      T.eq(count + 1, calls)
      fixture:switch("policy.lua"); ready(document, "policy.lua")
      T.eq("Ready · restored", document.pane.status); T.eq(accepted, document.pane.result)
      T.eq(#snapshots, #document.batches); T.eq(count + 1, calls)
      T.eq(snapshots, original_batches)
      T.eq("policy.lua", document.snapshot.target.path)
      T.eq(fixture.state.windows, document.snapshot.windows)
      fixture:switch("openspec/spec.md"); ready(document, "openspec/spec.md")
      T.eq(document_result, document.pane.result); T.eq(count + 1, calls)
      if case[1] and case[2] == "review" then
        local delayed = {}
        diff.restore_async = function(snapshot, source, callback)
          return old_restore(snapshot, source, function(value)
            delayed[#delayed + 1] = { value = value, callback = callback }
          end)
        end
        fixture:switch("policy.lua")
        assert(vim.wait(5000, function() return #delayed == 1 end))
        T.eq("Checking saved explanations", document.pane.status)
        T.eq(true, document.pane.restoring); T.eq(nil, document.pane.pending)
        assert(document.pane.timer)
        assert(#api.nvim_buf_get_extmarks(document.pane.buf, api.nvim_create_namespace("irrelevant_explainer.loading"),
          0, -1, {}) > 0)
        fixture:switch("openspec/spec.md")
        assert(vim.wait(5000, function() return #delayed == 2 end))
        delayed[1].callback(delayed[1].value)
        T.eq(nil, document.pane.result) -- Obsolete A cannot install in B.
        T.eq("Checking saved explanations", document.pane.status)
        T.eq("openspec/spec.md", fixture.view.cur_entry.path)
        delayed[2].callback(delayed[2].value); ready(document, "openspec/spec.md")
        T.eq(document_result, document.pane.result); T.eq(count + 1, calls)
        T.eq(nil, document.pane.timer); assert(not document.pane.restoring)
        T.eq({}, api.nvim_buf_get_extmarks(document.pane.buf, api.nvim_create_namespace("irrelevant_explainer.loading"), 0, -1, {}))
        diff.restore_async = old_restore
      end
      if case[1] then
        if case[2] == "focused" then
          local buf = api.nvim_create_buf(false, false)
          api.nvim_buf_set_name(buf, fixture.root .. "/tests/policy.txt")
          api.nvim_buf_set_lines(buf, 0, -1, false, { "Unsaved change in an omitted review file." })
        else fixture:write("docs/adr.md", "Rationale changed while reviewing another file.\n") end
        fixture:switch("policy.lua")
        assert(vim.wait(5000, function() return document.pane.status:match("^Stale") ~= nil end), document.pane.status)
        T.eq(nil, document.pane.result); T.eq(count + 1, calls)
      else
        fixture:write("docs/adr.md", "Working changes do not alter a fixed two-commit comparison.\n")
        fixture:git("add", "docs/adr.md")
        fixture:switch("policy.lua"); ready(document, "policy.lua")
        T.eq(accepted, document.pane.result); T.eq(count + 1, calls)
      end
      fixture:close(); fixture = nil
    end
    T.eq("", vim.v.errmsg)
  end, debug.traceback)
  if fixture then fixture:close() end
  diff.restore_async = old_restore
  agent.run, vim.o.columns = old_run, old_columns
  assert(ok, err)
end)

T.test("opt-in Diffview navigation requests files once while open and reuses or revalidates saved notes", function()
  local plugin, agent = require("irrelevant_explainer"), require("irrelevant_explainer.agent")
  local old_run, old_notify, old_columns = agent.run, vim.notify, vim.o.columns
  local jobs, errors = {}, {}
  agent.run = function(prompt, _, _, callback)
    local job = { target = vim.json.decode(prompt:match("FOCUSED TARGET JSON:\n(.*)")), callback = callback }
    job.cancel = function() job.cancelled = true end
    jobs[#jobs + 1] = job
    return job
  end
  vim.notify = function(message) errors[#errors + 1] = message end
  vim.o.columns = 220
  local fixture = dofile("tests/review.lua").open(true)
  local function job(count)
    assert(vim.wait(5000, function() return #jobs >= count end), "automatic request was not launched")
    T.eq(count, #jobs)
    return jobs[count]
  end
  local function answer(request)
    request.callback({ version = 1, notes = { { summary = "Explains " .. request.target.path,
      detail = "Fixture explanation.", anchors = { request.target.anchors[1] }, intent_basis = "unknown", evidence = {} } } })
  end
  local function ready(session, path)
    assert(vim.wait(5000, function()
      return session.pane.status:match("^Ready") and session.snapshot and session.snapshot.target.path == path
    end), session.pane.status)
  end
  local function events()
    for _ = 1, 4 do
      api.nvim_exec_autocmds("User", { pattern = "DiffviewDiffBufWinEnter" })
      api.nvim_exec_autocmds("User", { pattern = "DiffviewViewPostLayout" })
    end
    vim.wait(1100) -- Include a freshness poll: no repeated automatic inference.
  end
  local ok, err = xpcall(function()
    plugin.setup({ cache = { enabled = false }, diff = { auto_explain = true } })
    fixture:switch("openspec/spec.md"); events()
    T.eq(0, #jobs); T.eq(nil, require("irrelevant_explainer.session").current())
    fixture:switch("policy.lua")
    api.nvim_win_set_cursor(fixture.state.source, { 4, 0 })
    local session = plugin.explain("hunk"); answer(job(1)); ready(session, "policy.lua")
    local pane_win, accepted = session.pane.win, vim.deepcopy(session.pane.result)
    fixture:switch("openspec/spec.md")
    local automatic = job(2)
    T.eq("file", automatic.target.scope); T.eq("openspec/spec.md", automatic.target.path)
    local generation = session.generation
    events(); T.eq(2, #jobs); T.eq(generation, session.generation); T.eq(nil, automatic.cancelled)
    answer(automatic); ready(session, "openspec/spec.md")
    T.eq(pane_win, session.pane.win); T.eq(fixture.state.source, api.nvim_get_current_win())
    fixture:switch("policy.lua"); ready(session, "policy.lua")
    T.eq("Ready · restored", session.pane.status); T.eq(accepted, session.pane.result); T.eq(2, #jobs)
    fixture:switch("openspec/spec.md"); ready(session, "openspec/spec.md"); T.eq(2, #jobs)
    fixture:write("docs/adr.md", "Changed decision context.\n")
    assert(vim.wait(5000, function() return session.pane.status:match("^Stale") end))
    T.eq(2, #jobs) -- Edits on the current file do not auto-request.
    fixture:switch("policy.lua")
    local changed = job(3); T.eq("file", changed.target.scope)
    answer(changed); ready(session, "policy.lua") -- Stale saved notes are re-explained on navigation.
    fixture:switch("docs/adr.md"); local abandoned = job(4)
    fixture:switch("tests/policy.txt"); events(); T.eq(4, #jobs)
    T.eq(nil, abandoned.cancelled)
    answer(abandoned); T.eq(nil, session.pane.result)
    local current = job(5)
    answer(current); ready(session, "tests/policy.txt")
    fixture:switch("docs/adr.md")
    ready(session, "docs/adr.md"); T.eq(5, #jobs)
    plugin.refresh()
    job(6).callback(nil, "Fixture provider failure")
    assert(vim.wait(5000, function() return session.pane.status:match("^Failed") end))
    events(); T.eq(6, #jobs); T.eq("docs/adr.md: Fixture provider failure", errors[#errors])
    plugin.cancel(); events(); T.eq(6, #jobs)
    plugin.close(); fixture:switch("policy.lua"); events()
    T.eq(6, #jobs); T.eq(nil, require("irrelevant_explainer.session").current())
    T.eq("", vim.v.errmsg)
  end, debug.traceback)
  fixture:close(); plugin.setup()
  agent.run, vim.notify, vim.o.columns = old_run, old_notify, old_columns
  assert(ok, err)
end)

local function toggle_fixture(run)
  local plugin, agent = require("irrelevant_explainer"), require("irrelevant_explainer.agent")
  local old_run, old_notify, old_columns = agent.run, vim.notify, vim.o.columns
  local old_current, old_restore = adapter.current, diff.restore_async
  local f = { jobs = {} }
  agent.run = function(prompt, _, _, callback)
    local job = { target = vim.json.decode(prompt:match("FOCUSED TARGET JSON:\n(.*)")), callback = callback }
    job.cancel = function() job.cancelled = true end
    f.jobs[#f.jobs + 1] = job
    return job
  end
  vim.notify = function() end
  vim.o.columns = 220
  local fixture = dofile("tests/review.lua").open(true)
  function f.job(count)
    assert(vim.wait(5000, function() return #f.jobs >= count end), "expected request " .. count)
    T.eq(count, #f.jobs); return f.jobs[count]
  end
  function f.answer(job)
    job.callback({ version = 1, notes = { { summary = "Explains " .. job.target.path,
      detail = "First paragraph.\n\nSecond paragraph.", anchors = { job.target.anchors[1] }, intent_basis = "unknown", evidence = {} } } })
  end
  function f.ready(session, path)
    assert(vim.wait(5000, function()
      return session.pane.status:match("^Ready") and session.snapshot and session.snapshot.target.path == path
    end), session.pane.status)
  end
  function f.events()
    api.nvim_exec_autocmds("User", { pattern = "DiffviewViewPostLayout" })
    api.nvim_exec_autocmds("User", { pattern = "DiffviewDiffBufWinEnter" })
    vim.wait(1100)
  end
  local ok, err = xpcall(function() run(f, fixture, plugin) end, debug.traceback)
  adapter.current, diff.restore_async = old_current, old_restore
  fixture:close(); plugin.setup()
  agent.run, vim.notify, vim.o.columns = old_run, old_notify, old_columns
  assert(ok, err)
end

T.test("notes navigation preserves source window defaults for unopened Diffview files", function()
  for _, expanded in ipairs({ false, true }) do
    toggle_fixture(function(f, fixture, plugin)
      plugin.setup({ cache = { enabled = false } })
      local source = fixture.state.source
      local expected = { number = true, relativenumber = true, wrap = false, signcolumn = "auto:2", statuscolumn = "" }
      for name, value in pairs(expected) do vim.wo[source][name] = value end
      -- Establish native inheritance before IrrelevantExplainer, keeping the destination
      -- file unopened so Diffview must load it through its temporary window.
      fixture:switch("docs/adr.md")
      for name, value in pairs(expected) do T.eq(value, vim.wo[fixture.state.source][name]) end
      fixture:switch("policy.lua")
      local s = plugin.explain("file"); f.answer(f.job(1)); f.ready(s, "policy.lua")
      local p = s.pane
      api.nvim_set_current_win(p.win)
      if expanded then p:detail(1) end
      T.eq(false, vim.wo[p.win].number); T.eq(false, vim.wo[p.win].relativenumber)
      fixture:switch("openspec/spec.md")
      assert(vim.wait(5000, function() return not s.restoring and p.status:match("^No explanations") end))
      for name, value in pairs(expected) do T.eq(value, vim.wo[fixture.state.source][name]) end
      -- Returning from detail must not contaminate defaults either.
      api.nvim_set_current_win(p.win)
      fixture:switch("tests/policy.txt")
      for name, value in pairs(expected) do T.eq(value, vim.wo[fixture.state.source][name]) end
    end)
  end
end)

for _, auto in ipairs({ false, true }) do
  for _, collapse in ipairs({ false, true }) do
    T.test(string.format("explorer file selection isolates detail gutters (auto=%s, collapsed=%s)", auto, collapse), function()
      toggle_fixture(function(f, fixture, plugin)
        plugin.setup({ cache = { enabled = false } })
        local actions, panel = require("diffview.actions"), fixture.view.panel
        local gutters = { [fixture.state.windows.old] = "L ", [fixture.state.windows.new] = "R ",
          [panel.winid] = "T " }
        for win, gutter in pairs(gutters) do vim.wo[win].statuscolumn = gutter end
        local function select(path)
          actions.focus_files(); T.eq(panel.winid, api.nvim_get_current_win())
          local entry
          for _, item in ipairs(panel:ordered_file_list()) do if item.path == path then entry = item; break end end
          panel:highlight_file(assert(entry)); T.eq(entry, panel:get_item_at_cursor())
          actions.select_entry()
          assert(vim.wait(5000, function()
            fixture.state = adapter.current(fixture.view.cur_layout.b.id)
            return fixture.state and fixture.state.selected.path == path
          end), "explorer selection did not load " .. path)
          T.eq(panel.winid, api.nvim_get_current_win())
        end
        -- Diffview first loads working files in a temporary explorer-derived
        -- window. Compare native inheritance without IrrelevantExplainer, leaving the
        -- actual destination unopened for the regression below.
        select("docs/adr.md")
        local native_gutters = {}
        for win in pairs(gutters) do native_gutters[win] = vim.wo[win].statuscolumn end
        select("policy.lua")
        api.nvim_set_current_win(fixture.state.source)
        local s = plugin.explain("file"); f.answer(f.job(1)); f.ready(s, "policy.lua")
        local p, accepted = s.pane, vim.deepcopy(s.pane.result)
        vim.wo[p.win].statuscolumn = "O "
        local observed, errors = {}, {}
        local watch = api.nvim_create_autocmd("BufWinEnter", { callback = function()
          local win = api.nvim_get_current_win()
          if api.nvim_get_current_tabpage() ~= fixture.view.tabpage then return end
          local gutter = vim.wo[win].statuscolumn
          observed[#observed + 1] = { win = win, gutter = gutter }
          api.nvim_eval_statusline(gutter, { winid = win, use_statuscol_lnum = 1 })
          if vim.v.errmsg ~= "" then errors[#errors + 1] = vim.v.errmsg end
        end })
        local ok, err = xpcall(function()
          vim.v.errmsg = ""
          for visit = 1, 2 do
            api.nvim_set_current_win(p.win); p:detail(1)
            local detail = p.detail_buf
            if collapse then p:back() end
            if auto and visit == 1 then
              T.eq(true, plugin.toggle_auto_explain()); f.events(); T.eq(1, #f.jobs)
            end
            select("openspec/spec.md")
            if auto then
              if visit == 1 then
                local request = f.job(2)
                T.eq("file", request.target.scope); T.eq("openspec/spec.md", request.target.path)
                f.answer(request)
              end
              f.ready(s, "openspec/spec.md")
            else
              assert(vim.wait(5000, function() return not s.restoring and p.status:match("^No explanations") end))
            end
            T.eq(nil, p.detail_buf); T.eq(false, api.nvim_buf_is_valid(detail))
            T.eq("O ", vim.wo[p.win].statuscolumn)
            -- Old prose positions must not be applied after the file switch.
            local cursors = {}
            for _, win in pairs(fixture.state.windows) do
              api.nvim_win_set_cursor(win, { 2, 0 }); cursors[win] = api.nvim_win_get_cursor(win)
            end
            f.events(); vim.cmd("redraw!")
            for win, cursor in pairs(cursors) do T.eq(cursor, api.nvim_win_get_cursor(win)) end
            for win, gutter in pairs(native_gutters) do T.eq(gutter, vim.wo[win].statuscolumn) end
            T.eq(panel.winid, api.nvim_get_current_win()); T.eq(auto and 2 or 1, #f.jobs)
            select("policy.lua"); f.ready(s, "policy.lua")
            T.eq("Ready · restored", p.status); T.eq(accepted, p.result)
            T.eq("O ", vim.wo[p.win].statuscolumn); T.eq(auto and 2 or 1, #f.jobs)
          end
          assert(#observed > 0, "must observe buffer transitions")
          for _, item in ipairs(observed) do
            if gutters[item.win] then assert(not item.gutter:find("irrelevant_explainer_detail_active", 1, true)) end
          end
          T.eq({}, errors); T.eq("", vim.v.errmsg)
        end, debug.traceback)
        api.nvim_del_autocmd(watch)
        assert(ok, err)
      end)
    end)
  end
end

T.test("runtime toggle affects subsequent Diffview navigation, not current notes or active inference", function()
  toggle_fixture(function(f, fixture, plugin)
    plugin.setup({ cache = { enabled = false } })
    T.eq(true, plugin.toggle_auto_explain()); fixture:switch("openspec/spec.md"); f.events()
    T.eq(0, #f.jobs); T.eq(nil, require("irrelevant_explainer.session").current())
    T.eq(false, plugin.toggle_auto_explain()); fixture:switch("policy.lua")
    api.nvim_win_set_cursor(fixture.state.source, { 4, 0 })
    local s = plugin.explain("hunk"); f.answer(f.job(1)); f.ready(s, "policy.lua")
    local accepted = vim.deepcopy(s.pane.result)
    fixture:switch("openspec/spec.md")
    assert(vim.wait(5000, function() return s.pane.status:match("^No explanations") end))
    T.eq(true, plugin.toggle_auto_explain()); f.events(); T.eq(1, #f.jobs)
    fixture:switch("docs/adr.md")
    local automatic = f.job(2); T.eq("file", automatic.target.scope)
    T.eq("docs/adr.md", automatic.target.path)
    T.eq(false, plugin.toggle_auto_explain()); T.eq(nil, automatic.cancelled)
    f.answer(automatic); f.ready(s, "docs/adr.md")
    fixture:switch("openspec/spec.md"); f.events(); T.eq(2, #f.jobs)
    fixture:switch("policy.lua"); f.ready(s, "policy.lua")
    T.eq(accepted, s.pane.result); T.eq("Ready · restored", s.pane.status); T.eq(2, #f.jobs)
    plugin.refresh(); f.answer(f.job(3)); f.ready(s, "policy.lua")
    T.eq(true, plugin.toggle_auto_explain()); f.events(); T.eq(3, #f.jobs)
    fixture:switch("tests/policy.txt"); f.answer(f.job(4)); f.ready(s, "tests/policy.txt")
  end)
end)

T.test("runtime toggle never revives earlier loading, stale restoration or background navigation", function()
  for _, initial in ipairs({ false, true }) do
    toggle_fixture(function(f, fixture, plugin)
      plugin.setup({ cache = { enabled = false }, diff = { auto_explain = initial } })
      api.nvim_win_set_cursor(fixture.state.source, { 4, 0 })
      local s = plugin.explain("hunk"); f.answer(f.job(1)); f.ready(s, "policy.lua")
      local current = adapter.current
      adapter.current = function() return nil, "held loading buffers" end
      for _, entry in fixture.view.files:iter() do
        if entry.path == "openspec/spec.md" then fixture.view:set_file(entry, false, true); break end
      end
      assert(vim.wait(5000, function() return s.restoring and s.snapshot == nil end))
      if initial then T.eq(false, plugin.toggle_auto_explain()) end
      T.eq(true, plugin.toggle_auto_explain())
      adapter.current = current
      fixture:switch("openspec/spec.md"); f.events(); T.eq(1, #f.jobs)
      -- Capture saved notes, then hold a real failed restoration across a toggle.
      T.eq(false, plugin.toggle_auto_explain())
      local doc = plugin.explain("file"); f.answer(f.job(2)); f.ready(doc, "openspec/spec.md")
      fixture:switch("policy.lua"); f.ready(doc, "policy.lua")
      fixture:write("docs/adr.md", "Changed evidence before returning to saved notes.\n")
      local restore, delayed = diff.restore_async, nil
      diff.restore_async = function(snapshot, source, callback)
        return restore(snapshot, source, function(value) delayed = function() callback(value) end end)
      end
      if initial then T.eq(true, plugin.toggle_auto_explain()) end
      fixture:switch("openspec/spec.md")
      assert(vim.wait(5000, function() return delayed ~= nil end))
      if initial then T.eq(false, plugin.toggle_auto_explain()) end
      T.eq(true, plugin.toggle_auto_explain()); delayed(); diff.restore_async = restore
      f.events(); T.eq(2, #f.jobs); assert(doc.pane.status:match("^Stale"))
      -- Navigate while disabled in a background tab, then enable before activating it.
      T.eq(false, plugin.toggle_auto_explain())
      vim.cmd("tabnew"); local background_from = api.nvim_get_current_tabpage()
      for _, entry in fixture.view.files:iter() do
        if entry.path == "tests/policy.txt" then fixture.view:set_file(entry, false, true); break end
      end
      f.events(); T.eq(2, #f.jobs)
      T.eq(true, plugin.toggle_auto_explain())
      api.nvim_set_current_tabpage(doc.tab); fixture:switch("tests/policy.txt"); f.events(); T.eq(2, #f.jobs)
      -- An enabled background navigation is likewise revoked by an off/on cycle.
      api.nvim_set_current_tabpage(background_from)
      for _, entry in fixture.view.files:iter() do
        if entry.path == "docs/adr.md" then fixture.view:set_file(entry, false, true); break end
      end
      assert(vim.wait(5000, function() return doc.restoring end)); T.eq(2, #f.jobs)
      T.eq(false, plugin.toggle_auto_explain()); T.eq(true, plugin.toggle_auto_explain())
      api.nvim_set_current_tabpage(doc.tab); fixture:switch("docs/adr.md"); f.events(); T.eq(2, #f.jobs)
      api.nvim_set_current_tabpage(background_from); vim.cmd("tabclose!")
      api.nvim_set_current_tabpage(doc.tab)
      fixture:switch("tests/policy.txt"); f.answer(f.job(3)); f.ready(doc, "tests/policy.txt")
    end)
  end
end)

T.test("real Diffview whole-review fake-agent flow evidence deletion geometry and mutable lifecycle", function()
  local plugin, agent = require("irrelevant_explainer"), require("irrelevant_explainer.agent")
  local script = vim.fn.getcwd() .. "/tests/fixtures/agent.py"
  local old_notify, old_run = vim.notify, agent.run
  local calls, prompts, errors = 0, {}, {}
  agent.run = function(request, ...)
    calls = calls + 1; prompts[#prompts + 1] = request
    return old_run(request, ...)
  end
  vim.notify = function(err) errors[#errors + 1] = err end
  local old_columns = vim.o.columns
  vim.o.columns = 220
  local fixture = dofile("tests/review.lua").open(true)
  for _, win in pairs(fixture.state.windows) do
    vim.wo[win].wrap = false
    api.nvim_win_call(win, function() vim.cmd("normal! zR") end)
  end
  local function config(mode, limit, strategy, radius)
    plugin.setup({ ai = { command = { "python3", script, mode }, output = "plain" },
      context = { max_bytes = limit or 262144, diff = strategy or "auto", radius = radius or 20 } })
  end
  local function ready(session)
    assert(vim.wait(5000, function() return session.pane.status:find("Ready", 1, true) ~= nil end), session.pane.status)
  end
  local function stale(session)
    assert(vim.wait(4000, function() return session.closed or session.pane.status:find("Stale", 1, true) ~= nil end))
    if session.closed then T.eq(false, api.nvim_buf_is_valid(session.pane.buf))
    else T.eq(nil, session.pane.result) end
  end
  local ok, err = xpcall(function()
    config("review"); vim.cmd("IrrelevantExplainer file")
    local s = require("irrelevant_explainer.session").current(); ready(s)
    T.eq(1, calls); T.eq(4, #s.snapshot.comparison.manifest)
    T.eq("Editors still bypass owner-only cancellation.", s.pane.result.notes[1].summary)
    -- The notes buffer retains logical source lines. Removed old code appears
    -- in virtual filler, reachable at the next new-side logical boundary.
    local notes = api.nvim_buf_get_lines(s.pane.buf, 0, 9, false)
    assert(notes[4]:find("Editors", 1, true), vim.inspect(notes))
    T.eq("", notes[8]); T.eq({ 2 }, s.pane.rows[8])
    assert(s.pane.filler[8][-3]:find("Remove the legacy fallback.", 1, true))
    T.eq(api.nvim_buf_line_count(api.nvim_win_get_buf(s.source)), api.nvim_buf_line_count(s.pane.buf))
    T.eq(true, s.pane.projection[8].filler)
    for _, side in ipairs({ "old", "new" }) do
      T.eq(true, vim.wo[s.snapshot.windows[side]].diff); T.eq(true, vim.wo[s.snapshot.windows[side]].scrollbind)
    end
    api.nvim_set_current_win(s.pane.win); vim.cmd("normal n")
    T.eq(4, api.nvim_win_get_cursor(s.source)[1])
    vim.cmd("normal n"); T.eq(8, api.nvim_win_get_cursor(s.source)[1])
    vim.cmd("normal K")
    local deletion = table.concat(api.nvim_buf_get_lines(api.nvim_win_get_buf(s.pane.detail_win), 0, -1, false), "\n")
    assert(deletion:find("Remove the legacy fallback.", 1, true)); T.eq(1, calls)
    vim.cmd("normal q"); vim.cmd("normal p"); vim.cmd("normal K")
    local detail = table.concat(api.nvim_buf_get_lines(api.nvim_win_get_buf(s.pane.detail_win), 0, -1, false), "\n")
    assert(detail:find("contradicting the supplied owner-only requirement", 1, true), detail)
    for _, removed in ipairs({ "**Context:**", "## Evidence", "## Anchors", "`openspec/spec.md`" }) do
      assert(not detail:find(removed, 1, true), detail)
    end
    T.eq({ path = "openspec/spec.md", side = "new", start_line = 2, end_line = 2 }, s.pane.result.notes[1].evidence[1])
    T.eq(1, calls)
    T.eq(s.pane.win, s.pane.detail_win)
    s.pane:back()
    api.nvim_set_current_win(s.pane.win); vim.cmd("IrrelevantExplainer file")
    s = require("irrelevant_explainer.session").current(); ready(s); T.eq(1, calls); T.eq("Ready · cached", s.pane.status)
    s.pane:scroll(api.nvim_replace_termcodes("<C-f>", true, false, true))
    T.eq(api.nvim_win_call(s.snapshot.windows.old, vim.fn.winsaveview).topline - 3,
      api.nvim_win_call(s.snapshot.windows.new, vim.fn.winsaveview).topline)
    -- Filesystem/nonfocused edits invalidate even when code and focused window
    -- stay untouched. Refresh is explicit and cannot reuse obsolete context.
    fixture:write("docs/adr.md", "Rationale: preserve the owner's decision.\nUpdated rationale during review.\n")
    stale(s); T.eq(1, calls)
    s = plugin.refresh(); ready(s); T.eq(2, calls)
    assert(prompts[2]:find("Updated rationale during review", 1, true))
    local document = api.nvim_create_buf(false, false)
    api.nvim_buf_set_name(document, fixture.root .. "/docs/adr.md")
    api.nvim_buf_set_lines(document, 0, -1, false, { "Rationale: preserve the owner's decision.", "Unsaved business decision" })
    stale(s); T.eq(2, calls)
    s = plugin.refresh(); ready(s); assert(prompts[3]:find("Unsaved business decision", 1, true))
    fixture:git("add", "--", "tests/policy.txt"); stale(s); T.eq(3, calls)
    config("explain-slow"); local late = plugin.refresh()
    fixture:switch("openspec/spec.md")
    -- Collection continues for policy.lua, but cannot display it on the spec.
    assert(vim.wait(4000, function()
      return not late.pending
    end), late.pane.status)
    T.eq(nil, late.pane.result); T.eq(nil, late.invocation)
    config("explain"); local next_file = plugin.explain("file"); ready(next_file)
    vim.wait(500); T.eq("openspec/spec.md", next_file.snapshot.target.path)
    T.eq("Ready", next_file.pane.status)
    config("explain-slow"); local layout_pending = plugin.refresh()
    local old_layout = fixture.view.cur_layout.name
    require("diffview.actions").cycle_layout()
    assert(vim.wait(10000, function()
      fixture.state = require("irrelevant_explainer.diffview").current(fixture.view.cur_layout.b.id)
      return fixture.state and fixture.view.cur_layout.name ~= old_layout
    end, 20))
    stale(layout_pending); T.eq(nil, layout_pending.invocation)
    api.nvim_set_current_win(fixture.state.source)
    config("explain"); local rebuilt = plugin.explain("file"); ready(rebuilt)
    T.eq(fixture.state.windows, rebuilt.snapshot.windows)
    fixture:switch("policy.lua")
    config("nonzero"); local bad = plugin.explain("file")
    assert(vim.wait(5000, function() return bad.pane.status:find("Failed", 1, true) ~= nil end))
    assert(bad.pane.result); assert(errors[#errors]:find("authentication", 1, true))
    local preserved = vim.deepcopy(bad.pane.result)
    local count = calls
    config("review", 500, "review"); local budget = plugin.refresh()
    assert(vim.wait(5000, function() return budget.pane.status:find("Failed", 1, true) ~= nil end), budget.pane.status)
    T.eq(count, calls); T.eq(preserved, budget.pane.result); assert(errors[#errors]:find("Complete prompt", 1, true))
    -- Auto fallback through the public session, with real Diffview and a fake
    -- agent. A large unrelated change must not crowd out the chosen hunk/spec.
    fixture:write("src/unrelated.lua", string.rep("unrelated\n", 20000))
    api.nvim_set_current_win(fixture.state.source); api.nvim_win_set_cursor(0, { 4, 0 })
    config("explain", 12000, "auto", 2)
    local focused = plugin.explain("hunk")
    T.eq(nil, focused.pane.pending.snapshot); assert(focused.pane.status:find("Pending")); assert(focused.pane.timer)
    ready(focused); T.eq(count + 1, calls); T.eq(nil, focused.pane.timer)
    T.eq("focused", focused.snapshot.context.strategy); T.eq(2, focused.snapshot.context.requested_radius)
    T.eq({ 4, 1, 4, 1 }, focused.snapshot.target.hunk)
    assert(#prompts[#prompts] <= 12000)
    assert(prompts[#prompts]:find("Only owners may cancel.", 1, true))
    assert(not prompts[#prompts]:find("unrelated.lua", 1, true))
    api.nvim_set_current_win(focused.pane.win); vim.cmd("normal 80G")
    api.nvim_exec_autocmds("CursorMoved", { buffer = focused.pane.buf })
    T.eq(80, api.nvim_win_get_cursor(focused.source)[1]); vim.cmd("normal gg")
    api.nvim_exec_autocmds("CursorMoved", { buffer = focused.pane.buf })
    T.eq(1, api.nvim_win_get_cursor(focused.source)[1]); vim.cmd("normal n")
    T.eq(4, api.nvim_win_get_cursor(focused.source)[1])
    vim.wait(250); T.eq(count + 1, calls)
    config("explain-slow"); local closing = plugin.refresh()
    require("diffview").close()
    assert(vim.wait(2000, function() return closing.closed end)); T.eq(nil, closing.invocation)
    T.eq(false, api.nvim_win_is_valid(closing.pane.win))
  end, debug.traceback)
  fixture:close(); vim.notify, agent.run = old_notify, old_run; vim.o.columns = old_columns
  assert(ok, err)
end)

T.test("real Diffview old-triggered pane stays far right and queues pending hunks across both sides", function()
  local plugin, agent = require("irrelevant_explainer"), require("irrelevant_explainer.agent")
  local old_columns, old_run, old_notify = vim.o.columns, agent.run, vim.notify
  local calls, errors = 0, {}
  vim.o.columns = 220
  local fixture = dofile("tests/review.lua").open(true)
  agent.run = function(...) calls = calls + 1; return old_run(...) end
  vim.notify = function(message) errors[#errors + 1] = message end
  local function ready(session)
    assert(vim.wait(5000, function() return session.pane.status:find("Ready", 1, true) ~= nil end),
      session.pane.status .. " " .. vim.inspect(errors))
  end
  local ok, err = xpcall(function()
    local old, new = fixture.state.windows.old, fixture.state.windows.new
    for _, win in ipairs({ old, new }) do
      vim.wo[win].wrap = false
      api.nvim_win_call(win, function() vim.cmd("normal! zR") end)
    end
    local command = { "python3", fixture.cwd .. "/tests/fixtures/agent.py", "explain-slow" }
    plugin.setup({ ai = { command = command, output = "plain" }, context = { diff = "focused", radius = 2 } })
    api.nvim_set_current_win(old); api.nvim_win_set_cursor(old, { 4, 0 })
    local s = plugin.explain("hunk")
    T.eq(fixture.state.windows, s.pane.pending.windows)
    T.eq(nil, s.pane.pending.snapshot)
    assert(vim.wait(5000, function() return calls == 1 end), s.pane.status)
    local pane_win, pane_buf = s.pane.win, s.pane.buf
    local right = api.nvim_win_get_position(pane_win)[2]
    for _, win in ipairs(api.nvim_tabpage_list_wins(s.tab)) do
      assert(api.nvim_win_get_position(win)[2] <= right, "IrrelevantExplainer is not rightmost")
    end
    api.nvim_set_current_win(old); api.nvim_win_set_cursor(old, { 8, 0 })
    local active = s.pending
    T.eq(s, plugin.explain("hunk")); T.eq(active, s.pending); T.eq(1, #s.queue)
    api.nvim_set_current_win(new); api.nvim_win_set_cursor(new, { 30, 0 })
    ready(s)
    T.eq(2, #s.batches); T.eq(4, #s.pane.result.notes)
    T.eq({ 4, 1, 4, 1 }, s.batches[1].snapshot.target.hunk)
    T.eq({ 8, 3, 7, 0 }, s.batches[2].snapshot.target.hunk)
    T.eq(pane_win, s.pane.win); T.eq(pane_buf, s.pane.buf)
    for _, motion in ipairs({ { new, 30 }, { old, 33 } }) do
      api.nvim_set_current_win(motion[1]); api.nvim_win_set_cursor(motion[1], { motion[2], 0 })
      api.nvim_exec_autocmds("CursorMoved", { buffer = api.nvim_win_get_buf(motion[1]) })
      T.eq(motion[1], s.pane.source); T.eq(motion[2], api.nvim_win_get_cursor(pane_win)[1])
    end
    api.nvim_set_current_win(new); api.nvim_win_set_cursor(new, { 4, 0 })
    T.eq(s, plugin.explain("hunk")); ready(s)
    T.eq(2, #s.batches); T.eq(4, #s.pane.result.notes); T.eq(2, calls)
    api.nvim_set_current_win(pane_win); api.nvim_win_set_cursor(pane_win, { 20, 0 })
    api.nvim_exec_autocmds("CursorMoved", { buffer = pane_buf })
    T.eq(20, api.nvim_win_get_cursor(new)[1]); T.eq(23, api.nvim_win_get_cursor(old)[1])
    s.pane:jump(1); T.eq(20, api.nvim_win_get_cursor(pane_win)[1])
    s.pane:jump(-1, 9); T.eq(4, api.nvim_win_get_cursor(pane_win)[1])
    vim.cmd("normal K")
    T.eq(pane_win, s.pane.detail_win); T.eq("", api.nvim_win_get_config(pane_win).relative)
    vim.cmd("normal q"); T.eq(pane_buf, api.nvim_win_get_buf(pane_win)); T.eq(nil, s.pane.detail_win)
    command[3] = "nonzero"; plugin.setup({ ai = { command = command, output = "plain" } })
    local accepted = vim.deepcopy(s.pane.result)
    T.eq(s, plugin.refresh())
    assert(vim.wait(5000, function() return s.pane.status:find("Failed", 1, true) ~= nil end))
    T.eq(accepted, s.pane.result); T.eq(nil, s.pane.pending)
    T.eq(3, calls)
  end, debug.traceback)
  fixture:close(); vim.o.columns, agent.run, vim.notify = old_columns, old_run, old_notify
  assert(ok, err)
end)

local function whole_review_fixture(run, reference_variants)
  local plugin, agent = require("irrelevant_explainer"), require("irrelevant_explainer.agent")
  local original, notify, columns = agent.run, vim.notify, vim.o.columns
  local f = { jobs = {}, errors = {} }
  vim.o.columns = 220
  f.fixture = dofile("tests/review.lua").open(true, reference_variants)
  agent.run = function(prompt, config, _, callback)
    local request = prompt:match("UNTRUSTED REVIEW REQUEST JSON:\n(.*)")
    local job = { config = config, callback = callback, request = request and vim.json.decode(request) }
    if not request then
      job.target = vim.json.decode(prompt:match("FOCUSED TARGET JSON:\n(.*)"))
      job.context = vim.json.decode(prompt:match("UNTRUSTED SNAPSHOT JSON:\n(.-)\nFOCUSED TARGET JSON:"))
    end
    job.cancel = function() job.cancelled = true end
    f.jobs[#f.jobs + 1] = job
    return job
  end
  vim.notify = function(message) f.errors[#f.errors + 1] = message end
  function f:job(n)
    assert(vim.wait(7000, function() return #self.jobs >= n end), vim.inspect(self.errors))
    T.eq(n, #self.jobs)
    return self.jobs[n]
  end
  function f:answer(n, label)
    local job = self.jobs[n]
    local function notes(target)
      if target.path == "tests/policy.txt" then return {} end
      return { { summary = (label or "Explains") .. " " .. target.path,
        detail = "A complete explanation of `" .. target.path .. "`.\n\n" .. string.rep("Read the supplied evidence.\n\n", 20),
        anchors = { target.anchors[1] }, intent_basis = "unknown", evidence = {} } }
    end
    if job.request then
      local req = job.request
      local value = { version = 3, phase = req.phase, request_id = req.request_id, snapshot_id = req.snapshot_id }
      local citation = { path = "openspec/spec.md", side = "new", start_line = 2, end_line = 2 }
      if req.phase == "annotate" then
        value.units = vim.tbl_map(function(unit)
          local findings = {}
          for i = 1, self.verbose_findings and 4 or 1 do
            findings[i] = { text = self.verbose_findings and (i .. string.rep("Ownership matters. ", 45)) or "Cancellation requires ownership.",
              intent_basis = "documented", evidence = { citation }, file_ids = { unit.file_id } }
          end
          return { unit_id = unit.unit_id, notes = notes(unit.target), findings = findings }
        end, req.units)
      elseif req.phase == "reduce" then
        value.child_ids, value.findings = req.child_ids, { req.inputs[1].findings[1] }
      else
        value.child_ids = req.child_ids
        value.review = { title = label or "Owner-only cancellation", sections = {
          { heading = "How the files connect", detail = string.rep("Owners may cancel.\n\n", 30),
            intent_basis = "documented", evidence = { citation },
            file_ids = vim.tbl_map(function(entry) return entry.file_id end, req.manifest) },
        } }
      end
      job.callback(value)
    else job.callback({ version = 1, notes = notes(job.target) }) end
  end
  -- Every entry is one real agent invocation; callers can pause between phases.
  function f:complete(n, label)
    while true do
      local job = self:job(n)
      self:answer(n, label)
      if not job.request or job.request.phase == "synthesize" then return n end
      n = n + 1
    end
  end
  function f:settled(s)
    assert(vim.wait(10000, function() return not s.pending and not s.restoration and not s.checking end),
      s.pane.status .. " / " .. tostring(s.review_status) .. " / " .. vim.inspect(self.errors))
  end
  function f:select(path, s)
    self.fixture:switch(path)
    assert(vim.wait(5000, function()
      return s.review_key == vim.inspect({ self.fixture.state.cwd, self.fixture.state.pair,
        self.fixture.state.path_args, self.fixture.state.show_untracked, path, path, self.fixture.state.selected.kind })
        and not s.restoring
    end), s.pane.status)
  end
  plugin.setup({ cache = { enabled = false } })
  local ok, err = xpcall(function() run(f, plugin) end, debug.traceback)
  f.fixture:close()
  agent.run, vim.notify, vim.o.columns = original, notify, columns
  assert(ok, err)
end

T.test("whole-review commands work from the Diffview file tree without moving focus or selection", function()
  whole_review_fixture(function(f, plugin)
    require("diffview.actions").focus_files()
    local panel = f.fixture.view.panel
    T.eq(panel.winid, api.nvim_get_current_win())
    T.eq("DiffviewFiles", vim.bo[api.nvim_get_current_buf()].filetype)
    local selected = f.fixture.view.cur_entry
    local tree_view = api.nvim_win_call(panel.winid, vim.fn.winsaveview)
    -- File/hunk still require a source cursor, not an explorer line number.
    local state, err = adapter.current(panel.winid)
    T.eq(nil, state); assert(err:find("source pane", 1, true))
    vim.cmd("IrrelevantExplainerReview")
    local s = require("irrelevant_explainer.session").current()
    T.eq(true, s.pane.review_mode); T.eq(0, #f.jobs)
    T.eq(f.fixture.state.source, s.pane.source)
    vim.cmd("IrrelevantExplainer review")
    T.eq("annotate", f:job(1).request.phase)
    T.eq(3, f:complete(1)); f:settled(s)
    T.eq(panel.winid, api.nvim_get_current_win()); T.eq(selected, f.fixture.view.cur_entry)
    T.eq(tree_view, api.nvim_win_call(panel.winid, vim.fn.winsaveview))
    T.eq("Owner-only cancellation", s.pane.review.title)
    plugin.explain("review"); f:settled(s); T.eq(3, #f.jobs)
    vim.cmd("IrrelevantExplainerRefresh"); T.eq("annotate", f:job(4).request.phase)
    T.eq(6, f:complete(4, "Refreshed from tree")); f:settled(s)
    T.eq(panel.winid, api.nvim_get_current_win()); T.eq({}, f.errors)
  end)
end)

T.test("cancelling cached review validation keeps saved output and rejects late completion", function()
  whole_review_fixture(function(f, plugin)
    local s = plugin.explain("review")
    f:complete(1); f:settled(s)
    local saved = vim.deepcopy(s.pane.review)
    local replay, original = require("irrelevant_explainer.review"), require("irrelevant_explainer.review").validate_record_async
    local deliver
    replay.validate_record_async = function(record, snapshot, config, done)
      return original(record, snapshot, config, function(value, err)
        deliver = function() done(value, err) end
      end)
    end
    local ok, err = xpcall(function()
      plugin.explain("review")
      assert(vim.wait(7000, function() return deliver ~= nil end), s.review_status)
      vim.cmd("IrrelevantExplainerCancel")
      deliver()
      f:settled(s)
      T.eq(saved, s.pane.review)
      assert(s.pane.review_status:match("^Cancelled"))
      assert(not vim.wo[s.pane.win].winbar:find("Running review", 1, true))
      T.eq(nil, s.pane.timer); T.eq(3, #f.jobs)
      replay.validate_record_async = original
      api.nvim_set_current_win(f.fixture.state.source)
      plugin.explain("review"); f:settled(s)
      T.eq("Ready · cached", s.pane.review_status); T.eq(saved, s.pane.review)
      T.eq(3, #f.jobs)
    end, debug.traceback)
    replay.validate_record_async = original
    assert(ok, err)
  end)
end)

T.test("one review invocation survives collection navigation, distributes every file and supports display-only references", function()
  whole_review_fixture(function(f, plugin)
    plugin.setup({ cache = { enabled = false }, diff = { auto_explain = true }, context = { diff = "focused" } })
    vim.cmd("IrrelevantExplainerReview")
    local s = require("irrelevant_explainer.session").current()
    T.eq(true, s.pane.review_mode); T.eq(0, #f.jobs)
    assert(s.pane.review_status:find("No review", 1, true))
    vim.cmd("IrrelevantExplainer review")
    local collection = s.collection
    f:select("openspec/spec.md", s) -- Before collection has delivered.
    T.eq(false, collection.cancelled)
    local job = f:job(1)
    T.eq("annotate", job.request.phase); T.eq(3, #job.request.units)
    T.eq(4, #require("irrelevant_explainer.review").inspect(s.review_job).units)
    T.eq("review", s.pending.snapshot.context.strategy)
    plugin.explain("review") -- Same target even though a different file is displayed.
    f:select("docs/adr.md", s)
    T.eq(nil, job.cancelled); T.eq(false, s.pane.review_mode)
    local focus = api.nvim_get_current_win()
    f:answer(1)
    T.eq("annotate", f:job(2).request.phase); T.eq(1, #f.jobs[2].request.units)
    T.eq(nil, s.pane.review); T.eq(nil, s.pane.result)
    f:select("policy.lua", s); f:select("docs/adr.md", s)
    plugin.explain("review"); T.eq(2, #f.jobs)
    f:answer(2); T.eq("synthesize", f:job(3).request.phase)
    T.eq(nil, s.pane.review); T.eq(nil, s.pane.result)
    f:select("policy.lua", s); f:select("docs/adr.md", s)
    f:answer(3); f:settled(s)
    T.eq(3, #f.jobs); T.eq(focus, api.nvim_get_current_win()); T.eq(false, s.pane.review_mode)
    T.eq("Explains docs/adr.md", s.pane.result.notes[1].summary)
    for _, path in ipairs({ "policy.lua", "tests/policy.txt", "openspec/spec.md" }) do
      f:select(path, s); f:settled(s)
      T.eq(3, #f.jobs); T.eq(path, s.snapshot.target.path)
      if path == "tests/policy.txt" then T.eq(0, #s.pane.result.notes) end
    end
    plugin.review(); f:settled(s)
    T.eq(true, s.pane.review_mode)
    api.nvim_set_current_win(s.pane.win)
    api.nvim_win_set_cursor(s.pane.win, { 20, 0 })
    local reader = api.nvim_win_call(s.pane.win, vim.fn.winsaveview)
    vim.cmd("normal \27"); T.eq(false, s.pane.review_mode)
    plugin.review(); T.eq(reader, api.nvim_win_call(s.pane.win, vim.fn.winsaveview))
    T.eq("Checking saved review", s.pane.review_status); assert(s.pane.timer)
    local prose = api.nvim_buf_get_lines(s.pane.review_buf, 0, -1, false)
    f:settled(s); T.eq(nil, s.pane.timer)
    T.eq(prose, api.nvim_buf_get_lines(s.pane.review_buf, 0, -1, false))
    T.eq(reader, api.nvim_win_call(s.pane.win, vim.fn.winsaveview)); T.eq(3, #f.jobs)
    local row
    for line, entry in pairs(s.pane.review_references) do if entry.path == "policy.lua" then row = line end end
    api.nvim_win_set_cursor(s.pane.win, { assert(row), 0 }); vim.cmd("normal \r")
    assert(vim.wait(5000, function() return f.fixture.view.cur_entry.path == "policy.lua" and not s.restoring end))
    T.eq(false, s.pane.review_mode); T.eq("policy.lua", s.snapshot.target.path); T.eq(3, #f.jobs)
    plugin.refresh(); T.eq("file", f:job(4).target.scope); f:answer(4); f:settled(s)
    plugin.review(); plugin.refresh(); T.eq("annotate", f:job(5).request.phase)
    T.eq(7, f:complete(5, "Fresh narrative")); f:settled(s)
    T.eq("Fresh narrative", s.pane.review.title)
    local review = s.pane.review
    plugin.explain("review"); assert(s.pane.timer)
    T.eq(review, s.pane.review)
    f:settled(s); T.eq(7, #f.jobs); T.eq(nil, s.pane.timer)
    f.fixture:write("docs/adr.md", "Changed shared rationale.\n")
    api.nvim_exec_autocmds("TextChanged", {})
    assert(vim.wait(7000, function() return s.pane.review_status:match("^Stale") end))
    T.eq(nil, s.pane.review); T.eq(nil, s.pane.result)
    plugin.refresh(); local late = f:job(8)
    plugin.close(); T.eq(true, late.cancelled); f:answer(8)
    vim.wait(100); T.eq(nil, require("irrelevant_explainer.session").current())
    T.eq({}, f.errors)
  end)
end)

T.test("hidden file success and failure preserve another file's expanded reading state", function()
  whole_review_fixture(function(f, plugin)
    f.fixture:switch("openspec/spec.md")
    local s = plugin.explain("file"); f:job(1); f:answer(1); f:settled(s)
    f:select("policy.lua", s)
    plugin.explain("file"); local running = f:job(2)
    f:select("openspec/spec.md", s)
    api.nvim_set_current_win(s.pane.win); s.pane:detail(1)
    api.nvim_win_set_cursor(s.pane.win, { 10, 0 })
    local detail, view, source_view = s.pane.detail_buf, api.nvim_win_call(s.pane.win, vim.fn.winsaveview),
      api.nvim_win_call(s.pane.source, vim.fn.winsaveview)
    f:answer(2); f:settled(s)
    T.eq(nil, running.cancelled); T.eq(detail, s.pane.detail_buf)
    T.eq(view, api.nvim_win_call(s.pane.win, vim.fn.winsaveview))
    T.eq(source_view, api.nvim_win_call(s.pane.source, vim.fn.winsaveview))
    T.eq(s.pane.win, api.nvim_get_current_win()); assert(s.pane.status:match("^Ready"))
    f:select("policy.lua", s); f:settled(s); T.eq(2, #f.jobs)
    plugin.refresh(); f:job(3)
    f:select("openspec/spec.md", s)
    api.nvim_set_current_win(s.pane.win); s.pane:detail(1)
    detail = s.pane.detail_buf
    f.jobs[3].callback(nil, "provider unavailable"); f:settled(s)
    T.eq(detail, s.pane.detail_buf); assert(s.pane.status:match("^Ready"))
    T.eq("policy.lua: provider unavailable", f.errors[#f.errors])
  end)
end)

T.test("review failure suppresses Auto fallback but continues explicit file work and budget overflow invokes nothing", function()
  whole_review_fixture(function(f, plugin)
    plugin.setup({ cache = { enabled = false }, diff = { auto_explain = true } })
    local s = plugin.explain("review"); f:job(1)
    f:select("openspec/spec.md", s)
    plugin.explain("file")
    f:select("tests/policy.txt", s)
    vim.wait(200); T.eq(1, #f.jobs); T.eq(1, #s.queue); T.eq(nil, s.automatic)
    f.jobs[1].callback('{"version":3,"phase":')
    T.eq("openspec/spec.md", f:job(2).target.path)
    f:answer(2); f:settled(s)
    vim.wait(1100); T.eq(2, #f.jobs); T.eq(nil, s.pane.review)
    plugin.review(); assert(s.pane.review_status:match("^Failed"))
    plugin.setup({ cache = { enabled = false }, context = { max_bytes = 100, diff = "focused" } })
    plugin.refresh(); f:settled(s); T.eq(2, #f.jobs)
    assert(f.errors[#f.errors]:find("request_max_bytes", 1, true), vim.inspect(f.errors))
    T.eq({ "file", "selection", "hunk", "review" }, vim.fn.getcompletion("IrrelevantExplainer ", "cmdline"))
  end)
end)

T.test("Auto coalesces navigation while explicit promotion survives later navigation and disabling", function()
  whole_review_fixture(function(f, plugin)
    plugin.setup({ cache = { enabled = false }, diff = { auto_explain = true } })
    local s = plugin.explain("file"); f:job(1)
    f:select("openspec/spec.md", s)
    assert(vim.wait(7000, function() return s.automatic and s.automatic.collected end))
    local discarded = s.automatic
    f:select("docs/adr.md", s)
    assert(vim.wait(7000, function() return s.automatic and s.automatic.collected end))
    T.eq(true, discarded.cancelled); T.eq("docs/adr.md", s.automatic.path)
    plugin.explain("file")
    assert(vim.wait(7000, function() return not s.automatic and #s.queue == 1 and s.queue[1].collected end))
    T.eq("docs/adr.md", s.queue[1].path)
    f:select("tests/policy.txt", s)
    assert(vim.wait(7000, function() return s.automatic and s.automatic.collected end))
    plugin.toggle_auto_explain()
    T.eq(nil, s.automatic); T.eq(1, #s.queue); T.eq(nil, f.jobs[1].cancelled)
    f:answer(1)
    T.eq("docs/adr.md", f:job(2).target.path)
    f:answer(2); f:settled(s)
    vim.wait(1100); T.eq(2, #f.jobs)
    f:select("docs/adr.md", s); f:settled(s); T.eq(2, #f.jobs)
    T.eq("Explains docs/adr.md", s.pane.result.notes[1].summary)
    T.eq({ "Automatic explanations disabled" }, f.errors)
  end)
end)

T.test("review replaces full-file batches but preserves hunks and only reuses matching complete requests", function()
  whole_review_fixture(function(f, plugin)
    local s = plugin.explain("file"); f:job(1); f:answer(1, "Original"); f:settled(s)
    api.nvim_win_set_cursor(s.pane.source, { 4, 0 })
    plugin.explain("hunk"); f:job(2); f:answer(2, "Hunk"); f:settled(s)
    T.eq(2, #s.batches)
    plugin.explain("review"); f:job(3)
    s.pane:show_file(); s.pane:detail(1)
    local detail, view = s.pane.detail_buf, api.nvim_win_call(s.pane.win, vim.fn.winsaveview)
    T.eq(5, f:complete(3, "Replacement")); f:settled(s)
    T.eq(2, #s.batches); T.eq(detail, s.pane.detail_buf)
    T.eq(view, api.nvim_win_call(s.pane.win, vim.fn.winsaveview))
    T.eq("Original policy.lua", s.pane.result.notes[1].summary)
    s.pane:back()
    T.eq({ "Replacement policy.lua", "Hunk policy.lua" }, vim.tbl_map(function(n) return n.summary end, s.pane.result.notes))
    f:select("openspec/spec.md", s); f:settled(s)
    -- A distributed annotation did not receive this standalone request's whole
    -- comparison context/contract. Reading is free; explicitly requesting that
    -- different coverage is a miss, then an exact repeat is reusable.
    plugin.explain("file"); f:job(6); f:answer(6); f:settled(s)
    plugin.explain("file"); f:settled(s); T.eq(6, #f.jobs)
    plugin.setup({ cache = { enabled = false }, context = { diff = "focused" } })
    plugin.explain("file"); f:job(7); f:answer(7); f:settled(s)
    plugin.setup({ cache = { enabled = false }, ai = { output = function(text) return text end } })
    plugin.explain("file"); f:job(8); f:answer(8); f:settled(s)
    T.eq({}, f.errors)
  end)
end)

T.test("Review references navigate exact renamed deleted and binary entries without inference", function()
  whole_review_fixture(function(f, plugin)
    plugin.setup({ cache = { enabled = false }, diff = { auto_explain = true } })
    local s = plugin.explain("review"); T.eq(3, f:complete(1)); f:settled(s)
    T.eq({}, f.errors); assert(s.pane.review, s.pane.review_status)
    T.eq({ "annotate", "annotate", "synthesize" }, vim.tbl_map(function(job) return job.request.phase end, f.jobs))
    for _, path in ipairs({ "renamed.txt", "deleted.txt", "badge.bin" }) do
      plugin.review(); f:settled(s)
      local row, reference
      for line, entry in pairs(s.pane.review_references) do
        if entry.path == path then row, reference = line, entry end
      end
      assert(row, "missing reference for " .. path)
      api.nvim_set_current_win(s.pane.win)
      api.nvim_win_set_cursor(s.pane.win, { row, 0 }); vim.cmd("normal \r")
      assert(vim.wait(7000, function()
        return f.fixture.view.cur_entry.path == path and not s.restoring
          and (path == "badge.bin" or s.snapshot and s.snapshot.target.path == path)
      end), s.pane.status)
      f:settled(s); T.eq(false, s.pane.review_mode); T.eq(3, #f.jobs)
      if path == "renamed.txt" then
        T.eq("old-name.txt", s.snapshot.target.oldpath)
      elseif path == "deleted.txt" then
        T.eq(1, #s.snapshot.target.anchors); T.eq("old", s.snapshot.target.anchors[1].side)
      else
        assert(reference.text_unavailable); assert(s.pane.status:find("No text annotations", 1, true))
        T.eq(nil, s.pane.result)
      end
    end
    T.eq({}, f.errors)
  end, true)
end)

T.test("review checkpoints resume only in their owner and refresh discards partial progress", function()
  for _, failure in ipairs({ "provider unavailable", "Agent timed out", "cancel" }) do
    whole_review_fixture(function(f, plugin)
      local s = plugin.explain("review")
      local first = f:job(1).request.request_id
      f:answer(1)
      local second = f:job(2)
      T.eq("annotate", second.request.phase)
      T.eq(nil, s.pane.review); T.eq(nil, s.pane.result)
      if failure == "cancel" then plugin.cancel(); T.eq(true, second.cancelled)
      else second.callback(nil, failure) end
      f:settled(s)
      T.eq(nil, s.pane.review); T.eq(nil, s.pane.result)
      f:answer(2); vim.wait(100); T.eq(2, #f.jobs) -- Retired callbacks cannot advance.
      -- An identical comparison in a different Diffview has no partial checkpoint.
      local dv, lib = require("diffview"), require("diffview.lib")
      dv.open({ f.fixture.base, "--selected-file=" .. f.fixture.root .. "/policy.lua" })
      local other = lib.get_current_view()
      local ok, err = xpcall(function()
        assert(vim.wait(7000, function() return other.initialized and adapter.current(other.cur_layout.b.id) end))
        api.nvim_set_current_win(other.cur_layout.b.id)
        assert(plugin.explain("review") ~= s)
        T.eq(first, f:job(3).request.request_id)
      end, debug.traceback)
      plugin.close(); dv.close()
      api.nvim_set_current_tabpage(f.fixture.view.tabpage)
      assert(ok, err)
      f:select("openspec/spec.md", s)
      assert(vim.wait(5000, function()
        local state = adapter.current(f.fixture.state.source)
        return state and vim.deep_equal(state.panes.old.lines,
          { "# Cancellation", "Owners or administrators may cancel." })
      end), "original Diffview did not reload its old source: " .. vim.inspect(adapter.current(f.fixture.state.source)))
      plugin.explain("review")
      T.eq(second.request.request_id, f:job(4).request.request_id)
      plugin.explain("review"); vim.wait(100); T.eq(4, #f.jobs)
      plugin.cancel(); f:settled(s)
      plugin.review(); plugin.refresh()
      T.eq(first, f:job(5).request.request_id)
      plugin.close(); T.eq(true, f.jobs[5].cancelled)
      api.nvim_set_current_win(f.fixture.state.source)
      local replacement = plugin.explain("review")
      assert(replacement ~= s)
      T.eq(first, f:job(6).request.request_id)
      T.eq(8, f:complete(6)); f:settled(replacement)
      assert(replacement.pane.review, vim.inspect(f.errors))
    end)
  end
end)

T.test("review final output after an unsaved source edit cannot install partial annotations", function()
  whole_review_fixture(function(f, plugin)
    local s = plugin.explain("review")
    f:job(1); f:answer(1); f:job(2); f:answer(2)
    local final = f:job(3)
    T.eq("synthesize", final.request.phase)
    f:select("policy.lua", s)
    api.nvim_buf_set_lines(api.nvim_win_get_buf(s.pane.source), 0, 1, false, { "-- changed after annotations" })
    f:answer(3); f:settled(s)
    T.eq(nil, s.pane.review); T.eq(nil, s.pane.result)
    T.eq(3, #f.jobs)
    plugin.explain("review")
    local fresh = f:job(4)
    T.eq("annotate", fresh.request.phase)
    assert(fresh.request.snapshot_id ~= final.request.snapshot_id)
  end)
end)

T.test("bounded review keeps navigation display-only through annotation reduction and synthesis", function()
  whole_review_fixture(function(f, plugin)
    plugin.setup({ cache = { enabled = false }, review = { request_max_bytes = 14000, response_max_bytes = 16384 } })
    f.verbose_findings = true
    local s = plugin.explain("review")
    local phases, n = {}, 1
    while true do
      local job = f:job(n)
      phases[#phases + 1] = job.request.phase
      T.eq(nil, s.pane.review); T.eq(nil, s.pane.result)
      f:select(n % 2 == 0 and "policy.lua" or "openspec/spec.md", s)
      T.eq(nil, job.cancelled)
      plugin.explain("review"); vim.wait(50); T.eq(n, #f.jobs)
      f:answer(n)
      if job.request.phase == "synthesize" then break end
      n = n + 1
      assert(n <= 12, vim.inspect(phases))
    end
    f:settled(s)
    T.eq({ "annotate", "annotate", "annotate", "annotate", "reduce", "reduce", "reduce", "reduce", "synthesize" }, phases)
    T.eq({}, f.errors); assert(s.pane.review)
    local calls = #f.jobs
    f:select("docs/adr.md", s); f:settled(s)
    T.eq(calls, #f.jobs); T.eq("Explains docs/adr.md", s.pane.result.notes[1].summary)
  end)
end)
