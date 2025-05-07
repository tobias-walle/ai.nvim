local M = {}

local Tools = require('ai.tools')

---@param ctx ChatContext
---@param buffer ParsedChatBuffer
---@return AdapterMessage[]
function M.create_messages(ctx, buffer)
  ---@type AdapterMessage[]
  local context_messages = {}

  local custom_rules = require('ai.utils.rules').load_custom_rules()
  if custom_rules then
    table.insert(context_messages, {
      role = 'user',
      content = 'Please consider the following project rules instructions, defined by the developers:\n\n'
        .. custom_rules,
    })
  end

  local chat_messages = vim
    .iter(buffer.messages)
    :map(function(m)
      local content = m.content

      -- Remove fake tool calls to not confuse the llm
      for _, tool in ipairs(Tools.all) do
        if tool.is_fake then
          content =
            content:gsub('@' .. Tools.get_tool_definition_name(tool), '')
        end
      end

      local msg = {
        role = m.role,
        content = content,
        tool_calls = {},
        tool_call_results = {},
      }
      if m.tool_calls then
        for _, tool_call in ipairs(m.tool_calls) do
          table.insert(msg.tool_calls, {
            tool = tool_call.tool,
            id = tool_call.id,
            params = tool_call.params,
          })
          if tool_call.result then
            table.insert(
              msg.tool_call_results,
              { id = tool_call.id, result = tool_call.result }
            )
          end
        end
      end
      return msg
    end)
    :totable()

  ---@type AdapterMessage[]
  local variable_messages = {}
  for i = #buffer.messages, 1, -1 do
    if buffer.messages[i].role == 'user' then
      for _, variable_use in ipairs(buffer.messages[i].variables or {}) do
        local variable = require('ai.variables').find_by_name(variable_use.name)
        if variable ~= nil then
          local msg = {
            role = 'user',
            content = variable.resolve(ctx, variable_use.params),
          }
          table.insert(variable_messages, msg)
        end
      end
      break
    end
  end

  local reminder_message_parts = {}
  if require('ai.prompts').reminder_prompt_chat ~= '' then
    table.insert(
      reminder_message_parts,
      require('ai.prompts').reminder_prompt_chat
    )
  end

  for _, tool in ipairs(buffer.fake_tools) do
    if tool.reminder_prompt then
      ---@cast tool FakeToolDefinition
      table.insert(reminder_message_parts, tool.reminder_prompt)
    end
  end

  -- Merge all messages.
  local result = vim.fn.deepcopy(context_messages)
  for i = 1, #chat_messages - 1 do
    table.insert(result, chat_messages[i])
  end
  vim.list_extend(result, variable_messages)
  if #reminder_message_parts > 0 then
    table.insert(result, {
      role = 'user',
      content = table.concat(reminder_message_parts, '\n'),
    })
  end
  table.insert(result, chat_messages[#chat_messages])
  return result
end

return M
