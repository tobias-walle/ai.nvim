local eq = MiniTest.expect.equality
local T = MiniTest.new_set()

local ExecuteCode = require('ai.tools.execute_code')

T['ExecuteCode'] = MiniTest.new_set()

T['ExecuteCode']['execute should run python code and return output'] = function()
  local tool = ExecuteCode.create_execute_code_tool()
  local got_result = nil
  tool.execute({ language = 'python', code = 'print(2+2)' }, function(result)
    got_result = result
  end)
  vim.wait(200, function()
    return got_result ~= nil
  end)
  local decoded = vim.json.decode(got_result.result)
  eq(decoded.stdout:match('4'), '4')
end

T['ExecuteCode']['execute should handle unsupported language'] = function()
  local tool = ExecuteCode.create_execute_code_tool()
  local got_result = nil
  tool.execute({ language = 'foo', code = 'bar' }, function(result)
    got_result = result
  end)
  vim.wait(100, function()
    return got_result ~= nil
  end)
  local decoded = vim.json.decode(got_result.result)
  assert(
    decoded.error:match('Unsupported language'),
    'Error message should mention unsupported language'
  )
end

T['ExecuteCode']['render should show code and output'] = function()
  local tool = ExecuteCode.create_execute_code_tool()
  local tool_call = { params = { language = 'python', code = 'print(42)' } }
  local tool_call_result =
    { result = vim.json.encode({ stdout = '42\n', stderr = '', code = 0 }) }
  local rendered = tool.render(tool_call, tool_call_result)
  eq(rendered, {
    '`````python',
    'print(42)',
    '`````',
    '',
    'Output:',
    '`````',
    '42',
    '`````',
  })
end

T['ExecuteCode']['render should show error'] = function()
  local tool = ExecuteCode.create_execute_code_tool()
  local tool_call =
    { params = { language = 'python', code = 'raise Exception()' } }
  local tool_call_result = { result = vim.json.encode({ error = 'fail' }) }
  local rendered = tool.render(tool_call, tool_call_result)
  eq(rendered, {
    '`````python',
    'raise Exception()',
    '`````',
    '',
    'Output:',
    '`````',
    '❌ Error: fail',
    '`````',
  })
end

T['ExecuteCode']['render should handle missing params gracefully'] = function()
  local tool = ExecuteCode.create_execute_code_tool()
  local tool_call = {}
  local rendered = tool.render(tool_call)
  eq(rendered, {
    '`````',
    '',
    '`````',
    '',
  })
end

return T
