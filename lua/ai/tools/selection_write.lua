local M = {}

---@class ai.SelectionWriteTool.Options
---@field bufnr integer The buffer to override the selection of

---@param opts ai.SelectionWriteTool.Options
---@return ai.ToolDefinition
function M.create_selection_write_tool(opts)
  ---@type ai.ToolDefinition
  local tool = {
    definition = {
      name = 'selection_write',
      description = vim.trim([[
Overwrite the selected text. You can find the selected text in your context.
Afterwards the selection is updated to include the new text.
This allows you to iterate over it and overwrite the selection again later.
      ]]),
      parameters = {
        type = 'object',
        required = { 'content' },
        properties = {
          content = {
            type = 'string',
            description = 'The content to override the selection with',
            example = 'def say_hello():\n    print("Hello World")',
          },
        },
      },
    },
    execute = function(params, callback)
      local bufnr = opts.bufnr
      local content = params.content
      assert(type(content) == 'string', 'selection_write: Invalid parameters')
      -- Get selection marks
      local start = vim.api.nvim_buf_get_mark(bufnr, '<')
      local finish = vim.api.nvim_buf_get_mark(bufnr, '>')
      if not start or not finish then
        callback({ result = 'No selection found in buffer ' .. bufnr })
        return
      end
      local start_row, start_col = start[1] - 1, start[2]
      local end_row, end_col = finish[1] - 1, finish[2]
      -- Normalize order
      if
        start_row > end_row or (start_row == end_row and start_col > end_col)
      then
        start_row, end_row = end_row, start_row
        start_col, end_col = end_col, start_col
      end
      -- Replace lines in selection
      local lines = vim.split(content, '\n')
      vim.api.nvim_buf_set_text(
        bufnr,
        start_row,
        start_col,
        end_row,
        end_col + 1,
        lines
      )
      -- Update marks to select the new content
      local new_end_row = start_row + #lines - 1
      local new_end_col = (#lines == 1) and (start_col + #lines[1])
        or #lines[#lines]
      vim.api.nvim_buf_set_mark(bufnr, '<', start_row + 1, start_col, {})
      vim.api.nvim_buf_set_mark(bufnr, '>', new_end_row + 1, new_end_col, {})
      callback({ result = 'SUCCESS' })
    end,
    render = function()
      local bufnr = opts.bufnr
      local abs_path = vim.api.nvim_buf_get_name(bufnr)
      local file = vim.fn.fnamemodify(abs_path, ':~:.')
      local start = vim.api.nvim_buf_get_mark(bufnr, '<')[1] + 1
      local finish = vim.api.nvim_buf_get_mark(bufnr, '>')[1] + 1
      return {
        '📝 Overwrite selection in `'
          .. file
          .. ':'
          .. start
          .. ':'
          .. finish
          .. '`',
      }
    end,
  }
  return tool
end

return M
