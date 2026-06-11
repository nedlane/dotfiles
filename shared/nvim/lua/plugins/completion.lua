-- blink.cmp: fast completion. `version = "*"` pulls a prebuilt fuzzy-match
-- binary (no Rust build needed). Exposes get_lsp_capabilities() used by lsp.lua.
return {
  {
    "zbirenbaum/copilot.lua",
    event = "InsertEnter",
    cmd = "Copilot",
    opts = {
      copilot_node_command = vim.fn.expand("$HOME/.nvm/versions/node/v26.3.0/bin/node"),
      filetypes = {
        markdown = true,
        yaml = true,
      },
      suggestion = {
        enabled = true,
        auto_trigger = true,
        hide_during_completion = false,
        keymap = {
          accept = false, -- <Tab> is handled by blink.cmp below
          accept_word = "<M-w>",
          accept_line = "<M-l>",
        },
      },
      panel = { enabled = true },
    },
  },

  {
    "saghen/blink.cmp",
    version = "*",
    event = "InsertEnter",
    opts = {
      keymap = {
        preset = "default", -- <C-space> open, <C-y> accept, <C-n>/<C-p> select
        ["<Tab>"] = {
          function(cmp)
            if cmp.snippet_active() then
              return cmp.accept()
            end
            return cmp.select_and_accept()
          end,
          "snippet_forward",
          function()
            local ok, suggestion = pcall(require, "copilot.suggestion")
            if ok and suggestion.is_visible() then
              suggestion.accept()
              return true
            end
          end,
          "fallback",
        },
        ["<S-Tab>"] = { "snippet_backward", "fallback" },
      },
      appearance = { nerd_font_variant = "mono" },
      sources = {
        default = { "lsp", "path", "snippets", "buffer" },
      },
      completion = {
        documentation = { auto_show = true, auto_show_delay_ms = 200 },
      },
      signature = { enabled = true },
    },
  },
}
