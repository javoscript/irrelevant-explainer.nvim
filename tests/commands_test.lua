local api = vim.api
local plugin, sessions = require("irrelevant_explainer"), require("irrelevant_explainer.session")
local adapter = require("irrelevant_explainer.diffview")

T.test("fresh loader exposes only the renamed commands and Lua package", function()
  local check = [[lua
    assert(vim.g.loaded_irrelevant_explainer); assert(not vim.g.loaded_explainr)
    local p = require('irrelevant_explainer').setup()
    assert(not p.code and not p.diff)
    for name in pairs(vim.api.nvim_get_commands({})) do assert(not name:match('^Explainr')) end
    for _, suffix in ipairs({'', 'Review', 'Refresh', 'Cancel', 'Close', 'CacheClear', 'ToggleAutoExplain'}) do
      assert(vim.fn.exists(':IrrelevantExplainer' .. suffix) == 2)
    end
    assert(vim.deep_equal({'file', 'hunk', 'review', 'selection'},
      vim.fn.getcompletion('IrrelevantExplainer ', 'cmdline')))
    assert(not pcall(require, 'explainr')); assert(not package.loaded['diffview'])
    assert(not package.loaded['irrelevant_explainer.session'])
    print('fresh renamed startup verified')
  ]]
  local result = vim.system({ vim.v.progpath, "--headless", "-u", "NONE", "-i", "NONE", "-n",
    "--cmd", "set runtimepath^=" .. vim.fn.fnameescape(vim.fn.getcwd()),
    "-c", check, "-c", "qa!" }):wait(10000)
  assert(result.code == 0 and result.signal == 0, (result.stdout or "") .. (result.stderr or ""))
end)

