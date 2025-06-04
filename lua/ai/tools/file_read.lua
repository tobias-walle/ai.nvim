local M = {}

local Messages = require('ai.utils.messages')

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
Only use line_start and line_end if you know which lines are relevant (e.g. from an error message).
Read the whole file per default.
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
          line_start = {
            type = 'number',
            description = 'Optional. The first line to read (1-based, inclusive).',
            example = 1,
          },
          line_end = {
            type = 'number',
            description = 'Optional. The last line to read (1-based, inclusive).',
            example = 10,
          },
        },
      },
    },
    execute = function(params, callback)
      local file = params.file
      local line_start = params.line_start
      local line_end = params.line_end

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

      local function slice_lines(lines)
        if line_start or line_end then
          local total = #lines
          local s = line_start and math.max(1, line_start) or 1
          local e = line_end and math.min(total, line_end) or total
          -- Lua tables are 1-based, but nvim_buf_get_lines is 0-based for start, exclusive for end
          -- Here, for slicing, we use 1-based inclusive indices
          local sliced = {}
          for i = s, e do
            table.insert(sliced, lines[i])
          end
          return sliced
        else
          return lines
        end
      end

      if bufnr then
        -- Buffer is open, get content from buffer
        local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
        lines = slice_lines(lines)
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

      if line_start or line_end then
        local lines = vim.split(content, '\n', { plain = true })
        lines = slice_lines(lines)
        content = table.concat(lines, '\n')
      end

      callback({ result = content })
    end,
    render = function(tool_call, result)
      local file = tool_call.params and tool_call.params.file or ''
      local line_start = tool_call.params and tool_call.params.line_start
      local line_end = tool_call.params and tool_call.params.line_end
      local file_display = file
      if line_start or line_end then
        file_display = file
          .. ':'
          .. (line_start or '')
          .. ':'
          .. (line_end or '')
      end
      local result_text = result
        and result.result
        and Messages.extract_text(result.result)
      if result_text then
        if
          type(result_text) == 'string'
          and vim.startswith(result_text, 'Error:')
        then
          return {
            '❌ Error reading file `' .. file_display .. '`',
          }
        end
        local line_count = #vim.split(result_text, '\n') or 0
        return {
          '✅ Reading file `'
            .. file_display
            .. '` ('
            .. line_count
            .. ' lines)',
        }
      else
        return {
          '⏳ Reading file `' .. file_display .. '`',
        }
      end
    end,
  }
  return tool
end

return M
