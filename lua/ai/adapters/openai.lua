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
  url = 'https://api.openai.com',
  headers = {
    ['Authorization'] = 'Bearer ' .. os.getenv('OPENAI_API_KEY'),
  },
  default_model = 'gpt-4o',
  handlers = {
    create_request_body = function(request)
      return {
        stream = true,
        model = request.model,
        max_tokens = request.max_tokens,
        temperature = request.temperature,
        tools = map_tools(request.tools),
        messages = {
          { role = 'system', content = request.system_prompt },
          unpack(request.messages),
        },
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
      return response:match('^%s*%[DONE%]%s*$')
    end,
    get_tokens = function(response)
      if response.usage then
        return response.usage.total_tokens
      end
    end,
    get_delta = function(response)
      if response.choices and response.choices[1] then
        return { type = 'message', content = response.choices[1].delta.content }
      end
    end,
  },
}
return options
