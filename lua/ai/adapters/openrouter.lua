---@type AdapterOptions
local options =
  require('ai.adapters.utils.openai_like').create_adapter_options({
    name = 'openrouter',
    url = 'https://openrouter.ai/api/v1/chat/completions',
    headers = {
      ['Authorization'] = 'Bearer ' .. os.getenv('OPENROUTER_API_KEY'),
    },
    default_model = 'deepseek/deepseek-chat',
  })

return options
