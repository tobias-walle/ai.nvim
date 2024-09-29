local M = {}

---@class AiNvimOptions
---@field name? string

---@param opts AiNvimOptions
function M.setup(opts)
  opts = opts or {}

  vim.keymap.set('n', '<leader>h', function()
    if opts.name then
      print('Hello ' .. opts.name)
    else
      print('Hello')
    end
  end)
  print('new setup ai.nvim')
end

return M
