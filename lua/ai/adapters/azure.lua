local azureApiBase = os.getenv('AZURE_API_BASE')
local azureApiVersion = os.getenv('AZURE_API_VERSION')
local azureApiKey = os.getenv('AZURE_API_KEY')

---@type AdapterOptions
local options =
  require('ai.adapters.utils.openai_like').create_adapter_options({
    name = 'azure',
    url = azureApiBase
      .. '/openai/deployments/{{model}}/chat/completions?api-version='
      .. azureApiVersion,
    headers = {
      ['api-key'] = azureApiKey,
    },
    default_model = 'gpt-4o',
  })

return options
