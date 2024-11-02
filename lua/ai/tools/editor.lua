---@type ToolDefinition
return {
  definition = {
    name = 'editor',
    description = vim.trim([[
Use this tool to edit one or multiple files or buffers.
You can provide a list of edits.
Please choose the edit type that is most appropriate for the given task and can solve it using the least amount of tokens.
  ]]),
    parameters = {
      type = 'object',
      required = {
        'operations',
      },
      properties = {
        operations = {
          type = 'array',
          description = 'List of edit operations to perform',
          items = {
            oneOf = {
              {
                type = 'object',
                required = {
                  'type',
                  'file',
                  'line_start_inclusive',
                  'line_end_exclusive',
                  'content',
                },
                description = vim.trim([[
Standard edit operation that adds or replaces the given content on the given line numbers.
Provide the content you want to add and the line numbers you want to add it to.
Existing content in the lines will be overriden.
            ]]),
                properties = {
                  type = {
                    type = 'string',
                    const = 'edit',
                    description = 'Standard edit operation',
                  },
                  file = {
                    type = 'string',
                    description = 'The path to the file that should be edited or created.',
                  },
                  line_start_inclusive = {
                    type = 'integer',
                    description = 'The starting line number where the edit should begin (inclusive)',
                    minimum = 1,
                  },
                  line_end_exclusive = {
                    type = 'integer',
                    description = 'The ending line number where the edit should end (exclusive)',
                    minimum = 1,
                  },
                  content = {
                    type = 'string',
                    description = 'The new content to insert',
                  },
                },
                additionalProperties = false,
              },
              {
                type = 'object',
                required = {
                  'type',
                  'file',
                  'pattern',
                  'replacement',
                },
                description = vim.trim([[
Performs a search & replace operation on the given file using lua patterns.
            ]]),
                properties = {
                  type = {
                    type = 'string',
                    const = 'replacement',
                    description = 'Replace text matching a lua pattern.',
                  },
                  file = {
                    type = 'string',
                    description = 'The path to the file that should be edited',
                  },
                  pattern = {
                    type = 'string',
                    description = 'The lua pattern to search for. Make sure to use escaping if necessary.',
                    -- example = '\\(Hello\\) \\w\\+',
                  },
                  replacement = {
                    type = 'string',
                    description = 'The text to replace the pattern with. Can contain captures of the pattern before.',
                    -- example = '\\1 World',
                  },
                },
                additionalProperties = false,
              },
            },
          },
        },
      },
    },
  },
  execute = function(ctx, params, callback)
    local results = {}

    local function ensure_parent_dirs(file_path)
      local parent_dir = vim.fn.fnamemodify(file_path, ':h')
      if vim.fn.isdirectory(parent_dir) == 0 then
        vim.fn.mkdir(parent_dir, 'p')
      end
    end

    -- Setup keymap function
    local function setup_keymaps(bufnr, temp_bufnr, next_fn)
      local opts = { buffer = true, silent = true }
      -- Accept changes
      vim.keymap.set('n', 'ga', function()
        vim.notify('Accept ' .. vim.api.nvim_buf_get_name(bufnr))
        -- Copy content from temp buffer to original
        local lines = vim.api.nvim_buf_get_lines(temp_bufnr, 0, -1, false)
        vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
        -- Save the buffer
        vim.api.nvim_buf_call(bufnr, function()
          local file_path = vim.api.nvim_buf_get_name(bufnr)
          ensure_parent_dirs(file_path)
          vim.cmd('write')
        end)
        table.insert(results, 'ACCEPTED')
        vim.cmd('tabclose')
        next_fn()
      end, opts)

      -- Reject changes
      vim.keymap.set('n', 'gr', function()
        vim.notify('Reject ' .. vim.api.nvim_buf_get_name(bufnr))
        table.insert(results, 'REJECTED')
        vim.cmd('tabclose')
        next_fn()
      end, opts)
    end

    -- Process operations one by one
    local function process_operations(operations, index)
      if index > #operations then
        callback(results)
        return
      end

      local op = operations[index]
      local file = op.file

      -- Find or create buffer
      local bufnr = vim.fn.bufadd(file)
      vim.fn.bufload(bufnr)

      -- Create temporary buffer with changes
      local temp_bufnr = vim.api.nvim_create_buf(false, true)
      -- Set the filetype to match the original buffer
      local filetype = vim.api.nvim_buf_get_option(bufnr, 'filetype')
      vim.api.nvim_buf_set_option(temp_bufnr, 'filetype', filetype)
      -- Copy content
      local original_lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
      vim.api.nvim_buf_set_lines(temp_bufnr, 0, -1, false, original_lines)

      -- Apply changes based on operation type
      if op.type == 'edit' then
        -- Handle edit operation
        local new_lines = vim.split(op.content, '\n')
        vim.api.nvim_buf_set_lines(
          temp_bufnr,
          op.line_start_inclusive - 1,
          op.line_end_exclusive - 1,
          false,
          new_lines
        )
      elseif op.type == 'replacement' then
        -- Handle replacement operation
        local lines = vim.api.nvim_buf_get_lines(temp_bufnr, 0, -1, false)
        local buffer_text = vim.fn.join(lines, '\n')
        local new_buffer_text = buffer_text:gsub(op.pattern, op.replacement)
        vim.api.nvim_buf_set_lines(
          temp_bufnr,
          0,
          -1,
          false,
          vim.split(new_buffer_text, '\n')
        )
      end

      -- Create or switch to diff tab
      vim.cmd('tabnew')
      local win = vim.api.nvim_get_current_win()
      vim.api.nvim_win_set_buf(win, bufnr)
      vim.cmd('diffthis')

      -- Split and show temp buffer
      vim.cmd('vsplit')
      local temp_win = vim.api.nvim_get_current_win()
      vim.api.nvim_win_set_buf(temp_win, temp_bufnr)
      vim.cmd('diffthis')

      -- Setup keymaps for next operation
      setup_keymaps(bufnr, temp_bufnr, function()
        process_operations(operations, index + 1)
      end)
    end

    -- Start processing operations
    process_operations(params.operations, 1)
  end,
}
