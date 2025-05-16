local M = {}

local replace_placeholders = require('ai.utils.strings').replace_placeholders

---Builds a prompt by joining lines with newlines and replacing placeholders.
---@param lines string[] List of lines to join
---@param placeholders? table<string, string> Table of placeholder replacements
---@return string prompt The joined prompt string with placeholders replaced
function M.build_prompt(lines, placeholders)
  local processed_lines = {}
  for _, line in ipairs(lines) do
    if line:find('%S') then
      table.insert(processed_lines, vim.trim(line))
    else
      table.insert(processed_lines, line)
    end
  end
  local prompt = table.concat(processed_lines, '\n')
  if placeholders then
    prompt = replace_placeholders(prompt, placeholders)
  end
  return prompt
end

return M
