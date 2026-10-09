vim.opt.runtimepath:prepend(vim.g.capture_checkout or vim.fn.getcwd())
for _, path in ipairs(vim.g.capture_runtime or {}) do vim.opt.runtimepath:append(path) end
-- Exercise the installed optional plugin normally, without loading user config.
if #(vim.g.capture_runtime or {}) > 0 then vim.cmd("runtime plugin/render-markdown.lua") end
if vim.g.capture_state:match("^detail%-markdown.*%-plain$") then
  vim.treesitter.start = function() error("parser unavailable in fallback capture") end
end
if not vim.g.capture_personal then
  vim.o.termguicolors = true
  vim.o.laststatus = 3
  vim.o.statusline = " EXTERNAL EDITOR BAR %= untouched by Irrelevant Explainer "
  vim.o.showmode = false
  vim.o.signcolumn = "auto:2"
  if vim.g.capture_state == "detail-light" or vim.g.capture_state == "detail-highlight-rose-pine-light" then
    vim.o.background = "light"
  end
  vim.cmd("colorscheme default")
  vim.api.nvim_set_hl(0, "Normal", vim.g.capture_state == "detail-light"
    and { fg = "#263544", bg = "#fafafa" } or { fg = "#d5dce5", bg = "#18212b" })
  vim.api.nvim_set_hl(0, "StatusLine", { fg = "#adc6dd", bg = "#263544" })
end
if vim.g.capture_state:match("^publication%-code") then
  local api = vim.api
  local source = api.nvim_get_current_win()
  api.nvim_buf_set_name(0, vim.fn.getcwd() .. "/authorize.lua")
  local lines = {
    "-- Editing policy for an offline example.", "local policy = {}", "",
    "function policy.can_edit(user, document)", "  if not user then", "    return false", "  end", "",
    "  if document.archived then", "    return false", "  end", "",
    '  return user.is_admin or user.role == "editor"', "end", "",
    "function policy.describe(user)", '  return user and user.role or "guest"', "end", "",
  }
  for row = 20, 70 do lines[row] = "-- Public example context " .. row end
  lines[70] = "return policy"
  api.nvim_buf_set_lines(0, 0, -1, false, lines)
  vim.bo.filetype = "lua"
  local function note(first, last, summary, detail, kind)
    return { kind = kind, summary = summary, detail = detail, intent_basis = "inferred",
      anchors = { { path = "authorize.lua", side = "buffer", start_line = first, end_line = last } } }
  end
  _G.capture_pane = require("irrelevant_explainer.ui").open(source, { windows = { buffer = source } }, { notes = {
    note(1, 70, "File overview: one editing policy.",
      "Centralizes editing authorization and describes the user's role.", "overview"),
    note(4, 14, "Deny missing users and archived documents.",
      "## Guard the editing decision\n\nMissing users and archived documents are denied before checking roles.\n\n"
        .. "```lua\nreturn user.is_admin or user.role == \"editor\"\n```\n\n"
        .. "Administrators and editors can edit an active document. These are offline fixture explanations."),
    note(16, 18, "Describe a role without changing access.",
      "Returns the user's role, or `guest` when there is no user. This helper does not authorize an edit."),
  } })
  local p = capture_pane
  api.nvim_set_current_win(p.win)
  api.nvim_win_set_width(p.win, 90)
  api.nvim_win_set_cursor(p.win, { vim.g.capture_state == "publication-code" and 1 or 4, 0 }); p:sync(p.win)
  if vim.g.capture_state:find("narrow") then api.nvim_win_set_width(p.win, 38); p:header() end
  if vim.g.capture_state:find("detail%-still") then p:detail(2) end
  return
end
if vim.g.capture_state:match("^diff%-review%-open") then
  local api = vim.api
  local fixture = dofile((vim.g.capture_checkout or vim.fn.getcwd()) .. "/tests/review.lua").open(true)
  require("diffview").close()
  vim.cmd.edit(vim.fn.fnameescape(fixture.root .. "/policy.lua"))
  local plugin = require("irrelevant_explainer")
  plugin.setup({ ai = { output = "plain", command = { "python3", (vim.g.capture_checkout or fixture.cwd) .. "/tests/fixtures/agent.py", "whole-review" } } })
  local held
  if vim.g.capture_state == "diff-review-open-annotations" then
    require("irrelevant_explainer.agent").run = function(input)
      held = vim.json.decode(assert(input:match("UNTRUSTED REVIEW REQUEST JSON:\n(.*)")))
      assert(held.phase == "annotate")
      return { cancel = function() end }
    end
  end
  local operation = plugin.explain("review")
  local session
  assert(vim.wait(10000, function()
    session = operation.view and require("irrelevant_explainer.session").sessions[operation.view.tabpage]
    return session and (held or session.pane.review and not session.pending)
  end, 20), "outside review did not finish")
  fixture.view = operation.view
  _G.capture_review, _G.capture_pane = fixture, session.pane
  assert(session.pane.review_mode)
  api.nvim_set_current_win(session.pane.win)
  if vim.g.capture_state == "diff-review-open-cached" then
    -- Reopen an equivalent comparison: completed cache reuse, not checkpoints.
    vim.wait(300)
    require("diffview").close()
    vim.cmd.edit(vim.fn.fnameescape(fixture.root .. "/policy.lua"))
    local agent, launches = require("irrelevant_explainer.agent"), 0
    agent.run = function() launches = launches + 1; error("cached review invoked inference") end
    operation = plugin.explain("review")
    assert(vim.wait(10000, function()
      session = operation.view and require("irrelevant_explainer.session").sessions[operation.view.tabpage]
      return session and session.pane.review and not session.pending
    end, 20), "outside cached review did not finish")
    fixture.view, _G.capture_pane = operation.view, session.pane
    assert(launches == 0 and session.pane.review_status == "Ready · cached", session.pane.review_status)
    api.nvim_set_current_win(session.pane.win)
  end
  vim.cmd("redraw!")
  return
end
if vim.g.capture_state:match("^loading%-file") then
  local api = vim.api
  local source = api.nvim_get_current_win()
  api.nvim_buf_set_lines(0, 0, -1, false, { "local policy = require('policy')", "",
    "local function authorize(request)", "  return policy.allow(request)", "end", "", "return authorize" })
  vim.bo.filetype = "lua"
  local p = require("irrelevant_explainer.ui").open(source, { windows = { new = source } }, nil)
  p.mode, p.auto_explain = "diff", true
  if vim.g.capture_state:find("detail") then
    p:set({ notes = { { summary = "Use the shared authorization policy", intent_basis = "inferred",
      detail = "The caller delegates to **policy.allow** rather than duplicating the decision.\n\n"
        .. "This accepted detail remains readable while the whole review is processed in the background.",
      anchors = { { path = "caller.lua", side = "new", start_line = 4, end_line = 4 } } } } }, "Ready")
    p:detail(1)
    p.background, p.background_busy = "Running review", true
    p:set_status("Ready")
  else
    p.restoring = true
    p:set_status("Checking saved explanations")
  end
  api.nvim_set_current_win(p.win)
  if vim.g.capture_state:find("narrow") then api.nvim_win_set_width(p.win, 32) end
  _G.capture_pane = p
  p:state(); vim.cmd("redraw!")
  return
end
if vim.g.capture_state:match("^review%-reader") then
  local api = vim.api
  local source = api.nvim_get_current_win()
  api.nvim_buf_set_lines(0, 0, -1, false, { "-- A comparison stays visible while reading.",
    "local policy = require('policy')", "", "return policy.allow(request)" })
  vim.bo.filetype = "lua"
  local p = require("irrelevant_explainer.ui").open(source, { windows = { new = source } }, { notes = {} })
  p.mode, p.auto_explain = "diff", true
  local narrative = { title = "Centralize authorization policy", sections = {
    { heading = "Policy and caller now share one decision", intent_basis = "inferred",
      detail = "The caller delegates authorization to **policy.allow** rather than duplicating the check.\n\n"
        .. "This keeps the behavior consistent across entry points. The supplied tests describe the expected denial path; they do not prove the tests ran.",
      file_ids = { "policy", "caller" } },
    { heading = "Scope and caveats", intent_basis = "unknown",
      detail = "The comparison includes a binary asset with no textual annotations. No source ranges are invented for it.",
      file_ids = { "asset" } },
  } }
  local manifest = { { file_id = "policy", path = "policy.lua", oldpath = "access.lua" },
    { file_id = "caller", path = "caller.lua" },
    { file_id = "asset", path = "badge.png", text_unavailable = "binary version" } }
  local state = vim.g.capture_state
  if state:find("focused") or state:find("clipped") then
    narrative.sections[1].detail = string.rep("The caller delegates to policy.allow instead of duplicating the authorization decision. ", 36)
      .. "\n\nThe retained explanation is unchanged while its context is checked."
  end
  local status = state:find("pending") and "Pending · comparison · 2 files"
    or state:find("stale") and "Stale · regenerate review"
    or state:find("failed") and "Failed · see :messages"
    or state:find("empty") and "No review · :IrrelevantExplainer review" or "Ready"
  if state:find("loading") then
    status = state:find("saved") and "Checking saved review" or "Pending · checking result context"
  end
  -- UI projection fixtures: no job is invented and no provider is launched.
  -- Keep an accepted narrative visible across each background job transition.
  if state:find("batch") then
    local count = (state:find("annotation") or not state:find("reduction") and not state:find("synthesis")) and "3/12" or "12/12"
    status = state:find("annotation") and "Pending · Annotating 25% · 7 files"
      or state:find("reduction") and "Pending · reducing"
      or "Pending · synthesizing"
    if state:find("failed") then
      local phase = state:find("annotation") and "annotate" or state:find("reduction") and "reduce" or "synthesize"
      status = "Failed · " .. phase .. " · " .. count .. " units · :IrrelevantExplainer review to resume; Refresh regenerates"
    elseif state:find("resume") and not state:find("reduction") and not state:find("synthesis") then
      status = "Pending · Annotating 25% · 7 files"
    elseif state:find("cancel") then status = "Cancelled · " .. count .. " units · :IrrelevantExplainer review to resume"
    elseif state:find("cached") then status = "Ready · cached" end
  end
  p:set_review(not state:find("empty") and not state:find("stale") and narrative or nil, manifest, status)
  p:show_review()
  if state:find("batch") then
    api.nvim_set_current_win(p.win)
    api.nvim_win_set_cursor(p.win, { 7, 0 })
    local view = api.nvim_win_call(p.win, vim.fn.winsaveview)
    p:set_review(narrative, manifest, "Pending · Annotating 25% · 7 files")
    p:set_review(narrative, manifest, status)
    assert(vim.deep_equal(view, api.nvim_win_call(p.win, vim.fn.winsaveview)), "status moved Review reading position")
    assert(api.nvim_get_current_win() == p.win)
    if state:find("file") then
      p:set({ notes = { { summary = "Delegate authorization to policy.",
        detail = "The caller delegates to `policy.allow`.\n\nThis accepted File detail stays readable while the review changes phase.",
        intent_basis = "inferred", anchors = { { path = "caller.lua", side = "new", start_line = 4, end_line = 4 } } } } },
        state:find("cached") and "Ready · cached" or "Ready")
      p:show_file(); p:detail(1)
      local detail = p.detail_buf
      p.background = status; p:header()
      assert(p.detail_buf == detail and api.nvim_get_current_win() == p.win)
    end
  end
  if state:find("wide") then api.nvim_win_set_width(p.win, 80) end
  if state:find("narrow") then api.nvim_win_set_width(p.win, 32) end
  if state:find("background") then p.background = "Generating caller.lua"; p:header() end
  if state:find("loading") then
    api.nvim_set_current_win(p.win)
    if state:find("focused") or state:find("clipped") then
      api.nvim_win_set_width(p.win, 48)
      api.nvim_win_set_cursor(p.win, { 6, 0 })
    end
    if state:find("clipped") then
      vim.wo[p.win].smoothscroll = true
      api.nvim_win_call(p.win, function()
        vim.fn.winrestview({ topline = 6, skipcol = 180, lnum = 6, col = 200 })
      end)
    end
    p:state()
  end
  _G.capture_pane = p
  vim.cmd("redraw!")
  return
