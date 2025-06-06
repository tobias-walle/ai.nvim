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

local function get_cache_control_for_big_text(content)
  return #content > 5000 and { type = 'ephemeral' } or nil
end

---@param item AdapterMessageContentItem
local function map_message_content_item(item)
  if item['type'] == 'text' then
    return {
      type = 'text',
      text = item.text,
      cache_control = get_cache_control_for_big_text(item.text),
    }
  elseif item['type'] == 'image' then
    return {
      type = 'image',
      source = {
        type = 'base64',
        media_type = item.media_type,
        data = item.base64,
      },
    }
  end
  return item
end

---@param content ai.AdapterMessageContent
local function map_message_content(content)
  if type(content) == 'string' then
    return {
      map_message_content_item({ type = 'text', text = content }),
    }
  else
    return vim.iter(content):map(map_message_content_item):totable()
  end
end

---@type AdapterOptions
local options = {
  name = 'anthropic',
  url = 'https://api.anthropic.com/v1/messages',
  headers = {
    ['x-api-key'] = os.getenv('ANTHROPIC_API_KEY'),
    ['anthropic-version'] = '2023-06-01',
    ['anthropic-beta'] = 'prompt-caching-2024-07-31',
  },
  default_model = 'claude-3-7-sonnet-latest',
  handlers = {
    create_request_body = function(request)
      local messages = {}

      for _, msg in ipairs(request.messages) do
        local content = {}
        if msg.content and #msg.content > 0 then
          vim.list_extend(content, map_message_content(msg.content))
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
              content = vim.json.encode(tool_call_result.result),
              cache_control = get_cache_control_for_big_text(content),
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
        system = request.system_prompt and {
          {
            type = 'text',
            text = request.system_prompt,
            cache_control = get_cache_control_for_big_text(
              request.system_prompt
            ),
          },
        } or nil,
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
      return response.type == 'message_stop'
    end,
    get_tokens = function(response)
      if response.type == 'message_start' then
        local usage = response.message.usage
        return {
          input = usage.input_tokens or 0,
          input_cached = usage.cache_read_input_tokens or 0,
          output = usage.output_tokens or 0,
        }
      end
      if response.type == 'message_delta' then
        return {
          output = response.usage.output_tokens or 0,
        }
      end
    end,
    get_error = function(response)
      if response.error then
        return 'Error: ' .. vim.inspect(response.error)
      end
      return nil
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
