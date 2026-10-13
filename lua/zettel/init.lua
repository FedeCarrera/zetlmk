local M = {}

M._configurado = false

function M.setup(opts)
  local config = require("zettel.config")
  config.setup(opts)
  M._configurado = true

  -- Mapeo global: <leader>zn para crear nota
  if config.get().mapeos then
    vim.keymap.set("n", "<leader>zn", function()
      vim.cmd("Zettel nueva")
    end, { desc = "Zettel: nueva nota" })
  end
end

--- Asegura que el plugin está configurado (carga diferida).
local function asegurar_setup()
  if not M._configurado then
    M.setup({})
  end
end

-- ── Subcomandos ──────────────────────────────────────────────

local subcomandos = {
  "nueva",
  "fuente",
  "enlazar",
  "buscar",
  "fuentes",
  "tag",
  "borrar",
  "reindexar",
  "backlinks",
  "promover",
  "extraer",
  "siguiente",
  "anterior",
  "texto",
  "por-tag",
  "recientes",
  "salud",
  "tag-renombrar",
  "tag-fusionar",
  "titulo",
  "vecindario",
  "menciones",
  "relacionadas",
  "azar",
  "consulta",
  "busquedas",
  "tags-candidatos",
}

--- Determina si el buffer actual es una nota del zettel.
--- @return boolean
local function en_nota_zettel()
  local ruta = vim.api.nvim_buf_get_name(0)
  if ruta == "" then return false end
  local config = require("zettel.config")
  local raiz = config.get().raiz
  return ruta:sub(1, #raiz) == raiz and ruta:match("%.md$") ~= nil
end

--- Registra los autocommands para reindexado y mapeos locales.
local _autocmds_registrados = false
local function registrar_autocmds()
  if _autocmds_registrados then return end
  _autocmds_registrados = true

  local grupo = vim.api.nvim_create_augroup("ZettelPlugin", { clear = true })

  -- Reindexar al guardar una nota del zettel
  vim.api.nvim_create_autocmd("BufWritePost", {
    group = grupo,
    pattern = "*.md",
    callback = function(ev)
      local ruta = vim.api.nvim_buf_get_name(ev.buf)
      local config = require("zettel.config")
      local raiz = config.get().raiz
      if ruta:sub(1, #raiz) == raiz then
        -- No indexar salud.md
        if not ruta:match("%.zettel/salud%.md$") then
          require("zettel.index").reindexar_archivo(ruta)
        end
      end
    end,
  })

  -- Mapeos locales al abrir una nota del zettel
  vim.api.nvim_create_autocmd({ "BufRead", "BufNewFile" }, {
    group = grupo,
    pattern = "*.md",
    callback = function(ev)
      local config = require("zettel.config")
      if not config.get().mapeos then return end

      local ruta = vim.api.nvim_buf_get_name(ev.buf)
      local raiz = config.get().raiz
      if ruta:sub(1, #raiz) ~= raiz then return end

      -- gd: seguir enlace
      vim.keymap.set("n", "gd", function()
        require("zettel.links").seguir()
      end, { buffer = ev.buf, desc = "Zettel: seguir enlace" })

      -- ]n / [n: navegación sigue_a
      vim.keymap.set("n", "]n", function()
        require("zettel.links").siguiente()
      end, { buffer = ev.buf, desc = "Zettel: nota siguiente" })
      vim.keymap.set("n", "[n", function()
        require("zettel.links").anterior()
      end, { buffer = ev.buf, desc = "Zettel: nota anterior" })

      -- [[ en modo inserción: insertar enlace
      vim.keymap.set("i", "[[", function()
        local buf_origen = vim.api.nvim_get_current_buf()
        local row, col = unpack(vim.api.nvim_win_get_cursor(0))
        local linea = vim.api.nvim_get_current_line()

        -- Insertar [[ primero por si el usuario cancela
        local nueva = linea:sub(1, col) .. "[[" .. linea:sub(col + 1)
        vim.api.nvim_set_current_line(nueva)
        -- col es 0-indexed; el [[ ocupa posiciones col+1 y col+2 (1-indexed)
        local pos_bracket = col + 1  -- posición 1-indexed donde empieza [[

        vim.cmd("stopinsert")

        vim.schedule(function()
          local index = require("zettel.index")
          local picker_mod = require("zettel.picker")
          local notas = index.todas()
          if #notas == 0 then return end

          picker_mod.elegir({
            titulo = "Enlazar nota",
            entradas = notas,
            formato = function(entrada)
              local tags_str = ""
              if entrada.tags and #entrada.tags > 0 then
                local nombres = {}
                for _, t in ipairs(entrada.tags) do
                  nombres[#nombres + 1] = t.nombre
                end
                tags_str = " · " .. table.concat(nombres, ", ")
              end
              return entrada.titulo .. tags_str .. " · " .. entrada.carpeta
            end,
            on_elegir = function(entrada)
              -- Volver al buffer original por si fzf cambió de ventana
              vim.api.nvim_set_current_buf(buf_origen)
              local lin = vim.api.nvim_buf_get_lines(buf_origen, row - 1, row, false)[1] or ""
              local texto = "[[" .. entrada.id .. "|" .. entrada.titulo .. "]]"
              -- Reemplazar el [[ que insertamos (posición guardada)
              local nueva_lin = lin:sub(1, pos_bracket - 1) .. texto .. lin:sub(pos_bracket + 2)
              vim.api.nvim_buf_set_lines(buf_origen, row - 1, row, false, { nueva_lin })
              vim.api.nvim_win_set_cursor(0, { row, pos_bracket - 1 + #texto })
              vim.cmd("startinsert!")
            end,
          })
        end)
      end, { buffer = ev.buf, desc = "Zettel: insertar enlace" })
    end,
  })

end

-- ── Comando :Zettel ──────────────────────────────────────────

--- Ejecuta un subcomando de :Zettel.
--- @param args table argumentos del comando (de nvim_create_user_command)
function M.ejecutar(args)
  asegurar_setup()
  registrar_autocmds()

  local partes = vim.split(vim.trim(args.args or ""), "%s+", { trimempty = true })
  local sub = partes[1]

  if not sub then
    require("zettel.ui").advertir("Uso: :Zettel <subcomando>. Subcomandos: " .. table.concat(subcomandos, ", "))
    return
  end

  if sub == "nueva" then
    local tipo = partes[2]
    if not tipo then
      -- Elegir tipo
      vim.ui.select({ "inbox", "permanente", "estructura" }, {
        prompt = "Tipo de nota:",
      }, function(elegido)
        if not elegido then return end
        require("zettel.ui").input("Título: ", function(titulo)
          if not titulo then return end
          require("zettel.notes").nueva(elegido, titulo)
        end)
      end)
    else
      if not vim.tbl_contains({ "inbox", "permanente", "estructura" }, tipo) then
        require("zettel.ui").error("Tipo inválido: " .. tipo .. ". Usar: inbox, permanente, estructura")
        return
      end
      require("zettel.ui").input("Título: ", function(titulo)
        if not titulo then return end
        require("zettel.notes").nueva(tipo, titulo)
      end)
    end

  elseif sub == "fuente" then
    local notes = require("zettel.notes")
    notes.asegurar_estructura()
    local formatos = notes.formatos_fuente()
    if #formatos == 0 then
      require("zettel.ui").error("No hay plantillas de fuente.")
      return
    end
    vim.ui.select(formatos, { prompt = "Formato de fuente:" }, function(formato)
      if not formato then return end
      require("zettel.ui").input("Título: ", function(titulo)
        if not titulo then return end
        notes.fuente(formato, titulo)
      end)
    end)

  elseif sub == "enlazar" then
    require("zettel.links").insertar()

  elseif sub == "buscar" then
    require("zettel.links").buscar()

  elseif sub == "fuentes" then
    require("zettel.links").buscar_fuentes()

  elseif sub == "tag" then
    M._cmd_tag()

  elseif sub == "borrar" then
    require("zettel.notes").borrar()

  elseif sub == "backlinks" then
    require("zettel.links").backlinks()

  elseif sub == "promover" then
    require("zettel.notes").promover()

  elseif sub == "extraer" then
    require("zettel.notes").extraer(args.line1, args.line2)

  elseif sub == "siguiente" then
    require("zettel.links").siguiente()

  elseif sub == "anterior" then
    require("zettel.links").anterior()

  elseif sub == "texto" then
    require("zettel.links").texto()

  elseif sub == "por-tag" then
    require("zettel.links").por_tag()

  elseif sub == "recientes" then
    require("zettel.links").recientes()

  elseif sub == "salud" then
    local ruta = require("zettel.health").generar()
    vim.cmd("edit " .. vim.fn.fnameescape(ruta))

  elseif sub == "tag-renombrar" then
    M._cmd_tag_renombrar()

  elseif sub == "tag-fusionar" then
    M._cmd_tag_fusionar()

  elseif sub == "titulo" then
    M._cmd_titulo()

  elseif sub == "vecindario" then
    require("zettel.discover").vecindario()

  elseif sub == "menciones" then
    require("zettel.discover").menciones()

  elseif sub == "relacionadas" then
    require("zettel.discover").relacionadas()

  elseif sub == "azar" then
    require("zettel.discover").azar(partes[2])

  elseif sub == "consulta" then
    -- Si hay argumentos después de "consulta", usarlos como query directa
    local query = table.concat(partes, " ", 2)
    if query == "" then query = nil end
    require("zettel.query").consultar(query)

  elseif sub == "busquedas" then
    require("zettel.query").busquedas_guardadas()

  elseif sub == "tags-candidatos" then
    M._cmd_tags_candidatos()

  elseif sub == "reindexar" then
    require("zettel.index").reindexar_completo()
    require("zettel.ui").info("Índice reconstruido.")

  else
    require("zettel.ui").error("Subcomando desconocido: " .. sub)
  end
end

--- Comando :Zettel tag — agrega un tag a la nota actual.
function M._cmd_tag()
  if not en_nota_zettel() then
    require("zettel.ui").advertir("No estás en una nota del zettel.")
    return
  end

  local index = require("zettel.index")
  local tags_existentes = index.tags()
  local parser = require("zettel.parser")

  -- Leer tags actuales de la nota
  local buf_lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  local campos, linea_fin = parser.frontmatter(buf_lines)
  if not campos then
    require("zettel.ui").error("La nota no tiene frontmatter válido.")
    return
  end

  local tags_nota = campos.tags or {}

  -- Preparar opciones: tags existentes que la nota no tiene + opción de nuevo
  local opciones = {}
  for _, tag in ipairs(tags_existentes) do
    local ya_tiene = false
    for _, t in ipairs(tags_nota) do
      if t == tag.nombre then
        ya_tiene = true
        break
      end
    end
    if not ya_tiene then
      opciones[#opciones + 1] = tag
    end
  end

  -- Agregar opción de tag nuevo
  table.insert(opciones, 1, { nombre = "[nuevo tag]", cantidad = 0 })

  local picker_mod = require("zettel.picker")
  picker_mod.elegir({
    titulo = "Agregar tag",
    entradas = opciones,
    formato = function(e)
      if e.nombre == "[nuevo tag]" then
        return "+ Escribir un tag nuevo"
      end
      return e.nombre .. " (" .. e.cantidad .. ")"
    end,
    on_elegir = function(elegido)
      if elegido.nombre == "[nuevo tag]" then
        require("zettel.ui").input("Tag nuevo: ", function(tag_nuevo)
          if not tag_nuevo then return end
          M._agregar_tag(tag_nuevo)
        end)
      else
        M._agregar_tag(elegido.nombre)
      end
    end,
  })
end

--- Agrega un tag al frontmatter de la nota actual.
--- @param tag string
function M._agregar_tag(tag)
  local parser = require("zettel.parser")
  local buf_lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  local campos, linea_fin = parser.frontmatter(buf_lines)
  if not campos or not linea_fin then return end

  campos.tags = campos.tags or {}
  -- No duplicar
  for _, t in ipairs(campos.tags) do
    if t == tag then
      require("zettel.ui").info("El tag '" .. tag .. "' ya existe en esta nota.")
      return
    end
  end

  table.insert(campos.tags, tag)

  -- Reescribir el frontmatter
  local orden = { "id", "titulo", "autor", "formato", "tags", "sigue_a" }
  local nuevas_lineas = parser.serializar_frontmatter(campos, orden)

  -- Reemplazar las líneas del frontmatter en el buffer
  vim.api.nvim_buf_set_lines(0, 0, linea_fin, false, nuevas_lineas)

  require("zettel.ui").info("Tag agregado: " .. tag)
end

--- Comando :Zettel tag-renombrar
function M._cmd_tag_renombrar()
  local index = require("zettel.index")
  local picker_mod = require("zettel.picker")
  local tags = index.tags()
  if #tags == 0 then
    require("zettel.ui").info("No hay tags.")
    return
  end

  picker_mod.elegir({
    titulo = "Tag a renombrar",
    entradas = tags,
    formato = function(t) return t.nombre .. " (" .. t.cantidad .. ")" end,
    on_elegir = function(tag)
      require("zettel.ui").input("Nuevo nombre para '" .. tag.nombre .. "': ", function(nuevo)
        if not nuevo then return end
        require("zettel.notes").renombrar_tag(tag.nombre, nuevo, true)
      end)
    end,
  })
end

--- Comando :Zettel tag-fusionar
function M._cmd_tag_fusionar()
  local index = require("zettel.index")
  local picker_mod = require("zettel.picker")
  local tags = index.tags()
  if #tags < 2 then
    require("zettel.ui").info("Se necesitan al menos dos tags para fusionar.")
    return
  end

  picker_mod.elegir({
    titulo = "Tag origen (se elimina)",
    entradas = tags,
    formato = function(t) return t.nombre .. " (" .. t.cantidad .. ")" end,
    on_elegir = function(origen)
      -- Filtrar el tag origen de las opciones de destino
      local destinos = {}
      for _, t in ipairs(tags) do
        if t.nombre ~= origen.nombre then
          destinos[#destinos + 1] = t
        end
      end
      picker_mod.elegir({
        titulo = "Tag destino (permanece)",
        entradas = destinos,
        formato = function(t) return t.nombre .. " (" .. t.cantidad .. ")" end,
        on_elegir = function(destino)
          require("zettel.notes").fusionar_tag(origen.nombre, destino.nombre, true)
        end,
      })
    end,
  })
end

--- Comando :Zettel titulo
function M._cmd_titulo()
  if not en_nota_zettel() then
    require("zettel.ui").advertir("No estás en una nota del zettel.")
    return
  end
  require("zettel.ui").input("Nuevo título: ", function(titulo)
    if not titulo then return end
    require("zettel.notes").cambiar_titulo(titulo)
  end)
end

--- Comando :Zettel tags-candidatos — ofrece promover tags inline al frontmatter.
function M._cmd_tags_candidatos()
  if not en_nota_zettel() then
    require("zettel.ui").advertir("No estás en una nota del zettel.")
    return
  end

  local parser = require("zettel.parser")
  local bufnr = vim.api.nvim_get_current_buf()
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)

  -- Obtener tags inline
  local candidatos = parser.tags_inline_ts(bufnr)
  if #candidatos == 0 then
    require("zettel.ui").info("No se encontraron tags inline.")
    return
  end

  -- Obtener tags actuales del frontmatter
  local campos, linea_fin = parser.frontmatter(lines)
  if not campos or not linea_fin then return end
  local tags_actuales = {}
  for _, t in ipairs(campos.tags or {}) do
    tags_actuales[t] = true
  end

  -- Filtrar candidatos que ya están en el frontmatter, y deduplicar
  local vistos = {}
  local nuevos = {}
  for _, c in ipairs(candidatos) do
    if not tags_actuales[c.nombre] and not vistos[c.nombre] then
      vistos[c.nombre] = true
      nuevos[#nuevos + 1] = c
    end
  end

  if #nuevos == 0 then
    require("zettel.ui").info("Todos los tags inline ya están en el frontmatter.")
    return
  end

  local picker_mod = require("zettel.picker")
  picker_mod.elegir({
    titulo = "Tags candidatos (" .. #nuevos .. ")",
    entradas = nuevos,
    formato = function(c) return "#" .. c.nombre .. " (línea " .. c.linea .. ")" end,
    on_elegir = function(c)
      M._agregar_tag(c.nombre)
    end,
  })
end

--- Autocompletado de subcomandos.
--- @param line string
--- @return string[]
function M.completar(line)
  local partes = vim.split(vim.trim(line), "%s+", { trimempty = true })
  -- Si estamos completando el subcomando
  if #partes <= 2 then
    local prefijo = partes[2] or ""
    local resultado = {}
    for _, sub in ipairs(subcomandos) do
      if sub:sub(1, #prefijo) == prefijo then
        resultado[#resultado + 1] = sub
      end
    end
    return resultado
  end
  -- Completar argumento de "nueva"
  if partes[2] == "nueva" and #partes <= 3 then
    local prefijo = partes[3] or ""
    local tipos = { "inbox", "permanente", "estructura" }
    local resultado = {}
    for _, t in ipairs(tipos) do
      if t:sub(1, #prefijo) == prefijo then
        resultado[#resultado + 1] = t
      end
    end
    return resultado
  end
  return {}
end

return M
