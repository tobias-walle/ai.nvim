local M = {}

local Messages = require('ai.utils.messages')

local FINAL_QUESTION = 'Anything else?'

---@class ai.CompleteTaskTool.Result
---@field result "success" | "failure"
---@field summary string

---@class ai.CompleteTaskTool.Options
---@field on_completion fun(result: ai.CompleteTaskTool.Result)
---@field ask_user? fun(params: ai.AskTool.Params, callback: fun(answer: ai.AdapterMessageContent))

---@param opts ai.CompleteTaskTool.Options
---@return ai.ToolDefinition
function M.create_complete_task_tool(opts)
  local on_completion = opts.on_completion

  ---@type ai.ToolDefinition
  local tool = {
    definition = {
      name = 'task_complete',
      description = vim.trim([[
Mark the current task as completed. Do this after you finished all the required tasks, to give the control back to the user.
    ]]),
      parameters = {
        type = 'object',
        required = { 'result', 'summary' },
        properties = {
          result = {
            type = 'string',
            description = 'Indicates if the task was successful or failed',
            enum = { 'success', 'failure' },
          },
          summary = {
            type = 'string',
            description = 'Summary of the things you did for this task in markdown. If the task failed, provide a reason. Only use a list if multiple things were changed.',
          },
        },
      },
    },
    execute = function(params, callback)
      on_completion(params)
      if opts.ask_user then
        opts.ask_user({ question = FINAL_QUESTION }, function(answer)
          callback({ result = answer })
        end)
      end
    end,
    render = function(tool_call, tool_call_result)
      local params = tool_call.params or {}
      local result = {}

      if params.result == 'success' then
        table.insert(result, '✅ Task completed')
      elseif params.result == 'failure' then
        table.insert(result, '❌ Task failed')
      end

      if params.summary then
        table.insert(result, '')
        vim.list_extend(result, vim.split(params.summary, '\n'))
      end

      if tool_call_result and tool_call_result.result then
        vim.list_extend(result, {
          '',
          '> ' .. FINAL_QUESTION,
        })
        table.insert(result, '')
        vim.list_extend(
          result,
          vim.split(
            vim.trim(Messages.extract_text(tool_call_result.result)),
            '\n'
          )
        )
      end

      return result
    end,
  }
  return tool
end

return M
