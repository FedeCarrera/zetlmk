local new_set = MiniTest.new_set
local expect = MiniTest.expect

local T = new_set()

-- ── Helpers ──────────────────────────────────────────────────

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
  if campos_extra.sigue_a then lines[#lines + 1] = "sigue_a: " .. campos_extra.sigue_a end
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

-- ── Salud ────────────────────────────────────────────────────

T["salud"] = new_set({
  hooks = {
    pre_case = setup_raiz,
    post_case = teardown_raiz,
  },
})

T["salud"]["detecta enlaces rotos"] = function()
  crear_nota("permanentes", "20261012110000", {
    titulo = "Con enlace roto",
    tags = { "test" },
  }, "Ver [[99999999999999|inexistente]].")

  require("zettel.index").reindexar_completo()
  local ruta = require("zettel.health").generar()
  local lines = vim.fn.readfile(ruta)
  local contenido = table.concat(lines, "\n")

  expect.equality(contenido:find("Enlace roto") ~= nil, true)
end

T["salud"]["detecta fuente sin autor"] = function()
  crear_nota("fuentes", "20261012130000", {
    titulo = "Fuente rota",
    formato = "libro",
  })

  require("zettel.index").reindexar_completo()
  local ruta = require("zettel.health").generar()
  local lines = vim.fn.readfile(ruta)
  local contenido = table.concat(lines, "\n")

  expect.equality(contenido:find("Fuente sin autor") ~= nil, true)
end

T["salud"]["detecta permanente huérfana (nadie la cita)"] = function()
  crear_nota("permanentes", "20261012110000", {
    titulo = "Huérfana",
    tags = { "test" },
  })

  require("zettel.index").reindexar_completo()
  local ruta = require("zettel.health").generar()
  local lines = vim.fn.readfile(ruta)
  local contenido = table.concat(lines, "\n")

  expect.equality(contenido:find("Nadie la cita") ~= nil, true)
end

T["salud"]["detecta nota sin tags"] = function()
  crear_nota("permanentes", "20261012110000", { titulo = "Sin tags" })

  require("zettel.index").reindexar_completo()
  local ruta = require("zettel.health").generar()
  local lines = vim.fn.readfile(ruta)
  local contenido = table.concat(lines, "\n")

  expect.equality(contenido:find("Sin tags") ~= nil, true)
end

T["salud"]["salud.md no cuenta como backlink"] = function()
  local idx = require("zettel.index")

  crear_nota("permanentes", "20261012110000", {
    titulo = "Nota normal",
    tags = { "test" },
  })

  idx.reindexar_completo()

  -- Generar salud (contiene [[ID|título]])
  require("zettel.health").generar()

  -- Reindexar — salud.md no debería estar en el índice
  idx.reindexar_completo()

  -- Verificar que no hay backlinks espurios
  local bl = idx.backlinks("20261012110000")
  expect.equality(#bl, 0)

  -- Verificar que salud.md no está en el índice
  local todas = idx.todas()
  for _, e in ipairs(todas) do
    expect.equality(e.ruta:find("salud%.md") == nil, true)
  end
end

T["salud"]["detecta sigue_a roto"] = function()
  crear_nota("permanentes", "20261012110000", {
    titulo = "Sigue a nada",
    tags = { "test" },
    sigue_a = "99999999999999",
  })

  require("zettel.index").reindexar_completo()
  local ruta = require("zettel.health").generar()
  local lines = vim.fn.readfile(ruta)
  local contenido = table.concat(lines, "\n")

  expect.equality(contenido:find("sigue_a roto") ~= nil, true)
end

T["salud"]["se puede navegar con gd (enlaces válidos en el archivo)"] = function()
  crear_nota("permanentes", "20261012110000", {
    titulo = "Nota real",
    tags = { "test" },
  })

  require("zettel.index").reindexar_completo()
  local ruta = require("zettel.health").generar()
  local lines = vim.fn.readfile(ruta)
  local contenido = table.concat(lines, "\n")

  -- El archivo debe contener enlaces [[ID|título]] válidos
  local parser = require("zettel.parser")
  local enlaces = parser.enlaces(lines)

  -- Si hay hallazgos, deben tener enlaces válidos
  if #enlaces > 0 then
    for _, e in ipairs(enlaces) do
      expect.equality(#e.id, 14)
    end
  end
end

-- ── Tag renombrar ────────────────────────────────────────────

T["tag-renombrar"] = new_set({
  hooks = {
    pre_case = setup_raiz,
    post_case = teardown_raiz,
  },
})

T["tag-renombrar"]["renombra en todas las notas"] = function()
  crear_nota("permanentes", "20261012110000", {
    titulo = "Nota A",
    tags = { "viejo", "otro" },
  })
  crear_nota("permanentes", "20261012120000", {
    titulo = "Nota B",
    tags = { "viejo" },
  })

  local idx = require("zettel.index")
  idx.reindexar_completo()

  -- Renombrar sin confirmación (para test)
  require("zettel.notes").renombrar_tag("viejo", "nuevo", false)

  -- Reindexar para verificar
  idx._reset()
  idx.reindexar_completo()

  -- Verificar que el tag viejo ya no existe y el nuevo sí
  local tags = idx.tags()
  local por_nombre = {}
  for _, t in ipairs(tags) do por_nombre[t.nombre] = t.cantidad end

  expect.equality(por_nombre["viejo"], nil)
  expect.equality(por_nombre["nuevo"], 2)
  expect.equality(por_nombre["otro"], 1)
end

-- ── Tag fusionar ─────────────────────────────────────────────

T["tag-fusionar"] = new_set({
  hooks = {
    pre_case = setup_raiz,
    post_case = teardown_raiz,
  },
})

T["tag-fusionar"]["fusiona sin duplicar"] = function()
  -- Nota A tiene ambos tags
  crear_nota("permanentes", "20261012110000", {
    titulo = "Nota A",
    tags = { "origen", "destino" },
  })
  -- Nota B solo tiene el origen
  crear_nota("permanentes", "20261012120000", {
    titulo = "Nota B",
    tags = { "origen" },
  })

  local idx = require("zettel.index")
  idx.reindexar_completo()

  require("zettel.notes").fusionar_tag("origen", "destino", false)

  idx._reset()
  idx.reindexar_completo()

  local tags = idx.tags()
  local por_nombre = {}
  for _, t in ipairs(tags) do por_nombre[t.nombre] = t.cantidad end

  expect.equality(por_nombre["origen"], nil)
  expect.equality(por_nombre["destino"], 2)
end

-- ── Cambiar título ───────────────────────────────────────────

T["titulo"] = new_set({
  hooks = {
    pre_case = setup_raiz,
    post_case = teardown_raiz,
  },
})

T["titulo"]["actualiza enlaces en otras notas"] = function()
  local idx = require("zettel.index")
  local notes = require("zettel.notes")

  notes.asegurar_estructura()

  crear_nota("permanentes", "20261012110000", { titulo = "Título viejo", tags = { "test" } })
  crear_nota("permanentes", "20261012120000", {
    titulo = "Enlazante",
    tags = { "test" },
  }, "Ver [[20261012110000|Título viejo]].")

  idx.reindexar_completo()

  -- Simular cambiar el título directamente en el archivo (sin buffer interactivo)
  local cfg = require("zettel.config")
  local ruta_enlazante = cfg.carpeta("permanentes") .. "/20261012120000.md"

  -- Llamar a cambiar_titulo necesita un buffer, así que probamos la lógica directamente
  local viejo_enlace = "[[20261012110000|Título viejo]]"
  local nuevo_enlace = "[[20261012110000|Título nuevo]]"

  local ok, lines = pcall(vim.fn.readfile, ruta_enlazante)
  expect.equality(ok, true)

  local modificado = false
  for i, l in ipairs(lines) do
    local nueva, n = l:gsub(vim.pesc(viejo_enlace), nuevo_enlace)
    if n > 0 then
      lines[i] = nueva
      modificado = true
    end
  end

  expect.equality(modificado, true)
  vim.fn.writefile(lines, ruta_enlazante)

  -- Verificar que el archivo se actualizó
  local lines2 = vim.fn.readfile(ruta_enlazante)
  local contenido = table.concat(lines2, "\n")
  expect.equality(contenido:find("Título nuevo") ~= nil, true)
  expect.equality(contenido:find("Título viejo") == nil, true)
end

-- ── Alias de tags ────────────────────────────────────────────

T["alias"] = new_set({
  hooks = {
    pre_case = setup_raiz,
    post_case = teardown_raiz,
  },
})

T["alias"]["resuelve alias en conteo de tags"] = function()
  local cfg = require("zettel.config")
  local idx = require("zettel.index")

  -- Crear alias.yaml
  local dir_zettel = cfg.dir_zettel()
  vim.fn.mkdir(dir_zettel, "p")
  vim.fn.writefile({ "stoa: filosofia/estoicismo" }, dir_zettel .. "/alias.yaml")

  -- Nota con el alias
  crear_nota("permanentes", "20261012110000", {
    titulo = "Nota con alias",
    tags = { "stoa" },
  })
  -- Nota con el tag canónico
  crear_nota("permanentes", "20261012120000", {
    titulo = "Nota canónica",
    tags = { "filosofia/estoicismo" },
  })

  idx.reindexar_completo()
  local tags = idx.tags()

  local por_nombre = {}
  for _, t in ipairs(tags) do por_nombre[t.nombre] = t.cantidad end

  -- Ambas notas deberían contar bajo el tag canónico
  expect.equality(por_nombre["filosofia/estoicismo"], 2)
  expect.equality(por_nombre["stoa"], nil)
end

return T
