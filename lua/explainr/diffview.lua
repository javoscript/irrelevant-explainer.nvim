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

-- Whole-review actions belong to the comparison, not the tree's cursor row.
-- Resolve its real source without selecting an entry or transferring focus.
function M.review_source(win)
  if vim.bo[api.nvim_win_get_buf(win)].filetype ~= "DiffviewFiles" then return win end
  local ok, source = pcall(api.nvim_win_call, win, function()
    local view = require("diffview.lib").get_current_view()
    assert(view and view.valid and not view.closing:check() and view.panel and view.panel.winid == win,
      "no live Diffview file panel")
    assert(view.cur_layout and view.cur_layout.b and api.nvim_win_is_valid(view.cur_layout.b.id),
      "Diffview source panes are unavailable; select a file first")
    return view.cur_layout.b.id
  end)
  if ok then return source end
  return nil, "Diffview comparison unavailable: " .. tostring(source)
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

-- Inspect ownership without requiring the selected replacement panes to load.
function M.detached(state)
  local source = state.source
  if not api.nvim_win_is_valid(source) and state.tabpage and api.nvim_tabpage_is_valid(state.tabpage) then
    source = api.nvim_tabpage_list_wins(state.tabpage)[1]
  end
  local selection = source and M.selection(source)
  assert(selection and selection.cwd == state.cwd and vim.deep_equal(selection.pair, state.pair)
    and selection.selected.kind == state.selected.kind and vim.deep_equal(selection.path_args, state.path_args)
    and selection.show_untracked == state.show_untracked, "Diffview comparison changed during collection")
  local copy = vim.deepcopy(state)
  copy.detached = true
  local module = package.loaded["diffview.vcs.file"]
  if module and (state.pair.old.type == "stage" or state.pair.new.type == "stage") then
    local maps = module.File.index_bufmap
    copy.stage_buffers = vim.deepcopy(maps[state.cwd] or maps[vim.uv.fs_realpath(state.cwd)] or {})
  end
  return copy
end

function M.select(source, manifest_entry)
  local ok, err = pcall(api.nvim_win_call, source, function()
    local lib = assert(package.loaded["diffview.lib"], "Diffview is unavailable")
    local view = lib.get_current_view()
    assert(view and view.valid and not view.closing:check(), "Diffview comparison is unavailable")
    local comparison = pair(view.cur_entry)
    assert(manifest_entry.kind == view.cur_entry.kind
      and vim.deep_equal(manifest_entry.comparison, comparison),
      "Review comparison changed")
    local found
    for _, entry in view.files:iter() do
      if entry.path == manifest_entry.path and (entry.oldpath or entry.path) == manifest_entry.oldpath
        and entry.kind == manifest_entry.kind and vim.deep_equal(pair(entry), comparison) then
        assert(not found, "Ambiguous review file identity")
        found = entry
      end
    end
    assert(found, "Review file is no longer in the comparison")
    view:set_file(found)
  end)
  return ok, not ok and tostring(err) or nil
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
