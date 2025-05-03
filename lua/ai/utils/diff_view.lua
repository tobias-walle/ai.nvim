local M = {}

---@class AiRenderDiffViewOptions
---@field bufnr integer File to modify
---@field callback? fun(result: "ACCEPTED" | "REJECTED") A function to be executed after the diff view is closed.

---Renders a diff view for comparing two buffers.
---@param opts AiRenderDiffViewOptions
---@return integer diff_bufnr The buffer to apply the changes to
function M.render_diff_view(opts)
  local config = require('ai.config').get()
  local bufnr = opts.bufnr
  local callback = opts.callback

  -- Create temporary
  local temp_bufnr = vim.api.nvim_create_buf(false, true)
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
      end
    end
  end

  for _, b in ipairs({ bufnr, temp_bufnr }) do
    vim.api.nvim_create_autocmd('WinClosed', {
      buffer = b,
      once = true,
      callback = function(event)
        local event_win_id = tonumber(event.match)
        if event_win_id == win or event_win_id == temp_win then
          close_tab('ACCEPTED')
        end
      end,
    })
  end

  local keymap_opts = { buffer = true, silent = true }

  -- Accept changes
  vim.keymap.set('n', config.mappings.diff.accept_suggestion, function()
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
  vim.keymap.set('n', config.mappings.diff.reject_suggestion, function()
    close_tab('REJECTED')
  end, keymap_opts)

  return temp_bufnr
end

return M
