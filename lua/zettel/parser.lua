local M = {}

-- ── Frontmatter ──────────────────────────────────────────────

--- Parsea un valor YAML escalar.
--- Soporta: strings (con o sin comillas), números, booleanos, null, fechas.
--- @param raw string
--- @return any
local function parsear_escalar(raw)
  local s = vim.trim(raw)
  if s == "" or s == "~" or s == "null" then
    return nil
  end
  -- String entre comillas
  if (s:sub(1, 1) == '"' and s:sub(-1) == '"') or (s:sub(1, 1) == "'" and s:sub(-1) == "'") then
    return s:sub(2, -2)
  end
  -- Booleano
  if s == "true" then return true end
  if s == "false" then return false end
  -- Número
  local n = tonumber(s)
  if n then return n end
  -- Todo lo demás es string sin comillas
  return s
end

--- Parsea una lista inline YAML: [a, b, c]
--- @param s string el contenido entre [ y ]
--- @return string[]
local function parsear_lista_inline(s)
  local items = {}
  for item in s:gmatch("[^,]+") do
    local val = parsear_escalar(item)
    if val ~= nil then
      items[#items + 1] = tostring(val)
    end
  end
  return items
end

--- Parsea el frontmatter YAML de un archivo de nota.
--- Devuelve la tabla de campos y la línea donde termina el frontmatter (cierre ---).
--- @param lines string[] líneas del archivo
--- @return table|nil campos
--- @return number|nil linea_fin (1-indexed, la línea del --- de cierre)
function M.frontmatter(lines)
  if not lines or #lines == 0 then return nil, nil end
  if vim.trim(lines[1]) ~= "---" then return nil, nil end

  local campos = {}
  local linea_fin = nil
  local clave_lista = nil -- clave de lista en bloque activa

  for i = 2, #lines do
    local linea = lines[i]

    -- Cierre del frontmatter
    if vim.trim(linea) == "---" then
      linea_fin = i
      break
    end

    -- Ítem de lista en bloque: "  - valor"
    local item_val = linea:match("^%s+%-%s+(.+)$")
    if item_val and clave_lista then
      table.insert(campos[clave_lista], parsear_escalar(item_val))
    else
      clave_lista = nil

      -- Par clave: valor
      local clave, valor = linea:match("^([%w_]+):%s*(.*)$")
      if clave then
        valor = vim.trim(valor)
        if valor == "" then
          -- Posible inicio de lista en bloque
          campos[clave] = {}
          clave_lista = clave
        elseif valor:sub(1, 1) == "[" and valor:sub(-1) == "]" then
          campos[clave] = parsear_lista_inline(valor:sub(2, -2))
          -- Si la lista está vacía, dejar la tabla vacía
        else
          campos[clave] = parsear_escalar(valor)
        end
      end
    end
  end

  if not linea_fin then return nil, nil end
  return campos, linea_fin
end

-- ── Enlaces ──────────────────────────────────────────────────

--- Detecta si una línea está dentro de un bloque de código cercado.
--- @param lines string[] todas las líneas
--- @return boolean[] mapa indexado por número de línea
function M.mapa_codigo(lines)
  local en_codigo = {}
  local dentro = false
  for i, linea in ipairs(lines) do
    if linea:match("^```") then
      dentro = not dentro
    end
    en_codigo[i] = dentro
  end
  return en_codigo
end

--- Extrae todos los enlaces [[ID|texto]] o [[ID]] de las líneas, ignorando bloques de código.
--- Devuelve una lista de { id = string, texto = string|nil, linea = number }.
--- @param lines string[]
--- @return table[]
function M.enlaces(lines)
  local en_codigo = M.mapa_codigo(lines)
  local resultado = {}

  for i, linea in ipairs(lines) do
    if not en_codigo[i] then
      -- Buscar todos los [[...]] en la línea
      for contenido in linea:gmatch("%[%[(.-)%]%]") do
        local id, texto = contenido:match("^(%d+)|(.+)$")
        if not id then
          -- Forma [[ID]] sin texto
          id = contenido:match("^(%d+)$")
        end
        if id and #id == 14 then
          resultado[#resultado + 1] = { id = id, texto = texto, linea = i }
        end
      end
    end
  end

  return resultado
end

--- Encuentra el enlace bajo el cursor en el buffer actual.
--- @return table|nil { id = string, texto = string|nil, inicio = number, fin = number }
function M.enlace_en_cursor()
  local linea = vim.api.nvim_get_current_line()
  local col = vim.api.nvim_win_get_cursor(0)[2] + 1 -- 1-indexed

  for inicio, contenido, fin in linea:gmatch("()%[%[(.-)%]%]()" ) do
    if col >= inicio and col < fin then
      local id, texto = contenido:match("^(%d+)|(.+)$")
      if not id then
        id = contenido:match("^(%d+)$")
      end
      if id and #id == 14 then
        return { id = id, texto = texto, inicio = inicio, fin = fin - 1 }
      end
    end
  end

  return nil
end

-- ── Serialización de frontmatter ─────────────────────────────

--- Serializa una tabla de campos a líneas de frontmatter YAML.
--- @param campos table
--- @param orden string[]|nil orden preferido de claves
--- @return string[]
function M.serializar_frontmatter(campos, orden)
  local lines = { "---" }
  local escritas = {}

  local function escribir_campo(clave)
    if escritas[clave] or campos[clave] == nil then return end
    escritas[clave] = true
    local val = campos[clave]
    if type(val) == "table" then
      if #val == 0 then
        lines[#lines + 1] = clave .. ": []"
      else
        local partes = {}
        for _, v in ipairs(val) do
          partes[#partes + 1] = tostring(v)
        end
        lines[#lines + 1] = clave .. ": [" .. table.concat(partes, ", ") .. "]"
      end
    elseif type(val) == "boolean" then
      lines[#lines + 1] = clave .. ": " .. tostring(val)
    else
      lines[#lines + 1] = clave .. ": " .. tostring(val)
    end
  end

  -- Primero las claves en orden preferido
  if orden then
    for _, clave in ipairs(orden) do
      escribir_campo(clave)
    end
  end

  -- Después las restantes en orden alfabético
  local restantes = {}
  for clave in pairs(campos) do
    if not escritas[clave] then
      restantes[#restantes + 1] = clave
    end
  end
  table.sort(restantes)
  for _, clave in ipairs(restantes) do
    escribir_campo(clave)
  end

  lines[#lines + 1] = "---"
  return lines
end

-- ── Tags inline ──────────────────────────────────────────────

--- Detecta tags inline (#tag) en las líneas de una nota, ignorando:
--- - Frontmatter
--- - Títulos (líneas que empiezan con #)
--- - Bloques de código
--- - URLs (http/https)
--- - Colores hexadecimales (#abc123, #fff)
--- Usa Treesitter si está disponible para mayor precisión.
--- @param lines string[]
--- @return table[] lista de { nombre = string, linea = number }
function M.tags_inline(lines)
  local _, fin_fm = M.frontmatter(lines)
  local inicio = (fin_fm or 0) + 1
  local en_codigo = M.mapa_codigo(lines)

  local resultado = {}
  local patron_hex = "^#%x+$"

  for i = inicio, #lines do
    if en_codigo[i] then goto continue end

    local linea = lines[i]

    -- Ignorar títulos markdown (# Título, ## Subtítulo, etc.)
    if linea:match("^#+ ") then goto continue end

    -- Buscar #tag en la línea
    -- Un tag inline empieza con # seguido de letras/números/guiones/barras
    -- No debe estar precedido por carácter alfanumérico (evitar anclas de URL)
    for pos, tag in linea:gmatch("()#([%w_/%-]+)") do
      -- Verificar que no es parte de una URL
      local pre = linea:sub(1, pos - 1)
      if pre:match("https?://[^%s]*$") then goto next_tag end

      -- Verificar que no es un color hex (#fff, #abc123)
      if tag:match("^%x+$") and (#tag == 3 or #tag == 6) then goto next_tag end

      -- Verificar que no está precedido por carácter alfanumérico
      if pos > 1 then
        local char_antes = linea:sub(pos - 1, pos - 1)
        if char_antes:match("[%w_]") then goto next_tag end
      end

      resultado[#resultado + 1] = { nombre = tag, linea = i }
      ::next_tag::
    end

    ::continue::
  end

  return resultado
end

--- Versión con Treesitter: usa el árbol sintáctico para ignorar nodos de código.
--- Cae al método basado en patrones si Treesitter no está disponible.
--- @param bufnr number
--- @return table[]
function M.tags_inline_ts(bufnr)
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)

  -- Intentar usar Treesitter
  local ok, ts_parser = pcall(vim.treesitter.get_parser, bufnr, "markdown")
  if not ok or not ts_parser then
    return M.tags_inline(lines)
  end

  local tree = ts_parser:parse()
  if not tree or #tree == 0 then
    return M.tags_inline(lines)
  end

  local root = tree[1]:root()

  -- Construir set de líneas que están en nodos a ignorar
  local lineas_ignorar = {}

  local nodos_ignorar = {
    "fenced_code_block",
    "code_span",
    "atx_heading",
    "link_destination",
    "uri_autolink",
  }

  local function marcar_nodos(node)
    local tipo = node:type()
    for _, ignorar in ipairs(nodos_ignorar) do
      if tipo == ignorar then
        local sr, _, er, _ = node:range()
        for l = sr, er do
          lineas_ignorar[l + 1] = true -- 0-indexed a 1-indexed
        end
        return
      end
    end
    for child in node:iter_children() do
      marcar_nodos(child)
    end
  end

  marcar_nodos(root)

  -- Ahora buscar tags solo en líneas no ignoradas
  local _, fin_fm = M.frontmatter(lines)
  local inicio = (fin_fm or 0) + 1
  local resultado = {}

  for i = inicio, #lines do
    if lineas_ignorar[i] then goto continue end

    local linea = lines[i]
    if linea:match("^#+ ") then goto continue end

    for pos, tag in linea:gmatch("()#([%w_/%-]+)") do
      local pre = linea:sub(1, pos - 1)
      if pre:match("https?://[^%s]*$") then goto next_tag end
      if tag:match("^%x+$") and (#tag == 3 or #tag == 6) then goto next_tag end
      if pos > 1 then
        local char_antes = linea:sub(pos - 1, pos - 1)
        if char_antes:match("[%w_]") then goto next_tag end
      end
      resultado[#resultado + 1] = { nombre = tag, linea = i }
      ::next_tag::
    end
    ::continue::
  end

  return resultado
end

return M
