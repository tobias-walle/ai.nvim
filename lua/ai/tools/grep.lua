---@type RealToolDefinition
local tool = {
  definition = {
    name = 'grep',
    description = vim.trim([[
Use this tool to find files using a ripgrep search.

The command will be: rg --smart-case --heading <search>

Usecases:
- You need to find relevant files in the project
    ]]),
    parameters = {
      type = 'object',
      required = { 'search' },
      properties = {
        search = {
          type = 'string',
          description = 'The search pattern you want to look for in the codebase',
        },
      },
    },
  },
  execute = function(ctx, params, callback)
    if not params then
      local error = 'Tool (grep): Missing parameter'
      vim.notify(error, vim.log.levels.ERROR)
      return callback('Error: ' .. error)
    end
    if not params.search then
      local error = 'Tool (grep): Missing search parameter'
      vim.notify(error, vim.log.levels.ERROR)
      return callback('Error: ' .. error)
    end

    local command = { 'rg', '--smart-case', '--heading', params.search }

    vim.system(
      command,
      {},
      vim.schedule_wrap(function(obj)
        if obj.code ~= 0 then
          local error = 'Tool (grep): Ripgrep search failed: '
            .. (obj.stderr or 'Unknown error')
          vim.notify(error, vim.log.levels.ERROR)
          return callback(error)
        end

        local output = obj.stdout
        local lines = vim.split(output, '\n')

        -- If output is too large, do a file-only search
        if #lines > 1000 then
          vim.system(
            { 'rg', '--smart-case', '--files-with-matches', params.search },
            {},
            vim.schedule_wrap(function(file_obj)
              if file_obj.code ~= 0 then
                local error = 'Tool (grep): File-only search failed: '
                  .. (file_obj.stderr or 'Unknown error')
                vim.notify(error, vim.log.levels.ERROR)
                return callback(error)
              end
              callback(file_obj.stdout)
            end)
          )
        else
          callback(output)
        end
      end)
    )
  end,
}
return tool
