local M = {}

---@class ai.ToolDefinition.ExcutionResult
---@field result any

---@class ai.ToolDefinition
---@field is_completing_chat? boolean
---@field definition Tool
---@field execute fun(params: table, callback: fun(result: ai.ToolDefinition.ExcutionResult): nil): nil -- Run the tool and get a result
---@field render? fun(tool_call: AdapterMessageToolCall, tool_call_result?: AdapterMessageToolCallResult): string[] -- Get a string representation of the tool

---@param tool ai.ToolDefinition
---@return string
function M.get_tool_definition_name(tool)
  return tool.definition.name
end

---@param tool ai.ToolDefinition
---@param name string
---@return boolean
function M.is_tool_definition_matching_name(tool, name)
  return M.get_tool_definition_name(tool) == name
end

return M
