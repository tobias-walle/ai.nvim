local M = {}

M.did_setup = false

---@param config AiConfig?
function M.setup(config)
  require('ai.config').setup(config)
  require('ai.commands').setup()

  M.trigger_completion = require('ai.completion').trigger_completion

  M.did_setup = true
end

return M
