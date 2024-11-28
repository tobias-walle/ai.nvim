local M = {}

local Regex = require('ai.utils.regex')

---@class VariableDefinition
---@field name string
---@field resolve fun(ctx: ChatContext, params: table): string

---@type VariableDefinition[]
M.all = {
  require('ai.variables.buffer'),
  require('ai.variables.diagnostics'),
  require('ai.variables.file'),
  require('ai.variables.web'),
}

---@param name string
---@return VariableDefinition | nil
function M.find_by_name(name)
  for _, variable in ipairs(M.all) do
    if variable.name == name then
      return variable
    end
  end
  return nil
end

M.pattern_variable_name = [[\v#(%(\w|-)+)*]]
M.pattern_single_param =
  [[\v%(:`([^`\r\n]+)`)|%(:"([^"\r\n]+)")|%(:'([^'\r\n]+)')|%(:([^: \r\n"'`]+))]]
M.pattern_multi_param = '\\v%(' .. M.pattern_single_param .. ')*'
M.pattern_full = M.pattern_variable_name .. M.pattern_multi_param

---@class VariableUse
---@field raw string The raw representation of the variable like it was defined in the buffer
---@field name string
---@field params string[]

--- Parses variable uses from a chat message.
--- Examples of variable use: #buffer, #file:"/path/to/file"
---@param msg string
---@return VariableUse[]
function M.parse_variable_uses(msg)
  -- Define the Vim regex pattern

  -- Compute a unique key for a variable
  local unique_key = function(name, params)
    return name .. ':' .. table.concat(params, ',')
  end

  -- Initialize a table to store the matches
  local matches = {}
  local already_included_keys = {}

  -- Split the text into lines (if needed) and iterate over each line
  for _, full_match in ipairs(Regex.find_all_regex_matches(msg, M.pattern_full)) do
    local variable_name = full_match[2]
    local params = {}
    for _, param_match in
      ipairs(
        Regex.find_all_regex_matches(full_match[1], M.pattern_single_param)
      )
    do
      for i = 2, #param_match do
        -- Find matched group
        if param_match[i] ~= '' then
          table.insert(params, param_match[i])
        end
      end
    end
    local match = {
      raw = full_match[1],
      name = variable_name,
      params = params,
    }
    local match_key = unique_key(match.name, match.params)
    if not already_included_keys[match_key] then
      already_included_keys[match_key] = true
      table.insert(matches, match)
    end
  end

  return matches
end

return M
