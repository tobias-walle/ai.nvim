local M = {}

---@class VariableDefinition
---@field name string
---@field resolve fun(ctx: ChatContext, params: table): string

---@type VariableDefinition[]
M.all = {
  require('ai.variables.buffer'),
  require('ai.variables.diagnostics'),
}

---@param name string
---@return VariableDefinition | nil
function M.find_by_name(name)
  for _, variable in ipairs(M.all) do
    if variable.name == name then
      return variable
    end
  end
  return nil
end

return M
