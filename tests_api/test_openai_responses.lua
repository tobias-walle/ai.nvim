package.path = package.path .. ';./tests_api/?.lua'
local test_utils = require('test_utils')
local openai_like = require('ai.adapters.utils.openai_like')

return function()
  if
    not test_utils.check_env_vars('OpenAI Responses API', { 'OPENAI_API_KEY' })
  then
    return
  end

  local ADAPTER_OPTIONS = openai_like.create_adapter_options({
    name = 'OpenAI Responses API (GPT-5)',
    url = 'https://api.openai.com/v1/responses',
    headers = { ['Authorization'] = 'Bearer ' .. os.getenv('OPENAI_API_KEY') },
    default_model = 'gpt-5',
    api = 'responses',
    debug = os.getenv('DEBUG') == 'true',
  })

  test_utils.run_common_tests('OpenAI Responses API', ADAPTER_OPTIONS)
end
