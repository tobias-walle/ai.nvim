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
  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_set_option_value('filetype', 'markdown', { buf = bufnr })
  vim.cmd('tabnew')
  local tabnr = vim.fn.tabpagenr()
  vim.api.nvim_set_current_buf(bufnr)
  vim.api.nvim_buf_set_name(bufnr, 'AI')
  local win = vim.api.nvim_get_current_win()
  vim.api.nvim_set_option_value('wrap', true, { win = win })

  local function close()
    vim.cmd.tabclose(tabnr)
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
