local M = {}

---@class ToolDefinition
---@field definition Tool
---@field execute fun(ctx: ChatContext, params: table, callback: fun(result: any): nil): nil -- Run the tool and get a result

---@type ToolDefinition[]
M.all = {
  require('ai.tools.editor'),
}

---@param name string
---@return ToolDefinition | nil
function M.find_tool_by_name(name)
  for _, tool in ipairs(M.all) do
    if tool.definition.name == name then
      return tool
    end
  end
  return nil
end

return M
