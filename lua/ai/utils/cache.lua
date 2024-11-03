local M = {}

---@return string
local function get_project_id()
  local cwd = vim.fn.getcwd()
  local replaced = cwd:gsub('/', '__')
  return replaced
end

---@param subpath string
---@return string
local function get_cache_path(subpath)
  local project_id = get_project_id()
  return vim.fn.stdpath('data') .. '/ai/' .. project_id .. '/' .. subpath
end

---@param chat string
function M.save_chat(chat)
  local path = get_cache_path('chats/chat.md')
  vim.system({ 'mkdir', '-p', vim.fs.dirname(path) })
  local file = io.open(path, 'w')
  if file then
    file:write(chat)
    file:close()
  end
end

---@return string | nil
function M.load_chat()
  local path = get_cache_path('chats/chat.md')
  local file = io.open(path, 'r')
  if file then
    local content = file:read('*all')
    file:close()
    return content
  end
  return nil
end

return M
