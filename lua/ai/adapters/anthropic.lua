---@param tools Tool[]|nil
---@return Tool[]|nil
local function map_tools(tools)
  if not tools then
    return nil
  end
  local mapped_tools = {}
  for _, tool in ipairs(tools) do
    table.insert(mapped_tools, {
      name = tool.name,
      description = tool.description,
      input_schema = tool.parameters,
    })
  end
  return mapped_tools
end

---@type AdapterOptions
local options = {
  name = 'anthropic',
  url = 'https://api.anthropic.com/v1/messages',
  headers = {
    ['x-api-key'] = os.getenv('ANTHROPIC_API_KEY'),
    ['anthropic-version'] = '2023-06-01',
  },
  -- default_model = 'claude-3-5-sonnet-20241022',
  default_model = 'claude-3-5-haiku-20241022',
  handlers = {
    create_request_body = function(request)
      local messages = {}
      for _, msg in ipairs(request.messages) do
        local content = {}
        if msg.content and #msg.content > 0 then
          table.insert(content, { type = 'text', text = msg.content })
        end
        if msg.tool_calls then
          for _, tool_call in ipairs(msg.tool_calls) do
            table.insert(content, {
              type = 'tool_use',
              id = tool_call.id,
              name = tool_call.tool,
              input = tool_call.params,
            })
          end
        end
        table.insert(messages, {
          role = msg.role,
          content = content,
        })

        if msg.tool_call_results and #msg.tool_call_results > 0 then
          local tool_call_result_content = {}
          for _, tool_call_result in ipairs(msg.tool_call_results) do
            table.insert(tool_call_result_content, {
              type = 'tool_result',
              tool_use_id = tool_call_result.id,
              content = vim.fn.json_encode(tool_call_result.result),
            })
          end
          table.insert(messages, {
            role = 'user',
            content = tool_call_result_content,
          })
        end
      end

      return {
        stream = true,
        model = request.model,
        system = request.system_prompt,
        max_tokens = request.max_tokens or 4000,
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
      local success, json = pcall(vim.json.decode, data)
      if success then
        return json
      else
        return data
      end
    end,
    is_done = function(response)
      return response.type == 'message_stop'
    end,
    get_tokens = function(response)
      if response.type == 'message_start' then
        local usage = response.message.usage
        return {
          input = usage.input_tokens or 0,
          output = usage.output_tokens or 0,
        }
      end
      if response.type == 'message_delta' then
        return {
          output = response.usage.output_tokens or 0,
        }
      end
    end,
    get_delta = function(response)
      if
        response.type == 'content_block_delta'
        and response.delta.type == 'text_delta'
      then
        return { type = 'message', content = response.delta.text }
      end

      if
        response.type == 'content_block_start'
        and response.content_block.type == 'tool_use'
      then
        return {
          type = 'tool_call_start',
          tool = response.content_block.name,
          id = response.content_block.id,
        }
      end

      if
        response.type == 'content_block_delta'
        and response.delta.type == 'input_json_delta'
      then
        return {
          type = 'tool_call_delta',
          content = response.delta.partial_json,
        }
      end

      if
        response.type == 'content_block_delta'
        and response.delta.type == 'input_json_delta'
      then
        return {
          type = 'tool_call_delta',
          content = response.delta.partial_json,
        }
      end

      if
        response.type == 'message_delta'
        and response.delta.stop_reason == 'tool_use'
      then
        return {
          type = 'tool_call_end',
        }
      end
    end,
  },
}
return options
