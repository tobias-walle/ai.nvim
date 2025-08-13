local M = {}

local suites = {}
local current_suite = nil

function M.begin_suite(name)
  current_suite = { name = name, tests = {}, passed = true }
  table.insert(suites, current_suite)
  print('\nRunning Suite: ' .. name)
end

-- Simple expect implementation
local function expect(actual)
  return {
    eq = function(expected)
      if actual ~= expected then
        error(
          string.format(
            'Expected %s, got %s',
            vim.inspect(expected),
            vim.inspect(actual)
          )
        )
      end
    end,
    to_be_truthy = function()
      if not actual then
        error(string.format('Expected truthy, got %s', vim.inspect(actual)))
      end
    end,
    to_be_nil = function()
      if actual ~= nil then
        error(string.format('Expected nil, got %s', vim.inspect(actual)))
      end
    end,
    to_be_greater_than = function(val)
      if not (type(actual) == 'number' and actual > val) then
        error(string.format('Expected > %s, got %s', val, vim.inspect(actual)))
      end
    end,
    to_contain = function(substr)
      if not string.find(tostring(actual), substr, 1, true) then
        error(
          string.format("Expected to contain '%s', got '%s'", substr, actual)
        )
      end
    end,
    to_not_eq = function(val)
      if actual == val then
        error(
          string.format(
            'Expected not %s, got %s',
            vim.inspect(val),
            vim.inspect(actual)
          )
        )
      end
    end,
    to_be_empty = function()
      if type(actual) == 'string' and #actual > 0 then
        error(string.format("Expected empty string, got '%s'", actual))
      end
      if type(actual) == 'table' and not vim.tbl_isempty(actual) then
        error('Expected empty table')
      end
    end,
  }
end

M.expect = expect

---@param adapter_options table
---@param request_params table
---@return table
function M.run_adapter_test_case(adapter_options, request_params)
  local Adapter = require('ai.adapters').Adapter

  -- Create a Config mock if it's missing
  if not vim.g._ai_config then
    require('ai.config').set(require('ai.config').default_config)
  end

  local adapter = Adapter:new(adapter_options)

  local done = false
  local full_response = ''
  local raw_output_buffer = {}
  local exit_code = -1
  local tokens = nil
  local tool_calls = nil
  local err_msg = nil

  local ok, err = pcall(function()
    adapter:chat_stream({
      messages = request_params.messages,
      system_prompt = request_params.system_prompt,
      tools = request_params.tools,
      reasoning_effort = request_params.reasoning_effort,
      on_update = function(data)
        table.insert(raw_output_buffer, data.delta)
        if os.getenv('DEBUG') == 'true' then
          io.write(data.delta)
          io.flush()
        end
      end,
      on_exit = function(data)
        full_response = data.response
        exit_code = data.exit_code
        tokens = data.tokens
        tool_calls = data.tool_calls
        done = true
      end,
      on_error = function(error)
        err_msg = error
        done = true
      end,
    })
  end)

  if not ok then
    err_msg = 'Failed to start adapter stream: ' .. tostring(err)
    return {
      success = false,
      exit_code = -1,
      response = '',
      tokens = nil,
      tool_calls = nil,
      error = err_msg,
      raw_output = table.concat(raw_output_buffer),
    }
  end

  local max_wait = 1000000
  while not done and max_wait > 0 do
    vim.wait(10)
    max_wait = max_wait - 10
  end

  if not done then
    err_msg = err_msg or '[TIMEOUT] Test timed out.'
  end

  local success = exit_code == 0 and not err_msg

  return {
    success = success,
    exit_code = exit_code,
    response = full_response,
    tokens = tokens,
    tool_calls = tool_calls,
    error = err_msg,
    raw_output = table.concat(raw_output_buffer),
  }
end

