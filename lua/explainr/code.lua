local M = {}
local api = vim.api
local block = string.char(22)
local identity = require("explainr.identity")

local function path(buf)
  local name = api.nvim_buf_get_name(buf)
  return name == "" and "[unnamed]" or vim.fn.fnamemodify(name, ":p")
end

local function position(value, buf, lines)
  assert(type(value) == "table" and #value == 4, "selection positions must be {buffer, line, byte_column, offset}")
  for _, number in ipairs(value) do
    assert(type(number) == "number" and number % 1 == 0, "selection positions must contain integers")
  end
  assert(value[1] == 0 or value[1] == buf, "selection belongs to another buffer")
  assert(value[2] >= 1 and value[2] <= #lines and value[3] >= 1 and value[4] >= 0,
    "selection position is unset or outside the buffer")
  return { buf, value[2], value[3], value[4] }
end

local function region(buf, lines, selection)
  local kind = selection.type
  assert(kind == "v" or kind == "V" or (type(kind) == "string" and kind:match("^" .. block .. "%d*$")),
    "selection type must be v, V, or CTRL-V (optionally followed by a width)")
  assert(selection.exclusive == nil or type(selection.exclusive) == "boolean", "selection.exclusive must be boolean")
  local first = position(selection.pos1, buf, lines)
  local last = position(selection.pos2, buf, lines)
  local opts = { type = kind, exclusive = selection.exclusive }
  -- 'virtualedit=block' is inactive after Visual mode ends. Re-establish its
  -- region semantics for an Ex invocation/retained descriptor, then restore
  -- the exact local option (including an inherited global value).
  local local_ve = api.nvim_get_option_value("virtualedit", { scope = "local", win = 0 })
  local block_ve = kind:sub(1, 1) == block and vim.tbl_contains(vim.split(vim.wo.virtualedit, ","), "block")
  if block_ve then api.nvim_set_option_value("virtualedit", "all", { scope = "local", win = 0 }) end
  local ok, text, spans = pcall(function()
    local selected = vim.fn.getregion(first, last, opts)
    opts.eol = true
    return table.concat(selected, "\n"), vim.fn.getregionpos(first, last, opts)
  end)
  if block_ve then api.nvim_set_option_value("virtualedit", local_ve, { scope = "local", win = 0 }) end
  assert(ok, text)
  return text, spans
end

local function visual_selection()
  local kind = vim.fn.mode(1)
  if kind == "v" or kind == "V" or kind == block then
    return { type = kind, pos1 = vim.fn.getpos("v"), pos2 = vim.fn.getpos(".") }
  end
  return { type = vim.fn.visualmode(), pos1 = vim.fn.getpos("'<"), pos2 = vim.fn.getpos("'>") }
end

local function capture(win, scope, selection)
  assert(api.nvim_win_is_valid(win), "source window is unavailable")
  assert(scope == "file" or scope == "selection", "unsupported code scope: " .. tostring(scope))
  local buf = api.nvim_win_get_buf(win)
  assert(api.nvim_buf_is_loaded(buf) and vim.bo[buf].buftype == "", "source must be an ordinary loaded text buffer")
  return api.nvim_win_call(win, function()
    local tick = api.nvim_buf_get_changedtick(buf)
    local lines = api.nvim_buf_get_lines(buf, 0, -1, false)
    -- Neovim represents both an empty buffer and one blank line as {""}.
    local empty = #lines == 1 and lines[1] == "" and vim.fn.wordcount().bytes == 0
    local text, spans, descriptor
    if scope == "file" then
      text = table.concat(lines, "\n")
      if empty then spans = {}
      else
        text, spans = region(buf, lines, { type = "V", pos1 = { buf, 1, 1, 0 },
          pos2 = { buf, #lines, 1, 0 }, exclusive = false })
      end
    else
      descriptor = vim.deepcopy(selection or visual_selection())
      if descriptor.exclusive == nil then descriptor.exclusive = vim.o.selection == "exclusive" end
      text, spans = region(buf, lines, descriptor)
      assert(text ~= "", "there is no selected code")
    end
    local filename = path(buf)
    local anchors = {}
    if #spans > 0 then
      anchors[1] = { path = filename, side = "buffer", start_line = spans[1][1][2], end_line = spans[#spans][2][2] }
    end
    local file = { path = filename, side = "buffer", lines = lines, empty = empty, endofline = vim.bo[buf].endofline }
    local target = { anchors = anchors, scope = scope, spans = spans, text = text, selection = descriptor }
    local cwd = vim.fn.getcwd()
    assert(api.nvim_buf_get_changedtick(buf) == tick and api.nvim_win_get_buf(win) == buf,
      "source changed during collection")
    return {
      mode = "code", files = { file }, target = target, windows = { buffer = win },
      source_buf = buf, changedtick = tick, cwd = cwd,
      fingerprint = identity.hash({ filename, lines, empty, file.endofline, identity.target(target), cwd }),
    }
  end)
end

function M.collect(win, scope, selection)
  win = win == 0 and api.nvim_get_current_win() or win
  local ok, result = pcall(capture, win, scope, selection)
  if ok then return result end
  local hint = (scope == "function" or scope == "class")
    and "; function/class scopes were removed; use file or selection scope with an explicit Visual region instead" or ""
  return nil, "Code collection failed: " .. tostring(result) .. hint
end

function M.fresh(snapshot)
  local ok, result = pcall(function()
    local buf, win = snapshot.source_buf, snapshot.windows.buffer
    if snapshot.mode ~= "code" or not api.nvim_win_is_valid(win) or not api.nvim_buf_is_loaded(buf)
      or api.nvim_win_get_buf(win) ~= buf or api.nvim_buf_get_changedtick(buf) ~= snapshot.changedtick then
      return false
    end
    local file = snapshot.files[1]
    return api.nvim_win_call(win, function()
      local lines = api.nvim_buf_get_lines(buf, 0, -1, false)
      local empty = #lines == 1 and lines[1] == "" and vim.fn.wordcount().bytes == 0
      return path(buf) == file.path and vim.deep_equal(lines, file.lines) and empty == file.empty
        and vim.bo[buf].endofline == file.endofline and vim.fn.getcwd() == snapshot.cwd
    end)
  end)
  return ok and result == true
end

return M
