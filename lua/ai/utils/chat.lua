---@class Chat: Chat.Options Wraps an adapter and adds a chat history and other comfort functions
---@field messages AdapterMessage[]
---@field job? Job
---@field cancelled? boolean
local Chat = {}
Chat.__index = Chat

---@class Chat.Options
---@field adapter Adapter
---@field on_chat_start? fun()
---@field on_chat_update? fun(update: AdapterStreamUpdate): nil
---@field on_chat_exit? fun(data: AdapterStreamExitData): nil

---@param options Chat.Options
---@return Chat
function Chat:new(options)
  local chat = setmetatable(options, self)
  self.messages = {}
  ---@cast chat Chat
  return chat
end

---@class Chat.SendOptions: AdapterStreamOptions
---@field adapter? Adapter

---@param options Chat.SendOptions
---@param self Chat
function Chat:send(options)
  assert(options ~= nil, 'Chat:send requires options')
  local adapter = self.adapter or options.adapter
  self.cancelled = false
  vim.list_extend(self.messages, options.messages)
  self.job = adapter:chat_stream(vim.tbl_extend('force', {}, options, {
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
      -- Add response to chat history
      table.insert(self.messages, {
        role = 'assistant',
        content = data.response,
      })
      if options.on_exit then
        options.on_exit(data)
      end
      if self.on_chat_exit then
        self.on_chat_exit(data)
      end
    end,
  }))
end

---@param self Chat
function Chat:cancel()
  self.job:stop()
  self.cancelled = true
end

return Chat
