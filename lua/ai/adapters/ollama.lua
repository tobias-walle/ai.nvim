---@type AdapterOptions
local options =
  require('ai.adapters.utils.openai_like').create_adapter_options({
    name = 'ollama',
    url = 'http://localhost:11434/v1/chat/completions',
    headers = {},
    default_model = 'qwen2.5-coder:32b',
  })

return options
