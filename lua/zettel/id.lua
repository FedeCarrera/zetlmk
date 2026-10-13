local M = {}

--- Genera un ID de 14 dígitos con la fecha/hora actual.
--- @return string
function M.timestamp()
  return os.date("%Y%m%d%H%M%S")
end

--- Genera un ID único, sumando un segundo si hay choque.
--- @param existe_fn fun(id: string): boolean función que dice si el ID ya está tomado
--- @return string
function M.generar(existe_fn)
  local id = M.timestamp()
  while existe_fn(id) do
    -- Parsear el timestamp, sumar un segundo, reformatear
    local t = M.parsear(id)
    t = os.time(t) + 1
    id = os.date("%Y%m%d%H%M%S", t)
  end
  return id
end

--- Parsea un ID de 14 dígitos en una tabla compatible con os.time.
--- @param id string
--- @return table
function M.parsear(id)
  return {
    year = tonumber(id:sub(1, 4)),
    month = tonumber(id:sub(5, 6)),
    day = tonumber(id:sub(7, 8)),
    hour = tonumber(id:sub(9, 10)),
    min = tonumber(id:sub(11, 12)),
    sec = tonumber(id:sub(13, 14)),
  }
end

--- Valida que un string sea un ID de 14 dígitos numéricos.
--- @param s string
--- @return boolean
function M.es_valido(s)
  return type(s) == "string" and #s == 14 and s:match("^%d+$") ~= nil
end

return M
