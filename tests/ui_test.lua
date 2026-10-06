local ui = require("explainr.ui")
local api = vim.api
local function setup(lines)
  vim.cmd("silent! only!")
  vim.o.lines, vim.o.columns = 30, 120
  local buf = api.nvim_create_buf(false, true)
  api.nvim_win_set_buf(0, buf)
  api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.wo.wrap, vim.wo.foldenable, vim.wo.winbar = false, false, ""
  vim.wo.number, vim.wo.relativenumber, vim.wo.signcolumn, vim.wo.foldcolumn = false, false, "no", "0"
  vim.wo.statuscolumn = ""
  return api.nvim_get_current_win(), buf
end
local function note(line, summary, side)
  return { summary = summary or ("Note " .. line), detail = "Full explanation without another request.",
    intent_basis = "unknown", evidence = {}, anchors = { { path = "test.lua", side = side or "buffer", start_line = line, end_line = line } } }
end
local function summary(text) return "▎ ? " .. text .. " [+]" end
local function detail_lines(p)
  return api.nvim_buf_get_lines(p.detail_buf, p.detail_layout.first - 1, p.detail_layout.last, false)
end
local function detail_screen(p, row)
  return vim.fn.screenpos(p.win, p.detail_layout.first + row - 1, 1).row
end
local function marks(p, namespace)
  return api.nvim_buf_get_extmarks(p.buf, api.nvim_create_namespace(namespace), 0, -1, { details = true })
end
local function state(p)
  return api.nvim_eval_statusline(vim.wo[p.win].winbar, { winid = p.win, use_winbar = true }).str
end
local function motion(win, keys)
  api.nvim_set_current_win(win)
  vim.cmd.normal({ keys, bang = true })
  api.nvim_exec_autocmds("CursorMoved", { buffer = api.nvim_win_get_buf(win) })
end
local function key(buf, lhs)
  for _, mapping in ipairs(api.nvim_buf_get_keymap(buf, "n")) do
    if api.nvim_replace_termcodes(mapping.lhs, true, false, true) == api.nvim_replace_termcodes(lhs, true, false, true) then
      return mapping.callback()
    end
  end
  error("missing mapping " .. lhs)
end

