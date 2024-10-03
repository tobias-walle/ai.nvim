---@class AnthropicLLMOptions
---@field model string?
---@field endpoint string?
---@field api_key string?

---@class AnthropicLLM: LLMProvider
---@field endpoint string
---@field api_key string
local M = require('ai.providers').LLMProvider:new()
M.__index = M

local requests = require('ai.utils.requests')

---@param options AnthropicLLMOptions?
---@return AnthropicLLM
function M:new(options)
  options = options or {}
  return setmetatable({
    name = 'anthropic',
    model = options.model or 'claude-3-sonnet-20240229',
    endpoint = options.endpoint or 'https://api.anthropic.com',
    api_key = options.api_key or os.getenv('ANTHROPIC_API_KEY'),
  }, self)
end

---@param options LLMStreamOptions
---@return vim.SystemObj
function M:stream(options)
  return requests.stream({
    url = self.endpoint .. '/v1/messages',
    headers = {
      ['x-api-key'] = self.api_key,
      ['anthropic-version'] = '2023-06-01',
    },
    json_body = {
      model = self.model,
      system = options.system_prompt,
      messages = options.messages,
      max_tokens = options.max_tokens or 1000,
      temperature = options.temperature,
      stream = true,
    },
    on_data = function(data)
      local text = data.delta and data.delta.text
      if text then
        options.on_data(text)
      end
    end,
  })
end

return M
