-- These editor tests resize windows and render Diffview. -l script mode keeps
-- an old screen allocation when columns changes, making redraw unsafe.
if vim.tbl_contains(vim.v.argv, "-l") then
  print("Run tests with: nvim --headless -u NONE -i NONE -n -c 'luafile tests/run.lua' (not -l)")
  vim.cmd("cquit 1")
end
vim.opt.runtimepath:prepend(vim.fn.getcwd())
vim.o.swapfile = false
vim.o.shadafile = "NONE"
-- Persistence tests and child editors must never read/write the user's cache.
local cache_root
if not vim.env.EXPLAINR_TEST_CACHE_ROOT then
  cache_root = vim.fn.tempname()
  vim.fn.mkdir(cache_root, "p")
  cache_root = assert(vim.uv.fs_realpath(cache_root))
  vim.env.EXPLAINR_TEST_CACHE_ROOT = cache_root
  vim.env.XDG_CACHE_HOME = cache_root
end
local failures, passed = {}, 0
_G.T = {}
function T.eq(expected, actual)
  assert(vim.deep_equal(expected, actual), "expected " .. vim.inspect(expected) .. ", got " .. vim.inspect(actual))
end
function T.test(name, run)
  local ok, err = xpcall(run, debug.traceback)
  if ok then passed = passed + 1; print("PASS " .. name)
  else failures[#failures + 1] = name .. "\n" .. err; print("FAIL " .. name) end
end
local pattern = vim.env.EXPLAINR_TEST or "tests/*_test.lua"
for _, file in ipairs(vim.fn.glob(pattern, false, true)) do
  local ok, err = xpcall(function() dofile(file) end, debug.traceback)
  if not ok then failures[#failures + 1] = file .. "\n" .. err end
end
print(string.format("%d passed, %d failed", passed, #failures))
if cache_root then
  if package.loaded["explainr.session"] then require("explainr").close() end
  vim.wait(200)
  vim.fn.delete(cache_root, "rf")
end
if #failures > 0 then
  for _, failure in ipairs(failures) do print(failure) end
  vim.cmd("cquit 1")
else vim.cmd("qa!") end
