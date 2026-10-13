local M = {}

--- Abre Telescope con las entradas formateadas.
--- @param opts { titulo: string, entradas: table[], formato: fun(e: table): string, on_elegir: fun(e: table) }
function M.elegir(opts)
  local ok, pickers = pcall(require, "telescope.pickers")
  if not ok then
    require("zettel.ui").error("telescope.nvim no está instalado.")
    return
  end

  local finders = require("telescope.finders")
  local conf = require("telescope.config").values
  local actions = require("telescope.actions")
  local action_state = require("telescope.actions.state")

  pickers.new({}, {
    prompt_title = opts.titulo or "Zettel",
    finder = finders.new_table({
      results = opts.entradas,
      entry_maker = function(entrada)
        local texto = opts.formato(entrada)
        return {
          value = entrada,
          display = texto,
          ordinal = texto,
        }
      end,
    }),
    sorter = conf.generic_sorter({}),
    attach_mappings = function(prompt_bufnr)
      actions.select_default:replace(function()
        actions.close(prompt_bufnr)
        local seleccion = action_state.get_selected_entry()
        if seleccion then
          opts.on_elegir(seleccion.value)
        end
      end)
      return true
    end,
  }):find()
end

return M
