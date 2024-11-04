local M = {}

---@class AiConfig
---@field adapter? AdapterOptions
---@field mappings? { accept_suggestion: string }
---@field context_file? string -- Name of an optional file relative to the opened projects to define custom context for the LLM.

M.default_config = {
  adapter = require('ai.adapters.anthropic'),
  mappings = {
    accept_suggestion = '<Tab>',
  },
  context_file = '.ai-context.md',
}

---@param config? AiConfig
function M.setup(config)
  ---@type AiConfig
  M.config = vim.tbl_deep_extend('force', M.default_config, config or {})
  M.adapter = require('ai.adapters').Adapter:new(M.config.adapter)
end

return M
