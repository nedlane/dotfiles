-- blink.cmp: fast completion. `version = "*"` pulls a prebuilt fuzzy-match
-- binary (no Rust build needed). Exposes get_lsp_capabilities() used by lsp.lua.
return {
  {
    "saghen/blink.cmp",
    version = "*",
    event = "InsertEnter",
    opts = {
      keymap = { preset = "default" }, -- <C-space> open, <C-y> accept, <C-n>/<C-p> select
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
