package.path = package.path .. ';./tests_api/?.lua'
local test_utils = require('test_utils')

return function()
  if not test_utils.check_env_vars('OpenAI API', { 'OPENAI_API_KEY' }) then
    return
  end

  local ADAPTER_OPTIONS = require('ai.adapters.openai')

  test_utils.run_common_tests('OpenAI API', ADAPTER_OPTIONS)
end