T.test("header reservation starts before results and survives every request state", function()
  for _, kind in ipairs({ "overview", "block" }) do
    local source = setup({ string.rep("wrapped ", 30), "two", "three", "four", "five" })
    vim.wo[source].wrap = true; vim.wo[source].foldmethod = "manual"; vim.wo[source].foldenable = true
    api.nvim_win_call(source, function() vim.cmd("3,4fold") end)
    local p = ui.open(source, { windows = { buffer = source } }, nil)
    p:set(nil, "Pending · collecting")
    local function geometry()
      vim.cmd("redraw!")
      local rows = {}
      for _, line in ipairs({ 1, 2, 3, 5 }) do
        rows[#rows + 1] = vim.fn.screenpos(source, line, 1).row
        T.eq(rows[#rows], vim.fn.screenpos(p.win, line, 1).row)
      end
      T.eq(" ", vim.wo[source].winbar); T.eq(1, vim.fn.getwininfo(p.win)[1].winbar)
      T.eq(5, api.nvim_buf_line_count(p.buf)); T.eq({}, marks(p, "explainr.state"))
      return rows
    end
    local initial = geometry()
    local n = note(1); n.kind = kind; n.anchors[1].end_line = 5
    for _, status in ipairs({ "Ready", "Pending · refresh", "Failed", "Stale", "Cancelled" }) do
      p:set({ notes = { n } }, status); T.eq(initial, geometry())
    end
    p:set(nil, "Stale"); T.eq(initial, geometry())
    p:close(); T.eq("", vim.wo[source].winbar)
  end
end)

T.test("matched headers reconcile diff source ownership and preserve user replacements", function()
  local old = setup({ "first", "removed", "last" })
  vim.wo[old].winbar = "Existing old header"
  vim.cmd("belowright vsplit")
  local new, buf = api.nvim_get_current_win(), api.nvim_create_buf(false, true)
  api.nvim_win_set_buf(new, buf); api.nvim_buf_set_lines(buf, 0, -1, false, { "first", "last" })
  vim.wo[new].winbar = ""
  for _, win in ipairs({ old, new }) do api.nvim_win_call(win, function() vim.cmd("diffthis | normal! zR") end) end
  vim.cmd("diffupdate")
  local p = ui.open(new, { windows = { old = old, new = new } }, nil)
  p:set(nil, "Pending · diff collection")
  T.eq("Existing old header", vim.wo[old].winbar); T.eq(" ", vim.wo[new].winbar)
  p:set({ notes = { note(2, "Removed", "old") } }, "Ready")
  p:sync(old); T.eq(old, p.source)
  p:set(nil, "Stale"); T.eq(" ", vim.wo[new].winbar)
  p.snapshot = { windows = { old = old } }; p:render()
  T.eq("", vim.wo[new].winbar); T.eq(nil, p.source_headers[new])
  p.pending = { windows = { new = new } }; p:render(); T.eq(" ", vim.wo[new].winbar)
  vim.wo[new].winbar = "User replacement"
  p:close(); T.eq("User replacement", vim.wo[new].winbar); T.eq("Existing old header", vim.wo[old].winbar)
  vim.cmd("diffoff!")
end)

T.test("evaluated header colors are state independent and clipping preserves literal text", function()
  local colors = { ExplainrTitle = 0x33ccdd, ExplainrMetadata = 0x778899,
    ExplainrDocumented = 0x55bb66, ExplainrInferred = 0xddaa44, ExplainrUnknown = 0x6699ee }
  local saved = {}
  for group, color in pairs(colors) do
    saved[group] = api.nvim_get_hl(0, { name = group })
    api.nvim_set_hl(0, group, { fg = color })
  end
  local p
  local ok, err = xpcall(function()
    local source = setup({ "one", "two", "three", "four" }); vim.o.columns = 280
    p = ui.open(source, { windows = { buffer = source } }, nil)
    api.nvim_win_set_width(p.win, 130)
    local function check(parts)
      local evaluated = api.nvim_eval_statusline(vim.wo[p.win].winbar,
        { winid = p.win, use_winbar = true, highlights = true })
      assert(evaluated.width <= api.nvim_win_get_width(p.win), evaluated.str)
      for text, expected in pairs(parts) do
        local first, last = evaluated.str:find(text, 1, true)
        assert(first, evaluated.str .. " missing " .. text)
        for offset = first - 1, last - 1 do
          local actual
          for _, span in ipairs(evaluated.highlights) do
            if span.start <= offset then actual = span.group end
          end
          T.eq(expected, actual)
        end
      end
      return evaluated.str
    end
    for _, status in ipairs({ "Pending · collecting", "Ready", "Failed", "Stale", "Cancelled" }) do
      p:set(nil, status)
      check({ Explainr = "ExplainrTitle", [status] = "ExplainrMetadata", [" · "] = "ExplainrMetadata",
        D = "ExplainrDocumented", ["~"] = "ExplainrInferred", ["?"] = "ExplainrUnknown",
        documented = "ExplainrMetadata", inferred = "ExplainrMetadata", unknown = "ExplainrMetadata" })
    end
    local literal = "Failed · 50% %#Error# 界界"
    p:set(nil, literal); assert(check({ [literal] = "ExplainrMetadata" }):find(literal, 1, true))
    api.nvim_win_set_width(p.win, 80)
    p:set(nil, "Failed · " .. string.rep("界", 50))
    assert(check({ ["Failed · 界"] = "ExplainrMetadata", D = "ExplainrDocumented",
      ["~"] = "ExplainrInferred", ["?"] = "ExplainrUnknown" }):find("… · D", 1, true))
    p:set(nil, "Ready")
    for _, width in ipairs({ 60, 59, 40, 25, 12 }) do
      api.nvim_win_set_width(p.win, width); p:render()
      check({ [width >= 14 and "0 explanations" or "0 explan"] = "ExplainrMetadata" })
      if width >= 40 then
        check({ D = "ExplainrDocumented", ["~"] = "ExplainrInferred", ["?"] = "ExplainrUnknown",
          inferred = "ExplainrMetadata" })
      end
    end
    api.nvim_win_set_width(p.win, 130)
    p:set({ notes = { note(2), note(3) } }, "Ready"); motion(p.win, "2G0"); p:detail()
    check({ Explainr = "ExplainrTitle", ["1 / 2"] = "ExplainrMetadata", Expanded = "ExplainrMetadata" })
    local row = vim.fn.screenpos(source, 2, 1).row
    vim.wo[source].winbar = ""
    api.nvim_exec_autocmds("OptionSet", { pattern = "winbar" })
    T.eq(" ", vim.wo[source].winbar); T.eq(row, vim.fn.screenpos(source, 2, 1).row)
    key(p.detail_buf, "n"); check({ ["2 / 2"] = "ExplainrMetadata" })
    key(p.detail_buf, "q"); check({ ["2 / 2"] = "ExplainrMetadata", D = "ExplainrDocumented" })
    for group, color in pairs(colors) do T.eq(color, api.nvim_get_hl(0, { name = group, link = false }).fg) end
  end, debug.traceback)
  if p and not p.closed then p:close() end
  for group, value in pairs(saved) do api.nvim_set_hl(0, group, value) end
  assert(ok, err)
end)

T.test("sparse rows, read-only pane, truncation and in-pane detail", function()
  local win = setup({ "one", "two", "three", "four", "five" })
  local original = vim.wo[win].wrap
  local p = ui.open(win, { windows = { buffer = win } }, { notes = { note(1), note(4, string.rep("界", 70)) } })
  T.eq(summary("Note 1"), api.nvim_buf_get_lines(p.buf, 0, 1, false)[1])
  T.eq({ "", "" }, api.nvim_buf_get_lines(p.buf, 1, 3, false))
  assert(api.nvim_buf_get_lines(p.buf, 3, 4, false)[1]:find("%[%+%]"))
  T.eq(false, vim.bo[p.buf].modifiable); T.eq(false, vim.wo[p.win].diff)
  api.nvim_win_set_cursor(p.win, { 4, 0 })
  local before = api.nvim_win_call(win, vim.fn.winsaveview)
  p:detail(); assert(api.nvim_win_is_valid(p.detail_win))
  T.eq(before, api.nvim_win_call(win, vim.fn.winsaveview))
  p:close(); T.eq(original, vim.wo[win].wrap)
end)
T.test("wrapped rows, folds, matched winbars and page scrolling", function()
  local lines = { string.rep("x", 130), "two", "three", "four", "five" }
  for i = 6, 100 do lines[i] = "line " .. i end
  local win = setup(lines)
  vim.wo[win].wrap = true; vim.wo[win].winbar = "Source"
  local p = ui.open(win, { windows = { buffer = win } }, { notes = { note(1), note(2), note(4) } })
  local h = api.nvim_win_text_height(win, { start_row = 0, end_row = 0, start_vcol = 0 }).all
  assert(h > 1)
  T.eq(100, api.nvim_buf_line_count(p.buf))
  T.eq(summary("Note 2"), api.nvim_buf_get_lines(p.buf, 1, 2, false)[1])
  T.eq(h + 1, api.nvim_win_text_height(p.win, { start_row = 0, end_row = 1 }).all)
  T.eq(1, vim.fn.getwininfo(p.win)[1].winbar)
  vim.wo[win].foldmethod = "manual"; vim.wo[win].foldenable = true
  api.nvim_win_call(win, function() vim.cmd("2,4fold") end)
  p:render()
  T.eq(4, api.nvim_win_call(p.win, function() return vim.fn.foldclosedend(2) end))
  local row = vim.b[p.buf].explainr_foldtext["2"]
  assert(row:find("folded") and row:find("Note 2") and row:find("Note 4"))
  api.nvim_win_set_cursor(p.win, { 2, 0 }); p:detail()
  local detail = table.concat(api.nvim_buf_get_lines(api.nvim_win_get_buf(p.detail_win), 0, -1, false), "\n")
  assert(detail:find("Note 2") and detail:find("Note 4"))
  key(api.nvim_win_get_buf(p.detail_win), "q")
  p:scroll(api.nvim_replace_termcodes("<C-f>", true, false, true))
  assert(p.projection[1].line > 5)
  T.eq(true, vim.wo[win].wrap); T.eq(true, vim.wo[win].foldenable)
  p:close()
end)
T.test("deleted old rows map to new-side filler without joining diff", function()
  local old = setup({ "first", "removed one", "removed two", "last" })
  vim.cmd("vsplit")
  local new = api.nvim_get_current_win()
  local buf = api.nvim_create_buf(false, true); api.nvim_win_set_buf(new, buf)
  api.nvim_buf_set_lines(buf, 0, -1, false, { "first", "last" })
  for _, win in ipairs({ old, new }) do api.nvim_win_call(win, function() vim.cmd("diffthis") end) end
  vim.cmd("diffupdate")
  local p = ui.open(new, { windows = { old = old, new = new } }, { notes = { note(2, "Deletion", "old") } })
  T.eq({ "", "" }, api.nvim_buf_get_lines(p.buf, 0, -1, false))
  T.eq({ 1 }, p.rows[2])
  T.eq(summary("Deletion"), p.filler[2][-2])
  p:jump(1); T.eq(2, api.nvim_win_get_cursor(new)[1])
  key(p.buf, "K"); assert(api.nvim_win_is_valid(p.detail_win))
  T.eq(true, p.projection[2].filler)
  T.eq(false, vim.wo[p.win].diff); T.eq(false, vim.wo[p.win].scrollbind)
  p:close(); T.eq(true, vim.wo[old].diff); T.eq(true, vim.wo[new].diff)
  vim.cmd("diffoff!")
end)
T.test("source closure cleans pane and handlers", function()
  local win = setup({ "a", "b" })
  local p = ui.open(win, { windows = { buffer = win } }, { notes = { note(1) } })
  p:set(nil, "Pending · collection")
  local timer = p.timer
  api.nvim_win_close(win, true)
  assert(vim.wait(500, function() return p.closed end))
  T.eq(true, p.closed); T.eq(false, api.nvim_win_is_valid(p.win))
  T.eq(nil, p.timer); assert(timer:is_closing())
end)

T.test("whole logical lines retain independent wrap skipcol resize and off-screen notes", function()
  local source = { string.rep("x", 90), "second", "third" }
  for i = 4, 120 do source[i] = "line " .. i end
  local win = setup(source)
  vim.wo[win].wrap = true; vim.wo[win].smoothscroll = true
  local p = ui.open(win, { windows = { buffer = win } }, { notes = { note(1), note(2), note(3), note(40), note(43), note(46) } })
  api.nvim_win_set_width(win, 40); p:render()
  -- 90 columns at width 40 occupy three rows (no number/sign/fold columns).
  local logical = api.nvim_buf_get_lines(p.buf, 0, -1, false)
  T.eq(120, #logical)
  T.eq({ summary("Note 1"), summary("Note 2"), summary("Note 3") }, api.nvim_buf_get_lines(p.buf, 0, 3, false))
  T.eq(4, api.nvim_win_text_height(p.win, { start_row = 0, end_row = 1 }).all)
  T.eq(0, api.nvim_win_call(p.win, vim.fn.winsaveview).topfill)
  api.nvim_win_call(win, function() vim.fn.winrestview({ topline = 1, skipcol = 40, lnum = 1, col = 45 }) end)
  p:render(); T.eq(40, api.nvim_win_call(win, vim.fn.winsaveview).skipcol)
  T.eq(logical, api.nvim_buf_get_lines(p.buf, 0, -1, false))
  T.eq(0, api.nvim_win_call(p.win, vim.fn.winsaveview).topfill)
  api.nvim_win_set_width(win, 60)
  api.nvim_win_call(win, function() vim.fn.winrestview({ topline = 1, skipcol = 0, lnum = 1, col = 0 }) end)
  p:render(); T.eq(logical, api.nvim_buf_get_lines(p.buf, 0, -1, false))
  T.eq(3, api.nvim_win_text_height(p.win, { start_row = 0, end_row = 1 }).all)
  api.nvim_win_call(win, function() vim.fn.winrestview({ topline = 40, lnum = 40, col = 0 }) end)
  p:render()
  T.eq({ summary("Note 40"), "", "", summary("Note 43"), "", "", summary("Note 46") }, api.nvim_buf_get_lines(p.buf, 39, 46, false))
  T.eq(40, api.nvim_win_call(p.win, vim.fn.winsaveview).topline)
  local height = api.nvim_win_get_height(win)
  p.result.notes[#p.result.notes + 1] = note(40 + height - 1, "Bottom edge")
  p.result.notes[#p.result.notes + 1] = note(40 + height, "Not visible")
  p:render(); T.eq(summary("Bottom edge"), api.nvim_buf_get_lines(p.buf, 40 + height - 2, 40 + height - 1, false)[1])
  T.eq(summary("Not visible"), api.nvim_buf_get_lines(p.buf, 40 + height - 1, 40 + height, false)[1])
  p:close()
end)

T.test("pane wheel commands generic scrolling cursor navigation statuses and reopen cleanup", function()
  local lines = {}; for i = 1, 120 do lines[i] = "line " .. i end
  local win = setup(lines)
  local p = ui.open(win, { windows = { buffer = win } }, { notes = { note(4), note(20) } })
  api.nvim_set_current_win(p.win); api.nvim_win_set_cursor(p.win, { 4, 0 })
  api.nvim_exec_autocmds("CursorMoved", { buffer = p.buf })
  T.eq({ 4, 0 }, api.nvim_win_get_cursor(win))
  T.eq(1, api.nvim_win_call(win, vim.fn.winsaveview).topline)
  for _, mapping in ipairs(api.nvim_buf_get_keymap(p.buf, "n")) do
    if mapping.lhs == "<ScrollWheelDown>" then mapping.callback() end
  end
  T.eq(4, api.nvim_win_call(win, vim.fn.winsaveview).topline)
  T.eq(summary("Note 4"), api.nvim_buf_get_lines(p.buf, 3, 4, false)[1])
  T.eq(4, api.nvim_win_call(p.win, vim.fn.winsaveview).topline)
  for _, status in ipairs({ "Pending", "Failed", "Stale", "Cancelled" }) do
    p:set(nil, status); T.eq(nil, p.result); T.eq(status, vim.b[p.buf].explainr_status)
    assert(state(p):find(status, 1, true))
    T.eq(120, api.nvim_buf_line_count(p.buf))
  end
  local group, buf = p.group, p.buf
  p:close(); T.eq(false, api.nvim_buf_is_valid(buf)); T.eq(false, pcall(api.nvim_get_autocmds, { group = group }))
  local again = ui.open(win, { windows = { buffer = win } }, { notes = { note(20) } })
  again:close(); T.eq(true, api.nvim_win_is_valid(win)); T.eq(false, vim.wo[win].scrollbind)
end)

T.test("paired old59 new62 replacement and native diff scrolling stay isolated", function()
  local before, after = {}, {}
  for i = 1, 110 do before[i] = "context " .. i; after[i] = "context " .. i end
  before[59] = "old expression"
  table.insert(after, 59, "inserted a"); table.insert(after, 60, "inserted b"); table.insert(after, 61, "inserted c")
  after[62] = "new expression"
  local old = setup(before)
  vim.cmd("vsplit"); local new = api.nvim_get_current_win()
  local buf = api.nvim_create_buf(false, true); api.nvim_win_set_buf(new, buf)
  api.nvim_buf_set_lines(buf, 0, -1, false, after)
  for _, win in ipairs({ old, new }) do api.nvim_win_call(win, function() vim.cmd("diffthis"); vim.cmd("normal! zR") end) end
  vim.cmd("diffupdate")
  api.nvim_win_call(new, function() vim.fn.winrestview({ topline = 50, lnum = 50, col = 0 }); vim.cmd("syncbind") end)
  local paired = note(59, "Replacement", "old")
  paired.anchors[2] = { path = "test.lua", side = "new", start_line = 62, end_line = 62 }
  local p = ui.open(new, { windows = { old = old, new = new } }, { notes = { paired } })
  T.eq(summary("Replacement"), api.nvim_buf_get_lines(p.buf, 61, 62, false)[1])
  api.nvim_set_current_win(p.win)
  motion(p.win, "62G")
  T.eq(62, api.nvim_win_get_cursor(new)[1]); T.eq(59, api.nvim_win_get_cursor(old)[1])
  motion(p.win, "j"); T.eq(63, api.nvim_win_get_cursor(new)[1]); T.eq(60, api.nvim_win_get_cursor(old)[1])
  api.nvim_win_call(new, function() vim.fn.winrestview({ topline = 50, lnum = 50, col = 0 }); vim.cmd("syncbind") end)
  p:align()
  p:scroll(api.nvim_replace_termcodes("<C-e>", true, false, true))
  T.eq(51, api.nvim_win_call(new, vim.fn.winsaveview).topline)
  T.eq(51, api.nvim_win_call(old, vim.fn.winsaveview).topline)
  T.eq(false, vim.wo[p.win].diff); T.eq(false, vim.wo[p.win].scrollbind)
  p:close(); T.eq(true, vim.wo[new].scrollbind); T.eq(true, vim.wo[old].scrollbind)
  vim.cmd("diffoff!")
end)

T.test("opposite-side deletions follow native comparison rows despite wraps bars and stacked layout", function()
  for _, split in ipairs({ "vsplit", "belowright split" }) do
    local text = string.rep("x", 90)
    local old = setup({ text, "deleted", "last" })
    vim.cmd(split); local new = api.nvim_get_current_win()
    local buf = api.nvim_create_buf(false, true); api.nvim_win_set_buf(new, buf)
    api.nvim_buf_set_lines(buf, 0, -1, false, { text, "last" })
    for _, win in ipairs({ old, new }) do
      api.nvim_win_call(win, function() vim.cmd("diffthis"); vim.cmd("normal! zR") end)
      vim.wo[win].wrap = true
    end
    vim.wo[old].winbar = "Old side only"; vim.wo[new].winbar = ""
    vim.cmd("diffupdate")
    local p = ui.open(new, { windows = { old = old, new = new } }, { notes = { note(2, "Deleted old code", "old") } })
    api.nvim_win_set_width(new, 40); p:render()
    T.eq({ "", "" }, api.nvim_buf_get_lines(p.buf, 0, -1, false))
    T.eq(summary("Deleted old code"), p.filler[2][-1])
    T.eq(5, api.nvim_win_text_height(p.win, { start_row = 0, end_row = 1 }).all)
    T.eq(3, api.nvim_win_text_height(p.win, { start_row = 1, end_row = 1 }).fill)
    T.eq(true, p.projection[4].filler)
    api.nvim_win_call(new, function() vim.fn.winrestview({ topline = 2, topfill = 1, lnum = 2, col = 0 }) end)
    p:render(); T.eq(1, api.nvim_win_call(p.win, vim.fn.winsaveview).topfill)
    T.eq(2, api.nvim_win_get_cursor(p.win)[1])
    p:close(); vim.cmd("diffoff!")
  end
end)

T.test("external global statusline survives focus renders and all pane-local states", function()
  local win = setup({ "one", "two", "three" })
  local laststatus, global = vim.o.laststatus, vim.go.statusline
  vim.o.laststatus = 3; vim.go.statusline = "EXTERNAL GLOBAL %= editor bar"
  vim.wo[win].statusline = "EXTERNAL SOURCE"
  local result = { notes = { note(2) } }
  local p = ui.open(win, { windows = { buffer = win } }, result)
  T.eq("EXTERNAL GLOBAL %= editor bar", vim.wo[p.win].statusline)
  vim.wo[p.win].statusline = "EXTERNAL PANE"
  local projection = vim.deepcopy(p.projection)
  for _, status in ipairs({ "Pending · refresh", "Failed · exit 1", "Stale", "Cancelled", "Ready" }) do
    p:set(result, status)
    local tick = api.nvim_buf_get_changedtick(p.buf)
    for _, focus in ipairs({ p.win, win, p.win }) do
      api.nvim_set_current_win(focus); p:render()
      T.eq(tick, api.nvim_buf_get_changedtick(p.buf))
      T.eq("EXTERNAL PANE", vim.wo[p.win].statusline)
      T.eq("EXTERNAL SOURCE", vim.wo[win].statusline)
      T.eq("EXTERNAL GLOBAL %= editor bar", vim.go.statusline); T.eq(3, vim.o.laststatus)
      T.eq(1, vim.fn.getwininfo(p.win)[1].winbar); T.eq(" ", vim.wo[win].winbar)
      T.eq(projection, p.projection); T.eq({ 1 }, p.rows[2])
      T.eq(summary("Note 2"), api.nvim_buf_get_lines(p.buf, 1, 2, false)[1])
      T.eq(status, vim.b[p.buf].explainr_status)
      assert(state(p):find(status:match("^%w+"), 1, true), state(p))
    end
  end
  p:close(); vim.o.laststatus = laststatus; vim.go.statusline = global; vim.wo[win].statusline = ""
end)

T.test("semantic fallback stays single-row and detail omits citation sections and cleans buffers", function()
  local win = setup({ "one", "two", "three" })
  local n = note(1, "Guard\nmissing\tuser")
  n.intent_basis = "documented"
  n.anchors[1].side = "old"; n.anchors[2] = { path = "src/test.lua", side = "new", start_line = 2, end_line = 3 }
  n.evidence = { { path = "docs/decision.md", side = "new", start_line = 8, end_line = 12 } }
  n.detail = string.rep("Reason with **meaning**.\n\n", 40)
  local p = ui.open(win, { windows = { old = win } }, { notes = { n } })
  T.eq("▎ D Guard missing user [+]", api.nvim_buf_get_lines(p.buf, 0, 1, false)[1])
  local ns = api.nvim_get_namespaces()["explainr.ui"]
  local marks = api.nvim_buf_get_extmarks(p.buf, ns, 0, -1, { details = true })
  T.eq("ExplainrDocumented", marks[1][4].hl_group)
  T.eq(true, api.nvim_get_hl(0, { name = "ExplainrDetailCue", link = false }).nocombine)
  for _, m in ipairs(marks) do assert(not m[4].virt_lines and not m[4].conceal_lines) end
  p:detail()
  local detail_win, detail = p.detail_win, api.nvim_win_get_buf(p.detail_win)
  T.eq("markdown", vim.bo[detail].filetype)
  local text = table.concat(api.nvim_buf_get_lines(detail, 0, -1, false), "\n")
  for _, expected in ipairs({ "▎ D Guard missing user", "**Intent basis:** documented", n.detail }) do
    assert(text:find(expected, 1, true), expected)
  end
  for _, removed in ipairs({ "## Anchors", "## Evidence", "src/test.lua", "docs/decision.md", "No evidence cited." }) do
    assert(not text:find(removed, 1, true), removed)
  end
  T.eq("docs/decision.md", p.result.notes[1].evidence[1].path)
  T.eq(2, #p.result.notes[1].anchors)
  api.nvim_win_call(detail_win, function() vim.cmd.normal({ p.detail_layout.last .. "G", bang = true }) end)
  assert(api.nvim_win_call(detail_win, vim.fn.winsaveview).topline > 1)
  for _, mapping in ipairs(api.nvim_buf_get_keymap(detail, "n")) do if mapping.lhs == "q" then mapping.callback() end end
  T.eq(true, api.nvim_win_is_valid(detail_win)); T.eq(false, api.nvim_buf_is_valid(detail)); T.eq(p.win, api.nvim_get_current_win())
  T.eq(p.buf, api.nvim_win_get_buf(p.win)); T.eq(nil, p.detail_win)
  p:detail(); local second = p.detail_buf
  p:set(nil, "Failed"); T.eq(false, api.nvim_buf_is_valid(second)); T.eq(true, api.nvim_win_is_valid(p.win))
  p:close()
end)

T.test("public optional renderer is seeded before FileType and rerenders summaries and detail", function()
  local win = setup({ "one", "two", "three" })
  local previous, cache, calls = package.loaded["render-markdown"], {}, {}
  local group = api.nvim_create_augroup("ExplainrRendererTest", { clear = true })
  package.loaded["render-markdown"] = {
    setup = function() error("must not reset user configuration") end,
    render = function(ctx)
      cache[ctx.buf] = cache[ctx.buf] or ctx.config
      calls[#calls + 1] = { buf = ctx.buf, win = ctx.win }
      assert(ctx.config == cache[ctx.buf], "config must be stable for the buffer lifecycle")
    end,
  }
  api.nvim_create_autocmd("FileType", { group = group, pattern = { "explainr", "markdown" }, callback = function(event)
    assert(cache[event.buf], "automatic FileType attachment must not win the config cache")
  end })
  local ok, err = xpcall(function()
    local p = ui.open(win, { windows = { buffer = win } }, { notes = { note(1, "**Bold** `code`") } })
    local config = cache[p.buf]
    T.eq(false, config.anti_conceal.enabled); T.eq(false, config.win_options.wrap.rendered)
    T.eq(false, config.win_options.wrap.default); T.eq(0, config.win_options.conceallevel.rendered)
    for _, key in ipairs({ "heading", "code", "pipe_table", "document", "latex", "paragraph", "dash", "bullet",
      "checkbox", "quote", "sign", "indent", "html", "yaml", "link" }) do T.eq(false, config[key].enabled) end
    T.eq("markdown", vim.treesitter.language.get_lang("explainr"))
    local count = #calls; p:render(); assert(#calls > count)
    T.eq(p.win, calls[#calls].win); T.eq({ 1 }, p.rows[1])
    p:detail(); local detail = api.nvim_win_get_buf(p.detail_win)
    T.eq(true, cache[detail].win_options.wrap.rendered); T.eq({ "▎ " }, cache[detail].heading.icons)
    T.eq({ "-" }, cache[detail].bullet.icons)
    count = #calls
    api.nvim_exec_autocmds("WinScrolled", { buffer = detail })
    assert(#calls > count); T.eq(p.detail_win, calls[#calls].win)
    p:close(); T.eq(false, api.nvim_buf_is_valid(detail))
  end, debug.traceback)
  api.nvim_del_augroup_by_id(group); package.loaded["render-markdown"] = previous
  assert(ok, err)
end)

T.test("missing renderer API or parser leaves semantic native fallback usable", function()
  local previous, start = package.loaded["render-markdown"], vim.treesitter.start
  local ok, err = xpcall(function()
    vim.treesitter.start = function() error("parser unavailable") end
    for _, renderer in ipairs({ {}, { render = function() error("uninitialized optional renderer") end } }) do
      package.loaded["render-markdown"] = renderer
      local win = setup({ "one", "two" })
      local p = ui.open(win, { windows = { buffer = win } }, { notes = { note(1) } })
      T.eq(summary("Note 1"), api.nvim_buf_get_lines(p.buf, 0, 1, false)[1])
      assert(#api.nvim_buf_get_extmarks(p.buf, api.nvim_get_namespaces()["explainr.ui"], 0, -1, {}) > 0)
      p:detail(); T.eq("markdown", vim.bo[api.nvim_win_get_buf(p.detail_win)].filetype)
      p:close()
    end
  end, debug.traceback)
  package.loaded["render-markdown"], vim.treesitter.start = previous, start
  assert(ok, err)
end)

T.test("full note viewport uses a separate state header without moving any anchors", function()
  local lines, notes = {}, {}
  for row = 1, 60 do lines[row] = "line " .. row; notes[row] = note(row) end
  local win = setup(lines)
  local result = { notes = notes }
  local p = ui.open(win, { windows = { buffer = win } }, result)
  local rows, projection = vim.deepcopy(p.rows), vim.deepcopy(p.projection)
  p:set(result, "Stale")
  T.eq(rows, p.rows); T.eq(projection, p.projection)
  T.eq({}, marks(p, "explainr.state"))
  assert(state(p):find("Stale", 1, true))
  assert(state(p):find("? unknown", 1, true)); p:close()
end)

T.test("blank and pending lines synchronize both directions beyond viewport without stealing focus", function()
  local lines = {}; for i = 1, 160 do lines[i] = i % 2 == 0 and "" or "a longer source line" end
  local source, source_buf = setup(lines)
  local options = {}
  for _, name in ipairs({ "wrap", "cursorbind", "scrollbind", "foldenable", "scrolloff", "statusline" }) do
    options[name] = vim.wo[source][name]
  end
  local p = ui.open(source, nil, nil)
  p:set(nil, "Pending · collecting comparison")
  motion(p.win, "100G")
  T.eq({ 100, 0 }, api.nvim_win_get_cursor(source)); T.eq(p.win, api.nvim_get_current_win())
  motion(p.win, "31j"); T.eq(131, api.nvim_win_get_cursor(source)[1])
  motion(p.win, "G"); T.eq(160, api.nvim_win_get_cursor(source)[1])
  motion(p.win, "gg"); T.eq(1, api.nvim_win_get_cursor(source)[1])
  api.nvim_set_current_win(source); api.nvim_win_set_cursor(source, { 99, 12 })
  api.nvim_exec_autocmds("CursorMoved", { buffer = source_buf })
  T.eq({ 99, 12 }, api.nvim_win_get_cursor(source)); T.eq({ 99, 0 }, api.nvim_win_get_cursor(p.win))
  T.eq(source, api.nvim_get_current_win())
  -- Note-driven movement clamps an existing source column on an empty line.
  motion(p.win, "j"); T.eq({ 100, 0 }, api.nvim_win_get_cursor(source))
  p:set({ notes = { note(140) } }, "Ready")
  motion(source, "101G"); T.eq(101, api.nvim_win_get_cursor(p.win)[1])
  motion(p.win, "139G"); T.eq(139, api.nvim_win_get_cursor(source)[1])
  for name, value in pairs(options) do T.eq(value, vim.wo[source][name]) end
  T.eq(160, api.nvim_buf_line_count(p.buf)); p:close()
end)

T.test("counted n p stop at explanation edges and K Enter only use existing details", function()
  local lines = {}; for i = 1, 150 do lines[i] = "line " .. i end
  local source = setup(lines)
  local result = { notes = { note(5), note(40), note(100) } }
  local p = ui.open(source, { windows = { buffer = source } }, result)
  api.nvim_set_current_win(p.win)
  vim.cmd.normal({ "4n", bang = false }); T.eq(100, api.nvim_win_get_cursor(p.win)[1])
  local view = api.nvim_win_call(source, vim.fn.winsaveview)
  key(p.buf, "n"); T.eq(view, api.nvim_win_call(source, vim.fn.winsaveview))
  vim.cmd.normal({ "5p", bang = false }); T.eq(5, api.nvim_win_get_cursor(p.win)[1])
  view = api.nvim_win_call(source, vim.fn.winsaveview)
  key(p.buf, "p"); T.eq(view, api.nvim_win_call(source, vim.fn.winsaveview))
  vim.cmd.normal({ "2n", bang = false }); T.eq(100, api.nvim_win_get_cursor(source)[1])
  motion(p.win, "G"); key(p.buf, "n"); T.eq(150, api.nvim_win_get_cursor(source)[1])
  motion(p.win, "gg"); key(p.buf, "p"); T.eq(1, api.nvim_win_get_cursor(source)[1])
  key(p.buf, "n"); T.eq(5, api.nvim_win_get_cursor(source)[1])
  local tick = api.nvim_buf_get_changedtick(p.buf)
  for _, lhs in ipairs({ "K", "<CR>" }) do
    key(p.buf, lhs)
    local detail = api.nvim_win_get_buf(p.detail_win)
    local text = table.concat(api.nvim_buf_get_lines(detail, 0, -1, false), "\n")
    assert(text:find("Full explanation without another request.", 1, true))
    T.eq(result, p.result); T.eq(tick, api.nvim_buf_get_changedtick(p.buf))
    key(detail, "q")
  end
  p:set(nil, "Pending"); key(p.buf, "n"); T.eq(5, api.nvim_win_get_cursor(source)[1])
  key(p.buf, "<Esc>"); T.eq(true, p.closed)
end)

T.test("n p and Shift n center destinations and clamp counts at both edges in overview and expanded detail", function()
  local lines = {}; for row = 1, 300 do lines[row] = "line " .. row end
  local source = setup(lines)
  local p = ui.open(source, { windows = { buffer = source } }, { notes = { note(40), note(45), note(160), note(250) } })
  for _, expanded in ipairs({ false, true }) do
    motion(p.win, "40G0")
    if expanded then key(p.buf, "K") end
    local detail = p.detail_buf
    for _, step in ipairs({ { "n", 45 }, { "p", 40 }, { "2p", 40 }, { "9n", 250 }, { "n", 250 },
      { "N", 160 }, { "2N", 40 }, { "N", 40 }, { "9n", 250 }, { "9N", 40 },
      { "9n", 250 }, { "2p", 45 }, { "9p", 40 }, { "p", 40 }, { "n", 45 } }) do
      api.nvim_set_current_win(p.win)
      api.nvim_feedkeys(step[1], "xt", false); vim.cmd("redraw!")
      api.nvim_exec_autocmds("SafeState", {}); vim.wait(20, function() return false end); vim.cmd("redraw!")
      local view = api.nvim_win_call(source, vim.fn.winsaveview)
      T.eq(step[2], view.lnum)
      T.eq(step[2] - math.floor((api.nvim_win_get_height(source) - 1) / 2), view.topline)
      T.eq(vim.fn.screenpos(source, step[2], 1).row,
        expanded and detail_screen(p, 1) or vim.fn.screenpos(p.win, step[2], 1).row)
      T.eq(p.win, api.nvim_get_current_win())
      if expanded then T.eq(detail, p.detail_buf); T.eq(step[2], p.overview.view.lnum) end
    end
    if expanded then
      key(p.detail_buf, "<CR>")
      T.eq(45, api.nvim_win_get_cursor(p.win)[1])
      T.eq(32, api.nvim_win_call(p.win, vim.fn.winsaveview).topline)
    end
  end
  p:close()
end)

T.test("pending spinner ticks only decorations and stops every terminal phase and close", function()
  local source = setup({ "a", "b", "c" })
  local p = ui.open(source, { windows = { buffer = source } }, nil)
  local group = api.nvim_create_augroup("ExplainrSpinnerTest", { clear = true })
  local changed, renders, heights = 0, 0, 0
  api.nvim_create_autocmd("TextChanged", { group = group, buffer = p.buf, callback = function() changed = changed + 1 end })
  local render, height = p.render, api.nvim_win_text_height
  p.render = function(self) renders = renders + 1; return render(self) end
  api.nvim_win_text_height = function(...) heights = heights + 1; return height(...) end
  local ok, err = xpcall(function()
    vim.wo[source].statusline = "SOURCE BAR"; vim.wo[p.win].statusline = "NOTES BAR"
    for _, terminal in ipairs({ "Ready", "Failed · exit 1", "Stale", "Cancelled" }) do
      p:set(nil, "Pending · current phase")
      vim.wait(20, function() return false end) -- drain structural callbacks
      local first, tick, before, scans = state(p), api.nvim_buf_get_changedtick(p.buf), renders, heights
      assert(vim.wait(500, function() return state(p) ~= first end), "spinner never animated")
      T.eq("Pending · current phase", p.status); T.eq(p.status, vim.b[p.buf].explainr_status)
      assert(state(p):find("~ inferred", 1, true))
      T.eq(tick, api.nvim_buf_get_changedtick(p.buf)); T.eq(before, renders); T.eq(scans, heights)
      T.eq("SOURCE BAR", vim.wo[source].statusline); T.eq("NOTES BAR", vim.wo[p.win].statusline)
      local timer = p.timer
      p:set(nil, terminal); T.eq(nil, p.timer); assert(timer:is_closing())
      local frame = p.frame
      vim.wait(130, function() return false end); T.eq(frame, p.frame)
    end
    vim.wo[source].foldmethod = "manual"; vim.wo[source].foldenable = true
    api.nvim_win_call(source, function() vim.cmd("1,3fold") end)
    p:set(nil, "Pending · folded phase")
    local first_fold, tick = state(p), api.nvim_buf_get_changedtick(p.buf)
    assert(first_fold:find("Pending", 1, true)); T.eq("Pending · folded phase", p.status)
    assert(vim.wait(500, function() return state(p) ~= first_fold end), "folded spinner never animated")
    T.eq(tick, api.nvim_buf_get_changedtick(p.buf))
    -- Winbar animation is also pane-owned, matched to the source header.
    vim.wo[source].winbar = "Source"; p:set(nil, "Pending · winbar phase")
    local first = vim.wo[p.win].winbar
    assert(vim.wait(500, function() return vim.wo[p.win].winbar ~= first end))
    local timer, frame = p.timer, p.frame
    p:close(); T.eq(nil, p.timer); assert(timer:is_closing())
    p:set(nil, "Pending · late result"); T.eq(nil, p.timer)
    vim.wait(150, function() return false end); T.eq(frame, p.frame); T.eq(0, changed)
  end, debug.traceback)
  api.nvim_win_text_height = height
  api.nvim_del_augroup_by_id(group)
  if not p.closed then p:close() end
  assert(ok, err)
end)

T.test("focused context remains visible after scroll but is omitted from detail", function()
  local lines = {}; for i = 1, 120 do lines[i] = "line " .. i end
  local source = setup(lines)
  vim.o.columns = 240
  local snapshot = { windows = { buffer = source }, context = { strategy = "focused", radius = 12,
    omitted_files = { "docs/a.md", "src/b.lua" } } }
  local p = ui.open(source, snapshot, { notes = { note(100) } })
  assert(state(p):find("Focused ±12 · 2 files omitted", 1, true))
  motion(p.win, "100G"); assert(state(p):find("Focused", 1, true))
  T.eq({}, marks(p, "explainr.state"))
  key(p.buf, "K")
  local text = table.concat(api.nvim_buf_get_lines(api.nvim_win_get_buf(p.detail_win), 0, -1, false), "\n")
  assert(not text:find("**Context:**", 1, true))
  assert(not text:find("Focused", 1, true))
  assert(not text:find("omitted review files are not available to the model", 1, true))
  key(api.nvim_win_get_buf(p.detail_win), "q")
  snapshot.context.strategy = "full"; p:render()
  assert(not state(p):find("Focused", 1, true)); assert(state(p):find("D documented", 1, true))
  p:detail()
  text = table.concat(api.nvim_buf_get_lines(api.nvim_win_get_buf(p.detail_win), 0, -1, false), "\n")
  assert(not text:find("**Context:**", 1, true)); p:close()
end)

T.test("cursor synchronization bounds native scans to viewport and never rebuilds content", function()
  local lines = {}; for i = 1, 6000 do lines[i] = "line " .. i end
  local source = setup(lines)
  local p = ui.open(source, { windows = { buffer = source } }, { notes = { note(5000) } })
  local height, fill, fold = api.nvim_win_text_height, vim.fn.diff_filler, vim.fn.foldclosedend
  local calls, fillers, folds = 0, 0, 0
  api.nvim_win_text_height = function(...) calls = calls + 1; return height(...) end
  vim.fn.diff_filler = function(...) fillers = fillers + 1; return fill(...) end
  vim.fn.foldclosedend = function(...) folds = folds + 1; return fold(...) end
  local ok, err = xpcall(function()
    local tick = api.nvim_buf_get_changedtick(p.buf)
    for _, target in ipairs({ 30, 2999, 5001, 6000, 1 }) do
      motion(p.win, target .. "G"); T.eq(target, api.nvim_win_get_cursor(source)[1])
    end
    T.eq(tick, api.nvim_buf_get_changedtick(p.buf)); T.eq(0, fillers)
    assert(calls < 1000 and folds < 300, "cursor events scanned whole source")
  end, debug.traceback)
  api.nvim_win_text_height, vim.fn.diff_filler, vim.fn.foldclosedend = height, fill, fold
  p:close(); assert(ok, err)
end)

T.test("trailing old deletions render in EOF filler and share the final logical boundary", function()
  local old = setup({ "kept", "removed", "also removed" })
  vim.cmd("vsplit"); local new = api.nvim_get_current_win()
  local buf = api.nvim_create_buf(false, true); api.nvim_win_set_buf(new, buf)
  api.nvim_buf_set_lines(buf, 0, -1, false, { "kept" })
  for _, win in ipairs({ old, new }) do api.nvim_win_call(win, function() vim.cmd("diffthis | normal! zR") end) end
  vim.cmd("diffupdate")
  local p = ui.open(new, { windows = { old = old, new = new } },
    { notes = { note(2, "Trailing deletion", "old"), note(3, "Second deletion", "old") } })
  T.eq(1, api.nvim_buf_line_count(p.buf)); T.eq({ 1, 2 }, p.rows[1])
  T.eq(summary("Trailing deletion"), p.eof[1]); T.eq(summary("Second deletion"), p.eof[2])
  T.eq(true, p.projection[2].eof)
  local found = false
  for _, m in ipairs(marks(p, "explainr.geometry")) do
    if m[4].virt_lines and not m[4].virt_lines_above then
      T.eq("[old:2] ", m[4].virt_lines[1][1][1])
      T.eq(summary("Trailing deletion"), m[4].virt_lines[1][2][1]); found = true
    end
  end
  assert(found); p:jump(1, 3); T.eq(1, api.nvim_win_get_cursor(new)[1])
  key(p.buf, "<CR>")
  local detail = table.concat(api.nvim_buf_get_lines(api.nvim_win_get_buf(p.detail_win), 0, -1, false), "\n")
  assert(detail:find("Trailing deletion", 1, true) and detail:find("Second deletion", 1, true))
  p:close(); vim.cmd("diffoff!")
end)

T.test("idle fold changes preserve source columns and notes logical cursor and navigation", function()
  local lines = {}; for i = 1, 120 do lines[i] = "source line " .. i end
  local source = setup(lines)
  vim.wo[source].foldmethod = "manual"; vim.wo[source].foldenable = true
  local p = ui.open(source, { windows = { buffer = source } }, { notes = { note(3), note(6), note(100) } })
  api.nvim_set_current_win(source); api.nvim_win_set_cursor(source, { 2, 5 })
  api.nvim_exec_autocmds("CursorMoved", { buffer = api.nvim_win_get_buf(source) })
  api.nvim_win_call(source, function() vim.cmd("2,8fold") end)
  api.nvim_exec_autocmds("SafeState", {})
  T.eq({ 2, 5 }, api.nvim_win_get_cursor(source)); T.eq({ 2, 0 }, api.nvim_win_get_cursor(p.win))
  T.eq(8, api.nvim_win_call(p.win, function() return vim.fn.foldclosedend(2) end))
  motion(p.win, "gg"); key(p.buf, "n"); T.eq(2, api.nvim_win_get_cursor(source)[1])
  key(p.buf, "n"); T.eq(100, api.nvim_win_get_cursor(source)[1])
  key(p.buf, "p"); T.eq(2, api.nvim_win_get_cursor(source)[1])
  api.nvim_set_current_win(source); vim.cmd("normal! zo")
  api.nvim_exec_autocmds("SafeState", {})
  T.eq(-1, api.nvim_win_call(p.win, function() return vim.fn.foldclosedend(2) end))
  motion(p.win, "j"); T.eq(3, api.nvim_win_get_cursor(source)[1]); p:close()
end)

T.test("idle folding follows the interacted diff side without cursor or scroll events", function()
  local lines = {}; for row = 1, 50 do lines[row] = "context " .. row end
  local old = setup(lines)
  vim.cmd("belowright vsplit")
  local new = api.nvim_get_current_win()
  api.nvim_win_set_buf(new, api.nvim_create_buf(false, true))
  local after = vim.deepcopy(lines); table.insert(after, 12, "inserted")
  api.nvim_buf_set_lines(0, 0, -1, false, after)
  for _, source in ipairs({ old, new }) do
    api.nvim_win_call(source, function()
      vim.cmd("diffthis | normal! zR")
      vim.wo.foldmethod = "manual"; vim.wo.foldenable = true
      api.nvim_win_set_cursor(source, { 2, 4 })
    end)
  end
  vim.cmd("diffupdate")
  local result = { notes = { note(12, "Inserted row", "new"), note(20, "Later row", "old") } }
  local p = ui.open(new, { windows = { old = old, new = new } }, result)
  for _, source in ipairs({ old, new }) do
    api.nvim_set_current_win(source)
    api.nvim_win_set_cursor(source, { 2, 4 })
    vim.cmd("2,8fold") -- Cursor and topline do not move; no CursorMoved/WinScrolled.
    api.nvim_exec_autocmds("SafeState", {})
    T.eq(source, p.source)
    T.eq({ 2, 4 }, api.nvim_win_get_cursor(source))
    T.eq(8, api.nvim_win_call(p.win, function() return vim.fn.foldclosedend(2) end))
    vim.cmd("normal! zo")
    api.nvim_exec_autocmds("SafeState", {})
    -- Diff folding may leave a nested counterpart fold closed after one zo.
    T.eq(api.nvim_win_call(source, function() return vim.fn.foldclosedend(2) end),
      api.nvim_win_call(p.win, function() return vim.fn.foldclosedend(2) end))
    vim.cmd("redraw!")
    for _, item in ipairs(p.projection) do
      if not item.empty and not item.filler then
        T.eq(vim.fn.screenpos(source, item.line, 1).row, vim.fn.screenpos(p.win, item.line, 1).row)
      end
    end
  end
  T.eq(result, p.result); p:close(); vim.cmd("diffoff!")
end)

T.test("opening a cached fold above the viewport does not keep explanations trapped inside it", function()
  local lines = {}; for row = 1, 120 do lines[row] = "context " .. row end
  local source = setup(lines)
  vim.wo[source].foldmethod = "manual"; vim.wo[source].foldenable = true
  api.nvim_win_call(source, function() vim.cmd("90,110fold | 2,80fold | normal! gg") end)
  local original = { notes = { note(42, "Visible anchor after unfolding"), note(85, "Later anchor") } }
  local p = ui.open(source, { windows = { buffer = source } }, original)
  T.eq(80, p.folds[2]); T.eq(110, p.folds[90])
  api.nvim_set_current_win(source)
  vim.cmd("normal! 2Gzo")
  vim.fn.winrestview({ topline = 40, lnum = 42, col = 3 })
  api.nvim_exec_autocmds("SafeState", {})
  T.eq(nil, p.folds[2]); T.eq(110, p.folds[90]) -- Truly closed off-screen folds remain cached.
  T.eq(-1, api.nvim_win_call(p.win, function() return vim.fn.foldclosed(42) end))
  T.eq({ 42, 3 }, api.nvim_win_get_cursor(source))
  T.eq({ 42, 0 }, api.nvim_win_get_cursor(p.win))
  vim.cmd("redraw!")
  T.eq(vim.fn.screenpos(source, 42, 1).row, vim.fn.screenpos(p.win, 42, 1).row)
  T.eq(original, p.result); p:close()
end)

T.test("screen-filling wraps use bounded virtual geometry and retain a reachable logical cursor", function()
  local source = setup({ string.rep("x", 6000), "after wrap" })
  vim.wo[source].wrap = true; vim.wo[source].smoothscroll = true
  local p = ui.open(source, { windows = { buffer = source } }, { notes = { note(1), note(2) } })
  local height = vim.fn.getwininfo(p.win)[1].height
  T.eq(height + 1, api.nvim_win_text_height(p.win, { start_row = 0, end_row = 1 }).all)
  T.eq(0, api.nvim_win_call(p.win, vim.fn.winsaveview).topfill)
  T.eq(2, api.nvim_buf_line_count(p.buf))
  api.nvim_win_call(source, function() vim.fn.winrestview({ topline = 1, skipcol = 600, lnum = 1, col = 600 }) end)
  p:align()
  T.eq({ 1, 600 }, api.nvim_win_get_cursor(source)); T.eq({ 1, 0 }, api.nvim_win_get_cursor(p.win))
  local rows = marks(p, "explainr.geometry")
  for _, m in ipairs(rows) do
    if m[4].virt_lines then T.eq(height - 1, #m[4].virt_lines); T.eq("", m[4].virt_lines[1][1][1]) end
  end
  motion(p.win, "j"); T.eq(2, api.nvim_win_get_cursor(source)[1])
  T.eq(summary("Note 2"), api.nvim_buf_get_lines(p.buf, 1, 2, false)[1]); p:close()
end)

T.test("wrapped source cursor matches notes on each physical segment and n p reveal summary start", function()
  local source = setup({ string.rep("x", 180), "after", string.rep("y", 180) })
  vim.wo[source].wrap = true; vim.wo[source].smoothscroll = true
  local p = ui.open(source, { windows = { buffer = source } }, { notes = { note(1), note(3) } })
  vim.wo[p.win].cursorline = true
  api.nvim_win_set_width(source, 40); p:render()
  for _, column in ipairs({ 0, 39, 40, 75, 119, 120 }) do
    api.nvim_win_set_cursor(source, { 1, column }); p:sync(source)
    local info = vim.fn.getwininfo(source)[1]
    local expected_row = info.winrow + info.winbar + math.floor(column / 40)
    T.eq(expected_row, vim.fn.screenpos(source, 1, column + 1).row)
    T.eq(expected_row, vim.fn.screenpos(p.win, 1, 1).row)
    T.eq({ 1, column }, api.nvim_win_get_cursor(source))
    if column >= 40 then
      local overlay = false
      for _, m in ipairs(marks(p, "explainr.geometry")) do
        if m[2] == 0 and m[4].virt_text then T.eq("CursorLine", m[4].virt_text[1][2]); overlay = true end
      end
      assert(overlay, "wrapped cursor row was not highlighted")
    end
  end
  key(p.buf, "n"); T.eq({ 3, 0 }, api.nvim_win_get_cursor(source))
  T.eq(vim.fn.screenpos(source, 3, 1).row, vim.fn.screenpos(p.win, 3, 1).row)
  key(p.buf, "p"); T.eq({ 1, 0 }, api.nvim_win_get_cursor(source))
  p:close()
end)

T.test("opening from old puts the pane beyond both horizontal and stacked sources", function()
  for _, split in ipairs({ "belowright vsplit", "belowright split" }) do
    local old = setup({ "one", "two", "three" })
    vim.cmd(split); local new = api.nvim_get_current_win()
    local buf = api.nvim_create_buf(false, true); api.nvim_win_set_buf(new, buf)
    api.nvim_buf_set_lines(buf, 0, -1, false, { "one", "changed", "three" })
    for _, candidate in ipairs({ old, new }) do
      api.nvim_win_call(candidate, function() vim.cmd("diffthis | normal! zR") end)
    end
    api.nvim_set_current_win(old)
    local p = ui.open(old, { windows = { old = old, new = new } }, { notes = { note(2, nil, "old") } })
    local col = api.nvim_win_get_position(p.win)[2]
    for _, candidate in ipairs({ old, new }) do
      assert(api.nvim_win_get_position(candidate)[2] + api.nvim_win_get_width(candidate) <= col)
      T.eq(true, vim.wo[candidate].diff); T.eq(true, vim.wo[candidate].scrollbind)
    end
    T.eq(old, api.nvim_get_current_win()); T.eq(0, api.nvim_win_get_position(p.win)[1])
    p:close(); vim.cmd("diffoff!")
  end
end)

T.test("native cursor and viewport actions synchronize source and overview without mappings", function()
  local lines = {}; for row = 1, 240 do lines[row] = "line " .. row end
  local source = setup(lines)
  local p = ui.open(source, { windows = { buffer = source } }, { notes = { note(90), note(137) } })
  local tick = api.nvim_buf_get_changedtick(p.buf)
  local scroll = vim.wo[source].scroll
  for _, driver in ipairs({ p.win, source }) do
    for _, action in ipairs({ "90G0", "zz", "zt", "zb", "z+", "z-", "10j", "5k", "<Down>", "<Up>",
      "H", "M", "L", "search", "3<C-d>", "5<C-u>", "ma", "20j", "`a", "gg", "G" }) do
      if action == "search" then action = driver == source and "/line 137<CR>" or "/Note 137<CR>" end
      api.nvim_set_current_win(driver)
      local before = api.nvim_win_call(driver, vim.fn.winsaveview)
      api.nvim_feedkeys(api.nvim_replace_termcodes(action, true, false, true), "xt", false)
      vim.cmd("redraw!")
      api.nvim_exec_autocmds("SafeState", {})
      vim.wait(20, function() return false end)
      local code = api.nvim_win_call(source, vim.fn.winsaveview)
      local notes = api.nvim_win_call(p.win, vim.fn.winsaveview)
      T.eq({ driver, action, code.topline, code.topfill, code.lnum },
        { driver, action, notes.topline, notes.topfill, notes.lnum })
      local height = vim.fn.getwininfo(driver)[1].height
      local offset = ({ zz = math.floor((height - 1) / 2), zt = 0, zb = height - 1 })[action]
      if offset then T.eq({ action, notes.lnum - offset }, { action, notes.topline }) end
      local delta = ({ ["3<C-d>"] = 3, ["5<C-u>"] = -5 })[action]
      if delta then T.eq({ action, before.topline + delta }, { action, notes.topline }) end
      T.eq(driver, api.nvim_get_current_win())
      T.eq(tick, api.nvim_buf_get_changedtick(p.buf))
    end
  end
  for _, mapping in ipairs(api.nvim_buf_get_keymap(p.buf, "n")) do
    assert(mapping.lhs ~= "zz" and mapping.lhs ~= "zt" and mapping.lhs ~= "zb")
  end
  vim.wo[source].scroll = scroll
  p:close()
end)

T.test("native viewport positioning retains wraps folds and both diff sides", function()
  local lines = {}; for row = 1, 160 do lines[row] = "line " .. row end
  lines[70] = string.rep("wrapped ", 35)
  local old = setup(lines)
  vim.cmd("belowright vsplit")
  local new, buf = api.nvim_get_current_win(), api.nvim_create_buf(false, true)
  api.nvim_win_set_buf(new, buf)
  local after = vim.deepcopy(lines); table.insert(after, 35, "addition"); table.insert(after, 36, "another addition")
  api.nvim_buf_set_lines(buf, 0, -1, false, after)
  for _, win in ipairs({ old, new }) do
    api.nvim_win_call(win, function()
      vim.cmd("diffthis | normal! zR")
      vim.wo.wrap, vim.wo.smoothscroll = true, true
      vim.wo.foldmethod, vim.wo.foldenable = "manual", true
      vim.cmd("50,55fold")
    end)
  end
  vim.cmd("diffupdate")
  local p = ui.open(new, { windows = { old = old, new = new } }, { notes = { note(72, "Wrapped", "new") } })
  for _, driver in ipairs({ old, new, p.win }) do
    for _, action in ipairs({ "72G0", "zz", "zt", "zb", "60G0", "zz", "zt", "zb" }) do
      api.nvim_set_current_win(driver)
      api.nvim_feedkeys(action, "xt", false); vim.cmd("redraw!")
      api.nvim_exec_autocmds("SafeState", {}); vim.wait(20, function() return false end)
      vim.cmd("redraw!") -- screenpos observes the newly synchronized decoration grid.
      local line = api.nvim_win_get_cursor(p.source)[1]
      T.eq(line, api.nvim_win_get_cursor(p.win)[1])
      T.eq({ driver, action, line, vim.fn.screenpos(p.source, line, api.nvim_win_get_cursor(p.source)[2] + 1).row },
        { driver, action, line, vim.fn.screenpos(p.win, line, 1).row })
      T.eq(driver, api.nvim_get_current_win())
      local counterpart = p.source == old and new or old
      local coordinate = p:coordinates(p.source)[line]
      T.eq(p:locate(coordinate, counterpart).row, api.nvim_win_get_cursor(counterpart)[1])
    end
  end
  p:close(); vim.cmd("diffoff!")
end)

T.test("native overview positioning follows the current segment of a screen-filling wrapped line", function()
  local lines = {}; for row = 1, 200 do lines[row] = "line " .. row end
  lines[80] = string.rep("wrapped ", 400)
  local source = setup(lines)
  vim.wo[source].wrap, vim.wo[source].smoothscroll = true, true
  local p = ui.open(source, { windows = { buffer = source } }, { notes = { note(80) } })
  for _, driver in ipairs({ source, p.win }) do
    for _, action in ipairs({ driver == source and "80G$" or "80G0", "zt", "zz", "zb", "zt", "zz" }) do
      api.nvim_set_current_win(driver)
      api.nvim_feedkeys(action, "xt", false); vim.cmd("redraw!")
      api.nvim_exec_autocmds("SafeState", {}); vim.wait(20, function() return false end); vim.cmd("redraw!")
      local code_row = vim.fn.screenpos(source, 80, api.nvim_win_get_cursor(source)[2] + 1).row
      assert(code_row > 0, "wrapped code cursor must remain visible")
      T.eq({ driver, action, code_row }, { driver, action, vim.fn.screenpos(p.win, 80, 1).row })
      T.eq(80, api.nvim_win_get_cursor(p.win)[1]); T.eq(driver, api.nvim_get_current_win())
    end
  end
  p:close()
end)

T.test("native expanded viewport actions scroll code by display rows without mapping prose to source lines", function()
  local lines = {}; for row = 1, 700 do lines[row] = "line " .. row end
  local source = setup(lines)
  local selected = note(150); selected.detail = string.rep("Explanation\n", 600)
  local p = ui.open(source, { windows = { buffer = source } }, { notes = { selected } })
  motion(p.win, "150G0"); key(p.buf, "K")
  local function top(win)
    local view = api.nvim_win_call(win, vim.fn.winsaveview)
    return view.topline - view.topfill
  end
  for _, driver in ipairs({ source, p.win }) do
    for _, action in ipairs({ driver == source and "200G0" or "70G0", "zz", "zt", "zb", "5j", "5k", "<C-f>", "<C-b>" }) do
      local before_code, before_detail = top(source), top(p.win)
      api.nvim_set_current_win(driver)
      api.nvim_feedkeys(api.nvim_replace_termcodes(action, true, false, true), "xt", false)
      vim.cmd("redraw!"); api.nvim_exec_autocmds("SafeState", {})
      vim.wait(20, function() return false end)
      T.eq({ driver, action, top(source) - before_code }, { driver, action, top(p.win) - before_detail })
      T.eq(driver, api.nvim_get_current_win()); T.eq(1, p.detail_index)
    end
  end
  p:close()
end)

T.test("in-pane detail navigation syncs code and collapse retains the current explanation", function()
  local lines = {}; for row = 1, 100 do lines[row] = "line " .. row end
  local source = setup(lines)
  local a, b = note(40), note(80)
  a.detail = string.rep("Explanation paragraph.\n\n", 40)
  local result = { notes = { a, b } }
  local p = ui.open(source, { windows = { buffer = source } }, result)
  motion(p.win, "40G")
  vim.wait(20, function() return false end)
  local code_view = api.nvim_win_call(source, vim.fn.winsaveview)
  local tick, windows = api.nvim_buf_get_changedtick(p.buf), #api.nvim_list_wins()
  vim.wo[p.win].statusline = "OWNED BY EDITOR"
  key(p.buf, "K")
  T.eq(p.win, p.detail_win); T.eq(windows, #api.nvim_list_wins())
  T.eq("", api.nvim_win_get_config(p.detail_win).relative)
  T.eq(true, api.nvim_buf_is_valid(p.buf)); T.eq(false, vim.bo[p.detail_buf].modifiable)
  motion(p.win, p.detail_layout.last .. "G"); p:align(); p:render(); p:sync(p.win)
  api.nvim_exec_autocmds("WinScrolled", { pattern = tostring(p.win) })
  assert(not vim.deep_equal(code_view, api.nvim_win_call(source, vim.fn.winsaveview)), "native detail scrolling must move code too")
  local first = p.detail_buf
  local events = {}
  api.nvim_create_autocmd({ "BufEnter", "BufLeave", "BufWinEnter", "BufWinLeave", "FileType", "WinEnter", "WinLeave" }, {
    group = p.group, callback = function(event) events[#events + 1] = event.event .. ":" .. vim.bo[event.buf].filetype end,
  })
  key(first, "n"); T.eq(2, p.detail_index)
  T.eq({}, events); T.eq(first, p.detail_buf); T.eq(first, api.nvim_get_current_buf())
  T.eq(80, api.nvim_win_get_cursor(source)[1])
  T.eq(80, p.overview.view.lnum)
  assert(detail_lines(p)[1]:find("Note 80", 1, true))
  vim.wait(20, function() return false end)
  T.eq({}, events); T.eq(first, api.nvim_get_current_buf())
  key(first, "p"); key(first, "n")
  T.eq({}, events); T.eq(first, p.detail_buf)
  key(p.detail_buf, "<Esc>"); T.eq(nil, p.detail_win); T.eq(false, p.closed)
  vim.wait(20, function() return false end)
  T.eq(80, api.nvim_win_get_cursor(p.win)[1]); T.eq({ 2 }, p.focus_ids)
  key(p.buf, "K"); key(p.detail_buf, "p"); T.eq(1, p.detail_index)
  T.eq(40, api.nvim_win_get_cursor(source)[1]); T.eq(40, p.overview.view.lnum)
  key(p.detail_buf, "<CR>"); T.eq(40, api.nvim_win_get_cursor(p.win)[1]); T.eq({ 1 }, p.focus_ids)
  T.eq(tick, api.nvim_buf_get_changedtick(p.buf))
  T.eq("OWNED BY EDITOR", vim.wo[p.win].statusline); T.eq(false, vim.wo[p.win].wrap)
  p:back(); key(p.buf, "<CR>")
  local detail = p.detail_buf
  p:set({ notes = { a, b, note(90) } }, "Ready")
  T.eq(false, api.nvim_buf_is_valid(detail)); T.eq(p.buf, api.nvim_win_get_buf(p.win))
  T.eq({ 3 }, p.rows[90]); T.eq({ 1 }, p.rows[40])
  key(p.buf, "q"); T.eq(true, p.closed); T.eq(false, api.nvim_buf_is_valid(p.buf))
end)

T.test("expanded navigation follows deleted diff lines and collapses on their current side", function()
  local before = {}; for row = 1, 120 do before[row] = "line " .. row end
  local old = setup(before)
  vim.cmd("belowright vsplit")
  local new, buf = api.nvim_get_current_win(), api.nvim_create_buf(false, true)
  api.nvim_win_set_buf(new, buf)
  local after = vim.deepcopy(before)
  for _ = 1, 3 do table.remove(after, 80) end
  api.nvim_buf_set_lines(buf, 0, -1, false, after)
  for _, win in ipairs({ old, new }) do api.nvim_win_call(win, function() vim.cmd("diffthis | normal! zR") end) end
  vim.cmd("diffupdate")
  local deletion = note(81, "Removed old line", "old")
  local p = ui.open(new, { windows = { old = old, new = new } },
    { notes = { note(20, nil, "new"), deletion, note(100, nil, "new") } })
  motion(p.win, "20G0"); key(p.buf, "K"); key(p.detail_buf, "n")
  T.eq(2, p.detail_index); T.eq(old, p.source)
  T.eq(81, api.nvim_win_get_cursor(old)[1]); T.eq(80, api.nvim_win_get_cursor(new)[1])
  T.eq(68, api.nvim_win_call(old, vim.fn.winsaveview).topline)
  vim.cmd("redraw!")
  T.eq(vim.fn.screenpos(old, 81, 1).row, detail_screen(p, 1))
  key(p.detail_buf, "<CR>")
  T.eq(81, api.nvim_win_get_cursor(p.win)[1]); T.eq({ 2 }, p.focus_ids)
  T.eq(68, api.nvim_win_call(p.win, vim.fn.winsaveview).topline)
  key(p.buf, "K"); key(p.detail_buf, "n"); T.eq(3, p.detail_index)
  T.eq(100, api.nvim_win_get_cursor(new)[1]); T.eq(103, api.nvim_win_get_cursor(old)[1])
  key(p.detail_buf, "p"); key(p.detail_buf, "q")
  T.eq(81, api.nvim_win_get_cursor(p.win)[1]); T.eq(old, p.source)
  T.eq(68, api.nvim_win_call(p.win, vim.fn.winsaveview).topline)
  p:close(); vim.cmd("diffoff!")
end)

T.test("Ctrl e y synchronize both diff sources and notes in overview and detail", function()
  local before = {}; for row = 1, 120 do before[row] = "line " .. row end
  local old = setup(before)
  vim.cmd("belowright vsplit")
  local new, buf = api.nvim_get_current_win(), api.nvim_create_buf(false, true)
  api.nvim_win_set_buf(new, buf)
  local after = vim.deepcopy(before); table.insert(after, 10, "added"); table.insert(after, 11, "another addition")
  api.nvim_buf_set_lines(buf, 0, -1, false, after)
  for _, win in ipairs({ old, new }) do api.nvim_win_call(win, function() vim.cmd("diffthis | normal! zR") end) end
  vim.cmd("diffupdate")
  local selected = note(50, nil, "new"); selected.detail = string.rep("Detailed explanation\n", 80)
  local p = ui.open(new, { windows = { old = old, new = new } }, { notes = { selected } })
  motion(p.win, "50G0")
  local function top(win)
    local view = api.nvim_win_call(win, vim.fn.winsaveview)
    return view.topline - view.topfill
  end
  for _, expanded in ipairs({ false, true }) do
    if expanded then key(p.buf, "K") end
    for _, driver in ipairs({ p.win, old, new }) do
      for _, action in ipairs({ { "<C-e>", 1 }, { "<C-y>", -1 } }) do
        local old_top, new_top, notes_top = top(old), top(new), top(p.win)
        api.nvim_set_current_win(driver)
        if driver == p.win then key(expanded and p.detail_buf or p.buf, action[1])
        else
          vim.cmd.normal({ api.nvim_replace_termcodes(action[1], true, false, true), bang = true })
          api.nvim_exec_autocmds("WinScrolled", { pattern = tostring(driver) })
        end
        T.eq({ expanded, driver, old_top + action[2], new_top + action[2] }, { expanded, driver, top(old), top(new) })
        if expanded then T.eq(notes_top + action[2], top(p.win))
        else T.eq(top(p.source), top(p.win)) end
        T.eq(driver, api.nvim_get_current_win())
      end
    end
  end
  key(p.detail_buf, "<CR>"); T.eq(50, api.nvim_win_get_cursor(p.win)[1])
  p:close(); vim.cmd("diffoff!")
end)

T.test("expanded scroll follows physical wrapped and folded rows and supports counts", function()
  local lines = {}; for row = 1, 100 do lines[row] = "line " .. row end
  lines[2] = string.rep("wrapped text ", 35)
  local source = setup(lines)
  vim.wo[source].wrap, vim.wo[source].smoothscroll = true, true
  vim.wo[source].foldmethod, vim.wo[source].foldenable = "manual", true
  api.nvim_win_call(source, function() vim.cmd("10,14fold") end)
  local selected = note(20); selected.detail = string.rep("Explanation\n", 100)
  local p = ui.open(source, { windows = { buffer = source } }, { notes = { selected } })
  motion(p.win, "20G0"); key(p.buf, "K")
  for _, line in ipairs({ 2, 10 }) do
    api.nvim_win_call(source, function() vim.cmd.normal({ line .. "Gzt", bang = true }) end)
    p:scroll(nil, source)
    api.nvim_win_call(p.win, function() vim.cmd.normal({ "20Gzt", bang = true }) end)
    api.nvim_set_current_win(source)
    vim.cmd.normal({ api.nvim_replace_termcodes("<C-e>", true, false, true), bang = true })
    api.nvim_exec_autocmds("WinScrolled", { pattern = tostring(source) })
    T.eq(21, api.nvim_win_call(p.win, vim.fn.winsaveview).topline)
    vim.cmd.normal({ api.nvim_replace_termcodes("<C-y>", true, false, true), bang = true })
    api.nvim_exec_autocmds("WinScrolled", { pattern = tostring(source) })
    T.eq(20, api.nvim_win_call(p.win, vim.fn.winsaveview).topline)
  end
  api.nvim_set_current_win(p.win)
  api.nvim_feedkeys(api.nvim_replace_termcodes("3<C-e>", true, false, true), "xt", false)
  T.eq(23, api.nvim_win_call(p.win, vim.fn.winsaveview).topline)
  api.nvim_feedkeys(api.nvim_replace_termcodes("3<C-y>", true, false, true), "xt", false)
  T.eq(20, api.nvim_win_call(p.win, vim.fn.winsaveview).topline)
  key(p.detail_buf, "<CR>"); T.eq(20, api.nvim_win_get_cursor(p.win)[1])
  T.eq(true, vim.wo[source].smoothscroll); T.eq(true, vim.wo[source].wrap)
  p:close()
end)

T.test("expansion keeps its summary position and preceding context; K toggles without editing code", function()
  local source, source_buf = setup({ "one", "two", "three", "four", "five", "six", "seven" })
  vim.wo[source].winbar = "test.lua"
  local selected = note(4, "Selected range"); selected.intent_basis = "documented"
  selected.anchors[1].end_line = 5
  local p = ui.open(source, { source_buf = source_buf, windows = { buffer = source } },
    { notes = { note(2, "Earlier note"), selected } })
  motion(p.win, "4G"); vim.cmd("redraw")
  local before = vim.fn.screenpos(p.win, 4, 1).row
  local code_view, tick = api.nvim_win_call(source, vim.fn.winsaveview), api.nvim_buf_get_changedtick(source_buf)
  key(p.buf, "K"); vim.cmd("redraw")
  T.eq(before, detail_screen(p, 1))
  T.eq(3, #p.overview.context)
  T.eq("[buffer:2] " .. summary("Earlier note"), p.overview.context[2][1][1])
  T.eq("ExplainrDetailContext", p.overview.context[2][1][2])
  local lines = detail_lines(p)
  T.eq("▎ D Selected range", lines[1])
  local controls = {}
  for _, m in ipairs(api.nvim_buf_get_extmarks(p.detail_buf, api.nvim_get_namespaces()["explainr.ui"], 0, -1, { details = true })) do
    if m[2] == p.detail_layout.first - 1 and m[4].virt_text then controls[#controls + 1] = m[4].virt_text[1][1] end
  end
  T.eq({ "[buffer:4–5] ", " [−]" }, controls)
  T.eq("**Intent basis:** documented · `test.lua`", lines[2])
  T.eq(selected.detail, lines[4])
  assert(vim.wo[p.win].winbar:find("Explainr", 1, true))
  local active_ns = api.nvim_get_namespaces()["explainr.detail." .. p.win]
  local active = api.nvim_buf_get_extmarks(source_buf, active_ns, 0, -1, { details = true })
  T.eq(2, #active); T.eq(3, active[1][2]); T.eq(4, active[2][2])
  for _, mark in ipairs(active) do
    T.eq("▎ ", mark[4].sign_text)
    T.eq("ExplainrActiveRange", mark[4].sign_hl_group)
    T.eq(5, mark[4].priority)
    T.eq(nil, mark[4].hl_group); T.eq(nil, mark[4].line_hl_group)
    T.eq(nil, mark[4].number_hl_group); T.eq(nil, mark[4].end_row)
  end
  T.eq(nil, api.nvim_get_hl(0, { name = "ExplainrActiveRange", link = false }).underline)
  T.eq(tick, api.nvim_buf_get_changedtick(source_buf)); T.eq(code_view, api.nvim_win_call(source, vim.fn.winsaveview))
  local detail = p.detail_buf
  key(detail, "K"); T.eq(nil, p.detail_win); T.eq(false, api.nvim_buf_is_valid(detail))
  T.eq(2, #api.nvim_buf_get_extmarks(source_buf, active_ns, 0, -1, {})) -- Collapsed focus retains the anchors.
  key(p.buf, "<CR>"); key(p.detail_buf, "<CR>"); T.eq(p.buf, api.nvim_win_get_buf(p.win))
  T.eq(before, vim.fn.screenpos(p.win, 4, 1).row); T.eq(tick, api.nvim_buf_get_changedtick(source_buf))
  p:close()
end)

T.test("expanded neighbors remain dimmed at the same screen columns and source rows", function()
  local lines = {}; for row = 1, 40 do lines[row] = "source line " .. row end
  local source = setup(lines)
  vim.wo[source].winbar = "Source"
  local selected = note(4, "Selected range"); selected.anchors[1].end_line = 10
  selected.detail = "Short detail."
  local p = ui.open(source, { windows = { buffer = source } },
    { notes = { note(2, "Before"), selected, note(12, "After"), note(20, "Later") } })
  motion(p.win, "4G0"); api.nvim__inspect_cell(1, 0, 0); vim.cmd("redraw!")
  local info = vim.fn.getwininfo(p.win)[1]
  local function text(row, value)
    local actual = ""
    for col = info.wincol + 2, info.wincol + 1 + vim.fn.strdisplaywidth(value) do
      actual = actual .. vim.fn.screenstring(row, col)
    end
    T.eq(value, actual)
  end
  local rows = {}
  for _, line in ipairs({ 2, 4, 12, 20 }) do rows[line] = vim.fn.screenpos(p.win, line, 1).row end
  text(rows[2], "[buffer:2] " .. summary("Before"))
  text(rows[12], "[buffer:12] " .. summary("After"))
  text(rows[20], "[buffer:20] " .. summary("Later"))
  T.eq(2, info.textoff)
  key(p.buf, "<CR>"); vim.cmd("redraw!")
  T.eq(2, vim.fn.getwininfo(p.win)[1].textoff)
  text(rows[2], "[buffer:2] " .. summary("Before"))
  text(rows[4], "[buffer:4–10] ▎ ? Selected range [−]")
  text(rows[12], "[buffer:12] " .. summary("After"))
  text(rows[20], "[buffer:20] " .. summary("Later"))
  local dimmed = api.nvim_get_hl(0, { name = "ExplainrDetailContext", link = false })
  for _, line in ipairs({ 2, 12, 20 }) do
    local cell = api.nvim__inspect_cell(1, rows[line] - 1, info.wincol + 1)[2]
    T.eq(dimmed.fg, cell.foreground); T.eq(dimmed.bg, cell.background)
    T.eq(" ", vim.fn.screenstring(rows[line], info.wincol))
  end
  key(p.detail_buf, "n"); key(p.detail_buf, "<CR>")
  T.eq(12, api.nvim_win_get_cursor(p.win)[1])
  p:close()
end)

T.test("long and overlapping expanded cards retain following notes instead of consuming them", function()
  for _, long in ipairs({ false, true }) do
    local lines = {}; for row = 1, 40 do lines[row] = "source line " .. row end
    local source = setup(lines)
    vim.wo[source].winbar = "Source"
    local selected = note(3, "Overlapping range"); selected.anchors[1].end_line = 16
    selected.detail = long and string.rep("A longer detail.\n", 8) or "Short detail."
    local p = ui.open(source, { windows = { buffer = source } },
      { notes = { selected, note(5, "Inside anchor"), note(18, "Outside anchor") } })
    motion(p.win, "3G0"); p:detail(); vim.cmd("redraw!")
    local tail = {}
    for _, m in ipairs(api.nvim_buf_get_extmarks(p.detail_buf, api.nvim_get_namespaces()["explainr.ui"], 0, -1, { details = true })) do
      if m[2] >= p.detail_layout.last and m[4].virt_text then tail[#tail + 1] = m[4].virt_text end
    end
    assert(#tail > 0, "following notes must be retained")
    T.eq("[buffer:5] " .. summary("Inside anchor"), tail[1][1][1])
    T.eq({ "ExplainrDetailContext", "ExplainrDetailActive" }, tail[1][1][2])
    T.eq("[buffer:18] " .. summary("Outside anchor"), tail[14][1][1])
    T.eq("ExplainrDetailContext", tail[14][1][2])
    T.eq(lines, api.nvim_buf_get_lines(api.nvim_win_get_buf(source), 0, -1, false))
    p:close()
  end
end)

T.test("expanded card background covers semantic labels and wrapped margins without recoloring source", function()
  local source, source_buf = setup({ "source" })
  vim.wo[source].winbar = "Source"
  local note = note(1, "Removes the validation specialization.")
  note.intent_basis = "inferred"
  note.anchors[1].path = "app/Modules/Example/Exceptions/Example/ExampleValidationException.php"
  note.detail = "This file defined a creation-specific validation exception. The diff deletes the entire file. "
    .. "The supplied snapshot does not establish why it was removed or what replaces it."
  local p = ui.open(source, { windows = { buffer = source } }, { notes = { note } })
  local groups = { "ExplainrSummary", "ExplainrMetadata", "ExplainrInferred", "ExplainrDetailCue" }
  local saved = {}
  for _, name in ipairs(groups) do
    saved[name] = api.nvim_get_hl(0, { name = name, link = true })
    local hl = api.nvim_get_hl(0, { name = name, link = false })
    hl.bg = 0x090b10
    api.nvim_set_hl(0, name, hl)
  end
  local ok, err = xpcall(function()
    p:detail(); api.nvim__inspect_cell(1, 0, 0); vim.cmd("redraw!")
    local info = vim.fn.getwininfo(p.win)[1]
    local active = api.nvim_get_hl(0, { name = "ExplainrDetailActive", link = false }).bg
    local backdrop = api.nvim_get_hl(0, { name = "ExplainrDetailBackdrop", link = false }).bg
    local first = vim.fn.screenpos(p.win, 1, 1).row
    for col = info.wincol + info.textoff, info.wincol + info.width - 1 do
      T.eq(active, api.nvim__inspect_cell(1, first - 1, col - 1)[2].background)
    end
    local body, last = vim.fn.screenpos(p.win, 4, 1).row, vim.fn.screenpos(p.win, 5, 1).row
    assert(last - body > 1, "body must wrap to exercise the linebreak margin")
    for row = body, last do
      T.eq(active, api.nvim__inspect_cell(1, row - 1, info.wincol + info.width - 2)[2].background)
    end
    for row = first, last do
      for col = info.wincol, info.wincol + info.textoff - 1 do
        T.eq(backdrop, api.nvim__inspect_cell(1, row - 1, col - 1)[2].background)
      end
      T.eq(" ", vim.fn.screenstring(row, info.wincol + 1))
    end
    T.eq({ "source" }, api.nvim_buf_get_lines(source_buf, 0, -1, false))
  end, debug.traceback)
  for name, hl in pairs(saved) do api.nvim_set_hl(0, name, hl) end
  p:close(); assert(ok, err)
end)

T.test("focus tint softens theme CursorLine with neutral fallbacks and respects overrides", function()
  local saved, background = {}, vim.o.background
  for _, name in ipairs({ "Normal", "CursorLine", "NormalFloat", "DiagnosticInfo", "ExplainrDetailActive" }) do
    saved[name] = api.nvim_get_hl(0, { name = name, link = true })
  end
  local ok, err = xpcall(function()
    for _, theme in ipairs({
      { "dark", 0x102030, 0x304860, 0x203448 },
      { "light", 0xf0faf5, 0xdce4ec, 0xe6eff0 },
      { "dark", 0x102030, false, 0x1c3044, 0x284058 },
      { "dark", 0x102030, false, 0x182736 },
    }) do
      vim.o.background = theme[1]
      api.nvim_set_hl(0, "Normal", { fg = 0x808080, bg = theme[2] })
      api.nvim_set_hl(0, "CursorLine", theme[3] and { bg = theme[3] } or {})
      api.nvim_set_hl(0, "NormalFloat", theme[5] and { bg = theme[5] } or {})
      api.nvim_set_hl(0, "DiagnosticInfo", { fg = 0x00ff00 })
      api.nvim_set_hl(0, "ExplainrDetailActive", {})
      local source = setup({ "source" })
      local p = ui.open(source, { windows = { buffer = source } }, { notes = { note(1) } })
      T.eq(theme[4], api.nvim_get_hl(0, { name = "ExplainrDetailActive", link = false }).bg)
      p:close()
    end
    api.nvim_set_hl(0, "ExplainrDetailActive", { bg = 0x123456 })
    local source = setup({ "source" })
    local p = ui.open(source, { windows = { buffer = source } }, { notes = { note(1) } })
    T.eq(0x123456, api.nvim_get_hl(0, { name = "ExplainrDetailActive", link = false }).bg)
    p:close()
  end, debug.traceback)
  vim.o.background = background
  for name, hl in pairs(saved) do api.nvim_set_hl(0, name, hl) end
  assert(ok, err)
end)

T.test("expanded following context retains folded notes and old-side deletion filler", function()
  for _, folded in ipairs({ false, true }) do
    local lines = {}; for row = 1, 30 do lines[row] = "source line " .. row end
    local old = setup(lines)
    vim.cmd("belowright vsplit")
    local new, buf = api.nvim_get_current_win(), api.nvim_create_buf(false, true)
    api.nvim_win_set_buf(new, buf)
    local after = vim.deepcopy(lines); after[3] = "changed line"
    table.remove(after, 12); table.remove(after, 11)
    api.nvim_buf_set_lines(buf, 0, -1, false, after)
    for _, win in ipairs({ old, new }) do
      vim.wo[win].winbar = "Source"
      api.nvim_win_call(win, function() vim.cmd("diffthis | normal! zR") end)
    end
    vim.cmd("diffupdate")
    if folded then
      for _, win in ipairs({ old, new }) do
        vim.wo[win].foldmethod = "manual"
        api.nvim_win_call(win, function() vim.cmd("16,18fold") end)
      end
    end
    local deleted = note(11, "Deleted lines", "old"); deleted.anchors[1].end_line = 12
    local p = ui.open(new, { windows = { old = old, new = new } },
      { notes = { note(3, "Selected", "new"), deleted, note(17, "Fold", "new") } })
    motion(p.win, "3G0"); p:detail()
    local tail = ""
    for _, m in ipairs(api.nvim_buf_get_extmarks(p.detail_buf, api.nvim_get_namespaces()["explainr.ui"], 0, -1, { details = true })) do
      if m[2] >= p.detail_layout.last and m[4].virt_text then
        T.eq("ExplainrDetailContext", m[4].virt_text[1][2])
        tail = tail .. m[4].virt_text[1][1] .. "\n"
      end
    end
    assert(tail:find("[old:11–12] " .. summary("Deleted lines"), 1, true))
    assert(tail:find("[new:17]", 1, true)); assert(tail:find("Fold", 1, true))
    if folded then assert(tail:find("folded", 1, true)) end
    p:close(); vim.cmd("diffoff!")
  end
end)

T.test("short expanded detail extends its tint and gutter using navigable rows without changing prose", function()
  local lines = {}; for row = 1, 40 do lines[row] = "source line " .. row end
  local source, source_buf = setup(lines)
  local selected = note(4, "Wide anchored range"); selected.anchors[1].end_line = 18
  selected.detail = "A short explanation."
  local p = ui.open(source, { windows = { buffer = source } }, { notes = { selected, note(22, "Next entry") } })
  motion(p.win, "4G0"); p:detail()
  api.nvim__inspect_cell(1, 0, 0); vim.cmd("redraw!")
  local info = vim.fn.getwininfo(p.win)[1]
  local last = vim.fn.screenpos(source, 18, 1).row
  local active = api.nvim_get_hl(0, { name = "ExplainrDetailActive", link = false }).bg
  T.eq("▎", vim.fn.screenstring(last, info.wincol))
  T.eq(active, api.nvim__inspect_cell(1, last - 1, info.wincol + info.width - 2)[2].background)
  assert(vim.fn.screenstring(last + 1, info.wincol) ~= "▎", "rail must stop at the anchor end when text is shorter")
  T.eq({ "▎ ? Wide anchored range", "**Intent basis:** unknown · `test.lua`", "", "A short explanation.", "" },
    detail_lines(p))
  T.eq(lines, api.nvim_buf_get_lines(source_buf, 0, -1, false))
  local detail = p.detail_buf
  key(detail, "n"); T.eq(detail, p.detail_buf)
  local padding = 0
  for row, context in pairs(p.detail_layout.rows) do
    if row > p.detail_layout.last and context.active then padding = padding + 1 end
  end
  T.eq(0, padding) -- Following a small anchor removes the previous range's continuation.
  key(detail, "<CR>"); T.eq(22, api.nvim_win_get_cursor(p.win)[1]); p:close()
end)

T.test("native detail movement reaches blank anchors and collapses at the destination on either boundary", function()
  local lines = {}; for row = 1, 60 do lines[row] = "source line " .. row end
  local source, source_buf = setup(lines)
  vim.wo[source].winbar = "Source"
  local selected = note(4, "Wide range"); selected.anchors[1].end_line = 18
  selected.detail = "Short prose."
  local p = ui.open(source, { windows = { buffer = source } },
    { notes = { note(2), selected, note(22) } })
  local source_tick, overview_tick = api.nvim_buf_get_changedtick(source_buf), api.nvim_buf_get_changedtick(p.buf)
  motion(p.win, "4G0"); p:detail()
  local detail = p.detail_buf
  motion(p.win, "14G0")
  T.eq(detail, api.nvim_win_get_buf(p.win)); T.eq(14, api.nvim_win_get_cursor(p.win)[1])
  T.eq(14, api.nvim_win_get_cursor(source)[1]); T.eq("", api.nvim_get_current_line())
  key(detail, "<CR>")
  T.eq(4, api.nvim_win_get_cursor(p.win)[1]); T.eq(4, api.nvim_win_get_cursor(source)[1])
  key(p.buf, "K"); detail = p.detail_buf; motion(p.win, "14G0")
  motion(p.win, "4j"); T.eq(18, api.nvim_win_get_cursor(source)[1]); T.eq(detail, p.detail_buf)
  motion(p.win, "j")
  T.eq(nil, p.detail_buf); T.eq(false, api.nvim_buf_is_valid(detail))
  T.eq(p.buf, api.nvim_win_get_buf(p.win)); T.eq(19, api.nvim_win_get_cursor(p.win)[1])
  T.eq(19, api.nvim_win_get_cursor(source)[1]); T.eq(p.win, api.nvim_get_current_win())
  motion(p.win, "3j"); T.eq(22, api.nvim_win_get_cursor(p.win)[1]); T.eq(nil, p.detail_buf)
  motion(p.win, "0") -- Reset the count left by normal! before invoking mapping callbacks.
  key(p.buf, "K"); key(p.detail_buf, "p") -- Explicit expanded entry navigation still works.
  T.eq(2, p.detail_index)
  motion(p.win, "k"); T.eq(nil, p.detail_buf)
  T.eq(3, api.nvim_win_get_cursor(p.win)[1]); T.eq(3, api.nvim_win_get_cursor(source)[1])
  motion(p.win, "k"); T.eq(2, api.nvim_win_get_cursor(p.win)[1]); T.eq(nil, p.detail_buf)
  T.eq(source_tick, api.nvim_buf_get_changedtick(source_buf)); T.eq(overview_tick, api.nvim_buf_get_changedtick(p.buf))
  p:close()
end)

T.test("expanded continuation cursor resolves folded and deleted display rows instead of Markdown line numbers", function()
  local lines = {}; for row = 1, 40 do lines[row] = "context " .. row end
  local old = setup(lines)
  vim.o.columns = 180 -- Keep metadata unwrapped; each continuation row has a known display coordinate.
  vim.cmd("belowright vsplit")
  local new, buf = api.nvim_get_current_win(), api.nvim_create_buf(false, true)
  api.nvim_win_set_buf(new, buf)
  local after = {}; for _, row in ipairs({ 1, 2 }) do after[#after + 1] = lines[row] end
  for row = 16, 40 do after[#after + 1] = lines[row] end
  api.nvim_buf_set_lines(buf, 0, -1, false, after)
  for _, source in ipairs({ old, new }) do api.nvim_win_call(source, function() vim.cmd("diffthis | normal! zR") end) end
  vim.cmd("diffupdate")
  local deleted = note(3, "Removed range", "old"); deleted.anchors[1].end_line = 15
  local p = ui.open(new, { windows = { old = old, new = new } }, { notes = { deleted } })
  p:detail(1); motion(p.win, "10G0")
  T.eq(1, p.detail_index); T.eq(10, api.nvim_win_get_cursor(old)[1])
  T.eq(3, api.nvim_win_get_cursor(new)[1]) -- Deleted row has no native cursor on new.
  motion(p.win, "6j"); T.eq(nil, p.detail_buf)
  T.eq(new, p.source); T.eq(3, api.nvim_win_get_cursor(p.win)[1]); T.eq(16, api.nvim_win_get_cursor(old)[1])
  p:close(); vim.cmd("diffoff!")

  local source = setup(lines)
  vim.wo[source].foldmethod, vim.wo[source].foldenable = "manual", true
  api.nvim_win_call(source, function() vim.cmd("10,14fold") end)
  local selected = note(4, "Folded range"); selected.anchors[1].end_line = 18
  p = ui.open(source, { windows = { buffer = source } }, { notes = { selected } })
  motion(p.win, "4G0"); p:detail(); motion(p.win, "11G0")
  T.eq(1, p.detail_index); T.eq(15, api.nvim_win_get_cursor(source)[1])
  motion(p.win, "3j"); T.eq(18, api.nvim_win_get_cursor(source)[1]); T.eq(1, p.detail_index)
  motion(p.win, "j"); T.eq(nil, p.detail_buf); T.eq(19, api.nvim_win_get_cursor(p.win)[1])
  p:close()
end)

T.test("expanded whole-file diff overview keeps its full visible range active past neighboring notes", function()
  local old = setup({ "" })
  vim.cmd("belowright vsplit")
  local new, buf = api.nvim_get_current_win(), api.nvim_create_buf(false, true)
  api.nvim_win_set_buf(new, buf)
  local lines = {}; for row = 1, 299 do lines[row] = "source line " .. row end
  api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  for _, win in ipairs({ old, new }) do
    vim.wo[win].winbar = "Source"
    api.nvim_win_call(win, function() vim.cmd("diffthis | normal! zR") end)
  end
  vim.cmd("diffupdate")
  local overview = note(1, "File purpose", "new")
  overview.kind, overview.anchors[1].end_line = "overview", 299
  overview.detail = "A short high-level overview."
  local next_entry = note(13, "Local behavior", "new"); next_entry.anchors[1].end_line = 16
  local p = ui.open(new, { windows = { old = old, new = new } }, { notes = { overview, next_entry } })
  motion(p.win, "1G0"); p:detail(); api.nvim__inspect_cell(1, 0, 0); vim.cmd("redraw!")
  local info = vim.fn.getwininfo(p.win)[1]
  local active = api.nvim_get_hl(0, { name = "ExplainrDetailActive", link = false }).bg
  local backdrop = api.nvim_get_hl(0, { name = "ExplainrDetailBackdrop", link = false }).bg
  local dimmed = api.nvim_get_hl(0, { name = "ExplainrDetailContext", link = false }).fg
  local function cell(row, col) return api.nvim__inspect_cell(1, row - 1, col - 1)[2] end
  local first = vim.fn.screenpos(new, 1, 1).row
  local last = vim.fn.screenpos(new, vim.fn.getwininfo(new)[1].botline - 1, 1).row
  for row = first, last do
    T.eq("▎", vim.fn.screenstring(row, info.wincol))
    T.eq(active, cell(row, info.wincol + info.width - 1).background)
    T.eq(backdrop, cell(row, info.wincol).background)
    T.eq(backdrop, cell(row, info.wincol + 1).background)
  end
  local next_row = vim.fn.screenpos(new, 13, 1).row
  T.eq("[", vim.fn.screenstring(next_row, info.wincol + 2))
  T.eq(dimmed, cell(next_row, info.wincol + 2).foreground)
  T.eq(active, cell(next_row, info.wincol + 2).background)
  T.eq({ "▎ ? File purpose", "**Intent basis:** unknown · `test.lua`", "",
    "A short high-level overview.", "" }, detail_lines(p))
  key(p.detail_buf, "n"); vim.cmd("redraw!")
  local below = vim.fn.screenpos(new, 20, 1).row
  assert(vim.fn.screenstring(below, info.wincol) ~= "▎", "switching to a local entry must clear the overview rail")
  assert(cell(below, info.wincol + info.width - 1).background ~= active)
  key(p.detail_buf, "<CR>"); T.eq(13, api.nvim_win_get_cursor(p.win)[1])
  T.eq(lines, api.nvim_buf_get_lines(buf, 0, -1, false))
  p:close(); vim.cmd("diffoff!")
end)

T.test("expanded range continuation counts displayed wraps and folds instead of logical line count", function()
  local lines = {}; for row = 1, 40 do lines[row] = "source line " .. row end
  lines[9] = string.rep("wrapped words ", 12)
  local source = setup(lines)
  vim.wo[source].wrap = true
  vim.wo[source].foldmethod = "manual"; vim.wo[source].foldenable = true
  api.nvim_win_call(source, function() vim.cmd("12,16fold | normal! gg") end)
  local selected = note(4, "Wrapped and folded range"); selected.anchors[1].end_line = 20
  selected.detail = "Short detail."
  local p = ui.open(source, { windows = { buffer = source } }, { notes = { selected } })
  motion(p.win, "4G0"); p:detail(); vim.cmd("redraw!")
  local info = vim.fn.getwininfo(p.win)[1]
  local first, last = vim.fn.screenpos(source, 4, 1).row, vim.fn.screenpos(source, 20, 1).row
  assert(last - first + 1 ~= 17, "fixture must differ from plain logical height")
  for row = first, last do T.eq("▎", vim.fn.screenstring(row, info.wincol)) end
  assert(vim.fn.screenstring(last + 1, info.wincol) ~= "▎")
  p:close()
end)

T.test("expanded diff focus also covers anchored context before the changed-line summary", function()
  local lines = {}; for row = 1, 40 do lines[row] = "context " .. row end
  local old = setup(lines)
  vim.cmd("belowright vsplit")
  local new = api.nvim_get_current_win()
  api.nvim_win_set_buf(new, api.nvim_create_buf(false, true))
  local after = vim.deepcopy(lines); after[8] = "changed behavior"
  api.nvim_buf_set_lines(0, 0, -1, false, after)
  for _, source in ipairs({ old, new }) do api.nvim_win_call(source, function() vim.cmd("diffthis | normal! zR") end) end
  vim.cmd("diffupdate")
  local selected = note(2, "Changed behavior in context", "new"); selected.anchors[1].end_line = 18
  local p = ui.open(new, { windows = { old = old, new = new } }, { notes = { selected } })
  T.eq({ row = 8 }, p.locations[1]); motion(p.win, "8G0"); p:detail()
  api.nvim__inspect_cell(1, 0, 0); vim.cmd("redraw!")
  local info = vim.fn.getwininfo(p.win)[1]
  local active = api.nvim_get_hl(0, { name = "ExplainrDetailActive", link = false }).bg
  for _, source_line in ipairs({ 2, 7, 18 }) do
    local row = vim.fn.screenpos(new, source_line, 1).row
    T.eq("▎", vim.fn.screenstring(row, info.wincol))
    T.eq(active, api.nvim__inspect_cell(1, row - 1, info.wincol + info.width - 2)[2].background)
  end
  local before = vim.fn.screenpos(new, 1, 1).row
  assert(vim.fn.screenstring(before, info.wincol) ~= "▎")
  assert(api.nvim__inspect_cell(1, before - 1, info.wincol + info.width - 2)[2].background ~= active)
  motion(p.win, "7G0"); T.eq(1, p.detail_index); T.eq(7, api.nvim_win_get_cursor(new)[1])
  motion(p.win, "2G0"); T.eq(1, p.detail_index); T.eq(2, api.nvim_win_get_cursor(old)[1])
  motion(p.win, "k"); T.eq(nil, p.detail_buf)
  T.eq(1, api.nvim_win_get_cursor(p.win)[1]); T.eq(1, api.nvim_win_get_cursor(new)[1])
  p:close(); vim.cmd("diffoff!")
end)

T.test("Enter toggles focused detail with a continuous gutter and leaves Tab unmapped", function()
  local source = setup({ "one", "two", "three", "four", "five", "six" })
  local selected = note(4, "Selected explanation")
  selected.detail = string.rep("Detailed words here. ", 6)
  local p = ui.open(source, { windows = { buffer = source } }, { notes = { note(1), selected } })
  vim.wo[p.win].winhighlight = "Normal:Normal,CursorLine:Search"
  vim.wo[p.win].statuscolumn = "%s"
  local source_highlight, source_gutter = vim.wo[source].winhighlight, vim.wo[source].statuscolumn
  for _, mapping in ipairs(api.nvim_buf_get_keymap(p.buf, "n")) do assert(mapping.lhs ~= "<Tab>") end
  motion(p.win, "2G"); key(p.buf, "<CR>"); T.eq(nil, p.detail_buf)
  motion(p.win, "4G"); vim.cmd("redraw")
  local view = api.nvim_win_call(p.win, vim.fn.winsaveview)
  local opening_row = vim.fn.screenpos(p.win, 4, 1).row
  key(p.buf, "<CR>"); vim.cmd("redraw")
  for _, mapping in ipairs(api.nvim_buf_get_keymap(p.detail_buf, "n")) do assert(mapping.lhs ~= "<Tab>") end
  T.eq(opening_row, detail_screen(p, 1))
  T.eq("yes:1", vim.wo[p.win].signcolumn)
  assert(vim.wo[p.win].winhighlight:find("CursorLine:Search", 1, true))
  assert(vim.wo[p.win].winhighlight:find("Normal:ExplainrDetailActive", 1, true))
  T.eq(nil, api.nvim_get_hl(0, { name = "ExplainrDetailActive", link = false }).fg) -- Don't overwrite Markdown/intent colors.
  local active = 0
  for _, m in ipairs(api.nvim_buf_get_extmarks(p.detail_buf, api.nvim_get_namespaces()["explainr.ui"], 0, -1, { details = true })) do
    if m[4].hl_group == "ExplainrDetailActive" and m[4].hl_eol and m[4].priority == 0 then active = active + 1 end
  end
  T.eq(#detail_lines(p), active) -- Include blank lines and the entire explanation.
  local info = vim.fn.getwininfo(p.win)[1]
  local first, last = detail_screen(p, 4), detail_screen(p, 5) - 1
  assert(last > first, "test must exercise wrapped detail")
  for row = first, last do T.eq("▎", vim.fn.screenstring(row, info.wincol)) end
  T.eq(" ", vim.fn.screenstring(info.winrow + info.winbar, info.wincol)) -- No rail on ghost context.
  local end_row = detail_screen(p, #detail_lines(p))
  assert(end_row < info.winrow + info.winbar + info.height - 1)
  assert(vim.fn.screenstring(end_row + 1, info.wincol) ~= "▎") -- No rail after the active block.
  T.eq(source_highlight, vim.wo[source].winhighlight); T.eq(source_gutter, vim.wo[source].statuscolumn)
  local detail = p.detail_buf
  key(detail, "<CR>"); T.eq(false, api.nvim_buf_is_valid(detail)); T.eq(nil, p.detail_buf)
  T.eq("yes:1", vim.wo[p.win].signcolumn); T.eq("%s", vim.wo[p.win].statuscolumn)
  assert(vim.wo[p.win].winhighlight:find("Normal:ExplainrDetailBackdrop", 1, true))
  T.eq(view, api.nvim_win_call(p.win, vim.fn.winsaveview))
  api.nvim_set_current_win(source) -- Leaving collapsed focus restores the user's exact settings.
  T.eq("Normal:Normal,CursorLine:Search", vim.wo[p.win].winhighlight)
  key(p.buf, "K"); key(p.detail_buf, "n"); key(p.detail_buf, "K")
  T.eq("%s", vim.wo[p.win].statuscolumn); p:close()
end)

T.test("collapsed explanation focus follows notes, highlights their ranges and restores both buffers on leave", function()
  local source, source_buf = setup({ "one", "two", "three", "four", "five", "six", "seven", "eight" })
  vim.wo[source].winbar = "Source"
  local selected = note(4, "Selected range"); selected.anchors[1].end_line = 6
  local p = ui.open(source, { source_buf = source_buf, windows = { buffer = source } },
    { notes = { note(1), selected, note(8) } })
  local original = vim.wo[p.win].winhighlight
  local tick, source_tick = api.nvim_buf_get_changedtick(p.buf), api.nvim_buf_get_changedtick(source_buf)
  local focus_ns = api.nvim_get_namespaces()["explainr.focus." .. p.win]
  local active_ns = api.nvim_get_namespaces()["explainr.detail." .. p.win]
  local overview_ns = "explainr.overview.focus." .. p.win
  motion(p.win, "4G")
  T.eq(nil, p.detail_buf); T.eq({ 2 }, p.focus_ids)
  T.eq(3, #api.nvim_buf_get_extmarks(source_buf, active_ns, 0, -1, {}))
  local colored = {}
  for _, mark in ipairs(marks(p, overview_ns)) do colored[mark[2] + 1] = mark[4].virt_text end
  T.eq("ExplainrDetailContext", colored[1][1][2])
  for row = 4, 6 do T.eq("ExplainrDetailActive", colored[row][#colored[row]][2]) end
  T.eq("▎ ", colored[5][1][1])
  T.eq("ExplainrDetailContext", colored[7][#colored[7]][2])
  T.eq(tick, api.nvim_buf_get_changedtick(p.buf)); T.eq(source_tick, api.nvim_buf_get_changedtick(source_buf))
  key(p.buf, "n"); T.eq({ 3 }, p.focus_ids)
  T.eq(7, api.nvim_buf_get_extmarks(source_buf, active_ns, 0, -1, {})[1][2])
  motion(p.win, "2G")
  T.eq({}, marks(p, overview_ns)); T.eq(original, vim.wo[p.win].winhighlight)
  T.eq({}, api.nvim_buf_get_extmarks(source_buf, focus_ns, 0, -1, {}))
  motion(p.win, "4G"); api.nvim_set_current_win(source)
  T.eq(original, vim.wo[p.win].winhighlight); T.eq({}, marks(p, overview_ns))
  T.eq({}, api.nvim_buf_get_extmarks(source_buf, active_ns, 0, -1, {}))
  api.nvim_set_current_win(p.win)
  assert(vim.wait(500, function() return p.focus_highlight ~= nil end))
  T.eq({ 2 }, p.focus_ids)
  key(p.buf, "<CR>"); key(p.detail_buf, "<CR>"); T.eq({ 2 }, p.focus_ids)
  p:set(p.result, "Stale")
  T.eq({}, marks(p, overview_ns)); T.eq({}, api.nvim_buf_get_extmarks(source_buf, focus_ns, 0, -1, {}))
  T.eq(original, vim.wo[p.win].winhighlight); p:close()
end)

T.test("file overview has a separate matched status header and focuses the complete source", function()
  local source, source_buf = setup({ "header", "two", "three", "four", "five" })
  local overview = note(1, "File overview: determines access")
  overview.kind = "overview"; overview.anchors[1].end_line = 5
  local p = ui.open(source, { source_buf = source_buf, windows = { buffer = source } },
    { notes = { overview, note(3) } })
  local bar = vim.o.statusline
  T.eq(" ", vim.wo[source].winbar); assert(vim.wo[p.win].winbar:find("Explainr", 1, true))
  T.eq({}, marks(p, "explainr.state")) -- No overlay may overwrite the file overview.
  vim.cmd("redraw")
  for _, row in ipairs({ 1, 3 }) do T.eq(vim.fn.screenpos(source, row, 1).row, vim.fn.screenpos(p.win, row, 1).row) end
  motion(p.win, "1G")
  local active_ns = api.nvim_get_namespaces()["explainr.detail." .. p.win]
  local focus_ns = api.nvim_get_namespaces()["explainr.focus." .. p.win]
  T.eq(5, #api.nvim_buf_get_extmarks(source_buf, active_ns, 0, -1, {}))
  T.eq({}, api.nvim_buf_get_extmarks(source_buf, focus_ns, 0, -1, {}))
  key(p.buf, "<CR>"); T.eq(5, #api.nvim_buf_get_extmarks(source_buf, active_ns, 0, -1, {}))
  key(p.detail_buf, "<CR>"); T.eq(5, #api.nvim_buf_get_extmarks(source_buf, active_ns, 0, -1, {}))
  T.eq(bar, vim.o.statusline)
  p:set(nil, "Stale"); T.eq(" ", vim.wo[source].winbar)
  p:set({ notes = { overview } }, "Ready")
  vim.wo[source].winbar = "User changed this header"
  p:close(); T.eq("User changed this header", vim.wo[source].winbar)
end)

T.test("whole-file diff overview stays at the start instead of its first changed hunk on either side", function()
  local old = setup({ "header", "old", "tail" })
  vim.cmd("belowright vsplit")
  local new, new_buf = api.nvim_get_current_win(), api.nvim_create_buf(false, true)
  api.nvim_win_set_buf(new, new_buf); api.nvim_buf_set_lines(new_buf, 0, -1, false, { "header", "new", "tail", "added" })
  for _, win in ipairs({ old, new }) do api.nvim_win_call(win, function() vim.cmd("diffthis | normal! zR") end) end
  vim.cmd("diffupdate")
  local overview = note(1, "File purpose and change purpose", "old")
  overview.kind = "overview"; overview.anchors[1].end_line = 3
  overview.anchors[2] = { path = "renamed.lua", side = "new", start_line = 1, end_line = 4 }
  local p = ui.open(new, { windows = { old = old, new = new } }, { notes = { overview, note(2, "Change", "new") } })
  T.eq({ row = 1 }, p.locations[1]); T.eq({ row = 2 }, p.locations[2])
  motion(p.win, "1G")
  local active_ns = api.nvim_get_namespaces()["explainr.detail." .. p.win]
  T.eq(3, #api.nvim_buf_get_extmarks(api.nvim_win_get_buf(old), active_ns, 0, -1, {}))
  T.eq(4, #api.nvim_buf_get_extmarks(new_buf, active_ns, 0, -1, {}))
  p:sync(old); T.eq({ row = 1 }, p.locations[1]); T.eq({}, marks(p, "explainr.state"))
  p:close(); T.eq("", vim.wo[old].winbar); T.eq("", vim.wo[new].winbar); vim.cmd("diffoff!")
end)

T.test("collapsed diff focus colors deleted filler without highlighting unrelated hunks or moving anchors", function()
  setup({ "" })
  local fixture = dofile("tests/multihunk.lua").open()
  for _, win in ipairs({ fixture.old, fixture.new }) do api.nvim_win_call(win, function() vim.cmd("normal! zR") end) end
  local original = vim.deepcopy(fixture.result)
  local p = ui.open(fixture.new, { windows = { old = fixture.old, new = fixture.new } }, fixture.result)
  motion(p.win, "74G")
  T.eq({ 5 }, p.focus_ids); T.eq(nil, p.detail_buf)
  -- Entering this hunk refines native linematch filler without a text edit.
  T.eq(1, api.nvim_win_call(fixture.new, function() return vim.fn.diff_filler(74) end))
  T.eq(75, p:coordinates(fixture.new)[74]); T.eq(77, p:coordinates(fixture.new)[75])
  local active_ns = api.nvim_get_namespaces()["explainr.detail." .. p.win]
  local active = api.nvim_buf_get_extmarks(api.nvim_win_get_buf(fixture.old), active_ns, 0, -1, {})
  T.eq(2, #active); T.eq(70, active[1][2]); T.eq(71, active[2][2])
  T.eq({}, api.nvim_buf_get_extmarks(api.nvim_win_get_buf(fixture.new), active_ns, 0, -1, {}))
  local selected, dimmed = 0, 0
  for _, geometry in ipairs(p.virtual_geometry) do
    for i, coordinate in ipairs(geometry.coordinates) do
      local chunks = geometry.opts.virt_lines[i]
      local hl = chunks[#chunks][2]
      if coordinate >= p:coordinates(fixture.old)[71] and coordinate <= p:coordinates(fixture.old)[72] then
        T.eq("ExplainrDetailActive", hl); selected = selected + 1
      elseif hl == "ExplainrDetailContext" then dimmed = dimmed + 1 end
    end
  end
  -- Native diff pairs the first deleted old line with changed new line 74;
  -- only the second deletion is filler. Both must retain the focus tint.
  T.eq(1, selected); assert(dimmed > 0)
  local paired = false
  for _, mark in ipairs(marks(p, "explainr.overview.focus." .. p.win)) do
    if mark[2] == 73 then
      local chunks = mark[4].virt_text
      T.eq("ExplainrDetailActive", chunks[#chunks][2]); paired = true
    end
  end
  assert(paired)
  T.eq(original, p.result)
  p:close()
  T.eq({}, api.nvim_buf_get_extmarks(api.nvim_win_get_buf(fixture.old), active_ns, 0, -1, {}))
  vim.cmd("diffoff!")
end)

T.test("bottom-edge expansion leaves its first body visible without moving the source", function()
  local lines = {}; for row = 1, 100 do lines[row] = "line " .. row end
  for _, bar in ipairs({ "", "test.lua" }) do
    local source = setup(lines)
    vim.wo[source].winbar = bar
    local selected = note(80, "A lower note")
    selected.detail = "This explanation should be visible immediately, even when expanded near the bottom of the viewport."
    local p = ui.open(source, { windows = { buffer = source } }, { notes = { selected } })
    motion(p.win, "80G")
    api.nvim_win_call(source, function()
      vim.fn.winrestview({ topline = 80 - vim.fn.getwininfo(source)[1].height + 1, lnum = 80, col = 0 })
    end)
    p:align(); vim.cmd("redraw")
    local view = api.nvim_win_call(source, vim.fn.winsaveview)
    local opening_row = vim.fn.screenpos(p.win, 80, 1).row
    key(p.buf, "K"); vim.cmd("redraw")
    local body_row = detail_screen(p, 4)
    local info = vim.fn.getwininfo(p.win)[1]
    assert(body_row >= info.winrow + info.winbar and body_row < info.winrow + info.winbar + info.height,
      "the first explanation line is below the viewport")
    assert(detail_screen(p, 1) < opening_row)
    T.eq(view, api.nvim_win_call(source, vim.fn.winsaveview))
    T.eq(1, info.winbar) -- The matched header is already reserved before expansion.
    key(p.detail_buf, "q"); T.eq(view, api.nvim_win_call(source, vim.fn.winsaveview))
    p:close()
  end
end)

T.test("expanded range decorations update for entries, clear on set/close and preserve other panes", function()
  local source, source_buf = setup({ "one", "two", "three", "four", "five" })
  local result = { notes = { note(2), note(4) } }
  local snapshot = { source_buf = source_buf, windows = { buffer = source } }
  local p, other = ui.open(source, snapshot, result), ui.open(source, snapshot, result)
  local namespaces = api.nvim_get_namespaces()
  local first_ns, other_ns = namespaces["explainr.detail." .. p.win], namespaces["explainr.detail." .. other.win]
  local focus_ns, other_focus_ns = namespaces["explainr.focus." .. p.win], namespaces["explainr.focus." .. other.win]
  p:detail(1); other:detail(2)
  T.eq(1, #api.nvim_buf_get_extmarks(source_buf, first_ns, 0, -1, {}))
  T.eq(1, #api.nvim_buf_get_extmarks(source_buf, other_ns, 0, -1, {}))
  T.eq(2, #api.nvim_buf_get_extmarks(source_buf, focus_ns, 0, -1, {}))
  local other_focus = api.nvim_buf_get_extmarks(source_buf, other_focus_ns, 0, -1, { details = true })
  key(p.detail_buf, "n")
  T.eq(3, api.nvim_buf_get_extmarks(source_buf, first_ns, 0, -1, {})[1][2])
  T.eq(3, api.nvim_buf_get_extmarks(source_buf, focus_ns, 0, -1, { details = true })[1][4].end_row)
  T.eq(3, #p.overview.context) -- Visible entry 4 expands from its own row, not entry 2's.
  p:set(nil, "Stale")
  T.eq({}, api.nvim_buf_get_extmarks(source_buf, first_ns, 0, -1, {}))
  T.eq({}, api.nvim_buf_get_extmarks(source_buf, focus_ns, 0, -1, {}))
  T.eq(1, #api.nvim_buf_get_extmarks(source_buf, other_ns, 0, -1, {}))
  T.eq(other_focus, api.nvim_buf_get_extmarks(source_buf, other_focus_ns, 0, -1, { details = true }))
  other:close(); T.eq({}, api.nvim_buf_get_extmarks(source_buf, other_ns, 0, -1, {}))
  T.eq({}, api.nvim_buf_get_extmarks(source_buf, other_focus_ns, 0, -1, {})); p:close()
end)

T.test("source focus dims only the complement of overlapping and disjoint anchors without modifying text", function()
  local source, source_buf = setup({ "one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten", "eleven" })
  local selected = note(7)
  selected.anchors[1].end_line = 9
  selected.anchors[2] = { path = "test.lua", side = "buffer", start_line = 4, end_line = 5 }
  selected.anchors[3] = { path = "test.lua", side = "buffer", start_line = 2, end_line = 4 }
  local original, tick = vim.deepcopy(selected.anchors), api.nvim_buf_get_changedtick(source_buf)
  local p = ui.open(source, { source_buf = source_buf, windows = { buffer = source } }, { notes = { selected } })
  local focus_ns = api.nvim_get_namespaces()["explainr.focus." .. p.win]
  p:detail(1)
  local gaps = {}
  for _, mark in ipairs(api.nvim_buf_get_extmarks(source_buf, focus_ns, 0, -1, { details = true })) do
    gaps[#gaps + 1] = { mark[2], mark[4].end_row }
    T.eq("ExplainrSourceContext", mark[4].hl_group); T.eq(0, mark[4].end_col)
  end
  T.eq({ { 0, 1 }, { 5, 6 }, { 9, 11 } }, gaps)
  T.eq(nil, api.nvim_get_hl(0, { name = "ExplainrSourceContext", link = false }).bg)
  T.eq(original, selected.anchors); T.eq(tick, api.nvim_buf_get_changedtick(source_buf))
  p:back(); api.nvim_set_current_win(source)
  T.eq({}, api.nvim_buf_get_extmarks(source_buf, focus_ns, 0, -1, {}))
  -- Whole-file focus leaves no dimming, including both boundary rows.
  p.result.notes[1].anchors = { { path = "test.lua", side = "buffer", start_line = 1, end_line = 11 } }
  p:detail(1); T.eq({}, api.nvim_buf_get_extmarks(source_buf, focus_ns, 0, -1, {}))
  p:back()
  -- The source window now displays another file: never tint that replacement.
  local replacement = api.nvim_create_buf(false, true)
  api.nvim_buf_set_lines(replacement, 0, -1, false, { "unrelated", "code" })
  api.nvim_win_set_buf(source, replacement)
  p:detail(1); T.eq({}, api.nvim_buf_get_extmarks(replacement, focus_ns, 0, -1, {}))
  T.eq({}, api.nvim_buf_get_extmarks(source_buf, focus_ns, 0, -1, {})); p:close()
end)

T.test("deletion expansion marks original paired coordinates without replacing Git or diagnostic signs", function()
  local old, old_buf = setup({ "first", "removed", "removed too", "last", "tail" })
  vim.cmd("belowright vsplit"); local new = api.nvim_get_current_win()
  local new_buf = api.nvim_create_buf(false, true); api.nvim_win_set_buf(new, new_buf)
  api.nvim_buf_set_lines(new_buf, 0, -1, false, { "first", "last", "tail" })
  for _, win in ipairs({ old, new }) do api.nvim_win_call(win, function() vim.cmd("diffthis | normal! zR") end) end
  vim.cmd("diffupdate")
  vim.wo[old].signcolumn = "yes:2"; vim.wo[new].signcolumn = "yes:1"
  local signs_ns = api.nvim_create_namespace("test.other-signs")
  api.nvim_buf_set_extmark(old_buf, signs_ns, 1, 0, { sign_text = "-", sign_hl_group = "DiffDelete", priority = 6 })
  api.nvim_buf_set_extmark(new_buf, signs_ns, 1, 0, { sign_text = "!", sign_hl_group = "DiagnosticWarn", priority = 10 })
  local signs = {}
  for _, buf in ipairs({ old_buf, new_buf }) do
    signs[buf] = api.nvim_buf_get_extmarks(buf, signs_ns, 0, -1, { details = true })
  end
  local deletion = note(2, "Removed branch", "old"); deletion.anchors[1].end_line = 3
  local paired = note(4, "Remaining branch", "old")
  paired.anchors[2] = { path = "test.lua", side = "new", start_line = 2, end_line = 2 }
  local p = ui.open(new, { windows = { old = old, new = new } }, { notes = { deletion, paired } })
  -- Cell inspection enables highlight provenance; redraw before the baseline.
  api.nvim__inspect_cell(1, 0, 0)
  vim.cmd("redraw")
  local pixels = {}
  for _, win in ipairs({ old, new }) do
    local pos = vim.fn.screenpos(win, 2, 1)
    for col = pos.col, pos.col + 6 do
      pixels[#pixels + 1] = { win = win, row = pos.row, col = col,
        attrs = api.nvim__inspect_cell(1, pos.row - 1, col - 1)[2] }
    end
  end
  p:detail(1)
  T.eq(1, #p.overview.context) -- first row, then the first deleted virtual row
  T.eq("▎ ? Removed branch", detail_lines(p)[1])
  local active_ns = api.nvim_get_namespaces()["explainr.detail." .. p.win]
  local active = api.nvim_buf_get_extmarks(old_buf, active_ns, 0, -1, {})
  T.eq(2, #active); T.eq(1, active[1][2]); T.eq(2, active[2][2])
  T.eq({}, api.nvim_buf_get_extmarks(new_buf, active_ns, 0, -1, {}))
  local focus_ns = api.nvim_get_namespaces()["explainr.focus." .. p.win]
  local paired_focus = api.nvim_buf_get_extmarks(new_buf, focus_ns, 0, -1, { details = true })
  T.eq(1, #paired_focus); T.eq(0, paired_focus[1][2]); T.eq(3, paired_focus[1][4].end_row)
  vim.cmd("redraw")
  for _, pixel in ipairs(pixels) do
    local attrs = api.nvim__inspect_cell(1, pixel.row - 1, pixel.col - 1)[2]
    T.eq(pixel.attrs.background, attrs.background)
    if pixel.win == old then T.eq(pixel.attrs, attrs) end
  end
  local new_pos = vim.fn.screenpos(new, 2, 1)
  assert(api.nvim__inspect_cell(1, new_pos.row - 1, new_pos.col - 1)[2].foreground ~= pixels[8].attrs.foreground,
    "unanchored counterpart should be dimmed")
  key(p.detail_buf, "n")
  T.eq(3, api.nvim_buf_get_extmarks(old_buf, active_ns, 0, -1, {})[1][2])
  T.eq(1, api.nvim_buf_get_extmarks(new_buf, active_ns, 0, -1, {})[1][2])
  vim.cmd("redraw")
  for _, pixel in ipairs(pixels) do
    local attrs = api.nvim__inspect_cell(1, pixel.row - 1, pixel.col - 1)[2]
    T.eq(pixel.attrs.background, attrs.background)
    if pixel.win == new then T.eq(pixel.attrs, attrs) end
  end
  local old_pos = vim.fn.screenpos(old, 2, 1)
  -- A single-column gutter keeps the diagnostic; two columns show both signs.
  T.eq("!", vim.fn.screenstring(new_pos.row, new_pos.col - 2))
  p:detail(1); vim.cmd("redraw")
  T.eq("-", vim.fn.screenstring(old_pos.row, old_pos.col - 4))
  T.eq("▎", vim.fn.screenstring(old_pos.row, old_pos.col - 2))
  p:back(); api.nvim_set_current_win(new)
  T.eq({}, api.nvim_buf_get_extmarks(old_buf, active_ns, 0, -1, {}))
  T.eq({}, api.nvim_buf_get_extmarks(new_buf, active_ns, 0, -1, {}))
  T.eq({}, api.nvim_buf_get_extmarks(old_buf, focus_ns, 0, -1, {}))
  T.eq({}, api.nvim_buf_get_extmarks(new_buf, focus_ns, 0, -1, {}))
  vim.cmd("redraw")
  for _, pixel in ipairs(pixels) do T.eq(pixel.attrs, api.nvim__inspect_cell(1, pixel.row - 1, pixel.col - 1)[2]) end
  T.eq("yes:2", vim.wo[old].signcolumn); T.eq("yes:1", vim.wo[new].signcolumn)
  for _, buf in ipairs({ old_buf, new_buf }) do
    T.eq(signs[buf], api.nvim_buf_get_extmarks(buf, signs_ns, 0, -1, { details = true }))
    api.nvim_buf_clear_namespace(buf, signs_ns, 0, -1)
  end
  p:close(); vim.cmd("diffoff!")
end)

T.test("detail navigation follows source order rather than incremental request order", function()
  local source = setup({ "one", "two", "three", "four", "five" })
  local p = ui.open(source, { windows = { buffer = source } },
    { notes = { note(4), note(1), note(3), note(3, "Second note here") } })
  motion(p.win, "1G"); key(p.buf, "K"); T.eq(2, p.detail_index)
  key(p.detail_buf, "n"); T.eq(3, p.detail_index)
  key(p.detail_buf, "n"); T.eq(1, p.detail_index)
  key(p.detail_buf, "n"); T.eq(4, p.detail_index)
  local tick = api.nvim_buf_get_changedtick(p.detail_buf)
  key(p.detail_buf, "n"); T.eq(4, p.detail_index)
  T.eq(tick, api.nvim_buf_get_changedtick(p.detail_buf))
  key(p.detail_buf, "p"); T.eq(1, p.detail_index)
  key(p.detail_buf, "p"); T.eq(3, p.detail_index)
  key(p.detail_buf, "p"); T.eq(2, p.detail_index)
  tick = api.nvim_buf_get_changedtick(p.detail_buf)
  key(p.detail_buf, "p"); T.eq(2, p.detail_index)
  T.eq(tick, api.nvim_buf_get_changedtick(p.detail_buf))
  p:close()
end)

T.test("detail navigation keeps every entry free of generated context and citation sections", function()
  local source = setup({ "one", "two", "three" })
  local p = ui.open(source, { windows = { buffer = source }, context = { strategy = "focused", radius = 99,
    omitted_files = 9 } }, { notes = { note(1), note(2), note(3) } })
  p:detail()
  for index = 1, 3 do
    T.eq(index, p.detail_index)
    T.eq({ "▎ ? Note " .. index, "**Intent basis:** unknown · `test.lua`", "",
      "Full explanation without another request.", "" }, detail_lines(p))
    key(p.detail_buf, "n")
  end
  p:close()
end)

T.test("range references and continuation rails retain logical lines including paired deletion filler", function()
  local source = setup({ "one", "two", "three", "four", "five" })
  local n = note(2); n.anchors[1].end_line = 4
  local p = ui.open(source, { windows = { buffer = source } }, { notes = { n } })
  local refs, rails = {}, {}
  for _, m in ipairs(marks(p, "explainr.ranges")) do
    local text = m[4].virt_text[1][1]
    if text == "│ " then rails[#rails + 1] = m[2] + 1 else refs[#refs + 1] = text end
    assert(not m[4].virt_lines)
  end
  T.eq({ "[buffer:2–4] " }, refs); T.eq({ 3, 4 }, rails)
  T.eq(5, api.nvim_buf_line_count(p.buf)); T.eq({ 1 }, p.rows[2]); T.eq({}, p.rows[3]); p:close()
  local old = setup({ "kept", "removed", "removed too", "last", "tail" })
  vim.cmd("belowright vsplit"); local new = api.nvim_get_current_win()
  local buf = api.nvim_create_buf(false, true); api.nvim_win_set_buf(new, buf)
  api.nvim_buf_set_lines(buf, 0, -1, false, { "kept", "last", "tail" })
  for _, candidate in ipairs({ old, new }) do api.nvim_win_call(candidate, function() vim.cmd("diffthis | normal! zR") end) end
  vim.cmd("diffupdate")
  local deletion = note(2, "Deletion", "old"); deletion.anchors[1].end_line = 3
  local paired = note(4, "Paired", "old"); paired.anchors[1].end_line = 5
  paired.anchors[2] = { path = "test.lua", side = "new", start_line = 2, end_line = 3 }
  p = ui.open(new, { windows = { old = old, new = new } }, { notes = { deletion, paired } })
  T.eq("[old:4–5 ↔ new:2–3] ", p.references[2])
  T.eq("[old:2–3] ", p.filler_refs[2][-2])
  local found = false
  for _, m in ipairs(marks(p, "explainr.geometry")) do
    if m[4].virt_lines_above then
      T.eq("[old:2–3] ", m[4].virt_lines[1][1][1]); T.eq("│ ", m[4].virt_lines[2][1][1]); found = true
    end
  end
  assert(found); T.eq(3, api.nvim_buf_line_count(p.buf)); p:close(); vim.cmd("diffoff!")
end)

T.test("overlapping notes occupy separate rows in their ranges without stealing primary anchors", function()
  local source = setup({ "one", "two", "three", "four", "five", "six", "seven" })
  local broad, narrow, primary = note(2, "Broad"), note(2, "Narrow"), note(3, "Primary")
  broad.anchors[1].end_line = 6; broad.intent_basis = "documented"
  narrow.anchors[1].end_line = 3
  local result = { notes = { broad, narrow, primary } }
  local original, view = vim.deepcopy(result), api.nvim_win_call(source, vim.fn.winsaveview)
  local p = ui.open(source, { windows = { buffer = source } }, result)
  T.eq({ row = 2 }, p.locations[2]); T.eq({ row = 3 }, p.locations[3]); T.eq({ row = 4 }, p.locations[1])
  T.eq("[buffer:2–3] ", p.references[2]); T.eq("[buffer:2–6] ", p.references[4])
  T.eq({ 2, 3, 1 }, p.note_order); T.eq(7, api.nvim_buf_line_count(p.buf)); T.eq(original, p.result)
  T.eq(view, api.nvim_win_call(source, vim.fn.winsaveview))
  motion(p.win, "2G"); vim.cmd("normal n"); T.eq(3, api.nvim_win_get_cursor(source)[1])
  vim.cmd("normal n"); T.eq(4, api.nvim_win_get_cursor(source)[1]); key(p.buf, "<CR>"); T.eq(1, p.detail_index)
  local active = api.nvim_buf_get_extmarks(api.nvim_win_get_buf(source), api.nvim_get_namespaces()["explainr.detail." .. p.win], 0, -1, {})
  T.eq(5, #active); T.eq(1, active[1][2]); T.eq(5, active[#active][2])
  p:close()
end)

T.test("equal-range overlaps sort by intent then original order and remain stable across renders", function()
  local source = setup({ "one", "two", "three", "four", "five", "six", "seven" })
  local notes = { note(2, "Unknown"), note(2, "Inferred"), note(2, "Documented first"), note(2, "Documented second"), note(5) }
  notes[2].intent_basis = "inferred"; notes[3].intent_basis = "documented"; notes[4].intent_basis = "documented"
  for index = 1, 4 do notes[index].anchors[1].end_line = 6 end
  local p = ui.open(source, { windows = { buffer = source } }, { notes = notes })
  for id, row in pairs({ [3] = 2, [4] = 3, [2] = 4, [5] = 5, [1] = 6 }) do T.eq({ row = row }, p.locations[id]) end
  local locations = vim.deepcopy(p.locations)
  api.nvim_win_set_width(p.win, 45); p:render(); T.eq(locations, p.locations)
  p:render(); T.eq(locations, p.locations); p:close()
end)

T.test("exhausted overlaps use free rows without stealing primary positions or changing anchors", function()
  local source = setup({ "one", "two", "three" }); vim.o.columns = 240
  local first, second, primary = note(2, "First reason"), note(2, "Second reason"), note(3, "Reserved")
  first.intent_basis = "documented"
  local result = { notes = { second, first, primary } }
  local original = vim.deepcopy(result)
  local p = ui.open(source, { windows = { buffer = source } }, result)
  T.eq({ 2 }, p.rows[2]); T.eq({ 3 }, p.rows[3]); T.eq({ 1 }, p.rows[4])
  T.eq({ row = 4 }, p.locations[1]); T.eq({ row = 2 }, p.locations[2])
  T.eq("[buffer:2] ▎ D First reason [+]", p.references[2] .. p.lines[2])
  T.eq("[buffer:2] ▎ ? Second reason [+]", p.references[4] .. p.lines[4])
  motion(p.win, "ggj"); key(p.buf, "n"); T.eq(3, api.nvim_win_get_cursor(source)[1])
  key(p.buf, "n"); T.eq(4, api.nvim_win_get_cursor(p.win)[1]); T.eq(2, api.nvim_win_get_cursor(source)[1])
  key(p.buf, "K"); T.eq(1, p.detail_index)
  assert(table.concat(detail_lines(p), "\n"):find("Second reason", 1, true))
  key(p.detail_buf, "<CR>"); T.eq(4, api.nvim_win_get_cursor(p.win)[1])
  p:render(); T.eq({ row = 4 }, p.locations[1]); T.eq(original, p.result)
  T.eq(4, api.nvim_buf_line_count(p.buf)); T.eq(3, api.nvim_buf_line_count(api.nvim_win_get_buf(source))); p:close()
end)

T.test("exhausted overlaps reuse a blank annotation row while keeping its original cursor target", function()
  local source = setup({ "one", "two", "three", "four" })
  local first, second = note(2, "First"), note(2, "Second")
  first.intent_basis = "documented"
  local p = ui.open(source, { windows = { buffer = source } }, { notes = { second, first, note(4) } })
  T.eq({ row = 3 }, p.locations[1]); T.eq("[buffer:2] ", p.references[3])
  T.eq(4, api.nvim_buf_line_count(p.buf))
  motion(p.win, "ggj"); key(p.buf, "n")
  T.eq(3, api.nvim_win_get_cursor(p.win)[1]); T.eq(2, api.nvim_win_get_cursor(source)[1])
  key(p.buf, "n"); T.eq(4, api.nvim_win_get_cursor(source)[1])
  key(p.buf, "p"); T.eq(3, api.nvim_win_get_cursor(p.win)[1]); T.eq(2, api.nvim_win_get_cursor(source)[1])
  p:close()
end)

T.test("one-line diff overviews and overlapping notes have independent cursor, detail and navigation rows", function()
  local old = setup({ "-- empty module" })
  vim.cmd("belowright vsplit"); local new = api.nvim_get_current_win()
  local buf = api.nvim_create_buf(false, true); api.nvim_win_set_buf(new, buf)
  api.nvim_buf_set_lines(buf, 0, -1, false, { "from . import helpers" })
  for _, win in ipairs({ old, new }) do api.nvim_win_call(win, function() vim.cmd("diffthis | normal! zR") end) end
  vim.cmd("diffupdate")
  local overview, change = note(1, "File purpose", "new"), note(1, "Import change", "new")
  overview.kind = "overview"; change.intent_basis = "documented"
  local p = ui.open(new, { windows = { old = old, new = new } }, { notes = { change, overview } })
  T.eq({ 2 }, p.rows[1]); T.eq({ 1 }, p.rows[2]); T.eq({ 2, 1 }, p.note_order)
  T.eq("[new:1] ", p.references[1]); T.eq("[new:1] ", p.references[2])
  T.eq(2, api.nvim_buf_line_count(p.buf))
  motion(p.win, "gg"); key(p.buf, "j")
  T.eq(2, api.nvim_win_get_cursor(p.win)[1]); T.eq(1, api.nvim_win_get_cursor(new)[1])
  T.eq(1, api.nvim_win_get_cursor(old)[1]); assert(state(p):find("2 / 2", 1, true))
  key(p.buf, "k"); T.eq(1, api.nvim_win_get_cursor(p.win)[1])
  key(p.buf, "K"); T.eq(2, p.detail_index)
  key(p.detail_buf, "n"); T.eq(1, p.detail_index)
  T.eq(1, api.nvim_win_get_cursor(new)[1]); T.eq(1, api.nvim_win_get_cursor(old)[1])
  key(p.detail_buf, "<CR>"); T.eq(2, api.nvim_win_get_cursor(p.win)[1])
  key(p.buf, "p"); T.eq(1, api.nvim_win_get_cursor(p.win)[1])
  key(p.buf, "n"); T.eq(2, api.nvim_win_get_cursor(p.win)[1])
  p:sync(old); T.eq(2, api.nvim_buf_line_count(p.buf))
  p:sync(new); T.eq({ 2, 1 }, p.note_order)
  T.eq({ "from . import helpers" }, api.nvim_buf_get_lines(buf, 0, -1, false))
  p:close(); vim.cmd("diffoff!")
end)

T.test("overlapping deletion and EOF notes occupy existing diff filler rows", function()
  for _, before in ipairs({ { "kept", "removed one", "removed two", "last" }, { "kept", "removed one", "removed two" } }) do
    local old = setup(before)
    vim.cmd("belowright vsplit"); local new = api.nvim_get_current_win()
    local buf = api.nvim_create_buf(false, true); api.nvim_win_set_buf(new, buf)
    api.nvim_buf_set_lines(buf, 0, -1, false, #before == 4 and { "kept", "last" } or { "kept" })
    for _, win in ipairs({ old, new }) do api.nvim_win_call(win, function() vim.cmd("diffthis | normal! zR") end) end
    vim.cmd("diffupdate")
    local a, b = note(2, "First removal", "old"), note(2, "Second removal", "old")
    a.intent_basis = "documented"; a.anchors[1].end_line = 3; b.anchors[1].end_line = 3
    local p = ui.open(new, { windows = { old = old, new = new } }, { notes = { b, a } })
    local eof = #before == 3
    T.eq({ row = eof and 1 or 2, offset = eof and 1 or -2, eof = eof or nil }, p.locations[2])
    T.eq({ row = eof and 1 or 2, offset = eof and 2 or -1, eof = eof or nil }, p.locations[1])
    local refs = eof and p.eof_refs or p.filler_refs[2]
    T.eq("[old:2–3] ", refs[eof and 1 or -2]); T.eq("[old:2–3] ", refs[eof and 2 or -1])
    T.eq(eof and 1 or 2, api.nvim_buf_line_count(p.buf)); p:sync(old)
    T.eq({ row = 2 }, p.locations[2]); T.eq({ row = 3 }, p.locations[1])
    p:close(); vim.cmd("diffoff!")
  end
end)

T.test("ready and pending headers explain intent symbols without adding rows or owning statusline", function()
  for _, bar in ipairs({ "", "Source" }) do
    local source = setup({ "one", "two", "three" }); vim.wo[source].winbar = bar
    local p = ui.open(source, { windows = { buffer = source } }, { notes = { note(2) } })
    api.nvim_win_set_width(p.win, 100); p:render()
    local count, projection = api.nvim_buf_line_count(p.buf), vim.deepcopy(p.projection)
    for _, status in ipairs({ "Ready", "Pending · external agent" }) do
      p:set(p.result, status)
      local header = state(p)
      for _, meaning in ipairs({ "D documented", "~ inferred", "? unknown" }) do assert(header:find(meaning, 1, true), header) end
      T.eq(count, api.nvim_buf_line_count(p.buf)); T.eq(projection, p.projection)
      T.eq(status, vim.b[p.buf].explainr_status)
    end
    p:close()
  end
end)

T.test("headers count explanations in display order through navigation expansion and collapse", function()
  for _, bar in ipairs({ "", "Source" }) do
    local source = setup({ "one", "two", "three", "four", "five", "six", "seven" })
    vim.wo[source].winbar = bar
    local statusline = vim.o.statusline
    local p = ui.open(source, { windows = { buffer = source } }, { notes = { note(6), note(2), note(4) } })
    local function detail_header()
      return state(p)
    end
    assert(state(p):find("3 explanations", 1, true), state(p))
    motion(p.win, "2G0"); assert(state(p):find("1 / 3", 1, true), state(p))
    key(p.buf, "n"); assert(state(p):find("2 / 3", 1, true), state(p))
    key(p.buf, "K"); local detail = p.detail_buf
    assert(detail_header():find("2 / 3", 1, true), detail_header())
    key(detail, "n"); T.eq(1, p.detail_index)
    assert(detail_header():find("3 / 3", 1, true), detail_header())
    key(detail, "n"); T.eq(1, p.detail_index)
    assert(detail_header():find("3 / 3", 1, true), detail_header())
    key(detail, "p"); T.eq(3, p.detail_index)
    assert(detail_header():find("2 / 3", 1, true), detail_header())
    key(detail, "p"); T.eq(2, p.detail_index)
    assert(detail_header():find("1 / 3", 1, true), detail_header())
    key(detail, "p"); T.eq(2, p.detail_index)
    assert(detail_header():find("1 / 3", 1, true), detail_header())
    key(detail, "n"); T.eq(3, p.detail_index)
    assert(detail_header():find("2 / 3", 1, true), detail_header())
    key(detail, "n"); T.eq(1, p.detail_index)
    assert(detail_header():find("3 / 3", 1, true), detail_header())
    T.eq(detail, p.detail_buf); T.eq(statusline, vim.o.statusline)
    key(detail, "<CR>"); T.eq(6, api.nvim_win_get_cursor(p.win)[1])
    assert(state(p):find("3 / 3", 1, true), state(p))
    motion(p.win, "3G0"); p:set(p.result, "Pending · external agent")
    assert(state(p):find("3 explanations", 1, true), state(p))
    p:set({ notes = {} }, "Ready")
    assert(state(p):find("0 explanations", 1, true), state(p))
    p:close()
  end
end)

T.test("folded rows count every explanation rather than navigation stops", function()
  local source = setup({ "one", "two", "three", "four", "five", "six", "seven", "eight" })
  vim.wo[source].winbar = "Source"
  local p = ui.open(source, { windows = { buffer = source } },
    { notes = { note(8), note(3, "First"), note(3, "Second"), note(5) } })
  motion(p.win, "3G0")
  assert(state(p):find("1 / 4", 1, true), state(p))
  vim.wo[source].foldmethod, vim.wo[source].foldenable = "manual", true
  api.nvim_win_call(source, function() vim.cmd("3,5fold") end); p:render()
  assert(state(p):find("1–3 / 4", 1, true), state(p))
  key(p.buf, "K")
  assert(vim.wo[p.win].winbar:find("1–3 / 4", 1, true), vim.wo[p.win].winbar)
  key(p.detail_buf, "n")
  assert(vim.wo[p.win].winbar:find("2 / 4", 1, true), vim.wo[p.win].winbar)
  p:close()
end)

T.test("header ordinals update when notes are appended and survive narrow panes", function()
  local source = setup({ "one", "two", "three", "four", "five", "six", "seven", "eight", "nine" })
  vim.wo[source].winbar = "Source"
  local p = ui.open(source, { windows = { buffer = source } }, { notes = { note(9), note(4) } })
  motion(p.win, "4G0"); assert(state(p):find("1 / 2", 1, true), state(p))
  p:set({ notes = { note(9), note(4), note(2) } }, "Ready")
  assert(state(p):find("2 / 3", 1, true), state(p))
  api.nvim_win_set_width(p.win, 25); p:render()
  assert(state(p):find("2 / 3", 1, true), state(p))
  assert(vim.fn.strwidth(state(p)) <= 25, state(p))
  key(p.buf, "K")
  assert(vim.wo[p.win].winbar:find("2 / 3", 1, true), vim.wo[p.win].winbar)
  -- Winbars do not inherit Markdown's wrapped linebreak display calculation.
  assert(vim.fn.strwidth(state(p)) <= 25, state(p))
  key(p.detail_buf, "<CR>")
  p:set(nil, "Stale · changed context")
  assert(state(p):find("0 explanations", 1, true), state(p))
  p:close()
end)

T.test("expanded first-row counter stays in the reserved header without changing detail text", function()
  local source = setup({ "one", "two", "three" })
  local p = ui.open(source, { windows = { buffer = source } }, { notes = { note(1) } })
  motion(p.win, "2G0"); assert(state(p):find("1 explanation ·", 1, true), state(p))
  motion(p.win, "1G0"); key(p.buf, "K")
  T.eq({}, p.overview.context); T.eq(1, vim.fn.getwininfo(p.win)[1].winbar)
  local m = api.nvim_buf_get_extmarks(p.detail_buf, api.nvim_get_namespaces()["explainr.state"], 0, -1, { details = true })
  T.eq({}, m); assert(state(p):find("1 / 1 · Expanded", 1, true), state(p))
  T.eq("▎ ? Note 1", api.nvim_buf_get_lines(p.detail_buf, 0, 1, false)[1])
  key(p.detail_buf, "n")
  T.eq({}, api.nvim_buf_get_extmarks(p.detail_buf, api.nvim_get_namespaces()["explainr.state"], 0, -1, {}))
  p:close()
end)

T.test("requested scopes animate only matching visible rows without writes or coordinate scans", function()
  local lines = {}; for row = 1, 6000 do lines[row] = "line " .. row end
  local source = setup(lines)
  local result = { notes = { note(3) } }
  local p = ui.open(source, { windows = { buffer = source } }, result)
  local function rows()
    local rows = {}; for _, m in ipairs(marks(p, "explainr.loading")) do rows[#rows + 1] = m[2] + 1 end
    return rows
  end
  for _, scope in ipairs({ "selection", "function", "class", "hunk" }) do
    p.pending = { source = source, scope = scope, row = 4, windows = { buffer = source },
      snapshot = { target = { anchors = { { side = "buffer", start_line = 4, end_line = 6 } } } } }
    p:set(result, "Pending · " .. scope)
    T.eq({ 4, 5, 6 }, rows()); T.eq({ 1 }, p.rows[3])
  end
  vim.wait(20, function() return false end)
  local fill, height, render = vim.fn.diff_filler, api.nvim_win_text_height, p.render
  local calls, writes, renders = 0, 0, 0
  local group = api.nvim_create_augroup("ExplainrRangeAnimationTest", { clear = true })
  api.nvim_create_autocmd("TextChanged", { group = group, buffer = p.buf, callback = function() writes = writes + 1 end })
  vim.fn.diff_filler = function(...) calls = calls + 1; return fill(...) end
  api.nvim_win_text_height = function(...) calls = calls + 1; return height(...) end
  p.render = function(self) renders = renders + 1; return render(self) end
  local ok, err = xpcall(function()
    local tick, frame = api.nvim_buf_get_changedtick(p.buf), p.frame
    local first = marks(p, "explainr.loading")[1][4].virt_text[1][2][1]
    assert(vim.wait(500, function() return p.frame ~= frame end))
    assert(vim.wait(1000, function() return first ~= marks(p, "explainr.loading")[1][4].virt_text[1][2][1] end))
    T.eq({ 4, 5, 6 }, rows())
    -- Collection finishing between ticks replaces the provisional region, with
    -- no structural render or new full-file coordinate scan.
    p.pending.snapshot.target.anchors = { { side = "buffer", start_line = 10, end_line = 11 } }
    frame = p.frame; assert(vim.wait(500, function() return p.frame ~= frame end))
    T.eq({ 10, 11 }, rows()); T.eq(tick, api.nvim_buf_get_changedtick(p.buf))
    T.eq(0, calls); T.eq(0, writes); T.eq(0, renders)
  end, debug.traceback)
  vim.fn.diff_filler, api.nvim_win_text_height, p.render = fill, height, render
  api.nvim_del_augroup_by_id(group)
  assert(ok, err)
  p.pending = { source = source, scope = "file", row = 4, windows = { buffer = source } }
  p:set(result, "Pending · collecting file")
  T.eq(vim.fn.getwininfo(source)[1].height, #rows())
  p.pending.scope = "hunk"; p:set(result, "Pending · provisional hunk"); T.eq({ 4 }, rows())
  vim.wo[source].foldmethod = "manual"; vim.wo[source].foldenable = true
  api.nvim_win_call(source, function() vim.cmd("2,8fold") end)
  p.pending.snapshot = { target = { anchors = { { side = "buffer", start_line = 4, end_line = 6 } } } }
  p:set(result, "Pending · folded selection")
  local first = vim.b[p.buf].explainr_loading_folds["2"]
  assert(first and first:find("[buffer:3]", 1, true))
  assert(vim.startswith(first, "▊ "))
  local frame = p.frame
  assert(vim.wait(500, function() return p.frame ~= frame end))
  T.eq(first, vim.b[p.buf].explainr_loading_folds["2"]) -- Fold text is steady; the gutter glow changes.
  p.pending = nil; p:set(result, "Cancelled"); T.eq({}, rows()); T.eq({}, vim.b[p.buf].explainr_loading_folds); p:close()
end)

T.test("active and queued scopes animate together, retain accepted notes and clear completed ranges", function()
  local lines = {}; for row = 1, 12 do lines[row] = "line " .. row end
  local source = setup(lines)
  local result = { notes = { note(1, "Accepted") } }
  local p = ui.open(source, { windows = { buffer = source } }, result)
  local function request(first, last)
    return { source = source, scope = "hunk", row = first, windows = { buffer = source },
      snapshot = { target = { anchors = { { side = "buffer", start_line = first, end_line = last } } } } }
  end
  local function rows()
    return vim.tbl_map(function(m) return m[2] + 1 end, marks(p, "explainr.loading"))
  end
  p.pending = request(2, 3)
  p.queued = { request(5, 6), { source = source, scope = "hunk", row = 9, windows = { buffer = source } } }
  p:set(result, "Pending · external agent")
  T.eq({ 2, 3, 5, 6, 9 }, rows()); assert(state(p):find("2 queued", 1, true))
  T.eq(summary("Accepted"), api.nvim_buf_get_lines(p.buf, 0, 1, false)[1])
  local tick, frame = api.nvim_buf_get_changedtick(p.buf), p.frame
  assert(vim.wait(500, function() return p.frame ~= frame end))
  T.eq({ 2, 3, 5, 6, 9 }, rows()); T.eq(tick, api.nvim_buf_get_changedtick(p.buf))
  p.pending = table.remove(p.queued, 1)
  p:set(result, "Pending · external agent")
  T.eq({ 5, 6, 9 }, rows()); assert(state(p):find("1 queued", 1, true))
  p.pending, p.queued = nil, nil; p:set(result, "Cancelled")
  T.eq({}, rows()); T.eq(summary("Accepted"), api.nvim_buf_get_lines(p.buf, 0, 1, false)[1])
  p:close()
end)

T.test("loading does not repaint the focused cursor cell on summaries, blank rows or folds", function()
  local source = setup({ "one", "two", "three", "four", "five" })
  local p = ui.open(source, { windows = { buffer = source } }, { notes = { note(2) } })
  p.pending = { source = source, scope = "file", windows = { buffer = source } }
  p:set(p.result, "Pending · cursor check"); p:stop_spinner()
  api.nvim_set_current_win(p.win)
  local guicursor = vim.o.guicursor
  for _, line in ipairs({ 2, 3, 1 }) do
    api.nvim_win_set_cursor(p.win, { line, 0 }); p:sync(p.win)
    p.frame = 1; p:state(); vim.cmd("redraw")
    local pos = vim.fn.screenpos(p.win, line, 1)
    local char, attr = vim.fn.screenstring(pos.row, pos.col), vim.fn.screenattr(pos.row, pos.col)
    for _, frame in ipairs({ 9, 21, 33, 47 }) do
      p.frame = frame; p:state(); vim.cmd("redraw")
      T.eq(pos, vim.fn.screenpos(p.win, line, 1))
      T.eq(char, vim.fn.screenstring(pos.row, pos.col)); T.eq(attr, vim.fn.screenattr(pos.row, pos.col))
    end
    for _, m in ipairs(marks(p, "explainr.loading")) do assert(m[2] + 1 ~= line) end
    T.eq(4, #marks(p, "explainr.loading")) -- Only the cursor row pauses.
  end
  api.nvim_set_current_win(source)
  api.nvim_exec_autocmds("WinEnter", { buffer = api.nvim_win_get_buf(source) })
  assert(vim.wait(500, function() return #marks(p, "explainr.loading") == 5 end))
  api.nvim_set_current_win(p.win)
  vim.wo[source].foldmethod = "manual"; vim.wo[source].foldenable = true
  api.nvim_win_call(source, function() vim.cmd("2,4fold") end)
  api.nvim_win_set_cursor(source, { 2, 0 }); p:render()
  p.frame = 1; p:state(); vim.cmd("redraw")
  local pos = vim.fn.screenpos(p.win, 2, 1)
  local char, attr = vim.fn.screenstring(pos.row, pos.col), vim.fn.screenattr(pos.row, pos.col)
  p.frame = 21; p:state(); vim.cmd("redraw")
  T.eq(char, vim.fn.screenstring(pos.row, pos.col)); T.eq(attr, vim.fn.screenattr(pos.row, pos.col))
  T.eq(guicursor, vim.o.guicursor); p:close()
end)

T.test("loading rail cascades while full-width backgrounds and accepted text remain steady", function()
  local source, source_buf = setup({ "one", "two", "three", "four", "five", "six" })
  local result = { notes = { note(2, "Café 界"), note(5, "Outside request") } }
  local p = ui.open(source, { windows = { buffer = source } }, result)
  p.pending = { source = source, scope = "selection", windows = { buffer = source },
    snapshot = { target = { anchors = { { side = "buffer", start_line = 2, end_line = 4 } } } } }
  p:set(result, "Pending · selection"); p:stop_spinner()
  local tick, source_tick = api.nvim_buf_get_changedtick(p.buf), api.nvim_buf_get_changedtick(source_buf)
  local width = api.nvim_win_get_width(p.win) - vim.fn.getwininfo(p.win)[1].textoff
  local function inspect(frame)
    p.frame = frame; p:loading()
    local active = marks(p, "explainr.loading")
    T.eq(3, #active)
    local rails = {}
    for index, m in ipairs(active) do
      T.eq(index, m[2]); T.eq("win_col", m[4].virt_text_pos); T.eq(0, m[4].virt_text_win_col)
      local text, colors = "", {}
      for _, chunk in ipairs(m[4].virt_text) do
        text = text .. chunk[1]
        colors[chunk[2][1]] = true
        T.eq("ExplainrLoading", chunk[2][#chunk[2]])
      end
      local rail = m[4].virt_text[1]
      T.eq("▊", rail[1]); assert(rail[2][1]:match("^ExplainrLoadingRail[1-8]$"))
      rails[index] = rail[2][1]
      T.eq(width, vim.fn.strdisplaywidth(text))
      if index == 1 then
        assert(text:find("[buffer:2] " .. summary("Café 界"), 1, true))
        assert(colors.ExplainrUnknown and colors.ExplainrSummary and colors.ExplainrDetailCue)
      end
    end
    return rails, active
  end
  local first, before = inspect(1)
  local later, after = inspect(7)
  assert(first[1] ~= later[1]); assert(first[1] ~= first[2] and first[2] ~= first[3])
  for index, mark in ipairs(before) do
    T.eq(vim.list_slice(mark[4].virt_text, 2), vim.list_slice(after[index][4].virt_text, 2))
  end
  T.eq(tick, api.nvim_buf_get_changedtick(p.buf)); T.eq(source_tick, api.nvim_buf_get_changedtick(source_buf))
  -- A wide glyph cut at the boundary must not spill a following character into
  -- the final cell during resize, before the overview has been shortened again.
  result.notes[1].summary = "界Z"; p:set(result, "Pending · narrow")
  p:stop_spinner(); api.nvim_win_set_width(p.win, 18); p.frame = 21; p:loading()
  local chunks = marks(p, "explainr.loading")[1][4].virt_text
  local text = table.concat(vim.tbl_map(function(chunk) return chunk[1] end, chunks))
  T.eq(16, vim.fn.strdisplaywidth(text)); assert(not text:find("界", 1, true)); assert(not text:find("Z", 1, true))
  for _, terminal in ipairs({ "Ready", "Failed", "Cancelled", "Stale" }) do
    p:set(result, terminal); T.eq({}, marks(p, "explainr.loading")); T.eq(nil, p.timer)
  end
  p:close()
end)

T.test("loading rails cover wrapped continuations without duplicating their accepted summary", function()
  local source = setup({ "before", string.rep("x", 160), "after" })
  vim.wo[source].wrap = true
  local p = ui.open(source, { windows = { buffer = source } }, { notes = { note(2, "Wrapped summary") } })
  api.nvim_win_set_width(source, 40); api.nvim_win_set_cursor(source, { 2, 60 })
  p.pending = { source = source, scope = "selection", windows = { buffer = source },
    snapshot = { target = { anchors = { { side = "buffer", start_line = 2, end_line = 2 } } } } }
  p:set(p.result, "Pending · wrapped selection"); p:stop_spinner(); p.frame = 21; p:loading()
  local logical = marks(p, "explainr.loading")
  T.eq(1, #logical); T.eq(1, logical[1][2])
  local text = table.concat(vim.tbl_map(function(chunk) return chunk[1] end, logical[1][4].virt_text))
  assert(not text:find("Wrapped summary", 1, true))
  local summaries, animated = 0, 0
  for _, m in ipairs(marks(p, "explainr.geometry")) do
    for _, row in ipairs(m[4].virt_lines or {}) do
      if type(row[1][2]) == "table" then
        animated = animated + 1
        text = table.concat(vim.tbl_map(function(chunk) return chunk[1] end, row))
        T.eq(api.nvim_win_get_width(p.win) - vim.fn.getwininfo(p.win)[1].textoff, vim.fn.strdisplaywidth(text))
        if text:find("Wrapped summary", 1, true) then summaries = summaries + 1 end
      end
    end
  end
  T.eq(3, animated); T.eq(1, summaries)
  p:close()
end)

T.test("either diff side cursor and scroll remap annotations and paired movement by native coordinates", function()
  local before, after = {}, {}
  for row = 1, 100 do before[row] = "context " .. row; after[row] = "context " .. row end
  for row = 1, 3 do table.insert(after, 5, "inserted " .. row) end
  local old = setup(before)
  vim.cmd("belowright vsplit"); local new = api.nvim_get_current_win()
  local buf = api.nvim_create_buf(false, true); api.nvim_win_set_buf(new, buf)
  api.nvim_buf_set_lines(buf, 0, -1, false, after)
  for _, candidate in ipairs({ old, new }) do api.nvim_win_call(candidate, function() vim.cmd("diffthis | normal! zR") end) end
  vim.cmd("diffupdate")
  local paired = note(10, "Paired", "old")
  paired.anchors[2] = { path = "test.lua", side = "new", start_line = 13, end_line = 13 }
  local result = { notes = { paired, note(40, "Foreign", "old") } }
  local p = ui.open(old, { windows = { old = old, new = new } }, result)
  motion(new, "14G"); T.eq(new, p.source); T.eq(14, api.nvim_win_get_cursor(p.win)[1])
  T.eq({ 1 }, p.rows[13]); T.eq({ 2 }, p.rows[43]); T.eq(new, api.nvim_get_current_win())
  motion(p.win, "15G"); T.eq(15, api.nvim_win_get_cursor(new)[1]); T.eq(12, api.nvim_win_get_cursor(old)[1])
  motion(old, "16G"); T.eq(old, p.source); T.eq({ 1 }, p.rows[10]); T.eq({ 2 }, p.rows[40])
  -- Source-driven scrolling follows the side the user is interacting with.
  api.nvim_set_current_win(new)
  api.nvim_win_call(new, function() vim.fn.winrestview({ topline = 30, lnum = 31, col = 0 }) end)
  api.nvim_exec_autocmds("WinScrolled", { pattern = tostring(new) })
  T.eq(new, p.source); T.eq(30, api.nvim_win_call(p.win, vim.fn.winsaveview).topline)
  T.eq(31, api.nvim_win_get_cursor(p.win)[1]); T.eq(new, api.nvim_get_current_win())
  api.nvim_set_current_win(old)
  api.nvim_win_call(old, function() vim.fn.winrestview({ topline = 50, lnum = 51, col = 0 }) end)
  api.nvim_exec_autocmds("WinScrolled", { pattern = tostring(old) })
  T.eq(old, p.source); T.eq(50, api.nvim_win_call(p.win, vim.fn.winsaveview).topline)
  -- Pending windows participate even before they become the latest snapshot.
  p.snapshot = { windows = { old = old } }
  p.pending = { source = new, scope = "file", row = 31, windows = { old = old, new = new } }
  p:set(result, "Pending · collecting")
  motion(new, "60G"); T.eq(new, p.source); T.eq({ 2 }, p.rows[43])
  T.eq(result, p.result)
  p:close(); T.eq(true, vim.wo[old].diff); T.eq(true, vim.wo[new].diff); vim.cmd("diffoff!")
end)

T.test("multi-hunk summaries prefer changed lines within anchors, preserving unchanged and deletion references", function()
  setup({ "" })
  local fixture = dofile("tests/multihunk.lua").open()
  local original = vim.deepcopy(fixture.result)
  local p = ui.open(fixture.new, { windows = { old = fixture.old, new = fixture.new } }, fixture.result)
  T.eq({ row = 10 }, p.locations[1])
  T.eq({ row = 38 }, p.locations[2])
  T.eq({ row = 55 }, p.locations[3])
  T.eq({ row = 74 }, p.locations[4])
  T.eq({ row = 75, offset = -2 }, p.locations[5])
  T.eq({ row = 82 }, p.locations[6])
  T.eq("[new:37–38] ", p.references[38])
  T.eq("[old:49–52 ↔ new:53–56] ", p.references[55])
  T.eq({}, p.rows[37]); T.eq({ 2 }, p.rows[38])
  api.nvim_win_call(fixture.new, function() vim.cmd("normal! 38Gzt") end)
  p:align()
  local refs = 0
  for _, m in ipairs(marks(p, "explainr.ranges")) do
    if m[2] == 37 then refs = refs + 1; T.eq("[new:37–38] ", m[4].virt_text[1][1]) end
  end
  T.eq(1, refs) -- No redundant continuation rail on the summary itself.
  api.nvim_set_current_win(p.win)
  p:jump(1); T.eq(55, api.nvim_win_get_cursor(p.win)[1])
  key(p.buf, "<CR>"); T.eq(3, p.detail_index)
  local active_ns = api.nvim_get_namespaces()["explainr.detail." .. p.win]
  for side, range in pairs({ old = { 49, 52 }, new = { 53, 56 } }) do
    local source_buf = api.nvim_win_get_buf(fixture[side])
    local active = api.nvim_buf_get_extmarks(source_buf, active_ns, 0, -1, {})
    T.eq(range[2] - range[1] + 1, #active)
    T.eq(range[1] - 1, active[1][2]); T.eq(range[2] - 1, active[#active][2])
  end
  key(p.detail_buf, "<CR>"); T.eq(55, api.nvim_win_get_cursor(p.win)[1])
  p:sync(fixture.old)
  T.eq({ row = 10, offset = -3 }, p.locations[1])
  T.eq({ row = 35, offset = -1 }, p.locations[2])
  T.eq({ row = 51 }, p.locations[3])
  T.eq({ row = 70 }, p.locations[4])
  T.eq({ row = 71 }, p.locations[5])
  T.eq({ row = 80 }, p.locations[6])
  T.eq(original, p.result) -- Placement never rewrites accepted anchors.
  p:close(); vim.cmd("diffoff!")
end)

T.test("multiple hunks remain screen-aligned through closed folds, unfolding and scrolling on either side", function()
  setup({ "" })
  local fixture = dofile("tests/multihunk.lua").open()
  local p = ui.open(fixture.new, { windows = { old = fixture.old, new = fixture.new } }, fixture.result)
  for _, mode in ipairs({ "zM", "zR", "zM" }) do
    for _, source in ipairs({ fixture.old, fixture.new }) do
      api.nvim_win_call(source, function() vim.cmd("normal! " .. mode) end)
    end
    for _, source in ipairs({ fixture.old, fixture.new }) do
      for _, top in ipairs({ 1, 9, 34, 49, 69, 80, 100, 49, 34 }) do
        api.nvim_win_call(source, function() vim.cmd("normal! " .. top .. "Gzt") end)
        p:sync(source); vim.cmd("redraw!")
        for _, item in ipairs(p.projection) do
          if not item.empty and not item.filler then
            local source_row = vim.fn.screenpos(source, item.line, 1).row
            assert(source_row > 0, "projected text row must be visible")
            T.eq(source_row, vim.fn.screenpos(p.win, item.line, 1).row)
          end
        end
      end
    end
  end
  p:close(); vim.cmd("diffoff!")
end)

T.test("notes j k traverse insertions and deletions instead of skipping virtual diff rows", function()
  local old = setup({ "first", "before", "removed one", "removed two", "after", "tail" })
  vim.cmd("belowright vsplit"); local new = api.nvim_get_current_win()
  local buf = api.nvim_create_buf(false, true); api.nvim_win_set_buf(new, buf)
  api.nvim_buf_set_lines(buf, 0, -1, false, { "first", "inserted one", "inserted two", "before", "after", "tail" })
  for _, candidate in ipairs({ old, new }) do
    api.nvim_win_call(candidate, function() vim.cmd("diffthis | normal! zR") end)
  end
  vim.cmd("diffupdate")
  local p = ui.open(old, { windows = { old = old, new = new } },
    { notes = { note(2, "Insertion", "new"), note(3, "Deletion", "old") } })
  api.nvim_set_current_win(p.win)
  key(p.buf, "j")
  T.eq(new, p.source); T.eq(2, api.nvim_win_get_cursor(p.win)[1]); T.eq({ 1 }, p.rows[2])
  key(p.buf, "K"); assert(detail_lines(p)[1]:find("Insertion", 1, true))
  key(p.detail_buf, "q")
  api.nvim_exec_autocmds("WinScrolled", { pattern = tostring(old) })
  T.eq(new, p.source); T.eq(2, api.nvim_win_get_cursor(p.win)[1])
  p:move(1, 3)
  T.eq(old, p.source); T.eq(3, api.nvim_win_get_cursor(p.win)[1]); T.eq({ 2 }, p.rows[3])
  key(p.buf, "K"); assert(detail_lines(p)[1]:find("Deletion", 1, true))
  key(p.detail_buf, "q")
  key(p.buf, "j"); T.eq(4, api.nvim_win_get_cursor(p.win)[1])
  key(p.buf, "k"); T.eq(3, api.nvim_win_get_cursor(p.win)[1])
  p:move(-1, 3); T.eq(new, p.source); T.eq(2, api.nvim_win_get_cursor(p.win)[1])
  key(p.buf, "k"); T.eq(1, api.nvim_win_get_cursor(p.win)[1])
  p:close(); vim.cmd("diffoff!")
end)

T.test("diff line motion counts folds once and reaches added lines at EOF without wrapping", function()
  local before = {}; for row = 1, 12 do before[row] = "line " .. row end
  local old = setup(before)
  vim.cmd("belowright vsplit"); local new = api.nvim_get_current_win()
  local buf = api.nvim_create_buf(false, true); api.nvim_win_set_buf(new, buf)
  local after = vim.deepcopy(before); after[13], after[14] = "added at EOF", "last addition"
  api.nvim_buf_set_lines(buf, 0, -1, false, after)
  for _, candidate in ipairs({ old, new }) do
    api.nvim_win_call(candidate, function()
      vim.cmd("diffthis | normal! zR")
      vim.wo.foldmethod = "manual"; vim.wo.foldenable = true; vim.cmd("4,6fold")
    end)
  end
  vim.cmd("diffupdate")
  local p = ui.open(old, { windows = { old = old, new = new } }, { notes = { note(13, "Added tail", "new") } })
  api.nvim_set_current_win(p.win); api.nvim_win_set_cursor(p.win, { 3, 0 }); p:sync(p.win)
  key(p.buf, "j"); T.eq(4, api.nvim_win_get_cursor(p.win)[1])
  key(p.buf, "j"); T.eq(7, api.nvim_win_get_cursor(p.win)[1])
  key(p.buf, "k"); T.eq(4, api.nvim_win_get_cursor(p.win)[1])
  p:move(1, 5); T.eq(11, api.nvim_win_get_cursor(p.win)[1])
  p:move(1, 2); T.eq(new, p.source); T.eq(13, api.nvim_win_get_cursor(p.win)[1])
  key(p.buf, "j"); T.eq(14, api.nvim_win_get_cursor(p.win)[1])
  key(p.buf, "j"); T.eq(14, api.nvim_win_get_cursor(p.win)[1])
  p:move(-1, 10); T.eq(2, api.nvim_win_get_cursor(p.win)[1])
  p:close(); vim.cmd("diffoff!")
end)

T.test("status stays above content when the viewport begins inside diff filler", function()
  local old = setup({ "first", "removed one", "removed two", "removed three", "last", "tail" })
  vim.cmd("belowright vsplit"); local new = api.nvim_get_current_win()
  local buf = api.nvim_create_buf(false, true); api.nvim_win_set_buf(new, buf)
  api.nvim_buf_set_lines(buf, 0, -1, false, { "first", "last", "tail" })
  for _, candidate in ipairs({ old, new }) do
    api.nvim_win_call(candidate, function() vim.cmd("diffthis | normal! zR") end)
  end
  vim.cmd("diffupdate")
  local p = ui.open(new, { windows = { old = old, new = new },
    context = { strategy = "focused", radius = 20, omitted_files = { "omitted.lua" } } },
    { notes = { note(3, "Deletion", "old") } })
  api.nvim_win_set_width(p.win, 80); p:render()
  api.nvim_win_call(new, function() vim.fn.winrestview({ topline = 2, topfill = 2, lnum = 2, col = 0 }) end)
  p:align()
  local first
  for _, m in ipairs(marks(p, "explainr.geometry")) do
    if m[2] == 1 and m[4].virt_lines_above then
      local lines = m[4].virt_lines
      first = lines[#lines - 1]
    end
  end
  assert(first, "the first visible filler row must exist")
  local text = table.concat(vim.tbl_map(function(chunk) return chunk[1] end, first))
  assert(not text:find("Focused", 1, true), "status must not be in a filler row")
  assert(state(p):find("Focused ±20", 1, true), "status must remain in the reserved header")
  assert(text:find("[old:3]", 1, true), "annotation content must remain intact")
  T.eq({}, marks(p, "explainr.state"))
  p:close(); vim.cmd("diffoff!")
end)

T.test("large deletion filler has bounded animated geometry and source closure cleans hidden overview", function()
  local before = { "first" }; for row = 2, 1001 do before[row] = "removed " .. row end
  before[1002] = "last"
  local old = setup(before)
  vim.cmd("belowright vsplit"); local new = api.nvim_get_current_win()
  local buf = api.nvim_create_buf(false, true); api.nvim_win_set_buf(new, buf)
  api.nvim_buf_set_lines(buf, 0, -1, false, { "first", "last" })
  for _, candidate in ipairs({ old, new }) do api.nvim_win_call(candidate, function() vim.cmd("diffthis | normal! zR") end) end
  vim.cmd("diffupdate")
  local deletion = note(2, "Deletion", "old"); deletion.anchors[1].end_line = 1001
  local p = ui.open(new, { windows = { old = old, new = new } }, { notes = { deletion } })
  p.pending = { source = old, scope = "hunk", row = 2, windows = { old = old, new = new },
    snapshot = { target = { anchors = deletion.anchors } } }
  api.nvim_win_call(new, function() vim.fn.winrestview({ topline = 2, topfill = 1000, lnum = 2, col = 0 }) end)
  p:set(p.result, "Pending · deletion")
  local count, animated = 0, false
  for _, m in ipairs(marks(p, "explainr.geometry")) do
    for _, row in ipairs(m[4].virt_lines or {}) do
      count = count + 1
      if type(row[1][2]) == "table" and row[1][2][1]:match("^ExplainrLoadingRail") then
        animated = true
        local text = table.concat(vim.tbl_map(function(chunk) return chunk[1] end, row))
        T.eq(api.nvim_win_get_width(p.win) - vim.fn.getwininfo(p.win)[1].textoff, vim.fn.strdisplaywidth(text))
      end
    end
  end
  T.eq({}, marks(p, "explainr.loading")) -- Filler-only request must not animate the surviving logical row.
  assert(animated); assert(count <= 2 * api.nvim_win_get_height(new))
  local tick, frame = api.nvim_buf_get_changedtick(p.buf), p.frame
  assert(vim.wait(500, function() return p.frame ~= frame end)); T.eq(tick, api.nvim_buf_get_changedtick(p.buf))
  key(p.buf, "K"); local summary_buf, detail_buf = p.buf, p.detail_buf
  -- Closing the opposite source is also terminal, while summary is hidden.
  api.nvim_win_close(old, true); assert(vim.wait(500, function() return p.closed end))
  T.eq(false, api.nvim_buf_is_valid(summary_buf)); T.eq(false, api.nvim_buf_is_valid(detail_buf)); T.eq(nil, p.timer)
  vim.cmd("diffoff!")
end)

-- Opt in by adding render-markdown + parser directories to runtimepath and
-- sourcing its normal plugin entrypoint before tests/run.lua. No setup needed.
if vim.g.loaded_render_markdown then
  T.test("Markdown detail preserves JSON code escapes and renders inline and fenced code", function()
    local win = setup({ 'return user.role == "editor"' })
    local snapshot = { mode = "code", windows = { buffer = win },
      files = { { path = "test.lua", side = "buffer", lines = { 'return user.role == "editor"' } } },
      target = { anchors = { { path = "test.lua", side = "buffer", start_line = 1, end_line = 1 } } } }
    local result = assert(require("explainr.model").validate([[{"version":1,"notes":[{
      "summary":"Checks the editor role","detail":"Reads `user.role`.\n\n```lua\nreturn user.role == \"editor\"\n```\n\nA literal backslash: `\\`.",
      "anchors":[{"path":"test.lua","side":"buffer","start_line":1,"end_line":1}],
      "intent_basis":"inferred","evidence":[]}]}]], snapshot))
    local expected = 'Reads `user.role`.\n\n```lua\nreturn user.role == "editor"\n```\n\nA literal backslash: `\\`.'
    T.eq(expected, result.notes[1].detail)
    local p = ui.open(win, snapshot, result)
    p:detail()
    T.eq(expected, table.concat(vim.list_slice(detail_lines(p), 4, #detail_lines(p) - 1), "\n"))
    local ns = api.nvim_get_namespaces()["render-markdown.nvim"]
    assert(vim.wait(1000, function()
      local inline, block = false, false
      for _, m in ipairs(api.nvim_buf_get_extmarks(p.detail_buf, ns, 0, -1, { details = true })) do
        if m[2] == 3 and m[4].hl_group == "RenderMarkdownCodeInline" then inline = true end
        if m[2] == 6 and m[4].hl_group == "RenderMarkdownCode" then block = true end
      end
      return inline and block
    end), "inline code and fenced snippet must both be styled")
    api.nvim__inspect_cell(1, 0, 0)
    vim.cmd("redraw")
    local code = vim.fn.screenpos(p.detail_win, 7, 8) -- Plain identifier after 'return '.
    local info = vim.fn.getwininfo(p.detail_win)[1]
    local text_bg = api.nvim__inspect_cell(1, code.row - 1, code.col - 1)[2].background
    local eol_bg = api.nvim__inspect_cell(1, code.row - 1, info.wincol + info.width - 2)[2].background
    T.eq(api.nvim_get_hl(0, { name = "RenderMarkdownCode", link = false }).bg, text_bg)
    T.eq(text_bg, eol_bg) -- Same code background behind text and EOL, despite syntax foregrounds.
    p:close()
  end)

  T.test("installed renderer really renders first frame and scrolls detail without changing summary rows", function()
    local win = setup({ "one", "two", "three" })
    local n = note(1, "==Marked== **bold**")
    n.detail = string.rep("## Reason\n\nA **semantic** explanation.\n\n", 40)
    local next_note = note(3, "A **short** follow-up")
    next_note.detail = "The **second** explanation replaces the long first one."
    local p = ui.open(win, { windows = { buffer = win } }, { notes = { n, next_note } })
    local ns = api.nvim_get_namespaces()["render-markdown.nvim"]
    assert(ns)
    local function marks(buf) return api.nvim_buf_get_extmarks(buf, ns, 0, -1, { details = true }) end
    assert(vim.wait(1000, function() return #marks(p.buf) > 0 end), "summary renderer never drew marks")
    for _, m in ipairs(marks(p.buf)) do assert(not m[4].virt_lines and not m[4].conceal_lines) end
    T.eq(false, vim.wo[p.win].wrap)
    T.eq(3, api.nvim_buf_line_count(p.buf))
    T.eq(1, api.nvim_win_text_height(p.win, { start_row = 0, end_row = 0 }).all)
    local projection, rows = vim.deepcopy(p.projection), vim.deepcopy(p.rows)
    p:detail(); local detail = api.nvim_win_get_buf(p.detail_win)
    assert(vim.wait(1000, function() return #marks(detail) > 0 and vim.wo[p.detail_win].conceallevel == 3 end),
      "first detail render was swallowed by automatic attachment")
    api.nvim_win_call(p.detail_win, function() vim.cmd.normal({ p.detail_layout.last .. "G", bang = true }) end)
    api.nvim_exec_autocmds("WinScrolled", { buffer = detail })
    assert(vim.wait(1000, function()
      for _, m in ipairs(marks(detail)) do if m[2] > 100 then return true end end
      return false
    end), "renderer did not follow detail scrolling")
    p:render(); T.eq(projection, p.projection); T.eq(rows, p.rows)
    local handlers = #api.nvim_get_autocmds({ group = p.group })
    key(detail, "n"); T.eq(detail, p.detail_buf); T.eq(3, api.nvim_win_get_cursor(win)[1])
    assert(vim.wait(1000, function()
      local current = marks(detail)
      if #current == 0 then return false end
      for _, mark in ipairs(current) do if mark[2] >= p.detail_layout.last then return false end end
      return true
    end), "renderer retained decorations from the previous long explanation")
    assert(detail_lines(p)[4]:find("second", 1, true))
    key(detail, "p"); T.eq(detail, p.detail_buf); T.eq(1, api.nvim_win_get_cursor(win)[1])
    T.eq(handlers, #api.nvim_get_autocmds({ group = p.group }))
    T.eq(n.detail, table.concat(vim.list_slice(detail_lines(p), 4, #detail_lines(p) - 1), "\n"))
    local detail_win = p.detail_win; p:back()
    T.eq(p.win, detail_win); T.eq(false, api.nvim_buf_is_valid(detail))
    T.eq(p.buf, api.nvim_win_get_buf(p.win)); T.eq(false, vim.wo[p.win].wrap)
    p:close(); T.eq(false, api.nvim_win_is_valid(detail_win))
  end)
end
