-- Every acceptance request runs in a fresh editor. Only this test's disposable
-- repository and XDG cache are shared; no provider executable is ever launched.
local api = vim.api
local workspace = vim.fn.getcwd()
local runtime = vim.env.IRRELEVANT_EXPLAINER_DIFFVIEW_PATH or vim.fn.stdpath("data") .. "/lazy/diffview.nvim"
local plenary = vim.env.IRRELEVANT_EXPLAINER_PLENARY_PATH or vim.fn.stdpath("data") .. "/lazy/plenary.nvim"
local child = vim.env.IRRELEVANT_EXPLAINER_PERSISTENCE_CASE

if child then
  T.test("persistent acceptance child: " .. child, function()
    local case = vim.json.decode(child)
    local root = assert(vim.env.IRRELEVANT_EXPLAINER_PERSISTENCE_REPO)
    assert(vim.fn.stdpath("cache"):find(vim.env.IRRELEVANT_EXPLAINER_TEST_CACHE_ROOT, 1, true) == 1)
    vim.o.columns = 220
    for _ = 1, case.padding or 0 do api.nvim_create_buf(false, true) end
    api.nvim_set_current_dir(root)
    local plugin, sessions = require("irrelevant_explainer"), require("irrelevant_explainer.session")
    local agent, cache = require("irrelevant_explainer.agent"), require("irrelevant_explainer.cache")
    local calls, writes, errors, held = 0, 0, {}, nil
    vim.notify = function(message, level)
      if level == vim.log.levels.ERROR then errors[#errors + 1] = message end
    end
    local write = cache.write
    cache.write = function(source, key, value, config, callback)
      writes = writes + 1
      return write(source, key, value, config, function(ok)
        writes = writes - 1
        assert(ok, "fixture cache write failed")
        if callback then callback(ok) end
      end)
    end
    plugin.setup({ ai = { command = case.argv or { "offline-persistence-fixture-only" }, output = case.output or "plain" },
      cache = { namespace = case.namespace or case.scope } })
    agent.run = function(prompt, _, _, callback)
      calls = calls + 1
      local json = prompt:match("UNTRUSTED REVIEW REQUEST JSON:\n(.*)")
      local answer
      if json then
        assert(sessions.current().pane.review == nil, "review must install atomically after synthesis")
        local request = vim.json.decode(json)
        answer = { version = 3, phase = request.phase, request_id = request.request_id,
          snapshot_id = request.snapshot_id }
        if request.phase == "annotate" then
          answer.units = vim.tbl_map(function(unit)
            return { unit_id = unit.unit_id, notes = {}, findings = {} }
          end, request.units)
        else
          assert(request.phase == "synthesize", "small fixture should not need reduction")
          answer.child_ids = request.child_ids
          answer.review = { title = "Offline persistent review", sections = {
            { heading = "Changes", detail = "The supplied files change their return values.",
              intent_basis = "unknown", evidence = {}, file_ids = { request.manifest[1].file_id } },
          } }
        end
      else
        local target = vim.json.decode(assert(prompt:match("FOCUSED TARGET JSON:\n(.*)")))
        answer = { version = 1, notes = { { summary = "Offline persistent note",
          detail = "Restored structured anchors must bind to the current source.",
          anchors = { vim.deepcopy(target.anchors[1]) }, intent_basis = "unknown", evidence = {} } } }
      end
      local function deliver() callback(answer) end
      if case.action == "preclear" then held = deliver else vim.schedule(deliver) end
      return { cancel = function() end }
    end
    local function wait(predicate)
      assert(vim.wait(10000, predicate, 10), "acceptance timed out: " .. vim.inspect(errors)
        .. " status=" .. vim.inspect(sessions.current() and sessions.current().pane.status))
      assert(#errors == 0, vim.inspect(errors))
    end
    local scope = case.scope
    local requested = scope == "code" and "file" or scope == "diff" and "file" or scope
    local source, view
    if scope == "code" or scope == "selection" then
      -- An unnamed source proves that neither its display label nor selection
      -- coordinates retain an old process's buffer number.
      local buf = api.nvim_create_buf(false, false)
      api.nvim_set_current_buf(buf)
      api.nvim_buf_set_lines(buf, 0, -1, false,
        { "local value = 1", "return value", case.context and "-- changed context" or "-- context" })
      vim.bo[buf].filetype = "lua"
      source = api.nvim_get_current_win()
      if scope == "selection" then vim.cmd("normal! ggVj" .. string.char(27)) end
    else
      vim.opt.runtimepath:append(runtime)
      vim.opt.runtimepath:append(plenary)
      local dv, lib = require("diffview"), require("diffview.lib")
      dv.setup({ watch_index = false, use_icons = false })
      if case.opening ~= "outside" then
        local args = { case.revision or "HEAD", "--selected-file=" .. root .. "/" .. (case.selected or "a.lua") }
        if case.filter then vim.list_extend(args, { "--", case.filter }) end
        dv.open(args)
        wait(function()
          view = lib.get_current_view()
          local state = view and view.cur_layout.b and require("irrelevant_explainer.diffview").current(view.cur_layout.b.id)
          if state and state.selected.path == (case.selected or "a.lua") then source = state.source; return true end
        end)
        api.nvim_set_current_win(source)
        api.nvim_win_set_cursor(source, { 2, 0 })
      else
        vim.cmd.edit(vim.fn.fnameescape(root .. "/a.lua"))
        source = api.nvim_get_current_win()
      end
    end
    local legacy_path, legacy_bytes, sentinel
    if case.legacy then
      -- Captured from require("explainr").explain("file") before the rename,
      -- with explicit offline-persistence-fixture-only/plain and this namespace.
      -- Only the disposable worktree namespace varies. Keep these generation,
      -- target and context digests frozen so an accidental identity bump misses.
      assert(scope == "code" and case.namespace == "rename-continuity")
      local identity = require("irrelevant_explainer.identity")
      local source_hash = identity.hash({ worktree = root })
      local key = identity.hash({ format = 1, prompt = 2, planner = 2, response = 1,
        source = source_hash, mode = "code", scope = "file",
        target = "18fc344a392ea3710759b30ab85e291d81dc9dbbef757fe2d3316485b32b702c",
        context = "d6aae6d63c120956e8074cdf320e87292e66baceb557c443da3f06da1142a855",
        generation = "014505b67095411463b992aea73be4a9e35390d94f073f342961927a5ceacb4a" })
      local storage = vim.fn.stdpath("cache") .. "/explainr/results/v1"
      vim.fn.mkdir(storage .. "/" .. source_hash, "p", 448)
      legacy_path = storage .. "/" .. source_hash .. "/" .. key .. ".json"
      legacy_bytes = vim.json.encode({ version = 1, scope = "file", source = source_hash, key = key,
        answer = { version = 1, notes = { { detail = "Restored structured anchors must bind to the current source.",
          summary = "Offline persistent note", intent_basis = "unknown", evidence = {},
          anchors = { { path = "[unnamed]", side = "buffer", start_line = 1, end_line = 3 } } } } } })
      local fd = assert(vim.uv.fs_open(legacy_path, "w", 384))
      assert(vim.uv.fs_write(fd, legacy_bytes)); assert(vim.uv.fs_close(fd))
      sentinel = storage .. "/unrelated.txt"
      vim.fn.writefile({ "unrelated cache sentinel" }, sentinel)
    end
    local function invoke()
      if case.command then
        vim.cmd((scope == "selection" and "'<,'>" or "") .. "IrrelevantExplainer " .. requested)
      elseif scope == "selection" then
        local buf = api.nvim_win_get_buf(source)
        plugin.explain("selection", { type = "V", pos1 = { buf, 1, 1, 0 }, pos2 = { buf, 2, 1, 0 } })
      else plugin.explain(requested) end
    end
    invoke()
    if case.action == "cancel" then
      plugin.cancel()
      vim.wait(250)
      T.eq(0, calls)
      local s = sessions.current()
      assert(not s or not s.pane.result and not s.pane.review)
      return
    end
    if case.action == "preclear" then
      wait(function() return held ~= nil end)
      vim.cmd("IrrelevantExplainerCacheClear")
      wait(function() return #vim.fn.glob(vim.fn.stdpath("cache") .. "/explainr/results/v1/*/*.json", false, true) == 0 end)
      held()
    end
    wait(function()
      local s = sessions.current()
      return s and not s.pending and (scope == "review" and s.pane.review ~= nil
        or scope ~= "review" and s.pane.result ~= nil)
    end)
    local s = sessions.current()
    local function ready()
      wait(function() return not s.pending and writes == 0 end)
    end
    ready()
    if case.action == "preclear" then
      T.eq(0, #vim.fn.glob(vim.fn.stdpath("cache") .. "/explainr/results/v1/*/*.json", false, true))
    end
    if case.hit then
      T.eq(0, calls)
      T.eq("Ready · cached", scope == "review" and s.review_status or s.pane.status)
    else assert(calls > 0, "expected a cache miss") end
    if legacy_path then
      T.eq(legacy_bytes, table.concat(vim.fn.readfile(legacy_path, "b"), "\n"))
      T.eq({ "unrelated cache sentinel" }, vim.fn.readfile(sentinel))
      T.eq(0, vim.fn.isdirectory(vim.fn.stdpath("cache") .. "/irrelevant_explainer"))
    end
    if scope == "review" then
      T.eq("Offline persistent review", s.pane.review.title)
      assert(s.review_job == nil, "completed restoration must not leave an annotation job")
      if case.selected then
        T.eq(case.selected, require("irrelevant_explainer.diffview").current(s.pane.source).selected.path)
      end
    else
      T.eq("Offline persistent note", s.pane.result.notes[1].summary)
      T.eq(api.nvim_win_get_buf(source), s.snapshot.source_buf or s.snapshot.windows.buffer)
      if scope == "selection" then
        T.eq(1, s.pane.result.notes[1].anchors[1].start_line)
        T.eq(2, s.pane.result.notes[1].anchors[1].end_line)
        T.eq("[unnamed]", s.pane.result.notes[1].anchors[1].path)
      end
    end
    if case.action == "refresh" then
      local before = calls
      api.nvim_set_current_win(s.pane.win)
      vim.cmd("IrrelevantExplainerRefresh")
      wait(function() return calls > before end)
      ready()
    elseif case.action == "clear" then
      local visible = vim.deepcopy(s.pane.result)
      vim.cmd("IrrelevantExplainerCacheClear")
      wait(function() return #vim.fn.glob(vim.fn.stdpath("cache") .. "/explainr/results/v1/*/*.json", false, true) == 0 end)
      T.eq(visible, s.pane.result)
      local before = calls
      api.nvim_set_current_win(source); invoke()
      wait(function() return calls > before end)
      ready()
      -- Leave the cache cleared for the next process as well.
      plugin.clear_cache()
      wait(function() return #vim.fn.glob(vim.fn.stdpath("cache") .. "/explainr/results/v1/*/*.json", false, true) == 0 end)
    end
    if sentinel then T.eq({ "unrelated cache sentinel" }, vim.fn.readfile(sentinel)) end
    plugin.close()
    vim.wait(100)
  end)
  return
end

local function fixture(run)
  local root = vim.fn.tempname()
  vim.fn.mkdir(root, "p"); root = assert(vim.uv.fs_realpath(root))
  local repo, xdg = root .. "/repo", root .. "/cache"
  vim.fn.mkdir(repo, "p"); vim.fn.mkdir(xdg, "p")
  local function git(...)
    local result = vim.system(vim.list_extend({ "git", "-C", repo }, { ... })):wait()
    assert(result.code == 0, result.stderr)
  end
  local ok, err = xpcall(function()
    git("init", "-q"); git("config", "user.name", "Offline persistence")
    git("config", "user.email", "offline@example.invalid")
    for _, name in ipairs({ "a.lua", "b.lua" }) do
      vim.fn.writefile({ "local value = 0", "return value", "-- context" }, repo .. "/" .. name)
    end
    git("add", "."); git("commit", "-qm", "earlier")
    for _, name in ipairs({ "a.lua", "b.lua" }) do
      vim.fn.writefile({ "local value = 1", "return value", "-- context" }, repo .. "/" .. name)
    end
    git("add", "."); git("commit", "-qm", "base")
    for _, name in ipairs({ "a.lua", "b.lua" }) do
      vim.fn.writefile({ "local value = 1", "return value + 1", "-- context" }, repo .. "/" .. name)
    end
    run(function(case)
      local result = vim.system({ vim.v.progpath, "--headless", "-u", "NONE", "-i", "NONE", "-n",
        "-c", "luafile tests/run.lua" }, { cwd = workspace, env = {
          IRRELEVANT_EXPLAINER_TEST = "tests/persistence_test.lua", IRRELEVANT_EXPLAINER_PERSISTENCE_CASE = vim.json.encode(case),
          IRRELEVANT_EXPLAINER_PERSISTENCE_REPO = repo, IRRELEVANT_EXPLAINER_TEST_CACHE_ROOT = xdg, XDG_CACHE_HOME = xdg,
          IRRELEVANT_EXPLAINER_DIFFVIEW_PATH = runtime, IRRELEVANT_EXPLAINER_PLENARY_PATH = plenary,
        } }):wait(30000)
      assert(result.code == 0 and result.signal == 0,
        vim.inspect(case) .. "\n" .. (result.stdout or "") .. (result.stderr or ""))
    end)
  end, debug.traceback)
  vim.fn.delete(root, "rf")
  assert(ok, err)
end

T.test("legacy completed record survives rename unchanged, semantic overrides miss and public clears preserve unrelated files", function()
  fixture(function(run)
    run({ scope = "code", namespace = "rename-continuity", legacy = true, hit = true })
    run({ scope = "code", namespace = "rename-continuity", legacy = true,
      argv = { "different-offline-command" } })
    run({ scope = "code", namespace = "rename-continuity", legacy = true, output = "codex" })
    run({ scope = "code", namespace = "rename-continuity", legacy = true, hit = true,
      command = true, action = "clear" })
  end)
end)

T.test("persistent code and visual selection survive fresh buffer numbers and context edits miss", function()
  fixture(function(run)
    for _, scope in ipairs({ "code", "selection" }) do
      run({ scope = scope, command = true })
      run({ scope = scope, padding = 17, hit = true })
      run({ scope = scope, padding = 9, context = true })
      run({ scope = scope, padding = 23, command = true, hit = true })
    end
  end)
end)

T.test("persistent hits respect cancellation clear and refresh across processes", function()
  fixture(function(run)
    run({ scope = "code" })
    run({ scope = "code", hit = true, action = "cancel" })
    run({ scope = "code", hit = true, action = "refresh" })
    run({ scope = "code", hit = true, action = "clear" })
    run({ scope = "code" })
    run({ scope = "selection", action = "preclear" })
    run({ scope = "selection" }) -- Work started before clear must not repopulate disk.
  end)
end)

if vim.fn.isdirectory(runtime .. "/lua/diffview") ~= 1 then
  print("SKIP persistent Diffview acceptance: missing runtime at " .. runtime)
  return
end

T.test("persistent diff file hunk and whole review reuse across fresh editors", function()
  fixture(function(run)
    for _, scope in ipairs({ "diff", "hunk", "review" }) do
      run({ scope = scope, command = true })
      run({ scope = scope, padding = 19, hit = true, selected = scope == "review" and "b.lua" or nil })
      run({ scope = scope, action = "cancel" })
    end
  end)
end)

T.test("manual and outside HEAD reviews share completed answers in both directions but not filters or revisions", function()
  fixture(function(run)
    for _, direction in ipairs({ "manual-first", "outside-first" }) do
      local first = direction == "outside-first" and "outside" or "manual"
      local second = first == "outside" and "manual" or "outside"
      run({ scope = "review", namespace = direction, opening = first, command = true })
      run({ scope = "review", namespace = direction, opening = second, padding = 21, hit = true,
        selected = second == "manual" and "b.lua" or nil })
      run({ scope = "review", namespace = direction, filter = "a.lua" })
      run({ scope = "review", namespace = direction, revision = "HEAD~1" })
    end
  end)
end)
