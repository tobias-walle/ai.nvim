---@type FakeToolDefinition
local tool = {
  is_fake = true,
  name = 'editor',
  system_prompt = vim.trim([[
# Special "Editor" Syntax
You can use this `editor` special syntax to apply changes directly in the code base.

The user can interact with the suggested changes by accepting, rejecting, or modifying them. There are two main ways to specify changes:

## 1. Override or Create New Files

Use this method when you need to completely replace the contents of a file or create a new file from scratch.

### Syntax: `editor:override`
- Specify the exact path to the file.
- Provide the complete new content to override the original file.

**Syntax Example:**
```markdown
#### editor:override
path/to/file

`````<lang>
<content_to_override>
`````
```

- `path/to/file`: Location of the file, relative to the project root.
- `<lang>`: The language tag must match the file extension (e.g., `typescript`, `python`, etc.).
- `<content_to_override>`: The new content that will replace the entire file content.

Use this when over 80% of the file content changes.

## 2. Replace Specific Parts of a File

Use this method if you only need to change specific parts of a file. This helps in saving computational tokens by targeting exact locations.

### Syntax: `editor:replacement`
- Specify the path to the file.
- Mark the original content and specify the new content replacement(s).

**Syntax Example:**
```markdown
#### editor:replacement
path/to/file

`````<lang>
<<<<<<< ORIGINAL
<original_content>
=======
<new_content>
>>>>>>> UPDATED
`````
```

- `path/to/file`: Location of the file, relative to the project root.
- `<lang>`: The language tag matching the file type (e.g., `tsx`).
- Within the content:
  - `<<<<<<< ORIGINAL`: Starts the original content block.
  - `<original_content>`: The part of the file being replaced.
  - `=======`: Separator between old and new content.
  - `<new_content>`: The new content to replace `<original_content>`.
  - `>>>>>>> UPDATED`: Ends the new content declaration.

### Notes
- **Multiple Replacements**: You can repeat `<<<<<<< ORIGINAL`, `=======`, and `>>>>>>> UPDATED` to provide multiple replacements within the same file.
- **Completeness**: Always provide the entire replacement or overridden content without placeholders like "// Rest of the file."

## Steps

1. Choose `editor:override` if the entire file or a large majority needs to be replaced.
2. Choose `editor:replacement` if you need to target specific parts of the file for modification.
3. Make sure paths are always relative to the project root.
4. Follow the syntax strictly to ensure proper parsing.

## Output Format

Provide changes using one of the two formats `editor:override` or `editor:replacement`. Be explicit about replacements and use code blocks correctly (`````) for consistency.

Make sure the output contains:
- **File Paths**: Always relative.
- **Language Tags**: Match the file extension.
- **NO Placeholders**: Always provide the full content to replace or override.

## Example (editor:replacement)

**Prompt: "Add the argument firstName and lastName to the hello function"**

```plain
#### editor:replacement
src/hello.ts

`````typescript
<<<<<<< ORIGINAL
function sayHello(): void {
  console.log('Hello World')
}
=======
function sayHello(firstName: string, lastName: string): void {
  const fullName = `${firstName} ${lastName}`;
  console.log(`Hello ${fullName}`);
}
>>>>>>> UPDATED
`````
```

Use similar formats for any change request. Understand context and apply changes precisely.
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
      (
        (atx_heading
          (atx_h4_marker)
          (inline) @tool_header
          (#match? @tool_header "^editor:.*")
        )
        (paragraph) @file_path
        (fenced_code_block
          (info_string
            (language) @lang)
          (code_fence_content) @code)
      )
      ]]
    )

    local calls = {}
    local current_call = nil

    -- First pass: Find all paragraphs and code blocks
    for id, node in
      markdown_query:iter_captures(parser:parse()[1]:root(), message_content)
    do
      local text = vim.treesitter.get_node_text(node, message_content)

      if markdown_query.captures[id] == 'tool_header' then
        current_call = {}
        -- Extract operation type from ATX heading (#### editor:type)
        current_call.type = text:match('editor:(%w+)')
        if current_call.type then
          table.insert(calls, current_call)
        else
          current_call = nil
        end
      end

      if markdown_query.captures[id] == 'file_path' then
        current_call.file = vim.trim(text)
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

          current_call.replacements = replacements
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
