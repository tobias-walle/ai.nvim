---@class Chat.Options
---@field adapter Adapter
---@field tools? ToolDefinition[]
---@field on_chat_start? fun()
---@field on_chat_update? fun(update: AdapterStreamUpdate): nil
---@field on_chat_exit? fun(data: AdapterStreamExitData): nil
---@field on_tool_call_start? fun(tool_call: AdapterToolCall, index: number): nil
---@field on_tool_call_finish? fun(tool_call: AdapterToolCall, result: AdapterMessageToolCallResult, index: number): nil

---@class Chat: Chat.Options -- Wraps an adapter and adds a chat history and other comfort functions
---@field messages AdapterMessage[]
---@field tools ToolDefinition[]
---@field current_message? AdapterMessage
---@field job? Job
---@field cancelled? boolean
local Chat = {}
Chat.__index = Chat

local Tools = require('ai.utils.tools')

---@param options Chat.Options
---@return Chat
function Chat:new(options)
  local chat = setmetatable(options, self)
  ---@cast chat Chat
  chat.messages = {}
  chat.tools = options.tools or {}
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

  self.current_message = {
    role = 'assistant',
    content = '',
  }

  local request_messages = self.messages
  self.messages = vim.list_extend({}, self.messages)
  table.insert(self.messages, self.current_message)

  ---@type Chat.SendOptions
  local custom_options = {
    tools = vim
      .iter(self.tools)
      :map(function(tool)
        return tool.definition
      end)
      :totable(),
    messages = request_messages,
    on_update = function(update)
      if self.cancelled then
        return
      end
      self.current_message.content = update.response
      self.current_message.tool_calls = update.tool_calls
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

      self.current_message.content = data.response
      self.current_message.tool_calls = data.tool_calls
      self.current_message.tool_call_results = {}

      if options.on_exit then
        options.on_exit(data)
      end
      if self.on_chat_exit then
        self.on_chat_exit(data)
      end

      if #data.tool_calls > 0 then
        local is_any_tool_call_completing_chat = false
        for i, tool_call in ipairs(data.tool_calls) do
          local tool_definition =
            Tools.find_tool_definition(self.tools, tool_call.tool)
          is_any_tool_call_completing_chat = is_any_tool_call_completing_chat
            or (tool_definition and tool_definition.is_completing_chat or false)
          if self.on_tool_call_start then
            self.on_tool_call_start(tool_call, i)
          end
        end
        require('ai.utils.tools').execute_tool_calls(
          self.tools,
          data.tool_calls,
          function(result, _, finished)
            if self.cancelled then
              return
            end
            -- Find the right tool call
            local index, tool_call
            for i, t in ipairs(data.tool_calls) do
              if t.id == result.id then
                index = i
                tool_call = t
                break
              end
            end

            table.insert(self.current_message.tool_call_results, result)
            if self.on_tool_call_finish then
              self.on_tool_call_finish(tool_call, result, index)
            end
            if finished then
              if not is_any_tool_call_completing_chat then
                ---@type Chat.SendOptions
                local options_new = vim.tbl_extend('force', {}, options)
                options_new.messages = {}
                self:send(options_new)
              end
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
  if self.job then
    self.job:stop()
  end
  self.current_message = nil
  self.cancelled = true
end

---@param self Chat
function Chat:clear()
  self:cancel()
  self.messages = {}
  self.tools = {}
end

return Chat