end
if vim.g.capture_state:match("^source%-window%-") then
  local api = vim.api
  local source, buf = api.nvim_get_current_win(), api.nvim_get_current_buf()
  api.nvim_buf_set_lines(buf, 0, -1, false, {
    "-- Context stays bright in other views.", "local subtotal = 120", "local tax = 24", "",
    "local total = subtotal + tax", "print(total)", "", "-- More unrelated context.", "return total",
  })
  vim.bo.filetype = "lua"
  vim.cmd("syntax enable")
  vim.wo.signcolumn, vim.wo.winbar = "yes:1", " ORIGINAL · explained window "
  local p = require("irrelevant_explainer.ui").open(source, { source_buf = buf, windows = { buffer = source } }, { notes = {
    { summary = "Calculate the total", detail = "Add tax to the subtotal and print the result.", intent_basis = "inferred",
      anchors = { { path = "example.lua", side = "buffer", start_line = 5, end_line = 6 } } },
  } })
  p:detail(1)
  api.nvim_set_current_win(source)
  if vim.g.capture_state == "source-window-tab" then
    vim.cmd("tab split")
    vim.wo.winbar = " OTHER TAB · same buffer, no dimming or rails "
  else
    vim.cmd("leftabove vsplit")
    vim.wo.winbar = " OTHER SPLIT · same buffer "
    api.nvim_set_current_win(p.win)
    if vim.g.capture_state == "source-window-collapsed" then
      p:back(); vim.wait(100)
      vim.cmd("normal! 5G"); p:sync(p.win)
    end
  end
  vim.cmd("redraw!")
  return
end
if vim.g.capture_state == "gutter-cleanup" then
  local api = vim.api
  local source = api.nvim_get_current_win()
  api.nvim_buf_set_lines(0, 0, -1, false, { "local value = 1", "return value" })
  local p = require("irrelevant_explainer.ui").open(source, { windows = { buffer = source } }, { notes = {
    { summary = "Return the value", detail = "The source returns its local value.", intent_basis = "inferred",
      anchors = { { path = "example.lua", side = "buffer", start_line = 2, end_line = 2 } } },
  } })
  p:detail(1)
  api.nvim_win_close(source, true)
  assert(vim.wait(1000, function() return p.closed end))
  assert(not vim.wo.statuscolumn:find("irrelevant_explainer_detail_active", 1, true))
  api.nvim_buf_set_lines(0, 0, -1, false, { "-- Ordinary editor buffer after reader cleanup.",
    "local value = 2", "return value" })
  vim.bo.filetype = "lua"
  vim.cmd("redraw!"); assert(vim.v.errmsg == "", vim.v.errmsg)
  return
end
if vim.g.capture_state:match("^boundary%-") then
  local api = vim.api
  local source = api.nvim_get_current_win()
  local lines = {}; for row = 1, 180 do lines[row] = "local value_" .. row .. " = " .. row end
  api.nvim_buf_set_lines(0, 0, -1, false, lines)
  vim.bo.filetype = "lua"
  vim.wo.wrap, vim.wo.scrolloff = false, 0
  _G.capture_pane = require("irrelevant_explainer.ui").open(source, { windows = { buffer = source } }, { notes = {
    { summary = "Boundary explanation", detail = "First paragraph.\n\nSecond paragraph.", intent_basis = "inferred",
      anchors = { { path = "example.lua", side = "buffer", start_line = 40, end_line = 100 } } },
  } })
  local p = capture_pane
  api.nvim_set_current_win(p.win); vim.cmd("normal! 40Gzz"); p:sync(p.win); p:detail(1)
  local top = vim.g.capture_state == "boundary-top" and 70
    or 40 - (vim.fn.getwininfo(p.win)[1].height - p.detail_layout.card_height)
  api.nvim_set_current_win(source)
  vim.fn.winrestview({ topline = top, lnum = top + 10, col = 0 }); p:scroll(nil, source)
  api.nvim_set_current_win(p.win)
  api.nvim_win_set_cursor(p.win, { p.detail_layout.first, 0 })
  p:sync(p.win)
  vim.cmd("redraw!")
  return
end
if vim.g.capture_state == "diff-sticky-wrapped-filler" or vim.g.capture_state == "diff-sticky-eof-overflow" then
  local api = vim.api
  local eof = vim.g.capture_state == "diff-sticky-eof-overflow"
  local lines = {}; for row = 1, eof and 15 or 80 do lines[row] = "-- comparison context " .. row end
  lines[eof and 10 or 24] = string.rep("validate_payload(payload); ", eof and 4 or 40)
  local old = api.nvim_get_current_win()
  api.nvim_buf_set_lines(0, 0, -1, false, lines)
  vim.cmd("belowright vsplit")
  local new = api.nvim_get_current_win(); api.nvim_win_set_buf(new, api.nvim_create_buf(false, true))
  local after = eof and vim.list_slice(lines, 1, 10) or vim.deepcopy(lines)
  if not eof then for _ = 1, 3 do table.remove(after, 21) end end
  api.nvim_buf_set_lines(0, 0, -1, false, after)
  for _, win in ipairs({ old, new }) do
    api.nvim_win_call(win, function() vim.cmd("diffthis | normal! zR") end)
    vim.wo[win].wrap, vim.wo[win].scrolloff, vim.wo[win].number = true, 0, true
    vim.wo[win].smoothscroll = true
    vim.wo[win].winbar = win == old and " OLD · payload.lua " or " NEW · payload.lua "
  end
  vim.cmd("diffupdate")
  local function note(summary, detail)
    return { summary = summary, detail = detail, intent_basis = "inferred",
      anchors = { { path = "payload.lua", side = "new", start_line = eof and 10 or 21, end_line = eof and 10 or 21 } } }
  end
  local notes = eof and {
    note("Validate the final payload", "Preserve the final validation call."),
    note("Preserve its original anchor", "This overflow explanation follows every trailing deletion row."),
  } or { note("Validate the wrapped payload", "Pin this explanation below the header when its first wrapped segment scrolls away.") }
  _G.capture_pane = require("irrelevant_explainer.ui").open(new, { windows = { old = old, new = new } }, { notes = notes })
  local p = capture_pane
  p:detail(eof and 2 or 1)
  if eof then p:place_detail()
  else
    api.nvim_set_current_win(new); vim.cmd("normal! 21G0zt")
    vim.cmd.normal({ api.nvim_replace_termcodes("<C-e>", true, false, true), bang = true })
    p:scroll(nil, new)
  end
  vim.wait(50, function() return false end); vim.cmd("redraw!")
  if eof then
    local height = api.nvim_win_text_height(new, { start_row = 9, end_row = 9, start_vcol = 0 }).all
    assert(p.detail_layout.natural == 10 + height + 5)
  else assert(p.detail_layout.natural == 0 and p.detail_layout.first == 1) end
  return
