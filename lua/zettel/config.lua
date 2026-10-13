local M = {}

local defaults = {
  raiz = "~/zettel",
  carpetas = {
    inbox = "inbox",
    fuentes = "fuentes",
    permanentes = "permanentes",
  },
  slug_en_nombre = false,
  selector = "fzf",
  mapeos = true,
  salud = {
    inbox_dias = 14,
    nota_larga_palabras = 400,
    nota_varios_subtitulos = 3,
    tag_grande = 30,
  },
  descubrir = {
    nucleo_min_notas = 4,
    tag_maduro_min_notas = 8,
    relacionadas_min_tags = 2,
  },
}

M._opts = nil

function M.setup(opts)
  M._opts = vim.tbl_deep_extend("force", vim.deepcopy(defaults), opts or {})
  -- Expandir ~ en la raíz
  M._opts.raiz = vim.fn.expand(M._opts.raiz)
end

function M.get()
  if not M._opts then
    M.setup({})
  end
  return M._opts
end

--- Devuelve la ruta absoluta de una carpeta del zettel.
--- @param nombre string|nil "inbox", "fuentes", "permanentes" o nil para la raíz
--- @return string
function M.carpeta(nombre)
  local cfg = M.get()
  if not nombre then
    return cfg.raiz
  end
  local sub = cfg.carpetas[nombre]
  if not sub then
    error("Carpeta desconocida: " .. nombre)
  end
  return cfg.raiz .. "/" .. sub
end

--- Ruta de .zettel/
function M.dir_zettel()
  return M.get().raiz .. "/.zettel"
end

return M
