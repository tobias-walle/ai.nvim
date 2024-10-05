local M = {}

---@class AiConfig
---@field adapter? AdapterOptions
---@field mappings? { accept_suggestion: string }

M.default_config = {
  adapter = require('ai.adapters.anthropic'),
  mappings = {
    accept_suggestion = '<Tab>',
  },
}

---@param config? AiConfig
function M.setup(config)
  ---@type AiConfig
  M.config = vim.tbl_deep_extend('force', M.default_config, config or {})
  M.adapter = require('ai.adapters').Adapter:new(M.config.adapter)
end

return M
