local M = {}

---@class RealToolDefinition
---@field is_fake false|nil
---@field definition Tool
---@field execute fun(ctx: ChatContext, params: table, callback: fun(result: any): nil): nil -- Run the tool and get a result

---@class RealToolCall
---@field tool string
---@field id string
---@field is_loading boolean
---@field params table|nil
---@field result string|nil

---@class FakeToolCall
---@field params table
---@field result any|nil

---@class FakeToolDefinition
---@field is_fake true Always true if fake
---@field name string The name of the tool, used for parsing
---@field system_prompt string The prompt describing what the tool does and how it should be formatted in the buffer. The description needs to be as clear as possible and should contain one example. And also highlight which common mistakes to avoid.
---@field reminder_prompt? string A prompt added directly before the user message to reminder the LLM about the capability
---@field parse fun(message_content: string): FakeToolCall[] Parse the fake tool calls out of an assistant message following the format described above. It is highly recommend to utilize treesitter for parsing.
---@field execute fun(ctx: ChatContext, params: table, callback: fun(): nil): nil Run the fake tool. Results are not supported yet.

---@alias ToolDefinition (RealToolDefinition | FakeToolDefinition)

---@type ToolDefinition[]
M.all = {
  require('ai.tools.editor'),
  require('ai.tools.web'),
  require('ai.tools.grep'),
  require('ai.tools.file'),
}

---@param tool ToolDefinition
---@return string
function M.get_tool_definition_name(tool)
  if tool.is_fake then
    return tool.name
  else
    return tool.definition.name
  end
end

---@param tool ToolDefinition
---@param name string
---@return boolean
function M.is_tool_definition_matching_name(tool, name)
  return M.get_tool_definition_name(tool) == name
end

---@param name string
---@return RealToolDefinition | nil
function M.find_real_tool_by_name(name)
  for _, tool in ipairs(M.all) do
    if not tool.is_fake and M.is_tool_definition_matching_name(tool, name) then
      ---@cast tool RealToolDefinition
      return tool
    end
  end
  return nil
end

---@class FakeToolUse
---@field tool FakeToolDefinition
---@field calls FakeToolCall[]

---@param tools ToolDefinition[]
---@param message_content string
---@return FakeToolUse[]
function M.find_fake_tool_uses(tools, message_content)
  ---@type FakeToolUse[]
  local fake_took_uses = {}
  for _, tool in ipairs(tools) do
    if tool.is_fake then
      local calls = tool.parse(message_content)
      if #calls > 0 then
        table.insert(fake_took_uses, {
          tool = tool,
          calls = calls,
        })
      end
    end
  end
  return fake_took_uses
end

return M
