local M = {}

--- Abre fzf-lua con las entradas formateadas.
--- @param opts { titulo: string, entradas: table[], formato: fun(e: table): string, on_elegir: fun(e: table) }
function M.elegir(opts)
  local ok, fzf = pcall(require, "fzf-lua")
  if not ok then
    require("zettel.ui").error("fzf-lua no está instalado. Configurá selector = 'select' en setup().")
    return
  end

  -- Construir las líneas y un mapa para recuperar la entrada original
  local lineas = {}
  local mapa = {}
  for _, entrada in ipairs(opts.entradas) do
    local texto = opts.formato(entrada)
    lineas[#lineas + 1] = texto
    mapa[texto] = entrada
  end

  fzf.fzf_exec(lineas, {
    prompt = (opts.titulo or "Zettel") .. "> ",
    actions = {
      ["default"] = function(seleccion)
        if seleccion and #seleccion > 0 then
          local elegido = mapa[seleccion[1]]
          if elegido then
            opts.on_elegir(elegido)
          end
        end
      end,
    },
  })
end

return M
