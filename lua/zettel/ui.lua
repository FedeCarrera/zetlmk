local M = {}

--- Muestra un mensaje informativo.
--- @param msg string
function M.info(msg)
  vim.notify(msg, vim.log.levels.INFO, { title = "Zettel" })
end

--- Muestra un mensaje de advertencia.
--- @param msg string
function M.advertir(msg)
  vim.notify(msg, vim.log.levels.WARN, { title = "Zettel" })
end

--- Muestra un mensaje de error.
--- @param msg string
function M.error(msg)
  vim.notify(msg, vim.log.levels.ERROR, { title = "Zettel" })
end

--- Pide un texto al usuario.
--- @param prompt string
--- @param callback fun(input: string|nil)
function M.input(prompt, callback)
  vim.ui.input({ prompt = prompt }, function(input)
    if input and vim.trim(input) ~= "" then
      callback(input)
    else
      callback(nil)
    end
  end)
end

--- Abre una ventana flotante con líneas de contenido.
--- @param lines string[]
--- @param opts? { titulo?: string, ancho?: number, alto?: number }
--- @return number bufnr, number winnr
function M.flotante(lines, opts)
  opts = opts or {}
  local ancho = opts.ancho or math.floor(vim.o.columns * 0.7)
  local alto = opts.alto or math.min(#lines + 2, math.floor(vim.o.lines * 0.6))

  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].filetype = "markdown"

  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    width = ancho,
    height = alto,
    row = math.floor((vim.o.lines - alto) / 2),
    col = math.floor((vim.o.columns - ancho) / 2),
    style = "minimal",
    border = "rounded",
    title = opts.titulo and (" " .. opts.titulo .. " ") or nil,
    title_pos = opts.titulo and "center" or nil,
  })

  -- Cerrar con q o Escape
  vim.keymap.set("n", "q", function() vim.api.nvim_win_close(win, true) end, { buffer = buf })
  vim.keymap.set("n", "<Esc>", function() vim.api.nvim_win_close(win, true) end, { buffer = buf })

  return buf, win
end

return M
