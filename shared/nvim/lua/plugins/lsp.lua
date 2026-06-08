-- LSP for general languages (Lua, Rust — the M1 toolchain itself is Rust).
-- The M1 language server (m1-lsp, for .m1scr) is configured separately in
-- lua/plugins/m1.lua. Buffer-local LSP keymaps are set once here via LspAttach,
-- so they apply to EVERY server including m1-lsp.
return {
  {
    "neovim/nvim-lspconfig",
    event = { "BufReadPre", "BufNewFile" },
    dependencies = {
      { "mason-org/mason.nvim", config = true },
      "mason-org/mason-lspconfig.nvim",
      "saghen/blink.cmp",
    },
    config = function()
      -- Shared per-buffer keymaps when any LSP attaches.
      vim.api.nvim_create_autocmd("LspAttach", {
        group = vim.api.nvim_create_augroup("UserLspAttach", { clear = true }),
        callback = function(ev)
          local map = function(keys, fn, desc)
            vim.keymap.set("n", keys, fn, { buffer = ev.buf, desc = "LSP: " .. desc })
          end
          map("gd", vim.lsp.buf.definition, "Goto definition")
          map("gD", vim.lsp.buf.declaration, "Goto declaration")
          map("gi", vim.lsp.buf.implementation, "Goto implementation")
          map("gr", vim.lsp.buf.references, "References")
          map("K", vim.lsp.buf.hover, "Hover docs")
          map("<leader>rn", vim.lsp.buf.rename, "Rename symbol")
          map("<leader>ca", vim.lsp.buf.code_action, "Code action")
        end,
      })

      -- Diagnostics presentation.
      vim.diagnostic.config({
        virtual_text = true,
        severity_sort = true,
        float = { border = "rounded", source = true },
      })

      local capabilities = require("blink.cmp").get_lsp_capabilities()

      -- General servers installed/managed by Mason.
      require("mason-lspconfig").setup({
        ensure_installed = { "lua_ls", "rust_analyzer", "bashls", "marksman" },
      })

      vim.lsp.config("*", { capabilities = capabilities })
      vim.lsp.config("lua_ls", {
        settings = { Lua = { diagnostics = { globals = { "vim" } } } },
      })
      vim.lsp.enable({ "lua_ls", "rust_analyzer", "bashls", "marksman" })
    end,
  },
}
