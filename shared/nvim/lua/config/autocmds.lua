-- Global autocommands. (LSP/format-on-save autocmds live in their plugin specs.)
local aug = vim.api.nvim_create_augroup("UserCore", { clear = true })

-- Briefly highlight yanked text.
vim.api.nvim_create_autocmd("TextYankPost", {
  group = aug,
  callback = function()
    vim.highlight.on_yank()
  end,
})

-- Trim trailing whitespace on save (skip filetypes where it can matter).
vim.api.nvim_create_autocmd("BufWritePre", {
  group = aug,
  callback = function()
    -- Skip special/read-only buffers (e.g. checkhealth, help): substituting on a
    -- non-modifiable buffer throws E21. Only trim real, editable file buffers.
    if vim.bo.buftype ~= "" or not vim.bo.modifiable then
      return
    end
    if vim.bo.filetype == "" or vim.bo.filetype == "markdown" then
      return
    end
    local save = vim.fn.winsaveview()
    vim.cmd([[keeppatterns %s/\s\+$//e]])
    vim.fn.winrestview(save)
  end,
})
