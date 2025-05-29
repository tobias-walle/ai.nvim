local M = {}

---@return ai.ToolDefinition
function M.create_file_read_tool()
  ---@type ai.ToolDefinition
  local tool = {
    definition = {
      name = 'file_read',
      description = vim.trim([[
Read the content of a specific file.
The file path should be relative to the project root.
Use this tool to request access to the content of a specific file that you need to fullfill your task.
      ]]),
      parameters = {
        type = 'object',
        required = { 'file' },
        properties = {
          file = {
            type = 'string',
            description = 'The relative path to the file from the project root',
            example = 'src/index.ts',
          },
        },
      },
    },
    execute = function(params, callback)
      local file = params.file

      assert(type(file) == 'string', 'file_read: Invalid parameters')

      -- Try to find an open buffer for the file
      local file_path = vim.fn.getcwd() .. '/' .. file
      local bufnr = nil
      for _, b in ipairs(vim.api.nvim_list_bufs()) do
        if vim.api.nvim_buf_is_loaded(b) then
          local buf_name = vim.api.nvim_buf_get_name(b)
          if buf_name == file_path then
            bufnr = b
            break
          end
        end
      end

      if bufnr then
        -- Buffer is open, get content from buffer
        local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
        local content = table.concat(lines, '\n')
        callback({ result = content })
        return
      end

      -- Buffer not open, read the file content from disk
      local f = io.open(file_path, 'r')

      if not f then
        local error = 'Tool (file_read): Could not open file at path: '
          .. file_path
        return callback({ result = 'Error: ' .. error })
      end

      local content = f:read('*a')
      f:close()

      callback({ result = content })
    end,
    render = function(tool_call, result)
      local file = tool_call.params and tool_call.params.file or ''
      if result then
        if
          type(result.result) == 'string'
          and vim.startswith(result.result, 'Error:')
        then
          return {
            '❌ Error reading file `' .. file .. '`',
          }
        end
        local line_count = (
          type(result.result) == 'string' and #vim.split(result.result, '\n')
          or 0
        )
        return {
          '✅ Reading file `' .. file .. '` (' .. line_count .. ' lines)',
        }
      else
        return {
          '⏳ Reading file `' .. file .. '`',
        }
      end
    end,
  }
  return tool
end

return M
