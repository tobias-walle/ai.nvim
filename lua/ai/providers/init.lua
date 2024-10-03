local M = {}

---@class LLMMessage
---@field role "user"|"assistant"
---@field content string

---@class LLMStreamOptions
---@field system_prompt string?
---@field messages LLMMessage[]
---@field max_tokens integer?
---@field temperature float?
---@field on_data fun(delta:string): nil

---@class LLMProvider
---@field name string
---@field model string
---@field stream fun(self, options: LLMStreamOptions): vim.SystemObj
M.LLMProvider = {}
M.LLMProvider.__Index = M.LLMProvider

function M.LLMProvider:new()
  return setmetatable({}, self)
end

---@return string
function M.LLMProvider:as_string()
  return self.name .. ':' .. self.model
end

return M
