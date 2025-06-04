local M = {}

---@return string|nil
function M.load_custom_rules()
  local config = require('ai.config').get()
  local rules = require('ai.config').resolve_rules(config.rules_file)
  return rules
end

return M
