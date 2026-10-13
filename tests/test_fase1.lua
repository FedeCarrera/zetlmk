local new_set = MiniTest.new_set
local expect = MiniTest.expect

local T = new_set()

-- ── Helpers ──────────────────────────────────────────────────

local raiz_test

local function setup_raiz()
  raiz_test = vim.fn.tempname() .. "/zettel_test"
  vim.fn.mkdir(raiz_test, "p")
  require("zettel").setup({ raiz = raiz_test, selector = "select" })
  require("zettel.index")._reset()
end

local function teardown_raiz()
  if raiz_test then
    vim.fn.delete(raiz_test, "rf")
  end
end

-- ── id.lua ───────────────────────────────────────────────────

T["id"] = new_set()

T["id"]["timestamp genera 14 dígitos"] = function()
  local id = require("zettel.id")
  local ts = id.timestamp()
  expect.equality(#ts, 14)
  expect.equality(ts:match("^%d+$") ~= nil, true)
end

T["id"]["es_valido acepta IDs correctos"] = function()
  local id = require("zettel.id")
  expect.equality(id.es_valido("20261012213745"), true)
  expect.equality(id.es_valido("1234567890123"), false)   -- 13 dígitos
  expect.equality(id.es_valido("123456789012345"), false)  -- 15 dígitos
  expect.equality(id.es_valido("abcdefghijklmn"), false)   -- letras
  expect.equality(id.es_valido(""), false)
end

T["id"]["generar resuelve choques sumando un segundo"] = function()
  local id = require("zettel.id")
  local primer_id = id.timestamp()
  local ids_ocupados = { [primer_id] = true }

  local segundo_id = id.generar(function(candidato)
    return ids_ocupados[candidato] ~= nil
  end)

  expect.equality(#segundo_id, 14)
  expect.no_equality(primer_id, segundo_id)

  -- El segundo ID debe ser exactamente un segundo después
  local t1 = os.time(id.parsear(primer_id))
  local t2 = os.time(id.parsear(segundo_id))
  expect.equality(t2 - t1, 1)
end

T["id"]["dos IDs en el mismo segundo son distintos"] = function()
  local id = require("zettel.id")
  local base = id.timestamp()
  local ocupados = { [base] = true }

  local nuevo = id.generar(function(candidato)
    return ocupados[candidato] ~= nil
  end)

  expect.equality(#nuevo, 14)
  expect.no_equality(base, nuevo)
end

-- ── parser.lua ───────────────────────────────────────────────

T["parser"] = new_set()

T["parser"]["frontmatter parsea campos básicos"] = function()
  local p = require("zettel.parser")
  local lines = {
    "---",
    "id: 20261012213745",
    "titulo: La memoria es reconstructiva",
    "tags: [psicologia/memoria, aprendizaje]",
    "sigue_a: 20261010184500",
    "---",
    "",
    "Contenido de la nota.",
  }
  local campos, fin = p.frontmatter(lines)
  expect.no_equality(campos, nil)
  expect.equality(campos.id, 20261012213745)
  expect.equality(campos.titulo, "La memoria es reconstructiva")
  expect.equality(#campos.tags, 2)
  expect.equality(campos.tags[1], "psicologia/memoria")
  expect.equality(campos.tags[2], "aprendizaje")
  expect.equality(campos.sigue_a, 20261010184500)
  expect.equality(fin, 6)
end

T["parser"]["frontmatter parsea tags vacíos"] = function()
  local p = require("zettel.parser")
  local lines = { "---", "id: 20261012213745", "titulo: Test", "tags: []", "---" }
  local campos, _ = p.frontmatter(lines)
  expect.no_equality(campos, nil)
  expect.equality(type(campos.tags), "table")
  expect.equality(#campos.tags, 0)
end

T["parser"]["frontmatter devuelve nil sin frontmatter"] = function()
  local p = require("zettel.parser")
  local campos, _ = p.frontmatter({ "Sin frontmatter", "Solo texto" })
  expect.equality(campos, nil)
end

T["parser"]["frontmatter parsea lista en bloque"] = function()
  local p = require("zettel.parser")
  local lines = { "---", "id: 123", "tags:", "  - uno", "  - dos", "---" }
  local campos, _ = p.frontmatter(lines)
  expect.no_equality(campos, nil)
  expect.equality(#campos.tags, 2)
  expect.equality(campos.tags[1], "uno")
  expect.equality(campos.tags[2], "dos")
end

T["parser"]["enlaces extrae enlaces con texto"] = function()
  local p = require("zettel.parser")
  local lines = {
    "Texto con [[20261012213745|la memoria]] y más.",
    "Otro [[20261009112000|el olvido como filtro]].",
  }
  local enlaces = p.enlaces(lines)
  expect.equality(#enlaces, 2)
  expect.equality(enlaces[1].id, "20261012213745")
  expect.equality(enlaces[1].texto, "la memoria")
  expect.equality(enlaces[1].linea, 1)
  expect.equality(enlaces[2].id, "20261009112000")
  expect.equality(enlaces[2].linea, 2)
end

T["parser"]["enlaces acepta forma sin texto"] = function()
  local p = require("zettel.parser")
  local lines = { "Ver [[20261012213745]]." }
  local enlaces = p.enlaces(lines)
  expect.equality(#enlaces, 1)
  expect.equality(enlaces[1].id, "20261012213745")
  expect.equality(enlaces[1].texto, nil)
end

T["parser"]["enlaces ignora bloques de código"] = function()
  local p = require("zettel.parser")
  local lines = {
    "Texto normal [[20261012213745|válido]].",
    "```",
    "Dentro de código [[20261009112000|ignorado]].",
    "```",
    "Más texto [[20261013094512|también válido]].",
  }
  local enlaces = p.enlaces(lines)
  expect.equality(#enlaces, 2)
  expect.equality(enlaces[1].id, "20261012213745")
  expect.equality(enlaces[2].id, "20261013094512")
end

T["parser"]["enlaces ignora IDs que no son 14 dígitos"] = function()
  local p = require("zettel.parser")
  local lines = { "[[12345|corto]]", "[[123456789012345|largo]]" }
  local enlaces = p.enlaces(lines)
  expect.equality(#enlaces, 0)
end

T["parser"]["serializar_frontmatter ida y vuelta"] = function()
  local p = require("zettel.parser")
  local campos_orig = {
    id = 20261012213745,
    titulo = "Test",
    tags = { "a", "b" },
  }
  local lines = p.serializar_frontmatter(campos_orig, { "id", "titulo", "tags" })
  local campos, _ = p.frontmatter(lines)
  expect.no_equality(campos, nil)
  expect.equality(campos.titulo, "Test")
  expect.equality(#campos.tags, 2)
end

-- ── index.lua ────────────────────────────────────────────────

T["index"] = new_set({
  hooks = {
    pre_case = setup_raiz,
    post_case = teardown_raiz,
  },
})

T["index"]["indexa un archivo nuevo"] = function()
  local idx = require("zettel.index")
  local cfg = require("zettel.config")
  local dir = cfg.carpeta("permanentes")
  vim.fn.mkdir(dir, "p")

  local ruta = dir .. "/20261012213745.md"
  vim.fn.writefile({
    "---",
    "id: 20261012213745",
    "titulo: Nota de prueba",
    "tags: [test]",
    "---",
    "",
    "Contenido.",
  }, ruta)

  idx.reindexar_completo()
  local entrada = idx.obtener("20261012213745")
  expect.no_equality(entrada, nil)
  expect.equality(entrada.titulo, "Nota de prueba")
  expect.equality(entrada.carpeta, "permanentes")
  expect.equality(#entrada.tags, 1)
  expect.equality(entrada.tags[1].nombre, "test")
end

T["index"]["detecta archivo movido de carpeta"] = function()
  local idx = require("zettel.index")
  local cfg = require("zettel.config")

  local dir_inbox = cfg.carpeta("inbox")
  local dir_perm = cfg.carpeta("permanentes")
  vim.fn.mkdir(dir_inbox, "p")
  vim.fn.mkdir(dir_perm, "p")

  -- Crear en inbox
  local ruta_inbox = dir_inbox .. "/20261012213745.md"
  vim.fn.writefile({
    "---", "id: 20261012213745", "titulo: Nota movida", "tags: []", "---", "", "Texto.",
  }, ruta_inbox)

  idx.reindexar_completo()
  local e1 = idx.obtener("20261012213745")
  expect.equality(e1.carpeta, "inbox")

  -- Mover a permanentes
  local ruta_perm = dir_perm .. "/20261012213745.md"
  vim.fn.rename(ruta_inbox, ruta_perm)

  -- Reindexar — simula reabrir Neovim
  idx._reset()
  idx.reindexar_completo()

  local e2 = idx.obtener("20261012213745")
  expect.no_equality(e2, nil)
  expect.equality(e2.carpeta, "permanentes")
  expect.equality(e2.ruta, ruta_perm)
end

T["index"]["reindexado incremental detecta cambios"] = function()
  local idx = require("zettel.index")
  local cfg = require("zettel.config")
  local dir = cfg.carpeta("permanentes")
  vim.fn.mkdir(dir, "p")

  local ruta = dir .. "/20261012213745.md"
  vim.fn.writefile({
    "---", "id: 20261012213745", "titulo: Original", "tags: []", "---", "", "Texto.",
  }, ruta)

  idx.reindexar_completo()
  expect.equality(idx.obtener("20261012213745").titulo, "Original")

  -- Modificar el archivo (con un mtime diferente)
  -- Forzar cambio de mtime esperando un poco
  local stat = vim.uv.fs_stat(ruta)
  vim.fn.writefile({
    "---", "id: 20261012213745", "titulo: Modificado", "tags: [nuevo]", "---", "", "Texto nuevo.",
  }, ruta)
  -- Forzar mtime diferente
  vim.uv.fs_utime(ruta, stat.atime.sec + 2, stat.mtime.sec + 2)

  -- Simular recarga incremental
  idx._cargado = false
  idx.cargar()

  local e = idx.obtener("20261012213745")
  expect.equality(e.titulo, "Modificado")
  expect.equality(#e.tags, 1)
  expect.equality(e.tags[1].nombre, "nuevo")
end

T["index"]["enlaces en código no aparecen en el índice"] = function()
  local idx = require("zettel.index")
  local cfg = require("zettel.config")
  local dir = cfg.carpeta("permanentes")
  vim.fn.mkdir(dir, "p")

  vim.fn.writefile({
    "---", "id: 20261012213745", "titulo: Test código", "tags: []", "---",
    "",
    "Enlace real [[20261009112000|válido]].",
    "```",
    "Enlace en código [[20261013094512|ignorado]].",
    "```",
  }, dir .. "/20261012213745.md")

  idx.reindexar_completo()
  local e = idx.obtener("20261012213745")
  expect.equality(#e.enlaces, 1)
  expect.equality(e.enlaces[1].id, "20261009112000")
end

T["index"]["backlinks calcula correctamente"] = function()
  local idx = require("zettel.index")
  local cfg = require("zettel.config")
  local dir = cfg.carpeta("permanentes")
  vim.fn.mkdir(dir, "p")

  vim.fn.writefile({
    "---", "id: 20261012213745", "titulo: Nota A", "tags: []", "---",
    "", "Enlaza a [[20261009112000|nota B]].",
  }, dir .. "/20261012213745.md")

  vim.fn.writefile({
    "---", "id: 20261009112000", "titulo: Nota B", "tags: []", "---",
    "", "Contenido.",
  }, dir .. "/20261009112000.md")

  idx.reindexar_completo()
  local bl = idx.backlinks("20261009112000")
  expect.equality(#bl, 1)
  expect.equality(bl[1].entrada.id, "20261012213745")
end

T["index"]["tags cuenta correctamente"] = function()
  local idx = require("zettel.index")
  local cfg = require("zettel.config")
  local dir = cfg.carpeta("permanentes")
  vim.fn.mkdir(dir, "p")

  vim.fn.writefile({
    "---", "id: 20261012213745", "titulo: A", "tags: [memoria, test]", "---", "",
  }, dir .. "/20261012213745.md")
  vim.fn.writefile({
    "---", "id: 20261009112000", "titulo: B", "tags: [memoria]", "---", "",
  }, dir .. "/20261009112000.md")

  idx.reindexar_completo()
  local tags = idx.tags()
  local por_nombre = {}
  for _, t in ipairs(tags) do por_nombre[t.nombre] = t.cantidad end

  expect.equality(por_nombre["memoria"], 2)
  expect.equality(por_nombre["test"], 1)
end

-- ── notes.lua ────────────────────────────────────────────────

T["notes"] = new_set({
  hooks = {
    pre_case = setup_raiz,
    post_case = teardown_raiz,
  },
})

T["notes"]["asegura plantillas por defecto"] = function()
  local notes = require("zettel.notes")
  local cfg = require("zettel.config")
  notes.asegurar_estructura()

  local dir = cfg.dir_zettel() .. "/plantillas"
  expect.equality(vim.fn.filereadable(dir .. "/fugaz.md"), 1)
  expect.equality(vim.fn.filereadable(dir .. "/permanente.md"), 1)
  expect.equality(vim.fn.filereadable(dir .. "/estructura.md"), 1)
  expect.equality(vim.fn.filereadable(dir .. "/fuentes/libro.md"), 1)
  expect.equality(vim.fn.filereadable(dir .. "/fuentes/video.md"), 1)
  expect.equality(vim.fn.filereadable(dir .. "/fuentes/articulo.md"), 1)
end

T["notes"]["asegura .gitignore"] = function()
  local notes = require("zettel.notes")
  local cfg = require("zettel.config")
  notes.asegurar_estructura()

  local gitignore = cfg.dir_zettel() .. "/.gitignore"
  expect.equality(vim.fn.filereadable(gitignore), 1)
  local contenido = vim.fn.readfile(gitignore)
  local tiene_index = false
  local tiene_salud = false
  for _, linea in ipairs(contenido) do
    if linea == "index.json" then tiene_index = true end
    if linea == "salud.md" then tiene_salud = true end
  end
  expect.equality(tiene_index, true)
  expect.equality(tiene_salud, true)
end

T["notes"]["formatos_fuente lista los disponibles"] = function()
  local notes = require("zettel.notes")
  notes.asegurar_estructura()
  local formatos = notes.formatos_fuente()
  expect.equality(#formatos >= 3, true)
  -- Deben estar ordenados
  local tiene_libro = false
  for _, f in ipairs(formatos) do
    if f == "libro" then tiene_libro = true end
  end
  expect.equality(tiene_libro, true)
end

-- ── Carga diferida ───────────────────────────────────────────

T["carga diferida"] = new_set()

T["carga diferida"]["require no lee disco"] = function()
  -- Limpiar módulos cargados para simular un require fresco
  for k in pairs(package.loaded) do
    if k:match("^zettel") then
      package.loaded[k] = nil
    end
  end

  -- Configurar con una raíz que no existe
  local zettel = require("zettel")
  -- No debería haber leído disco aún, solo haber cargado el módulo
  local idx = require("zettel.index")
  expect.equality(idx._cargado, false)
end

return T
