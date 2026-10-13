local new_set = MiniTest.new_set
local expect = MiniTest.expect

local T = new_set()

local raiz_test

local function setup_raiz()
  raiz_test = vim.fn.tempname() .. "/zettel_test"
  vim.fn.mkdir(raiz_test, "p")
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
  if campos_extra.autor then lines[#lines + 1] = "autor: " .. campos_extra.autor end
  if campos_extra.formato then lines[#lines + 1] = "formato: " .. campos_extra.formato end
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

-- ── Consulta: parsear ────────────────────────────────────────

T["consulta parsear"] = new_set()

T["consulta parsear"]["parsea tags positivos y negativos"] = function()
  local q = require("zettel.query")
  local f = q.parsear("#memoria -#borrador")
  expect.equality(#f.tags_si, 1)
  expect.equality(f.tags_si[1], "memoria")
  expect.equality(#f.tags_no, 1)
  expect.equality(f.tags_no[1], "borrador")
end

T["consulta parsear"]["parsea texto entre comillas"] = function()
  local q = require("zettel.query")
  local f = q.parsear('"texto libre" #tag')
  expect.equality(#f.texto, 1)
  expect.equality(f.texto[1], "texto libre")
  expect.equality(#f.tags_si, 1)
end

T["consulta parsear"]["parsea filtros de carpeta, desde y formato"] = function()
  local q = require("zettel.query")
  local f = q.parsear("en:inbox desde:2026-09 formato:libro")
  expect.equality(f.carpeta, "inbox")
  expect.equality(f.desde, "2026-09")
  expect.equality(f.formato, "libro")
end

T["consulta parsear"]["consulta compleja"] = function()
  local q = require("zettel.query")
  local f = q.parsear('#memoria -#borrador "olvido" en:inbox desde:2026-09 formato:libro')
  expect.equality(#f.tags_si, 1)
  expect.equality(#f.tags_no, 1)
  expect.equality(#f.texto, 1)
  expect.equality(f.carpeta, "inbox")
  expect.equality(f.desde, "2026-09")
  expect.equality(f.formato, "libro")
end

-- ── Consulta: ejecutar ───────────────────────────────────────

T["consulta ejecutar"] = new_set({
  hooks = { pre_case = setup_raiz, post_case = teardown_raiz },
})

T["consulta ejecutar"]["filtra por tag"] = function()
  crear_nota("permanentes", "20261012110000", { titulo = "Con memoria", tags = { "memoria" } })
  crear_nota("permanentes", "20261012120000", { titulo = "Sin tag", tags = { "otro" } })

  require("zettel.index").reindexar_completo()
  local q = require("zettel.query")
  local res = q.ejecutar("#memoria")
  expect.equality(#res, 1)
  expect.equality(res[1].titulo, "Con memoria")
end

T["consulta ejecutar"]["filtra por tag negado"] = function()
  crear_nota("permanentes", "20261012110000", { titulo = "A", tags = { "memoria", "borrador" } })
  crear_nota("permanentes", "20261012120000", { titulo = "B", tags = { "memoria" } })

  require("zettel.index").reindexar_completo()
  local q = require("zettel.query")
  local res = q.ejecutar("#memoria -#borrador")
  expect.equality(#res, 1)
  expect.equality(res[1].titulo, "B")
end

T["consulta ejecutar"]["filtra por carpeta"] = function()
  crear_nota("inbox", "20261012110000", { titulo = "Fugaz" })
  crear_nota("permanentes", "20261012120000", { titulo = "Permanente" })

  require("zettel.index").reindexar_completo()
  local q = require("zettel.query")
  local res = q.ejecutar("en:inbox")
  expect.equality(#res, 1)
  expect.equality(res[1].titulo, "Fugaz")
end

T["consulta ejecutar"]["filtra por fecha desde"] = function()
  crear_nota("permanentes", "20260812110000", { titulo = "Agosto" })
  crear_nota("permanentes", "20261012120000", { titulo = "Octubre" })

  require("zettel.index").reindexar_completo()
  local q = require("zettel.query")
  local res = q.ejecutar("desde:2026-10")
  expect.equality(#res, 1)
  expect.equality(res[1].titulo, "Octubre")
end

T["consulta ejecutar"]["filtra por formato"] = function()
  crear_nota("fuentes", "20261012110000", {
    titulo = "Un libro", formato = "libro", autor = "Autor",
  })
  crear_nota("fuentes", "20261012120000", {
    titulo = "Un video", formato = "video", autor = "Canal",
  })

  require("zettel.index").reindexar_completo()
  local q = require("zettel.query")
  local res = q.ejecutar("formato:libro")
  expect.equality(#res, 1)
  expect.equality(res[1].titulo, "Un libro")
end

T["consulta ejecutar"]["filtra por texto en contenido"] = function()
  crear_nota("permanentes", "20261012110000", { titulo = "Nota A" }, "Recordar es reconstruir.")
  crear_nota("permanentes", "20261012120000", { titulo = "Nota B" }, "Olvidar es filtrar.")

  require("zettel.index").reindexar_completo()
  local q = require("zettel.query")
  local res = q.ejecutar('"reconstruir"')
  expect.equality(#res, 1)
  expect.equality(res[1].titulo, "Nota A")
end

-- ── Búsquedas guardadas ──────────────────────────────────────

T["busquedas guardadas"] = new_set({
  hooks = { pre_case = setup_raiz, post_case = teardown_raiz },
})

T["busquedas guardadas"]["guarda y carga"] = function()
  local q = require("zettel.query")
  local cfg = require("zettel.config")
  vim.fn.mkdir(cfg.dir_zettel(), "p")

  q.guardar_busqueda("recientes memoria", "#memoria desde:2026-10")
  q.guardar_busqueda("inbox viejo", "en:inbox")

  local cargadas = q.cargar_busquedas()
  expect.equality(#cargadas, 2)
  expect.equality(cargadas[1].nombre, "recientes memoria")
  expect.equality(cargadas[1].query, "#memoria desde:2026-10")
end

-- ── Tags inline ──────────────────────────────────────────────

T["tags inline"] = new_set()

T["tags inline"]["detecta tags en el cuerpo"] = function()
  local p = require("zettel.parser")
  local lines = {
    "---", "id: 123", "titulo: Test", "tags: []", "---",
    "", "Esto tiene #memoria y #aprendizaje.",
  }
  local tags = p.tags_inline(lines)
  expect.equality(#tags, 2)
  expect.equality(tags[1].nombre, "memoria")
  expect.equality(tags[2].nombre, "aprendizaje")
end

T["tags inline"]["ignora títulos"] = function()
  local p = require("zettel.parser")
  local lines = {
    "---", "id: 123", "titulo: Test", "tags: []", "---",
    "", "# Título con #tag", "", "Cuerpo con #real.",
  }
  local tags = p.tags_inline(lines)
  expect.equality(#tags, 1)
  expect.equality(tags[1].nombre, "real")
end

T["tags inline"]["ignora bloques de código"] = function()
  local p = require("zettel.parser")
  local lines = {
    "---", "id: 123", "titulo: Test", "tags: []", "---",
    "", "```", "#ignorado", "```", "", "#valido aquí.",
  }
  local tags = p.tags_inline(lines)
  expect.equality(#tags, 1)
  expect.equality(tags[1].nombre, "valido")
end

T["tags inline"]["ignora colores hexadecimales"] = function()
  local p = require("zettel.parser")
  local lines = {
    "---", "id: 123", "titulo: Test", "tags: []", "---",
    "", "Color #fff y #abc123 no son tags. Pero #memoria sí.",
  }
  local tags = p.tags_inline(lines)
  expect.equality(#tags, 1)
  expect.equality(tags[1].nombre, "memoria")
end

T["tags inline"]["ignora dentro de URLs"] = function()
  local p = require("zettel.parser")
  local lines = {
    "---", "id: 123", "titulo: Test", "tags: []", "---",
    "", "Ver https://example.com/path#section y #real.",
  }
  local tags = p.tags_inline(lines)
  expect.equality(#tags, 1)
  expect.equality(tags[1].nombre, "real")
end

T["tags inline"]["soporta tags jerárquicos"] = function()
  local p = require("zettel.parser")
  local lines = {
    "---", "id: 123", "titulo: Test", "tags: []", "---",
    "", "Tema de #psicologia/memoria.",
  }
  local tags = p.tags_inline(lines)
  expect.equality(#tags, 1)
  expect.equality(tags[1].nombre, "psicologia/memoria")
end

return T
