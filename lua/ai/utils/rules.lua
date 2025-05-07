local M = {}

---@return string|nil
function M.load_custom_rules()
  local config = require('ai.config').get()
  if vim.fn.filereadable(config.rules_file) == 1 then
    local project_rules_lines = vim.fn.readfile(config.rules_file)
    local project_rules = table.concat(project_rules_lines, '\n')
    return project_rules
  end
end

return M
