return {
  {
    "nvim-telescope/telescope.nvim",
    branch = "0.1.x",
    cmd = "Telescope",
    dependencies = {
      "nvim-lua/plenary.nvim",
      "nvim-tree/nvim-web-devicons",
    },
    keys = {
      { "<leader>ff", "<cmd>Telescope find_files<CR>", desc = "Find files" },
      { "<leader>fg", "<cmd>Telescope live_grep<CR>", desc = "Live grep" },
      { "<leader>fb", "<cmd>Telescope buffers<CR>", desc = "Buffers" },
      { "<leader>fh", "<cmd>Telescope help_tags<CR>", desc = "Help tags" },
      { "<leader>fd", "<cmd>Telescope diagnostics<CR>", desc = "Diagnostics" },
      { "<leader>fr", "<cmd>Telescope lsp_references<CR>", desc = "References" },
      { "<leader>fs", "<cmd>Telescope lsp_document_symbols<CR>", desc = "Doc symbols" },
    },
    opts = {
      defaults = {
        -- nvim-treesitter rewrite (main branch) dropped the old parsers/configs
        -- API that Telescope 0.1.x uses in treesitter_attach; disable treesitter
        -- highlighting in the previewer so it falls back to vim regex syntax.
        preview = { treesitter = false },
      },
    },
  },
}
