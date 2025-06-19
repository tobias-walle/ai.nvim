local M = {}

local Messages = require('ai.utils.messages')

---@class ai.Subtask
---@field id string
---@field description string
---@field completed? boolean

---@class ai.SubtaskCreateTool.Options
---@field get_subtasks fun(): ai.Subtask[]
---@field update_subtasks fun(subtasks: ai.Subtask[])

---@param opts ai.SubtaskCreateTool.Options
---@return ai.ToolDefinition
function M.create_tool(opts)
  ---@type ai.ToolDefinition
  local tool = {
    definition = {
      name = 'subtasks_create',
      description = vim.trim([[
Create one or more new subtasks. Use this for planning of multistep subtasks.
The tasks are shown to the user, so no need to repeat them before the tool call.
      ]]),
      parameters = {
        type = 'object',
        required = { 'subtasks' },
        properties = {
          subtasks = {
            type = 'array',
            description = 'A list of subtasks to create',
            items = {
              type = 'object',
              required = { 'id', 'description' },
              properties = {
                id = {
                  type = 'string',
                  description = 'A unique id of the subtask in snake case',
                  example = 'create-readme',
                },
                description = {
                  type = 'string',
                  description = 'The description of the subtask in a single sentence',
                  example = 'Create README.md file with a description of the project',
                },
              },
            },
          },
        },
      },
    },
    execute = function(params, callback)
      local subtasks = opts.get_subtasks()
      local new_subtasks = params.subtasks or {}
      for _, subtask in ipairs(new_subtasks) do
        subtask.completed = false
        table.insert(subtasks, subtask)
      end
      opts.update_subtasks(subtasks)
      callback({
        result = 'Subtasks created. All Subtasks:\n'
          .. table.concat(M.render_subtasks(subtasks), '\n'),
      })
    end,
    render = function(tool_call)
      local params = tool_call.params or {}
      local new_subtasks = params.subtasks or {}
      local all_subtasks = vim.deepcopy(opts.get_subtasks())
      local all_by_id = {}
      for _, subtask in ipairs(all_subtasks) do
        all_by_id[subtask.id] = true
      end
      local new_ids = {}
      for _, subtask in ipairs(new_subtasks) do
        if subtask.id then
          table.insert(new_ids, subtask.id)
        end
        if subtask.id and subtask.description and not all_by_id[subtask.id] then
          table.insert(all_subtasks, subtask)
        end
      end
      return M.render_subtasks(all_subtasks, new_ids)
    end,
  }
  return tool
end

---@param subtasks ai.Subtask[]
---@param new_ids? string[]
---@return string[] lines
function M.render_subtasks(subtasks, new_ids)
  local lines = {}
  local is_new = {}
  if new_ids then
    for _, id in ipairs(new_ids) do
      is_new[id] = true
    end
  end
  for _, subtask in ipairs(subtasks) do
    local check = subtask.completed and '[x]' or '[ ]'
    local line = '- ' .. check .. ' ' .. subtask.description
    if is_new[subtask.id] then
      line = line .. ' (NEW)'
    end
    table.insert(lines, line)
  end
  return lines
end

return M
