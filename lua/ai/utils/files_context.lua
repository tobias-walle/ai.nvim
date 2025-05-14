local M = {} -- Start with this line

local string_utils = require('ai.utils.strings')
local prompts = require('ai.prompts')

--- @type string[]
M.files = {}
M.enabled = true

---@return nil
function M.toggle_enabled()
  if M.enabled then
    vim.notify('Disable Files Context')
  else
    vim.notify('Enable Files Context')
  end
  M.enabled = not M.enabled
  M._emit_change_event()
end

---Get the list of context file paths.
---@return string[]
function M.get_files()
  if M.enabled then
    return vim.deepcopy(M.files)
  else
    return {}
  end
end

---Set the list of context file paths.
---@param paths string[]
---@return nil
function M.set_files(paths)
  M.files = vim.deepcopy(paths)
  M._emit_change_event()
end

---Clear all context file paths.
---@return nil
function M.clear()
  vim.notify('Cleared')
  M.files = {}
  M._emit_change_event()
end

---Add a file path to the context if not already present.
---@param path string
---@return nil
function M.add_file(path)
  for _, p in ipairs(M.files) do
    if p == path then
      return
    end
  end
  table.insert(M.files, path)
  M._emit_change_event()
end

---Remove a file path from the context.
---@param path string
---@return nil
function M.remove_file(path)
  for i, p in ipairs(M.files) do
    if p == path then
      table.remove(M.files, i)
      M._emit_change_event()
      return
    end
  end
end

---Add the relative path of the current buffer to the context if not already present.
---@return nil
function M.add_current()
  local path = M._get_relative_path_of_current_buffer()
  if path then
    vim.notify('Add ' .. path, vim.log.levels.INFO)
    M.add_file(path)
  end
end

---Remove the relative path of the current buffer from the context.
---@return nil
function M.remove_current()
  local path = M._get_relative_path_of_current_buffer()
  if path then
    vim.notify('Remove ' .. path, vim.log.levels.INFO)
    M.remove_file(path)
  end
end

---Open a popup buffer with the list of files, editable, and update context on save.
---@return nil
function M.toggle_menu()
  local buf = vim.api.nvim_create_buf(false, true)
  local width = 100
  local height = 10
  local row = math.floor((vim.o.lines - height) / 2)
  local col = math.floor((vim.o.columns - width) / 2)
  local win = vim.api.nvim_open_win(buf, true, {
    relative = 'editor',
    width = width,
    height = height,
    row = row,
    col = col,
    style = 'minimal',
    border = 'rounded',
  })

  vim.api.nvim_buf_set_lines(buf, 0, -1, false, M.files)

  local function save()
    local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    local new_files = {}
    for _, line in ipairs(lines) do
      local trimmed = vim.trim(line)
      if trimmed ~= '' then
        table.insert(new_files, trimmed)
      end
    end
    M.set_files(new_files)
    vim.api.nvim_win_close(win, true)
    vim.notify('Context saved (' .. #lines .. ' files)', vim.log.levels.INFO)
  end

  vim.keymap.set('n', '<localleader>q', function()
    vim.api.nvim_win_close(win, true)
  end, { buffer = buf, nowait = true, silent = true })

  vim.keymap.set('n', '<localleader>a', function()
    save()
  end, { buffer = buf, nowait = true, silent = true })
end

---Get the prompt string for the current context files.
---@return string
function M.get_prompt()
  if #M.files == 0 then
    return ''
  end
  local file_prompts = {}
  for _, filepath in ipairs(M.files) do
    local ft = vim.filetype.match({ filename = filepath }) or 'text'
    local ok, lines = pcall(vim.fn.readfile, filepath)
    if ok and lines then
      local file_prompt =
        string_utils.replace_placeholders(prompts.files_context_single_file, {
          filename = filepath,
          language = ft,
          content = table.concat(lines, '\n'),
        })
      table.insert(file_prompts, file_prompt)
    end
  end
  local prompt = string_utils.replace_placeholders(prompts.files_context, {
    files = table.concat(file_prompts, '\n'),
  })
  return prompt
end

function M._get_relative_path_of_current_buffer()
  local buf = vim.api.nvim_get_current_buf()
  local abs_path = vim.api.nvim_buf_get_name(buf)
  if abs_path == '' then
    return
  end
  local rel_path = vim.fn.fnamemodify(abs_path, ':.')
  return rel_path
end

---Emit a custom event when files change.
function M._emit_change_event()
  vim.api.nvim_exec_autocmds('User', { pattern = 'AiFilesContextChanged' })
end

return M
