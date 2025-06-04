local M = {}

---@generic T
---@param lines T[]
---@param idx_start integer
---@param idx_end integer
---@param replacement T[]
---@return T[]
function M.replace_lines(lines, idx_start, idx_end, replacement)
  local result = {}
  for i = 1, idx_start - 1 do
    table.insert(result, lines[i])
  end
  for i = 1, #replacement do
    table.insert(result, replacement[i])
  end
  for i = idx_end + 1, #lines do
    table.insert(result, lines[i])
  end
  return result
end

return M
