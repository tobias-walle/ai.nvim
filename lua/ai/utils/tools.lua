local M = {}

---@param tools ToolDefinition[]
---@param tool_calls AdapterToolCall[]
---@param callback fun(result: AdapterMessageToolCallResult, all_results: AdapterMessageToolCallResult[], finished: boolean)
function M.execute_tool_calls(tools, tool_calls, callback)
  ---@type AdapterMessageToolCallResult[]
  local results = {}
  local completed = 0
  for _, tool_call in ipairs(tool_calls) do
    ---@type ToolDefinition
    local tool = vim.iter(tools):find(function(t)
      return t.definition.name == tool_call.tool
    end)
    if not tool then
      completed = completed + 1
      vim.notify('Tool not found: ' .. tool_call.tool, vim.log.levels.ERROR)
      goto continue
    end

    tool.execute(tool_call.params, function(result)
      completed = completed + 1
      ---@type AdapterMessageToolCallResult
      local tool_call_result = {
        id = tool_call.id,
        result = result,
      }
      table.insert(results, tool_call_result)
      callback(tool_call_result, results, completed == #tool_calls)
    end)

    ::continue::
  end
end

---@param tools ToolDefinition[]
---@param name string
---@return ToolDefinition | nil
function M.find_tool_definition(tools, name)
  return vim.iter(tools):find(function(tool)
    ---@cast tool ToolDefinition
    return tool.definition.name == name
  end)
end

return M
