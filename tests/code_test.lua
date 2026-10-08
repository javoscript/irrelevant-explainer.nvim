local code = require("explainr.code")
local api = vim.api
local block, esc = string.char(22), string.char(27)

local function buffer(lines, ft, run)
  local previous = api.nvim_get_current_buf()
  local buf = api.nvim_create_buf(false, false)
  api.nvim_set_current_buf(buf)
  if lines then api.nvim_buf_set_lines(buf, 0, -1, false, lines) end
  vim.bo[buf].filetype = ft or ""
  local selection, virtualedit = vim.o.selection, vim.o.virtualedit
  vim.o.selection, vim.o.virtualedit = "inclusive", ""
  local ok, err = xpcall(function() run(buf, api.nvim_get_current_win()) end, debug.traceback)
  vim.cmd("normal! " .. esc)
  vim.o.selection, vim.o.virtualedit = selection, virtualedit
  api.nvim_set_current_buf(previous)
  api.nvim_buf_delete(buf, { force = true })
  assert(ok, err)
end

local function collect(scope, selection, win)
  local snapshot, err = code.collect(win or 0, scope, selection)
  assert(snapshot, err)
  return snapshot
end

local function selected(kind, first, last, exclusive)
  return collect("selection", { type = kind, pos1 = first, pos2 = last, exclusive = exclusive })
end

local function anchor(snapshot, first, last)
  T.eq({ { path = snapshot.files[1].path, side = "buffer", start_line = first, end_line = last } }, snapshot.target.anchors)
end

T.test("code file captures unsaved text and immutable complete context", function()
  buffer({ "saved-looking", "unsaved edit", "" }, nil, function(buf, win)
    local name = vim.fn.getcwd() .. "/unsaved-code-fixture.lua"
    api.nvim_buf_set_name(buf, name) -- No disk file is needed or read.
    local s = collect("file")
    T.eq("code", s.mode)
    T.eq(name, s.files[1].path)
    T.eq("buffer", s.files[1].side)
    T.eq({ "saved-looking", "unsaved edit", "" }, s.files[1].lines)
    T.eq("saved-looking\nunsaved edit\n", s.target.text)
    T.eq({ buffer = win }, s.windows)
    T.eq(buf, s.source_buf)
    T.eq(api.nvim_buf_get_changedtick(buf), s.changedtick)
    T.eq(vim.fn.getcwd(), s.cwd)
    anchor(s, 1, 3)
    T.eq(true, code.fresh(s))
    api.nvim_buf_set_lines(buf, 1, 2, false, { "later edit" })
    T.eq("unsaved edit", s.files[1].lines[2])
    T.eq(false, code.fresh(s))
  end)
end)

T.test("code unnamed identity and empty buffer differ from one blank line", function()
  buffer(nil, nil, function(buf)
    local empty = collect("file")
    T.eq("[buffer:" .. buf .. "]", empty.files[1].path)
    T.eq({ "" }, empty.files[1].lines)
    T.eq(true, empty.files[1].empty)
    T.eq({}, empty.target.spans)
    T.eq({}, empty.target.anchors)
    T.eq("", empty.target.text)
    api.nvim_buf_set_lines(buf, 0, -1, false, { "" })
    local blank = collect("file")
    T.eq(false, blank.files[1].empty)
    anchor(blank, 1, 1)
    T.eq({ { { buf, 1, 1, 0 }, { buf, 1, 1, 0 } } }, blank.target.spans)
    assert(empty.fingerprint ~= blank.fingerprint)
    T.eq(false, code.fresh(empty))
  end)
end)

