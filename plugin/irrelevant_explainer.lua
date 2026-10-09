if vim.g.loaded_irrelevant_explainer then return end
vim.g.loaded_irrelevant_explainer = true
require("irrelevant_explainer").commands()
