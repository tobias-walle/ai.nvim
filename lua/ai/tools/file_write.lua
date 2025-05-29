local M = {}

local Strings = require('ai.utils.strings')

---@class ai.FileWriteTool.Options
---@field editor ai.Editor

---@param opts ai.FileWriteTool.Options
---@return ai.ToolDefinition
function M.create_file_write_tool(opts)
  local editor = opts.editor
  ---@type ai.ToolDefinition
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
      local path = params.path
      local content = params.content

      assert(
        type(path) == 'string' and type(content) == 'string',
        'file_write: Invalid parameters'
      )

      local bufnr = editor:add_file_patch({
        file = path,
        patch = content,
      })
      editor:subscribe(bufnr, function(job)
        if job.apply_result == 'ACCEPTED' then
          callback({
            result = 'The change was accepted. The file now contains the suggested changes.',
          })
        elseif job.apply_result == 'REJECTED' then
          callback({
            result = "The change was rejected by the user. Probably because he didn't aggree with it. The file was NOT updated",
          })
        end
      end)
    end,
    render = function(tool_call)
      local path = tool_call.params and tool_call.params.path or ''
      local content = tool_call.params and tool_call.params.content or ''
      local lang = 'text'
      local ext = vim.fn.fnamemodify(path, ':e')
      if ext ~= '' then
        lang = vim.filetype.match({ filename = path }) or ext
      end
      local result = Strings.replace_placeholders(
        vim.trim('```' .. lang .. ' {{path}} (File Write)\n{{content}}\n```'),
        { path = path, content = content }
      )
      return vim.split(result, '\n')
    end,
  }
  return tool
end

return M
