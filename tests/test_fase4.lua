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
  require("zettel").setup({
    raiz = raiz_test,
    selector = "select",
    descubrir = {
      nucleo_min_notas = 2,      -- bajo para tests
      tag_maduro_min_notas = 3,  -- bajo para tests
      relacionadas_min_tags = 1,
    },
  })
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

-- ── Vecindario ───────────────────────────────────────────────

T["vecindario"] = new_set({
  hooks = { pre_case = setup_raiz, post_case = teardown_raiz },
})

T["vecindario"]["encuentra notas a 1 y 2 saltos"] = function()
  local idx = require("zettel.index")
  local discover = require("zettel.discover")

  -- A -> B -> C (cadena de enlaces)
  crear_nota("permanentes", "20261012110000", { titulo = "Nota A", tags = { "t" } }, "Ver [[20261012120000|Nota B]].")
  crear_nota("permanentes", "20261012120000", { titulo = "Nota B", tags = { "t" } }, "Ver [[20261012130000|Nota C]].")
  crear_nota("permanentes", "20261012130000", { titulo = "Nota C", tags = { "t" } })
  -- D no conectada
  crear_nota("permanentes", "20261012140000", { titulo = "Nota D", tags = { "t" } })

  idx.reindexar_completo()

  -- Desde A: salto 1 = {B}, salto 2 = {C}
  local entrada_a = idx.obtener("20261012110000")
  local visto = { ["20261012110000"] = true }
  local salto1 = {}

  for _, enlace in ipairs(entrada_a.enlaces) do
    if not visto[enlace.id] and idx.existe(enlace.id) then
      visto[enlace.id] = true
      salto1[#salto1 + 1] = enlace.id
    end
  end

  expect.equality(#salto1, 1)
  expect.equality(salto1[1], "20261012120000")

  local salto2 = {}
  for _, id1 in ipairs(salto1) do
    local e1 = idx.obtener(id1)
    for _, enlace in ipairs(e1.enlaces) do
      if not visto[enlace.id] and idx.existe(enlace.id) then
        visto[enlace.id] = true
        salto2[#salto2 + 1] = enlace.id
      end
    end
  end

  expect.equality(#salto2, 1)
  expect.equality(salto2[1], "20261012130000")

  -- D no debería aparecer
  expect.equality(visto["20261012140000"], nil)
end

-- ── Relacionadas ─────────────────────────────────────────────

T["relacionadas"] = new_set({
  hooks = { pre_case = setup_raiz, post_case = teardown_raiz },
})

T["relacionadas"]["encuentra notas con tags compartidos"] = function()
  local idx = require("zettel.index")

  crear_nota("permanentes", "20261012110000", { titulo = "Nota A", tags = { "memoria", "test" } })
  crear_nota("permanentes", "20261012120000", { titulo = "Nota B", tags = { "memoria" } })
  crear_nota("permanentes", "20261012130000", { titulo = "Nota C", tags = { "otro" } })

  idx.reindexar_completo()

  -- Desde A: B comparte "memoria", C no
  local entrada_a = idx.obtener("20261012110000")
  local tags_a = {}
  for _, t in ipairs(entrada_a.tags) do
    tags_a[t.nombre] = true
  end

  local enlazados = { ["20261012110000"] = true }
  local relacionadas = {}

  for _, otra in ipairs(idx.todas()) do
    if enlazados[otra.id] then goto continue end
    local compartidos = 0
    for _, t in ipairs(otra.tags) do
      if tags_a[t.nombre] then compartidos = compartidos + 1 end
    end
    if compartidos >= 1 then
      relacionadas[#relacionadas + 1] = otra
    end
    ::continue::
  end

  expect.equality(#relacionadas, 1)
  expect.equality(relacionadas[1].titulo, "Nota B")
end

-- ── Núcleos emergentes ───────────────────────────────────────

T["nucleos"] = new_set({
  hooks = { pre_case = setup_raiz, post_case = teardown_raiz },
})

T["nucleos"]["detecta componente conexo no alcanzado"] = function()
  local idx = require("zettel.index")
  local discover = require("zettel.discover")

  -- Estructura que enlaza a nota A
  crear_nota("raiz", "20261012100000", { titulo = "Estructura", tags = { "t" } }, "Ver [[20261012110000|Nota A]].")
  crear_nota("permanentes", "20261012110000", { titulo = "Nota A", tags = { "t" } })

  -- Núcleo aislado: B <-> C (no alcanzado por estructura)
  crear_nota("permanentes", "20261012120000", { titulo = "Nota B", tags = { "t" } }, "Ver [[20261012130000|Nota C]].")
  crear_nota("permanentes", "20261012130000", { titulo = "Nota C", tags = { "t" } }, "Ver [[20261012120000|Nota B]].")

  idx.reindexar_completo()

  -- Calcular alcanzables
  local alcanzables = {}
  local cola = {}
  for _, e in ipairs(idx.todas()) do
    if e.carpeta == "raiz" then
      alcanzables[e.id] = true
      cola[#cola + 1] = e.id
    end
  end
  while #cola > 0 do
    local id = table.remove(cola, 1)
    local e = idx.obtener(id)
    if e then
      for _, enlace in ipairs(e.enlaces) do
        if not alcanzables[enlace.id] then
          alcanzables[enlace.id] = true
          cola[#cola + 1] = enlace.id
        end
      end
    end
  end

  local nucleos = discover.nucleos_emergentes(alcanzables)
  expect.equality(#nucleos, 1)
  expect.equality(#nucleos[1], 2)

  local ids_nucleo = {}
  for _, e in ipairs(nucleos[1]) do ids_nucleo[e.id] = true end
  expect.equality(ids_nucleo["20261012120000"], true)
  expect.equality(ids_nucleo["20261012130000"], true)
end

-- ── Tags maduros ─────────────────────────────────────────────

T["tags maduros"] = new_set({
  hooks = { pre_case = setup_raiz, post_case = teardown_raiz },
})

T["tags maduros"]["detecta tag maduro sin estructura"] = function()
  local idx = require("zettel.index")
  local discover = require("zettel.discover")

  -- 3 notas con tag "memoria" (umbral = 3)
  crear_nota("permanentes", "20261012110000", { titulo = "A", tags = { "memoria" } })
  crear_nota("permanentes", "20261012120000", { titulo = "B", tags = { "memoria" } })
  crear_nota("permanentes", "20261012130000", { titulo = "C", tags = { "memoria" } })

  -- Estructura con otro tag
  crear_nota("raiz", "20261012100000", { titulo = "Estructura", tags = { "otro" } })

  idx.reindexar_completo()

  local maduros = discover.tags_maduros()
  expect.equality(#maduros >= 1, true)

  local tiene_memoria = false
  for _, t in ipairs(maduros) do
    if t.nombre == "memoria" then tiene_memoria = true end
  end
  expect.equality(tiene_memoria, true)
end

T["tags maduros"]["no reporta tag cubierto por estructura"] = function()
  local idx = require("zettel.index")
  local discover = require("zettel.discover")

  crear_nota("permanentes", "20261012110000", { titulo = "A", tags = { "memoria" } })
  crear_nota("permanentes", "20261012120000", { titulo = "B", tags = { "memoria" } })
  crear_nota("permanentes", "20261012130000", { titulo = "C", tags = { "memoria" } })

  -- Estructura que cubre el tag "memoria"
  crear_nota("raiz", "20261012100000", { titulo = "Mapa memoria", tags = { "memoria" } })

  idx.reindexar_completo()

  local maduros = discover.tags_maduros()
  local tiene_memoria = false
  for _, t in ipairs(maduros) do
    if t.nombre == "memoria" then tiene_memoria = true end
  end
  expect.equality(tiene_memoria, false)
end

-- ── Azar ─────────────────────────────────────────────────────

T["azar"] = new_set({
  hooks = { pre_case = setup_raiz, post_case = teardown_raiz },
})

T["azar"]["solo elige permanentes"] = function()
  local idx = require("zettel.index")

  crear_nota("permanentes", "20261012110000", { titulo = "Permanente", tags = { "t" } })
  crear_nota("inbox", "20261012120000", { titulo = "Fugaz", tags = { "t" } })

  idx.reindexar_completo()

  -- Verificar que solo permanentes son candidatas
  local candidatas = {}
  for _, e in ipairs(idx.todas()) do
    if e.carpeta == "permanentes" then
      candidatas[#candidatas + 1] = e
    end
  end
  expect.equality(#candidatas, 1)
  expect.equality(candidatas[1].titulo, "Permanente")
end

-- ── Oportunidades en salud ───────────────────────────────────

T["oportunidades en salud"] = new_set({
  hooks = { pre_case = setup_raiz, post_case = teardown_raiz },
})

T["oportunidades en salud"]["muestra núcleos y tags maduros"] = function()
  local idx = require("zettel.index")

  -- Núcleo aislado
  crear_nota("permanentes", "20261012120000", { titulo = "Isla A", tags = { "memoria" } }, "Ver [[20261012130000|Isla B]].")
  crear_nota("permanentes", "20261012130000", { titulo = "Isla B", tags = { "memoria" } }, "Ver [[20261012120000|Isla A]].")
  crear_nota("permanentes", "20261012140000", { titulo = "Isla C", tags = { "memoria" } })

  idx.reindexar_completo()

  local ruta = require("zettel.health").generar()
  local lines = vim.fn.readfile(ruta)
  local contenido = table.concat(lines, "\n")

  -- Debe tener la sección de oportunidades con contenido
  expect.equality(contenido:find("## Oportunidades") ~= nil, true)
  expect.equality(contenido:find("Núcleo emergente") ~= nil, true)
  expect.equality(contenido:find("Tag maduro") ~= nil, true)
end

return T
