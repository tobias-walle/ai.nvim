local M = {}

local Requests = require('ai.utils.requests')
local Json = require('ai.utils.json')

---@class ToolParameters
---@field type string
---@field properties table<string, { type: string, description: string }>
---@field required string[]

---@class Tool
---@field name string The name of the tool
---@field description string A description of what the tool does
---@field parameters table The JSON schema for the tool's parameters

---@class AdapterMessageToolCall
---@field tool string
---@field id string
---@field params table | nil

---@class AdapterMessageToolCallResult
---@field id string
---@field result ai.AdapterMessageContent

---@class AdapterMessageContentText
---@field type "text"
---@field text string

---@class AdapterMessageContentImage
---@field type "image"
---@field media_type string
---@field base64 string

---@alias AdapterMessageContentItem AdapterMessageContentText | AdapterMessageContentImage
---@alias ai.AdapterMessageContent string | AdapterMessageContentItem[]

---@class AdapterMessage
---@field role "user" | "assistant"
---@field content ai.AdapterMessageContent
---@field tool_calls? AdapterMessageToolCall[]
---@field tool_call_results? AdapterMessageToolCallResult[]

---@class AdapterPrediction
---@field type string
---@field content string

---@class AdapterRequestOptions
---@field model string
---@field messages AdapterMessage[]
---@field prediction AdapterPrediction
---@field system_prompt? string
---@field max_tokens? integer
---@field temperature? number
---@field tools? Tool[] List of tools that can be used by the model

---@class AdapterMessageDelta
---@field type "message"
---@field content string

---@class AdapterToolCallStart
---@field type "tool_call_start"
---@field id string
---@field tool string

---@class AdapterToolCallDelta
---@field type "tool_call_delta"
---@field content string

---@class AdapterToolCallEnd
---@field type "tool_call_end"

---@alias AdapterDelta (AdapterMessageDelta | AdapterToolCallStart | AdapterToolCallDelta | AdapterToolCallEnd)

---@class AdapterTokenInfo
---@field input integer | nil
---@field input_cached integer | nil
---@field output integer | nil
---@field accepted_prediction_tokens integer | nil
---@field reasoning_tokens integer | nil

---@class AdapterHandlers
---@field create_request_body fun(request: AdapterRequestOptions): table -- Create the request body for the API
---@field parse_response fun(raw_response: string): any -- Parse the response so they can be used by the following function
---@field is_done fun(response: any): boolean -- Return true if the response is completed
---@field get_tokens fun(response: any): AdapterTokenInfo | nil
---@field get_delta fun(response: any): AdapterDelta | nil -- Get the text from the response
---@field get_error fun(response: any): string | nil -- Get an error from the response if it exists

---@class AdapterOptions
---@field name string
---@field url string
---@field headers table
---@field default_model string
---@field handlers AdapterHandlers

---@class ai.Adapter: AdapterOptions
---@field model string
local Adapter = {}
Adapter.__index = Adapter

---@param options AdapterOptions
---@return ai.Adapter
function Adapter:new(options)
  local adapter = setmetatable(options, self)
  adapter.model = options.default_model
  ---@diagnostic disable-next-line: return-type-mismatch
  return adapter
end

---@class AdapterToolCall
---@field tool string
---@field id string
---@field content string -- The streamed content (params) as a string
---@field params table|nil
---@field is_loading boolean -- True while params are loading. Params are nil in this case.

---@class AdapterStreamUpdate
---@field delta string
---@field response string
---@field tool_calls AdapterToolCall[]
---@field tokens AdapterTokenInfo

---@class AdapterStreamExitData
---@field response string
---@field tool_calls AdapterToolCall[]
---@field tokens AdapterTokenInfo
---@field exit_code integer
---@field cancelled boolean

---@class AdapterStreamOptions
---@field messages AdapterMessage[]
---@field prediction? AdapterPrediction
---@field system_prompt? string
---@field max_tokens? integer
---@field temperature? number
---@field tools? Tool[] List of tools that can be used by the model
---@field on_update? fun(update: AdapterStreamUpdate): nil
---@field on_exit? fun(data: AdapterStreamExitData): nil
--- @field on_error (fun(error: string): nil)?

