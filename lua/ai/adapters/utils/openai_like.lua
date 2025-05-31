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

---@class OpenAiLikeAdapterOptions
---@field name string
---@field url string
---@field headers table<string, string>
---@field default_model string
---@field pricing_per_model? table<string, AdapterPricing>

---@params OpenAiLikeAdapterOptions options
---@return AdapterOptions
function M.create_adapter_options(options)
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
          table.insert(messages, message)
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
    },
  }
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

return M
