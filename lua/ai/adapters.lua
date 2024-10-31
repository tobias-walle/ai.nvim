local M = {}

local requests = require('ai.utils.requests')

---@class AdapterMessage
---@field role "user" | "assistant"
---@field content string

---@class AdapterRequestOptions
---@field model string
---@field messages AdapterMessage[]
---@field system_prompt? string
---@field max_tokens? integer
---@field temperature? float

---@class AdapterHandlers
---@field create_request_body fun(request: AdapterRequestOptions): table -- Create the request body for the API
---@field parse_response fun(raw_response: string): any -- Parse the response so they can be used by the following function
---@field is_done fun(response: any): boolean -- Return true if the response is completed
---@field get_tokens fun(response: any): { input: integer | nil, output: integer | nil } | nil
---@field get_delta fun(response: any): string | nil -- Get the text from the response

---@class AdapterOptions
---@field name string
---@field url string
---@field headers table
---@field default_model string
---@field handlers AdapterHandlers

---@class Adapter: AdapterOptions
---@field model string
local Adapter = {}
Adapter.__index = Adapter

---@param options AdapterOptions
---@return Adapter
function Adapter:new(options)
  local adapter = setmetatable(options, self)
  adapter.model = options.default_model
  ---@diagnostic disable-next-line: return-type-mismatch
  return adapter
end

---@class AdapterStreamUpdate
---@field delta string
---@field response string
---@field input_tokens integer
---@field output_tokens integer

---@class AdapterStreamExitData
---@field response string
---@field input_tokens integer
---@field output_tokens integer

---@class AdapterStreamOptions
---@field messages AdapterMessage[]
---@field system_prompt? string
---@field max_tokens? integer
---@field temperature? float
---@field on_update fun(update: AdapterStreamUpdate): nil
---@field on_exit? fun(data: AdapterStreamExitData): nil
--- @field on_error (fun(error: string): nil)?

---@param options AdapterStreamOptions
---@return Job
function Adapter:chat_stream(options)
  local is_done = false
  local response = ''
  local input_tokens = 0
  local output_tokens = 0
  return requests.stream({
    url = self.url,
    headers = self.headers,
    json_body = self.handlers.create_request_body({
      model = self.model,
      messages = options.messages,
      system_prompt = options.system_prompt,
      max_tokens = options.max_tokens,
      temperature = options.temperature,
    }),
    on_data = function(raw_response)
      local data = self.handlers.parse_response(raw_response)
      if data == nil then
        return
      end

      -- Check if done
      is_done = is_done and self.handlers.is_done(data)
      if is_done then
        return
      end

      -- Update tokens
      local tokens = self.handlers.get_tokens(data)
      if tokens then
        input_tokens = input_tokens + (tokens.input or 0)
        output_tokens = output_tokens + (tokens.output or 0)
      end

      -- Get delta
      local delta = self.handlers.get_delta(data)
      if not delta then
        return
      end

      -- Aggregate
      response = response .. delta

      options.on_update({
        response = response,
        delta = delta,
        input_tokens = input_tokens,
        output_tokens = output_tokens,
      })
    end,
    on_error = options.on_error,
    on_exit = function()
      if options.on_exit then
        options.on_exit({
          response = response,
          input_tokens = input_tokens,
          output_tokens = output_tokens,
        })
      end
    end,
  })
end

M.Adapter = Adapter

return M
