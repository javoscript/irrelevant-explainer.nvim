if vim.g.loaded_explainr then return end
vim.g.loaded_explainr = true
require("explainr").commands()
