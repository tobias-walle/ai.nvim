---@type VariableDefinition
return {
  name = 'selection',
  resolve = function(ctx, params)
    local bufnr = ctx.left_bufnr
    local selection = ctx.left_buf_selection

    if not bufnr or not selection then
      return 'No selection'
    end

    -- Get the selected text
    local lines = vim.api.nvim_buf_get_lines(
      bufnr,
      selection.line_start - 1,
      selection.line_end,
      false
    )
    if #lines > 0 then
      lines[#lines] = string.sub(lines[#lines], 1, selection.col_end)
      lines[1] = string.sub(lines[1], selection.col_start + 1)
    end

    -- Get relative paths
    local path = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(bufnr), ':.')
    local ft = vim.api.nvim_buf_get_option(bufnr, 'filetype')
    local result = string.format(
      vim.trim([[
Variable: #selection - Contains the current selection
FILE: %s
```%s
%s
```
]]),
      path,
      ft,
      table.concat(lines, '\n')
    )
    vim.print(result)
    return result
  end,
}
