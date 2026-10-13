local config = require("zettel.config")
local parser = require("zettel.parser")
local id_mod = require("zettel.id")

local M = {}

local VERSION = 1

-- Estado interno
M._datos = {}     -- { [id] = entrada }
M._cargado = false

--- Estructura de una entrada del índice:
--- {
---   id       = string,
---   ruta     = string (absoluta),
---   carpeta  = string ("inbox"|"fuentes"|"permanentes"|"raiz"),
---   titulo   = string,
---   tags     = { { nombre = string, origen = "frontmatter" } },
---   enlaces  = { { id = string, linea = number } },
---   sigue_a  = string|nil,
---   autor    = string|nil,
---   formato  = string|nil,
---   mtime    = number,
--- }

-- ── Helpers ──────────────────────────────────────────────────

--- Determina a qué carpeta lógica pertenece un archivo.
--- @param ruta string ruta absoluta del archivo
--- @return string
local function carpeta_de(ruta)
  local cfg = config.get()
  for nombre, sub in pairs(cfg.carpetas) do
    local prefijo = cfg.raiz .. "/" .. sub .. "/"
    if ruta:sub(1, #prefijo) == prefijo then
      return nombre
    end
  end
  return "raiz"
end

--- Lee y parsea un archivo de nota, devuelve una entrada del índice o nil.
--- @param ruta string
--- @return table|nil
local function indexar_archivo(ruta)
  local ok, lines = pcall(vim.fn.readfile, ruta)
  if not ok or not lines or #lines == 0 then return nil end

  local campos, _ = parser.frontmatter(lines)
  if not campos or not campos.id then return nil end

  local id_str = tostring(campos.id)
  if not id_mod.es_valido(id_str) then return nil end

  -- Tags con origen
  local tags = {}
  if campos.tags and type(campos.tags) == "table" then
    for _, t in ipairs(campos.tags) do
      tags[#tags + 1] = { nombre = t, origen = "frontmatter" }
    end
  end

  -- Enlaces
  local enlaces_raw = parser.enlaces(lines)
  local enlaces = {}
  for _, e in ipairs(enlaces_raw) do
    enlaces[#enlaces + 1] = { id = e.id, linea = e.linea }
  end

  local stat = vim.uv.fs_stat(ruta)
  local mtime = stat and stat.mtime.sec or 0

  return {
    id = id_str,
    ruta = ruta,
    carpeta = carpeta_de(ruta),
    titulo = campos.titulo or "",
    tags = tags,
    enlaces = enlaces,
    sigue_a = campos.sigue_a and tostring(campos.sigue_a) or nil,
    autor = campos.autor,
    formato = campos.formato,
    mtime = mtime,
  }
end

--- Recorre recursivamente un directorio buscando archivos .md
--- @param dir string
--- @return string[]
local function listar_md(dir)
  local archivos = {}
  local handle = vim.uv.fs_scandir(dir)
  if not handle then return archivos end

  while true do
    local nombre, tipo = vim.uv.fs_scandir_next(handle)
    if not nombre then break end
    local ruta = dir .. "/" .. nombre

    if tipo == "directory" then
      -- No entrar en .zettel
      if nombre ~= ".zettel" then
        local sub = listar_md(ruta)
        for _, a in ipairs(sub) do
          archivos[#archivos + 1] = a
        end
      end
    elseif tipo == "file" and nombre:match("%.md$") then
      archivos[#archivos + 1] = ruta
    end
  end

  return archivos
end

-- ── Persistencia ─────────────────────────────────────────────

local function ruta_index()
  return config.dir_zettel() .. "/index.json"
end

--- Carga el índice desde disco.
--- @return table|nil datos, boolean necesita_rebuild
local function cargar_json()
  local path = ruta_index()
  local ok, contenido = pcall(vim.fn.readfile, path)
  if not ok or not contenido or #contenido == 0 then
    return nil, true
  end

  local json_ok, datos = pcall(vim.json.decode, table.concat(contenido, "\n"))
  if not json_ok or type(datos) ~= "table" then
    return nil, true
  end

  if datos.version ~= VERSION then
    return nil, true
  end

  return datos.entradas or {}, false
end

--- Persiste el índice a disco.
function M.guardar()
  local dir = config.dir_zettel()
  vim.fn.mkdir(dir, "p")

  local datos = { version = VERSION, entradas = M._datos }
  local json = vim.json.encode(datos)
  vim.fn.writefile({ json }, ruta_index())
end

-- ── Carga e indexación ───────────────────────────────────────

--- Carga el índice: lee el JSON persistido, compara mtimes, reindexa lo necesario.
function M.cargar()
  if M._cargado then return end

  local cfg = config.get()
  local raiz = cfg.raiz

  if vim.fn.isdirectory(raiz) == 0 then
    M._cargado = true
    return
  end

  local previos, rebuild = cargar_json()

  if rebuild or not previos then
    M.reindexar_completo()
    return
  end

  -- Construir mapa ruta→entrada desde el JSON previo
  M._datos = {}
  local por_ruta = {}
  for id, entrada in pairs(previos) do
    M._datos[id] = entrada
    por_ruta[entrada.ruta] = entrada
  end

  -- Recorrer disco, detectar nuevos y modificados
  local archivos = listar_md(raiz)
  local en_disco = {}

  for _, ruta in ipairs(archivos) do
    en_disco[ruta] = true
    local stat = vim.uv.fs_stat(ruta)
    local mtime = stat and stat.mtime.sec or 0
    local previo = por_ruta[ruta]

    if not previo or previo.mtime ~= mtime then
      local entrada = indexar_archivo(ruta)
      if entrada then
        -- Borrar entrada vieja si el ID cambió
        if previo and previo.id ~= entrada.id then
          M._datos[previo.id] = nil
        end
        M._datos[entrada.id] = entrada
      end
    end
  end

  -- Detectar archivos borrados
  for id, entrada in pairs(M._datos) do
    if not en_disco[entrada.ruta] then
      M._datos[id] = nil
    end
  end

  M._cargado = true
  M.guardar()
end

--- Reconstruye el índice completo desde cero.
function M.reindexar_completo()
  local cfg = config.get()
  M._datos = {}

  if vim.fn.isdirectory(cfg.raiz) == 0 then
    M._cargado = true
    return
  end

  local archivos = listar_md(cfg.raiz)
  for _, ruta in ipairs(archivos) do
    local entrada = indexar_archivo(ruta)
    if entrada then
      M._datos[entrada.id] = entrada
    end
  end

  M._cargado = true
  M.guardar()
end

--- Reindexa un solo archivo (llamado desde BufWritePost).
--- @param ruta string ruta absoluta
function M.reindexar_archivo(ruta)
  if not M._cargado then
    M.cargar()
  end

  -- Borrar entrada vieja con esta ruta
  for id, entrada in pairs(M._datos) do
    if entrada.ruta == ruta then
      M._datos[id] = nil
      break
    end
  end

  -- Reindexar si el archivo existe
  if vim.uv.fs_stat(ruta) then
    local entrada = indexar_archivo(ruta)
    if entrada then
      M._datos[entrada.id] = entrada
    end
  end

  M.guardar()
end

--- Registra una entrada directamente (usado por notes.lua después de crear).
--- @param entrada table
function M.registrar(entrada)
  if not M._cargado then
    M.cargar()
  end
  M._datos[entrada.id] = entrada
  M.guardar()
end

-- ── Consultas ────────────────────────────────────────────────

--- Devuelve la entrada de un ID.
--- @param id string
--- @return table|nil
function M.obtener(id)
  M.cargar()
  return M._datos[id]
end

--- Devuelve true si el ID existe en el índice.
--- @param id string
--- @return boolean
function M.existe(id)
  M.cargar()
  return M._datos[id] ~= nil
end

--- Devuelve todas las entradas como lista.
--- @return table[]
function M.todas()
  M.cargar()
  local lista = {}
  for _, entrada in pairs(M._datos) do
    lista[#lista + 1] = entrada
  end
  return lista
end

--- Devuelve las fuentes como lista.
--- @return table[]
function M.fuentes()
  M.cargar()
  local lista = {}
  for _, entrada in pairs(M._datos) do
    if entrada.carpeta == "fuentes" then
      lista[#lista + 1] = entrada
    end
  end
  return lista
end

--- Devuelve los backlinks de un ID (notas que enlazan a este ID).
--- @param id string
--- @return table[] lista de { entrada = table, linea = number }
function M.backlinks(id)
  M.cargar()
  local resultado = {}
  for _, entrada in pairs(M._datos) do
    for _, enlace in ipairs(entrada.enlaces) do
      if enlace.id == id then
        resultado[#resultado + 1] = { entrada = entrada, linea = enlace.linea }
      end
    end
  end
  return resultado
end

--- Devuelve todos los tags únicos con su conteo (resolviendo alias).
--- @return table[] lista de { nombre = string, cantidad = number }
function M.tags()
  M.cargar()
  M.cargar_alias()
  local conteo = {}
  for _, entrada in pairs(M._datos) do
    for _, tag in ipairs(entrada.tags) do
      local nombre = M._alias[tag.nombre] or tag.nombre
      conteo[nombre] = (conteo[nombre] or 0) + 1
    end
  end

  local lista = {}
  for nombre, cantidad in pairs(conteo) do
    lista[#lista + 1] = { nombre = nombre, cantidad = cantidad }
  end
  table.sort(lista, function(a, b) return a.cantidad > b.cantidad end)
  return lista
end

--- Verifica si un ID existe, considerando índice y disco.
--- Usada por id.generar() para resolver choques.
--- @param id string
--- @return boolean
function M.id_ocupado(id)
  M.cargar()
  if M._datos[id] then return true end
  -- También verificar en disco por si hay archivos no indexados
  local cfg = config.get()
  local archivos = listar_md(cfg.raiz)
  for _, ruta in ipairs(archivos) do
    local nombre = vim.fn.fnamemodify(ruta, ":t:r")
    if nombre == id or nombre:match("^" .. id .. "%-") then
      return true
    end
  end
  return false
end

-- ── Alias de tags ────────────────────────────────────────────

M._alias = {} -- { [alias] = tag_canonico }

--- Carga los alias de tags desde .zettel/alias.yaml.
function M.cargar_alias()
  local ruta = config.dir_zettel() .. "/alias.yaml"
  M._alias = {}
  local ok, lines = pcall(vim.fn.readfile, ruta)
  if not ok or not lines then return end

  for _, linea in ipairs(lines) do
    local alias, canonico = linea:match("^([%w_/%-]+):%s*(.+)$")
    if alias and canonico then
      M._alias[vim.trim(alias)] = vim.trim(canonico)
    end
  end
end

--- Resuelve un tag a través de los alias.
--- @param tag string
--- @return string tag canónico
function M.resolver_alias(tag)
  if not next(M._alias) then
    M.cargar_alias()
  end
  return M._alias[tag] or tag
end

--- Devuelve la tabla de alias.
--- @return table { [alias] = canonico }
function M.alias()
  if not next(M._alias) then
    M.cargar_alias()
  end
  return M._alias
end

--- Resetea el estado del índice (para tests).
function M._reset()
  M._datos = {}
  M._alias = {}
  M._cargado = false
end

return M
