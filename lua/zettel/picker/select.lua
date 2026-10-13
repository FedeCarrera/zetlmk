local M = {}

--- Abre vim.ui.select con las entradas formateadas.
--- @param opts { titulo: string, entradas: table[], formato: fun(e: table): string, on_elegir: fun(e: table) }
function M.elegir(opts)
  vim.ui.select(opts.entradas, {
    prompt = opts.titulo or "Zettel",
    format_item = opts.formato,
  }, function(elegido)
    if elegido then
      opts.on_elegir(elegido)
    end
  end)
end

return M
