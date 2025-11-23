local azureApiBase = os.getenv('AZURE_API_BASE')
local azureApiKey = os.getenv('AZURE_API_KEY')

---@type AdapterOptions
local options =
  require('ai.adapters.utils.openai_like').create_adapter_options({
    name = 'azure',
    api = 'responses',
    url = azureApiBase .. '/openai/v1/responses?api-version=preview',
    headers = {
      ['api-key'] = azureApiKey,
    },
    default_model = 'gpt-5.1',
  })

return options
