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

return M
