local M = {}

---@class PromptInputOptions
---@field prompt string

---@param opts PromptInputOptions
---@param callback fun(input: string)
---@return nil
function M.open_prompt_input(opts, callback)
  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_set_option_value('filetype', 'markdown', { buf = bufnr })

  local maximize = false

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
    callback(table.concat(lines, '\n'))
  end

  local keymap_opts = { buffer = bufnr, silent = true }
  vim.keymap.set('n', '<ESC>', cancel, keymap_opts)
  vim.keymap.set('n', '<CR>', confirm, keymap_opts)
  vim.keymap.set('n', ',m', toggle_maximize, keymap_opts)
end

return M
