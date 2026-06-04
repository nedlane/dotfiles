-- Small editing niceties. (Commenting uses Neovim's built-in `gc`/`gcc`.)
return {
  {
    "windwp/nvim-autopairs",
    event = "InsertEnter",
    opts = {},
  },
  {
    "echasnovski/mini.surround",
    event = "VeryLazy",
    opts = {}, -- sa/sd/sr add/delete/replace surroundings
  },
}
