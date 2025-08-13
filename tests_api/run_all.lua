package.path = package.path .. ";./tests_api/?.lua"
local test_utils = require('test_utils')

print("Running API Integration Tests...")

local suites = {
    require('test_azure'),
    require('test_openai_responses')
}

for _, run_suite in ipairs(suites) do
    run_suite()
end

test_utils.print_summary()
