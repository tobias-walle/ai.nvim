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
        return response.choices[1].delta.content
      end
    end,
  },
}
return options
