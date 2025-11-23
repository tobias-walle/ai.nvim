local M = {}

---@param tools Tool[]|nil
---@return Tool[]|nil
function M.map_tools(tools)
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

---@param tools Tool[]|nil
---@return Tool[]|nil
function M.map_tools_responses(tools)
  if not tools then
    return nil
  end
  local mapped_tools = {}
  for _, tool in ipairs(tools) do
    table.insert(mapped_tools, {
      type = 'function',
      name = tool.name,
      description = tool.description,
      parameters = tool.parameters,
    })
  end
  return mapped_tools
end

---@param content ai.AdapterMessageContent
function M.map_message_content(content)
  if type(content) == 'string' then
    return content
  else
    return vim.iter(content):map(M.map_message_content_item):totable()
  end
end

---@param item AdapterMessageContentItem
function M.map_message_content_item(item)
  if item['type'] == 'text' then
    return {
      type = 'text',
      text = item.text,
    }
  elseif item['type'] == 'image' then
    return {
      type = 'image_url',
      image_url = {
        url = 'data:' .. item.media_type .. ';base64,' .. item.base64,
      },
    }
  end
  return item
end

---@param content ai.AdapterMessageContent
---@param role? string
function M.map_message_content_responses(content, role)
  local text_type = 'input_text'
  if role == 'assistant' or role == 'tool' then
    text_type = 'output_text'
  end

  if type(content) == 'string' then
    return {
      {
        type = text_type,
        text = content,
      },
    }
  else
    return vim
      .iter(content)
      :map(function(item)
        return M.map_message_content_item_responses(item, role)
      end)
      :totable()
  end
end

---@param item AdapterMessageContentItem
---@param role? string
function M.map_message_content_item_responses(item, role)
  local text_type = 'input_text'
  if role == 'assistant' or role == 'tool' then
    text_type = 'output_text'
  end

  if item['type'] == 'text' then
    return {
      type = text_type,
      text = item.text,
    }
  elseif item['type'] == 'image' then
    return {
      type = 'input_image',
      image_url = {
        url = 'data:' .. item.media_type .. ';base64,' .. item.base64,
      },
    }
  end
  return item
end

---@param options OpenAiLikeAdapterOptions
local function create_chat_handlers(options)
  return {
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
          message.content = M.map_message_content(msg.content)
        end
        if msg.tool_calls and #msg.tool_calls > 0 then
          message.tool_calls = {}
          for _, tool_call in ipairs(msg.tool_calls) do
            table.insert(message.tool_calls, {
              id = tool_call.id,
              type = 'function',
              ['function'] = {
                name = tool_call.tool,
                arguments = vim.json.encode(tool_call.params),
              },
              strict = true,
            })
          end
        end
        if msg.role ~= 'tool' then
          table.insert(messages, message)
        end
        if msg.tool_call_results and #msg.tool_call_results > 0 then
          for _, tool_call in ipairs(msg.tool_call_results) do
            table.insert(messages, {
              role = 'tool',
              tool_call_id = tool_call.id,
              content = tool_call.result
                and M.map_message_content(tool_call.result),
            })
          end
        end
      end

      return {
        stream = true,
        stream_options = {
          include_usage = true,
        },
        model = request.model,
        max_tokens = request.max_tokens,
        temperature = request.temperature,
        tools = request.tools and #request.tools > 0 and M.map_tools(
          request.tools
        ) or nil,
        messages = messages,
        prediction = request.prediction,
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
          input_cached = response.usage.prompt_tokens_details
              and response.usage.prompt_tokens_details.cached_tokens
            or 0,
          accepted_prediction_tokens = response.usage.completion_tokens_details
              and response.usage.completion_tokens_details.accepted_prediction_tokens
            or 0,
          reasoning_tokens = response.usage.completion_tokens_details
              and response.usage.completion_tokens_details.reasoning_tokens
            or 0,
        }
      end
    end,
    get_error = function(response)
      if response.error then
        return 'Error: ' .. vim.inspect(response.error)
      end
      if
        response
        and response.choices
        and response.choices[1]
        and response.choices[1].finish_reason == 'error'
      then
        return 'Error: '
          .. (response.choices[1].native_finish_reason or '<unknown reason>')
      else
        return nil
      end
    end,
    get_delta = function(response)
      if not (response.choices and response.choices[1]) then
        return nil
      end
      local delta = response.choices[1].delta

      -- Handle regular message content
      if delta and delta.content then
        return { type = 'message', content = delta.content }
      end

      -- Handle function calls
      if delta and delta.tool_calls then
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
  }
end

