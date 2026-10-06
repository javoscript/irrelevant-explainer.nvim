local api = vim.api
local adapter, diff = require("explainr.diffview"), require("explainr.diff")

T.test("diff modules and code mode load without optional Diffview dependency", function()
  assert(not package.loaded["diffview.lib"], "Diffview was eagerly loaded")
  local previous, buf = api.nvim_get_current_buf(), api.nvim_create_buf(false, false)
  api.nvim_set_current_buf(buf)
  api.nvim_buf_set_lines(buf, 0, -1, false, { "ordinary code" })
  local s, err = require("explainr.code").collect(0, "file")
  api.nvim_set_current_buf(previous); api.nvim_buf_delete(buf, { force = true })
  assert(s, err)
  assert(not package.loaded["diffview.lib"])
end)

local runtime = vim.env.EXPLAINR_DIFFVIEW_PATH or (vim.fn.stdpath("data") .. "/lazy/diffview.nvim")
if vim.fn.isdirectory(runtime .. "/lua/diffview") ~= 1 then
  print("SKIP real Diffview runtime tests: missing dependency at " .. runtime .. " (set EXPLAINR_DIFFVIEW_PATH)")
  return
end
-- Keep optional-plugin globals/autocmds/module loading out of the ordinary
-- suite. In particular its code-mode dependency assertion must stay useful.
if vim.env.EXPLAINR_DIFFVIEW_CHILD ~= "1" then
  T.test("real Diffview runtime in isolated offline Neovim", function()
    -- Script (-l) mode does not resize the allocated screen grid when columns
    -- changes. Diffview's explicit redraw requires normal editor startup.
    local result = vim.system({ vim.v.progpath, "--headless", "-u", "NONE", "-i", "NONE", "-n",
      "-c", "luafile tests/run.lua" }, {
      cwd = vim.fn.getcwd(), env = { EXPLAINR_TEST = "tests/diffview_test.lua", EXPLAINR_DIFFVIEW_CHILD = "1",
        EXPLAINR_DIFFVIEW_PATH = runtime } }):wait(60000)
    print((result.stdout or "") .. (result.stderr or ""))
    assert(result.code == 0 and result.signal == 0,
      string.format("isolated real Diffview tests failed (code=%s, signal=%s)", result.code, result.signal))
  end)
  return
end
vim.opt.runtimepath:append(runtime)
local plenary = vim.env.EXPLAINR_PLENARY_PATH or (vim.fn.stdpath("data") .. "/lazy/plenary.nvim")
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
    T.eq(false, diff.fresh(s))
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
  local plugin = require("explainr")
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
    local session = plugin.diff("file")
    T.eq(nil, session.pane.pending.snapshot)
    return session
  end
  local function ready(session)
    assert(vim.wait(5000, function() return session.pane.status:match("^Ready") ~= nil end), session.pane.status)
  end
  -- Fixture cwd is a disposable repository; the process fixture lives in ours.
  plugin.setup({ ai = { command = { "python3", fixture.cwd .. "/tests/fixtures/agent.py", "explain" } } })
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
    local code = plugin.code("file"); ready(code)
    T.eq({}, mapping(code.pane, "<Tab>")); T.eq({}, mapping(code.pane, "<leader>e"))
    T.eq("", vim.v.errmsg)
  end, debug.traceback)
  fixture:close(); vim.g.mapleader, vim.o.columns = old_leader, old_columns
  assert(ok, err)
end)

