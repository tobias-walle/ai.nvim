---@type ToolDefinition
local tool = {
  is_completing_chat = true,
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
    vim.notify('task_complete: ' .. vim.inspect(params))
    callback()
  end,
  render = function(tool_call)
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

    return result
  end,
}
return tool
