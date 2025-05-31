local M = {}

---@param n number
---@return string
function M.format_integer(n)
  local s = tostring(math.floor(n))
  local sep = ','
  s = s:reverse():gsub('(%d%d%d)', '%1' .. sep)
  s = s:reverse():gsub('^' .. sep, '')
  return s
end

return M
