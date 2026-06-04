-- General editor options. Kept conservative + sensible.
local opt = vim.opt

opt.number = true
opt.relativenumber = true
opt.cursorline = true
opt.signcolumn = "yes" -- stable gutter (LSP/git signs don't shift text)
opt.scrolloff = 8
opt.wrap = false

-- Indentation: 4 spaces by default (M1 ftplugin reaffirms this for .m1scr).
opt.expandtab = true
opt.shiftwidth = 4
opt.tabstop = 4
opt.smartindent = true

-- Search.
opt.ignorecase = true
opt.smartcase = true
opt.incsearch = true
opt.hlsearch = true

-- Splits open where you'd expect.
opt.splitright = true
opt.splitbelow = true

-- System clipboard, mouse, true colour.
opt.clipboard = "unnamedplus"
opt.mouse = "a"
opt.termguicolors = true

-- Persistent undo, no swap/backup clutter.
opt.undofile = true
opt.swapfile = false
opt.backup = false

-- Faster UI / better completion UX.
opt.updatetime = 250
opt.timeoutlen = 400
opt.completeopt = "menu,menuone,noselect"

opt.list = true
opt.listchars = { tab = "» ", trail = "·", nbsp = "␣" }
