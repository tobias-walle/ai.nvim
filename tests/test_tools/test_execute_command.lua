local eq = MiniTest.expect.equality
local T = MiniTest.new_set()

local ExecuteCommand = require('ai.tools.execute_command')

T['ExecuteCommand'] = MiniTest.new_set()

T['ExecuteCommand']['execute should deny command if user does not confirm'] = function()
  local tool = ExecuteCommand.create_execute_command_tool()
  local got_result = nil
  -- Patch vim.ui.input to simulate user denial
  vim.ui.input = function(opts, cb)
    cb('n')
  end
  tool.execute({ command = 'echo hi' }, function(result)
    got_result = result
  end)
  vim.wait(100, function()
    return got_result ~= nil
  end)
  local decoded = vim.json.decode(got_result.result)
  eq(
    decoded.error:match('denied'),
    'Command execution denied by user. Reason: n'
  )
end

T['ExecuteCommand']['render should show command and waiting if no result'] = function()
  local tool = ExecuteCommand.create_execute_command_tool()
  local tool_call = { params = { command = 'ls' } }
  local rendered = tool.render(tool_call)
  eq(rendered, {
    '`````bash',
    'ls',
    '`````',
    '',
    'Output:',
    '`````',
    '⏳ Waiting...',
    '`````',
  })
end

T['ExecuteCommand']['render should show output if result present'] = function()
  local tool = ExecuteCommand.create_execute_command_tool()
  local tool_call = { params = { command = 'echo hi' } }
  local tool_call_result =
    { result = vim.json.encode({ stdout = 'hi\n', stderr = '', code = 0 }) }
  local rendered = tool.render(tool_call, tool_call_result)
  eq(rendered, {
    '`````bash',
    'echo hi',
    '`````',
    '',
    'Output:',
    '`````',
    'hi',
    '`````',
  })
end

T['ExecuteCommand']['render should show error if result has error'] = function()
  local tool = ExecuteCommand.create_execute_command_tool()
  local tool_call = { params = { command = 'fail' } }
  local tool_call_result = { result = vim.json.encode({ error = 'fail' }) }
  local rendered = tool.render(tool_call, tool_call_result)
  eq(rendered, {
    '`````bash',
    'fail',
    '`````',
    '',
    'Output:',
    '`````',
    '❌ Error: fail',
    '`````',
  })
end

return T
