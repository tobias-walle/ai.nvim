package.path = package.path .. ';./tests_api/?.lua'
local test_utils = require('test_utils')

return function()
  -- Ollama usually runs locally, so we don't strictly need an env var to authenticate.
  -- However, to avoid running this in CI/environments without Ollama, we check for OLLAMA_API_BASE.
  -- If set, we use it. If not, we skip.
  if not os.getenv('OLLAMA_API_BASE') then
    -- Optionally we could default to skipping or trying localhost.
    -- Given the user said "some will fail is fine", we could try localhost if no env var?
    -- But consistent behavior (skip if not configured) is usually better for test suites.
    test_utils.begin_suite('Ollama API')
    test_utils.fail_test(
      'Env Variables',
      'OLLAMA_API_BASE not set (e.g. http://localhost:11434)'
    )
    return
  end

  local ADAPTER_OPTIONS = require('ai.adapters.ollama')

  -- Override URL if specified in env var
  local env_url = os.getenv('OLLAMA_API_BASE')
  if env_url then
    -- Append chat completions endpoint if not present
    if not string.find(env_url, '/chat/completions') then
      ADAPTER_OPTIONS.url = env_url .. '/v1/chat/completions'
    else
      ADAPTER_OPTIONS.url = env_url
    end
  end

  test_utils.run_common_tests('Ollama API', ADAPTER_OPTIONS)
end
