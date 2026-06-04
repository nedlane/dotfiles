-- MoTeC M1 toolchain integration for .m1scr / .m1prj files.
--
-- Everything is sourced from the published GitHub plugins (no local checkout,
-- no paths into ~/projects), so it behaves identically on every machine the
-- dotfiles land on and tracks upstream automatically:
--
--   * C-Nucifora/nvim-m1          -> the turn-key integration in one setup():
--                                    m1scr/m1prj filetypes, tree-sitter `m1`
--                                    grammar+queries (compiled from
--                                    tree-sitter-m1), m1-lsp wiring, format +
--                                    lint, and the m1-project edit commands.
--                                    Its `build` hook downloads the *bundled*
--                                    M1 toolchain (m1-lsp/fmt/lint/project) for
--                                    this platform — nothing to compile or
--                                    install by hand.
--   * C-Nucifora/telescope-m1.nvim -> Telescope pickers backed by the same
--                                    m1-lsp / m1-lint (workspace symbols,
--                                    component tree, lint rules).
--
-- nvim-m1 already auto-detects blink.cmp's LSP capabilities, registers the
-- client as "m1lsp", and reapplies filetypes to buffers opened at startup, so
-- there is nothing to re-implement here — just options + convenience maps.

return {
  {
    "C-Nucifora/nvim-m1",
    dependencies = {
      "C-Nucifora/tree-sitter-m1",                       -- m1 grammar + queries (required)
      { "nvim-treesitter/nvim-treesitter", optional = true },
      { "neovim/nvim-lspconfig", optional = true },      -- only used on Neovim 0.10
      { "stevearc/conform.nvim", optional = true },      -- format-on-save path
      { "mfussenegger/nvim-lint", optional = true },     -- standalone-lint path
    },
    -- Download the bundled M1 toolchain (m1-lsp/fmt/lint/project) at the pinned
    -- versions on install + update. Equivalent to running :M1Install.
    build = function()
      require("nvim-m1.install").install()
    end,
    ft = { "m1scr", "m1prj" },
    opts = {
      format_on_save = true,   -- format .m1scr on write with m1-fmt
      lint_on_save = true,     -- lint .m1scr on write with m1-lint
      attach_m1prj = true,     -- attach m1-lsp to Project.m1prj (rename-from-declaration)
    },
    config = function(_, opts)
      require("nvim-m1").setup(opts)

      -- Convenience maps over nvim-m1's own commands (harmless off-filetype).
      local map = vim.keymap.set
      map("n", "<leader>mf", "<cmd>M1Format<CR>",       { desc = "M1: format buffer" })
      map("n", "<leader>mt", "<cmd>M1FormatToggle<CR>", { desc = "M1: toggle format-on-save" })
      map("n", "<leader>ml", "<cmd>M1Lint<CR>",         { desc = "M1: lint buffer" })
      map("n", "<leader>mr", "<cmd>LspRestart m1lsp<CR>", { desc = "M1: restart m1-lsp" })
    end,
  },

  {
    "C-Nucifora/telescope-m1.nvim",
    dependencies = {
      "nvim-telescope/telescope.nvim",
      "C-Nucifora/nvim-m1",  -- starts m1-lsp + shares the canonical client name
    },
    config = function()
      require("telescope").load_extension("m1")
    end,
    -- Lazy-load on first use; the key handler triggers config (load_extension).
    keys = {
      { "<leader>ms", function() require("telescope").extensions.m1.workspace_symbols() end,
        desc = "M1: workspace symbols" },
      { "<leader>mc", function() require("telescope").extensions.m1.components() end,
        desc = "M1: component browser" },
      { "<leader>mR", function() require("telescope").extensions.m1.lint_rules() end,
        desc = "M1: lint rules" },
    },
  },
}
