local M = {}

---@alias Placeholders table<string, string | number>

---@param template string
---@param placeholders Placeholders
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

---@param text string
---@return string
function M.strip_ansi_codes(text)
  if type(text) ~= 'string' then
    return text
  end
  -- Remove ANSI escape sequences
  -- Pattern matches: ESC[ followed by any number of digits, semicolons, and other characters,
  -- ending with a letter (the command character)
  local result = text:gsub('[\27\155][][()#;?%d]*[A-PRZcf-ntqry=><~]', '')
  return result
end

---@param lines string[]
---@return string[]
function M.flatten_lines(lines)
  local result = {}
  for _, item in ipairs(lines) do
    for _, line in ipairs(vim.split(tostring(item), '\n')) do
      table.insert(result, line)
    end
  end
  return result
end

return M
