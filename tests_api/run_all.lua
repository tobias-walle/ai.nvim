package.path = package.path .. ";./tests_api/?.lua;./lua/?.lua;./lua/?/init.lua"
local test_utils = require('test_utils')

print("Running API Integration Tests...")

-- Dynamically discover test suites
local suites = {}
local suite_files = vim.fn.glob('tests_api/test_*.lua', false, true)

for _, file in ipairs(suite_files) do
    local module_name = vim.fn.fnamemodify(file, ":t:r")
    if module_name ~= 'test_utils' then
        local name = module_name:gsub("^test_", "")
        table.insert(suites, { name = name, module = module_name })
    end
end
table.sort(suites, function(a, b) return a.name < b.name end)

-- Parse arguments
local only_filter = nil
if arg then
    for i, v in ipairs(arg) do
        if v == '--only' then
            only_filter = arg[i+1]
        else
            local match = v:match('^--only=(.*)')
            if match then only_filter = match end
        end
    end
end

-- Determine which suites to run
local modules_to_run = {}

if only_filter then
    for _, name in ipairs(vim.split(only_filter, ',')) do
        name = vim.trim(name)
        local found = false
        for _, suite in ipairs(suites) do
            if suite.name == name then
                table.insert(modules_to_run, require(suite.module))
                found = true
                break
            end
        end
        if not found then
            print("Warning: Unknown suite '" .. name .. "'")
        end
    end
else
    for _, suite in ipairs(suites) do
        table.insert(modules_to_run, require(suite.module))
    end
end

for _, run_suite in ipairs(modules_to_run) do
    run_suite()
end

test_utils.print_summary()