end
if vim.g.capture_state:match("^sticky%-") then
  local api, state = vim.api, vim.g.capture_state
  local source = api.nvim_get_current_win()
  local lines = {}; for row = 1, 200 do lines[row] = "-- request preparation context " .. row end
  lines[40], lines[100] = "local function prepare(payload)", "end -- request validated"
  api.nvim_buf_set_lines(0, 0, -1, false, lines)
  vim.bo.filetype = "lua"
  vim.wo.number, vim.wo.cursorline, vim.wo.wrap, vim.wo.scrolloff = true, true, false, 5
  vim.wo.winbar = " SOURCE · preparation.lua "
  api.nvim_set_hl(0, "CursorLine", { bg = "#34485c" })
  local function note(first, last, summary, detail)
    return { summary = summary, detail = detail, intent_basis = "inferred",
      anchors = { { path = "preparation.lua", side = "buffer", start_line = first, end_line = last } } }
  end
  local prose = "Validate required fields before preparing the request.\n\n"
    .. "Reject incomplete payloads; preserve existing validation."
  if state == "sticky-long" then
    prose = string.rep("A wrapped reading paragraph retains its logical position as code moves. ", 8)
      .. "\n\n" .. string.rep("Later paragraphs remain reachable through native scrolling.\n\n", 35)
  elseif state == "sticky-resized" then
    prose = string.rep("Validate the payload before preparing the request. ", 9)
      .. "\n\n" .. string.rep("Existing validation remains in place. ", 6)
  elseif state:match("^sticky%-markdown") then
    prose = string.rep("Read each wrapped row before preparing `payload`. Preserve validation and source alignment. ", 40)
      .. "\n\n## Result\n\nKeep Markdown visible."
  end
  local selected = note(40, 100, "Validate the request", prose)
  if state == "sticky-markdown-summary" then
    selected.summary = "Validate the request and preserve the source position while reading every wrapped summary segment."
  end
  if state == "sticky-disjoint" then
    selected.anchors[1].end_line = 50
    selected.anchors[2] = { path = "preparation.lua", side = "buffer", start_line = 80, end_line = 100 }
  end
  _G.capture_pane = require("irrelevant_explainer.ui").open(source, { windows = { buffer = source } }, { notes = {
    note(24, 24, "Earlier request context", "Previous explanation."),
    selected,
    note(65, 65, "Preserve validation", "Following explanation."),
  } })
  local p = capture_pane
  if state:match("^sticky%-markdown") then api.nvim_win_set_width(p.win, 42) end
  if state == "sticky-offscreen" then
    api.nvim_set_current_win(source); vim.cmd("normal! 60Gzt"); p:sync(source); p:detail(2)
    assert(p.detail_layout.rows[api.nvim_buf_line_count(p.detail_buf)].item.line == 200)
  else
    api.nvim_set_current_win(p.win); vim.cmd("normal! 40Gzz"); p:sync(p.win); p:detail()
  end
  local detail = p.detail_buf
  if state == "sticky-long" then
    vim.cmd.normal({ (p.detail_layout.first + 3) .. "G02gjzt", bang = true }); p:sync(p.win)
  end
  api.nvim_set_current_win(source)
  vim.cmd.normal({ (state == "sticky-bottom" and "1Gzt" or state == "sticky-aligned" and "28Gzt" or "60Gzt"), bang = true })
  p:sync(source)
  if state == "sticky-resized" then
    api.nvim_win_set_width(p.win, 24); api.nvim_exec_autocmds("WinResized", {})
  end
  if state:match("^sticky%-markdown") then
    vim.wo[p.win].smoothscroll = true
    for _, win in ipairs({ source, p.win }) do
      vim.wo[win].cursorline = true; vim.wo[win].cursorlineopt = "screenline"
    end
    api.nvim_set_current_win(p.win)
    local function input(keys)
      api.nvim_feedkeys(api.nvim_replace_termcodes(keys, true, false, true), "xt", false)
      vim.cmd("redraw!"); api.nvim_exec_autocmds("SafeState", {}); vim.wait(20, function() return false end)
    end
    if state == "sticky-markdown-summary" then
      input(p.detail_layout.first .. "G02gj2<C-e>")
      assert(vim.fn.winline() == 1 and vim.fn.winsaveview().skipcol > 0)
      local column = api.nvim_win_get_cursor(p.win)[2]
      input("k")
      assert(api.nvim_win_get_cursor(p.win)[1] == p.detail_layout.first and api.nvim_win_get_cursor(p.win)[2] < column)
    else
      input((p.detail_layout.first + 3) .. "G0")
      local row, column = api.nvim_win_get_cursor(p.win)[1], api.nvim_win_get_cursor(p.win)[2]
      local top = api.nvim_win_call(source, vim.fn.winsaveview).topline
      input("30j")
      assert(api.nvim_win_get_cursor(p.win)[1] == row and api.nvim_win_get_cursor(p.win)[2] > column)
      assert(api.nvim_win_call(source, vim.fn.winsaveview).topline > top)
    end
    local source_view = api.nvim_win_call(source, vim.fn.winsaveview)
    assert(source_view.lnum == math.min(100, source_view.topline + vim.fn.winline() - 1))
    assert(api.nvim_get_current_win() == p.win and p.detail_buf == detail)
  end
  if state == "sticky-scroll-top" or state == "sticky-scroll-bottom" then
    local bottom = state == "sticky-scroll-bottom"
    local height = vim.fn.getwininfo(source)[1].height
    api.nvim_set_current_win(source)
    vim.cmd.normal({ (bottom and (40 - height + 7) or 70) .. "Gzt", bang = true }); p:sync(source)
    api.nvim_set_current_win(p.win)
    vim.cmd.normal({ (bottom and p.detail_layout.last or p.detail_layout.first + 3) .. "G0", bang = true })
    p:sync(p.win)
    vim.wo[p.win].cursorline = true
    local top = api.nvim_win_call(source, vim.fn.winsaveview).topline
    api.nvim_feedkeys(api.nvim_replace_termcodes("<C-y>", true, false, true), "xt", false)
    vim.wait(50, function() return false end); vim.cmd("redraw!")
    api.nvim_exec_autocmds("SafeState", {})
    local view = api.nvim_win_call(source, vim.fn.winsaveview)
    local reader = api.nvim_win_call(p.win, vim.fn.winsaveview)
    assert(view.topline == top - 1)
    assert(view.lnum == (bottom and 40 or 67), "sticky scroll must finish on the final source row")
    assert(view.lnum == view.topline + reader.lnum - reader.topline)
  end
  vim.wait(50, function() return false end); vim.cmd("redraw!")
  assert(p.detail_buf == detail and p.detail_index == 2 and vim.wo[source].scrolloff == 5)
  api.nvim_set_current_win(p.win)
  return
end
if vim.g.capture_state:match("^detail%-eof") then
  local api = vim.api
  local source = api.nvim_get_current_win()
  local lines = {}; for row = 1, 180 do lines[row] = "-- request preparation context " .. row end
  lines[40], lines[110], lines[180] = "local function prepare(payload)", "end -- validation finishes here",
    "return prepare -- end of source"
  api.nvim_buf_set_lines(0, 0, -1, false, lines)
  vim.bo.filetype = "lua"
  vim.wo.number, vim.wo.cursorline, vim.wo.wrap = true, true, false
  vim.wo.winbar = " SOURCE · preparation.lua "
  api.nvim_set_hl(0, "CursorLine", { bg = "#34485c" })
  _G.capture_pane = require("irrelevant_explainer.ui").open(source, { windows = { buffer = source } }, { notes = { {
    summary = "Validate the request before preparation.",
    detail = "Reject missing or extra fields before preparing the request.\n\n"
      .. "The validation continues through line 110, beyond the initial viewport.\n\n"
      .. "Unreferenced source lines remain reachable after the explanation ends.",
    intent_basis = "inferred", anchors = { { path = "preparation.lua", side = "buffer", start_line = 40, end_line = 110 } },
  } } })
  local p = capture_pane
  api.nvim_set_current_win(p.win)
  vim.cmd("normal! 40Gzz"); p:sync(p.win); p:detail()
  local last = api.nvim_buf_line_count(p.detail_buf)
  assert(p.detail_layout.rows[last].item.line == 180, "expanded context must reach the source EOF")
  if vim.g.capture_state == "detail-eof-range" then
    local boundary
    for row = 1, last do
      local context = p.detail_layout.rows[row]
      if context and context.item.line == 110 then boundary = row end
    end
    assert(boundary)
    vim.cmd.normal({ boundary .. "G0", bang = true }); p:sync(p.win)
    assert(p.detail_index == 1 and api.nvim_win_get_cursor(source)[1] == 110)
  elseif vim.g.capture_state == "detail-eof-end" then
    vim.cmd("normal! G0"); p:sync(p.win)
    assert(not p.detail_buf and api.nvim_win_get_cursor(source)[1] == 180)
    assert(api.nvim_win_get_cursor(p.win)[1] == 180)
  end
  return
end
if vim.g.capture_state:match("^range%-") then
  local api = vim.api
  local source = api.nvim_get_current_win()
  local lines = {}; for row = 1, 40 do lines[row] = "-- request preparation context " .. row end
  lines[10], lines[18], lines[24] = "local function prepare(payload)", "  validate(payload)", "end"
  api.nvim_buf_set_lines(0, 0, -1, false, lines)
  vim.bo.filetype = "lua"
  vim.wo.number, vim.wo.cursorline, vim.wo.wrap = true, true, false
  vim.wo.winbar = " SOURCE · preparation.lua "
  api.nvim_set_hl(0, "CursorLine", { bg = "#34485c" })
  local function note(first, last, summary, detail, kind)
    return { kind = kind, summary = summary, detail = detail, intent_basis = "inferred",
      anchors = { { path = "preparation.lua", side = "new", start_line = first, end_line = last } } }
  end
  _G.capture_pane = require("irrelevant_explainer.ui").open(source, { windows = { new = source } }, { notes = {
    note(1, 40, "Prepare and validate incoming requests.", "The file provides safe request preparation.", "overview"),
    note(10, 24, "Prepare the request without blocking.",
      "The preparation function validates the payload before forwarding it.\n\nExisting validation remains in place."),
    note(18, 22, "Validate required payload fields.", "Reject incomplete payloads before preparing the request."),
  } })
  api.nvim_set_current_win(capture_pane.win)
  local chooser = vim.g.capture_state == "range-chooser"
  api.nvim_win_set_cursor(capture_pane.win, { chooser and 20 or 14, 0 })
  capture_pane:sync(capture_pane.win)
  if chooser then
    api.nvim_win_call(source, function() vim.cmd("normal! 20Gzz") end)
    capture_pane:sync(source)
    vim.cmd("redraw!")
  end
  api.nvim_feedkeys(api.nvim_replace_termcodes("<CR>", true, false, true), "xt", false)
  if chooser then
    assert(not capture_pane.detail_buf and api.nvim_win_get_cursor(source)[1] == 20)
    return
  end
  assert(capture_pane.detail_index == 2 and api.nvim_win_get_cursor(source)[1] == 14,
    "range opening must select the local note without moving the source")
  if vim.g.capture_state ~= "range-open" then
    vim.cmd.normal({ "22G0", bang = true })
    api.nvim_exec_autocmds("CursorMoved", { buffer = capture_pane.detail_buf })
    assert(api.nvim_win_get_cursor(source)[1] == 22, "continuation must select source line 22")
    if vim.g.capture_state == "range-after-collapse" then
      api.nvim_feedkeys(api.nvim_replace_termcodes("<CR>", true, false, true), "xt", false)
      assert(not capture_pane.detail_buf and api.nvim_win_get_cursor(capture_pane.win)[1] == 22)
      assert(api.nvim_win_get_cursor(source)[1] == 22, "collapse must not jump to summary line 10")
    end
  end
  assert(api.nvim_get_current_win() == capture_pane.win)
  return
