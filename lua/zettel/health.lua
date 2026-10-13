local config = require("zettel.config")
local index = require("zettel.index")
local parser = require("zettel.parser")
local ui = require("zettel.ui")

local M = {}

-- ── Helpers ──────────────────────────────────────────────────

--- Cuenta palabras en las líneas de cuerpo (después del frontmatter).
--- @param ruta string
--- @return number palabras, number subtitulos
local function contar_contenido(ruta)
  local ok, lines = pcall(vim.fn.readfile, ruta)
  if not ok or not lines then return 0, 0 end

  local _, fin = parser.frontmatter(lines)
  if not fin then return 0, 0 end

  local palabras = 0
  local subtitulos = 0
  for i = fin + 1, #lines do
    local linea = lines[i]
    -- Contar palabras
    for _ in linea:gmatch("%S+") do
      palabras = palabras + 1
    end
    -- Contar subtítulos (## o más)
    if linea:match("^##+ ") then
      subtitulos = subtitulos + 1
    end
  end
  return palabras, subtitulos
end

--- Verifica si una nota tiene bloques de cita (líneas que empiezan con >).
--- @param ruta string
--- @return boolean
local function tiene_citas(ruta)
  local ok, lines = pcall(vim.fn.readfile, ruta)
  if not ok or not lines then return false end

  local _, fin = parser.frontmatter(lines)
  if not fin then return false end

  for i = fin + 1, #lines do
    if lines[i]:match("^>") then
      return true
    end
  end
  return false
end

--- Detecta ciclos en sigue_a desde un ID dado.
--- @param id_inicio string
--- @return boolean tiene_ciclo
local function detectar_ciclo_sigue_a(id_inicio)
  local visitados = {}
  local actual = id_inicio
  while actual do
    if visitados[actual] then return true end
    visitados[actual] = true
    local e = index.obtener(actual)
    if not e then break end
    actual = e.sigue_a
  end
  return false
end

--- Calcula las notas alcanzables desde las estructuras (por enlaces).
--- @return table set de IDs alcanzables
local function notas_alcanzables_desde_estructuras()
  local alcanzables = {}
  local cola = {}

  -- Semillas: todas las notas de estructura (raíz)
  for _, e in ipairs(index.todas()) do
    if e.carpeta == "raiz" then
      alcanzables[e.id] = true
      cola[#cola + 1] = e.id
    end
  end

  -- BFS por enlaces salientes
  while #cola > 0 do
    local id = table.remove(cola, 1)
    local e = index.obtener(id)
    if e then
      for _, enlace in ipairs(e.enlaces) do
        if not alcanzables[enlace.id] then
          alcanzables[enlace.id] = true
          cola[#cola + 1] = enlace.id
        end
      end
    end
  end

  return alcanzables
end

--- Calcula la distancia de Levenshtein entre dos strings.
--- @param s1 string
--- @param s2 string
--- @return number
local function levenshtein(s1, s2)
  local len1, len2 = #s1, #s2
  local matrix = {}
  for i = 0, len1 do
    matrix[i] = { [0] = i }
  end
  for j = 0, len2 do
    matrix[0][j] = j
  end
  for i = 1, len1 do
    for j = 1, len2 do
      local costo = s1:sub(i, i) == s2:sub(j, j) and 0 or 1
      matrix[i][j] = math.min(
        matrix[i - 1][j] + 1,
        matrix[i][j - 1] + 1,
        matrix[i - 1][j - 1] + costo
      )
    end
  end
  return matrix[len1][len2]
end

-- ── Generación del informe ───────────────────────────────────

--- Genera el informe de salud y lo escribe en .zettel/salud.md.
--- @return string ruta del archivo generado
function M.generar()
  index.cargar()
  local cfg = config.get()
  local todas = index.todas()

  local errores = {}
  local sugerencias = {}

  -- Conjuntos para análisis
  local ids_vistos = {}
  local ids_duplicados = {}
  local tiene_backlinks = {} -- IDs que alguien enlaza
  local enlaza_a_algo = {}  -- IDs que enlazan a algo
  local enlaza_a_fuente = {} -- IDs de permanentes que enlazan a alguna fuente
  local fuentes_enlazadas = {} -- IDs de fuentes que alguna permanente enlaza

  -- Primer paso: mapear enlaces y detectar duplicados
  for _, e in ipairs(todas) do
    if ids_vistos[e.id] then
      ids_duplicados[e.id] = true
    end
    ids_vistos[e.id] = true

    for _, enlace in ipairs(e.enlaces) do
      tiene_backlinks[enlace.id] = true
      enlaza_a_algo[e.id] = true

      -- Verificar si enlaza a una fuente
      local destino = index.obtener(enlace.id)
      if destino then
        if destino.carpeta == "fuentes" and e.carpeta == "permanentes" then
          enlaza_a_fuente[e.id] = true
          fuentes_enlazadas[destino.id] = true
        end
      end
    end
  end

  -- Segundo paso: análisis por nota
  for _, e in ipairs(todas) do
    -- ── Errores ──

    -- IDs duplicados
    if ids_duplicados[e.id] then
      errores[#errores + 1] = "ID duplicado: [[" .. e.id .. "|" .. e.titulo .. "]]"
    end

    -- Frontmatter inválido: leer el archivo y verificar
    local ok_read, lines = pcall(vim.fn.readfile, e.ruta)
    if ok_read and lines then
      local campos, _ = parser.frontmatter(lines)
      if not campos then
        errores[#errores + 1] = "Frontmatter inválido: [[" .. e.id .. "|" .. e.titulo .. "]]"
      elseif not campos.id or not campos.titulo then
        errores[#errores + 1] = "Campos obligatorios faltantes (id, titulo): [[" .. e.id .. "|" .. e.titulo .. "]]"
      else
        -- ID del frontmatter distinto del nombre del archivo
        local nombre_archivo = vim.fn.fnamemodify(e.ruta, ":t:r")
        local id_archivo = nombre_archivo:match("^(%d+)")
        if id_archivo and id_archivo ~= tostring(campos.id) then
          errores[#errores + 1] = "ID del frontmatter (" .. tostring(campos.id) .. ") distinto del archivo (" .. id_archivo .. "): [[" .. e.id .. "|" .. e.titulo .. "]]"
        end

        -- Campos faltantes en tags
        if not campos.tags then
          errores[#errores + 1] = "Falta campo tags: [[" .. e.id .. "|" .. e.titulo .. "]]"
        end
      end
    end

    -- Enlaces rotos
    for _, enlace in ipairs(e.enlaces) do
      if not index.existe(enlace.id) then
        errores[#errores + 1] = "Enlace roto a " .. enlace.id .. " en [[" .. e.id .. "|" .. e.titulo .. "]]"
      end
    end

    -- sigue_a roto
    if e.sigue_a then
      if not index.existe(e.sigue_a) then
        errores[#errores + 1] = "sigue_a roto (" .. e.sigue_a .. "): [[" .. e.id .. "|" .. e.titulo .. "]]"
      elseif detectar_ciclo_sigue_a(e.id) then
        errores[#errores + 1] = "Ciclo en sigue_a: [[" .. e.id .. "|" .. e.titulo .. "]]"
      end
    end

    -- Fuentes sin autor o formato
    if e.carpeta == "fuentes" then
      if not e.autor or e.autor == "" then
        errores[#errores + 1] = "Fuente sin autor: [[" .. e.id .. "|" .. e.titulo .. "]]"
      end
      if not e.formato or e.formato == "" then
        errores[#errores + 1] = "Fuente sin formato: [[" .. e.id .. "|" .. e.titulo .. "]]"
      end
    end

    -- ── Sugerencias ──

    if e.carpeta == "permanentes" then
      -- Huérfanas: nadie la cita
      if not tiene_backlinks[e.id] then
        sugerencias[#sugerencias + 1] = "Nadie la cita: [[" .. e.id .. "|" .. e.titulo .. "]]"
      end
      -- Huérfanas: no cita a nadie
      if not enlaza_a_algo[e.id] then
        sugerencias[#sugerencias + 1] = "No cita a nadie: [[" .. e.id .. "|" .. e.titulo .. "]]"
      end
      -- Citas sin fuente
      if tiene_citas(e.ruta) and not enlaza_a_fuente[e.id] then
        sugerencias[#sugerencias + 1] = "Tiene citas pero no enlaza a ninguna fuente: [[" .. e.id .. "|" .. e.titulo .. "]]"
      end
    end

    -- Notas sin tags
    if #e.tags == 0 then
      sugerencias[#sugerencias + 1] = "Sin tags: [[" .. e.id .. "|" .. e.titulo .. "]]"
    end

    -- Inbox viejo
    if e.carpeta == "inbox" then
      local id_mod = require("zettel.id")
      local t_nota = os.time(id_mod.parsear(e.id))
      local dias = (os.time() - t_nota) / 86400
      if dias > cfg.salud.inbox_dias then
        sugerencias[#sugerencias + 1] = "Fugaz con más de " .. cfg.salud.inbox_dias .. " días: [[" .. e.id .. "|" .. e.titulo .. "]]"
      end
    end

    -- Notas largas o con muchos subtítulos
    if ok_read and lines then
      local palabras, subtitulos = contar_contenido(e.ruta)
      if palabras > cfg.salud.nota_larga_palabras then
        sugerencias[#sugerencias + 1] = "Nota larga (" .. palabras .. " palabras): [[" .. e.id .. "|" .. e.titulo .. "]]"
      end
      if subtitulos > cfg.salud.nota_varios_subtitulos then
        sugerencias[#sugerencias + 1] = "Muchos subtítulos (" .. subtitulos .. "): [[" .. e.id .. "|" .. e.titulo .. "]]"
      end
    end
  end

  -- Islas: permanentes no alcanzables desde ninguna estructura
  local alcanzables = notas_alcanzables_desde_estructuras()
  for _, e in ipairs(todas) do
    if e.carpeta == "permanentes" and not alcanzables[e.id] then
      sugerencias[#sugerencias + 1] = "Isla (no alcanzable desde ninguna estructura): [[" .. e.id .. "|" .. e.titulo .. "]]"
    end
  end

  -- Fuentes sin ninguna permanente que las enlace
  for _, e in ipairs(todas) do
    if e.carpeta == "fuentes" and not fuentes_enlazadas[e.id] then
      sugerencias[#sugerencias + 1] = "Fuente sin permanentes que la enlacen: [[" .. e.id .. "|" .. e.titulo .. "]]"
    end
  end

  -- Tags: con una sola nota, más grandes que tag_grande, casi duplicados
  local tags = index.tags()
  local nombres_tags = {}
  for _, t in ipairs(tags) do
    nombres_tags[#nombres_tags + 1] = t.nombre
    if t.cantidad == 1 then
      sugerencias[#sugerencias + 1] = "Tag con una sola nota: " .. t.nombre
    end
    if t.cantidad > cfg.salud.tag_grande then
      sugerencias[#sugerencias + 1] = "Tag muy grande (" .. t.cantidad .. " notas): " .. t.nombre
    end
  end

  -- Tags casi duplicados (distancia de Levenshtein ≤ 2, ignorando jerarquía)
  local ya_reportados = {}
  for i = 1, #nombres_tags do
    for j = i + 1, #nombres_tags do
      local a, b = nombres_tags[i], nombres_tags[j]
      -- Solo comparar la parte final (después del último /)
      local a_final = a:match("[^/]+$") or a
      local b_final = b:match("[^/]+$") or b
      if a_final ~= b_final and levenshtein(a_final, b_final) <= 2 then
        local par = a < b and (a .. "|" .. b) or (b .. "|" .. a)
        if not ya_reportados[par] then
          ya_reportados[par] = true
          sugerencias[#sugerencias + 1] = "Tags casi duplicados: " .. a .. " / " .. b
        end
      end
    end
  end

  -- ── Escribir archivo ──

  local total = #errores + #sugerencias
  local resumen = total == 0
    and "Todo en orden."
    or (total .. " hallazgo" .. (total > 1 and "s" or "") .. ": " .. #errores .. " error" .. (#errores ~= 1 and "es" or "") .. ", " .. #sugerencias .. " sugerencia" .. (#sugerencias ~= 1 and "s" or "") .. ".")

  local lineas = {
    "# Salud del zettel",
    "",
    resumen,
    "",
    "## Errores",
    "",
  }

  if #errores == 0 then
    lineas[#lineas + 1] = "Ninguno."
  else
    for _, e in ipairs(errores) do
      lineas[#lineas + 1] = "- " .. e
    end
  end

  lineas[#lineas + 1] = ""
  lineas[#lineas + 1] = "## Sugerencias"
  lineas[#lineas + 1] = ""

  if #sugerencias == 0 then
    lineas[#lineas + 1] = "Ninguna."
  else
    for _, s in ipairs(sugerencias) do
      lineas[#lineas + 1] = "- " .. s
    end
  end

  lineas[#lineas + 1] = ""
  lineas[#lineas + 1] = "## Oportunidades"
  lineas[#lineas + 1] = ""

  local discover = require("zettel.discover")
  local oportunidades = {}

  -- Núcleos emergentes
  local nucleos = discover.nucleos_emergentes(alcanzables)
  for i, nucleo in ipairs(nucleos) do
    local titulos = {}
    for _, e in ipairs(nucleo) do
      titulos[#titulos + 1] = "[[" .. e.id .. "|" .. e.titulo .. "]]"
    end
    oportunidades[#oportunidades + 1] = "Núcleo emergente (" .. #nucleo .. " notas): " .. table.concat(titulos, ", ")
  end

  -- Tags maduros
  local maduros = discover.tags_maduros()
  for _, t in ipairs(maduros) do
    oportunidades[#oportunidades + 1] = "Tag maduro sin estructura: " .. t.nombre .. " (" .. t.cantidad .. " notas)"
  end

  if #oportunidades == 0 then
    lineas[#lineas + 1] = "Ninguna."
  else
    for _, o in ipairs(oportunidades) do
      lineas[#lineas + 1] = "- " .. o
    end
  end

  local dir = config.dir_zettel()
  vim.fn.mkdir(dir, "p")
  local ruta = dir .. "/salud.md"
  vim.fn.writefile(lineas, ruta)

  return ruta
end

return M
