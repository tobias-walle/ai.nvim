package.path = package.path .. ';./tests_api/?.lua'
local test_utils = require('test_utils')

return function()
  if
    not test_utils.check_env_vars(
      'Azure API',
      { 'AZURE_API_BASE', 'AZURE_API_VERSION', 'AZURE_API_KEY' }
    )
  then
    return
  end

  local ADAPTER_OPTIONS = require('ai.adapters.azure')

  test_utils.run_common_tests('Azure API', ADAPTER_OPTIONS)
end
