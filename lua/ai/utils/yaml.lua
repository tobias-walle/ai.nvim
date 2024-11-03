local M = {}

---@param value any
---@return string
function M.encode(value)
  local yaml = vim.fn.system({
    'yq',
    'e',
    '-n',
    '-P',
    vim.json.encode(value),
  })
  local formatted = vim.fn.system({
    'yq',
    'sort_keys(..)',
  }, yaml)
  return vim.trim(formatted)
end

---@param yaml string
---@return any
function M.decode(yaml)
  local json = vim.fn.system({
    'yq',
    'eval',
    '-o=json',
    '-',
  }, yaml)
  return vim.json.decode(json)
end

return M