T.test("ordinary routing needs no Diffview and rejects utility and hunk origins", function()
  plugin.close(); plugin.setup()
  local notify, messages = vim.notify, {}
  vim.notify = function(message) messages[#messages + 1] = message end
  local previous, buf = api.nvim_get_current_buf(), api.nvim_create_buf(false, false)
  api.nvim_set_current_buf(buf)
  local ok, err = xpcall(function()
    T.eq("code", adapter.origin(api.nvim_get_current_win()))
    vim.wo.diff = true
    T.eq("code", adapter.origin(api.nvim_get_current_win()))
    T.eq(nil, plugin.explain("hunk")); assert(messages[#messages]:find("source pane"))
    T.eq(nil, package.loaded["diffview.lib"])
    vim.bo[buf].buftype = "nofile"
    T.eq(nil, plugin.explain("file")); assert(messages[#messages]:find("source window"))
    T.eq(nil, next(sessions.openings))
  end, debug.traceback)
  vim.wo.diff = false
  api.nvim_set_current_buf(previous); api.nvim_buf_delete(buf, { force = true }); vim.notify = notify
  assert(ok, err)
end)

T.test("missing Diffview and immediate cancellation cannot start opening or inference", function()
  local loader, notify, messages = package.preload["diffview"], vim.notify, {}
  local agent = require("irrelevant_explainer.agent")
  local run, calls = agent.run, 0
  agent.run = function() calls = calls + 1; error("unexpected inference") end
  vim.notify = function(message) messages[#messages + 1] = message end
  package.preload["diffview"] = function() error("missing optional dependency") end
  local ok, err = xpcall(function()
    local cancelled = plugin.explain("review"); plugin.cancel()
    vim.wait(50); T.eq(true, cancelled.done); T.eq(nil, next(sessions.openings))
    local missing = plugin.explain("review")
    assert(vim.wait(1000, function() return missing.done and not next(sessions.openings) end))
    assert(messages[#messages]:find("Diffview is unavailable", 1, true))
    T.eq(0, calls)
  end, debug.traceback)
  package.preload["diffview"], package.loaded["diffview"] = loader, nil
  vim.notify, agent.run = notify, run
  assert(ok, err)
end)

local runtime = vim.env.IRRELEVANT_EXPLAINER_DIFFVIEW_PATH or vim.fn.stdpath("data") .. "/lazy/diffview.nvim"
if vim.fn.isdirectory(runtime .. "/lua/diffview") ~= 1 then
  print("SKIP command integration: missing Diffview at " .. runtime)
  return
end
if vim.env.IRRELEVANT_EXPLAINER_COMMAND_CHILD ~= "1" then
  T.test("unified commands with real Diffview in isolated Neovim", function()
    local result = vim.system({ vim.v.progpath, "--headless", "-u", "NONE", "-i", "NONE", "-n",
      "-c", "luafile tests/run.lua" }, { cwd = vim.fn.getcwd(), env = {
        IRRELEVANT_EXPLAINER_TEST = "tests/commands_test.lua", IRRELEVANT_EXPLAINER_COMMAND_CHILD = "1",
        IRRELEVANT_EXPLAINER_DIFFVIEW_PATH = runtime } }):wait(120000)
    print((result.stdout or "") .. (result.stderr or ""))
    assert(result.code == 0 and result.signal == 0, "command integration failed")
  end)
  return
end
vim.opt.runtimepath:append(runtime)
vim.opt.runtimepath:append(vim.env.IRRELEVANT_EXPLAINER_PLENARY_PATH or vim.fn.stdpath("data") .. "/lazy/plenary.nvim")
local dv, lib, agent = require("diffview"), require("diffview.lib"), require("irrelevant_explainer.agent")

local function fixture(run)
  plugin.close()
  local root = vim.fn.tempname() .. " working tree;'"
  vim.fn.mkdir(root, "p"); root = vim.uv.fs_realpath(root)
  local f = { root = root, cwd = vim.fn.getcwd(), tab = api.nvim_get_current_tabpage(), jobs = {}, errors = {} }
  local notify, execute, columns = vim.notify, agent.run, vim.o.columns
  vim.o.columns = 220
  function f.git(...)
    local result = vim.system(vim.list_extend({ "git", "-C", root }, { ... })):wait()
    assert(result.code == 0, result.stderr); return vim.trim(result.stdout)
  end
  function f.write(path, text)
    local fd = assert(vim.uv.fs_open(root .. "/" .. path, "w", 420))
    assert(vim.uv.fs_write(fd, text)); vim.uv.fs_close(fd)
  end
  f.git("init", "-q"); f.git("config", "user.name", "Offline commands")
  f.git("config", "user.email", "offline@example.invalid")
  for _, name in ipairs({ "mixed.lua", "staged.lua", "working.lua", "undone.lua" }) do f.write(name, "base\n") end
  f.git("add", "."); f.git("commit", "-qm", "base"); f.head = f.git("rev-parse", "HEAD")
  for _, name in ipairs({ "mixed.lua", "staged.lua", "undone.lua", "added.lua" }) do f.write(name, "staged\n") end
  f.git("add", ".")
  f.write("mixed.lua", "final\n"); f.write("working.lua", "working\n"); f.write("undone.lua", "base\n")
  f.write("untracked.lua", "not in HEAD comparison\n")
  f.index = f.git("write-tree")
  vim.cmd("tabnew"); f.origin_tab, f.origin = api.nvim_get_current_tabpage(), api.nvim_get_current_win()
  vim.cmd.edit(vim.fn.fnameescape(root .. "/mixed.lua"))
  dv.setup({ watch_index = false, use_icons = false })
  plugin.setup({ ai = { command = { "fixture-only" }, output = "plain" }, diff = { auto_explain = true }, cache = { enabled = false } })
  vim.notify = function(message, level)
    if level == vim.log.levels.ERROR then f.errors[#f.errors + 1] = message end
  end
  agent.run = function(prompt, config, _, callback)
    local request = prompt:match("UNTRUSTED REVIEW REQUEST JSON:\n(.*)")
    local job = { request = request and vim.json.decode(request), config = config, callback = callback }
    if not request then job.target = vim.json.decode(prompt:match("FOCUSED TARGET JSON:\n(.*)")) end
    job.cancel = function() job.cancelled = true end
    f.jobs[#f.jobs + 1] = job
    return job
  end
  function f.wait(predicate)
    assert(vim.wait(7000, predicate, 20), vim.inspect(f.errors))
  end
  function f.open()
    local operation = plugin.explain("review")
    f.wait(function() return operation.done end)
    assert(#f.errors == 0, vim.inspect(f.errors))
    return operation
  end
  local ok, err = xpcall(function() run(f) end, debug.traceback)
  for _, operation in pairs(sessions.openings) do operation.cancel() end
  sessions.openings = {}
  for _, session in pairs(sessions.sessions) do sessions.close(session) end
  for _, view in ipairs(vim.list_extend({}, lib.views)) do
    if view.adapter and view.adapter.ctx.toplevel:find(root, 1, true) then
      if view.tabpage and api.nvim_tabpage_is_valid(view.tabpage) then api.nvim_set_current_tabpage(view.tabpage); dv.close()
      else lib.dispose_view(view) end
    end
  end
  if api.nvim_tabpage_is_valid(f.origin_tab) then api.nvim_set_current_tabpage(f.origin_tab); vim.cmd("tabclose!") end
  api.nvim_set_current_tabpage(f.tab); api.nvim_set_current_dir(f.cwd)
  for _, buf in ipairs(api.nvim_list_bufs()) do
    if api.nvim_buf_is_valid(buf) and api.nvim_buf_get_name(buf):find(root, 1, true) then api.nvim_buf_delete(buf, { force = true }) end
  end
  vim.notify, agent.run, vim.o.columns = notify, execute, columns
  vim.fn.delete(root, "rf")
  assert(ok, err)
end

T.test("outside review captures net HEAD-to-working changes and window-owned file routing", function()
  fixture(function(f)
    dv.open({ "-C" .. f.root, "--cached" })
    local unrelated = lib.get_current_view()
    f.wait(function() return unrelated.initialized and adapter.current(unrelated.cur_layout.b.id) end)
    api.nvim_set_current_win(f.origin)
    local op = plugin.explain("review")
    T.eq(op, plugin.explain("review"))
    f.wait(function() return #f.jobs == 1 end)
    assert(unrelated ~= op.view); T.eq(3, unrelated.right.type)
    local s, state = sessions.current(), adapter.current(op.view.cur_layout.b.id)
    T.eq(f.root, state.cwd); T.eq(f.head, state.pair.old.commit); T.eq("local", state.pair.new.type)
    T.eq({}, state.path_args); T.eq(false, state.show_untracked)
    local versions, originals, paths = {}, {}, {}
    for _, file in ipairs(s.pending.snapshot.files) do
      if file.side == "new" then versions[file.path] = table.concat(file.lines, "\n") end
      if file.side == "old" then originals[file.path] = table.concat(file.lines, "\n") end
    end
    T.eq({ ["added.lua"] = "staged", ["mixed.lua"] = "final", ["staged.lua"] = "staged", ["working.lua"] = "working" }, versions)
    T.eq({ ["mixed.lua"] = "base", ["staged.lua"] = "base", ["working.lua"] = "base" }, originals)
    for _, entry in ipairs(s.pending.snapshot.comparison.manifest) do T.eq(nil, entry.patch) end
    T.eq("annotate", f.jobs[1].request.phase)
    local plan = require("irrelevant_explainer.review").inspect(s.review_job)
    T.eq(2, #plan.annotations); T.eq(3, #f.jobs[1].request.units)
    for _, unit in ipairs(plan.units) do paths[#paths + 1] = unit.target.path end
    table.sort(paths)
    T.eq({ "added.lua", "mixed.lua", "staged.lua", "working.lua" }, paths)
    T.eq("final", versions["mixed.lua"]); T.eq("staged", versions["staged.lua"])
    T.eq("working", versions["working.lua"]); T.eq("staged", versions["added.lua"])
    T.eq(f.index, f.git("write-tree")); T.eq("final", vim.fn.readfile(f.root .. "/mixed.lua")[1])
    T.eq(nil, next(sessions.openings))
    T.eq("diff", adapter.origin(state.source)); T.eq("panel", adapter.origin(op.view.panel.winid))
    api.nvim_set_current_win(op.view.panel.winid)
    T.eq(nil, plugin.explain("file")); T.eq(nil, plugin.explain("hunk"))
    local selected, panel = op.view.cur_entry, api.nvim_get_current_win()
    T.eq(s, plugin.explain("review")); T.eq(panel, api.nvim_get_current_win()); T.eq(selected, op.view.cur_entry)
    api.nvim_set_current_win(s.pane.win); T.eq(s, plugin.explain("file")); T.eq("file", s.queue[#s.queue].scope)
    api.nvim_set_current_win(f.origin)
    T.eq(api.nvim_win_get_buf(state.source), api.nvim_get_current_buf())
    T.eq("code", adapter.origin(f.origin))
    local code = plugin.explain("file"); T.eq("code", code.mode)
    api.nvim_set_current_win(state.source); plugin.cancel()
    local rev = op.view.cur_entry.revs.a
    op.view.cur_entry.revs.a = { type = 3, stage = 2 }
    T.eq("diff", adapter.origin(state.source))
    local before = #f.jobs
    plugin.explain("file"); vim.wait(100); T.eq(before, #f.jobs)
    op.view.cur_entry.revs.a = rev
  end)
end)

T.test("opening waits for buffers, deduplicates in the new view and preserves configuration", function()
  fixture(function(f)
    local current, held = adapter.current, true
    adapter.current = function(...) if held then return nil, "loading" end; return current(...) end
    local ok, err = xpcall(function()
      local captured = vim.deepcopy(plugin.config)
      local epoch = require("irrelevant_explainer.cache").epoch()
      local op = plugin.explain("review")
      plugin.clear_cache() -- Opening is already pending, even before collection.
      plugin.setup({ ai = { command = { "changed-after-invocation" }, output = "plain", timeout_ms = 1 },
        context = { max_bytes = 100, radius = 0 }, review = { request_max_bytes = 100, max_requests = 1 },
        cache = { enabled = true, namespace = "changed-after-invocation" } })
      f.wait(function() return op.view and op.view.initialized end)
      T.eq(0, #f.jobs); T.eq(nil, sessions.current()); T.eq(op, plugin.explain("review"))
      op.view.emitter:emit("file_open_post", op.view.cur_entry); op.view.emitter:emit("files_updated", op.view.files)
      vim.wait(100); T.eq(0, #f.jobs)
      api.nvim_buf_set_lines(api.nvim_win_get_buf(f.origin), 0, -1, false, { "edited while opening" })
      held = false
      f.wait(function() return #f.jobs == 1 end)
      T.eq({ "fixture-only" }, f.jobs[1].config.command)
      T.eq(epoch, sessions.current().pending.cache_epoch)
      assert(epoch ~= require("irrelevant_explainer.cache").epoch())
      local config = require("irrelevant_explainer.review").config(sessions.current().review_job)
      for _, key in ipairs({ "ai", "context", "review", "cache" }) do T.eq(captured[key], config[key]) end
      local found
      for _, file in ipairs(sessions.current().pending.snapshot.files) do
        if file.path == "mixed.lua" and file.side == "new" then found = file.lines end
      end
      T.eq({ "edited while opening" }, found)
      T.eq(true, sessions.current().pane.auto_explain)
      op.view.emitter:emit("file_open_post", op.view.cur_entry); vim.wait(100); T.eq(1, #f.jobs)
    end, debug.traceback)
    adapter.current = current
    assert(ok, err)
  end)
end)

T.test("cancel close replacement and source/view loss retire opening callbacks", function()
  for _, action in ipairs({ "cancel", "close", "replace", "source", "view", "comparison", "timeout" }) do
    fixture(function(f)
      local current, clock = adapter.current, vim.uv.now
      adapter.current = function() return nil, "held" end
      local ok, err = xpcall(function()
        local op = plugin.explain("review")
        f.wait(function() return op.view and op.view.initialized and current(op.view.cur_layout.b.id) end)
        if action == "cancel" then plugin.cancel()
        elseif action == "close" then plugin.close()
        elseif action == "replace" then api.nvim_set_current_win(f.origin); plugin.explain("file")
        elseif action == "source" then api.nvim_win_close(f.origin, true)
        elseif action == "view" then dv.close()
        elseif action == "comparison" then op.view.left.commit = string.rep("a", 40)
        else vim.uv.now = function() return clock() + 20000 end end
        f.wait(function() return op.done end)
        vim.uv.now = clock
        adapter.current = current
        op.view.emitter:emit("file_open_post", op.view.cur_entry); vim.wait(120)
        for _, job in ipairs(f.jobs) do assert(not job.request, action) end
        if action == "cancel" or action == "close" then assert(api.nvim_tabpage_is_valid(op.view.tabpage)) end
        T.eq(nil, next(sessions.openings))
      end, debug.traceback)
      adapter.current, vim.uv.now = current, clock
      assert(ok, err)
    end)
  end
end)

T.test("outside review rejects defaults clean trees absent HEAD and metadata-only targets", function()
  for _, case in ipairs({ "defaults", "filters", "clean", "head", "binary", "not-repository" }) do
    fixture(function(f)
      if case == "defaults" then dv.setup({ watch_index = false, default_args = { DiffviewOpen = { "--cached" } } })
      elseif case == "filters" then dv.setup({ watch_index = false, default_args = { DiffviewOpen = { "HEAD", "--", "mixed.lua" } } })
      elseif case == "clean" or case == "binary" then
        f.git("reset", "--hard", "HEAD") -- Disposable fixture only.
        vim.cmd("edit!")
        if case == "binary" then f.write("mixed.lua", "\0binary\n"); vim.cmd("edit!") end
      elseif case == "head" then f.git("symbolic-ref", "HEAD", "refs/heads/unborn")
      else api.nvim_buf_set_name(0, vim.fn.tempname() .. "/outside.lua") end
      local op = plugin.explain("review")
      f.wait(function() return op.done end)
      f.wait(function() return #f.errors > 0 end)
      T.eq(0, #f.jobs)
      if case == "defaults" or case == "filters" then assert(f.errors[#f.errors]:find("default_args")) end
    end)
  end
end)

T.test("unnamed origin and linked worktree resolve their own repository", function()
  for _, kind in ipairs({ "unnamed", "worktree" }) do
    fixture(function(f)
      local expected, buf = f.root, api.nvim_create_buf(false, false)
      if kind == "worktree" then
        expected = f.root .. "/linked"
        f.git("worktree", "add", "--detach", expected, "HEAD")
        f.write("linked/mixed.lua", "linked only\n")
        api.nvim_buf_set_name(buf, expected .. "/mixed.lua")
        api.nvim_set_current_buf(buf); vim.cmd("edit!")
      else
        api.nvim_set_current_buf(buf)
        api.nvim_win_call(f.origin, function() vim.cmd.lcd(vim.fn.fnameescape(f.root)) end)
      end
      local op = f.open()
      f.wait(function() return #f.jobs == 1 end)
      T.eq(expected, adapter.current(op.view.cur_layout.b.id).cwd)
      if kind == "worktree" then T.eq(1, #f.jobs[1].request.units); T.eq("mixed.lua", f.jobs[1].request.units[1].target.path) end
    end)
  end
end)

T.test("background opening preserves focus and unsaved text then reuses and refreshes the review", function()
  fixture(function(f)
    local current, held = adapter.current, true
    adapter.current = function(...) if held then return nil, "loading" end; return current(...) end
    local ok, err = xpcall(function()
      api.nvim_buf_set_lines(0, 0, -1, false, { "unsaved overlay" })
      local op = plugin.explain("review")
      f.wait(function() return op.view and op.view.initialized and current(op.view.cur_layout.b.id) end)
      local entry = op.view.files.working[#op.view.files.working]
      op.view:set_file(entry)
      f.wait(function()
        local state = current(op.view.cur_layout.b.id)
        return state and state.selected.path == entry.path
      end)
      api.nvim_set_current_win(f.origin)
      local focus = api.nvim_get_current_win()
      held = false
      f.wait(function() return #f.jobs == 1 end)
      T.eq(focus, api.nvim_get_current_win())
      local s = sessions.sessions[op.view.tabpage]
      local snapshot = s.pending.snapshot
      for _, file in ipairs(snapshot.files) do
        if file.path == "mixed.lua" and file.side == "new" then T.eq({ "unsaved overlay" }, file.lines) end
      end
      for n = 1, 2 do
        f.wait(function() return #f.jobs == n end)
        local job, req = f.jobs[n], f.jobs[n].request
        T.eq("annotate", req.phase); T.eq(nil, s.pane.review)
        job.callback({ version = 3, phase = req.phase, request_id = req.request_id, snapshot_id = req.snapshot_id,
          units = vim.tbl_map(function(unit) return { unit_id = unit.unit_id, notes = {}, findings = {} } end, req.units) })
      end
      f.wait(function() return #f.jobs == 3 end)
      T.eq(nil, s.pane.review)
      local req = f.jobs[3].request
      T.eq("synthesize", req.phase)
      f.jobs[3].callback({ version = 3, phase = req.phase, request_id = req.request_id, snapshot_id = req.snapshot_id,
        child_ids = req.child_ids, review = { title = "Net change", sections = {
        { heading = "Working tree", detail = "The supplied changes update the files.", intent_basis = "unknown",
          evidence = {}, file_ids = { req.manifest[1].file_id } },
      } } })
      f.wait(function() return not s.pending end)
      T.eq(focus, api.nvim_get_current_win()); T.eq("Net change", s.pane.review.title)
      T.eq(f.index, f.git("write-tree")); T.eq("final", vim.fn.readfile(f.root .. "/mixed.lua")[1])
      api.nvim_set_current_win(s.pane.win)
      plugin.explain("review"); f.wait(function() return not s.pending end); T.eq(3, #f.jobs)
      plugin.refresh(); f.wait(function() return #f.jobs == 4 end); T.eq("annotate", f.jobs[4].request.phase)
    end, debug.traceback)
    adapter.current = current
    assert(ok, err)
  end)
end)
