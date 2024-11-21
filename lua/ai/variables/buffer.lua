---@type VariableDefinition
return {
  name = 'buffer',
  resolve = function(ctx, params)
    -- Get the text of the leftmost buffer in the current tab and call the callback with it
    -- Let's expect a vertical split setup
    local wins = vim.api.nvim_tabpage_list_wins(0)
    local leftmost_win = wins[1]
    local buf = vim.api.nvim_win_get_buf(leftmost_win)
    local text = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    -- Get relative paths
    local path = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(buf), ':.')
    local ft = vim.api.nvim_buf_get_option(buf, 'filetype')
    return string.format(
      vim.trim([[
Variable: #buffer - Contains the current buffer. It is always updated and contains all the changes made before.
FILE: %s
```%s
%s
```
]]),
      path,
      ft,
      table.concat(text, '\n')
    )
  end,
}
