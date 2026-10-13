local config = require("zettel.config")
local id_mod = require("zettel.id")
local index = require("zettel.index")
local parser = require("zettel.parser")
local ui = require("zettel.ui")

local M = {}

-- ── Plantillas por defecto ───────────────────────────────────

local plantillas_defecto = {
  ["fugaz.md"] = [[---
id: {{id}}
titulo: {{titulo}}
tags: []
---

]],
  ["permanente.md"] = [[---
id: {{id}}
titulo: {{titulo}}
tags: []
---

]],
  ["estructura.md"] = [[---
id: {{id}}
titulo: {{titulo}}
tags: []
---

]],
  ["fuentes/libro.md"] = [[---
id: {{id}}
titulo: {{titulo}}
autor:
formato: libro
tags: []
---

]],
  ["fuentes/video.md"] = [[---
id: {{id}}
titulo: {{titulo}}
autor:
formato: video
tags: []
---

]],
  ["fuentes/articulo.md"] = [[---
id: {{id}}
titulo: {{titulo}}
autor:
formato: articulo
tags: []
---

]],
}

--- Asegura que las plantillas por defecto existen en .zettel/plantillas/.
function M.asegurar_plantillas()
  local dir = config.dir_zettel() .. "/plantillas"
  vim.fn.mkdir(dir .. "/fuentes", "p")

  for nombre, contenido in pairs(plantillas_defecto) do
    local ruta = dir .. "/" .. nombre
    if vim.fn.filereadable(ruta) == 0 then
      vim.fn.writefile(vim.split(contenido, "\n", { plain = true }), ruta)
    end
  end
end

--- Asegura que .zettel/.gitignore existe con las entradas necesarias.
function M.asegurar_gitignore()
  local dir = config.dir_zettel()
  vim.fn.mkdir(dir, "p")
  local ruta = dir .. "/.gitignore"
  if vim.fn.filereadable(ruta) == 0 then
    vim.fn.writefile({ "index.json", "salud.md" }, ruta)
  end
end

--- Inicializa la estructura .zettel/ si es necesario.
function M.asegurar_estructura()
  local cfg = config.get()
  vim.fn.mkdir(cfg.raiz, "p")
  for _, sub in pairs(cfg.carpetas) do
    vim.fn.mkdir(cfg.raiz .. "/" .. sub, "p")
  end
  M.asegurar_plantillas()
  M.asegurar_gitignore()
end

-- ── Leer plantilla ───────────────────────────────────────────

