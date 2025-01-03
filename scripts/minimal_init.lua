-- Add current directory to 'runtimepath' to be able to use 'lua' files
vim.cmd([[let &rtp.=','.getcwd()]])

vim.g.mapleader = ' '
vim.g.maplocalleader = ','

-- Add 'mini.nvim' to 'runtimepath' to be able to use 'mini.test'
-- Assumed that 'mini.nvim' is stored in 'deps/mini.nvim'
vim.cmd('set rtp+=deps/mini.nvim')
vim.cmd('set rtp+=deps/dressing.nvim')
vim.cmd('set rtp+=deps/cmp.nvim')

-- Set up 'mini.test' only when calling headless Neovim (like with `make test`)
if #vim.api.nvim_list_uis() == 0 then
  -- Set up 'mini.test'
  require('mini.test').setup()
end
