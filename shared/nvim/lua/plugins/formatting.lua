return {
  {
    "WhoIsSethDaniel/mason-tool-installer.nvim",
    dependencies = { "mason-org/mason.nvim" },
    opts = {
      ensure_installed = {
        "mdslw", -- markdown
        "prettier", -- json, yaml
        "stylua", -- lua
        "shfmt", -- shell
      },
    },
  },

  {
    "stevearc/conform.nvim",
    event = { "BufWritePre" },
    cmd = { "ConformInfo" },
    keys = {
      {
        "<leader>fm",
        function()
          require("conform").format({ async = true, lsp_fallback = true })
        end,
        mode = "",
        desc = "Format buffer",
      },
    },
    opts = {
      formatters_by_ft = {
        lua = { "stylua" },
        sh = { "shfmt" },
        bash = { "shfmt" },
        zsh = { "shfmt" },
        markdown = { "mdslw" },
        json = { "prettier" },
        yaml = { "prettier" },
      },
      formatters = {
        -- conform pipes the buffer to mdslw over stdin, and mdslw only looks for
        -- .mdslw.toml when it knows which file the text came from. Without this
        -- it silently falls back to its defaults (notably end-markers "?!:.",
        -- which breaks lines after every colon).
        mdslw = {
          prepend_args = function(_, ctx)
            if ctx.filename == "" then
              return {}
            end
            return { "--stdin-filepath", ctx.filename }
          end,
        },
      },
      format_on_save = { timeout_ms = 1000, lsp_fallback = true },
    },
  },
}
