local M = {}

local defaults = {
  ai = { command = { "opencode", "run", "--agent", "explain", "--format", "json" },
    output = "opencode", timeout_ms = 300000 },
  context = { max_bytes = 262144, diff = "auto", radius = 20 },
  diff = { auto_explain = false },
  review = { request_max_bytes = 262144, response_max_bytes = 32768, max_snapshot_bytes = 16777216, max_requests = 128 },
  cache = { enabled = true, max_bytes = 104857600, namespace = "default" },
}
M.config = vim.deepcopy(defaults)

function M.setup(options)
  assert(vim.fn.has("nvim-0.11") == 1, "irrelevant_explainer requires Neovim 0.11+")
  assert(options == nil or type(options) == "table", "irrelevant_explainer setup expects a table")
  local config = vim.tbl_deep_extend("force", vim.deepcopy(defaults), vim.deepcopy(options or {}))
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
  for name, value in pairs(config.review) do
    assert(defaults.review[name] ~= nil, "unknown review option: " .. name)
    assert(type(value) == "number" and value > 0 and value < math.huge and value % 1 == 0,
      "review." .. name .. " must be a positive finite integer")
  end
  assert(type(config.cache.enabled) == "boolean", "cache.enabled must be a boolean")
  local size = config.cache.max_bytes
  assert(type(size) == "number" and size > 0 and size < math.huge and size % 1 == 0,
    "cache.max_bytes must be a positive finite integer")
  for _, name in ipairs({ "namespace", "decoder_key" }) do
    local value = config.cache[name]
    assert(name == "decoder_key" and value == nil or type(value) == "string" and value ~= "",
      "cache." .. name .. " must be nonempty text")
  end
  M.config = config
  local sessions = package.loaded["irrelevant_explainer.session"]
  if sessions then sessions.auto_explain_changed(config.diff.auto_explain) end
  M.commands()
  return M
end

function M.explain(scope, selection)
  return require("irrelevant_explainer.session").explain(scope or "file", selection)
end

function M.review() return require("irrelevant_explainer.session").review() end
function M.refresh() return require("irrelevant_explainer.session").refresh() end
function M.cancel() return require("irrelevant_explainer.session").cancel() end
function M.close() return require("irrelevant_explainer.session").close() end
function M.clear_cache() return require("irrelevant_explainer.session").clear_cache() end

function M.toggle_auto_explain()
  M.config.diff.auto_explain = not M.config.diff.auto_explain
  local sessions = package.loaded["irrelevant_explainer.session"]
  if sessions then sessions.auto_explain_changed(M.config.diff.auto_explain) end
  vim.notify("Automatic explanations " .. (M.config.diff.auto_explain and "enabled" or "disabled"),
    vim.log.levels.INFO, { title = "Irrelevant Explainer" })
  return M.config.diff.auto_explain
end

function M.commands()
  vim.api.nvim_create_user_command("IrrelevantExplainer", function(args) M.explain(args.args ~= "" and args.args or "file") end,
    { nargs = "?", range = true, force = true, complete = function() return { "file", "selection", "hunk", "review" } end })
  for name, fn in pairs({ Review = M.review, Refresh = M.refresh, Cancel = M.cancel, Close = M.close,
    CacheClear = M.clear_cache, ToggleAutoExplain = M.toggle_auto_explain }) do
    vim.api.nvim_create_user_command("IrrelevantExplainer" .. name, fn, { force = true })
  end
end

return M
