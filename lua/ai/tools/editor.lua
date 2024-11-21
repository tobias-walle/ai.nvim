---@type FakeToolDefinition
local tool = {
  is_fake = true,
  name = 'editor',
  system_prompt = vim.trim([[
# Special Editor syntax
You can use this syntax to apply changes directly in the code base.

- You can use this syntax to replace sections in project files.
- Make sure the original content is unique in the file to prevent unintended replacements.
- Combine multiple replacements for more complex changes.

Follow the syntax VERY CLOSELY:

FILE: <path-relative-to-project-root>
```<language>
<<<<<<< ORIGINAL
<original-code>
=======:
<updated-code>
>>>>>>> UPDATED
```

- FILE: <path> - Specifies the file. Required for the detection of the syntax. NEVER LEAVE IT OUT.
- ```<language> - Start of the code block. Use more than three ticks if three ticks are used within the changes.
- <<<<<<< ORIGINAL - Marks the start of the original content block.
- <original-code> - The EXACT code to replace. MAKE SURE THE SECTION IS UNIQUE!
- ======= - Marks the separator between old and new content.
- <original-code> - The updated code. NEVER USE PLACEHOLDERS LIKE "...", "// Other Methods", etc. IN THE CODE, INSTEAD PROVIDE THE FULL UPDATED CODE.
- >>>>>>> UPDATED - Marks the end the new content declaration.
- ``` - End of the code block

- The markers HAVE TO BE USED IN THE EXACT ORDER
- You can use multiple markers in the same code block IF the order is honored.
- Add no content between the markers

In the following section, examples are separated with "--- EXAMPLE START" and "--- EXAMPLE END".
NEVER USE THESE SEPERATORS IN YOUR OUTPUT.

--- EXAMPLE START
FILE: src/hello.ts
```typescript
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
```
--- EXAMPLE END

--- EXAMPLE START
FILE: backend/logging.py
```python
<<<<<<< ORIGINAL
import logging
=======
from loguru import logger
>>>>>>> UPDATED
<<<<<<< ORIGINAL
logging.basicConfig(
    level=logging.INFO, format=f"{grey}%(levelname)s(%(name)s):{reset} %(message)s"
)

logger = logging.getLogger("backend")
=======
logger.remove()
logger.add(lambda msg: print(f"{grey}{msg}{reset}"), level="INFO", format="{level}({name}): {message}", colorize=False)
>>>>>>> UPDATED
```
--- EXAMPLE END


Here some example which logic to follow then applying changes:
- A lot of small changes across the file -> Replace the changed content
- Creation of new file -> Create the file by keep the ORIGINAL block empty and only specifying the UPDATED content.
- One tiny change -> Replace the part of the file that needs to be changed
- One change that also requires a new import -> Replace the part of the code that needs to be changed and use another replacement for adding the import
- Extraction of some code part into a new file -> Create a the new file, update the imports in the original file using one replacement and use another replacement to remove the old code.

Remember that you HAVE to use the markers.

Before each strategy use:
Summarize in one short sentence what you want to do and which strategy you want to use. Keep it short.

After you have done the changes:
Post a nice emoji and a short, inspirational quote fitting to the change.
]]),

  ---Parse editor tool calls from message content
  ---@param message_content string
  ---@return FakeToolCall[]
  parse = function(message_content)
    -- Ensure newline at the end to prevent parsing issues
    message_content = message_content .. '\n'

    local parser = vim.treesitter.get_string_parser(message_content, 'markdown')

    -- Queries to match our tool format
    local query = vim.treesitter.query.parse(
      'markdown',
      [[
      (
        (paragraph) @file_path
        (#match? @file_path "FILE: .*")
        (fenced_code_block
          (info_string (language) @lang)
          (code_fence_content) @code)+
      )
      ]]
    )

    local calls = {}
    local current_call = nil

    for _, match, _ in
      query:iter_matches(
        parser:parse()[1]:root(),
        message_content,
        0,
        -1,
        { all = true }
      )
    do
      for id, nodes in ipairs(match) do
        for _, node in ipairs(nodes) do
          local capture_name = query.captures[id]
          local text = vim.treesitter.get_node_text(node, message_content)

          if capture_name == 'file_path' then
            local file = text:gsub('^FILE:%s*', '')
            current_call = { file = vim.trim(file) }
            table.insert(calls, current_call)
          end

          -- Parse the code content
          if capture_name == 'code' and current_call then
            -- If the call has markers, it is a replacement, otherwise an override
            local has_replacement_markers = text:find('<<<<<<< ORIGINAL\n')
              ~= nil
            if has_replacement_markers then
              current_call.type = 'replacement'
            else
              current_call.type = 'override'
            end

            if current_call.type == 'override' then
              current_call.content = text
            elseif current_call.type == 'replacement' then
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

                current_call.replacements = current_call.replacements or {}
                table.insert(current_call.replacements, {
                  search = original,
                  replacement = updated,
                })

                pos = end_marker + 16
              end
            end
          end
        end
      end
      -- Reset current call as we're done processing it
      current_call = nil
    end

    -- Group the results by file
    local calls_grouped_by_file = {}
    for _, call in ipairs(calls) do
      local file = call.file
      calls_grouped_by_file[file] = calls_grouped_by_file[file] or {}
      table.insert(calls_grouped_by_file[file], call)
    end

    local groups = {}
    for file, file_calls in pairs(calls_grouped_by_file) do
      table.insert(groups, { file = file, calls = file_calls })
    end

    return groups
  end,

  ---Execute the editor tool
  ---@param ctx ChatContext
  ---@param group table
  ---@param callback function
  execute = function(ctx, group, callback)
    local bufnr = vim.fn.bufadd(group.file)
    vim.fn.bufload(bufnr)

    -- Create temporary buffer with changes
    local temp_bufnr = vim.api.nvim_create_buf(false, true)
    local filetype = vim.api.nvim_buf_get_option(bufnr, 'filetype')
    vim.api.nvim_buf_set_option(temp_bufnr, 'filetype', filetype)

    -- Copy content
    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    vim.api.nvim_buf_set_lines(temp_bufnr, 0, -1, false, lines)

    -- Apply the operation
    for _, call in ipairs(group.calls) do
      if call.type == 'override' then
        local new_lines = vim.split(call.content, '\n')
        vim.api.nvim_buf_set_lines(temp_bufnr, 0, -1, false, new_lines)
      elseif call.type == 'replacement' then
        local current_lines =
          vim.api.nvim_buf_get_lines(temp_bufnr, 0, -1, false)
        local buffer_text = vim.fn.join(current_lines, '\n')

        local replacements = call.replacements

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
    end

    -- Show diff view
    vim.cmd('tabnew')
    local win = vim.api.nvim_get_current_win()
    vim.api.nvim_win_set_buf(win, bufnr)
    vim.cmd('diffthis')

    vim.cmd('vsplit')
    local temp_win = vim.api.nvim_get_current_win()
    vim.api.nvim_win_set_buf(temp_win, temp_bufnr)
    vim.cmd('diffthis')

    -- Setup autocmd to close diff if one of the buffers is closed
    local already_closed = false
    local close_tab = function()
      if not already_closed then
        already_closed = true
        pcall(vim.api.nvim_win_close, win, true)
        pcall(vim.api.nvim_win_close, temp_win, true)
        pcall(vim.api.nvim_buf_delete, temp_bufnr, { force = true })
        callback()
      end
    end

    for _, b in ipairs({ bufnr, temp_bufnr }) do
      vim.api.nvim_create_autocmd('WinClosed', {
        buffer = b,
        once = true,
        callback = function(event)
          local event_win_id = tonumber(event.match)
          if event_win_id == win or event_win_id == temp_win then
            close_tab()
          end
        end,
      })
    end

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
      close_tab()
    end, opts)

    -- Reject changes
    vim.keymap.set('n', 'gr', function()
      close_tab()
    end, opts)
  end,
}

return tool
