---@param tools Tool[]|nil
---@return Tool[]|nil
local function map_tools(tools)
  if not tools then
    return nil
  end
  local mapped_tools = {}
  for _, tool in ipairs(tools) do
    table.insert(mapped_tools, {
      type = 'function',
      ['function'] = {
        name = tool.name,
        description = tool.description,
        parameters = tool.parameters,
      },
    })
  end
  return mapped_tools
end

---@type AdapterOptions
local options = {
  name = 'openai',
  url = 'https://api.openai.com/v1/chat/completions',
  headers = {
    ['Authorization'] = 'Bearer ' .. os.getenv('OPENAI_API_KEY'),
  },
  default_model = 'gpt-4o',
  handlers = {
    create_request_body = function(request)
      local messages = {}
      if request.system_prompt then
        table.insert(
          messages,
          { role = 'system', content = request.system_prompt }
        )
      end
      for _, msg in ipairs(request.messages) do
        local message = { role = msg.role }
        if msg.content and #msg.content > 0 then
          message.content = msg.content
        end
        if msg.tool_calls then
          message.tool_calls = {}
          for _, tool_call in ipairs(msg.tool_calls) do
            table.insert(message.tool_calls, {
              id = tool_call.id,
              type = 'function',
              ['function'] = {
                name = tool_call.tool,
                arguments = vim.json.encode(tool_call.params),
              },
            })
          end
        end
        table.insert(messages, message)
        if msg.tool_call_results and #msg.tool_call_results > 0 then
          for _, tool_call in ipairs(msg.tool_call_results) do
            table.insert(messages, {
              role = 'tool',
              tool_call_id = tool_call.id,
              content = vim.json.encode(tool_call.result),
            })
          end
        end
      end

      return {
        stream = true,
        model = request.model,
        max_tokens = request.max_tokens,
        temperature = request.temperature,
        tools = map_tools(request.tools),
        messages = messages,
      }
    end,
    parse_response = function(chunk)
      local data = require('ai.utils.requests').parse_sse_data(chunk)
      if not data then
        return
      end
      local success, json = pcall(
        vim.json.decode,
        data,
        { luanil = { object = true, array = true } }
      )
      if success then
        return json
      else
        return data
      end
    end,
    is_done = function(response)
      return response:match('^%s*%[DONE%]%s*$')
    end,
    get_tokens = function(response)
      if response.usage then
        return {
          input = response.usage.prompt_tokens or 0,
          output = response.usage.completion_tokens or 0,
        }
      end
    end,
    get_delta = function(response)
      if not (response.choices and response.choices[1]) then
        return nil
      end

      local delta = response.choices[1].delta

      -- Handle regular message content
      if delta.content then
        return { type = 'message', content = delta.content }
      end

      -- Handle function calls
      if delta.tool_calls then
        for _, tool_call in ipairs(delta.tool_calls) do
          -- Start of tool call
          if
            tool_call.id
            or tool_call['function'] and tool_call['function'].name
          then
            return {
              type = 'tool_call_start',
              tool = tool_call['function'] and tool_call['function'].name,
              id = tool_call.id,
            }
          end

          -- Tool call arguments/parameters
          if tool_call['function'] and tool_call['function'].arguments then
            return {
              type = 'tool_call_delta',
              content = tool_call['function'].arguments,
            }
          end
        end
      end

      -- End of function call is determined by the finish_reason
      if response.choices[1].finish_reason == 'tool_calls' then
        return {
          type = 'tool_call_end',
        }
      end
    end,
  },
}
return options
