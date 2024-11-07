---@type ToolDefinition
return {
  definition = {
    name = 'editor',
    description = vim.trim([[
Use this tool to edit one file or buffer.
You can provide a list of operations to apply on one file.
Operations for each file will be executed in the order they are specified.
Changes for each file can be accepted or rejected as a whole by the user.
As a result of this tool you get a list of logs.

Please choose the edit type that is most appropriate for the given task and can solve it using the least amount of tokens. For example:
- Use the "replacement" tool for most edits
- Use the "override" tool for new files or if overriding the whole file is more efficient
    ]]),
    parameters = {
      type = 'object',
      required = {
        'file',
        'operations',
      },
      properties = {
        file = {
          type = 'string',
          description = 'The path to the file that should be edited or created. Relative to the project root.',
        },
        operations = {
          type = 'array',
          description = 'List of operations to perform on this file in order',
          items = {
            oneOf = {
              {
                type = 'object',
                required = {
                  'type',
                  'search',
                  'replacement',
                },
                description = vim.trim([[
Performs a search & replace operation on the given file.
Please remember you can also do multiline replacements.
You can only replace with simple strings. Regex patterns are not possible. No escaping is needed.
                      ]]),
                properties = {
                  type = {
                    type = 'string',
                    const = 'replacement',
                    description = 'Has to be "replacement"',
                  },
                  search = {
                    type = 'string',
                    description = 'The text to search for',
                  },
                  replacement = {
                    type = 'string',
                    description = 'The text to replace the pattern with',
                  },
                },
                additionalProperties = false,
              },
              {
                type = 'object',
                required = {
                  'type',
                  'content',
                },
                description = 'Standard edit operation that adds or replaces the content of a whole file.',
                properties = {
                  type = {
                    type = 'string',
                    const = 'override',
                    description = 'Has to be "override"',
                  },
                  content = {
                    type = 'string',
                    description = 'The new content to insert',
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

    local file = params.file
    local operations = params.operations

    -- Find or create buffer
    local bufnr = vim.fn.bufadd(file)
    vim.fn.bufload(bufnr)

    -- Create temporary buffer with changes
    local temp_bufnr = vim.api.nvim_create_buf(false, true)
    -- Set the filetype to match the original buffer
    local filetype = vim.api.nvim_buf_get_option(bufnr, 'filetype')
    vim.api.nvim_buf_set_option(temp_bufnr, 'filetype', filetype)
    -- Copy content
    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    vim.api.nvim_buf_set_lines(temp_bufnr, 0, -1, false, lines)

    -- Apply all operations in sequence
    local text_before_opts = vim.fn.join(lines, '\n')
    for i, op in ipairs(operations) do
      if op.type == 'override' then
        -- Handle edit operation
        local new_lines = vim.split(op.content, '\n')
        vim.api.nvim_buf_set_lines(temp_bufnr, 0, -1, false, new_lines)
      elseif op.type == 'replacement' then
        -- Handle replacement operation
        local current_lines =
          vim.api.nvim_buf_get_lines(temp_bufnr, 0, -1, false)
        local buffer_text = vim.fn.join(current_lines, '\n')
        -- Escape everything
        local search = op.search:gsub('%W', '%%%1')
        local replacement = op.replacement:gsub('%%', '%%%%')
        local new_buffer_text = buffer_text:gsub(search, replacement)
        if replacement == new_buffer_text then
          table.insert('Operation ' .. i .. ': Replacement had no effect')
        end
        vim.api.nvim_buf_set_lines(
          temp_bufnr,
          0,
          -1,
          false,
          vim.split(new_buffer_text, '\n')
        )
      end
    end
    local text_after_opts =
      vim.fn.join(vim.api.nvim_buf_get_lines(temp_bufnr, 0, -1, false), '\n')
    if text_before_opts == text_after_opts then
      table.insert(results, 'NO EFFECT')
      callback(results)
      return
    end

    -- Create or switch to diff tab
    vim.cmd('tabnew')
    local win = vim.api.nvim_get_current_win()
    vim.api.nvim_win_set_buf(win, bufnr)
    vim.cmd('diffthis')

    -- Split and show temp buffer
    vim.cmd('vert leftabove split')
    local temp_win = vim.api.nvim_get_current_win()
    vim.api.nvim_win_set_buf(temp_win, temp_bufnr)
    vim.cmd('diffthis')

    -- Setup keymap function
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
        local parent_dir = vim.fn.fnamemodify(file_path, ':h')
        if vim.fn.isdirectory(parent_dir) == 0 then
          vim.fn.mkdir(parent_dir, 'p')
        end
        vim.cmd('write')
      end)
      table.insert(results, 'ACCEPTED')
      vim.cmd('tabclose')
      callback(vim.fn.join(results, '\n'))
    end, opts)

    -- Reject changes
    vim.keymap.set('n', 'gr', function()
      vim.notify('Reject ' .. vim.api.nvim_buf_get_name(bufnr))
      table.insert(results, 'REJECTED')
      vim.cmd('tabclose')
      callback(vim.fn.join(results, '\n'))
    end, opts)
  end,
}
