local M = {}

---@class ai.RenderDiffView
---@field bufnr number
---@field win number
---@field close fun()

---@alias ai.ApplyResult "ACCEPTED" | "REJECTED"

---@class ai.RenderDiffViewOptions
---@field bufnr integer File to modify
---@field callback? fun(result: ai.ApplyResult) A function to be executed after the diff view is closed.
---@field on_retry? fun() It defined, allow the user to retry

---Renders a diff view for comparing two buffers.
---@param opts ai.RenderDiffViewOptions
---@return ai.RenderDiffView
function M.render_diff_view(opts)
  local config = require('ai.config').get()
  local bufnr = opts.bufnr
  local callback = opts.callback

  -- Create temporary
  local temp_bufnr = vim.api.nvim_create_buf(false, true)
  local filename = vim.api.nvim_buf_get_name(bufnr)
  vim.api.nvim_buf_set_name(temp_bufnr, filename .. ' [AI]')
  local filetype = vim.api.nvim_buf_get_option(bufnr, 'filetype')
  vim.api.nvim_buf_set_option(temp_bufnr, 'filetype', filetype)

  -- Copy content
  local original_buf_lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  vim.api.nvim_buf_set_lines(temp_bufnr, 0, -1, false, original_buf_lines)

  -- Show diff view
  vim.cmd('tabnew')
  local win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(win, bufnr)
  vim.cmd('diffthis')

  vim.cmd('vsplit')
  local temp_win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(temp_win, temp_bufnr)
  vim.cmd('diffthis')

  -- Setup autocmd to close diff if one of the buffers is closed
  local already_closed = false
  local close_tab = function(result)
    if not already_closed then
      already_closed = true
      -- Lose all windows of the diff
      pcall(vim.api.nvim_win_close, win, true)
      pcall(vim.api.nvim_win_close, temp_win, true)
      pcall(vim.api.nvim_buf_delete, temp_bufnr, { force = true })
      if callback then
        callback(result)
        callback = nil
      end
    end
  end

  for _, b in ipairs({ bufnr, temp_bufnr }) do
    vim.api.nvim_create_autocmd({ 'WinClosed', 'BufWipeout' }, {
      buffer = b,
      once = true,
      callback = function(event)
        local event_win_id = tonumber(event.match)
        if event_win_id == win or event_win_id == temp_win then
          close_tab('REJECTED')
        end
      end,
    })
  end

  local keymap_opts = { buffer = true, silent = true }

  -- Accept changes
  vim.keymap.set('n', config.mappings.buffers.accept_suggestion, function()
    local lines = vim.api.nvim_buf_get_lines(temp_bufnr, 0, -1, false)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
    vim.api.nvim_buf_call(bufnr, function()
      local file_path = vim.api.nvim_buf_get_name(bufnr)
      local parent_dir = vim.fn.fnamemodify(file_path, ':h')
      if vim.fn.isdirectory(parent_dir) == 0 then
        vim.fn.mkdir(parent_dir, 'p')
      end
      vim.cmd('write')
    end)
    close_tab('ACCEPTED')
  end, keymap_opts)

  -- Reject changes
  vim.keymap.set('n', config.mappings.buffers.cancel, function()
    close_tab('REJECTED')
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

  ---@type ai.RenderDiffView
  local result = {
    bufnr = temp_bufnr,
    win = win,
    close = close_tab,
  }
  return result
end

return M
