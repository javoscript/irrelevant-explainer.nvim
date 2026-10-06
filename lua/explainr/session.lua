local M = { sessions = {} }
local api = vim.api
local contexts, results, retained = {}, {}, {}

local function review_key(state)
  if not state then return end
  return vim.inspect({ state.cwd, state.pair, state.path_args, state.show_untracked,
    state.selected.path, state.selected.oldpath, state.selected.kind })
end

local function remember(session)
  if session.review_key and #session.batches > 0 then
    retained[session.review_key] = { batches = vim.deepcopy(session.batches), scope = session.scope }
  end
end

local function collector(mode) return require("explainr." .. (mode == "code" and "code" or "diff")) end
local function notify(err) vim.notify(err, vim.log.levels.ERROR, { title = "Explainr" }) end

function M.current() return M.sessions[api.nvim_get_current_tabpage()] end

-- Accepted batches are immutable. Only their assembled view is given to UI.
local function render(session, status)
  local value = #session.batches > 0 and { version = 1, notes = {} } or nil
  for _, batch in ipairs(session.batches) do
    for _, note in ipairs(batch.result.notes) do
      value.notes[#value.notes + 1] = vim.deepcopy(note)
    end
  end
  if status == "Ready" and value and #value.notes == 0 then status = "Ready · no notes" end
  session.pane:set(value, status)
end

local function stop_jobs(session)
  for _, key in ipairs({ "collection", "checking", "invocation" }) do
    if session[key] then session[key].cancel(); session[key] = nil end
  end
  for _, request in ipairs(session.queue or {}) do
    if request.collection then request.collection.cancel() end
  end
  session.queue, session.pane.queued = {}, nil
  session.waiters, session.recheck, session.restoring = nil, nil, nil
end

local function discard_pending(session)
  session.generation = session.generation + 1
  stop_jobs(session)
  session.pending, session.pane.pending = nil, nil
end

function M.close(session)
  session = session or M.current()
  if not session or session.closed then return end
  remember(session)
  session.closed = true
  discard_pending(session)
  if session.timer then session.timer:stop(); session.timer:close(); session.timer = nil end
  if session.group then api.nvim_del_augroup_by_id(session.group) end
  if M.sessions[session.tab] == session then M.sessions[session.tab] = nil end
  session.pane:close()
end

function M.cancel()
  local session = M.current()
  if session and not session.closed then
    discard_pending(session)
    render(session, "Cancelled · refresh explicitly")
  end
end

local follow
local function check(session, callback, dirty)
  if session.closed then return end
  if not api.nvim_tabpage_is_valid(session.tab) then M.close(session); return end
  if follow(session) then return end
  if callback then
    session.waiters = session.waiters or {}
    session.waiters[#session.waiters + 1] = callback
  end
  if session.checking then
    -- Events/results arriving after capture need a trailing pass, not another
    -- concurrent read. Poll ticks simply join the outstanding operation.
    if callback or dirty then session.recheck = true end
    return
  end
  local generation = session.generation
  local operation = {}
  operation.cancel = function()
    operation.cancelled = true
    if operation.job then operation.job.cancel() end
  end
  session.checking = operation
  local function owned()
    return not session.closed and session.generation == generation
      and session.checking == operation and not operation.cancelled
  end
  local snapshots = {}
  local pending_snapshot = session.pending and session.pending.snapshot
  local function add(snapshot)
    for _, item in ipairs(snapshots) do if vim.deep_equal(item, snapshot) then return end end
    snapshots[#snapshots + 1] = snapshot
  end
  -- Old stale data only discards accepted batches, never a new collection.
  -- Check the pending snapshot LAST, so slow retained-evidence reads cannot
  -- justify accepting output against an earlier freshness observation.
  for _, batch in ipairs(session.batches) do
    if not pending_snapshot or not vim.deep_equal(batch.snapshot, pending_snapshot) then add(batch.snapshot) end
  end
  if pending_snapshot then add(pending_snapshot) end
  local index, stale_batches = 0, false
  local advance
  local function complete()
    if not owned() then return end
    session.checking = nil
    if stale_batches then
      if session.review_key then retained[session.review_key] = nil end
      session.batches = {}
      session.stale = not session.pending
      render(session, session.pending and session.pane.status or "Stale · context changed · refresh")
    end
    if session.recheck then session.recheck = nil; check(session); return end
    local waiters = session.waiters or {}
    session.waiters = nil
    for _, done in ipairs(waiters) do
      if session.closed or session.generation ~= generation then return end
      done()
    end
  end
  advance = function()
    if not owned() then return end
    index = index + 1
    local snapshot = snapshots[index]
    if not snapshot then complete(); return end
    local delivered = false
    local function checked(fresh)
      if not owned() or delivered then return end
      if follow(session) then return end
      delivered = true
      operation.job = nil
      if not fresh and snapshot == pending_snapshot then
        if session.review_key then retained[session.review_key] = nil end
        session.batches, session.stale = {}, true
        discard_pending(session)
        render(session, "Stale · context changed · refresh")
        return
      end
      stale_batches = stale_batches or not fresh
      advance()
    end
    if session.mode == "diff" then
      local job = collector(session.mode).fresh_async(snapshot, checked)
      if not delivered and owned() then operation.job = job end
    else checked(collector(session.mode).fresh(snapshot)) end
  end
  advance()
end

local function watch(session)
  session.group = api.nvim_create_augroup("ExplainrSession" .. session.pane.win, { clear = true })
  local queued = false
  local function schedule()
    if session.closed or queued then return end
    queued = true
    vim.schedule(function() queued = false; check(session, nil, true) end)
  end
  api.nvim_create_autocmd({ "TextChanged", "TextChangedI", "BufWritePost", "BufWinEnter", "TabEnter", "FocusGained" }, {
    group = session.group, callback = schedule,
  })
  if session.mode == "diff" then
    api.nvim_create_autocmd("User", { group = session.group,
      pattern = { "DiffviewDiffBufWinEnter", "DiffviewViewPostLayout", "DiffviewViewEnter" }, callback = schedule })
    api.nvim_create_autocmd("User", { group = session.group, pattern = "DiffviewViewClosed", callback = function()
      -- This payloadless event runs after tab teardown, possibly in another
      -- tab. Inspect the owned view, not whichever tab now has focus. User
      -- events are outside WinClosed, so cancel jobs and clean up immediately.
      local lib = package.loaded["diffview.lib"]
      local view = lib and lib.tabpage_to_view(session.tab)
      if not api.nvim_tabpage_is_valid(session.tab) or lib and (not view or view.closing:check()) then
        M.close(session)
      end
    end })
  end
  -- Freshness polling never re-explains edits. Only following a different
  -- review entry may infer, when navigation auto-explanation is enabled.
  session.timer = vim.uv.new_timer()
  session.timer:start(1000, 1000, vim.schedule_wrap(function() check(session) end))
end

local function identity(mode, snapshot, state)
  if mode == "code" then return { mode = mode, buf = snapshot.source_buf, cwd = snapshot.cwd } end
  state = state or (snapshot and snapshot.capture and snapshot.capture.state)
  if state then
    local buffers = {}
    for side, pane in pairs(state.panes or {}) do buffers[side] = pane.buf end
    return { mode = mode, cwd = state.cwd, windows = state.windows, buffers = buffers,
      selected = state.selected, pair = state.pair, path_args = state.path_args, tab = state.tabpage }
  end
  -- Minimal mocks need not expose the real adapter descriptor.
  if snapshot then return { mode = mode, cwd = snapshot.cwd, windows = snapshot.windows,
    comparison = snapshot.comparison and { pair = snapshot.comparison.pair },
    path = snapshot.target.path, oldpath = snapshot.target.oldpath,
    paths = vim.tbl_map(function(anchor) return { anchor.path, anchor.side } end, snapshot.target.anchors or {}) } end
end

follow = function(session)
  if session.mode ~= "diff" then return false end
  local adapter = require("explainr.diffview")
  local selected = adapter.selection(session.pane.source)
  if not selected then return false end
  local key = review_key(selected)
  if key ~= session.review_key then
    remember(session)
    discard_pending(session)
    session.review_key, session.batches, session.restoring = key, {}, true
    session.snapshot, session.context, session.pane.snapshot = nil, nil, nil
    session.stale = false
    render(session, retained[key] and "Checking saved explanations" or "No explanations · request file or hunk")
  end
  if not session.restoring then return false end
  if session.checking then return true end
  -- Diffview advertises the next entry before its replacement buffers load.
  -- Wait for a coherent pair; never navigate Diffview to validate old notes.
  local state = adapter.current(session.pane.source)
  if not state then return true end
  session.pane.snapshot = { windows = state.windows }
  local saved = retained[key]
  if not saved then
    local auto = require("explainr").config.diff.auto_explain
    -- M.start owns the current tab's session. Defer background-tab navigation
    -- until that tab is active, instead of opening/replacing another tab's pane.
    if auto and M.current() ~= session then return true end
    session.restoring = nil
    if auto then
      M.start("diff", "file", { win = state.source })
      return true
    end
    render(session, "No explanations · request file or hunk")
    return false
  end
  local operation, generation, batches, index = {}, session.generation, {}, 0
  operation.cancel = function()
    operation.cancelled = true
    if operation.job then operation.job.cancel() end
  end
  session.checking = operation
  local function owned()
    return not session.closed and not operation.cancelled and session.generation == generation
      and session.checking == operation and session.review_key == key
  end
  local advance
  advance = function()
    if not owned() then return end
    index = index + 1
    local batch = saved.batches[index]
    if not batch then
      session.checking, session.restoring = nil, nil
      session.batches, session.scope = batches, saved.scope
      session.snapshot = batches[#batches].snapshot
      session.context = identity("diff", session.snapshot)
      session.source, session.pane.snapshot = session.snapshot.source, session.snapshot
      remember(session)
      render(session, "Ready · restored")
      return
    end
    local delivered = false
    local job = collector("diff").restore_async(batch.snapshot, session.pane.source, function(snapshot)
      if not owned() then return end
      delivered, operation.job = true, nil
      if not snapshot then
        retained[key], session.checking, session.restoring = nil, nil, nil
        session.stale = true
        if require("explainr").config.diff.auto_explain then
          session.restoring = true
          follow(session)
        else render(session, "Stale · context changed · refresh") end
        return
      end
      batches[#batches + 1] = { snapshot = snapshot, result = vim.deepcopy(batch.result) }
      advance()
    end)
    if not delivered and owned() then operation.job = job end
  end
  advance()
  return true
end

local launch, advance_queue

local function fail(session, err)
  session.pending, session.pane.pending = nil, nil
  notify(err)
  advance_queue(session, "Failed · see :messages")
  check(session)
  return session, err
end

launch = function(session, snapshot, options, config)
  snapshot = vim.deepcopy(snapshot)
  local context = identity(session.mode, snapshot)
  if session.context and not vim.deep_equal(session.context, context) then session.batches = {} end
  session.context = context
  session.snapshot, session.pane.snapshot = snapshot, snapshot
  session.source = snapshot.source or snapshot.windows.buffer
  session.selection = session.scope == "selection" and snapshot.target.selection or nil
  session.pending.snapshot, session.pane.pending.snapshot = snapshot, snapshot
  session.pane.pending.windows = snapshot.windows
  render(session, "Pending · building prompt")
  local prompt = require("explainr.prompt")
  local context_key = snapshot.review_fingerprint or snapshot.fingerprint
  contexts[context_key] = contexts[context_key] or prompt.context(snapshot)
  local request, err = prompt.build(snapshot, config.context.max_bytes, contexts[context_key])
  if not request then return fail(session, err) end
  -- Function keys preserve decoder identity; captured configuration also keys
  -- the cache, rather than whatever setup() contains when output arrives.
  results[config.ai.output] = results[config.ai.output] or {}
  local cache = results[config.ai.output]
  local result_key = snapshot.fingerprint .. "\0" .. vim.inspect({ config.ai, config.context })
  local generation = session.generation
  local function accept(raw, failure, cached)
    if session.closed or session.generation ~= generation
      or not session.pending or session.pending.snapshot ~= snapshot then return end
    session.invocation = nil
    render(session, "Pending · checking result context")
    check(session, function()
      local value
      if not failure then value, failure = require("explainr.model").validate(raw, snapshot) end
      if failure then fail(session, failure); return end
      cache[result_key] = vim.deepcopy(value)
      local batch = { snapshot = snapshot, result = vim.deepcopy(value) }
      local replaced = false
      for index, previous in ipairs(session.batches) do
        if vim.deep_equal(previous.snapshot.target, snapshot.target) then
          session.batches[index], replaced = batch, true
          break
        end
      end
      if not replaced then session.batches[#session.batches + 1] = batch end
      session.pending, session.pane.pending, session.stale = nil, nil, false
      remember(session)
      advance_queue(session, cached and "Ready · cached" or "Ready")
    end)
  end
  if not options.refresh and cache[result_key] then
    accept(vim.deepcopy(cache[result_key]), nil, true)
  else
    render(session, "Pending · external agent")
    local delivered = false
    local job = require("explainr.agent").run(request, config.ai, snapshot.cwd, function(raw, failure)
      if delivered then return end
      delivered = true
      accept(raw, failure)
    end)
    if not delivered then session.invocation = job end
  end
  return session
end

advance_queue = function(session, status)
  local request = table.remove(session.queue or {}, 1)
  if not request then render(session, status); return end
  session.scope, session.source = request.scope, request.source
  session.pending, session.pane.pending = request, request
  session.collection = request.collection
  if request.collected then
    if request.error then fail(session, request.error)
    else launch(session, request.snapshot, request.options, request.config) end
  else render(session, "Pending · collecting comparison") end
end

function M.start(mode, scope, options)
  options = options or {}
  local previous = M.current()
  local source = options.win or api.nvim_get_current_win()
  if source == 0 then source = api.nvim_get_current_win() end
  if previous and (source == previous.pane.win or source == previous.pane.detail_win) then source = previous.pane.source end
  if previous and previous.pane.detail_win and previous.pane.back then
    -- A new request can beat deferred follow/freshness checks. Only resolve
    -- the reader cursor while its captured source identity still owns the
    -- displayed buffers; otherwise collapse without navigating replacements.
    local displayed = previous.pane.snapshot
    local same = previous.mode == mode and displayed and api.nvim_win_is_valid(previous.pane.source)
    if same and mode == "code" then
      same = api.nvim_win_get_buf(previous.pane.source) == displayed.source_buf
        and api.nvim_win_get_buf(source) == displayed.source_buf
    elseif same then
      local state = require("explainr.diffview").current(previous.pane.source)
      same = state and vim.deep_equal(identity("diff", displayed), identity("diff", nil, state))
        and (source == state.windows.old or source == state.windows.new)
    end
    previous.pane:back(not same)
  end
  local config = vim.deepcopy(require("explainr").config)
  local snapshot, err, collection, session, generation
  local request = { source = source, scope = scope, row = api.nvim_win_get_cursor(source)[1],
    options = vim.deepcopy(options), config = config }
  local previous_windows = previous and (previous.snapshot and previous.snapshot.windows
    or previous.pane.pending and previous.pane.pending.windows)
  if mode == "code" then
    if previous then discard_pending(previous) end
    snapshot, err = collector(mode).collect(source, scope, options.selection)
    if not snapshot then
      if previous then fail(previous, err) else notify(err) end
      return nil, err
    end
  else
    local delivered = false
    collection = collector(mode).collect_async(source, scope, function(value, failure)
      if delivered or not session or session.closed or session.generation ~= generation then return end
      delivered = true
      request.collection, request.collected = nil, true
      request.snapshot, request.error = value, not value and (failure or "Diff collection failed") or nil
      if request == session.pending then
        session.collection = nil
        if request.error then fail(session, request.error); return end
        launch(session, value, options, config)
      else render(session, session.pane.status) end
    end, vim.tbl_extend("force", config.context, { target = options.target }))
  end
  local context = identity(mode, snapshot, collection and collection.state)
  local compatible = previous and previous.mode == mode
    and (not context or not previous.context or vim.deep_equal(previous.context, context))
  -- Without a descriptor, defer full diff identity to launch, but never reuse
  -- a pane for a source outside its loaded pair.
  if compatible and mode == "diff" and not context then
    compatible = source == previous.source or previous_windows
      and (source == previous_windows.old or source == previous_windows.new)
  end
  local append = compatible and mode == "diff" and scope == "hunk" and previous.pending and not options.refresh
  if previous and mode == "diff" and not append then discard_pending(previous) end
  if previous and not compatible then M.close(previous) end
  session = compatible and previous or { mode = mode, generation = 1, batches = {}, tab = api.nvim_get_current_tabpage() }
  if mode == "diff" then
    session.review_key = review_key(collection and collection.state or snapshot and snapshot.capture and snapshot.capture.state
      or require("explainr.diffview").selection(source))
  end
  generation = session.generation
  if not compatible then
    session.pane = require("explainr.ui").open(source, snapshot, nil, function() M.close(session) end,
      mode == "diff" and require("explainr.diffview").keymaps or nil)
    M.sessions[session.tab] = session
    watch(session)
  end
  session.pane.source = source
  request.windows = snapshot and snapshot.windows or collection and collection.state and collection.state.windows
    or compatible and previous_windows or { [mode == "code" and "buffer" or "new"] = source }
  request.collection = collection
  session.queue = session.queue or {}
  session.pane.queued = session.queue
  if append then
    session.queue[#session.queue + 1] = request
    render(session, session.pane.status)
    return session
  end
  session.mode, session.scope, session.source, session.stale = mode, scope, source, false
  session.selection = options.selection
  session.pending, session.pane.pending = request, request
  if context then session.context = context end
  session.collection = collection
  render(session, "Pending · collecting comparison")
  if snapshot then return launch(session, snapshot, options, config) end
  return session
end

function M.refresh()
  local session = M.current()
  if not session then local err = "No explanation to refresh; use ExplainrCode or ExplainrDiff"; notify(err); return nil, err end
  -- Diff targets are recaptured from the followed source: retained anchors may
  -- have changed after edits. Only freshness reads retain immutable targets.
  return M.start(session.mode, session.scope, { win = session.pane.source, selection = session.selection, refresh = true })
end

return M
