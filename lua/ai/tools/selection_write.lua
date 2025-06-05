local M = {}

---@class ai.SelectionWriteTool.Options
---@field editor ai.Editor
---@field bufnr integer The buffer to override the selection of

---@param opts ai.SelectionWriteTool.Options
---@return ai.ToolDefinition
function M.create_selection_write_tool(opts)
  local editor = opts.editor
  local bufnr = opts.bufnr
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
            description = vim.trim([[
The content to override the selection with.
NEVER wrap this in a code block.
Output the code directly.
Do not add any final newline if not already present.
            ]]),
            example = 'def say_hello():\n    print("Hello World")',
          },
        },
      },
    },
    execute = function(params, callback)
      local content = params.content
      assert(type(content) == 'string', 'selection_write: Invalid parameters')
      -- Get selection marks
      local start = vim.api.nvim_buf_get_mark(bufnr, '<')
      local finish = vim.api.nvim_buf_get_mark(bufnr, '>')
      if not start or not finish then
        callback({ result = 'No selection found in buffer ' .. bufnr })
        return
      end
      local start_row = start[1]
      local end_row = finish[1]
      -- Create patch for the editor
      local patch = {
        bufnr = bufnr,
        line_start = start_row,
        line_end = end_row,
        patch = content,
      }
      local patch_bufnr = editor:add_patch(patch)
      editor:subscribe(patch_bufnr, function(job)
        if job.diffview_result then
          if job.diffview_result.result == 'ACCEPTED' then
            -- Update marks to select the new content
            local lines = vim.split(content, '\n')
            local new_end_row = start_row + #lines - 1
            vim.api.nvim_buf_set_mark(bufnr, '<', start_row, 0, {})
            vim.api.nvim_buf_set_mark(bufnr, '>', new_end_row, 0, {})
            callback({ result = 'SUCCESS' })
          elseif job.diffview_result.result == 'REJECTED' then
            callback({
              result = 'REJECTED by the user. Try again and strongly consider the reason for the rejection: '
                .. (job.diffview_result.reason or 'Reason not defined'),
            })
          end
        end
      end)
    end,
    render = function(tool_call, tool_call_result)
      local label = '[selection]'
      if tool_call_result then
        if tool_call_result.result == 'SUCCESS' then
          label = label .. ' ✅'
        else
          label = label .. ' ❌'
        end
      end
      local content = tool_call
          and tool_call.params
          and tool_call.params.content
        or ''
      local result = {}
      local ft = vim.api.nvim_get_option_value('filetype', { buf = bufnr })
      vim.list_extend(result, { '`````' .. ft .. ' ' .. label })
      vim.list_extend(result, vim.split(content, '\n'))
      vim.list_extend(result, { '`````' })
      return result
    end,
  }
  return tool
end

return M
