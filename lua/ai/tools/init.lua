local M = {}

---@class ToolDefinition
---@field is_completing_chat? boolean
---@field definition Tool
---@field execute fun(params: table, callback: fun(result: any): nil): nil -- Run the tool and get a result
---@field render? fun(tool_call: AdapterMessageToolCall, tool_call_result?: AdapterMessageToolCallResult): string[] -- Get a string representation of the tool

---@type ToolDefinition[]
M.all = {
  -- require('ai.tools.editor'),
  -- require('ai.tools.web'),
  -- require('ai.tools.grep'),
  -- require('ai.tools.file'),
}

M.aliases = {
  all = { 'editor', 'grep', 'file', 'web' },
  dev = { 'editor', 'grep', 'file' },
}

---@param tool ToolDefinition
---@return string
function M.get_tool_definition_name(tool)
  return tool.definition.name
end

---@param tool ToolDefinition
---@param name string
---@return boolean
function M.is_tool_definition_matching_name(tool, name)
  return M.get_tool_definition_name(tool) == name
end

---@param name string
---@return ToolDefinition | nil
function M.find_tool_by_name(name)
  local tool = M.find_tool_by_name(name)
  if tool and not tool.is_fake then
    ---@cast tool ToolDefinition
    return tool
  end
  return nil
end

return M
