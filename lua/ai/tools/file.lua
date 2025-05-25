---@type ToolDefinition
local tool = {
  definition = {
    name = 'file',
    description = vim.trim([[
Use this tool to request access to the content of a specific file.

The file path should be relative to the project root.
    ]]),
    parameters = {
      type = 'object',
      required = { 'path' },
      properties = {
        path = {
          type = 'string',
          description = 'The relative path to the file from the project root',
        },
      },
    },
  },
  execute = function(ctx, params, callback)
    if not params then
      local error = 'Tool (file): Missing parameter'
      vim.notify(error, vim.log.levels.ERROR)
      return callback('Error: ' .. error)
    end
    if not params.path then
      local error = 'Tool (file): Missing path parameter'
      vim.notify(error, vim.log.levels.ERROR)
      return callback('Error: ' .. error)
    end

    -- Read the file content
    local file_path = vim.fn.getcwd() .. '/' .. params.path
    local file = io.open(file_path, 'r')

    if not file then
      local error = 'Tool (file): Could not open file at path: ' .. file_path
      vim.notify(error, vim.log.levels.ERROR)
      return callback('Error: ' .. error)
    end

    local content = file:read('*a')
    file:close()

    callback(content)
  end,
}
return tool