end
if vim.g.capture_state == "diff-scroll-deletion" then
  local api = vim.api
  local old = api.nvim_get_current_win()
  local lines = {}; for row = 1, 120 do lines[row] = "-- comparison context " .. row end
  api.nvim_buf_set_lines(0, 0, -1, false, lines)
  vim.cmd("belowright vsplit")
  local new = api.nvim_get_current_win(); api.nvim_win_set_buf(new, api.nvim_create_buf(false, true))
  local after = vim.deepcopy(lines); for _ = 1, 5 do table.remove(after, 40) end
  api.nvim_buf_set_lines(0, 0, -1, false, after)
  api.nvim_set_hl(0, "CursorLine", { bg = "#34485c" })
  for side, win in pairs({ old = old, new = new }) do
    vim.bo[api.nvim_win_get_buf(win)].filetype = "lua"
    vim.wo[win].winbar = " " .. side:upper() .. " · comparison.lua "
    vim.wo[win].number, vim.wo[win].cursorline, vim.wo[win].wrap = true, true, false
    vim.wo[win].scrolloff = side == "old" and 5 or 9
    api.nvim_win_call(win, function() vim.cmd("diffthis | normal! zR") end)
  end
  vim.cmd("diffupdate")
  _G.capture_pane = require("irrelevant_explainer.ui").open(new, { windows = { old = old, new = new } }, { notes = { {
    summary = "Review the removed comparison context",
    detail = "The old side retains the deleted code.\n\nThe new side shows native diff filler.",
    intent_basis = "inferred", anchors = { { path = "comparison.lua", side = "old", start_line = 30, end_line = 80 } },
  } } })
  local p = capture_pane
  p:detail(1)
  api.nvim_set_current_win(old); vim.cmd("normal! 45Gzt"); p:sync(old)
  api.nvim_set_current_win(p.win); vim.cmd("normal! 4G0"); p:sync(p.win)
  vim.wo[p.win].cursorline = true
  api.nvim_feedkeys(api.nvim_replace_termcodes("<C-y>", true, false, true), "xt", false)
  vim.wait(50, function() return false end); vim.cmd("redraw!"); api.nvim_exec_autocmds("SafeState", {})
  assert(api.nvim_win_call(old, vim.fn.winsaveview).topline == 39)
  -- The relocated diff summary releases to row 2; retained fourth-card-row
  -- prose moves to screen row 5, beside deleted old line 43 (not pre-scroll 42).
  assert(p.detail_layout.first == 2 and api.nvim_win_get_cursor(p.win)[1] == 5)
  assert(api.nvim_win_get_cursor(old)[1] == 43 and api.nvim_win_get_cursor(new)[1] == 40)
  assert(p.detail_index == 1 and api.nvim_get_current_win() == p.win and not vim.wo[p.win].diff)
  assert(vim.wo[old].scrolloff == 5 and vim.wo[new].scrolloff == 9)
  return
end
if vim.g.capture_state:match("^diff%-prose") then
  local api = vim.api
  local old = api.nvim_get_current_win()
  local lines = {}; for row = 1, 90 do lines[row] = "# Route context " .. row end
  local route = { "@http.route(", '    "/example/inbound/prepare",', '    type="json",', '    auth="bearer",',
    '    methods=["POST"],', "    save_session=False,", ")", "def prepare(self, **payload):",
    '    return self._call("prepare", payload)', "", "@http.route(", '    "/example/inbound/status",',
    '    type="json",', '    auth="bearer",', '    methods=["POST"],', "    readonly=True,", ")",
    "def status(self, **payload):", '    return self._call("status", payload)' }
  for row, text in ipairs(route) do lines[36 + row] = text end
  local before = vim.deepcopy(lines); before[37] = '@http.route("/legacy/prepare")'
  api.nvim_buf_set_lines(0, 0, -1, false, before)
  vim.cmd("belowright vsplit")
  local new = api.nvim_get_current_win()
  api.nvim_win_set_buf(new, api.nvim_create_buf(false, true))
  api.nvim_buf_set_lines(0, 0, -1, false, lines)
  api.nvim_set_hl(0, "CursorLine", { bg = "#34485c" })
  for side, win in pairs({ old = old, new = new }) do
    vim.bo[api.nvim_win_get_buf(win)].filetype = "python"
    vim.wo[win].winbar = " " .. side:upper() .. " · routes.py "
    vim.wo[win].number, vim.wo[win].cursorline, vim.wo[win].wrap = true, true, false
    api.nvim_win_call(win, function() vim.cmd("diffthis | normal! zR") end)
  end
  vim.cmd("diffupdate")
  local wrapped = vim.g.capture_state:find("wrapped", 1, true) ~= nil
  local boundary = vim.g.capture_state == "diff-prose-boundary"
  _G.capture_pane = require("irrelevant_explainer.ui").open(new, { windows = { old = old, new = new } }, { notes = { {
    summary = "Both routes require bearer auth.",
    detail = wrapped and string.rep("Both routes use bearer auth and forward their payload to a shared service. ", 5)
      or "Both routes use bearer authentication.\n\nEach handler forwards its payload to the shared service.",
    intent_basis = "inferred", anchors = { { path = "routes.py", side = "new", start_line = 37,
      end_line = boundary and 40 or 58 } },
  } } })
  api.nvim_set_current_win(capture_pane.win)
  vim.cmd.normal({ "37Gzz", bang = true }); capture_pane:sync(capture_pane.win)
  capture_pane:detail()
  vim.cmd.normal({ wrapped and (capture_pane.detail_layout.first + 3) .. "G02gj" or "5j", bang = true })
  api.nvim_exec_autocmds("CursorMoved", { buffer = capture_pane.detail_buf })
  assert(api.nvim_win_get_cursor(new)[1] == (boundary and 40 or 42), "prose must select the expected source row")
  assert(api.nvim_get_current_win() == capture_pane.win and capture_pane.detail_index == 1)
  if vim.g.capture_state == "diff-prose-wrapped-collapse" then
    api.nvim_feedkeys(api.nvim_replace_termcodes("<CR>", true, false, true), "xt", false)
    assert(not capture_pane.detail_buf and api.nvim_win_get_cursor(capture_pane.win)[1] == 42)
    assert(api.nvim_win_get_cursor(new)[1] == 42, "wrapped prose collapse must keep source line 42")
    assert(api.nvim_get_current_win() == capture_pane.win)
  end
  return
end
if vim.g.capture_state:match("^detail%-highlight") then
  if vim.g.capture_state:match("^detail%-highlight%-rose%-pine") then
    require("rose-pine").setup({ dim_inactive_windows = true })
    vim.cmd("colorscheme rose-pine")
  end
  local api = vim.api
  local source = api.nvim_get_current_win()
  local lines = { "<?php", "", "namespace App\\Modules\\Example;", "", "use RuntimeException;", "",
    "class ExampleValidationException extends RuntimeException", "{", "    public function message()", "    {",
    "        return 'Invalid creation request';", "    }", "}" }
  api.nvim_buf_set_lines(0, 0, -1, false, lines)
  vim.bo.filetype = "php"; vim.wo.winbar = " OLD · ExampleValidationException.php "
  vim.wo.number = true
  _G.capture_pane = require("irrelevant_explainer.ui").open(source, { windows = { old = source } }, { notes = { {
    summary = "Removes the example request validation exception specialization.",
    detail = "This file defined `ExampleValidationException`, a creation-specific subclass of `RuntimeException`. "
      .. "The diff deletes the entire file. Inferred intent: remove this specialization; the supplied snapshot does not establish why it was removed or what replaces it.\n\n"
      .. "```php\nclass ExampleValidationException extends RuntimeException\n{\n}\n```",
    intent_basis = "inferred", anchors = { { side = "old", start_line = 1, end_line = 13,
      path = "app/Modules/Example/Exceptions/Example/ExampleValidationException.php" } },
  } } })
  api.nvim_set_current_win(capture_pane.win); capture_pane:detail(1)
  return
