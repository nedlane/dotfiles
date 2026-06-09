-- Neovim config — modern lazy.nvim "IDE" baseline + MoTeC M1 toolchain support.
-- Layout:
--   lua/config/   options, keymaps, autocmds  (loaded eagerly, below)
--   lua/plugins/  one file per plugin spec, auto-imported by lazy.nvim
--   lua/plugins/m1.lua  <- the M1 (.m1scr) integration: tree-sitter-m1 + m1-lsp

-- Leader must be set before lazy / any plugin that maps <leader>.
vim.g.mapleader = " "
vim.g.maplocalleader = "\\"

-- Eager core config.
require("config.options")
require("config.keymaps")
require("config.autocmds")

-- vim.treesitter.language.ft_to_lang was removed in Neovim 0.11; shim it for
-- any plugin that still calls it.
if not vim.treesitter.language.ft_to_lang then
  vim.treesitter.language.ft_to_lang = function(ft)
    return vim.treesitter.language.get_lang(ft) or ft
  end
end

-- Bootstrap lazy.nvim (clones it on first run) then load lua/plugins/*.
local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not (vim.uv or vim.loop).fs_stat(lazypath) then
  local out = vim.fn.system({
    "git",
    "clone",
    "--filter=blob:none",
    "--branch=stable",
    "https://github.com/folke/lazy.nvim.git",
    lazypath,
  })
  if vim.v.shell_error ~= 0 then
    error("Failed to clone lazy.nvim:\n" .. out)
  end
end
vim.opt.rtp:prepend(lazypath)

require("lazy").setup({
  spec = { { import = "plugins" } },
  install = { colorscheme = { "catppuccin" } },
  checker = { enabled = false }, -- don't auto-check for plugin updates
  change_detection = { notify = false },
})