T.test("code fingerprints are stable but bind contents and exact target", function()
  buffer({ "abcdef", "context" }, nil, function(buf)
    local file = collect("file")
    T.eq(file.fingerprint, collect("file").fingerprint)
    local a = selected("v", { 0, 1, 2, 0 }, { 0, 1, 4, 0 }, false)
    local b = selected("v", { 0, 1, 4, 0 }, { 0, 1, 2, 0 }, false)
    T.eq(a.fingerprint, b.fingerprint)
    assert(file.fingerprint ~= a.fingerprint)
    assert(a.fingerprint ~= selected("v", { 0, 1, 3, 0 }, { 0, 1, 4, 0 }, false).fingerprint)
    api.nvim_buf_set_lines(buf, 1, 2, false, { "changed context" })
    assert(a.fingerprint ~= selected("v", { 0, 1, 2, 0 }, { 0, 1, 4, 0 }, false).fingerprint)
    api.nvim_buf_set_lines(buf, 1, 2, false, { "context" })
    T.eq(file.fingerprint, collect("file").fingerprint)
    T.eq(false, code.fresh(file)) -- Reverting text does not restore the tick.
  end)
end)

T.test("code reversed character selection retains exact multibyte spans", function()
  buffer({ "aé中z", "xyéq", "context" }, nil, function(buf)
    local s = selected("v", { 0, 2, 3, 0 }, { 0, 1, 2, 0 }, false)
    T.eq("é中z\nxyé", s.target.text)
    T.eq({ { { buf, 1, 2, 0 }, { buf, 1, 8, 0 } },
      { { buf, 2, 1, 0 }, { buf, 2, 4, 0 } } }, s.target.spans)
    anchor(s, 1, 2)
    T.eq({ "aé中z", "xyéq", "context" }, s.files[1].lines)
  end)
end)

T.test("code exclusive character selection uses Vim boundaries", function()
  buffer({ "aé中z", "next" }, nil, function(buf)
    local s = selected("v", { 0, 1, 2, 0 }, { 0, 1, 7, 0 }, true)
    T.eq("é中", s.target.text)
    T.eq({ { { buf, 1, 2, 0 }, { buf, 1, 6, 0 } } }, s.target.spans)
    local to_next = selected("v", { 0, 1, 2, 0 }, { 0, 2, 1, 0 }, true)
    T.eq("é中z", to_next.target.text)
    anchor(to_next, 1, 1)
    vim.o.selection = "exclusive"
    T.eq(s.target.spans, selected("v", { 0, 1, 2, 0 }, { 0, 1, 7, 0 }).target.spans)
  end)
end)

T.test("code reversed linewise selection includes blank lines", function()
  buffer({ "abc", "", "éz", "outside" }, nil, function(buf)
    local s = selected("V", { 0, 3, 3, 0 }, { 0, 1, 2, 0 }, false)
    T.eq("abc\n\néz", s.target.text)
    T.eq({ { { buf, 1, 1, 0 }, { buf, 1, 4, 0 } },
      { { buf, 2, 1, 0 }, { buf, 2, 1, 0 } },
      { { buf, 3, 1, 0 }, { buf, 3, 4, 0 } } }, s.target.spans)
    anchor(s, 1, 3)
  end)
end)

T.test("code reversed block selection preserves partial wide characters", function()
  buffer({ "aé中z", "xyéq", "12345" }, nil, function(buf)
    local s = selected(block, { 0, 3, 3, 0 }, { 0, 1, 2, 0 }, false)
    T.eq("é \nyé\n23", s.target.text)
    T.eq({ { { buf, 1, 2, 0 }, { buf, 1, 4, 1 } },
      { { buf, 2, 2, 0 }, { buf, 2, 4, 0 } },
      { { buf, 3, 2, 0 }, { buf, 3, 3, 0 } } }, s.target.spans)
    anchor(s, 1, 3)
  end)
end)

T.test("code block selections retain tab virtual columns and padding", function()
  buffer({ "\talpha", "0123456789", "x" }, nil, function(buf)
    vim.bo[buf].tabstop = 8
    vim.o.virtualedit = "block"
    local local_ve = api.nvim_get_option_value("virtualedit", { scope = "local", win = 0 })
    local s = selected(block, { 0, 3, 2, 4 }, { 0, 1, 1, 2 }, false)
    T.eq("    \n2345\n    ", s.target.text)
    T.eq({ { { buf, 1, 1, 2 }, { buf, 1, 1, 6 } },
      { { buf, 2, 3, 0 }, { buf, 2, 6, 0 } },
      { { buf, 3, 2, 1 }, { buf, 3, 2, 5 } } }, s.target.spans)
    T.eq(local_ve, api.nvim_get_option_value("virtualedit", { scope = "local", win = 0 }))
    T.eq("block", vim.wo.virtualedit)
  end)
end)

