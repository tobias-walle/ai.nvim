local eq = MiniTest.expect.equality
local T = MiniTest.new_set()

local CompleteTask = require('ai.tools.complete_task')

T['CompleteTask'] = MiniTest.new_set()

T['CompleteTask']['execute should call on_completion and ask_user if provided'] = function()
  local called_params = nil
  local called_ask = false
  local tool = CompleteTask.create_complete_task_tool({
    on_completion = function(params)
      called_params = params
    end,
    ask_user = function(params, callback)
      called_ask = true
      callback('done')
    end,
  })
  local got_result = nil
  tool.execute({ result = 'success', summary = 'All done' }, function(result)
    got_result = result
  end)
  eq(called_params.result, 'success')
  eq(called_params.summary, 'All done')
  eq(called_ask, true)
  eq(got_result.result, 'done')
end

T['CompleteTask']['render should show success and summary'] = function()
  local tool =
    CompleteTask.create_complete_task_tool({ on_completion = function() end })
  local tool_call = { params = { result = 'success', summary = 'Did it!' } }
  local rendered = tool.render(tool_call)
  eq(rendered, { '✅ Task completed', '', 'Did it!' })
end

T['CompleteTask']['render should show failure'] = function()
  local tool =
    CompleteTask.create_complete_task_tool({ on_completion = function() end })
  local tool_call = { params = { result = 'failure', summary = 'Failed.' } }
  local rendered = tool.render(tool_call)
  eq(rendered, { '❌ Task failed', '', 'Failed.' })
end

T['CompleteTask']['render should show final question and answer if ask_user present'] = function()
  local tool = CompleteTask.create_complete_task_tool({
    on_completion = function() end,
    ask_user = function() end,
  })
  local tool_call = { params = { result = 'success', summary = 'Done.' } }
  local tool_call_result = { result = 'No more.' }
  local rendered = tool.render(tool_call, tool_call_result)
  eq(
    rendered,
    { '✅ Task completed', '', 'Done.', '', 'Anything else?', '', 'No more.' }
  )
end

T['CompleteTask']['render should handle missing params gracefully'] = function()
  local tool =
    CompleteTask.create_complete_task_tool({ on_completion = function() end })
  local tool_call = {}
  local rendered = tool.render(tool_call)
  eq(rendered, {})
end

return T
