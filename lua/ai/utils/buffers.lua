local M = {}

---Finds the buffer number of the first buffer whose name matches the given target name.
---
---@param target_name string The name or pattern to match against buffer names.
---@return integer|nil bufnr The buffer number if found, or nil if no matching buffer exists.
function M.find_buf_by_name(target_name)
  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_get_name(bufnr):match(target_name) then
      return bufnr
    end
  end
  return nil
end

---@param bufnr_or_file number|string
---@return integer
function M.get_bufnr(bufnr_or_file)
  if type(bufnr_or_file) == 'number' then
    return bufnr_or_file
  end
  local file = bufnr_or_file
  local bufnr = vim.fn.bufnr(file, true)
  -- Ensure the buffer name is set
  if vim.api.nvim_buf_get_name(bufnr) == '' then
    vim.api.nvim_buf_set_name(bufnr, file)
  end
  -- Trigger filetype detection
  vim.api.nvim_buf_call(bufnr, function()
    vim.cmd('filetype detect')
  end)
  return bufnr
end

return M
