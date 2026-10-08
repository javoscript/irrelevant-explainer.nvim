-- Shared disposable MR-style fixture for runtime acceptance and screen capture.
local api = vim.api
local M = {}
function M.open(working, reference_variants)
  local runtime = vim.env.EXPLAINR_DIFFVIEW_PATH or (vim.fn.stdpath("data") .. "/lazy/diffview.nvim")
  assert(vim.fn.isdirectory(runtime .. "/lua/diffview") == 1, "Diffview runtime is required for this fixture")
  vim.opt.runtimepath:append(runtime)
  vim.opt.runtimepath:append(vim.env.EXPLAINR_PLENARY_PATH or (vim.fn.stdpath("data") .. "/lazy/plenary.nvim"))
  local root = vim.fn.tempname()
  vim.fn.mkdir(root, "p"); root = vim.uv.fs_realpath(root)
  local fixture = { root = root, cwd = vim.fn.getcwd(), tab = api.nvim_get_current_tabpage() }
  function fixture:git(...)
    local value = vim.system(vim.list_extend({ "git" }, { ... }), { cwd = self.root }):wait()
    assert(value.code == 0, value.stderr); return vim.trim(value.stdout)
  end
  function fixture:write(path, text)
    vim.fn.mkdir(vim.fn.fnamemodify(self.root .. "/" .. path, ":h"), "p")
    local fd = assert(vim.uv.fs_open(self.root .. "/" .. path, "w", 420))
    assert(vim.uv.fs_write(fd, text, 0)); vim.uv.fs_close(fd)
  end
  fixture:git("init", "-q"); fixture:git("config", "user.name", "Offline review")
  fixture:git("config", "user.email", "offline@example.invalid")
  local tail = {}; for i = 13, 110 do tail[#tail + 1] = "-- unchanged context " .. i end
  fixture.before = { "local function can_cancel(user, request)", "  if not user then return false end", "",
    "  if user.is_admin then return true end", "  -- Keep the owner check visible.", "  local owner = user.id == request.owner_id", "",
    "  if request.legacy then", "    return true -- obsolete bypass", "  end", "  return owner", "end" }
  fixture.after = { "local function can_cancel(user, request)", "  if not user then return false end", "",
    '  if user.role == "editor" then return true end', "  -- Keep the owner check visible.", "  local owner = user.id == request.owner_id", "",
    "  return owner", "end" }
  vim.list_extend(fixture.before, tail); vim.list_extend(fixture.after, tail)
  fixture:write("policy.lua", table.concat(fixture.before, "\n") .. "\n")
  fixture:write("openspec/spec.md", "# Cancellation\nOwners or administrators may cancel.\n")
  fixture:write("docs/adr.md", "Rationale: preserve the owner's decision.\nOld permission rule.\n")
  fixture:write("tests/policy.txt", "allow administrator\n")
  if reference_variants then
    fixture:write("old-name.txt", "Unchanged content in a renamed file.\n")
    fixture:write("deleted.txt", "Removed policy.\n")
    fixture:write("badge.bin", "\0before\n")
  end
  fixture:git("add", "--all"); fixture:git("commit", "-qm", "base")
  fixture.base = fixture:git("rev-parse", "HEAD")
  fixture:write("policy.lua", table.concat(fixture.after, "\n") .. "\n")
  fixture:write("openspec/spec.md", "# Cancellation\nOnly owners may cancel.\n")
  fixture:write("docs/adr.md", "Rationale: preserve the owner's decision.\nAdopt strict ownership.\n")
  fixture:write("tests/policy.txt", "allow owner; reject editor\n")
  if reference_variants then
    fixture:git("mv", "old-name.txt", "renamed.txt")
    assert(vim.uv.fs_unlink(root .. "/deleted.txt"))
    fixture:write("badge.bin", "\0after\n")
  end
  local args = { fixture.base }
  if not working then
    fixture:git("add", "--all"); fixture:git("commit", "-qm", "review")
    args[1] = fixture.base .. ".." .. fixture:git("rev-parse", "HEAD")
  end
  args[#args + 1] = "--selected-file=" .. root .. "/policy.lua"
  local dv, lib = require("diffview"), require("diffview.lib")
  dv.setup({ watch_index = false, use_icons = false })
  api.nvim_set_current_dir(root); dv.open(args)
  assert(vim.wait(10000, function()
    local view = lib.get_current_view()
    if not view or not view.cur_layout.b then return false end
    fixture.state = require("explainr.diffview").current(view.cur_layout.b.id)
    return fixture.state and fixture.state.selected.path == "policy.lua"
  end, 20), "review fixture did not load")
  fixture.view = lib.get_current_view()
  api.nvim_set_current_win(fixture.state.source)
  function fixture:switch(path)
    local entry
    for _, item in self.view.files:iter() do if item.path == path then entry = item; break end end
    self.view:set_file(assert(entry), false, true)
    assert(vim.wait(10000, function()
      self.state = require("explainr.diffview").current(self.view.cur_layout.b.id)
      return self.state and self.state.selected.path == path
    end, 20))
    api.nvim_set_current_win(self.state.source)
  end
  function fixture:close()
    require("explainr").close()
    if api.nvim_tabpage_is_valid(self.view.tabpage) then api.nvim_set_current_tabpage(self.view.tabpage); dv.close() end
    if api.nvim_tabpage_is_valid(self.tab) then api.nvim_set_current_tabpage(self.tab) end
    api.nvim_set_current_dir(self.cwd)
    for _, buf in ipairs(api.nvim_list_bufs()) do
      if api.nvim_buf_is_valid(buf) and api.nvim_buf_get_name(buf):find(self.root, 1, true) then api.nvim_buf_delete(buf, { force = true }) end
    end
    vim.fn.delete(self.root, "rf")
  end
  return fixture
end
return M
