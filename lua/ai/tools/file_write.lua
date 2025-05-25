local Strings = require('ai.utils.strings')

---@type ToolDefinition
local tool = {
  definition = {
    name = 'file_write',
    description = vim.trim([[
Write content to a specific file.
Please note that this will override any existing content in the file, so this tool is not suitable for modifying files.
If you want to modify files, use the "file_patch" tool instead.
Use this tool if you need to create new files or are sure you want to override an existing file.
    ]]),
    parameters = {
      type = 'object',
      required = { 'path', 'content' },
      properties = {
        path = {
          type = 'string',
          description = 'The relative path to the file from the project root',
          example = 'src/index.ts',
        },
        content = {
          type = 'string',
          description = 'The content to write to the file',
          example = 'export function main() {\n  console.log("Hello World");\n}',
        },
      },
    },
  },
  execute = function(params, callback)
    vim.notify('file_write: ' .. vim.inspect(params))
    callback('Write succesful')
  end,
  render = function(tool_call)
    local result = Strings.replace_placeholders(
      vim.trim([[
```lua {{path}} (File Write)
{{content}}
```
      ]]),
      tool_call.params or {}
    )
    return vim.split(result, '\n')
  end,
}
return tool
