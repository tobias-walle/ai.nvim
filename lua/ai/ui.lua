local M = {}

--- @class InputOptions
--- @field prompt string|nil Prompt text to display above the input area.
--- @field hint string|nil Hint text to display after the prompt.

--- Source: https://github.com/frankroeder/parrot.nvim/blob/main/lua/parrot/ui.lua
--- @param opts InputOptions|nil Options for the input prompt. See `InputOptions`.
--- @param on_confirm fun(content: string) Callback function called with the input content when the prompt is confirmed.
M.input = function(opts, on_confirm)
  opts = (opts and not vim.tbl_isempty(opts)) and opts or vim.empty_dict()

  local prompt = opts.prompt or 'Enter text here... '
  local hint =
    [[confirm with: CTRL-W_q or CTRL-C (all modes) | Esc (normal mode)]]

  -- Create a new buffer
  local buf = vim.api.nvim_create_buf(false, true)

  -- Open the buffer in an upper split
  vim.cmd('aboveleft split')
  local win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(win, buf)

  -- Set buffer options
  vim.api.nvim_set_option_value('buftype', 'nofile', { buf = buf })
  vim.api.nvim_set_option_value('bufhidden', 'wipe', { buf = buf })

  -- Add prompt and hint as virtual text
  local ns_id = vim.api.nvim_create_namespace('input_prompt')
  vim.api.nvim_buf_set_extmark(buf, ns_id, 0, 0, {
    virt_text = { { prompt .. hint, 'Comment' } },
    virt_text_pos = 'overlay',
  })

  -- Enter insert mode in next line
  vim.cmd('normal! o')
  vim.cmd('startinsert')

  -- Set up an autocommand to capture buffer content when the window is closed
  vim.api.nvim_create_autocmd({ 'WinClosed', 'BufLeave' }, {
    buffer = buf,
    callback = function()
      local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
      local content = vim.trim(table.concat(lines, '\n'))

      vim.api.nvim_buf_delete(buf, { force = true })

      if content ~= '' then
        on_confirm(content)
      end
      return true
    end,
  })

  vim.api.nvim_buf_set_keymap(
    buf,
    'i',
    '<C-c>',
    '<Esc>:q<CR>',
    { noremap = true, silent = true }
  )
  vim.api.nvim_buf_set_keymap(
    buf,
    'n',
    '<C-c>',
    ':q<CR>',
    { noremap = true, silent = true }
  )
  vim.api.nvim_buf_set_keymap(
    buf,
    'n',
    'q',
    ':q<CR>',
    { noremap = true, silent = true }
  )
  vim.api.nvim_buf_set_keymap(
    buf,
    'n',
    '<Esc>',
    ':q<CR>',
    { noremap = true, silent = true }
  )
end

return M