T.test("real DiffviewClose cancels queued expanded placement without leaking buffers or callback errors", function()
  local fixture = dofile("tests/review.lua").open(true)
  local pane, errors, schedule = nil, {}, vim.schedule
  local ok, err = xpcall(function()
    vim.cmd("runtime plugin/diffview.lua") -- Runtime is added after -u NONE startup.
    local state = fixture.state
    pane = require("explainr.ui").open(state.source, { windows = state.windows }, { notes = { {
      summary = "Read the permission change", detail = "Preserve the owner check while reading the diff.",
      intent_basis = "inferred", anchors = { { path = "policy.lua", side = "new", start_line = 1, end_line = 9 } },
    } } })
    pane:detail(1)
    vim.wait(30, function() return false end)
    local detail, summary_buf = pane.detail_buf, pane.buf
    vim.v.errmsg = ""
    vim.schedule = function(callback)
      schedule(function()
        local success, failure = xpcall(callback, debug.traceback)
        if not success then errors[#errors + 1] = failure end
      end)
    end
    api.nvim_exec_autocmds("WinResized", {})
    vim.cmd("DiffviewClose") -- Do not pre-close Explainr as normal fixture teardown does.
    assert(vim.wait(1000, function() return pane.closed end), "DiffviewClose did not clean the pane")
    vim.wait(30, function() return false end)
    T.eq({}, errors); T.eq("", vim.v.errmsg)
    T.eq(false, api.nvim_buf_is_valid(detail)); T.eq(false, api.nvim_buf_is_valid(summary_buf))
    T.eq(0, vim.fn.exists("#ExplainrPane" .. pane.win))
  end, debug.traceback)
  vim.schedule = schedule
  if pane then pane:close() end
  fixture:close()
  assert(ok, err)
end)

T.test("Diffview restores per-file explanations without inference and rejects changed review context", function()
  local plugin, agent = require("explainr"), require("explainr.agent")
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
      plugin.setup({ ai = { command = { "python3", fixture.cwd .. "/tests/fixtures/agent.py", "explain" } },
        context = { diff = case[2], radius = 2 } })
      api.nvim_win_set_cursor(fixture.state.source, { 4, 0 })
      local session = plugin.diff(case[3]); ready(session)
      if case[3] == "hunk" then
        api.nvim_set_current_win(fixture.state.windows.old); api.nvim_win_set_cursor(fixture.state.windows.old, { 9, 0 })
        T.eq(session, plugin.diff("hunk")); ready(session); T.eq(2, #session.batches)
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
      local document = plugin.diff("file"); ready(document)
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
        fixture:switch("openspec/spec.md")
        assert(vim.wait(5000, function() return #delayed == 2 end))
        delayed[1].callback(delayed[1].value)
        T.eq(nil, document.pane.result) -- Obsolete A cannot install in B.
        delayed[2].callback(delayed[2].value); ready(document, "openspec/spec.md")
        T.eq(document_result, document.pane.result); T.eq(count + 1, calls)
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
  local plugin, agent = require("explainr"), require("explainr.agent")
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
    plugin.setup({ diff = { auto_explain = true } })
    fixture:switch("openspec/spec.md"); events()
    T.eq(0, #jobs); T.eq(nil, require("explainr.session").current())
    fixture:switch("policy.lua")
    api.nvim_win_set_cursor(fixture.state.source, { 4, 0 })
    local session = plugin.diff("hunk"); answer(job(1)); ready(session, "policy.lua")
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
    fixture:switch("tests/policy.txt"); local current = job(5)
    T.eq(true, abandoned.cancelled)
    answer(abandoned); T.eq(nil, session.pane.result)
    answer(current); ready(session, "tests/policy.txt")
    fixture:switch("docs/adr.md")
    job(6).callback(nil, "Fixture provider failure")
    assert(vim.wait(5000, function() return session.pane.status:match("^Failed") end))
    events(); T.eq(6, #jobs); T.eq("Fixture provider failure", errors[#errors])
    plugin.cancel(); events(); T.eq(6, #jobs)
    plugin.close(); fixture:switch("policy.lua"); events()
    T.eq(6, #jobs); T.eq(nil, require("explainr.session").current())
    T.eq("", vim.v.errmsg)
  end, debug.traceback)
  fixture:close(); plugin.setup()
  agent.run, vim.notify, vim.o.columns = old_run, old_notify, old_columns
  assert(ok, err)
end)

T.test("real Diffview whole-review fake-agent flow evidence deletion geometry and mutable lifecycle", function()
  local plugin, agent = require("explainr"), require("explainr.agent")
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
    plugin.setup({ ai = { command = { "python3", script, mode } },
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
    config("review"); vim.cmd("ExplainrDiff file")
    local s = require("explainr.session").current(); ready(s)
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
    api.nvim_set_current_win(s.pane.win); vim.cmd("ExplainrDiff file")
    s = require("explainr.session").current(); ready(s); T.eq(1, calls); T.eq("Ready · cached", s.pane.status)
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
    -- Switching during initial collection can fail its capture guard before
    -- there is a pending snapshot to label stale. Neither outcome installs it.
    assert(vim.wait(4000, function()
      return late.closed or late.pane.status:match("^No explanations") or late.pane.status:match("^Failed")
    end), late.pane.status)
    T.eq(nil, late.pane.result); T.eq(nil, late.invocation)
    config("explain"); local next_file = plugin.diff("file"); ready(next_file)
    vim.wait(500); T.eq("openspec/spec.md", next_file.snapshot.target.path)
    T.eq("Ready", next_file.pane.status)
    config("explain-slow"); local layout_pending = plugin.refresh()
    local old_layout = fixture.view.cur_layout.name
    require("diffview.actions").cycle_layout()
    assert(vim.wait(10000, function()
      fixture.state = require("explainr.diffview").current(fixture.view.cur_layout.b.id)
      return fixture.state and fixture.view.cur_layout.name ~= old_layout
    end, 20))
    stale(layout_pending); T.eq(nil, layout_pending.invocation)
    api.nvim_set_current_win(fixture.state.source)
    config("explain"); local rebuilt = plugin.diff("file"); ready(rebuilt)
    T.eq(fixture.state.windows, rebuilt.snapshot.windows)
    fixture:switch("policy.lua")
    config("nonzero"); local bad = plugin.diff("file")
    assert(vim.wait(5000, function() return bad.pane.status:find("Failed", 1, true) ~= nil end))
    T.eq(nil, bad.pane.result); assert(errors[#errors]:find("authentication", 1, true))
    local count = calls
    config("review", 500, "review"); local budget = plugin.refresh()
    assert(vim.wait(5000, function() return budget.pane.status:find("Failed", 1, true) ~= nil end), budget.pane.status)
    T.eq(count, calls); T.eq(nil, budget.pane.result); assert(errors[#errors]:find("Complete prompt", 1, true))
    -- Auto fallback through the public session, with real Diffview and a fake
    -- agent. A large unrelated change must not crowd out the chosen hunk/spec.
    fixture:write("src/unrelated.lua", string.rep("unrelated\n", 20000))
    api.nvim_set_current_win(fixture.state.source); api.nvim_win_set_cursor(0, { 4, 0 })
    config("explain", 12000, "auto", 2)
    local focused = plugin.diff("hunk")
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
  local plugin, agent = require("explainr"), require("explainr.agent")
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
    plugin.setup({ ai = { command = command }, context = { diff = "focused", radius = 2 } })
    api.nvim_set_current_win(old); api.nvim_win_set_cursor(old, { 4, 0 })
    local s = plugin.diff("hunk")
    T.eq(fixture.state.windows, s.pane.pending.windows)
    T.eq(nil, s.pane.pending.snapshot)
    assert(vim.wait(5000, function() return calls == 1 end), s.pane.status)
    local pane_win, pane_buf = s.pane.win, s.pane.buf
    local right = api.nvim_win_get_position(pane_win)[2]
    for _, win in ipairs(api.nvim_tabpage_list_wins(s.tab)) do
      assert(api.nvim_win_get_position(win)[2] <= right, "Explainr is not rightmost")
    end
    api.nvim_set_current_win(old); api.nvim_win_set_cursor(old, { 8, 0 })
    local active = s.pending
    T.eq(s, plugin.diff("hunk")); T.eq(active, s.pending); T.eq(1, #s.queue)
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
    T.eq(s, plugin.diff("hunk")); ready(s)
    T.eq(2, #s.batches); T.eq(4, #s.pane.result.notes); T.eq(2, calls)
    api.nvim_set_current_win(pane_win); api.nvim_win_set_cursor(pane_win, { 20, 0 })
    api.nvim_exec_autocmds("CursorMoved", { buffer = pane_buf })
    T.eq(20, api.nvim_win_get_cursor(new)[1]); T.eq(23, api.nvim_win_get_cursor(old)[1])
    s.pane:jump(1); T.eq(20, api.nvim_win_get_cursor(pane_win)[1])
    s.pane:jump(-1, 9); T.eq(4, api.nvim_win_get_cursor(pane_win)[1])
    vim.cmd("normal K")
    T.eq(pane_win, s.pane.detail_win); T.eq("", api.nvim_win_get_config(pane_win).relative)
    vim.cmd("normal q"); T.eq(pane_buf, api.nvim_win_get_buf(pane_win)); T.eq(nil, s.pane.detail_win)
    command[3] = "nonzero"; plugin.setup({ ai = { command = command } })
    local accepted = vim.deepcopy(s.pane.result)
    T.eq(s, plugin.refresh())
    assert(vim.wait(5000, function() return s.pane.status:find("Failed", 1, true) ~= nil end))
    T.eq(accepted, s.pane.result); T.eq(nil, s.pane.pending)
    T.eq(3, calls)
  end, debug.traceback)
  fixture:close(); vim.o.columns, agent.run, vim.notify = old_columns, old_run, old_notify
  assert(ok, err)
end)
