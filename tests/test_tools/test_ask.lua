local eq = MiniTest.expect.equality
local T = MiniTest.new_set()

local AskTool = require('ai.tools.ask')

T['AskTool'] = MiniTest.new_set()

T['AskTool']['execute should call ask_user and return answer'] = function()
  --- @type ai.AskTool.Params
  local called_params = nil
  local tool = AskTool.create_ask_tool({
    ask_user = function(params, callback)
      called_params = params
      callback('my answer')
    end,
  })
  --- @type ai.ToolDefinition.ExcutionResult
  local got_result = nil
  tool.execute({ question = 'What?' }, function(result)
    got_result = result
  end)
  eq(called_params.question, 'What?')
  eq(got_result.result, 'my answer')
end

T['AskTool']['execute should pass choices to ask_user'] = function()
  --- @type ai.AskTool.Params
  local called_params = nil
  local tool = AskTool.create_ask_tool({
    ask_user = function(params, callback)
      called_params = params
      callback('chosen')
    end,
  })
  tool.execute(
    { question = 'Pick one', choices = { 'a', 'b' } },
    function() end
  )
  eq(called_params.choices, { 'a', 'b' })
end

T['AskTool']['render should show question and choices'] = function()
  local tool = AskTool.create_ask_tool({ ask_user = function() end })
  local tool_call = {
    params = {
      question = 'Favorite color?',
      choices = { 'Red', 'Blue' },
    },
  }
  local rendered = tool.render(tool_call)
  eq(rendered, {
    '> Favorite color?',
    '> \\1 Red',
    '> \\2 Blue',
  })
end

T['AskTool']['render should show answer if present'] = function()
  local tool = AskTool.create_ask_tool({ ask_user = function() end })
  local tool_call = {
    params = { question = '2+2?' },
  }
  local tool_call_result = { result = '4' }
  local rendered = tool.render(tool_call, tool_call_result)
  eq(rendered, {
    '> 2+2?',
    '',
    '4',
    '',
    '---',
  })
end

T['AskTool']['render should handle missing params gracefully'] = function()
  local tool = AskTool.create_ask_tool({ ask_user = function() end })
  local tool_call = {}
  local rendered = tool.render(tool_call)
  eq(rendered, {
    '> ',
  })
end

return T
