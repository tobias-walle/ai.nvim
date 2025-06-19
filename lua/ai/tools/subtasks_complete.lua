local M = {}

local Messages = require('ai.utils.messages')

---@class ai.SubtaskCompleteTool.Result
---@field id string

---@class ai.SubtaskCompleteTool.Options
---@field get_subtasks fun(): ai.Subtask[]
---@field update_subtasks fun(subtasks: ai.Subtask[])

---@param opts ai.SubtaskCompleteTool.Options
---@return ai.ToolDefinition
function M.create_tool(opts)
  ---@type ai.ToolDefinition
  local tool = {
    definition = {
      name = 'subtasks_complete',
      description = vim.trim(
        [[Complete one or more given subtasks. Always use this tool after finishing a subsubtask.]]
      ),
      parameters = {
        type = 'object',
        required = { 'ids' },
        properties = {
          ids = {
            type = 'array',
            items = { type = 'string' },
            description = 'The ids of the subtasks to complete. You defined the id in the subtasks_create tool.',
            example = { 'create-readme', 'write-tests' },
          },
        },
      },
    },
    execute = function(params, callback)
      ---@type ai.Subtask[]
      local subtasks = opts.get_subtasks()
      local updated = {}
      local not_found = {}
      for _, id in ipairs(params.ids) do
        local found = false
        for _, t in ipairs(subtasks) do
          if t.id == id then
            t.completed = true
            found = true
            table.insert(updated, id)
            break
          end
        end
        if not found then
          table.insert(not_found, id)
        end
      end
      opts.update_subtasks(subtasks)
      local result = 'Updated Subtasks:\n'
        .. table.concat(
          require('ai.tools.subtask_create').render_subtasks(subtasks),
          '\n'
        )
      if #not_found > 0 then
        result = result
          .. '\nSubtasks not found: '
          .. table.concat(not_found, ', ')
      end
      callback({ result = result })
    end,
    render = function()
      local subtasks = opts.get_subtasks()
      return require('ai.tools.subtask_create').render_subtasks(subtasks)
    end,
  }
  return tool
end

return M
