-- Configuración mínima para correr tests con mini.test en modo headless.
-- Uso: nvim --headless -u tests/minimal_init.lua -c "lua MiniTest.run()"

-- Agregar el plugin al runtimepath
local plugin_dir = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":h:h")
vim.opt.runtimepath:prepend(plugin_dir)

-- Agregar mini.nvim al runtimepath
local mini_path = vim.fn.expand("~/.local/share/nvim/lazy/mini.nvim")
vim.opt.runtimepath:prepend(mini_path)

-- Cargar mini.test
require("mini.test").setup()
