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
      local start_row = start[1] - 1
      local end_row = finish[1] - 1
      -- Normalize order
      if start_row > end_row then
        start_row, end_row = end_row, start_row
      end
      -- Replace lines in selection
      local lines = vim.split(content, '\n')
      vim.api.nvim_buf_set_text(bufnr, start_row, 0, end_row, -1, lines)
      -- Update marks to select the new content
      local new_end_row = start_row + #lines - 1
      vim.api.nvim_buf_set_mark(bufnr, '<', start_row + 1, 0, {})
      vim.api.nvim_buf_set_mark(bufnr, '>', new_end_row + 1, 0, {})
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
