---@type ToolDefinition
return {
  definition = {
    name = 'editor',
    description = vim.trim([[
Use this tool to edit one or multiple files or buffers.
You can provide a list of files with their corresponding edit operations.
Operations for each file will be executed in the order they are specified.
Changes for each file can be accepted or rejected as a whole.
PLEASE CHOOSE THE EDIT TYPE THAT IS MOST APPROPRIATE FOR THE GIVEN TASK AND CAN SOLVE IT USING THE LEAST AMOUNT OF TOKENS.
MOST OF THE TIME THIS IS THE REPLACEMENT TOOL (Except when creating new files or completly replacing the content of a file)
    ]]),
    parameters = {
      type = 'object',
      required = {
        'files',
      },
      properties = {
        files = {
          type = 'array',
          description = 'List of files to edit, each with their own operations',
          items = {
            type = 'object',
            required = {
              'file',
              'operations',
            },
            properties = {
              file = {
                type = 'string',
                description = 'The path to the file that should be edited or created.',
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
                        'content',
                      },
                      description = vim.trim([[
Standard edit operation that adds or replaces the content of a whole file.
                      ]]),
                      properties = {
                        type = {
                          type = 'string',
                          const = 'edit',
                          description = 'Standard edit operation',
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
                        'pattern',
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
                          description = 'Replace text using search & replace',
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
                  },
                },
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

    -- Process files one by one
    local function process_files(files, index)
      if index > #files then
        callback(results)
        return
      end

      local file_entry = files[index]
      local file = file_entry.file
      local operations = file_entry.operations

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
      for _, op in ipairs(operations) do
        if op.type == 'edit' then
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
          vim.api.nvim_buf_set_lines(
            temp_bufnr,
            0,
            -1,
            false,
            vim.split(new_buffer_text, '\n')
          )
        end
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

      -- Setup keymaps for next file
      setup_keymaps(bufnr, temp_bufnr, function()
        process_files(files, index + 1)
      end)
    end

    -- Start processing files
    process_files(params.files, 1)
  end,
}
