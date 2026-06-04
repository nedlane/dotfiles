-- nvim-treesitter on the `main` branch (the rewrite). The classic API
-- (ensure_installed / nvim-treesitter.configs / highlight=indent= opts) is gone:
-- parsers are installed with require("nvim-treesitter").install{}, and
-- highlighting/indent are started per-buffer via vim.treesitter.start +
-- 'indentexpr'. Requires Neovim 0.12+ and the `tree-sitter` CLI to compile
-- parsers. The M1 grammar is registered + started separately in m1.lua.
local ENSURE = {
  "lua",
  "vim",
  "vimdoc",
  "bash",
  "rust",
  "toml",
  "json",
  "yaml",
  "markdown",
  "markdown_inline",
  "c",
  "diff",
  "regex",
}

return {
  {
    "nvim-treesitter/nvim-treesitter",
    branch = "main",
    lazy = false,
    build = ":TSUpdate",
    config = function()
      require("nvim-treesitter").setup()

      -- Install any parsers we want that aren't compiled yet (async, no-op if
      -- already present). get_installed avoids re-triggering the tree-sitter CLI
      -- on every startup.
      local installed = require("nvim-treesitter").get_installed()
      local have = {}
      for _, l in ipairs(installed) do
        have[l] = true
      end
      local missing = vim.tbl_filter(function(l)
        return not have[l]
      end, ENSURE)
      if #missing > 0 then
        require("nvim-treesitter").install(missing)
      end

      -- The rewrite no longer wires highlight/indent automatically. Start both
      -- per-buffer for any filetype whose parser is installed. Guarded so files
      -- without a parser (or with a special setup, e.g. m1scr) are skipped here.
      vim.api.nvim_create_autocmd("FileType", {
        group = vim.api.nvim_create_augroup("TSHighlight", { clear = true }),
        callback = function(args)
          local lang = vim.treesitter.language.get_lang(vim.bo[args.buf].filetype)
          if not lang then
            return
          end
          if not pcall(vim.treesitter.language.add, lang) then
            return
          end
          pcall(vim.treesitter.start, args.buf, lang)
          vim.bo[args.buf].indentexpr = "v:lua.require'nvim-treesitter'.indentexpr()"
        end,
      })
    end,
  },
}
