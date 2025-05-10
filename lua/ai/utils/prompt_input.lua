local M = {}

---@class PromptInputOptions
---@field prompt string

---@param opts PromptInputOptions
---@param callback fun(input: string)
---@return nil
function M.open_prompt_input(opts, callback)
  M.load_history()

  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_set_option_value('filetype', 'markdown', { buf = bufnr })

  local maximize = false

  -- History navigation state
  local history_index = nil
  local original_lines = nil

  --- @return vim.api.keyset.win_config
  local function get_win_options()
    local screen_width = vim.o.columns
    local screen_height = vim.o.lines
    local win_row = 3
    local width = maximize and screen_width - 6 or 50
    local height = maximize and screen_height - 6 - win_row or 10
    local win_col = math.floor((screen_width - width) / 2)
    return {
      relative = 'editor',
      width = width,
      height = height,
      row = win_row,
      col = win_col,
      title = ' ' .. opts.prompt .. ' ',
      title_pos = 'center',
      style = 'minimal',
      border = 'rounded',
      focusable = true,
      zindex = 100,
    }
  end

  local win = vim.api.nvim_open_win(bufnr, true, get_win_options())
  vim.cmd('startinsert')

  local function refresh_options()
    vim.api.nvim_win_set_config(win, get_win_options())
  end

  local function toggle_maximize()
    maximize = not maximize
    refresh_options()
  end

  local function cancel()
    vim.api.nvim_win_close(win, true)
  end

  local function confirm()
    vim.api.nvim_win_close(win, true)
    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, true)
    local prompt = table.concat(lines, '\n')
    table.insert(M.history, prompt)
    M.save_history()
    callback(prompt)
  end

  local keymap_opts = { buffer = bufnr, silent = true }
  vim.keymap.set('n', '<ESC>', cancel, keymap_opts)
  vim.keymap.set('n', '<CR>', confirm, keymap_opts)
  vim.keymap.set('i', '<S-CR>', confirm, keymap_opts)
  vim.keymap.set('n', ',m', toggle_maximize, keymap_opts)

  local function set_buffer_lines(lines)
    local split_lines = vim.split(lines, '\n')
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, true, split_lines)
    local last_line = #split_lines
    local last_col = #split_lines[#split_lines] or 0
    vim.api.nvim_win_set_cursor(win, { last_line, last_col })
  end

  local function history_up()
    if #M.history == 0 then
      return
    end
    if history_index == nil then
      original_lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, true)
      history_index = #M.history
    elseif history_index > 1 then
      history_index = history_index - 1
    end
    set_buffer_lines(M.history[history_index])
  end

  local function history_down()
    if history_index ~= nil and history_index < #M.history then
      history_index = history_index + 1
      set_buffer_lines(M.history[history_index])
    else
      -- Restore original input
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, true, original_lines or { '' })
      history_index = nil
    end
  end

  vim.keymap.set({ 'n', 'i' }, '<Up>', history_up, keymap_opts)
  vim.keymap.set({ 'n', 'i' }, '<Down>', history_down, keymap_opts)
end

M.history = {}

---@return string
local function get_history_file()
  local config = require('ai.config').get()
  return config.data_dir .. '/prompt_input_history.json'
end

function M.save_history()
  local ok, encoded = pcall(vim.fn.json_encode, M.history)
  if ok and encoded then
    vim.fn.writefile({ encoded }, get_history_file())
  end
end

function M.load_history()
  if vim.fn.filereadable(get_history_file()) == 1 then
    local lines = vim.fn.readfile(get_history_file())
    if lines and #lines > 0 then
      local ok, decoded = pcall(vim.fn.json_decode, table.concat(lines, ''))
      if ok and type(decoded) == 'table' then
        M.history = decoded
      end
    end
  end
end

return M
