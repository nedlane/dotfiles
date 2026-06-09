return {
  {
    "nvim-telescope/telescope.nvim",
    -- 0.2.x is the stable line that uses native vim.treesitter in the previewer
    -- (the old 0.1.x called nvim-treesitter's removed parsers/configs API, which
    -- crashes against the nvim-treesitter rewrite). Needs Neovim >= 0.11.
    version = "^0.2",
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
    opts = {},
  },
}
