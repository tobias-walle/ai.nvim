---@class Chat: Chat.Options Wraps an adapter and adds a chat history and other comfort functions
---@field messages AdapterMessage[]
---@field job? Job
---@field cancelled? boolean
local Chat = {}
Chat.__index = Chat

---@class Chat.Options
---@field adapter Adapter
---@field tools? RealToolDefinition[]
---@field on_chat_start? fun()
---@field on_chat_update? fun(update: AdapterStreamUpdate): nil
---@field on_chat_exit? fun(data: AdapterStreamExitData): nil
---@field on_tool_call_start? fun(tool_call: AdapterToolCall, index: number): nil
---@field on_tool_call_finish? fun(tool_call: AdapterToolCall, result: AdapterMessageToolCallResult, index: number): nil

---@param options Chat.Options
---@return Chat
function Chat:new(options)
  local chat = setmetatable(options, self)
  self.messages = {}
  self.tools = options.tools or {}
  ---@cast chat Chat
  return chat
end

---@param tool Tool
function Chat:add_tool(tool)
  table.insert(self.tools, tool)
end

---@class Chat.SendOptions: AdapterStreamOptions
---@field adapter? Adapter

---@param options Chat.SendOptions
---@param self Chat
function Chat:send(options)
  assert(options ~= nil, 'Chat:send requires options')
  local adapter = options.adapter or self.adapter
  self.cancelled = false
  vim.list_extend(self.messages, options.messages)

  if self.on_chat_start then
    self.on_chat_start()
  end

  ---@type Chat.SendOptions
  local custom_options = {
    tools = vim
      .iter(self.tools)
      :map(function(tool)
        return tool.definition
      end)
      :totable(),
    messages = self.messages,
    on_update = function(update)
      if self.cancelled then
        return
      end
      if options.on_update then
        options.on_update(update)
      end
      if self.on_chat_update then
        self.on_chat_update(update)
      end
    end,
    on_exit = function(data)
      if self.cancelled then
        return
      end

      ---@type AdapterMessage
      local message = {
        role = 'assistant',
        content = data.response,
        tool_calls = data.tool_calls,
        tool_call_results = {},
      }
      -- Add response to chat history
      table.insert(self.messages, message)

      if options.on_exit then
        options.on_exit(data)
      end
      if self.on_chat_exit then
        self.on_chat_exit(data)
      end

      if #data.tool_calls > 0 then
        for i, tool_call in ipairs(data.tool_calls) do
          if self.on_tool_call_start then
            self.on_tool_call_start(tool_call, i)
          end
        end
        require('ai.utils.tools').execute_tool_calls(
          self.tools,
          data.tool_calls,
          function(result, results, finished)
            -- Find the right tool call
            local index, tool_call
            for i, t in ipairs(data.tool_calls) do
              if t.id == result.id then
                index = i
                tool_call = t
                break
              end
            end

            table.insert(message.tool_call_results, result)
            if self.on_tool_call_finish then
              self.on_tool_call_finish(tool_call, result, index)
            end
            vim.notify('R' .. #results)
            if finished then
              vim.notify('Resend with tool calls')
              self:send(options)
            end
          end
        )
      end
    end,
  }

  self.job =
    adapter:chat_stream(vim.tbl_extend('force', {}, options, custom_options))
end

---@param self Chat
function Chat:cancel()
  self.job:stop()
  self.cancelled = true
end

---@param self Chat
function Chat:clear()
  self.messages = {}
  self.tools = {}
end

return Chat
