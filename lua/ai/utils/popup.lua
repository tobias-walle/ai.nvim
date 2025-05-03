local M = {}

--- @class ResponsePreviewOptions
--- @field bufnr number
--- @field on_cancel? fun()
--- @field on_confirm? fun(lines: string[])

--- @class ResponsePreviewResult
--- @field bufnr number
--- @field win number
--- @field close fun()

--- @param options ResponsePreviewOptions
--- @return ResponsePreviewResult
function M.open_response_preview(options)
  local screen_width = vim.o.columns
  local screen_height = vim.o.lines
  local width = math.floor(screen_width * 0.9)
  local height = math.floor(screen_height * 0.9)
  local win_row = math.floor((screen_height - height) / 2)
  local win_col = math.floor((screen_width - width) / 2)
  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_set_option_value('filetype', 'markdown', { buf = bufnr })
  local win = vim.api.nvim_open_win(bufnr, true, {
    relative = 'editor',
    width = width,
    height = height,
    row = win_row,
    col = win_col,
    title = 'Ai Response',
    style = 'minimal',
    border = 'single',
    focusable = true,
    zindex = 50,
  })

  local function close()
    vim.api.nvim_win_close(win, true)
  end

  vim.keymap.set('n', 'q', close, {
    buffer = bufnr,
    silent = true,
  })

  local is_confirmed = false
  vim.keymap.set('n', '<CR>', function()
    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    if options.on_confirm then
      is_confirmed = true
      options.on_confirm(lines)
    end
    close()
  end, {
    buffer = bufnr,
    silent = true,
  })

  vim.api.nvim_create_autocmd('WinClosed', {
    buffer = bufnr,
    once = true,
    callback = function()
      vim.api.nvim_buf_delete(bufnr, { force = true })
      if not is_confirmed and options.on_cancel then
        options.on_cancel()
      end
    end,
  })

  return {
    close = close,
    bufnr = bufnr,
    win = win,
  }
end

return M
