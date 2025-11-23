package.path = package.path .. ";./tests_api/?.lua"
local test_utils = require('test_utils')

print("Running API Integration Tests...")

local suites = {
    require('test_anthropic'),
    require('test_azure'),
    require('test_ollama'),
    require('test_openai'),
    require('test_openai_responses'),
    require('test_openrouter')
}

for _, run_suite in ipairs(suites) do
    run_suite()
end

test_utils.print_summary()
