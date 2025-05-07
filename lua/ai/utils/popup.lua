local M = {}

---@class ResponsePreviewOptions
---@field bufnr number
---@field on_cancel? fun()
---@field on_confirm? fun(lines: string[])
---@field on_retry? fun() It defined, allow the user to retry

---@class ResponsePreviewResult
---@field bufnr number
---@field win number
---@field close fun()

---@param opts ResponsePreviewOptions
---@return ResponsePreviewResult
function M.open_response_preview(opts)
  local config = require('ai.config').get()
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

  local keymap_opts = { buffer = true, silent = true }

  -- Accept changes (and show fast apply diff)
  local is_confirmed = false
  vim.keymap.set('n', config.mappings.buffers.accept_suggestion, function()
    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    if opts.on_confirm then
      is_confirmed = true
      opts.on_confirm(lines)
    end
    close()
  end, keymap_opts)

  -- Cancel
  vim.keymap.set('n', config.mappings.buffers.cancel, function()
    close()
  end, keymap_opts)

  -- Retry (if defined)
  vim.keymap.set('n', config.mappings.buffers.retry, function()
    if opts.on_retry then
      vim.notify('Retry', vim.log.levels.INFO)
      opts.on_retry()
    else
      vim.notify('No retry defined', vim.log.levels.INFO)
    end
  end, keymap_opts)

  vim.api.nvim_create_autocmd('WinClosed', {
    buffer = bufnr,
    once = true,
    callback = function()
      vim.api.nvim_buf_delete(bufnr, { force = true })
      if not is_confirmed and opts.on_cancel then
        opts.on_cancel()
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
