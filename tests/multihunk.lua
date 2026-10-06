-- Native multi-hunk diff, shared by row-alignment tests and screen captures.
local api = vim.api
local M = {}
function M.open()
  local before = {}
  for line = 1, 100 do before[line] = "-- unchanged context " .. line end
  before[9] = "local function prepare()"
  before[10] = "end"
  before[34], before[35], before[36] = "checkbox = {", "  checked = {},", "},"
  before[49], before[50], before[51], before[52] = "in_progress = {", '  raw = "[>]",', '  rendered = "tools",', "},"
  before[69], before[70], before[71], before[72], before[73] = "preview = {", "  lazy = true,",
    "  build = function()", "    install_custom_preview()", "},"
  local after = vim.deepcopy(before)
  for index, text in ipairs({ "  load_config()", "  load_theme()", "  load_keys()" }) do table.insert(after, 9 + index, text) end
  table.insert(after, 38, "  bullet = true,")
  after[55] = '  rendered = "play",'
  after[74] = '  build = ":call install()",'
  table.remove(after, 75); table.remove(after, 75)
  local old = api.nvim_get_current_win()
  api.nvim_buf_set_lines(0, 0, -1, false, before)
  vim.bo.filetype = "lua"
  vim.cmd("belowright vsplit")
  local new = api.nvim_get_current_win()
  api.nvim_win_set_buf(new, api.nvim_create_buf(false, true))
  api.nvim_buf_set_lines(0, 0, -1, false, after)
  vim.bo.filetype = "lua"
  for _, win in ipairs({ old, new }) do
    vim.wo[win].wrap, vim.wo[win].winbar = false, ""
    api.nvim_win_call(win, function() vim.cmd("diffthis | normal! zM") end)
  end
  vim.cmd("diffupdate")
  local function anchor(side, first, last)
    return { path = "config.lua", side = side, start_line = first, end_line = last }
  end
  local function note(summary, anchors)
    return { summary = summary, detail = "Explain the change without losing its source coordinates.",
      intent_basis = "inferred", evidence = {}, anchors = anchors }
  end
  return { old = old, new = new, result = { notes = {
    note("Load configuration before returning.", { anchor("new", 9, 12) }),
    note("Enable checkbox bullets.", { anchor("new", 37, 38) }),
    note("Use a play icon for in-progress tasks.", { anchor("old", 49, 52), anchor("new", 53, 56) }),
    note("Replace the custom preview build.", { anchor("old", 69, 73), anchor("new", 73, 75) }),
    note("Remove the custom installer.", { anchor("old", 71, 72) }),
    note("Unchanged context still applies.", { anchor("old", 80, 81) }),
  } } }
end
return M
