-- Optional compatibility boundary. Tested against Diffview 4516612fe98f.
-- Never load this module's dependency until an explicit diff request.
local M = {}
local api = vim.api

local function revision(rev)
  assert(type(rev) == "table", "missing Diffview revision metadata")
  if rev.type == 1 then return { type = "local" } end
  if rev.type == 2 then
    assert(type(rev.commit) == "string" and rev.commit:match("^%x+$"), "unresolved commit identity")
    return { type = "commit", commit = rev.commit, track_head = rev.track_head == true }
  end
  assert(rev.type == 3 and rev.stage == 0, "custom revisions and nonzero index stages are unsupported")
  return { type = "stage", stage = 0 }
end

local function pair(entry)
  assert(entry.kind ~= "conflicting" and entry.status ~= "U", "conflict comparisons are unsupported")
  local a, b = revision(entry.revs.a), revision(entry.revs.b)
  assert((a.type == "commit" and (b.type == "commit" or b.type == "stage" or b.type == "local"))
    or (a.type == "stage" and b.type == "local"), "unsupported or reversed comparison pair")
  return { old = a, new = b }
end

local function entry_info(entry)
  return { path = entry.path, oldpath = entry.oldpath or entry.path, status = entry.status, kind = entry.kind }
end

local function current(win)
  win = (win == nil or win == 0) and api.nvim_get_current_win() or win
  assert(api.nvim_win_is_valid(win), "source window is unavailable")
  local state
  api.nvim_win_call(win, function()
    local ok, lib = pcall(require, "diffview.lib")
    assert(ok, "Diffview is unavailable; code mode does not require it")
    local view = lib.get_current_view()
    assert(view and view.valid and not view.closing:check() and view.files and view.cur_entry,
      "no live Diffview comparison in the source tab")
    local entry, layout = view.cur_entry, view.cur_layout
    assert(entry.path ~= "null", "Diffview has no selected file")
    local selected_pair = pair(entry)
    assert(layout and layout.a and layout.b and not layout.c and not layout.d,
      "only two-way Diffview layouts are supported")
    local roles = {}
    require("diffview.actions").view_windo(function(name, symbol)
      assert(symbol == "a" or symbol == "b", "unsupported Diffview role")
      roles[symbol] = { win = api.nvim_get_current_win(), buf = api.nvim_get_current_buf(), layout = name }
    end)()
    assert(roles.a and roles.b and (win == roles.a.win or win == roles.b.win),
      "request must follow a Diffview source pane (not the file panel or notes)")
    local panes, windows = {}, {}
    for symbol, side in pairs({ a = "old", b = "new" }) do
      local role, file = roles[symbol], layout[symbol].file
      assert(entry.layout[symbol] and entry.layout[symbol].file == file and file.active
        and file.bufnr == role.buf and api.nvim_buf_is_loaded(role.buf),
        "Diffview panes are still loading or switching; retry after both panes load")
      assert(vim.deep_equal(revision(file.rev), selected_pair[side]), "mixed displayed revision pair")
      assert(file.path == (side == "old" and (entry.oldpath or entry.path) or entry.path),
        "mixed displayed file identities")
      windows[side] = role.win
      panes[side] = { buf = role.buf, path = file.path, nulled = file.nulled, binary = file.binary == true,
        lines = api.nvim_buf_get_lines(role.buf, 0, -1, false), tick = api.nvim_buf_get_changedtick(role.buf) }
    end
    local entries, stage_buffers = {}, {}
    for _, item in view.files:iter() do
      -- Other staged/working sets are deliberately not merged into this review.
      if item.kind == entry.kind then
        assert(vim.deep_equal(pair(item), selected_pair), "ambiguous mixed pairs in the selected file set")
        entries[#entries + 1] = entry_info(item)
      end
      for _, symbol in ipairs({ "a", "b" }) do
        local file = item.layout[symbol] and item.layout[symbol].file
        if file and file.rev.type == 3 and file.rev.stage == 0 and not file.nulled and not file.binary
          and file.bufnr and api.nvim_buf_is_loaded(file.bufnr) then
          local previous = stage_buffers[file.path]
          assert(not previous or previous == file.bufnr, "ambiguous index buffers")
          stage_buffers[file.path] = file.bufnr
        end
      end
    end
    if selected_pair.old.type == "stage" or selected_pair.new.type == "stage" then
      -- Stage buffers can survive a refresh or live in another view after
      -- their entry drops out of the displayed manifest. They still supply
      -- mutable stage-0 text, so don't lose nonfocused unsaved edits.
      local maps = require("diffview.vcs.file").File.index_bufmap
      local root = view.adapter.ctx.toplevel
      for path, buf in pairs(maps[root] or maps[vim.uv.fs_realpath(root)] or {}) do
        if api.nvim_buf_is_loaded(buf) then
          assert(not stage_buffers[path] or stage_buffers[path] == buf, "ambiguous index buffers")
          stage_buffers[path] = buf
        end
      end
    else
      stage_buffers = {}
    end
    table.sort(entries, function(a, b) return a.path < b.path end)
    state = { cwd = view.adapter.ctx.toplevel, pair = selected_pair, selected = entry_info(entry),
      entries = entries, path_args = vim.deepcopy(view.path_args or {}),
      -- Capture only editor policy here. Diffview's show_untracked() performs
      -- synchronous Git IO and pumps events inside this window snapshot.
      -- The collector resolves Git configuration asynchronously in each pass.
      show_untracked = selected_pair.old.type == "stage" and selected_pair.new.type == "local"
        and view.options.show_untracked ~= false,
      windows = windows, panes = panes, source = win,
      stage_buffers = stage_buffers, tabpage = view.tabpage }
  end)
  return state
end

function M.current(win)
  local ok, result = pcall(current, win)
  if ok then return result end
  return nil, "Diffview comparison unavailable: " .. tostring(result)
end

-- Selection is available before replacement panes finish loading. Navigation
-- must hide the previous file's notes without calling its content stale.
function M.selection(win)
  if not package.loaded["diffview.lib"] or not api.nvim_win_is_valid(win) then return end
  local ok, value = pcall(api.nvim_win_call, win, function()
    local view = package.loaded["diffview.lib"].get_current_view()
    if not view or not view.valid or view.closing:check() or not view.cur_entry then return end
    local selected_pair = pair(view.cur_entry)
    return { cwd = view.adapter.ctx.toplevel, pair = selected_pair,
      selected = entry_info(view.cur_entry), path_args = vim.deepcopy(view.path_args or {}),
      show_untracked = selected_pair.old.type == "stage" and selected_pair.new.type == "local"
        and view.options.show_untracked ~= false }
  end)
  if ok then return value end
end

-- Copy only navigation/explorer bindings, never attach notes to a diff layout.
-- Resolved configuration preserves custom RHS/options and disabled defaults.
function M.keymaps(buf)
  local lib = package.loaded["diffview.lib"]
  local view = lib and lib.get_current_view()
  if not view or view.closing:check() or not view.cur_layout then return end
  local config, actions = require("diffview.config"), require("diffview.actions")
  local wanted = { [actions.select_next_entry] = true, [actions.select_prev_entry] = true,
    [actions.focus_files] = true, [actions.toggle_files] = true }
  local keys = { ["<tab>"] = true, ["<s-tab>"] = true, ["<leader>e"] = true, ["<leader>b"] = true }
  local mappings = config.extend_keymaps(config.get_config().keymaps.view, config.get_layout_keymaps(view.cur_layout) or {})
  for _, mapping in ipairs(mappings) do
    local mode, lhs, rhs, opts = unpack(mapping)
    if mode == "n" and rhs and (wanted[rhs] or keys[lhs:lower()]) then
      vim.keymap.set(mode, lhs, rhs, vim.tbl_extend("force", { silent = true, nowait = true }, opts or {}, { buffer = buf }))
    end
  end
end

return M
