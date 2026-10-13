local index = require("zettel.index")
local parser = require("zettel.parser")
local picker = require("zettel.picker")
local ui = require("zettel.ui")

local M = {}

--- Sigue el enlace bajo el cursor: abre la nota si existe, avisa si no.
function M.seguir()
  local enlace = parser.enlace_en_cursor()
  if not enlace then
    ui.advertir("No hay un enlace bajo el cursor.")
    return
  end

  local entrada = index.obtener(enlace.id)
  if not entrada then
    ui.advertir("La nota " .. enlace.id .. " no existe.")
    return
  end

  vim.cmd("edit " .. vim.fn.fnameescape(entrada.ruta))
end

--- Formatea una entrada para el selector de enlaces.
--- @param entrada table
--- @return string
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

--- Formatea una fuente para el selector.
--- @param entrada table
--- @return string
local function formato_fuente(entrada)
  local autor = entrada.autor or ""
  return autor .. " · " .. entrada.titulo
end

--- Entrada especial para crear nota desde el selector.
local CREAR_NOTA = { _crear = true, titulo = "", id = "" }

--- Abre el selector de notas e inserta un enlace [[ID|título]].
function M.insertar()
  local notas = index.todas()

  -- Agregar opción de crear nota al inicio
  local entradas = { CREAR_NOTA }
  for _, n in ipairs(notas) do
    entradas[#entradas + 1] = n
  end

  picker.elegir({
    titulo = "Enlazar nota",
    entradas = entradas,
    formato = function(e)
      if e._crear then return "+ Crear nota permanente" end
      return formato_nota(e)
    end,
    on_elegir = function(entrada)
      if entrada._crear then
        ui.input("Título de la nueva nota: ", function(titulo)
          if not titulo then return end
          local notes = require("zettel.notes")
          notes.nueva("permanente", titulo)
          -- Después de crear, obtener la entrada recién creada e insertar enlace no aplica
          -- porque ya se abrió la nota nueva. El usuario la escribe y vuelve.
        end)
        return
      end
      local texto = "[[" .. entrada.id .. "|" .. entrada.titulo .. "]]"
      local row, col = unpack(vim.api.nvim_win_get_cursor(0))
      local linea = vim.api.nvim_get_current_line()
      local nueva = linea:sub(1, col) .. texto .. linea:sub(col + 1)
      vim.api.nvim_set_current_line(nueva)
      vim.api.nvim_win_set_cursor(0, { row, col + #texto })
    end,
  })
end

--- Abre el selector de notas por título (buscar).
function M.buscar()
  local notas = index.todas()
  if #notas == 0 then
    ui.advertir("No hay notas en el zettel.")
    return
  end

  picker.elegir({
    titulo = "Buscar nota",
    entradas = notas,
    formato = formato_nota,
    on_elegir = function(entrada)
      vim.cmd("edit " .. vim.fn.fnameescape(entrada.ruta))
    end,
  })
end

--- Abre el selector de fuentes por autor y título.
function M.buscar_fuentes()
  local fuentes = index.fuentes()
  if #fuentes == 0 then
    ui.advertir("No hay fuentes en el zettel.")
    return
  end

  picker.elegir({
    titulo = "Fuentes",
    entradas = fuentes,
    formato = formato_fuente,
    on_elegir = function(entrada)
      vim.cmd("edit " .. vim.fn.fnameescape(entrada.ruta))
    end,
  })
end

--- Muestra los backlinks de la nota actual en una ventana flotante.
function M.backlinks()
  local ruta = vim.api.nvim_buf_get_name(0)
  if ruta == "" then
    ui.advertir("El buffer no tiene archivo.")
    return
  end

  local lines_buf = vim.fn.readfile(ruta)
  local campos = parser.frontmatter(lines_buf)
  if not campos or not campos.id then
    ui.advertir("La nota no tiene un ID válido.")
    return
  end

  local id_nota = tostring(campos.id)
  -- Reindexar el archivo actual para tener datos frescos
  index.reindexar_archivo(ruta)

  local bl = index.backlinks(id_nota)
  if #bl == 0 then
    ui.info("No hay backlinks hacia esta nota.")
    return
  end

  -- Construir líneas para la ventana flotante y un mapa para navegación
  local lineas = {}
  local destinos = {} -- { [nro_linea] = { ruta, linea } }

  for _, b in ipairs(bl) do
    -- Leer el párrafo donde aparece el enlace
    local ok, archivo_lines = pcall(vim.fn.readfile, b.entrada.ruta)
    local contexto = ""
    if ok and archivo_lines then
      -- Tomar la línea del enlace y un par alrededor
      local desde = math.max(1, b.linea - 1)
      local hasta = math.min(#archivo_lines, b.linea + 1)
      local parrafo = {}
      for j = desde, hasta do
        parrafo[#parrafo + 1] = "    " .. archivo_lines[j]
      end
      contexto = table.concat(parrafo, "\n")
    end

    lineas[#lineas + 1] = "## [[" .. b.entrada.id .. "|" .. b.entrada.titulo .. "]]"
    local nro = #lineas
    destinos[nro] = { ruta = b.entrada.ruta, linea = b.linea }

    -- Agregar líneas de contexto
    if contexto ~= "" then
      for _, cl in ipairs(vim.split(contexto, "\n", { plain = true })) do
        lineas[#lineas + 1] = cl
      end
    end
    lineas[#lineas + 1] = ""
  end

  local titulo_nota = campos.titulo or id_nota
  local buf, win = ui.flotante(lineas, { titulo = "Backlinks de: " .. titulo_nota })

  -- Enter abre la nota en la línea correspondiente
  vim.keymap.set("n", "<CR>", function()
    local cursor = vim.api.nvim_win_get_cursor(0)[1]
    -- Buscar el destino más cercano hacia arriba
    local destino
    for nro = cursor, 1, -1 do
      if destinos[nro] then
        destino = destinos[nro]
        break
      end
    end
    if destino then
      vim.api.nvim_win_close(win, true)
      vim.cmd("edit +" .. destino.linea .. " " .. vim.fn.fnameescape(destino.ruta))
    end
  end, { buffer = buf })
end

--- Búsqueda de texto completo con ripgrep vía fzf-lua.
function M.texto()
  local cfg = require("zettel.config").get()

  local ok, fzf = pcall(require, "fzf-lua")
  if not ok then
    ui.advertir("La búsqueda de texto requiere fzf-lua.")
    return
  end

  fzf.grep_live({
    cwd = cfg.raiz,
    search = "",
    filespec = "*.md",
    prompt = "Texto> ",
    -- Excluir .zettel/
    rg_opts = "--column --line-number --no-heading --color=always --smart-case --glob '!.zettel/'",
  })
end

--- Selector por tag: primero elige tag, después nota dentro de ese tag.
function M.por_tag()
  local tags = index.tags()
  if #tags == 0 then
    ui.info("No hay tags en el zettel.")
    return
  end

  picker.elegir({
    titulo = "Elegir tag",
    entradas = tags,
    formato = function(t) return t.nombre .. " (" .. t.cantidad .. ")" end,
    on_elegir = function(tag_elegido)
      -- Buscar notas con ese tag
      local todas = index.todas()
      local con_tag = {}
      for _, entrada in ipairs(todas) do
        for _, t in ipairs(entrada.tags) do
          if t.nombre == tag_elegido.nombre then
            con_tag[#con_tag + 1] = entrada
            break
          end
        end
      end
      if #con_tag == 0 then return end
      picker.elegir({
        titulo = tag_elegido.nombre,
        entradas = con_tag,
        formato = formato_nota,
        on_elegir = function(entrada)
          vim.cmd("edit " .. vim.fn.fnameescape(entrada.ruta))
        end,
      })
    end,
  })
end

--- Notas editadas recientemente (por mtime), las más recientes primero.
function M.recientes()
  local notas = index.todas()
  if #notas == 0 then
    ui.advertir("No hay notas en el zettel.")
    return
  end

  table.sort(notas, function(a, b) return (a.mtime or 0) > (b.mtime or 0) end)

  -- Tomar las 30 más recientes
  local recientes = {}
  for i = 1, math.min(30, #notas) do
    recientes[#recientes + 1] = notas[i]
  end

  picker.elegir({
    titulo = "Recientes",
    entradas = recientes,
    formato = formato_nota,
    on_elegir = function(entrada)
      vim.cmd("edit " .. vim.fn.fnameescape(entrada.ruta))
    end,
  })
end

--- Navegación sigue_a: ir a la nota siguiente (notas que siguen a la actual).
function M.siguiente()
  local ruta = vim.api.nvim_buf_get_name(0)
  local lines = vim.fn.readfile(ruta)
  local campos = parser.frontmatter(lines)
  if not campos or not campos.id then
    ui.advertir("La nota no tiene un ID válido.")
    return
  end

  local id_actual = tostring(campos.id)
  -- Buscar notas cuyo sigue_a apunte a la actual
  local siguientes = {}
  for _, entrada in ipairs(index.todas()) do
    if entrada.sigue_a == id_actual then
      siguientes[#siguientes + 1] = entrada
    end
  end

  if #siguientes == 0 then
    ui.info("Ninguna nota sigue a esta.")
    return
  end

  if #siguientes == 1 then
    vim.cmd("edit " .. vim.fn.fnameescape(siguientes[1].ruta))
    return
  end

  picker.elegir({
    titulo = "Notas que siguen a esta",
    entradas = siguientes,
    formato = formato_nota,
    on_elegir = function(entrada)
      vim.cmd("edit " .. vim.fn.fnameescape(entrada.ruta))
    end,
  })
end

--- Navegación sigue_a: ir a la nota anterior (la que esta sigue).
function M.anterior()
  local ruta = vim.api.nvim_buf_get_name(0)
  local lines = vim.fn.readfile(ruta)
  local campos = parser.frontmatter(lines)
  if not campos or not campos.sigue_a then
    ui.info("Esta nota no sigue a ninguna otra.")
    return
  end

  local id_anterior = tostring(campos.sigue_a)
  local entrada = index.obtener(id_anterior)
  if not entrada then
    ui.advertir("La nota " .. id_anterior .. " no existe.")
    return
  end

  vim.cmd("edit " .. vim.fn.fnameescape(entrada.ruta))
end

return M
