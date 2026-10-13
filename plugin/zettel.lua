if vim.g.loaded_zettel then
  return
end
vim.g.loaded_zettel = true

vim.api.nvim_create_user_command("Zettel", function(args)
  require("zettel").ejecutar(args)
end, {
  nargs = "*",
  range = true,
  complete = function(_, line, _)
    return require("zettel").completar(line)
  end,
})
