local requests = require('ai.utils.requests')

---@class OpenAILLMOptions
---@field model string?
---@field endpoint string?
---@field api_key string?

---@class OpenAILLM: LLMProvider
---@field endpoint string
---@field api_key string
local M = require('ai.providers').LLMProvider:new()
M.__index = M

-- Creates a new OpenAI instance
---@param options OpenAILLMOptions?
---@return OpenAILLM
function M:new(options)
  options = options or {}
  return setmetatable({
    name = 'openai',
    endpoint = options.endpoint or 'https://api.openai.com',
    api_key = options.api_key or os.getenv('OPENAI_API_KEY'),
    model = options.model or 'gpt-4o',
  }, self)
end

---@param options LLMStreamOptions
---@return vim.SystemObj
function M:stream(options)
  return requests.stream({
    url = self.endpoint .. '/v1/chat/completions',
    headers = {
      ['Authorization'] = 'Bearer ' .. self.api_key,
    },
    json_body = {
      model = self.model,
      messages = {
        { role = 'system', content = options.system_prompt },
        unpack(options.messages),
      },
      max_tokens = options.max_tokens,
      temperature = options.temperature,
      stream = true,
    },
    on_data = function(data)
      local text = data.choices[1].delta.content
      if text then
        options.on_data(text)
      end
    end,
  })
end

return M
