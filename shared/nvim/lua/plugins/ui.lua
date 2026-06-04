return {
  {
    "nvim-lualine/lualine.nvim",
    event = "VeryLazy",
    dependencies = { "nvim-tree/nvim-web-devicons" },
    opts = {
      -- "auto" follows vim.g.colors_name (catppuccin-mocha), so lualine tracks
      -- the active catppuccin flavour. Catppuccin no longer ships a bare
      -- "catppuccin" lualine theme — only per-flavour ones (catppuccin-mocha …).
      options = { theme = "auto", globalstatus = true },
    },
  },
  {
    "folke/which-key.nvim",
    event = "VeryLazy",
    opts = {
      spec = {
        { "<leader>f", group = "find / format" },
        { "<leader>d", group = "diagnostics" },
        { "<leader>h", group = "git hunks" },
        { "<leader>c", group = "code" },
        { "<leader>m", group = "M1" },
      },
    },
  },
}
