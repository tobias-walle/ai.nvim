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
- MAKE SURE TO ALWAYS USE REPLACEMENTS FOR EDITS. AVOID REPEATING THE WHOLE FILE CONTENT.

Follow the syntax VERY CLOSELY:

`````<language> FILE=<path-relative-to-project-root> - Start of the code block. Specify the language and the file. Use five instead of three ticks to avoid conflicts with triple ticks inside the block. THE FILE PATH HAS TO BE DEFINED IN THE SAME LINE!
<<<<<<< ORIGINAL - Marks the start of the original content block.
<original-code> - The EXACT code to replace. MAKE SURE THE SECTION IS UNIQUE BY REPEATING A LARGE ENOUGH SECTION! NEVER LEAVE THIS BLOCK EMPTY IF THE FILE IS NOT EMPTY.
======= - Marks the separator between old and new content.
<code-to-replace-original-code> - The updated code. NEVER USE PLACEHOLDERS LIKE "...", "// Other Methods", etc. IN THE CODE, INSTEAD PROVIDE THE FULL UPDATED CODE.
>>>>>>> UPDATED - Marks the end the new content declaration.
````` - End of the code block. USE FIVE TICKS!

- The markers HAVE TO BE USED IN THE EXACT ORDER
- You can use multiple markers in the same code block IF the order is honored.
- Add no content between the markers

In the following section, examples are separated with "--- EXAMPLE START" and "--- EXAMPLE END".
NEVER USE THESE SEPERATORS IN YOUR OUTPUT.

--- EXAMPLE START (Prompt: Add the firstName and lastName arguments)
`````typescript FILE=src/hello.ts
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
--- EXAMPLE END

--- EXAMPLE START (Prompt: Replace logging with loguru)
`````python FILE=backend/logging.py
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
`````
--- EXAMPLE END

--- EXAMPLE START (Prompt: Add the sub function)
`````typescript FILE=src/hello.ts
<<<<<<< ORIGINAL
function add(a: number, b: number): number {
  return a + b;
}
=======
function add(a: number, b: number): number {
  return a + b;
}

function sub(a: number, b: number): number {
  return a - b;
}
>>>>>>> UPDATED
`````


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
Post a emoji fitting the theme of the changes
]]),
  reminder_prompt = vim.trim([[
## Editor
Use the editor syntax for all edits like this:

`````typescript FILE=src/hello.ts
<<<<<<< ORIGINAL
  console.log('Hello World')
=======
  const fullName = `${firstName} ${lastName}`;
  console.log(`Hello ${fullName}`);
>>>>>>> UPDATED

REMEMBER THAT THE ORIGINAL BLOCK NEEDS TO MATCH EXACTLY. THIS INCLUDES LEADING WHITESPACE!
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
        (fenced_code_block
          (info_string (language)) @info
          (#match? @info "FILE=.*")
          (code_fence_content) @code)+
      )
      ]]
    )

    local calls = {}
    local current_call = nil

    for id, node, _, _ in
      query:iter_captures(parser:parse()[1]:root(), message_content, 0, -1)
    do
      local capture_name = query.captures[id]
      local text = vim.treesitter.get_node_text(node, message_content)

      if capture_name == 'info' then
        local file = text:gsub('^.*FILE=', '')
        current_call = { file = vim.trim(file) }
        table.insert(calls, current_call)
      end

      -- Parse the code content
      if capture_name == 'code' and current_call then
        -- If the call has markers, it is a replacement, otherwise an override
        local has_replacement_markers = text:find('<<<<<<< ORIGINAL\n') ~= nil
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

    -- Reset current call as we're done processing it
    current_call = nil

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
  ---@diagnostic disable-next-line: unused-local
  execute = function(ctx, group, callback)
    local bufnr = vim.fn.bufadd(group.file)
    vim.fn.bufload(bufnr)

    local diff_bufnr = require('ai.utils.diff_view').render_diff_view({
      bufnr = bufnr,
      callback = callback,
    })

    -- Apply the operation
    for _, call in ipairs(group.calls) do
      if call.type == 'override' then
        local new_lines = vim.split(call.content, '\n')
        vim.api.nvim_buf_set_lines(diff_bufnr, 0, -1, false, new_lines)
      elseif call.type == 'replacement' then
        local current_lines =
          vim.api.nvim_buf_get_lines(diff_bufnr, 0, -1, false)
        local buffer_text = vim.fn.join(current_lines, '\n')

        local replacements = call.replacements or {}

        local new_buffer_text = buffer_text
        for _, rep in ipairs(replacements) do
          local search = rep.search:gsub('%W', '%%%1')
          local replacement = rep.replacement:gsub('%%', '%%%%')
          new_buffer_text = new_buffer_text:gsub(search, replacement)
        end

        vim.api.nvim_buf_set_lines(
          diff_bufnr,
          0,
          -1,
          false,
          vim.split(new_buffer_text, '\n')
        )
      end
    end
  end,
}

return tool
