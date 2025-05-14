---@type FakeToolDefinition
local tool = {
  is_fake = true,
  name = 'editor',
  system_prompt = vim.trim(--[[ markdown ]] [[
# Special Editor syntax
You can use this syntax to apply changes directly in the code base.

- You can use this syntax to replace sections in project files.
- Make sure the original content is unique in the file to prevent unintended replacements.
- MAKE SURE TO ALWAYS USE REPLACEMENTS FOR EDITS. AVOID REPEATING THE WHOLE FILE CONTENT.

Follow the syntax VERY CLOSELY:

`````<language> <path-relative-to-project-root> - Start of the code block. Specify the language and the file. USE FIVE INSTEAD OF THREE TICKS to avoid conflicts with triple ticks inside the block. THE FILE PATH HAS TO BE DEFINED IN THE SAME LINE!
<<<<<<< ORIGINAL - Marks the start of the original content block.
<original-code> - The EXACT code to replace. MAKE SURE THE SECTION IS UNIQUE BY REPEATING A LARGE ENOUGH SECTION! NEVER LEAVE THIS BLOCK EMPTY IF THE FILE IS NOT EMPTY.
======= - Marks the separator between old and new content.
<code-to-replace-original-code> - The updated code. NEVER USE PLACEHOLDERS LIKE "...", "// Other Methods", etc. IN THE CODE, INSTEAD PROVIDE THE FULL UPDATED CODE.
>>>>>>> UPDATED - Marks the end the new content declaration.
`````

- The markers HAVE TO BE USED IN THE EXACT ORDER
- Never add content between the markers
- Plan and reason about your changes before doing them.
  Always consider all changes that might need to be done as an effect of the request.
  Make your thought process transparent and ask the user questions if something is not clear.

## Examples
For the following examples, expect the following files to exist:

`````typescript src/utils/array.ts
export function deleteAll<T>(
  array: T[],
  toDelete: T[],
  getId: (item: T) => string | number
): T[] {
  array = array.slice();
  toDelete.forEach(elementToDelete => {
    const idToDelete = getId(elementToDelete);
    const index = array.findIndex(element => idToDelete === getId(element));
    array.splice(index, 1);
  });
  return array;
}

export function setAt<T>(array: T[], i: number, value: T): T[] {
  array = array.slice();
  array[i] = value;
  return array;
}

export function arrayToMap<T, K extends keyof any>(
  array: T[],
  getKey: (t: T) => K
): Record<K, T> {
  const result = {} as Record<K, T>;
  array.forEach(value => {
    result[getKey(value)] = value;
  });
  return result;
}

export function arrayToArrayMap<T, K extends keyof any>(
  array: T[],
  getKey: (t: T) => K
): Record<K, T[]> {
  const result = {} as Record<K, T[]>;
  array.forEach(value => {
    const key = getKey(value);
    if (!result[key]) {
      result[key] = [];
    }

    result[key].push(value);
  });
  return result;
}
`````

### Example 1
#### User
Add a new flatMap function

#### Assistant
Sure! Let me think about the steps:

1) Based on the given name and common practices, I think the `flatMap` function should map a given list of items and flattens the output
2) I will use generics to make the new function reusable. I will use `T` for the incoming array and `R` (like Result) for the outgoing array items.
3) I could implement it by combining the `map` and `flat` function.
   But as the user seems to use a more restricted browser environment in which `flat` might not be available I will fallback to a for loop.
   A for loop is appropriate as it reduces the memory overhead.
4) I will add the new function under the `arrayToArrayMap` function.

`````typescript src/utils/array.ts
<<<<<<< ORIGINAL
export function arrayToArrayMap<T, K extends keyof any>(
  array: T[],
  getKey: (t: T) => K
): Record<K, T[]> {
  const result = {} as Record<K, T[]>;
  array.forEach(value => {
    const key = getKey(value);
    if (!result[key]) {
      result[key] = [];
    }

    result[key].push(value);
  });
  return result;
}
=======
export function arrayToArrayMap<T, K extends keyof any>(
  array: T[],
  getKey: (t: T) => K
): Record<K, T[]> {
  const result = {} as Record<K, T[]>;
  array.forEach(value => {
    const key = getKey(value);
    if (!result[key]) {
      result[key] = [];
    }

    result[key].push(value);
  });
  return result;
}

export function flatMap<T, R>(array: T[], map: (value: T) => R | R[]): R[] {
  const result: R[] = [];
  for (const value of array) {
    const mapped = map(value);
    if (Array.isArray(mapped)) {
      result.push(...mapped);
    } else {
      result.push(mapped);
    }
  }
  return result;
}
>>>>>>> UPDATED
`````

Much better 💪

