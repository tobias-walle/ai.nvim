local M = {}

M.did_setup = false

---@param config AiConfig?
function M.setup(config)
  require('ai.config').merge(config)
  require('ai.commands').setup()
  require('ai.chat').setup()

  M.trigger_completion = require('ai.completion').trigger_completion

  vim.api.nvim_create_user_command('AiChangeModels', function()
    require('ai.config').change_default_models()
  end, { nargs = 0 })

  vim.api.nvim_create_user_command('AiEdit', function()
    require('ai.agents.editor').apply_edits({
      bufnr = vim.fn.bufnr('%'),
      patch = [[
// …
    local mapped_tools = vim.iter(tools)
    :map(function(tool)
      return {
        type = 'function',
        ['function'] = {
          name = tool.name,
          description = tool.description,
          parameters = tool.parameters,
        },
      }
    end)
    :totable()
  return mapped_tools
// …
      ]],
    })
  end, { nargs = 0 })

  M.did_setup = true
end

--- Toggle the chat sidebar
function M.toggle_chat()
  require('ai.chat').toggle_chat()
end

return M