--- Lee una plantilla y reemplaza los marcadores.
--- @param nombre_plantilla string ruta relativa dentro de .zettel/plantillas/
--- @param vars table { id, titulo, fecha, formato }
--- @return string[] líneas
local function aplicar_plantilla(nombre_plantilla, vars)
  local ruta = config.dir_zettel() .. "/plantillas/" .. nombre_plantilla
  local ok, lines = pcall(vim.fn.readfile, ruta)
  if not ok or not lines then
    ui.error("No se pudo leer la plantilla: " .. ruta)
    return {}
  end

  local resultado = {}
  for _, linea in ipairs(lines) do
    local l = linea
    for clave, valor in pairs(vars) do
      l = l:gsub("{{" .. clave .. "}}", valor)
    end
    resultado[#resultado + 1] = l
  end
  return resultado
end

--- Genera un slug a partir del título.
--- @param titulo string
--- @return string
local function slugificar(titulo)
  local s = titulo:lower()
  -- Reemplazar acentos comunes
  local acentos = {
    ["á"] = "a", ["é"] = "e", ["í"] = "i", ["ó"] = "o", ["ú"] = "u",
    ["ñ"] = "n", ["ü"] = "u",
  }
  for acento, reemplazo in pairs(acentos) do
    s = s:gsub(acento, reemplazo)
  end
  s = s:gsub("[^%w]+", "-")
  s = s:gsub("^%-+", ""):gsub("%-+$", "")
  return s
end

--- Devuelve el nombre de archivo para una nota.
--- @param id string
--- @param titulo string
--- @return string
local function nombre_archivo(id, titulo)
  if config.get().slug_en_nombre then
    return id .. "-" .. slugificar(titulo) .. ".md"
  end
  return id .. ".md"
end

-- ── Crear notas ──────────────────────────────────────────────

--- Crea una nota y la abre en el buffer actual.
--- @param tipo string "inbox"|"permanente"|"estructura"
--- @param titulo string
function M.nueva(tipo, titulo)
  M.asegurar_estructura()

  local mapa_carpeta = {
    inbox = "inbox",
    permanente = "permanentes",
    estructura = nil, -- raíz
  }

  local mapa_plantilla = {
    inbox = "fugaz.md",
    permanente = "permanente.md",
    estructura = "estructura.md",
  }

  local carpeta_nombre = mapa_carpeta[tipo]
  local dir
  if carpeta_nombre then
    dir = config.carpeta(carpeta_nombre)
  else
    dir = config.get().raiz
  end

  local id = id_mod.generar(function(id_candidato) return index.id_ocupado(id_candidato) end)
  local fecha = os.date("%Y-%m-%d")
  local vars = { id = id, titulo = titulo, fecha = fecha }

  local lines = aplicar_plantilla(mapa_plantilla[tipo], vars)
  local archivo = nombre_archivo(id, titulo)
  local ruta = dir .. "/" .. archivo

  vim.fn.mkdir(dir, "p")
  vim.fn.writefile(lines, ruta)

  -- Registrar en el índice
  local campos = parser.frontmatter(lines)
  if campos then
    local carpeta_logica = carpeta_nombre or "raiz"
    index.registrar({
      id = id,
      ruta = ruta,
      carpeta = carpeta_logica,
      titulo = titulo,
      tags = {},
      enlaces = {},
      sigue_a = nil,
      autor = nil,
      formato = nil,
      mtime = vim.uv.fs_stat(ruta) and vim.uv.fs_stat(ruta).mtime.sec or 0,
    })
  end

  vim.cmd("edit " .. vim.fn.fnameescape(ruta))
  ui.info("Nota creada: " .. titulo)
end

--- Crea una fuente y la abre.
--- @param formato string nombre del formato (libro, video, articulo, etc.)
--- @param titulo string
function M.fuente(formato, titulo)
  M.asegurar_estructura()

  local plantilla = "fuentes/" .. formato .. ".md"
  local plantilla_ruta = config.dir_zettel() .. "/plantillas/" .. plantilla
  if vim.fn.filereadable(plantilla_ruta) == 0 then
    ui.error("No existe la plantilla para formato: " .. formato)
    return
  end

  local dir = config.carpeta("fuentes")
  local id = id_mod.generar(function(id_candidato) return index.id_ocupado(id_candidato) end)
  local fecha = os.date("%Y-%m-%d")
  local vars = { id = id, titulo = titulo, fecha = fecha, formato = formato }

  local lines = aplicar_plantilla(plantilla, vars)
  local archivo = nombre_archivo(id, titulo)
  local ruta = dir .. "/" .. archivo

  vim.fn.mkdir(dir, "p")
  vim.fn.writefile(lines, ruta)

  index.registrar({
    id = id,
    ruta = ruta,
    carpeta = "fuentes",
    titulo = titulo,
    tags = {},
    enlaces = {},
    sigue_a = nil,
    autor = nil,
    formato = formato,
    mtime = vim.uv.fs_stat(ruta) and vim.uv.fs_stat(ruta).mtime.sec or 0,
  })

  vim.cmd("edit " .. vim.fn.fnameescape(ruta))
  ui.info("Fuente creada: " .. titulo .. " (" .. formato .. ")")
end

--- Lista los formatos de fuente disponibles (basado en plantillas existentes).
--- @return string[]
function M.formatos_fuente()
  local dir = config.dir_zettel() .. "/plantillas/fuentes"
  if vim.fn.isdirectory(dir) == 0 then return {} end

  local formatos = {}
  local handle = vim.uv.fs_scandir(dir)
  if not handle then return {} end

  while true do
    local nombre, tipo = vim.uv.fs_scandir_next(handle)
    if not nombre then break end
    if tipo == "file" and nombre:match("%.md$") then
      formatos[#formatos + 1] = nombre:gsub("%.md$", "")
    end
  end

  table.sort(formatos)
  return formatos
end

--- Promueve la nota actual de inbox a permanentes.
--- Si no tiene al menos un tag y un enlace saliente, avisa y pide confirmación.
function M.promover()
  local ruta = vim.api.nvim_buf_get_name(0)
  if ruta == "" then
    ui.advertir("El buffer no tiene archivo.")
    return
  end

  local cfg = config.get()
  local dir_inbox = config.carpeta("inbox")
  if ruta:sub(1, #dir_inbox) ~= dir_inbox then
    ui.advertir("Solo se pueden promover notas de " .. cfg.carpetas.inbox .. "/.")
    return
  end

  local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  local campos = parser.frontmatter(lines)
  if not campos or not campos.id then
    ui.advertir("La nota no tiene frontmatter válido.")
    return
  end

  local id_nota = tostring(campos.id)
  local titulo = campos.titulo or id_nota

  -- Verificar tags y enlaces
  local tiene_tags = campos.tags and #campos.tags > 0
  local enlaces = parser.enlaces(lines)
  local tiene_enlaces = #enlaces > 0
  local avisos = {}
  if not tiene_tags then avisos[#avisos + 1] = "sin tags" end
  if not tiene_enlaces then avisos[#avisos + 1] = "sin enlaces salientes" end

  local hacer = function()
    local nombre_archivo_actual = vim.fn.fnamemodify(ruta, ":t")
    local dir_perm = config.carpeta("permanentes")
    vim.fn.mkdir(dir_perm, "p")
    local nueva_ruta = dir_perm .. "/" .. nombre_archivo_actual

    -- Guardar cambios del buffer antes de mover
    if vim.bo.modified then
      vim.cmd("write")
    end

    vim.fn.rename(ruta, nueva_ruta)

    -- Actualizar índice
    local entrada = index.obtener(id_nota)
    if entrada then
      entrada.ruta = nueva_ruta
      entrada.carpeta = "permanentes"
      index.guardar()
    end

    -- Reabrir en la nueva ruta
    vim.cmd("edit " .. vim.fn.fnameescape(nueva_ruta))
    -- Limpiar buffer viejo
    local bufs = vim.api.nvim_list_bufs()
    for _, b in ipairs(bufs) do
      if vim.api.nvim_buf_get_name(b) == ruta then
        vim.api.nvim_buf_delete(b, { force = true })
      end
    end

    ui.info("Nota promovida: " .. titulo)
  end

  if #avisos > 0 then
    vim.ui.select({ "Sí", "No" }, {
      prompt = "La nota está " .. table.concat(avisos, " y ") .. ". ¿Promover igual?",
    }, function(elegido)
      if elegido == "Sí" then hacer() end
    end)
  else
    hacer()
  end
end

--- Extrae la selección visual a una nueva nota permanente.
--- Reemplaza la selección por [[ID|título]].
--- @param linea1 number línea inicio (1-indexed)
--- @param linea2 number línea fin (1-indexed)
function M.extraer(linea1, linea2)
  local ruta_origen = vim.api.nvim_buf_get_name(0)
  if ruta_origen == "" then
    ui.advertir("El buffer no tiene archivo.")
    return
  end

  -- Obtener las líneas seleccionadas
  local lines_sel = vim.api.nvim_buf_get_lines(0, linea1 - 1, linea2, false)
  if #lines_sel == 0 then
    ui.advertir("No hay texto seleccionado.")
    return
  end

  ui.input("Título de la nueva nota: ", function(titulo)
    if not titulo then return end

    M.asegurar_estructura()
    local dir = config.carpeta("permanentes")
    local id = id_mod.generar(function(id_candidato) return index.id_ocupado(id_candidato) end)
    local fecha = os.date("%Y-%m-%d")
    local vars = { id = id, titulo = titulo, fecha = fecha }

    local plantilla_lines = aplicar_plantilla("permanente.md", vars)

    -- Insertar el texto seleccionado después del frontmatter
    local contenido = {}
    for _, l in ipairs(plantilla_lines) do
      contenido[#contenido + 1] = l
    end
    for _, l in ipairs(lines_sel) do
      contenido[#contenido + 1] = l
    end

    local archivo = nombre_archivo(id, titulo)
    local nueva_ruta = dir .. "/" .. archivo

    vim.fn.mkdir(dir, "p")
    vim.fn.writefile(contenido, nueva_ruta)

    -- Registrar en el índice
    index.registrar({
      id = id,
      ruta = nueva_ruta,
      carpeta = "permanentes",
      titulo = titulo,
      tags = {},
      enlaces = parser.enlaces(contenido),
      sigue_a = nil,
      autor = nil,
      formato = nil,
      mtime = vim.uv.fs_stat(nueva_ruta) and vim.uv.fs_stat(nueva_ruta).mtime.sec or 0,
    })

    -- Reemplazar la selección por el enlace en el buffer original
    local enlace = "[[" .. id .. "|" .. titulo .. "]]"
    vim.api.nvim_buf_set_lines(0, linea1 - 1, linea2, false, { enlace })

    ui.info("Nota extraída: " .. titulo)
  end)
end

-- ── Operaciones de tags masivas ──────────────────────────────

--- Reemplaza un tag por otro en el frontmatter de un archivo.
--- @param ruta string
--- @param tag_viejo string
--- @param tag_nuevo string
--- @return boolean modificado
function M._reemplazar_tag_en_archivo(ruta, tag_viejo, tag_nuevo)
  local ok, lines = pcall(vim.fn.readfile, ruta)
  if not ok or not lines then return false end

  local campos, fin = parser.frontmatter(lines)
  if not campos or not fin or not campos.tags then return false end

  local modificado = false
  for i, t in ipairs(campos.tags) do
    if t == tag_viejo then
      if tag_nuevo then
        -- Renombrar: verificar que no duplique
        local ya_existe = false
        for _, t2 in ipairs(campos.tags) do
          if t2 == tag_nuevo then ya_existe = true; break end
        end
        if ya_existe then
          table.remove(campos.tags, i)
        else
          campos.tags[i] = tag_nuevo
        end
      else
        table.remove(campos.tags, i)
      end
      modificado = true
      break
    end
  end

  if not modificado then return false end

  -- Reescribir el archivo
  local orden = { "id", "titulo", "autor", "formato", "tags", "sigue_a" }
  local nuevas = parser.serializar_frontmatter(campos, orden)
  for i = fin + 1, #lines do
    nuevas[#nuevas + 1] = lines[i]
  end
  vim.fn.writefile(nuevas, ruta)

  -- Actualizar índice
  index.reindexar_archivo(ruta)

  -- Actualizar buffer si está abierto
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_get_name(buf) == ruta and vim.api.nvim_buf_is_loaded(buf) then
      vim.api.nvim_buf_call(buf, function()
        vim.cmd("edit!")
      end)
    end
  end

  return true
end

--- Renombra un tag en todas las notas.
--- @param tag_viejo string
--- @param tag_nuevo string
--- @param confirmar boolean si es true, pide confirmación
function M.renombrar_tag(tag_viejo, tag_nuevo, confirmar)
  index.cargar()

  -- Encontrar notas afectadas
  local afectadas = {}
  for _, e in ipairs(index.todas()) do
    for _, t in ipairs(e.tags) do
      if t.nombre == tag_viejo then
        afectadas[#afectadas + 1] = e
        break
      end
    end
  end

  if #afectadas == 0 then
    ui.info("No hay notas con el tag '" .. tag_viejo .. "'.")
    return
  end

  local hacer = function()
    local conteo = 0
    for _, e in ipairs(afectadas) do
      if M._reemplazar_tag_en_archivo(e.ruta, tag_viejo, tag_nuevo) then
        conteo = conteo + 1
      end
    end
    ui.info("Tag renombrado: " .. tag_viejo .. " → " .. tag_nuevo .. " (" .. conteo .. " nota" .. (conteo ~= 1 and "s" or "") .. ").")
  end

  if confirmar then
    local nombres = {}
    for _, e in ipairs(afectadas) do
      nombres[#nombres + 1] = e.titulo
    end
    vim.ui.select({ "Sí", "No" }, {
      prompt = "Renombrar '" .. tag_viejo .. "' → '" .. tag_nuevo .. "' en " .. #afectadas .. " nota(s):\n" .. table.concat(nombres, ", "),
    }, function(elegido)
      if elegido == "Sí" then hacer() end
    end)
  else
    hacer()
  end
end

--- Fusiona un tag en otro (el origen desaparece).
--- @param tag_origen string el tag que se elimina
--- @param tag_destino string el tag que permanece
--- @param confirmar boolean
function M.fusionar_tag(tag_origen, tag_destino, confirmar)
  -- Fusionar es renombrar: las notas que tengan tag_origen pasan a tener tag_destino.
  -- Si ya tienen tag_destino, simplemente se elimina tag_origen.
  index.cargar()

  local afectadas = {}
  for _, e in ipairs(index.todas()) do
    for _, t in ipairs(e.tags) do
      if t.nombre == tag_origen then
        afectadas[#afectadas + 1] = e
        break
      end
    end
  end

  if #afectadas == 0 then
    ui.info("No hay notas con el tag '" .. tag_origen .. "'.")
    return
  end

  local hacer = function()
    local conteo = 0
    for _, e in ipairs(afectadas) do
      if M._reemplazar_tag_en_archivo(e.ruta, tag_origen, tag_destino) then
        conteo = conteo + 1
      end
    end
    ui.info("Tag fusionado: " .. tag_origen .. " → " .. tag_destino .. " (" .. conteo .. " nota" .. (conteo ~= 1 and "s" or "") .. ").")
  end

  if confirmar then
    local nombres = {}
    for _, e in ipairs(afectadas) do
      nombres[#nombres + 1] = e.titulo
    end
    vim.ui.select({ "Sí", "No" }, {
      prompt = "Fusionar '" .. tag_origen .. "' en '" .. tag_destino .. "' (" .. #afectadas .. " nota(s)):\n" .. table.concat(nombres, ", "),
    }, function(elegido)
      if elegido == "Sí" then hacer() end
    end)
  else
    hacer()
  end
end

-- ── Cambiar título ───────────────────────────────────────────

--- Cambia el título de la nota actual y ofrece actualizar enlaces.
--- @param titulo_nuevo string
function M.cambiar_titulo(titulo_nuevo)
  local ruta = vim.api.nvim_buf_get_name(0)
  if ruta == "" then
    ui.advertir("El buffer no tiene archivo.")
    return
  end

  local buf_lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  local campos, fin = parser.frontmatter(buf_lines)
  if not campos or not fin then
    ui.advertir("La nota no tiene frontmatter válido.")
    return
  end

  local titulo_viejo = campos.titulo
  local id_nota = tostring(campos.id)

  -- Actualizar frontmatter en el buffer
  campos.titulo = titulo_nuevo
  local orden = { "id", "titulo", "autor", "formato", "tags", "sigue_a" }
  local nuevas = parser.serializar_frontmatter(campos, orden)
  vim.api.nvim_buf_set_lines(0, 0, fin, false, nuevas)

  ui.info("Título cambiado: " .. titulo_viejo .. " → " .. titulo_nuevo)

  -- Buscar enlaces que referencien esta nota con el título viejo
  index.cargar()
  local por_actualizar = {}
  for _, e in ipairs(index.todas()) do
    for _, enlace in ipairs(e.enlaces) do
      if enlace.id == id_nota then
        -- Leer el archivo para verificar el texto del enlace
        local ok_read, lines = pcall(vim.fn.readfile, e.ruta)
        if ok_read and lines and enlace.linea <= #lines then
          local linea = lines[enlace.linea]
          local patron = "%[%[" .. id_nota .. "|" .. vim.pesc(titulo_viejo) .. "%]%]"
          if linea:match(patron) then
            por_actualizar[#por_actualizar + 1] = { entrada = e, linea_num = enlace.linea }
          end
        end
      end
    end
  end

  if #por_actualizar == 0 then return end

  local nombres = {}
  for _, item in ipairs(por_actualizar) do
    nombres[#nombres + 1] = item.entrada.titulo
  end

  vim.ui.select({ "Sí", "No" }, {
    prompt = "¿Actualizar enlaces en " .. #por_actualizar .. " nota(s)?\n" .. table.concat(nombres, ", "),
  }, function(elegido)
    if elegido ~= "Sí" then return end

    local viejo_enlace = "[[" .. id_nota .. "|" .. titulo_viejo .. "]]"
    local nuevo_enlace = "[[" .. id_nota .. "|" .. titulo_nuevo .. "]]"

    for _, item in ipairs(por_actualizar) do
      local ok_read, lines = pcall(vim.fn.readfile, item.entrada.ruta)
      if ok_read and lines then
        local modificado = false
        for i, l in ipairs(lines) do
          local nueva, n = l:gsub(vim.pesc(viejo_enlace), nuevo_enlace)
          if n > 0 then
            lines[i] = nueva
            modificado = true
          end
        end
        if modificado then
          vim.fn.writefile(lines, item.entrada.ruta)
          index.reindexar_archivo(item.entrada.ruta)

          -- Refrescar buffer si está abierto
          for _, buf in ipairs(vim.api.nvim_list_bufs()) do
            if vim.api.nvim_buf_get_name(buf) == item.entrada.ruta and vim.api.nvim_buf_is_loaded(buf) then
              vim.api.nvim_buf_call(buf, function()
                vim.cmd("edit!")
              end)
            end
          end
        end
      end
    end
    ui.info("Enlaces actualizados en " .. #por_actualizar .. " nota(s).")
  end)
end

--- Borra la nota del buffer actual de disco y del índice.
--- Pide confirmación antes de borrar.
function M.borrar()
  local ruta = vim.api.nvim_buf_get_name(0)
  if ruta == "" then
    ui.advertir("El buffer no tiene archivo.")
    return
  end

  local cfg = config.get()
  if ruta:sub(1, #cfg.raiz) ~= cfg.raiz or not ruta:match("%.md$") then
    ui.advertir("No estás en una nota del zettel.")
    return
  end

  -- Obtener info de la nota
  local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  local campos = parser.frontmatter(lines)
  local titulo = campos and campos.titulo or vim.fn.fnamemodify(ruta, ":t")
  local id_nota = campos and tostring(campos.id) or nil

  -- Verificar si hay backlinks
  local aviso_backlinks = ""
  if id_nota then
    local bl = index.backlinks(id_nota)
    if #bl > 0 then
      local nombres = {}
      for _, b in ipairs(bl) do
        nombres[#nombres + 1] = b.entrada.titulo
      end
      aviso_backlinks = "\nEnlazada desde: " .. table.concat(nombres, ", ")
    end
  end

  vim.ui.select({ "Sí", "No" }, {
    prompt = "¿Borrar \"" .. titulo .. "\"?" .. aviso_backlinks,
  }, function(elegido)
    if elegido ~= "Sí" then return end

    -- Cerrar el buffer
    local buf = vim.api.nvim_get_current_buf()
    vim.cmd("bprevious")
    vim.api.nvim_buf_delete(buf, { force = true })

    -- Borrar archivo
    vim.fn.delete(ruta)

    -- Quitar del índice
    if id_nota then
      index._datos[id_nota] = nil
      index.guardar()
    end

    ui.info("Nota borrada: " .. titulo)
  end)
end

return M
