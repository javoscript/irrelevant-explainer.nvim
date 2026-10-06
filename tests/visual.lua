vim.opt.runtimepath:prepend(vim.fn.getcwd())
for _, path in ipairs(vim.g.capture_runtime or {}) do vim.opt.runtimepath:append(path) end
-- Exercise the installed optional plugin normally, without loading user config.
if #(vim.g.capture_runtime or {}) > 0 then vim.cmd("runtime plugin/render-markdown.lua") end
vim.o.termguicolors = true
vim.o.laststatus = 3
vim.o.statusline = " EXTERNAL EDITOR BAR %= untouched by Explainr "
vim.o.showmode = false
vim.o.signcolumn = "auto:2"
if vim.g.capture_state == "detail-light" or vim.g.capture_state == "detail-highlight-rose-pine-light" then
  vim.o.background = "light"
end
vim.cmd("colorscheme default")
vim.api.nvim_set_hl(0, "Normal", vim.g.capture_state == "detail-light"
  and { fg = "#263544", bg = "#fafafa" } or { fg = "#d5dce5", bg = "#18212b" })
vim.api.nvim_set_hl(0, "StatusLine", { fg = "#adc6dd", bg = "#263544" })
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
  _G.capture_pane = require("explainr.ui").open(source, { windows = { new = source } }, { notes = {
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
  _G.capture_pane = require("explainr.ui").open(new, { windows = { old = old, new = new } }, { notes = { {
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
  _G.capture_pane = require("explainr.ui").open(source, { windows = { old = source } }, { notes = { {
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
  _G.capture_pane = require("explainr.ui").open(new, { windows = { old = old, new = new } }, { notes = {
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
  _G.capture_pane = require("explainr.ui").open(new, { windows = { old = old, new = new } }, { notes = {
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
  _G.capture_pane = require("explainr.ui").open(new, { windows = { old = old, new = new } },
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
  local fixture = dofile("tests/multihunk.lua").open()
  for side, win in pairs({ old = fixture.old, new = fixture.new }) do
    vim.wo[win].number, vim.wo[win].relativenumber = true, false
    vim.wo[win].winbar = " " .. side:upper() .. " · config.lua "
  end
  if vim.g.capture_state == "diff-multihunk-detail-range" then
    fixture.result.notes[3].anchors[1].end_line = 67
    fixture.result.notes[3].anchors[2].end_line = 71
    fixture.result.notes[3].detail = "The `in_progress` setting now uses `play` instead of `tools`. Nearby configuration is otherwise unchanged."
  end
  _G.capture_pane = require("explainr.ui").open(fixture.new,
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
  _G.capture_pane = require("explainr.ui").open(old, { windows = { old = old, new = new },
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
  _G.capture_pane = require("explainr.ui").open(old, { windows = { old = old, new = new } }, result)
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
  local script = vim.fn.getcwd() .. "/tests/fixtures/agent.py"
  _G.capture_review = dofile("tests/review.lua").open(true)
  for _, win in pairs(capture_review.state.windows) do
    vim.wo[win].wrap = false
    vim.api.nvim_win_call(win, function() vim.cmd("normal! zR") end)
  end
  local plugin = require("explainr")
  local focused = vim.g.capture_state == "diff-focused"
  local overview = vim.g.capture_state:match("^diff%-file%-overview")
  if focused then
    capture_review:write("src/unrelated.lua", string.rep("unrelated\n", 20000))
    vim.api.nvim_win_set_cursor(capture_review.state.source, { 4, 0 })
  end
  plugin.setup({ ai = { command = { "python3", script, focused and "explain" or overview and "review-overview" or "review" } },
    context = { max_bytes = focused and 12000 or 262144, radius = 2 } })
  if vim.g.capture_state == "diff-old" or vim.g.capture_state == "diff-incremental" then
    vim.api.nvim_set_current_win(capture_review.state.windows.old)
  end
  local session = plugin.diff(focused and "hunk" or "file")
  assert(vim.wait(5000, function() return session.pane.result ~= nil end), session.pane.status)
  _G.capture_pane = session.pane
  if overview then
    assert(capture_pane.locations[1].row == 1)
    assert(vim.deep_equal(capture_pane.result.notes[1].anchors, session.snapshot.target.anchors))
    vim.api.nvim_set_current_win(capture_pane.win)
    capture_pane:jump(1)
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
    plugin.setup({ ai = { command = { "python3", script, "explain-slow" } } })
    plugin.diff("hunk")
    assert(vim.wait(5000, function() return capture_pane.pending and capture_pane.pending.snapshot ~= nil end),
      capture_pane.status)
  elseif vim.g.capture_state == "diff-detail" or vim.g.capture_state == "diff-detail-back" then
    capture_pane:jump(1); capture_pane:detail()
    if vim.g.capture_state == "diff-detail-back" then capture_pane:back() end
  elseif vim.g.capture_state == "diff-scroll" then
    capture_pane:scroll(vim.api.nvim_replace_termcodes("<C-d>", true, false, true))
  elseif vim.g.capture_state == "diff-stale" then
    capture_review:write("docs/adr.md", "Rationale: preserve the owner's decision.\nChanged during inference.\n")
    assert(vim.wait(4000, function() return session.stale end))
  elseif vim.g.capture_state == "diff-failed" then
    plugin.setup({ ai = { command = { "python3", script, "nonzero" } } })
    vim.notify = function() end
    session = plugin.refresh(); _G.capture_pane = session.pane
    assert(vim.wait(5000, function() return capture_pane.status:find("Failed", 1, true) ~= nil end))
  elseif vim.g.capture_state == "diff-switch" then
    capture_review:switch("openspec/spec.md")
    plugin.setup({ ai = { command = { "python3", script, "explain" } } })
    session = plugin.diff("file"); _G.capture_pane = session.pane
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
_G.capture_pane = require("explainr.ui").open(source, { windows = { buffer = source } }, { notes = {
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
elseif vim.g.capture_state == "detail-markdown" then
  capture_pane.result.notes[3].detail = "Reads `user.is_admin` and `user.role` to decide whether editing is allowed.\n\n"
    .. "```lua\nreturn user.is_admin or user.role == \"editor\"\n```\n\n"
    .. "- Administrators pass immediately.\n- Otherwise, the role must equal `\"editor\"`.\n\n"
    .. "**Scope:** this explains the supplied check, not unavailable callers."
  vim.api.nvim_win_set_cursor(capture_pane.win, { 6, 0 }); capture_pane:detail()
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
