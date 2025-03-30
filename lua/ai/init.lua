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

  M.did_setup = true
end

--- Toggle the chat sidebar
function M.toggle_chat()
  require('ai.chat').toggle_chat()
end

return M