end
if vim.g.capture_state:match("^diff%-overlap%-single") then
  local api = vim.api
  local old = api.nvim_get_current_win()
  api.nvim_buf_set_lines(0, 0, -1, false, { "# Empty package" })
  vim.cmd("belowright vsplit")
  local new = api.nvim_get_current_win()
  api.nvim_win_set_buf(new, api.nvim_create_buf(false, true))
  api.nvim_buf_set_lines(0, 0, -1, false, { "from . import helpers" })
  for side, win in pairs({ old = old, new = new }) do
    vim.bo[api.nvim_win_get_buf(win)].filetype = "python"
    vim.wo[win].winbar = " " .. side:upper() .. " · __init__.py "
    api.nvim_win_call(win, function() vim.cmd("diffthis | normal! zR") end)
  end
  vim.cmd("diffupdate")
  _G.capture_pane = require("irrelevant_explainer.ui").open(new, { windows = { old = old, new = new } }, { notes = {
    { kind = "overview", summary = "Initialize the package by loading its helper module.",
      detail = "This package initializer imports the sibling `helpers` module when the package is loaded.",
      intent_basis = "inferred", anchors = { { path = "__init__.py", side = "new", start_line = 1, end_line = 1 } } },
    { summary = "Replace the empty initializer with a relative import.",
      detail = "The new statement loads `.helpers`. This makes the module available during package initialization.\n\n```python\nfrom . import helpers\n```",
      intent_basis = "unknown", anchors = { { path = "__init__.py", side = "new", start_line = 1, end_line = 1 } } },
  } })
  api.nvim_set_current_win(capture_pane.win)
  if vim.g.capture_state == "diff-overlap-single-detail" then
    capture_pane:detail(1); capture_pane:detail(2)
  elseif vim.g.capture_state == "diff-overlap-single-focused" then
    capture_pane:jump(1)
  end
  return
end
if vim.g.capture_state == "diff-overview-range" then
  local api = vim.api
  local old = api.nvim_get_current_win()
  api.nvim_buf_set_lines(0, 0, -1, false, { "" })
  vim.cmd("belowright vsplit")
  local new = api.nvim_get_current_win()
  api.nvim_win_set_buf(new, api.nvim_create_buf(false, true))
  local lines = {}; for row = 1, 299 do lines[row] = "-- request preparation context " .. row end
  lines[1], lines[6], lines[13] = "local requests = {}", "local function prepare(payload)", "local function authorize(user)"
  api.nvim_buf_set_lines(0, 0, -1, false, lines); vim.bo.filetype = "lua"
  for side, win in pairs({ old = old, new = new }) do
    vim.wo[win].winbar = " " .. side:upper() .. " · preparation.lua "
    vim.wo[win].number = true
    api.nvim_win_call(win, function() vim.cmd("diffthis | normal! zR") end)
  end
  vim.cmd("diffupdate")
  _G.capture_pane = require("irrelevant_explainer.ui").open(new, { windows = { old = old, new = new } }, { notes = {
    { kind = "overview", summary = "Adds safe request preparation and status lookup.",
      detail = "This added file validates requests, prepares pending work, and reports existing results.\n\n"
        .. "Inferred purpose: provide a narrowly scoped preparation operation with retry protection.",
      intent_basis = "inferred", anchors = { { path = "preparation.lua", side = "new", start_line = 1, end_line = 299 } } },
    { summary = "Authorize the requested operation.", detail = "Only authorized users can prepare the request.",
      intent_basis = "documented", anchors = { { path = "preparation.lua", side = "new", start_line = 13, end_line = 16 } } },
    { summary = "Return the stored request status.", detail = "Existing results are returned without processing the request again.",
      intent_basis = "inferred", anchors = { { path = "preparation.lua", side = "new", start_line = 24, end_line = 28 } } },
  } })
  api.nvim_set_current_win(capture_pane.win); capture_pane:detail(1)
  return
end
if vim.g.capture_state:match("^diff%-neighbors") then
  local api = vim.api
  local old = api.nvim_get_current_win()
  local lines = {}; for row = 1, 40 do lines[row] = "-- surrounding context " .. row end
  lines[2] = "local cached = load_cache(key)"
  lines[6] = "local result = prepare_request(payload)"
  lines[16] = "return save_result(result)"
  lines[23] = "local function cleanup() end"
  api.nvim_buf_set_lines(0, 0, -1, false, lines); vim.bo.filetype = "lua"
  vim.cmd("belowright vsplit")
  local new, buf = api.nvim_get_current_win(), api.nvim_create_buf(false, true)
  api.nvim_win_set_buf(new, buf)
  local after = vim.deepcopy(lines)
  after[6] = "local result = prepare_request(payload, { nonblocking = true })"
  after[16] = "return save_result(result, key)"
  api.nvim_buf_set_lines(buf, 0, -1, false, after); vim.bo.filetype = "lua"
  for side, win in pairs({ old = old, new = new }) do
    vim.wo[win].winbar = " " .. side:upper() .. " · requests.lua "
    vim.wo[win].number = true
    api.nvim_win_call(win, function() vim.cmd("diffthis | normal! zR") end)
  end
  vim.cmd("diffupdate")
  local function note(first, last, text)
    return { summary = text, detail = "Requests use `nonblocking` preparation to avoid waiting for a busy resource.\n\nThe existing validation still runs before the result is saved.",
      intent_basis = "documented", anchors = { { path = "requests.lua", side = "new", start_line = first, end_line = last } } }
  end
  _G.capture_pane = require("irrelevant_explainer.ui").open(new, { windows = { old = old, new = new } },
    { notes = { note(2, 3, "Reuse the cached request."), note(6, 13, "Prepare without blocking."),
      note(16, 19, "Save the keyed result."), note(23, 23, "Keep cleanup separate.") } })
  api.nvim_set_current_win(capture_pane.win)
  api.nvim_win_set_cursor(capture_pane.win, { 6, 0 }); capture_pane:sync(capture_pane.win)
  if vim.g.capture_state ~= "diff-neighbors-overview" then
    if vim.g.capture_state == "diff-neighbors-long" then
      capture_pane.result.notes[2].detail = string.rep("More detail on `nonblocking` request preparation and validation.\n", 9)
    elseif vim.g.capture_state == "diff-neighbors-cursor" or vim.g.capture_state == "diff-neighbors-cursor-collapse" then
      capture_pane.result.notes[2].anchors[1].end_line = 19
      capture_pane.result.notes[2].detail = "Preparation is nonblocking."
      capture_pane:render()
    end
    capture_pane:detail()
    if vim.g.capture_state == "diff-neighbors-cursor" or vim.g.capture_state == "diff-neighbors-cursor-collapse" then
      local row = vim.g.capture_state == "diff-neighbors-cursor" and 14 or 20
      vim.cmd.normal({ row .. "G0", bang = true })
      capture_pane:sync(capture_pane.win)
      assert(api.nvim_win_get_cursor(new)[1] == row)
      assert((capture_pane.detail_buf ~= nil) == (row == 14))
    end
  end
  return
end
if vim.g.capture_state:match("^diff%-multihunk") then
  local api = vim.api
  vim.o.diffopt = "internal,filler,closeoff,context:3"
  local fixture = dofile((vim.g.capture_checkout or vim.fn.getcwd()) .. "/tests/multihunk.lua").open()
  for side, win in pairs({ old = fixture.old, new = fixture.new }) do
    vim.wo[win].number, vim.wo[win].relativenumber = true, false
    vim.wo[win].winbar = " " .. side:upper() .. " · config.lua "
  end
  if vim.g.capture_state == "diff-multihunk-detail-range" then
    fixture.result.notes[3].anchors[1].end_line = 67
    fixture.result.notes[3].anchors[2].end_line = 71
    fixture.result.notes[3].detail = "The `in_progress` setting now uses `play` instead of `tools`. Nearby configuration is otherwise unchanged."
  end
  _G.capture_pane = require("irrelevant_explainer.ui").open(fixture.new,
    { windows = { old = fixture.old, new = fixture.new } }, fixture.result)
  local source = vim.g.capture_state == "diff-multihunk-old" and fixture.old or fixture.new
  api.nvim_win_call(source, function() vim.cmd("normal! 34Gzt") end)
  if vim.g.capture_state == "diff-multihunk-open" then
    api.nvim_win_call(source, function() vim.cmd("normal! zR"); vim.cmd("normal! 34Gzt") end)
  elseif vim.g.capture_state == "diff-multihunk-detail-range" then
    api.nvim_win_call(source, function() vim.cmd("normal! zR"); vim.cmd("normal! 49Gzt") end)
  end
  capture_pane:sync(source)
  api.nvim_set_current_win(capture_pane.win)
  if vim.g.capture_state == "diff-multihunk-fold-live-old" or vim.g.capture_state == "diff-multihunk-fold-live-new" then
    -- Real fold input: rely on editor events, not a direct pane sync afterward.
    api.nvim_set_current_win(vim.g.capture_state == "diff-multihunk-fold-live-old" and fixture.old or fixture.new)
    api.nvim_feedkeys("zR34Gzt", "xt", false)
    return
  end
  if vim.g.capture_state == "diff-multihunk-queued" or vim.g.capture_state == "diff-multihunk-queue-next" then
    local function request(index)
      return { source = fixture.new, scope = "hunk", windows = { old = fixture.old, new = fixture.new },
        snapshot = { target = { anchors = fixture.result.notes[index].anchors } } }
    end
    capture_pane.pending = request(3)
    capture_pane.queued = { request(4), request(5) }
    local accepted = { notes = { fixture.result.notes[2] } }
    if vim.g.capture_state == "diff-multihunk-queue-next" then
      accepted.notes[2] = fixture.result.notes[3]
      capture_pane.pending = table.remove(capture_pane.queued, 1)
    end
    capture_pane:set(accepted, "Pending · external agent")
  end
  if vim.g.capture_state:match("^diff%-multihunk%-detail") then
    capture_pane:detail(3)
    if vim.g.capture_state == "diff-multihunk-detail-next" or vim.g.capture_state == "diff-multihunk-detail-collapse" then
      api.nvim_feedkeys("n", "xt", false)
      if vim.g.capture_state == "diff-multihunk-detail-collapse" then
        api.nvim_feedkeys(api.nvim_replace_termcodes("<CR>", true, false, true), "xt", false)
      end
    elseif vim.g.capture_state == "diff-multihunk-detail-scroll" then
      api.nvim_feedkeys(api.nvim_replace_termcodes("3<C-e>", true, false, true), "xt", false)
    end
  end
  return
