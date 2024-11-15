---@type AdapterOptions
local options =
  require('ai.adapters.utils.openai_like').create_adapter_options({
    name = 'openai',
    url = 'https://api.openai.com/v1/chat/completions',
    headers = {
      ['Authorization'] = 'Bearer ' .. os.getenv('OPENAI_API_KEY'),
    },
    default_model = 'gpt-4o',
  })

return options
