local M = {}

local requests = require('ai.utils.requests')

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
---@field params table

---@class AdapterMessageToolCallResult
---@field id string
---@field result any

---@class AdapterMessage
---@field role "user" | "assistant"
---@field content string
---@field tool_calls? AdapterMessageToolCall[]
---@field tool_call_results? AdapterMessageToolCallResult[]

---@class AdapterRequestOptions
---@field model string
---@field messages AdapterMessage[]
---@field system_prompt? string
---@field max_tokens? integer
---@field temperature? float
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

---@class AdapterHandlers
---@field create_request_body fun(request: AdapterRequestOptions): table -- Create the request body for the API
---@field parse_response fun(raw_response: string): any -- Parse the response so they can be used by the following function
---@field is_done fun(response: any): boolean -- Return true if the response is completed
---@field get_tokens fun(response: any): { input: integer | nil, input_cached: integer | nil, output: integer | nil } | nil
---@field get_delta fun(response: any): AdapterDelta | nil -- Get the text from the response
---@field get_error fun(response: any): string | nil -- Get an error from the response if it exists

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
---@field input_tokens integer
---@field output_tokens integer

---@class AdapterStreamExitData
---@field response string
---@field tool_calls AdapterToolCall[]
---@field input_tokens integer
---@field input_tokens_cached integer
---@field output_tokens integer
---@field exit_code integer
---@field cancelled boolean

---@class AdapterStreamOptions
---@field messages AdapterMessage[]
---@field system_prompt? string
---@field max_tokens? integer
---@field temperature? float
---@field tools? Tool[] List of tools that can be used by the model
---@field on_update fun(update: AdapterStreamUpdate): nil
---@field on_exit? fun(data: AdapterStreamExitData): nil
--- @field on_error (fun(error: string): nil)?

---@param options AdapterStreamOptions
---@return Job
function Adapter:chat_stream(options)
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

  local input_tokens = 0
  local input_tokens_cached = 0
  local output_tokens = 0
  local request_body = self.handlers.create_request_body({
    model = self.model,
    messages = options.messages,
    system_prompt = options.system_prompt,
    max_tokens = options.max_tokens,
    temperature = options.temperature,
    tools = options.tools,
  })

  local url = self.url:gsub('{{model}}', self.model)
  return requests.stream({
    url = url,
    headers = self.headers,
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
        input_tokens = input_tokens + (tokens.input or 0)
        input_tokens_cached = input_tokens_cached + (tokens.input_cached or 0)
        output_tokens = output_tokens + (tokens.output or 0)
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
      options.on_update({
        response = response,
        delta = delta_content,
        input_tokens = input_tokens,
        input_tokens_cached = input_tokens_cached,
        output_tokens = output_tokens,
        tool_calls = tool_calls,
      })
    end,
    on_error = options.on_error,
    on_exit = function(exit_code, cancelled)
      if options.on_exit then
        options.on_exit({
          response = response,
          tool_calls = tool_calls,
          input_tokens = input_tokens,
          input_tokens_cached = input_tokens_cached,
          output_tokens = output_tokens,
          exit_code = exit_code,
          cancelled = cancelled,
        })
      end
    end,
  })
end

M.Adapter = Adapter

return M
