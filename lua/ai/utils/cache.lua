local M = {}

---@return string
local function get_project_id()
  local cwd = vim.fn.getcwd()
  local replaced = cwd:gsub('/', '__')
  return replaced
end

---@return string
local function generate_timestamp()
  return tostring(os.date('%Y%m%d_%H%M%S'))
end

---@param timestamp string
---@return string
local function get_chat_file_name(timestamp)
  return 'chat_' .. timestamp .. '.md'
end

---@param file string
---@return string
local function get_cache_path(file)
  local project_id = get_project_id()
  local base_path = vim.fn.stdpath('data') .. '/ai/' .. project_id .. '/'
  return base_path .. file
end

---@param chat string
---@param timestamp string|nil
function M.save_chat(chat, timestamp)
  local chat_file
  if timestamp then
    chat_file = get_chat_file_name(timestamp)
  else
    local state = M.load_state()
    chat_file = state and state.current_chat_file
      or get_cache_path(generate_timestamp())
  end
  local path = get_cache_path(chat_file)

  -- Ensure directory exists
  vim.system({ 'mkdir', '-p', vim.fs.dirname(path) })

  local file = io.open(path, 'w')
  if file then
    file:write(chat)
    file:close()
  else
    vim.notify('Failed to save chat: ' .. path, vim.log.levels.ERROR)
  end

  -- Update state with current chat timestamp
  M.save_state({ current_chat_file = chat_file })
end

---@return string | nil
function M.load_chat()
  local state = M.load_state()
  if not state then
    return nil
  end

  local path = get_cache_path(state.current_chat_file)
  local file = io.open(path, 'r')
  if file then
    local content = file:read('*all')
    file:close()
    return content
  end
  return nil
end

---@class CacheState
---@field current_chat_file string

---@param state CacheState
function M.save_state(state)
  local state_path = get_cache_path('state.json')
  local file = io.open(state_path, 'w')
  if file then
    file:write(vim.json.encode(state))
    file:close()
  else
    vim.notify('Failed to save state', vim.log.levels.ERROR)
  end
end

---@return CacheState | nil
function M.load_state()
  local state_path = get_cache_path('state.json')
  local file = io.open(state_path, 'r')
  if file then
    local content = file:read('*all')
    file:close()
    if content then
      local state = vim.json.decode(content)
      return state
    end
  end
  return nil
end

function M.new_chat()
  local new_timestamp = generate_timestamp()
  M.save_chat('', new_timestamp)
end

---@return string[] | nil
local function list_chat_files()
  local project_id = get_project_id()
  local base_path = vim.fn.stdpath('data') .. '/ai/' .. project_id .. '/'

  -- Use vim.fn.glob to get all chat files
  local chat_files = vim.fn.glob(base_path .. 'chat_*.md', false, true)
  chat_files = vim
    .iter(chat_files)
    :map(function(file)
      local parts = vim.split(file, '/')
      return parts[#parts]
    end)
    :totable()

  -- Sort files to ensure chronological order
  table.sort(chat_files)

  return #chat_files > 0 and chat_files or nil
end

---@param direction 1|-1
---@return string|nil
local function navigate_chat(direction)
  local state = M.load_state()
  if not state then
    return
  end

  local chat_files = list_chat_files()
  if not chat_files then
    return
  end

  -- Find current chat's index
  local current_index
  for i, file in ipairs(chat_files) do
    if file:match(state.current_chat_file) then
      current_index = i
      break
    end
  end

  -- Validate navigation based on direction
  if
    not current_index
    or (direction == -1 and current_index <= 1)
    or (direction == 1 and current_index >= #chat_files)
  then
    return
  end

  -- Select next or previous file
  local target_file = chat_files[current_index + direction]
  local target_chat_file = target_file:match('chat_[^/]+')

  M.save_state({ current_chat_file = target_chat_file })
  return M.load_chat()
end

---@return string|nil
function M.previous_chat()
  return navigate_chat(-1)
end

---@return string|nil
function M.next_chat()
  return navigate_chat(1)
end

return M
