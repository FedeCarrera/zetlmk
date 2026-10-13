local config = require("zettel.config")

local M = {}

--- Obtiene el adaptador configurado.
--- @return table
local function adaptador()
  local sel = config.get().selector
  if sel == "fzf" then
    return require("zettel.picker.fzf")
  elseif sel == "telescope" then
    return require("zettel.picker.telescope")
  else
    return require("zettel.picker.select")
  end
end

--- Abre un selector con las entradas dadas.
--- @param opts { titulo: string, entradas: table[], formato: fun(e: table): string, on_elegir: fun(e: table) }
function M.elegir(opts)
  adaptador().elegir(opts)
end

return M
