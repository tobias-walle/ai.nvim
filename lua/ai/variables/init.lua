local M = {}

local Regex = require('ai.utils.regex')

---@class VariableDefinition
---@field name string
---@field resolve fun(ctx: ChatContext, params: table): string
---@field min_params? integer
---@field max_params? integer
---@field cmp_items? fun(cmp_ctx: any, callback: fun(items: lsp.CompletionItem[])): nil Optional completions for the chat blink.cmp source

---@type VariableDefinition[]
M.all = {
  require('ai.variables.buffer'),
  require('ai.variables.selection'),
  require('ai.variables.diagnostics'),
  require('ai.variables.file'),
  require('ai.variables.files'),
  require('ai.variables.web'),
  require('ai.variables.sh'),
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

  -- Initialize a table to store the matches
  local matches = {}

  -- Split the text into lines (if needed) and iterate over each line
  for _, full_match in ipairs(Regex.find_all_regex_matches(msg, M.pattern_full)) do
    local variable_name = full_match[2]
    if M.find_by_name(variable_name) ~= nil then
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
      table.insert(matches, match)
    end
  end

  return M.remove_duplicates(matches)
end

--- Compute a unique key for a variable
---@param name string
---@param params string[]
---@return string
function M.unique_key(name, params)
  return name .. ':' .. table.concat(params, ',')
end

---@param variable_uses VariableUse[]
---@param other_variable_uses? VariableUse[]
---@return VariableUse[]
function M.remove_duplicates(variable_uses, other_variable_uses)
  local unique_keys = {}

  if other_variable_uses then
    for _, use in ipairs(other_variable_uses) do
      local key = M.unique_key(use.name, use.params)
      unique_keys[key] = true
    end
  end

  local unique_variable_uses = {}
  for _, use in ipairs(variable_uses) do
    local key = M.unique_key(use.name, use.params)
    if not unique_keys[key] then
      unique_keys[key] = true
      table.insert(unique_variable_uses, use)
    end
  end
  return unique_variable_uses
end

return M
