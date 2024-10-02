local M = {}

---@class AiConfig
---@field provider? LLMProvider
---@field mappings? { accept_suggestion: string }

M.default_config = {
  provider = require('ai.providers.anthrophic'):new(),
  mappings = {
    accept_suggestion = '<Tab>',
  },
}

---@param config? AiConfig
function M.setup(config)
  ---@type AiConfig
  M.config = vim.tbl_deep_extend('force', M.default_config, config or {})
end

---@param provider string|table
function M.set_provider(provider)
  if type(provider) == 'table' then
    M.config.provider = provider
  else
    M.config.provider = require('ai.providers.' .. provider):new()
  end
  vim.notify_once('[ai] Provider set to ' .. M.config.provider.name)
end

return M
