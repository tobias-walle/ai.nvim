local M = {}

---@param template string
---@param placeholders table
function M.replace_placeholders(template, placeholders)
  return string.gsub(template, '{{([-_%w]+)}}', placeholders)
end

return M
