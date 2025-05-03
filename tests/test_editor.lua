---@diagnostic disable-next-line: unused-local
local expect = MiniTest.expect

local child = MiniTest.new_child_neovim()

local U = require('ai.utils.testing').setup(child)

local project_dir

local T = MiniTest.new_set({
  hooks = {
    pre_case = function()
      -- Restart child process with custom 'init.lua' script
      child.restart({ '-u', 'scripts/minimal_init.lua' })
    end,
    post_case = U.post_case_log_debug_info,
    -- Stop once all test cases are finished
    post_once = child.stop,
  },
})

local setup = function(model)
  U.before_each()
  project_dir = U.prepare_test_project()
  child.cmd('cd ' .. project_dir)
  local tmp_dir = U.create_tmp_dir()
  ---@type AiConfig
  local options = {
    default_models = { default = model or 'openai:gpt-4o-mini' },
    data_dir = tmp_dir,
  }
  child.lua(string.format("require('ai').setup(%s)", vim.inspect(options)))
end

local function test_edit(options)
  child.api.nvim_buf_set_lines(
    0,
    0,
    -1,
    false,
    vim.split(vim.trim(options.original), '\n')
  )

  child.g._ai_patch = vim.trim(options.patch)
  child.lua([[
    require('ai.agents.editor').apply_edits(
      {
        bufnr = 0,
        patch = vim.g._ai_patch,
      },
      function() vim.g._ai_is_done = true end
    )
  ]])

  -- Wait until the answer was generated
  U.lua_wait_for('vim.g._ai_is_done', 10000)

  -- Now we will see a diff in which we can accept the changes
  -- We accept it
  child.type_keys('ga')

  -- Verify that the patch was fixed
  local normalize = function(content)
    return vim.trim(content):gsub('%s+', '')
  end
  local buffer_content = U.buffer_content_normalized(0)
  expect.equality(normalize(buffer_content), normalize(options.expected))
end

local activated = {
  simple = true,
  medium = true,
  big = true,
}

local models = {
  'azure:gpt-4.1-mini',
  'azure:gpt-4.1-nano',
}

