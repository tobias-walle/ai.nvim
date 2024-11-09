---@type FakeToolDefinition
local tool = {
  is_fake = true,
  name = 'editor',
  system_prompt = vim.trim([[
You can use the `editor` tool to apply changes directly.
The user has the opportunity to accept, reject or modify the changes.

You can provide changes in two formats:

1. Override the whole file:
_tool-use:editor:override_
`path/to/file`

```<lang>
<content_to_override>
```

2. Replace specific parts with 1 or more replacements:
_tool-use:editor:replacement_
`path/to/file`

```<lang>
<<<<<<< ORIGINAL
<original_content>
=======
<new_content>
>>>>>>> UPDATED
<<<<<<< ORIGINAL
<original_content_2>
=======
<new_content_2>
>>>>>>> UPDATED
```

IMPORTANT RULES:
- NEVER use placeholders like "// Rest of the file" or similar. ALWAYS show the complete content that should be changed
- For replacements: Show the EXACT content that should be replaced in the ORIGINAL section. Multiline replacements are possible.
- File paths are always relative to the project root
- The language tag <lang> should match the file extension (e.g. lua, typescript, etc.)
- Prefer the use of replacement for most edits to save tokens. Exceptions are creating or overriding completly new files.
]]),

  ---Parse editor tool calls from message content
  ---@param message_content string
  ---@return FakeToolCall[]
  parse = function(message_content)
    local parser = vim.treesitter.get_string_parser(message_content, 'markdown')

    -- Queries to match our tool format
    local markdown_query = vim.treesitter.query.parse(
      'markdown',
      [[
        (paragraph) @paragraph
        (fenced_code_block
          (info_string
            (language) @lang)
          (code_fence_content) @code)
      ]]
    )

    local inline_query = vim.treesitter.query.parse(
      'markdown_inline',
      [[
        (emphasis) @tool_header
        (code_span) @file_path
      ]]
    )

    local calls = {}
    local current_call = nil

    -- First pass: Find all paragraphs and code blocks
    for id, node in
      markdown_query:iter_captures(parser:parse()[1]:root(), message_content)
    do
      local text = vim.treesitter.get_node_text(node, message_content)

      if markdown_query.captures[id] == 'paragraph' then
        -- Parse the paragraph with the inline parser
        local inline_parser =
          vim.treesitter.get_string_parser(text, 'markdown_inline')
        local inline_root = inline_parser:parse()[1]:root()

        -- Process inline elements
        for inline_id, inline_node in
          inline_query:iter_captures(inline_root, text)
        do
          local inline_text = vim.treesitter.get_node_text(inline_node, text)

          if inline_query.captures[inline_id] == 'tool_header' then
            current_call = {}

            -- Extract operation type
            current_call.type = inline_text:match('^_tool%-use:editor:(%w+)_$')

            if current_call.type then
              table.insert(calls, current_call)
            else
              current_call = nil
            end
          end

          if
            inline_query.captures[inline_id] == 'file_path' and current_call
          then
            -- Remove the backticks
            current_call.file = inline_text:match('`([^`]+)`')
          end
        end
      end

      -- Parse the code content
      if markdown_query.captures[id] == 'code' and current_call then
        if current_call.type == 'override' then
          current_call.content = text
        elseif current_call.type == 'replacement' then
          -- Extract all original and updated content pairs
          local replacements = {}
          local pos = 1
          while true do
            local original_start = text:find('<<<<<<< ORIGINAL\n', pos)
            if not original_start then
              break
            end

            local separator = text:find('\n=======\n', original_start)
            local end_marker = text:find('\n>>>>>>> UPDATED', separator)

            if not separator or not end_marker then
              break
            end

            local original = text:sub(original_start + 17, separator - 1)
            local updated = text:sub(separator + 9, end_marker - 1)

            table.insert(replacements, {
              search = original,
              replacement = updated,
            })

            pos = end_marker + 16
          end

          if #replacements > 0 then
            current_call.replacements = replacements
          end
        end

        -- Reset current call as we're done processing it
        current_call = nil
      end
    end

    return calls
  end,

  ---Execute the editor tool
  ---@param ctx ChatContext
  ---@param params table
  ---@param callback function
  execute = function(ctx, params, callback)
    local bufnr = vim.fn.bufadd(params.file)
    vim.fn.bufload(bufnr)

    -- Create temporary buffer with changes
    local temp_bufnr = vim.api.nvim_create_buf(false, true)
    local filetype = vim.api.nvim_buf_get_option(bufnr, 'filetype')
    vim.api.nvim_buf_set_option(temp_bufnr, 'filetype', filetype)

    -- Copy content
    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    vim.api.nvim_buf_set_lines(temp_bufnr, 0, -1, false, lines)

    -- Apply the operation
    if params.type == 'override' then
      local new_lines = vim.split(params.content, '\n')
      vim.api.nvim_buf_set_lines(temp_bufnr, 0, -1, false, new_lines)
    elseif params.type == 'replacement' then
      local current_lines = vim.api.nvim_buf_get_lines(temp_bufnr, 0, -1, false)
      local buffer_text = vim.fn.join(current_lines, '\n')

      local replacements = params.replacements

      local new_buffer_text = buffer_text
      for _, rep in ipairs(replacements) do
        local search = rep.search:gsub('%W', '%%%1')
        local replacement = rep.replacement:gsub('%%', '%%%%')
        new_buffer_text = new_buffer_text:gsub(search, replacement)
      end

      vim.api.nvim_buf_set_lines(
        temp_bufnr,
        0,
        -1,
        false,
        vim.split(new_buffer_text, '\n')
      )
    end

    -- Show diff view
    vim.cmd('tabnew')
    local win = vim.api.nvim_get_current_win()
    vim.api.nvim_win_set_buf(win, bufnr)
    vim.cmd('diffthis')

    vim.cmd('vert leftabove split')
    local temp_win = vim.api.nvim_get_current_win()
    vim.api.nvim_win_set_buf(temp_win, temp_bufnr)
    vim.cmd('diffthis')

    -- Setup keymaps
    local opts = { buffer = true, silent = true }

    -- Accept changes
    vim.keymap.set('n', 'ga', function()
      local lines = vim.api.nvim_buf_get_lines(temp_bufnr, 0, -1, false)
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
      vim.api.nvim_buf_call(bufnr, function()
        local file_path = vim.api.nvim_buf_get_name(bufnr)
        local parent_dir = vim.fn.fnamemodify(file_path, ':h')
        if vim.fn.isdirectory(parent_dir) == 0 then
          vim.fn.mkdir(parent_dir, 'p')
        end
        vim.cmd('write')
      end)
      vim.cmd('tabclose')
      callback()
    end, opts)

    -- Reject changes
    vim.keymap.set('n', 'gr', function()
      vim.cmd('tabclose')
      callback()
    end, opts)
  end,
}

return tool
