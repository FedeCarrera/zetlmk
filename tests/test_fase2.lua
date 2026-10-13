local new_set = MiniTest.new_set
local expect = MiniTest.expect

local T = new_set()

-- ── Helpers ──────────────────────────────────────────────────

local raiz_test

local function setup_raiz()
  raiz_test = vim.fn.tempname() .. "/zettel_test"
  vim.fn.mkdir(raiz_test, "p")
  -- Limpiar módulos para resetear estado
  for k in pairs(package.loaded) do
    if k:match("^zettel") then
      package.loaded[k] = nil
    end
  end
  require("zettel").setup({ raiz = raiz_test, selector = "select" })
  require("zettel.index")._reset()
end

local function teardown_raiz()
  if raiz_test then
    vim.fn.delete(raiz_test, "rf")
  end
end

--- Crea una nota de prueba directamente en disco.
local function crear_nota(carpeta, id, campos_extra, cuerpo)
  local cfg = require("zettel.config")
  local dir
  if carpeta == "raiz" then
    dir = cfg.get().raiz
  else
    dir = cfg.carpeta(carpeta)
  end
  vim.fn.mkdir(dir, "p")

  local titulo = campos_extra.titulo or "Nota " .. id
  local tags = campos_extra.tags or {}
  local tags_str = "[" .. table.concat(tags, ", ") .. "]"

  local lines = { "---", "id: " .. id, "titulo: " .. titulo, "tags: " .. tags_str }
  if campos_extra.sigue_a then
    lines[#lines + 1] = "sigue_a: " .. campos_extra.sigue_a
  end
  if campos_extra.autor then
    lines[#lines + 1] = "autor: " .. campos_extra.autor
  end
  if campos_extra.formato then
    lines[#lines + 1] = "formato: " .. campos_extra.formato
  end
  lines[#lines + 1] = "---"
  lines[#lines + 1] = ""
  if cuerpo then
    for _, l in ipairs(vim.split(cuerpo, "\n", { plain = true })) do
      lines[#lines + 1] = l
    end
  end

  local ruta = dir .. "/" .. id .. ".md"
  vim.fn.writefile(lines, ruta)
  return ruta
end

-- ── Promover ─────────────────────────────────────────────────

T["promover"] = new_set({
  hooks = {
    pre_case = setup_raiz,
    post_case = teardown_raiz,
  },
})

T["promover"]["mueve de inbox a permanentes sin romper enlaces"] = function()
  local idx = require("zettel.index")
  local cfg = require("zettel.config")

  -- Crear nota en inbox
  local ruta_inbox = crear_nota("inbox", "20261012213745", { titulo = "Nota fugaz" })

  -- Crear nota en permanentes que enlaza a la fugaz
  crear_nota("permanentes", "20261009112000", {
    titulo = "Nota que enlaza",
  }, "Ver [[20261012213745|Nota fugaz]].")

  idx.reindexar_completo()

  -- Verificar que la nota está en inbox
  local e = idx.obtener("20261012213745")
  expect.equality(e.carpeta, "inbox")

  -- Simular promover: mover archivo y actualizar índice
  local dir_perm = cfg.carpeta("permanentes")
  local nueva_ruta = dir_perm .. "/20261012213745.md"
  vim.fn.rename(ruta_inbox, nueva_ruta)

  -- Actualizar índice como lo hace promover()
  e.ruta = nueva_ruta
  e.carpeta = "permanentes"
  idx.guardar()

  -- Verificar que la entrada se actualizó
  local e2 = idx.obtener("20261012213745")
  expect.equality(e2.carpeta, "permanentes")
  expect.equality(e2.ruta, nueva_ruta)

  -- Verificar que los backlinks siguen funcionando (buscan por ID, no por ruta)
  local bl = idx.backlinks("20261012213745")
  expect.equality(#bl, 1)
  expect.equality(bl[1].entrada.id, "20261009112000")
end

-- ── Extraer ──────────────────────────────────────────────────

T["extraer"] = new_set({
  hooks = {
    pre_case = setup_raiz,
    post_case = teardown_raiz,
  },
})

T["extraer"]["reemplaza selección con enlace válido"] = function()
  local notes = require("zettel.notes")
  local idx = require("zettel.index")
  local cfg = require("zettel.config")

  notes.asegurar_estructura()

  -- Crear nota origen
  local ruta_origen = crear_nota("permanentes", "20261012213745", {
    titulo = "Nota origen",
  }, "Línea uno.\nTexto a extraer.\nLínea tres.")

  idx.reindexar_completo()

  -- Abrir la nota en un buffer
  vim.cmd("edit " .. vim.fn.fnameescape(ruta_origen))
  local buf = vim.api.nvim_get_current_buf()

  -- Las líneas del buffer: frontmatter (4 líneas) + vacía + 3 líneas de cuerpo
  local lines_antes = vim.api.nvim_buf_get_lines(buf, 0, -1, false)

  -- Encontrar la línea "Texto a extraer."
  local linea_extraer
  for i, l in ipairs(lines_antes) do
    if l == "Texto a extraer." then
      linea_extraer = i
      break
    end
  end
  expect.no_equality(linea_extraer, nil)

  -- Simular la extracción: crear nota nueva y reemplazar
  local id_mod = require("zettel.id")
  local parser = require("zettel.parser")
  local id_nuevo = id_mod.generar(function(id_c) return idx.id_ocupado(id_c) end)
  local titulo_nuevo = "Idea extraída"

  local dir_perm = cfg.carpeta("permanentes")
  local nueva_ruta = dir_perm .. "/" .. id_nuevo .. ".md"
  vim.fn.writefile({
    "---", "id: " .. id_nuevo, "titulo: " .. titulo_nuevo, "tags: []", "---",
    "", "Texto a extraer.",
  }, nueva_ruta)

  idx.registrar({
    id = id_nuevo, ruta = nueva_ruta, carpeta = "permanentes",
    titulo = titulo_nuevo, tags = {}, enlaces = {}, sigue_a = nil,
    autor = nil, formato = nil, mtime = 0,
  })

  -- Reemplazar la línea en el buffer
  local enlace = "[[" .. id_nuevo .. "|" .. titulo_nuevo .. "]]"
  vim.api.nvim_buf_set_lines(buf, linea_extraer - 1, linea_extraer, false, { enlace })

  -- Verificar que el enlace quedó en el buffer
  local linea_nueva = vim.api.nvim_buf_get_lines(buf, linea_extraer - 1, linea_extraer, false)[1]
  expect.equality(linea_nueva, enlace)

  -- Verificar que la nota nueva existe en el índice
  local e = idx.obtener(id_nuevo)
  expect.no_equality(e, nil)
  expect.equality(e.titulo, titulo_nuevo)

  -- Verificar que el enlace es válido (el ID existe)
  local enlaces = parser.enlaces({ linea_nueva })
  expect.equality(#enlaces, 1)
  expect.equality(enlaces[1].id, id_nuevo)
  expect.equality(idx.existe(id_nuevo), true)
end

-- ── Backlinks ────────────────────────────────────────────────

T["backlinks"] = new_set({
  hooks = {
    pre_case = setup_raiz,
    post_case = teardown_raiz,
  },
})

T["backlinks"]["muestra contexto correcto tras cambio en disco"] = function()
  local idx = require("zettel.index")

  -- Crear nota destino
  crear_nota("permanentes", "20261012213745", { titulo = "Destino" })

  -- Crear nota que enlaza
  local ruta_enlazante = crear_nota("permanentes", "20261009112000", {
    titulo = "Enlazante",
  }, "Primer párrafo.\nVer [[20261012213745|Destino]].\nTercer párrafo.")

  idx.reindexar_completo()

  -- Verificar backlinks
  local bl = idx.backlinks("20261012213745")
  expect.equality(#bl, 1)
  expect.equality(bl[1].entrada.titulo, "Enlazante")

  -- Modificar la nota enlazante en disco (simula edición externa)
  vim.fn.writefile({
    "---", "id: 20261009112000", "titulo: Enlazante editada", "tags: []", "---",
    "", "Nuevo contexto.", "Ver [[20261012213745|Destino]].", "Más contexto.",
  }, ruta_enlazante)

  -- Forzar cambio de mtime
  local stat = vim.uv.fs_stat(ruta_enlazante)
  vim.uv.fs_utime(ruta_enlazante, stat.atime.sec + 2, stat.mtime.sec + 2)

  -- Reindexar
  idx.reindexar_archivo(ruta_enlazante)

  -- Los backlinks deben reflejar el cambio
  local bl2 = idx.backlinks("20261012213745")
  expect.equality(#bl2, 1)
  expect.equality(bl2[1].entrada.titulo, "Enlazante editada")
end

-- ── Navegación sigue_a ───────────────────────────────────────

T["sigue_a"] = new_set({
  hooks = {
    pre_case = setup_raiz,
    post_case = teardown_raiz,
  },
})

T["sigue_a"]["encuentra siguiente y anterior"] = function()
  local idx = require("zettel.index")

  crear_nota("permanentes", "20261010184500", { titulo = "Primera" })
  crear_nota("permanentes", "20261012213745", {
    titulo = "Segunda",
    sigue_a = "20261010184500",
  })

  idx.reindexar_completo()

  -- Verificar que la segunda sigue a la primera
  local e = idx.obtener("20261012213745")
  expect.equality(e.sigue_a, "20261010184500")

  -- Buscar notas que siguen a la primera
  local siguientes = {}
  for _, entrada in ipairs(idx.todas()) do
    if entrada.sigue_a == "20261010184500" then
      siguientes[#siguientes + 1] = entrada
    end
  end
  expect.equality(#siguientes, 1)
  expect.equality(siguientes[1].id, "20261012213745")
end

-- ── Tags ─────────────────────────────────────────────────────

T["por-tag"] = new_set({
  hooks = {
    pre_case = setup_raiz,
    post_case = teardown_raiz,
  },
})

T["por-tag"]["filtra notas por tag correctamente"] = function()
  local idx = require("zettel.index")

  crear_nota("permanentes", "20261012213745", {
    titulo = "Con memoria",
    tags = { "memoria", "test" },
  })
  crear_nota("permanentes", "20261009112000", {
    titulo = "Sin memoria",
    tags = { "test" },
  })

  idx.reindexar_completo()

  -- Buscar notas con tag "memoria"
  local todas = idx.todas()
  local con_tag = {}
  for _, entrada in ipairs(todas) do
    for _, t in ipairs(entrada.tags) do
      if t.nombre == "memoria" then
        con_tag[#con_tag + 1] = entrada
        break
      end
    end
  end
  expect.equality(#con_tag, 1)
  expect.equality(con_tag[1].titulo, "Con memoria")
end

return T