Please consider that `flatMap` is builtin in newer browser versions and you don't need to implement it yourself.

### Example 2
#### User
Move the `setAt` function to a new file

#### Assistant
Should I do a reexport of `setAt` to prevent a breaking change?

#### User
y

#### Assistant
Sure! I will do the following:

1) Create a new file `src/utils/setAt.ts` and move `setAt` into it.
2) Replace `setAt` in `src/utils/array.ts` with an reexport of the new file to prevent a breaking change.

`````typescript src/utils/setAt.ts
<<<<<<< ORIGINAL
=======
export function setAt<T>(array: T[], i: number, value: T): T[] {
  array = array.slice();
  array[i] = value;
  return array;
}
>>>>>>> UPDATED
`````

`````typescript src/utils/array.ts
<<<<<<< ORIGINAL
export function setAt<T>(array: T[], i: number, value: T): T[] {
  array = array.slice();
  array[i] = value;
  return array;
}
=======
export * from './setAt';
>>>>>>> UPDATED
`````

Here we go ✨

To stay consistent I would recommend moving the other functions as well.
1) Move `deleteAll` to `src/utils/deleteAll.ts`
2) Move `arrayToMap` to `src/utils/arrayToMap.ts`
3) Move `arrayToArrayMap` to `src/utils/arrayToArrayMap.ts`

### Example 3
#### User
Please replace all `forEach` loops with `for..of` loops

#### Assistant
Good idea! Using a `for..of` loop can be more performant.

1) I will replace all occurrences of `forEach` with `for..of`
2) I will make sure that each replacement is unique to avoid unintended changes

`````typescript src/utils/array.ts
<<<<<<< ORIGINAL
  toDelete.forEach(elementToDelete => {
    const idToDelete = getId(elementToDelete);
    const index = array.findIndex(element => idToDelete === getId(element));
    array.splice(index, 1);
  });
=======
>>>>>>> UPDATED
  for (const elementToDelete of toDelete) {
    const idToDelete = getId(elementToDelete);
    const index = array.findIndex(element => idToDelete === getId(element));
    array.splice(index, 1);
  }
`````

`````typescript src/utils/array.ts
<<<<<<< ORIGINAL
  array.forEach(value => {
    result[getKey(value)] = value;
  });
=======
>>>>>>> UPDATED
  for (const value of array) {
    result[getKey(value)] = value;
  }
`````

`````typescript src/utils/array.ts
<<<<<<< ORIGINAL
  array.forEach(value => {
    const key = getKey(value);
    if (!result[key]) {
      result[key] = [];
    }

    result[key].push(value);
  });
=======
>>>>>>> UPDATED
  for (const value of array) {
    const key = getKey(value);
    if (!result[key]) {
      result[key] = [];
    }

    result[key].push(value);
  }
`````

Blazingly fast! 🚀

Do you like me to do one of the following other optimizations?
1) Replace the nested loop in `deleteAll`
2) ...

---

DO NOT TAKE THE EXAMPLE FILES ABOVE INTO ACCOUNT FROM THIS POINT ON!
]]),

  reminder_prompt = vim.trim(--[[ markdown ]] [[
## Editor
Use the editor syntax for all edits like this:

`````typescript src/hello.ts
<<<<<<< ORIGINAL
  console.log('Hello World')
=======
  const fullName = `${firstName} ${lastName}`;
  console.log(`Hello ${fullName}`);
>>>>>>> UPDATED
`````

Remember that you HAVE to use the markers.

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
          (#match? @info "^.+\\s+.+$")
          (code_fence_content) @code)+
      )
      ]]
    )

    local calls = {}
    local current_call = nil

    local tree = parser:parse()[1]
    for id, node, metadata in query:iter_captures(tree:root(), message_content) do
      local capture_name = query.captures[id]
      local text = vim.treesitter.get_node_text(node, message_content)

      if capture_name == 'info' then
        local file = text:gsub('^.+%s+(.+)$', '%1')
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

    -- Create groups while keeping original order
    local groups = {}
    for _, call in ipairs(calls) do
      local file = call.file
      if calls_grouped_by_file[file] then
        table.insert(
          groups,
          { file = file, calls = calls_grouped_by_file[file] }
        )
        calls_grouped_by_file[file] = nil
      end
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
          if vim.trim(rep.search) == '' then
            if vim.trim(new_buffer_text) == '' then
              new_buffer_text = rep.replacement
            else
              new_buffer_text = new_buffer_text .. '\n' .. rep.replacement
            end
          else
            local search = rep.search:gsub('%W', '%%%1')
            local replacement = rep.replacement:gsub('%%', '%%%%')
            new_buffer_text = new_buffer_text:gsub(search, replacement)
          end
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