T.test("code live and Ex block captures agree on retained tab offsets", function()
  buffer({ "\talpha", "0123456789" }, nil, function(buf)
    vim.bo[buf].tabstop = 8
    vim.o.virtualedit = "block"
    api.nvim_win_set_cursor(0, { 1, 0 })
    vim.cmd("normal! " .. block)
    vim.fn.setpos(".", { 0, 1, 1, 2 })
    vim.cmd("normal! o")
    vim.fn.setpos(".", { 0, 2, 6, 0 })
    local live = collect("selection")
    local expected = { { { buf, 1, 1, 2 }, { buf, 1, 1, 6 } },
      { { buf, 2, 3, 0 }, { buf, 2, 6, 0 } } }
    T.eq("    \n2345", live.target.text)
    T.eq(expected, live.target.spans)
    T.eq(block, vim.fn.mode())
    vim.cmd("normal! " .. esc)
    local from_marks = collect("selection")
    T.eq("    \n2345", from_marks.target.text)
    T.eq(expected, from_marks.target.spans)
    T.eq(live.fingerprint, from_marks.fingerprint)
    T.eq("block", vim.wo.virtualedit)
  end)
end)

T.test("code restores virtualedit even if region evaluation fails", function()
  buffer({ "\talpha" }, nil, function()
    vim.o.virtualedit = "block"
    local original = vim.fn.getregion
    vim.fn.getregion = function() error("fixture region failure") end
    local ok, s, err = pcall(code.collect, 0, "selection", {
      type = block, pos1 = { 0, 1, 1, 2 }, pos2 = { 0, 1, 1, 4 } })
    vim.fn.getregion = original
    T.eq(true, ok)
    T.eq(nil, s)
    assert(err:find("fixture region failure", 1, true), err)
    T.eq("block", vim.wo.virtualedit)
    T.eq("", api.nvim_get_option_value("virtualedit", { scope = "local", win = 0 }))
  end)
end)

T.test("code empty selection and invalid descriptors return errors", function()
  buffer({ "" }, nil, function()
    local s, err = code.collect(0, "selection", { type = "v", pos1 = { 0, 1, 1, 0 }, pos2 = { 0, 1, 1, 0 } })
    T.eq(nil, s)
    assert(err:find("no selected code", 1, true), err)
    s, err = code.collect(0, "selection", { type = "v", pos1 = { 0, 0, 0, 0 }, pos2 = { 0, 1, 1, 0 } })
    T.eq(nil, s)
    assert(err:find("unset or outside", 1, true), err)
    s = code.collect(0, "selection", { type = "v", pos1 = { 999999, 1, 1, 0 }, pos2 = { 0, 1, 1, 0 } })
    T.eq(nil, s)
    T.eq(nil, code.collect(-1, "file"))
    T.eq(nil, code.collect(0, "bogus"))
  end)
end)

T.test("code live Visual state uses current endpoints rather than stale marks", function()
  buffer({ "abcdef", "ghijkl" }, nil, function(buf)
    api.nvim_buf_set_mark(buf, "<", 2, 0, {})
    api.nvim_buf_set_mark(buf, ">", 2, 5, {})
    api.nvim_win_set_cursor(0, { 1, 1 })
    vim.cmd("normal! v2l")
    local s = collect("selection")
    T.eq("bcd", s.target.text)
    T.eq({ { { buf, 1, 2, 0 }, { buf, 1, 4, 0 } } }, s.target.spans)
    T.eq("v", vim.fn.mode()) -- Collection doesn't end Visual mode.
  end)
end)

