local M = {}

M.did_setup = false

---@param config AiConfig?
function M.setup(config)
  require('ai.config').set(config)
  require('ai.commands').setup()
  require('ai.chat').setup()
  require('ai.cmp').register_sources()

  M.trigger_completion = require('ai.completion').trigger_completion

  M.did_setup = true
end

--- Toggle the chat sidebar
function M.toggle_chat()
  require('ai.chat').toggle_chat()
end

return M
