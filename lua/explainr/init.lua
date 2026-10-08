local M = {}

local defaults = {
  ai = { command = {}, output = "plain", timeout_ms = 300000 },
  context = { max_bytes = 262144, diff = "auto", radius = 20 },
  diff = { auto_explain = false },
}
M.config = vim.deepcopy(defaults)

function M.setup(options)
  assert(vim.fn.has("nvim-0.11") == 1, "explainr requires Neovim 0.11+")
  assert(options == nil or type(options) == "table", "explainr setup expects a table")
  local config = vim.tbl_deep_extend("force", vim.deepcopy(defaults), options or {})
  assert(vim.islist(config.ai.command), "ai.command must be an argument list")
  for _, arg in ipairs(config.ai.command) do
    assert(type(arg) == "string" and arg ~= "", "ai.command arguments must be nonempty strings")
  end
  assert(type(config.ai.output) == "function" or vim.tbl_contains({ "plain", "opencode", "codex" }, config.ai.output),
    "ai.output must be plain, opencode, codex, or a decoder function")
  for name, value in pairs({ timeout_ms = config.ai.timeout_ms, max_bytes = config.context.max_bytes }) do
    assert(type(value) == "number" and value > 0 and value < math.huge and value % 1 == 0,
      name .. " must be a positive finite integer")
  end
  assert(vim.tbl_contains({ "auto", "review", "focused" }, config.context.diff),
    "context.diff must be auto, review, or focused")
  assert(type(config.context.radius) == "number" and config.context.radius >= 0
    and config.context.radius < math.huge and config.context.radius % 1 == 0,
    "context.radius must be a nonnegative finite integer")
  assert(type(config.diff.auto_explain) == "boolean", "diff.auto_explain must be a boolean")
  M.config = config
  local sessions = package.loaded["explainr.session"]
  if sessions then sessions.auto_explain_changed(config.diff.auto_explain) end
  M.commands()
  return M
end

function M.explain(scope, selection)
  return require("explainr.session").explain(scope or "file", selection)
end

function M.review() return require("explainr.session").review() end
function M.refresh() return require("explainr.session").refresh() end
function M.cancel() return require("explainr.session").cancel() end
function M.close() return require("explainr.session").close() end

function M.toggle_auto_explain()
  M.config.diff.auto_explain = not M.config.diff.auto_explain
  local sessions = package.loaded["explainr.session"]
  if sessions then sessions.auto_explain_changed(M.config.diff.auto_explain) end
  vim.notify("Automatic explanations " .. (M.config.diff.auto_explain and "enabled" or "disabled"),
    vim.log.levels.INFO, { title = "Explainr" })
  return M.config.diff.auto_explain
end

function M.commands()
  vim.api.nvim_create_user_command("Explainr", function(args) M.explain(args.args ~= "" and args.args or "file") end,
    { nargs = "?", range = true, force = true, complete = function() return { "file", "selection", "hunk", "review" } end })
  for name, fn in pairs({ Review = M.review, Refresh = M.refresh, Cancel = M.cancel, Close = M.close, ToggleAutoExplain = M.toggle_auto_explain }) do
    vim.api.nvim_create_user_command("Explainr" .. name, fn, { force = true })
  end
end

return M