T.test("code Ex-invoked marks preserve character line and block shapes", function()
  buffer({ "abcde", "vwxyz" }, nil, function(buf)
    for _, case in ipairs({
      { keys = "vjl", text = "bcde\nvwx", spans = {
        { { buf, 1, 2, 0 }, { buf, 1, 6, 0 } }, { { buf, 2, 1, 0 }, { buf, 2, 3, 0 } } } },
      { keys = "Vj", text = "abcde\nvwxyz", spans = {
        { { buf, 1, 1, 0 }, { buf, 1, 6, 0 } }, { { buf, 2, 1, 0 }, { buf, 2, 6, 0 } } } },
      { keys = block .. "lj", text = "bc\nwx", spans = {
        { { buf, 1, 2, 0 }, { buf, 1, 3, 0 } }, { { buf, 2, 2, 0 }, { buf, 2, 3, 0 } } } },
    }) do
      api.nvim_win_set_cursor(0, { 1, 1 })
      vim.cmd("normal! " .. case.keys .. esc)
      _G.explainr_code_ex_capture = function() return collect("selection") end
      vim.cmd("'<,'>lua _G.explainr_code_ex_result = _G.explainr_code_ex_capture()")
      local s = _G.explainr_code_ex_result
      _G.explainr_code_ex_capture, _G.explainr_code_ex_result = nil, nil
      T.eq(case.text, s.target.text)
      T.eq(case.spans, s.target.spans)
    end
  end)
end)

T.test("code freshness binds window buffer name eol and current contents", function()
  buffer({ "same" }, nil, function(buf, win)
    local s = collect("file")
    local other = api.nvim_create_buf(false, false)
    api.nvim_buf_set_lines(other, 0, -1, false, { "same" })
    api.nvim_win_set_buf(win, other)
    T.eq(false, code.fresh(s))
    api.nvim_win_set_buf(win, buf)
    api.nvim_buf_delete(other, { force = true })
    T.eq(true, code.fresh(s))
    vim.bo[buf].endofline = false
    T.eq(false, code.fresh(s))
    vim.bo[buf].endofline = true
    api.nvim_buf_set_name(buf, vim.fn.getcwd() .. "/renamed-code-fixture.lua")
    T.eq(false, code.fresh(s))
    local copy = vim.deepcopy(collect("file"))
    copy.files[1].lines[1] = "different"
    T.eq(false, code.fresh(copy))
    T.eq(false, code.fresh(nil))
  end)
end)

T.test("code collection uses specified noncurrent window and detects its closure", function()
  buffer({ "original" }, nil, function(buf)
    local original = api.nvim_get_current_win()
    vim.cmd("vsplit")
    local win = api.nvim_get_current_win()
    api.nvim_set_current_win(original)
    local s = collect("file", nil, win)
    T.eq({ buffer = win }, s.windows)
    T.eq(original, api.nvim_get_current_win())
    T.eq(true, code.fresh(s))
    api.nvim_win_close(win, true)
    T.eq(false, code.fresh(s))
    T.eq(buf, s.source_buf)
  end)
end)

T.test("code rejects retired scopes without parser lookup and file or selection still work", function()
  buffer({ "local function inner()", "  return 1", "end", "outside" }, "lua", function()
    local get_parser, get_query = vim.treesitter.get_parser, vim.treesitter.query.get
    local lookups = 0
    local function unexpected()
      lookups = lookups + 1
      error("unexpected parser/query lookup")
    end
    vim.treesitter.get_parser, vim.treesitter.query.get = unexpected, unexpected
    local ok, err = xpcall(function()
      api.nvim_win_set_cursor(0, { 2, 2 })
      for _, scope in ipairs({ "function", "class" }) do
        local snapshot, message = code.collect(0, scope)
        T.eq(nil, snapshot)
        assert(message:find("unsupported code scope: " .. scope, 1, true), message)
        assert(message:find("scopes were removed; use file or selection", 1, true), message)
      end
      T.eq("local function inner()\n  return 1\nend\noutside", collect("file").target.text)
      local selection = selected("V", { 0, 2, 1, 0 }, { 0, 3, 1, 0 }, false)
      T.eq("  return 1\nend", selection.target.text); anchor(selection, 2, 3)
      T.eq(0, lookups)
    end, debug.traceback)
    vim.treesitter.get_parser, vim.treesitter.query.get = get_parser, get_query
    assert(ok, err)
  end)
end)
