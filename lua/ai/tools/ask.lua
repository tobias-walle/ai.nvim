local M = {}

local Messages = require('ai.utils.messages')

---@class ai.AskTool.Params
---@field question string
---@field choices? string[]

---@class ai.AskTool.Options
---@field ask_user fun(params: ai.AskTool.Params, callback: fun(answer: string))

---@param opts ai.AskTool.Options
---@return ai.ToolDefinition
function M.create_ask_tool(opts)
  ---@type ai.ToolDefinition
  local tool = {
    definition = {
      name = 'ask',
      description = vim.trim([[
Ask the user a question. He will see a popup in which he can type the answer to you.
Use this if additional input is required.
    ]]),
      parameters = {
        type = 'object',
        required = { 'question' },
        properties = {
          question = {
            type = 'string',
            description = 'What do you want to know from the user? Only use a single, short sentence',
          },
          choices = {
            type = 'array',
            items = { type = 'string' },
            description = 'Optional list of choices the user can select from. The user has still the option ignore the choices.',
          },
        },
      },
    },
    execute = function(params, callback)
      opts.ask_user(params, function(answer)
        callback({ result = answer })
      end)
    end,
    render = function(tool_call, tool_call_result)
      local params = tool_call.params or {}
      local question = params.question or ''
      local rendered = {
        '> ' .. question,
      }
      if params.choices and #params.choices > 0 then
        for i, choice in ipairs(params.choices) do
          table.insert(rendered, '> \\' .. i .. ' ' .. choice)
        end
      end
      if tool_call_result and tool_call_result.result then
        vim.list_extend(rendered, { '' })
        vim.list_extend(
          rendered,
          vim.split(
            vim.trim(Messages.extract_text(tool_call_result.result)),
            '\n'
          )
        )
        vim.list_extend(rendered, { '', '---' })
      end
      return rendered
    end,
  }
  return tool
end

return M
