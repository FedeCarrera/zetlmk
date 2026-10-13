local config = require("zettel.config")
local index = require("zettel.index")
local parser = require("zettel.parser")
local picker = require("zettel.picker")
local ui = require("zettel.ui")

local M = {}

-- Longitud mínima de un título para considerarlo en menciones (evitar ruido).
local TITULO_MIN_LEN = 4

-- ── Helpers ──────────────────────────────────────────────────

--- Obtiene el ID de la nota en el buffer actual.
--- @return string|nil id, table|nil campos
local function nota_actual()
  local ruta = vim.api.nvim_buf_get_name(0)
  if ruta == "" then return nil, nil end
  local ok, lines = pcall(vim.fn.readfile, ruta)
  if not ok or not lines then return nil, nil end
  local campos = parser.frontmatter(lines)
  if not campos or not campos.id then return nil, nil end
  return tostring(campos.id), campos
end

--- Formatea una entrada para el selector.
local function formato_nota(entrada)
  local tags_str = ""
  if entrada.tags and #entrada.tags > 0 then
    local nombres = {}
    for _, t in ipairs(entrada.tags) do
      nombres[#nombres + 1] = t.nombre
    end
    tags_str = " · " .. table.concat(nombres, ", ")
  end
  return entrada.titulo .. tags_str .. " · " .. entrada.carpeta
end

-- ── Vecindario ───────────────────────────────────────────────

--- Muestra las notas a uno y dos saltos (enlaces y backlinks).
function M.vecindario()
  local id_actual = nota_actual()
  if not id_actual then
    ui.advertir("No estás en una nota del zettel.")
    return
  end

  index.cargar()
  local entrada_actual = index.obtener(id_actual)
  if not entrada_actual then
    ui.advertir("La nota actual no está en el índice.")
    return
  end

  -- Salto 1: enlaces salientes + backlinks
  local salto1 = {}
  local visto = { [id_actual] = true }

  for _, enlace in ipairs(entrada_actual.enlaces) do
    if not visto[enlace.id] and index.existe(enlace.id) then
      visto[enlace.id] = true
      salto1[#salto1 + 1] = enlace.id
    end
  end
  for _, bl in ipairs(index.backlinks(id_actual)) do
    if not visto[bl.entrada.id] then
      visto[bl.entrada.id] = true
      salto1[#salto1 + 1] = bl.entrada.id
    end
  end

  -- Salto 2: desde cada nota del salto 1
  local salto2 = {}
  for _, id1 in ipairs(salto1) do
    local e1 = index.obtener(id1)
    if e1 then
      for _, enlace in ipairs(e1.enlaces) do
        if not visto[enlace.id] and index.existe(enlace.id) then
          visto[enlace.id] = true
          salto2[#salto2 + 1] = enlace.id
        end
      end
      for _, bl in ipairs(index.backlinks(id1)) do
        if not visto[bl.entrada.id] then
          visto[bl.entrada.id] = true
          salto2[#salto2 + 1] = bl.entrada.id
        end
      end
    end
  end

  -- Construir líneas para la ventana flotante
  local lineas = {}

  lineas[#lineas + 1] = "## Nota actual"
  lineas[#lineas + 1] = "[[" .. id_actual .. "|" .. entrada_actual.titulo .. "]]"
  lineas[#lineas + 1] = ""

  lineas[#lineas + 1] = "## A un salto (" .. #salto1 .. ")"
  lineas[#lineas + 1] = ""
  if #salto1 == 0 then
    lineas[#lineas + 1] = "Ninguna."
  else
    for _, id in ipairs(salto1) do
      local e = index.obtener(id)
      if e then
        lineas[#lineas + 1] = "- [[" .. id .. "|" .. e.titulo .. "]]"
      end
    end
  end

  lineas[#lineas + 1] = ""
  lineas[#lineas + 1] = "## A dos saltos (" .. #salto2 .. ")"
  lineas[#lineas + 1] = ""
  if #salto2 == 0 then
    lineas[#lineas + 1] = "Ninguna."
  else
    for _, id in ipairs(salto2) do
      local e = index.obtener(id)
      if e then
        lineas[#lineas + 1] = "- [[" .. id .. "|" .. e.titulo .. "]]"
      end
    end
  end

  local buf, win = ui.flotante(lineas, { titulo = "Vecindario de: " .. entrada_actual.titulo })

  -- gd para seguir enlaces en la ventana flotante
  vim.keymap.set("n", "gd", function()
    local enlace = parser.enlace_en_cursor()
    if enlace then
      local destino = index.obtener(enlace.id)
      if destino then
        vim.api.nvim_win_close(win, true)
        vim.cmd("edit " .. vim.fn.fnameescape(destino.ruta))
      end
    end
  end, { buffer = buf, desc = "Zettel: seguir enlace" })

  -- Enter también sigue el enlace
  vim.keymap.set("n", "<CR>", function()
    local enlace = parser.enlace_en_cursor()
    if enlace then
      local destino = index.obtener(enlace.id)
      if destino then
        vim.api.nvim_win_close(win, true)
        vim.cmd("edit " .. vim.fn.fnameescape(destino.ruta))
      end
    end
  end, { buffer = buf })
end

-- ── Menciones ────────────────────────────────────────────────

--- Busca menciones del título de la nota actual en otras notas (sin enlace),
--- y títulos de otras notas que aparecen en la actual (sin enlace).
function M.menciones()
  local id_actual, campos = nota_actual()
  if not id_actual or not campos then
    ui.advertir("No estás en una nota del zettel.")
    return
  end

  index.cargar()
  local titulo_actual = campos.titulo or ""
  local entrada_actual = index.obtener(id_actual)
  if not entrada_actual then return end

  -- Leer el contenido de la nota actual (sin frontmatter)
  local ruta_actual = vim.api.nvim_buf_get_name(0)
  local ok, lines_actual = pcall(vim.fn.readfile, ruta_actual)
  if not ok or not lines_actual then return end
  local _, fin_fm = parser.frontmatter(lines_actual)
  local cuerpo_actual = ""
  if fin_fm then
    local partes = {}
    for i = fin_fm + 1, #lines_actual do
      partes[#partes + 1] = lines_actual[i]
    end
    cuerpo_actual = table.concat(partes, "\n")
  end

  -- IDs ya enlazados desde la actual
  local enlazados = { [id_actual] = true }
  for _, e in ipairs(entrada_actual.enlaces) do
    enlazados[e.id] = true
  end

  local resultados = {}

  for _, otra in ipairs(index.todas()) do
    if otra.id == id_actual then goto continue end

    -- 1. ¿El título de otra nota aparece en la actual sin enlace?
    if #otra.titulo >= TITULO_MIN_LEN and not enlazados[otra.id] then
      if cuerpo_actual:lower():find(otra.titulo:lower(), 1, true) then
        resultados[#resultados + 1] = {
          entrada = otra,
          tipo = "título en esta nota",
        }
      end
    end

    -- 2. ¿El título de la actual aparece en otra nota sin enlace hacia acá?
    if #titulo_actual >= TITULO_MIN_LEN then
      -- Verificar que la otra nota no enlaza ya a la actual
      local ya_enlaza = false
      for _, e in ipairs(otra.enlaces) do
        if e.id == id_actual then
          ya_enlaza = true
          break
        end
      end

      if not ya_enlaza then
        local ok2, lines_otra = pcall(vim.fn.readfile, otra.ruta)
        if ok2 and lines_otra then
          local _, fin2 = parser.frontmatter(lines_otra)
          if fin2 then
            for i = fin2 + 1, #lines_otra do
              if lines_otra[i]:lower():find(titulo_actual:lower(), 1, true) then
                resultados[#resultados + 1] = {
                  entrada = otra,
                  tipo = "menciona esta nota",
                }
                break
              end
            end
          end
        end
      end
    end

    ::continue::
  end

  if #resultados == 0 then
    ui.info("No se encontraron menciones sin enlace.")
    return
  end

  picker.elegir({
    titulo = "Menciones sin enlace",
    entradas = resultados,
    formato = function(r)
      return r.entrada.titulo .. " (" .. r.tipo .. ")"
    end,
    on_elegir = function(r)
      vim.cmd("edit " .. vim.fn.fnameescape(r.entrada.ruta))
    end,
  })
end

-- ── Relacionadas ─────────────────────────────────────────────

--- Notas que comparten al menos N tags con la actual y no están enlazadas.
function M.relacionadas()
  local id_actual = nota_actual()
  if not id_actual then
    ui.advertir("No estás en una nota del zettel.")
    return
  end

  index.cargar()
  local entrada_actual = index.obtener(id_actual)
  if not entrada_actual then return end

  local cfg = config.get()
  local min_tags = cfg.descubrir.relacionadas_min_tags

  -- Tags de la nota actual (resolviendo alias)
  local tags_actual = {}
  for _, t in ipairs(entrada_actual.tags) do
    local nombre = index.resolver_alias(t.nombre)
    tags_actual[nombre] = true
  end

  -- IDs ya enlazados
  local enlazados = { [id_actual] = true }
  for _, e in ipairs(entrada_actual.enlaces) do
    enlazados[e.id] = true
  end
  for _, bl in ipairs(index.backlinks(id_actual)) do
    enlazados[bl.entrada.id] = true
  end

  local resultados = {}
  for _, otra in ipairs(index.todas()) do
    if enlazados[otra.id] then goto continue end

    local compartidos = 0
    for _, t in ipairs(otra.tags) do
      local nombre = index.resolver_alias(t.nombre)
      if tags_actual[nombre] then
        compartidos = compartidos + 1
      end
    end

    if compartidos >= min_tags then
      resultados[#resultados + 1] = {
        entrada = otra,
        compartidos = compartidos,
      }
    end
    ::continue::
  end

  if #resultados == 0 then
    ui.info("No se encontraron notas relacionadas.")
    return
  end

  table.sort(resultados, function(a, b) return a.compartidos > b.compartidos end)

  picker.elegir({
    titulo = "Relacionadas",
    entradas = resultados,
    formato = function(r)
      return r.entrada.titulo .. " (" .. r.compartidos .. " tags en común)"
    end,
    on_elegir = function(r)
      vim.cmd("edit " .. vim.fn.fnameescape(r.entrada.ruta))
    end,
  })
end

-- ── Azar ─────────────────────────────────────────────────────

--- Abre una permanente al azar, opcionalmente dentro de un tag.
--- @param tag string|nil
function M.azar(tag)
  index.cargar()

  local candidatas = {}
  for _, e in ipairs(index.todas()) do
    if e.carpeta == "permanentes" then
      if tag then
        for _, t in ipairs(e.tags) do
          local nombre = index.resolver_alias(t.nombre)
          if nombre == tag then
            candidatas[#candidatas + 1] = e
            break
          end
        end
      else
        candidatas[#candidatas + 1] = e
      end
    end
  end

  if #candidatas == 0 then
    local msg = tag and ("No hay permanentes con el tag '" .. tag .. "'.") or "No hay permanentes."
    ui.info(msg)
    return
  end

  math.randomseed(os.time())
  local elegida = candidatas[math.random(#candidatas)]
  vim.cmd("edit " .. vim.fn.fnameescape(elegida.ruta))
  ui.info("Azar: " .. elegida.titulo)
end

-- ── Núcleos y oportunidades (para health.lua) ────────────────

--- Encuentra componentes conexos de permanentes no alcanzadas por estructuras.
--- @param alcanzables table set de IDs alcanzables desde estructuras
--- @return table[] lista de componentes, cada uno es una lista de entradas
function M.nucleos_emergentes(alcanzables)
  index.cargar()
  local cfg = config.get()

  -- Permanentes no alcanzadas
  local no_alcanzadas = {}
  for _, e in ipairs(index.todas()) do
    if e.carpeta == "permanentes" and not alcanzables[e.id] then
      no_alcanzadas[e.id] = e
    end
  end

  -- Construir grafo no dirigido entre no alcanzadas
  local vecinos = {}
  for id in pairs(no_alcanzadas) do
    vecinos[id] = {}
  end

  for id, e in pairs(no_alcanzadas) do
    for _, enlace in ipairs(e.enlaces) do
      if no_alcanzadas[enlace.id] then
        vecinos[id][enlace.id] = true
        vecinos[enlace.id][id] = true
      end
    end
  end

  -- BFS para componentes conexos
  local visitados = {}
  local componentes = {}

  for id in pairs(no_alcanzadas) do
    if not visitados[id] then
      local componente = {}
      local cola = { id }
      visitados[id] = true

      while #cola > 0 do
        local actual = table.remove(cola, 1)
        componente[#componente + 1] = no_alcanzadas[actual]
        for vecino in pairs(vecinos[actual] or {}) do
          if not visitados[vecino] then
            visitados[vecino] = true
            cola[#cola + 1] = vecino
          end
        end
      end

      if #componente >= cfg.descubrir.nucleo_min_notas then
        componentes[#componentes + 1] = componente
      end
    end
  end

  -- Ordenar por tamaño descendente
  table.sort(componentes, function(a, b) return #a > #b end)
  return componentes
end

--- Tags con muchas notas pero sin ninguna estructura que los cubra.
--- @return table[] lista de { nombre, cantidad }
function M.tags_maduros()
  index.cargar()
  local cfg = config.get()

  -- Tags de las estructuras
  local tags_estructura = {}
  for _, e in ipairs(index.todas()) do
    if e.carpeta == "raiz" then
      for _, t in ipairs(e.tags) do
        tags_estructura[index.resolver_alias(t.nombre)] = true
      end
    end
  end

  -- Tags con suficientes notas que no están cubiertos
  local tags = index.tags()
  local resultado = {}
  for _, t in ipairs(tags) do
    if t.cantidad >= cfg.descubrir.tag_maduro_min_notas and not tags_estructura[t.nombre] then
      resultado[#resultado + 1] = t
    end
  end

  return resultado
end

return M
