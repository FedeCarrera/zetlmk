local index = require("zettel.index")
local id_mod = require("zettel.id")
local config = require("zettel.config")
local picker = require("zettel.picker")
local ui = require("zettel.ui")

local M = {}

--- Parsea una cadena de consulta en filtros estructurados.
--- Sintaxis: #tag -#tag "texto libre" en:carpeta desde:AAAA-MM formato:X
--- @param query string
--- @return table { tags_si, tags_no, texto, carpeta, desde, formato }
function M.parsear(query)
  local filtros = {
    tags_si = {},
    tags_no = {},
    texto = {},
    carpeta = nil,
    desde = nil,
    formato = nil,
  }

  -- Extraer textos entre comillas primero
  local sin_comillas = query:gsub('"([^"]+)"', function(t)
    filtros.texto[#filtros.texto + 1] = t:lower()
    return ""
  end)

  -- Procesar tokens restantes
  for token in sin_comillas:gmatch("%S+") do
    if token:match("^%-#") then
      -- Tag negado
      filtros.tags_no[#filtros.tags_no + 1] = token:sub(3)
    elseif token:match("^#") then
      -- Tag requerido
      filtros.tags_si[#filtros.tags_si + 1] = token:sub(2)
    elseif token:match("^en:") then
      filtros.carpeta = token:sub(4)
    elseif token:match("^desde:") then
      filtros.desde = token:sub(7)
    elseif token:match("^formato:") then
      filtros.formato = token:sub(9)
    else
      -- Texto libre sin comillas
      filtros.texto[#filtros.texto + 1] = token:lower()
    end
  end

  return filtros
end

--- Evalúa si una entrada del índice cumple los filtros.
--- @param entrada table
--- @param filtros table
--- @return boolean
function M.cumple(entrada, filtros)
  -- Tags requeridos (resolviendo alias)
  for _, tag_req in ipairs(filtros.tags_si) do
    local tiene = false
    for _, t in ipairs(entrada.tags) do
      local nombre = index.resolver_alias(t.nombre)
      if nombre == tag_req or nombre:match("^" .. vim.pesc(tag_req) .. "/") then
        tiene = true
        break
      end
    end
    if not tiene then return false end
  end

  -- Tags negados
  for _, tag_no in ipairs(filtros.tags_no) do
    for _, t in ipairs(entrada.tags) do
      local nombre = index.resolver_alias(t.nombre)
      if nombre == tag_no or nombre:match("^" .. vim.pesc(tag_no) .. "/") then
        return false
      end
    end
  end

  -- Carpeta
  if filtros.carpeta then
    if filtros.carpeta ~= entrada.carpeta then
      return false
    end
  end

  -- Formato
  if filtros.formato then
    if entrada.formato ~= filtros.formato then
      return false
    end
  end

  -- Desde (fecha deducida del ID)
  if filtros.desde then
    -- filtros.desde puede ser "AAAA-MM" o "AAAA-MM-DD"
    local desde_limpia = filtros.desde:gsub("%-", "")
    local prefijo = entrada.id:sub(1, #desde_limpia)
    if prefijo < desde_limpia then
      return false
    end
  end

  -- Texto libre: buscar en título y contenido del archivo
  if #filtros.texto > 0 then
    local titulo_lower = (entrada.titulo or ""):lower()
    local contenido_lower = ""

    local ok, lines = pcall(vim.fn.readfile, entrada.ruta)
    if ok and lines then
      contenido_lower = table.concat(lines, "\n"):lower()
    end

    for _, t in ipairs(filtros.texto) do
      if not titulo_lower:find(t, 1, true) and not contenido_lower:find(t, 1, true) then
        return false
      end
    end
  end

  return true
end

--- Ejecuta una consulta y devuelve las entradas que la cumplen.
--- @param query string
--- @return table[] entradas
--- @return table filtros
function M.ejecutar(query)
  index.cargar()
  local filtros = M.parsear(query)
  local resultados = {}

  for _, entrada in ipairs(index.todas()) do
    if M.cumple(entrada, filtros) then
      resultados[#resultados + 1] = entrada
    end
  end

  -- Ordenar por ID descendente (más recientes primero)
  table.sort(resultados, function(a, b) return a.id > b.id end)

  return resultados, filtros
end

--- Comando interactivo: pide la consulta y muestra resultados en el selector.
--- @param query_directa string|nil si se pasa, no pide input
function M.consultar(query_directa)
  local hacer = function(query)
    if not query or query == "" then return end
    local resultados = M.ejecutar(query)

    if #resultados == 0 then
      ui.info("Sin resultados para: " .. query)
      return
    end

    picker.elegir({
      titulo = "Consulta: " .. query .. " (" .. #resultados .. ")",
      entradas = resultados,
      formato = function(e)
        local tags_str = ""
        if e.tags and #e.tags > 0 then
          local nombres = {}
          for _, t in ipairs(e.tags) do nombres[#nombres + 1] = t.nombre end
          tags_str = " · " .. table.concat(nombres, ", ")
        end
        return e.titulo .. tags_str .. " · " .. e.carpeta
      end,
      on_elegir = function(e)
        vim.cmd("edit " .. vim.fn.fnameescape(e.ruta))
      end,
    })
  end

  if query_directa then
    hacer(query_directa)
  else
    ui.input("Consulta: ", hacer)
  end
end

-- ── Búsquedas guardadas ──────────────────────────────────────

--- Carga búsquedas guardadas desde .zettel/busquedas.yaml.
--- @return table[] lista de { nombre, query }
function M.cargar_busquedas()
  local ruta = config.dir_zettel() .. "/busquedas.yaml"
  local ok, lines = pcall(vim.fn.readfile, ruta)
  if not ok or not lines then return {} end

  local busquedas = {}
  for _, linea in ipairs(lines) do
    local nombre, query = linea:match("^([^:]+):%s*(.+)$")
    if nombre and query then
      busquedas[#busquedas + 1] = {
        nombre = vim.trim(nombre),
        query = vim.trim(query),
      }
    end
  end
  return busquedas
end

--- Guarda una búsqueda en .zettel/busquedas.yaml.
--- @param nombre string
--- @param query string
function M.guardar_busqueda(nombre, query)
  local ruta = config.dir_zettel() .. "/busquedas.yaml"
  vim.fn.mkdir(config.dir_zettel(), "p")

  local busquedas = M.cargar_busquedas()
  -- Actualizar si ya existe
  local encontrada = false
  for _, b in ipairs(busquedas) do
    if b.nombre == nombre then
      b.query = query
      encontrada = true
      break
    end
  end
  if not encontrada then
    busquedas[#busquedas + 1] = { nombre = nombre, query = query }
  end

  local lines = {}
  for _, b in ipairs(busquedas) do
    lines[#lines + 1] = b.nombre .. ": " .. b.query
  end
  vim.fn.writefile(lines, ruta)
end

--- Selector de búsquedas guardadas.
function M.busquedas_guardadas()
  local busquedas = M.cargar_busquedas()
  if #busquedas == 0 then
    ui.info("No hay búsquedas guardadas. Guardalas en .zettel/busquedas.yaml")
    return
  end

  picker.elegir({
    titulo = "Búsquedas guardadas",
    entradas = busquedas,
    formato = function(b) return b.nombre .. ": " .. b.query end,
    on_elegir = function(b)
      M.consultar(b.query)
    end,
  })
end

return M