function M.run_test(name, adapter_options, request_params, assertion_fn)
  if not current_suite then
    M.begin_suite('Default Suite')
  end

  print('  Running ' .. name .. '... ')

  local result = M.run_adapter_test_case(adapter_options, request_params)
  local ok, err = pcall(assertion_fn, result)

  local status = 'pass'
  local error_detail = nil

  if ok then
    print('  PASSED')
  else
    status = 'fail'
    current_suite.passed = false
    print('  FAILED')
    -- print("    Assertion failed: " .. tostring(err))

    error_detail = 'Assertion failed: ' .. tostring(err) .. '\n'

    if result.error then
      if type(result.error) == 'string' then
        error_detail = error_detail .. 'Error:\n' .. result.error .. '\n'
      else
        error_detail = error_detail
          .. 'Error: '
          .. vim.inspect(result.error)
          .. '\n'
      end
    end
    if result.exit_code ~= 0 then
      error_detail = error_detail .. 'Exit Code: ' .. result.exit_code .. '\n'
    end
    -- Only show raw output if it helps debugging failures
    if result.raw_output and result.raw_output ~= '' then
      error_detail = error_detail
        .. 'Raw Output (Preview): '
        .. string.sub(result.raw_output, 1, 200)
        .. '...\n'
    end

    -- Print immediately for debugging
    print('    ' .. error_detail:gsub('\n', '\n    '))
  end

  table.insert(
    current_suite.tests,
    { name = name, status = status, error = error_detail }
  )
end

function M.fail_test(name, message)
  if not current_suite then
    M.begin_suite('Default Suite')
  end

  print('  Running ' .. name .. '... ')
  print('  FAILED')

  if message then
    print('    ' .. message)
  end

  current_suite.passed = false
  table.insert(
    current_suite.tests,
    { name = name, status = 'fail', error = message }
  )
end

function M.check_env_vars(suite_name, vars)
  local missing = {}
  for _, var in ipairs(vars) do
    if not os.getenv(var) then
      table.insert(missing, var)
    end
  end

  if #missing > 0 then
    M.begin_suite(suite_name)
    M.fail_test(
      'Env Variables',
      'Missing required environment variables: ' .. table.concat(missing, ', ')
    )
    return false
  end

  return true
end

function M.run_common_tests(adapter_name, adapter_options)
  local default_request = {
    messages = { { role = 'user', content = 'Say hello.' } },
    system_prompt = 'You are a helpful AI assistant. Always respond in a friendly tone.',
    temperature = 0.5,
    max_tokens = 50,
  }

  local MOCK_TOOL = {
    name = 'echo',
    description = 'Echoes the input back.',
    parameters = {
      type = 'object',
      properties = {
        text = { type = 'string', description = 'The text to echo' },
      },
      required = { 'text' },
    },
  }

  M.begin_suite(adapter_name)

  M.run_test('Basic Chat', adapter_options, default_request, function(result)
    expect(result.success).eq(true)
    expect(result.response).to_be_truthy()
    expect(result.tokens).to_be_truthy()
    expect(result.tokens.input).to_be_greater_than(0)
    expect(result.tokens.output).to_be_greater_than(0)
    expect(result.error).to_be_nil()
  end)

  local tool_request = vim.tbl_extend('force', default_request, {
    messages = { { role = 'user', content = 'Echo "Hello Tool!"' } },
    tools = { MOCK_TOOL },
  })

  M.run_test('Tool Call', adapter_options, tool_request, function(result)
    expect(result.success).eq(true)
    expect(result.response).to_be_truthy()
    expect(result.tokens).to_be_truthy()
    expect(result.tokens.input).to_be_greater_than(0)
    expect(result.tokens.output).to_be_greater_than(0)
    expect(result.error).to_be_nil()

    -- Verify tool calls
    if not result.tool_calls or #result.tool_calls == 0 then
      error('Expected tool_calls in result')
    end
    local tool_call = result.tool_calls[1]
    if tool_call.tool ~= 'echo' then
      error("Expected tool 'echo', got " .. tostring(tool_call.tool))
    end
  end)
end

function M.print_summary()
  print('\n' .. string.rep('=', 50))
  print('TEST SUMMARY')
  print(string.rep('=', 50))

  local any_failed = false

  if #suites == 0 then
    print('No tests ran (check environment variables)')
    return
  end

  for _, suite in ipairs(suites) do
    local suite_icon = suite.passed and 'PASS' or 'FAIL'
    local suite_line = string.format('%s %s: ', suite_icon, suite.name)

    local test_parts = {}
    for _, test in ipairs(suite.tests) do
      local test_icon = (test.status == 'pass') and '✓' or 'x'
      table.insert(test_parts, string.format('%s %s', test_icon, test.name))
    end

    print(suite_line .. table.concat(test_parts, ', '))

    if not suite.passed then
      any_failed = true
    end
  end
  print(string.rep('=', 50))

  if any_failed then
    os.exit(1)
  else
    os.exit(0)
  end
end

return M
