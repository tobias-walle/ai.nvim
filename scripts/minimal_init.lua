-- Add current directory to 'runtimepath' to be able to use 'lua' files
vim.cmd([[let &rtp.=','.getcwd()]])

vim.g.mapleader = ' '
vim.g.maplocalleader = ','

-- Add 'mini.nvim' to 'runtimepath' to be able to use 'mini.test'
-- Assumed that 'mini.nvim' is stored in 'deps/mini.nvim'
vim.cmd('set rtp+=deps/mini.nvim')
vim.cmd('set rtp+=deps/dressing.nvim')
vim.cmd('set rtp+=deps/cmp.nvim')
