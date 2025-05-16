local M = {}

---@param template string
---@param placeholders table
---@return string
function M.replace_placeholders(template, placeholders)
  local result = template
  local max_iterations = 10
  for _ = 1, max_iterations do
    local replaced
    result, replaced = string.gsub(result, '{{([-_%w]+)}}', placeholders)
    if replaced == 0 then
      break
    end
  end
  return result
end

return M
