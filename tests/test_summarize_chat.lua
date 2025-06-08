local eq = MiniTest.expect.equality
local Messages = require('ai.utils.messages')
local Summarize = require('ai.tools.summarize_chat')

local T = MiniTest.new_set()

T['summarize_chat'] = MiniTest.new_set()

T['summarize_chat']['should summarize simple chat'] = function()
  local called = false
  local tool = Summarize.create_complete_task_tool({
    on_summarization = function(result)
      called = true
      -- Optionally, check result format here
    end,
  })
  local params = {
    chat_summary = '1. User asked about weather.\n2. Assistant replied sunny.\n3. User asked for milk reminder.\n4. Assistant set reminder.',
    relevant_context = 'No files referenced.',
    tasks = '- [x] Weather answered\n- [x] Reminder set',
  }
  tool.execute(params, function(result)
    -- This callback is not used by the tool, so nothing here
  end)
  assert(called)
end

return T