---@param options AdapterStreamOptions
---@return Job
function Adapter:chat_stream(options)
  local config = require('ai.config').get()
  local is_done = false
  local response = ''
  ---@type AdapterToolCall[]
  local tool_calls = {}

  ---@type AdapterToolCall|nil
  local active_tool_call
  local function finalize_active_tool_call_if_present()
    if not active_tool_call then
      return
    end
    local ok, parsed = pcall(
      vim.json.decode,
      active_tool_call.content,
      { luanil = { object = true, array = true } }
    )
    if ok then
      active_tool_call.params = parsed
    else
      vim.notify(
        'Invalid tool call params: '
          .. parsed
          .. ' '
          .. active_tool_call.content
      )
    end
    active_tool_call = nil
  end

  --- @type AdapterTokenInfo
  local tokens_total = {}
  local request_body = self.handlers.create_request_body({
    model = self.model,
    messages = options.messages,
    system_prompt = options.system_prompt,
    max_tokens = options.max_tokens,
    temperature = options.temperature,
    tools = options.tools,
    prediction = options.prediction,
  })
  local headers = self.headers

  local adapter_model_string = self.name .. ':' .. self.model
  for pattern, overrides in pairs(config.model_overrides or {}) do
    if adapter_model_string:match(pattern) then
      request_body =
        vim.tbl_extend('force', {}, request_body, overrides.request or {})
      headers = vim.tbl_extend('force', {}, headers, overrides.headers or {})
    end
  end

  local url = self.url:gsub('{{model}}', self.model)
  return Requests.stream({
    url = url,
    headers = headers,
    json_body = request_body,
    on_data = function(raw_response)
      local data = self.handlers.parse_response(raw_response)
      if data == nil then
        return
      end

      -- Check and log error
      local error = self.handlers.get_error and self.handlers.get_error(data)
      if error ~= nil then
        vim.notify(error, vim.log.levels.ERROR)
      end

      -- Check if done
      is_done = is_done and self.handlers.is_done(data)
      if is_done then
        return
      end

      -- Update tokens
      local tokens = self.handlers.get_tokens(data)
      if tokens then
        for key, value in pairs(tokens) do
          tokens_total[key] = (tokens_total[key] or 0) + (value or 0)
        end
      end

      -- Get delta
      local delta = self.handlers.get_delta(data)
      if not delta then
        return
      end

      local delta_content = ''
      -- Handle different delta types
      if delta.type == 'message' then
        delta_content = delta.content
        response = response .. delta.content
      elseif delta.type == 'tool_call_start' then
        finalize_active_tool_call_if_present()
        -- Start new tool call
        active_tool_call = {
          id = delta.id,
          tool = delta.tool,
          params = nil,
          content = '',
          is_loading = true,
        }
        table.insert(tool_calls, active_tool_call)
      elseif delta.type == 'tool_call_delta' then
        if active_tool_call then
          active_tool_call.content = active_tool_call.content .. delta.content
          local parsed = Json.decode_partial(active_tool_call.content)
          if parsed then
            active_tool_call.params = parsed
          end
        else
          vim.notify(
            'Unexpected tool call delta, no active tool call: '
              .. vim.inspect(delta),
            vim.log.levels.ERROR
          )
        end
      elseif delta.type == 'tool_call_end' then
        if active_tool_call then
          finalize_active_tool_call_if_present()
          active_tool_call = nil
        end
      end
      if options.on_update then
        options.on_update({
          response = response,
          delta = delta_content,
          tokens = tokens_total,
          tool_calls = tool_calls,
        })
      end
    end,
    on_error = options.on_error,
    on_exit = function(exit_code, cancelled)
      if options.on_update then
        options.on_update({
          response = response,
          delta = '',
          tokens = tokens_total,
          tool_calls = tool_calls,
        })
      end
      if options.on_exit then
        options.on_exit({
          response = response,
          tokens = tokens_total,
          tool_calls = tool_calls,
          exit_code = exit_code,
          cancelled = cancelled,
        })
      end
    end,
  })
end

M.Adapter = Adapter

return M
