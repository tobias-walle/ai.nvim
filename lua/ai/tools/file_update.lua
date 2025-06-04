local M = {}

local Strings = require('ai.utils.strings')
local Buffers = require('ai.utils.buffers')

---@class ai.FileUpdateTool.Options
---@field editor ai.Editor

---@param opts ai.FileUpdateTool.Options
---@return ai.ToolDefinition
function M.create_file_update_tool(opts)
  local editor = opts.editor
  ---@type ai.ToolDefinition
  local tool = {
    definition = {
      name = 'file_update',
      description = vim.trim([[
Update an existing file in an efficient way. Only write the parts of the file that have changed.
Use this tool over 'file_write' if the file already exists.
    ]]),
      parameters = {
        type = 'object',
        required = { 'file', 'update' },
        properties = {
          file = {
            type = 'string',
            description = 'The relative path to the file from the project root',
            example = 'src/index.ts',
          },
          update = {
            type = 'string',
            description = vim.trim([[
The update to apply to the file.

When creating the update, follow these format requirements:
1. Output only the code that should change.
2. Use the code comment "... existing code ..." to indicate unchanged sections of code.
3. Always use the correct comment syntax for the specific language provided (e.g., "// ... existing code ..." for C-style languages, "# ... existing code ..." for Python, "-- ... existing code ..." for Lua, etc.).

To create the update:
1. Analyze the provided code and identify the sections that need to be changed.
2. Write out the modified code sections, using the appropriate comment syntax to indicate unchanged parts.
3. Ensure that you're only outputting the necessary changes and using the "... existing code ..." comment for parts that remain the same. Use this feature aggressively to save output tokens and time!

It is CRUCIAL that you add the "... existing code ..." comments! Also add them to the start and end of the file if you are omitting something there.

Remember, the purpose of this update is to guide a small language model in modifying the existing code.
The model will replace the "... existing code ..." sections with the original code.
Therefore, focus only on the changes that need to be made and use the comment syntax to preserve the overall structure of the code.
            ]]),
            example = vim.trim([[
// ... existing code ...

export interface EventsApi {
  // ... existing code ...
  updateEvents(events: EventInput[]): Promise<void>;
}

function createEventsApi(client: Client): EventsApi {
    // ... existing code ...
    updateEvents: (events) => client.update('events', { json: events }).json(),
    // ... existing code ...
}

// ... existing code ...
            ]]),
          },
        },
      },
    },
    execute = function(params, callback)
      local file = params.file
      local update = params.update

      assert(
        type(file) == 'string' and type(update) == 'string',
        'file_update: Invalid parameters'
      )

      local bufnr = editor:add_patch({
        bufnr = file,
        patch = update,
      })
      editor:subscribe(bufnr, function(job)
        if job.apply_result == 'ACCEPTED' then
          callback({
            result = 'The change was accepted. The file now contains the suggested changes.',
          })
        elseif job.apply_result == 'REJECTED' then
          callback({
            result = "The change was rejected by the user. Probably because he didn't aggree with it. Do not try to write this file again.",
          })
        end
      end)
    end,
    render = function(tool_call)
      local file = tool_call.params and tool_call.params.file or ''
      local update = tool_call.params and tool_call.params.update or ''
      local lang = 'text'
      local ext = vim.fn.fnamemodify(file, ':e')
      if ext ~= '' then
        lang = vim.filetype.match({ filename = file }) or ext
      end
      local result = Strings.replace_placeholders(
        vim.trim(
          '`````' .. lang .. ' {{file}} (File Update)\n{{update}}\n`````'
        ),
        { file = file, update = update }
      )
      return vim.split(result, '\n')
    end,
  }
  return tool
end

return M
