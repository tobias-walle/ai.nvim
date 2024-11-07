local M = {}

---@param value any
---@return string
function M.encode(value)
  -- TODO: Fix yaml encoding
  return vim.json.encode(value) or '{}'
end

---@param yaml string
---@return any
function M.decode(yaml)
  -- TODO: Fix yaml decoding
  return vim.json.decode(yaml)
end

return M