for _, model in ipairs(models) do
  T[model] = MiniTest.new_set()

  if activated.simple then
    T[model]['should do a simple edit'] = function()
      setup(model)
      test_edit({
        original = [[
local function add(a, b)
  return a - b
end
      ]],
        patch = [[
// …
  return a * b
// …
      ]],
        expected = [[
local function add(a, b)
  return a * b
end
      ]],
      })
    end
  end

  if activated.medium then
    T[model]['should do a medium complex edit'] = function()
      setup(model)
      test_edit({
        original = [[
import { State, EventInput } from '@life/shared';
import ky from 'ky';

export const api = createApi();

export type Client = typeof ky;
export type Api = EventsApi & StateApi;

export function createApi(): Api {
  const client: Client = ky.extend({ prefixUrl: '/api' });
  return {
    ...createEventsApi(client),
    ...createStateApi(client),
  };
}

export interface EventsApi {
  addEvents(event: EventInput[]): Promise<void>;
  getEvents(): Promise<Event[]>;
}

function createEventsApi(client: Client): EventsApi {
  return {
    getEvents: () => client.get('events').json(),
    addEvents: (events) => client.post('events', { json: events }).json(),
  };
}

export interface StateApi {
  getState(signal?: AbortSignal): Promise<State>;
}

function createStateApi(client: Client): StateApi {
  return {
    getState: (signal) => client.get('state', { signal }).json(),
  };
}
      ]],
        patch = [[
// …
export interface EventsApi {
  // …
  updateEvents(events: EventInput[]): Promise<void>;
}

function createEventsApi(client: Client): EventsApi {
  return {
    // …
    updateEvents: (events) => client.patch('events', { json: events }).json(),
  };
}
// …
      ]],
        expected = [[
import { State, EventInput } from '@life/shared';
import ky from 'ky';

export const api = createApi();

export type Client = typeof ky;
export type Api = EventsApi & StateApi;

export function createApi(): Api {
  const client: Client = ky.extend({ prefixUrl: '/api' });
  return {
    ...createEventsApi(client),
    ...createStateApi(client),
  };
}

export interface EventsApi {
  addEvents(event: EventInput[]): Promise<void>;
  getEvents(): Promise<Event[]>;
  updateEvents(events: EventInput[]): Promise<void>;
}

function createEventsApi(client: Client): EventsApi {
  return {
    getEvents: () => client.get('events').json(),
    addEvents: (events) => client.post('events', { json: events }).json(),
    updateEvents: (events) => client.patch('events', { json: events }).json(),
  };
}

export interface StateApi {
  getState(signal?: AbortSignal): Promise<State>;
}

function createStateApi(client: Client): StateApi {
  return {
    getState: (signal) => client.get('state', { signal }).json(),
  };
}
      ]],
      })
    end
  end

  if activated.big then
    T[model]['should do a edit in a big file'] = function()
      setup(model)
      test_edit({
        original = [[
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
  local config = require('ai.config').get()
  local project_id = get_project_id()
  local base_path = config.data_dir .. '/' .. project_id .. '/'
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
  vim.system({ 'mkdir', '-p', vim.fs.dirname(path) }):wait()

  local file, err = io.open(path, 'w')
  if file then
    file:write(chat)
    file:close()
  else
    vim.notify(
      'Failed to save chat (' .. err .. '): ' .. path,
      vim.log.levels.ERROR
    )
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
      local state =
        vim.json.decode(content, { luanil = { object = true, array = true } })
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

--- Search chats via Telescope
function M.search_chats(opts, callback)
  opts = opts or {}

  local pickers = require('telescope.pickers')
  local previewers = require('telescope.previewers')
  local finders = require('telescope.finders')
  local conf = require('telescope.config').values
  local actions = require('telescope.actions')
  local action_state = require('telescope.actions.state')

  -- Get list of chat files
  local chat_files = list_chat_files()

  if not chat_files or #chat_files == 0 then
    vim.notify('No chat files found', vim.log.levels.WARN)
    return
  end

  -- Prepare chat files with full paths
  local project_id = get_project_id()
  local base_path = vim.fn.stdpath('data') .. '/ai/' .. project_id .. '/'

  -- Prepare results with unique filenames and their full paths
  local unique_files = {}
  for _, file in ipairs(chat_files) do
    local full_path = base_path .. file
    unique_files[file] = full_path
  end

  -- Custom previewer to show full file content
  local previewer = previewers.new_buffer_previewer({
    title = 'Chat Preview',
    get_buffer_by_name = function(_, entry)
      return entry.filename
    end,
    define_preview = function(self, entry)
      -- Read the full file content
      local content = vim.fn.readfile(entry.value)

      -- Set the preview buffer content
      vim.api.nvim_buf_set_lines(self.state.bufnr, 0, -1, false, content)

      -- Set syntax highlighting
      vim.api.nvim_buf_set_option(self.state.bufnr, 'filetype', 'markdown')
    end,
  })

  pickers
    .new(opts, {
      prompt_title = 'Search Chat History',
      finder = finders.new_table({
        results = (function()
          local results = {}
          for filename, full_path in pairs(unique_files) do
            -- Read the full file content
            local content = table.concat(vim.fn.readfile(full_path), '\n')
            table.insert(results, {
              filename = filename,
              value = full_path,
              content = content,
            })
          end
          -- Sort the results by filename
          table.sort(results, function(a, b)
            return a.filename > b.filename
          end)
          return results
        end)(),
        entry_maker = function(entry)
          local lines = vim.split(entry.content, '\n')
          local content_preview =
            table.concat(vim.list_slice(lines, 2, 20), ' ')
          return {
            value = entry.value,
            display = entry.filename .. content_preview,
            ordinal = entry.filename .. ' ' .. entry.content,
            filename = entry.filename,
          }
        end,
      }),
      sorter = conf.generic_sorter(opts),
      previewer = previewer,
      attach_mappings = function(prompt_bufnr, map)
        actions.select_default:replace(function()
          local selection = action_state.get_selected_entry()
          M.save_state({ current_chat_file = selection.filename })
          actions.close(prompt_bufnr)
          callback()
        end)
        return true
      end,
    })
    :find()
end

return M
      ]],
        patch = [[
-- …

---@return string
local function generate_timestamp()
  return tostring(os.date('%Y%m%d_%H%M%S'))
end

-- …
      ]],
        expected = [[
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
  local config = require('ai.config').get()
  local project_id = get_project_id()
  local base_path = config.data_dir .. '/' .. project_id .. '/'
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
  vim.system({ 'mkdir', '-p', vim.fs.dirname(path) }):wait()

  local file, err = io.open(path, 'w')
  if file then
    file:write(chat)
    file:close()
  else
    vim.notify(
      'Failed to save chat (' .. err .. '): ' .. path,
      vim.log.levels.ERROR
    )
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
      local state =
        vim.json.decode(content, { luanil = { object = true, array = true } })
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

--- Search chats via Telescope
function M.search_chats(opts, callback)
  opts = opts or {}

  local pickers = require('telescope.pickers')
  local previewers = require('telescope.previewers')
  local finders = require('telescope.finders')
  local conf = require('telescope.config').values
  local actions = require('telescope.actions')
  local action_state = require('telescope.actions.state')

  -- Get list of chat files
  local chat_files = list_chat_files()

  if not chat_files or #chat_files == 0 then
    vim.notify('No chat files found', vim.log.levels.WARN)
    return
  end

  -- Prepare chat files with full paths
  local project_id = get_project_id()
  local base_path = vim.fn.stdpath('data') .. '/ai/' .. project_id .. '/'

  -- Prepare results with unique filenames and their full paths
  local unique_files = {}
  for _, file in ipairs(chat_files) do
    local full_path = base_path .. file
    unique_files[file] = full_path
  end

  -- Custom previewer to show full file content
  local previewer = previewers.new_buffer_previewer({
    title = 'Chat Preview',
    get_buffer_by_name = function(_, entry)
      return entry.filename
    end,
    define_preview = function(self, entry)
      -- Read the full file content
      local content = vim.fn.readfile(entry.value)

      -- Set the preview buffer content
      vim.api.nvim_buf_set_lines(self.state.bufnr, 0, -1, false, content)

      -- Set syntax highlighting
      vim.api.nvim_buf_set_option(self.state.bufnr, 'filetype', 'markdown')
    end,
  })

  pickers
    .new(opts, {
      prompt_title = 'Search Chat History',
      finder = finders.new_table({
        results = (function()
          local results = {}
          for filename, full_path in pairs(unique_files) do
            -- Read the full file content
            local content = table.concat(vim.fn.readfile(full_path), '\n')
            table.insert(results, {
              filename = filename,
              value = full_path,
              content = content,
            })
          end
          -- Sort the results by filename
          table.sort(results, function(a, b)
            return a.filename > b.filename
          end)
          return results
        end)(),
        entry_maker = function(entry)
          local lines = vim.split(entry.content, '\n')
          local content_preview =
            table.concat(vim.list_slice(lines, 2, 20), ' ')
          return {
            value = entry.value,
            display = entry.filename .. content_preview,
            ordinal = entry.filename .. ' ' .. entry.content,
            filename = entry.filename,
          }
        end,
      }),
      sorter = conf.generic_sorter(opts),
      previewer = previewer,
      attach_mappings = function(prompt_bufnr, map)
        actions.select_default:replace(function()
          local selection = action_state.get_selected_entry()
          M.save_state({ current_chat_file = selection.filename })
          actions.close(prompt_bufnr)
          callback()
        end)
        return true
      end,
    })
    :find()
end

return M
      ]],
      })
    end
  end
end

return T