end
if vim.g.capture_state:match("^diff%-motion") then
  local api = vim.api
  local old = api.nvim_get_current_win()
  local before = { "local user = load_user()", "-- Determine access", "return user.is_admin" }
  local after = { "local user = load_user()", "-- Determine access", "if user.role == 'editor' then",
    "  return true", "end", "return user.is_admin" }
  for i = 1, 80 do before[#before + 1] = "-- context " .. i; after[#after + 1] = "-- context " .. i end
  api.nvim_buf_set_lines(0, 0, -1, false, before)
  vim.bo.filetype = "lua"; vim.wo.winbar = ""
  vim.cmd("belowright vsplit")
  local new, buf = api.nvim_get_current_win(), api.nvim_create_buf(false, true)
  api.nvim_win_set_buf(new, buf); api.nvim_buf_set_lines(buf, 0, -1, false, after)
  vim.bo.filetype = "lua"; vim.wo.winbar = ""
  for _, candidate in ipairs({ old, new }) do
    api.nvim_win_call(candidate, function() vim.cmd("diffthis | normal! zR") end)
    vim.wo[candidate].wrap = false; vim.wo[candidate].cursorline = true
  end
  vim.cmd("diffupdate")
  if vim.g.capture_state == "diff-motion-detail" then
    local signs = api.nvim_create_namespace("capture.git-signs")
    for row = 2, 4 do
      api.nvim_buf_set_extmark(buf, signs, row, 0, { sign_text = "+", sign_hl_group = "DiffAdd", priority = 6 })
    end
  end
  _G.capture_pane = require("irrelevant_explainer.ui").open(old, { windows = { old = old, new = new },
    context = { strategy = "focused", radius = 20, omitted_files = 39 } }, { notes = { {
      summary = "Editors bypass the admin check.", detail = "The added branch returns before the original admin check.",
      intent_basis = "inferred", evidence = {}, anchors = { { path = "access.lua", side = "new", start_line = 3, end_line = 5 } },
    } } })
  if vim.g.capture_state:find("overlap", 1, true) then
    capture_pane.result.notes[1].anchors[1].end_line = 4
    capture_pane.result.notes[2] = {
      summary = "The fallback still checks admin access.", detail = "After the early editor branch, the existing admin check remains.",
      intent_basis = "unknown", evidence = {}, anchors = { { path = "access.lua", side = "new", start_line = 3, end_line = 5 } },
    }
    capture_pane:render()
  end
  vim.wo[capture_pane.win].cursorline = true
  api.nvim_set_current_win(capture_pane.win)
  api.nvim_win_set_cursor(capture_pane.win, { 2, 0 }); capture_pane:sync(capture_pane.win)
  if vim.g.capture_state == "diff-motion-topfill" then
    api.nvim_win_call(old, function()
      vim.fn.winrestview({ topline = 3, topfill = 2, lnum = 3, col = 0 })
      vim.cmd("syncbind")
    end)
    capture_pane:align()
  elseif vim.g.capture_state ~= "diff-motion-start" then
    vim.cmd("normal j")
    if vim.g.capture_state == "diff-motion-detail" then capture_pane:detail() end
  end
  return
end
-- UI-only native diff fixtures: open from old, with paired ranges, deletion
-- filler and a scope-local refresh retaining the previous explanation.
if vim.g.capture_state:match("^ranges%-diff") then
  local api = vim.api
  local old = api.nvim_get_current_win()
  api.nvim_buf_set_lines(0, 0, -1, false, {
    "local function authorize(user)", "  local legacy = user.legacy", "  audit(legacy)",
    "  return user.is_admin", "end", "", "-- Access decision", "return authorize(user)",
  })
  vim.bo.filetype = "lua"; vim.wo.winbar = " OLD · authorize.lua "
  vim.cmd(vim.g.capture_state == "ranges-diff-stacked" and "belowright split" or "belowright vsplit")
  local new = api.nvim_get_current_win()
  local buf = api.nvim_create_buf(false, true); api.nvim_win_set_buf(new, buf)
  api.nvim_buf_set_lines(buf, 0, -1, false, {
    "local function authorize(user)", '  return user.is_admin or user.role == "editor"',
    "end", "", "-- Access decision", "return authorize(user)",
  })
  vim.bo.filetype = "lua"; vim.wo.winbar = " NEW · authorize.lua "
  for _, candidate in ipairs({ old, new }) do
    api.nvim_win_call(candidate, function() vim.cmd("diffthis | normal! zR") end)
    vim.wo[candidate].wrap = false
  end
  vim.cmd("diffupdate")
  local deletion = { { path = "authorize.lua", side = "old", start_line = 2, end_line = 3 } }
  local paired = { { path = "authorize.lua", side = "old", start_line = 4, end_line = 5 },
    { path = "authorize.lua", side = "new", start_line = 2, end_line = 3 } }
  local result = { notes = {
    { summary = "Remove legacy auditing.", detail = "Legacy audit calls are removed.",
      intent_basis = "inferred", evidence = {}, anchors = deletion },
    { summary = "Editors can authorize.", detail = "The role grants another route to authorization.",
      intent_basis = "documented", evidence = {}, anchors = paired },
  } }
  _G.capture_pane = require("irrelevant_explainer.ui").open(old, { windows = { old = old, new = new } }, result)
  if vim.g.capture_state ~= "ranges-diff-old" then capture_pane:sync(new) end
  if vim.g.capture_state == "ranges-diff-pending" then
    capture_pane.pending = { source = old, scope = "hunk", row = 2, windows = { old = old, new = new },
      snapshot = { target = { anchors = deletion } } }
    capture_pane:set(result, "Pending · deletion hunk")
  elseif vim.g.capture_state == "ranges-diff-detail" then
    api.nvim_win_set_cursor(capture_pane.win, { 2, 0 }); capture_pane:detail()
  end
  return
end
if vim.g.capture_state:match("^diff") then
  local script = (vim.g.capture_checkout or vim.fn.getcwd()) .. "/tests/fixtures/agent.py"
  _G.capture_review = dofile((vim.g.capture_checkout or vim.fn.getcwd()) .. "/tests/review.lua").open(true)
  for _, win in pairs(capture_review.state.windows) do
    vim.wo[win].wrap = false
    if vim.g.capture_state:match("^diff%-numbers") then
      vim.wo[win].number, vim.wo[win].relativenumber = true, true
    end
    vim.api.nvim_win_call(win, function() vim.cmd("normal! zR") end)
  end
  local plugin = require("irrelevant_explainer")
  local focused = vim.g.capture_state == "diff-focused"
  local overview = vim.g.capture_state:match("^diff%-file%-overview")
    or vim.g.capture_state:match("^diff%-navigation")
  if focused then
    capture_review:write("src/unrelated.lua", string.rep("unrelated\n", 20000))
    vim.api.nvim_win_set_cursor(capture_review.state.source, { 4, 0 })
  end
  plugin.setup({ ai = { output = "plain", command = { "python3", script, focused and "explain" or overview and "review-overview" or "review" } },
    context = { max_bytes = focused and 12000 or 262144, radius = 2 } })
  if vim.g.capture_state == "diff-old" or vim.g.capture_state == "diff-incremental" then
    vim.api.nvim_set_current_win(capture_review.state.windows.old)
  end
  local session = plugin.explain(focused and "hunk" or "file")
  assert(vim.wait(5000, function() return session.pane.result ~= nil end), session.pane.status)
  _G.capture_pane = session.pane
  if vim.g.capture_state:match("^diff%-navigation") then
    local api, agent = vim.api, require("irrelevant_explainer.agent")
    local calls, run = 0, agent.run
    agent.run = function(...)
      calls = calls + 1
      return run(...)
    end
    capture_review:switch("docs/adr.md")
    plugin.config.ai.command = { "python3", script, "explain" }
    plugin.explain("file")
    assert(vim.wait(5000, function() return capture_pane.result and not session.pending end))
    api.nvim_set_current_win(capture_pane.win)
    api.nvim_win_set_width(capture_pane.win, 90)
    local expanded = vim.g.capture_state ~= "diff-navigation-collapsed"
    if expanded then capture_pane:detail(1) end
    local actions = require("diffview.actions")
    if vim.g.capture_state == "diff-navigation-empty" then actions.select_next_entry()
    else actions.select_prev_entry() end
    assert(vim.wait(5000, function() return not session.restoring and
      (vim.g.capture_state == "diff-navigation-empty" and capture_pane.status:match("^No explanations")
        or session.snapshot and session.snapshot.target.path == "policy.lua") end), capture_pane.status)
    assert(api.nvim_get_current_win() == capture_pane.win and calls == 1)
    assert((capture_pane.detail_buf ~= nil) == (vim.g.capture_state == "diff-navigation-expanded"))
    if capture_pane.detail_buf then
      local prose = table.concat(api.nvim_buf_get_lines(capture_pane.detail_buf, 0, -1, false), "\n")
      assert(prose:find("This file decides whether", 1, true), "first displayed overview did not expand")
    end
    assert(vim.v.errmsg == "")
  elseif vim.g.capture_state == "diff-publication-review" then
    -- Run the real offline review pipeline, then retain readable File notes.
    plugin.config.ai.command = { "python3", script, "whole-review" }
    session = plugin.explain("review")
    assert(vim.wait(10000, function() return capture_pane.review and not session.pending end))
    capture_review:switch("openspec/spec.md")
    plugin.config.ai.command = { "python3", script, "explain" }
    session = plugin.explain("file")
    assert(vim.wait(5000, function() return session.pane.result and #session.pane.result.notes > 0 and not session.pending end))
    capture_review:switch("policy.lua")
    plugin.config.ai.command = { "python3", script, "review" }
    session = plugin.explain("file")
    assert(vim.wait(5000, function() return capture_pane.result and #capture_pane.result.notes > 0 and not session.pending end))
    plugin.review()
    assert(vim.wait(5000, function() return capture_pane.review_mode and not session.review_checking end))
    vim.api.nvim_set_current_win(capture_pane.win)
    vim.api.nvim_win_set_width(capture_pane.win, 90)
    vim.api.nvim_win_set_width(capture_review.state.windows.old, 51)
    for row, entry in pairs(capture_pane.review_references) do
      if entry.path == "openspec/spec.md" then
        _G.capture_reference_row = row
        vim.api.nvim_win_set_cursor(capture_pane.win, { row, 0 })
      end
    end
    _G.capture_review_view = vim.api.nvim_win_call(capture_pane.win, vim.fn.winsaveview)
    -- After the offline fixture preparation, navigation must launch no agent.
    require("irrelevant_explainer.agent").run = function() error("display-only navigation launched inference") end
  elseif vim.g.capture_state:match("^diff%-numbers") then
    local expanded = vim.g.capture_state == "diff-numbers-detail"
    vim.api.nvim_set_current_win(capture_pane.win)
    if expanded then capture_pane:detail(1) end
    capture_review:switch("openspec/spec.md")
    for _, win in pairs(capture_review.state.windows) do
      assert(vim.wo[win].number and vim.wo[win].relativenumber)
    end
    plugin.config.ai.command = { "python3", script, "explain" }
    session = plugin.explain("file"); _G.capture_pane = session.pane
    assert(vim.wait(5000, function() return capture_pane.result ~= nil end))
    vim.api.nvim_set_current_win(capture_pane.win)
    if expanded then capture_pane:detail(1) end
    assert(not vim.wo[capture_pane.win].number and not vim.wo[capture_pane.win].relativenumber)
  elseif vim.g.capture_state:match("^diff%-gutter") then
    local api = vim.api
    capture_pane.result.notes[1].detail = string.rep("Read the changed permission check alongside its source. ", 6)
    api.nvim_set_current_win(capture_pane.win)
    capture_pane:jump(1); capture_pane:detail(1)
    plugin.toggle_auto_explain()
    if vim.g.capture_state ~= "diff-gutter-detail" then
      if vim.g.capture_state == "diff-gutter-collapsed-switch" then capture_pane:back() end
      local actions, panel = require("diffview.actions"), capture_review.view.panel
      actions.focus_files()
      for _, entry in ipairs(panel:ordered_file_list()) do
        if entry.path == "openspec/spec.md" then panel:highlight_file(entry); break end
      end
      -- Use the general fixture response for the newly selected Markdown file.
      plugin.config.ai.command = { "python3", script, "explain" }
      actions.select_entry()
      assert(vim.wait(5000, function()
        return session.snapshot and session.snapshot.target.path == "openspec/spec.md"
          and capture_pane.status:match("^Ready")
      end), capture_pane.status)
      assert(capture_pane.detail_buf == nil)
      assert(not vim.wo[capture_pane.win].statuscolumn:find("irrelevant_explainer_detail_active", 1, true))
      assert(api.nvim_get_current_win() == panel.winid)
    end
    vim.cmd("redraw!"); assert(vim.v.errmsg == "", vim.v.errmsg)
  elseif vim.g.capture_state:match("^diff%-auto") then
    plugin.toggle_auto_explain()
    vim.api.nvim_set_current_win(capture_pane.win)
    capture_pane:jump(1)
    if vim.g.capture_state == "diff-auto-detail" then capture_pane:detail(1) end
    if vim.g.capture_state == "diff-auto-narrow" then
      vim.api.nvim_win_set_width(capture_pane.win, 32); capture_pane:header()
    end
    if vim.g.capture_state == "diff-auto-off" then plugin.toggle_auto_explain() end
    local text = vim.api.nvim_eval_statusline(vim.wo[capture_pane.win].winbar,
      { winid = capture_pane.win, use_winbar = true }).str
    assert((text:find("Auto", 1, true) ~= nil) == (vim.g.capture_state ~= "diff-auto-off"))
  elseif overview then
    assert(capture_pane.locations[1].row == 1)
    assert(vim.deep_equal(capture_pane.result.notes[1].anchors, session.snapshot.target.anchors))
    vim.api.nvim_set_current_win(capture_pane.win)
    vim.api.nvim_win_set_width(capture_pane.win, 90)
    if vim.g.capture_demo then
      -- Concise synthetic summaries keep the complete overview readable.
      capture_pane.result.notes[1].summary = "File overview: cancellation policy."
      capture_pane.result.notes[2].summary = "Editors still bypass ownership."
      vim.api.nvim_win_set_width(capture_review.state.windows.old, 51)
      capture_pane:render()
    end
    vim.cmd("normal! gg"); capture_pane:sync(capture_pane.win)
    if vim.g.capture_state == "diff-file-overview-detail" then capture_pane:detail(1) end
  elseif vim.g.capture_state == "diff-saved-empty" or vim.g.capture_state == "diff-saved-restored" then
    local saved = vim.deepcopy(capture_pane.result)
    capture_review:switch("openspec/spec.md")
    assert(vim.wait(5000, function() return capture_pane.status:match("^No explanations") ~= nil end), capture_pane.status)
    if vim.g.capture_state == "diff-saved-restored" then
      capture_review:switch("policy.lua")
      assert(vim.wait(5000, function() return capture_pane.status == "Ready · restored" end), capture_pane.status)
      assert(vim.deep_equal(saved, capture_pane.result))
      vim.api.nvim_set_current_win(capture_pane.win)
      capture_pane:jump(1)
    end
  elseif vim.g.capture_state == "diff-incremental" then
    vim.api.nvim_win_set_cursor(capture_review.state.windows.old, { 8, 0 })
    plugin.setup({ ai = { output = "plain", command = { "python3", script, "explain-slow" } } })
    plugin.explain("hunk")
    assert(vim.wait(5000, function() return capture_pane.pending and capture_pane.pending.snapshot ~= nil end),
      capture_pane.status)
  elseif vim.g.capture_state == "diff-detail" or vim.g.capture_state == "diff-detail-back"
      or vim.g.capture_state == "diff-detail-background" then
    capture_pane:jump(1); capture_pane:detail()
    if vim.g.capture_state == "diff-detail-back" then capture_pane:back() end
    if vim.g.capture_state == "diff-detail-background" then
      capture_pane.background = "Running docs/adr.md"; capture_pane:header()
    end
  elseif vim.g.capture_state == "diff-review-return" then
    local manifest = session.snapshot.comparison.manifest
    local entry
    for _, item in ipairs(manifest) do if item.path == "policy.lua" then entry = item end end
    capture_pane:set_review({ title = "Change narrative", sections = {
      { heading = "Cancellation policy", detail = "The policy and requirements change together.",
        intent_basis = "inferred", file_ids = { assert(entry).file_id } },
    } }, manifest, "Ready")
    capture_pane:show_review()
    for row in pairs(capture_pane.review_references) do
      vim.api.nvim_set_current_win(capture_pane.win)
      vim.api.nvim_win_set_cursor(capture_pane.win, { row, 0 }); vim.cmd("normal \r")
      break
    end
    assert(not capture_pane.review_mode and capture_pane.result)
  elseif vim.g.capture_state == "diff-scroll" then
    capture_pane:scroll(vim.api.nvim_replace_termcodes("<C-d>", true, false, true))
  elseif vim.g.capture_state == "diff-stale" then
    capture_review:write("docs/adr.md", "Rationale: preserve the owner's decision.\nChanged during inference.\n")
    assert(vim.wait(4000, function() return session.stale end))
  elseif vim.g.capture_state == "diff-failed" then
    plugin.setup({ ai = { output = "plain", command = { "python3", script, "nonzero" } } })
    vim.notify = function() end
    session = plugin.refresh(); _G.capture_pane = session.pane
    assert(vim.wait(5000, function() return capture_pane.status:find("Failed", 1, true) ~= nil end))
  elseif vim.g.capture_state == "diff-switch" then
    capture_review:switch("openspec/spec.md")
    plugin.setup({ ai = { output = "plain", command = { "python3", script, "explain" } } })
    session = plugin.explain("file"); _G.capture_pane = session.pane
    assert(vim.wait(5000, function() return capture_pane.result ~= nil end))
  end
  return
end
vim.wo.number = true
vim.wo.winbar = " authorize.lua "
local source = vim.api.nvim_get_current_win()
vim.api.nvim_buf_set_lines(0, 0, -1, false, {
  "local function can_edit(user)", "  if not user then", "    return false", "  end", "",
  '  return user.is_admin or user.role == "editor"', "end", "",
  "-- An explicit guard replaces the old missing-user error.",
  "-- The new role check broadens editing access.",
})
vim.bo.filetype = "lua"
local function note(line, summary, detail, basis)
  return { summary = summary, detail = detail, intent_basis = basis or "documented",
    anchors = { { path = "authorize.lua", side = "buffer", start_line = line, end_line = line } },
    evidence = { { path = "openspec/changes/editor-access/specs/access/spec.md", side = "new", start_line = 8, end_line = 12 } } }
end
_G.capture_pane = require("irrelevant_explainer.ui").open(source, { windows = { buffer = source } }, { notes = {
  note(1, "Controls who can edit.", "Checks access for the supplied user.", "unknown"),
  note(2, "Missing user: deny access.", "The guard returns false instead of indexing a missing user.", "inferred"),
  note(6, "Also grant editing access to editors.", "Previously, only `is_admin` could grant access. The role check adds another way to grant access, matching the editor-access requirement in this change.\n\n**Caution:** schema validation confirms that the cited range was supplied, not that the interpretation is necessarily correct."),
} })
if vim.g.capture_state:match("^file%-overview") then
  capture_pane.result.notes[1] = note(1, "File overview: decides who may edit.",
    "This file centralizes editing authorization: missing users are denied, while administrators and editors may edit.", "inferred")
  capture_pane.result.notes[1].kind = "overview"
  capture_pane.result.notes[1].anchors[1].end_line = vim.api.nvim_buf_line_count(vim.api.nvim_win_get_buf(source))
  if vim.g.capture_state == "file-overview-header" then vim.wo[source].winbar = "" end
  capture_pane:render()
  vim.api.nvim_set_current_win(capture_pane.win)
  capture_pane:sync(capture_pane.win)
  if vim.g.capture_state == "file-overview-detail" then capture_pane:detail(1) end
elseif vim.g.capture_state == "focus" or vim.g.capture_state == "focus-wrapped" or vim.g.capture_state == "focus-folded" then
  capture_pane.result.notes[3].anchors[1].end_line = 7
  if vim.g.capture_state == "focus-wrapped" then
    vim.api.nvim_buf_set_lines(vim.api.nvim_win_get_buf(source), 5, 6, false, { string.rep("-- wrapped code ", 10) })
    vim.wo[source].wrap = true
  elseif vim.g.capture_state == "focus-folded" then
    vim.wo[source].foldmethod = "manual"; vim.wo[source].foldenable = true
    vim.api.nvim_win_call(source, function() vim.cmd("6,7fold") end)
  end
  capture_pane:render()
  vim.api.nvim_set_current_win(capture_pane.win)
  vim.api.nvim_win_set_cursor(capture_pane.win, { 6, 0 }); capture_pane:sync(capture_pane.win)
elseif vim.g.capture_state:match("^overlap") then
  capture_pane.result.notes[3].anchors[1].end_line = 8
  capture_pane.result.notes[4] = note(6, "The user role must be available.", "The expression reads `user.role` when `is_admin` is false.", "unknown")
  capture_pane.result.notes[4].anchors[1].end_line = 10
  if vim.g.capture_state == "overlap-folded" then
    vim.wo[source].foldmethod = "manual"; vim.wo[source].foldenable = true
    vim.api.nvim_win_call(source, function() vim.cmd("6,8fold") end)
  end
  capture_pane:render()
elseif vim.g.capture_state == "ranges" or vim.g.capture_state == "incremental" then
  capture_pane.result.notes[1].anchors[1].end_line = 7
  capture_pane.result.notes[2].anchors[1].end_line = 4
  capture_pane:render()
  if vim.g.capture_state == "incremental" then
    capture_pane.pending = { source = source, scope = "selection", row = 6, windows = { buffer = source },
      snapshot = { target = { anchors = { { side = "buffer", start_line = 6, end_line = 7 } } } } }
    capture_pane:set(capture_pane.result, "Pending · selected range")
  end
elseif vim.g.capture_state == "detail" or vim.g.capture_state == "detail-back" or vim.g.capture_state == "detail-next"
    or vim.g.capture_state == "detail-narrow" or vim.g.capture_state == "detail-light"
    or vim.g.capture_state == "detail-no-header" or vim.g.capture_state == "detail-no-header-first" then
  if vim.g.capture_state:match("^detail%-no%-header") then
    vim.wo[source].winbar = ""; capture_pane:render()
  end
  vim.api.nvim_win_set_cursor(capture_pane.win, { vim.g.capture_state == "detail-no-header-first" and 1 or 6, 0 })
  capture_pane:detail()
  if vim.g.capture_state == "detail-back" then capture_pane:back()
  elseif vim.g.capture_state == "detail-next" then capture_pane:detail(1) end
elseif vim.g.capture_state:match("^detail%-markdown") then
  if vim.g.capture_state:find("narrow", 1, true) then vim.api.nvim_win_set_width(capture_pane.win, 38) end
  capture_pane.result.notes[3].detail = "## Access check\n\nReads `user.is_admin` and `user.role` to decide whether editing is allowed.\n\n"
    .. "```lua\nreturn user.is_admin or user.role == \"editor\"\n```\n\n"
    .. "- Administrators pass immediately.\n- Otherwise, the role must equal `\"editor\"`.\n\n"
    .. "**Scope:** this explains the supplied check, not unavailable callers."
  vim.api.nvim_win_set_cursor(capture_pane.win, { 6, 0 }); capture_pane:detail()
  if vim.g.capture_state == "detail-markdown-back" then capture_pane:back() end
elseif vim.g.capture_state == "folded" then
  vim.wo[source].foldmethod = "manual"; vim.wo[source].foldenable = true
  vim.api.nvim_win_call(source, function() vim.cmd("1,7fold") end); capture_pane:render()
elseif vim.g.capture_state == "wrapped" or vim.g.capture_state == "wrapped-long" or vim.g.capture_state == "wrapped-skipped"
    or vim.g.capture_state == "wrapped-cursor" then
  local repeats = vim.g.capture_state == "wrapped-long" and 400 or 10
  vim.api.nvim_buf_set_lines(vim.api.nvim_win_get_buf(source), 0, 1, false, { string.rep("-- wrapped context ", repeats) })
  vim.wo[source].wrap = true; capture_pane:render()
  if vim.g.capture_state == "wrapped-skipped" then
    vim.wo[source].smoothscroll = true
    local width = vim.api.nvim_win_get_width(source) - vim.fn.getwininfo(source)[1].textoff
    vim.api.nvim_win_call(source, function() vim.fn.winrestview({ topline = 1, skipcol = width, lnum = 1, col = width + 5 }) end)
    capture_pane:align()
  elseif vim.g.capture_state == "wrapped-cursor" then
    local width = vim.api.nvim_win_get_width(source) - vim.fn.getwininfo(source)[1].textoff
    for _, win in ipairs({ source, capture_pane.win }) do
      vim.wo[win].cursorline = true; vim.wo[win].cursorlineopt = "screenline"
    end
    vim.api.nvim_set_hl(0, "CursorLine", { bg = "#263544" })
    vim.api.nvim_win_set_cursor(source, { 1, width + 5 }); capture_pane:sync(source)
  end
elseif vim.g.capture_state == "focused" or vim.g.capture_state == "focused-detail" or vim.g.capture_state == "focused-folded" then
  capture_pane.snapshot.context = { strategy = "focused", radius = 20,
    omitted_files = { "docs/adr.md", "src/other.lua", "openspec/other/spec.md" } }
  if vim.g.capture_state == "focused-folded" then
    vim.wo[source].winbar = ""; vim.wo[source].foldmethod = "manual"; vim.wo[source].foldenable = true
    vim.api.nvim_win_call(source, function() vim.cmd("1,7fold") end)
  end
  capture_pane:render()
  if vim.g.capture_state == "focused-detail" then
    vim.api.nvim_win_set_cursor(capture_pane.win, { 6, 0 }); capture_pane:detail()
  end
elseif vim.g.capture_state == "navigation" or vim.g.capture_state == "detail-bottom" then
  local buf = vim.api.nvim_win_get_buf(source)
  local lines = {}; for i = 11, 120 do lines[#lines + 1] = "-- context line " .. i end
  vim.api.nvim_buf_set_lines(buf, -1, -1, false, lines)
  capture_pane.result.notes[#capture_pane.result.notes + 1] = note(100, "An off-screen explanation.",
    "Ordinary logical-line motion and counted n/p can reach this note without another inference.", "inferred")
  capture_pane:render()
  vim.api.nvim_set_current_win(capture_pane.win)
  vim.cmd("normal 3n")
  if vim.g.capture_state == "detail-bottom" then
    vim.api.nvim_win_call(source, function()
      vim.fn.winrestview({ topline = 100 - vim.fn.getwininfo(source)[1].height + 1, lnum = 100, col = 0 })
    end)
    capture_pane:align(); capture_pane:detail()
  end
elseif vim.g.capture_state == "pending" or vim.g.capture_state == "pending-folded" or vim.g.capture_state == "pending-cursor" then
  vim.wo[source].winbar = "" -- status must remain visible with no extra header row
  if vim.g.capture_state == "pending-folded" then
    vim.wo[source].foldmethod = "manual"; vim.wo[source].foldenable = true
    vim.api.nvim_win_call(source, function() vim.cmd("1,7fold") end)
  end
  capture_pane.pending = { source = source, scope = "file", row = 1, windows = { buffer = source } }
  capture_pane:set(nil, "Pending · external agent")
  if vim.g.capture_state == "pending-cursor" then
    vim.api.nvim_set_current_win(capture_pane.win)
    vim.wo[capture_pane.win].cursorline = true
    vim.api.nvim_set_hl(0, "CursorLine", { bg = "#263544" })
    vim.api.nvim_win_set_cursor(capture_pane.win, { 5, 0 }); capture_pane:sync(capture_pane.win)
  end
elseif vim.g.capture_state == "cached-code" then
  local accepted = vim.deepcopy(capture_pane.result)
  vim.api.nvim_set_current_win(capture_pane.win)
  capture_pane:set(accepted, "Ready · cached")
  assert(vim.deep_equal(accepted, capture_pane.result))
  assert(vim.api.nvim_get_current_win() == capture_pane.win)
elseif vim.g.capture_state == "failed" then
  vim.wo[source].winbar = ""; capture_pane:set(nil, "Failed · external agent exit 1")
elseif vim.g.capture_state == "stale" then
  capture_pane:set(capture_pane.result, "Stale · source changed")
elseif vim.g.capture_state == "cancelled" then
  vim.wo[source].winbar = ""; capture_pane:set(nil, "Cancelled")
elseif vim.g.capture_state == "global-statusline" then
  vim.wo[source].winbar = ""; capture_pane:set(capture_pane.result, "Pending · refresh")
  vim.api.nvim_set_current_win(capture_pane.win); capture_pane:render()
end