---@param options OpenAiLikeAdapterOptions
local function create_responses_handlers(options)
  local current_event_type = nil

  return {
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
          message.content = M.map_message_content_responses(
            msg.content,
            msg.role
          )
        elseif msg.role == 'assistant' then
          message.content = M.map_message_content_responses('', msg.role)
        end
        if msg.tool_calls and #msg.tool_calls > 0 and msg.role ~= 'assistant' then
          message.tool_calls = {}
          for _, tool_call in ipairs(msg.tool_calls) do
            table.insert(message.tool_calls, {
              id = tool_call.id,
              type = 'function',
              ['function'] = {
                name = tool_call.tool,
                arguments = vim.json.encode(tool_call.params),
              },
              strict = true,
            })
          end
        end
        if msg.role ~= 'tool' then
          table.insert(messages, message)
        end
      end

      return {
        stream = true,
        model = request.model,
        input = messages,
        tools = request.tools and #request.tools > 0 and M.map_tools_responses(
          request.tools
        ) or nil,
        reasoning = request.reasoning_effort and {
          effort = request.reasoning_effort,
        } or nil,
      }
    end,
    parse_response = function(chunk)
      local event = chunk:match('^event: (.+)')
      if event then
        if options.debug then
          vim.notify('DEBUG EVENT: ' .. vim.trim(event))
        end
        current_event_type = vim.trim(event)
        return nil
      end

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
        json._event_type = current_event_type
        if options.debug and current_event_type == 'response.completed' then
          vim.notify('DEBUG COMPLETED JSON: ' .. vim.inspect(json))
        end
        return json
      else
        return data
      end
    end,
    is_done = function(response)
      return response._event_type == 'response.completed'
    end,
    get_tokens = function(response)
      if response._event_type == 'response.completed' then
        local usage = response.usage
          or (response.response and response.response.usage)
        if usage then
          return {
            input = usage.input_tokens or usage.prompt_tokens or 0,
            output = usage.output_tokens or usage.completion_tokens or 0,
            input_cached = usage.input_tokens_details
                and usage.input_tokens_details.cached_tokens
              or 0,
            accepted_prediction_tokens = usage.output_tokens_details
                and usage.output_tokens_details.accepted_prediction_tokens
              or 0,
            reasoning_tokens = usage.output_tokens_details
                and usage.output_tokens_details.reasoning_tokens
              or 0,
          }
        end
      end
      return nil
    end,
    get_error = function(response)
      if response.error then
        return 'Error: ' .. vim.inspect(response.error)
      end
      return nil
    end,
    get_delta = function(response)
      if response._event_type == 'response.output_text.delta' then
        return {
          type = 'message',
          content = response.delta or '',
        }
      elseif response._event_type == 'response.output_item.added' then
        if
          response.item
          and response.item.type == 'function_call'
          and response.item.name
        then
          return {
            type = 'tool_call_start',
            tool = response.item.name,
            id = response.item.call_id,
          }
        end
      elseif
        response._event_type == 'response.function_call_arguments.delta'
      then
        return {
          type = 'tool_call_delta',
          content = response.delta
            or response.function_call_arguments_delta
            or '',
        }
      elseif response._event_type == 'response.output_item.done' then
        if
          response.item
          and response.item.type == 'function_call'
          and response.item.status == 'completed'
        then
          return {
            type = 'tool_call_end',
          }
        end
      end
      return nil
    end,
  }
end

---@class OpenAiLikeAdapterOptions
---@field name string
---@field url string
---@field api? "chat" | "responses"
---@field debug? boolean
---@field headers table<string, string>
---@field default_model string
---@field pricing_per_model? table<string, AdapterPricing>

---@params OpenAiLikeAdapterOptions options
---@return AdapterOptions
function M.create_adapter_options(options)
  local handlers
  if options.api == 'responses' then
    handlers = create_responses_handlers(options)
  else
    handlers = create_chat_handlers(options)
  end

  ---@type AdapterOptions
  return {
    name = options.name,
    url = options.url,
    headers = vim.tbl_extend('force', {
      ['HTTP-Referer'] = 'https://github.com/tobias-walle/ai.nvim',
      ['X-Title'] = 'ai.nvim',
    }, options.headers),
    default_model = options.default_model,
    pricing_per_model = vim.tbl_extend('force', {
      ['gpt-5'] = {
        input_per_million = 1.25,
        output_per_million = 10.00,
        cache_read_per_million = 0.125,
        cache_write_per_million = 0.00,
      },
      ['gpt-5-mini'] = {
        input_per_million = 0.25,
        output_per_million = 2.00,
        cache_read_per_million = 0.025,
        cache_write_per_million = 0.00,
      },
      ['gpt-5-nano'] = {
        input_per_million = 0.05,
        output_per_million = 0.40,
        cache_read_per_million = 0.005,
        cache_write_per_million = 0.00,
      },
      ['gpt-4.1'] = {
        input_per_million = 2.00,
        output_per_million = 8.00,
        cache_read_per_million = 0.50,
        cache_write_per_million = 0.00,
      },
      ['gpt-4.1-mini'] = {
        input_per_million = 0.40,
        output_per_million = 1.60,
        cache_read_per_million = 0.10,
        cache_write_per_million = 0.00,
      },
      ['gpt-4.1-nano'] = {
        input_per_million = 0.10,
        output_per_million = 0.40,
        cache_read_per_million = 0.025,
        cache_write_per_million = 0.00,
      },
      ['gpt-4o'] = {
        input_per_million = 2.50,
        output_per_million = 10.00,
        cache_read_per_million = 0.00,
        cache_write_per_million = 0.00,
      },
      ['gpt-4o-mini'] = {
        input_per_million = 0.15,
        output_per_million = 0.60,
        cache_read_per_million = 0.00,
        cache_write_per_million = 0.00,
      },
      ['o3-mini'] = {
        input_per_million = 1.10,
        output_per_million = 4.40,
        cache_read_per_million = 0.00,
        cache_write_per_million = 0.00,
      },
      ['o4-mini'] = {
        input_per_million = 1.10,
        output_per_million = 4.40,
        cache_read_per_million = 0.275,
        cache_write_per_million = 0.00,
      },
      ['o3'] = {
        input_per_million = 10.00,
        output_per_million = 40.00,
        cache_read_per_million = 2.50,
        cache_write_per_million = 0.00,
      },
    }, options.pricing_per_model or {}),
    handlers = handlers,
  }
end

return M
