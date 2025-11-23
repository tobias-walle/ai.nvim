package.path = package.path .. ';./tests_api/?.lua'
local test_utils = require('test_utils')

return function()
  if
    not test_utils.check_env_vars('OpenRouter API', { 'OPENROUTER_API_KEY' })
  then
    return
  end

  local ADAPTER_OPTIONS = require('ai.adapters.openrouter')

  test_utils.run_common_tests('OpenRouter API', ADAPTER_OPTIONS)
end
