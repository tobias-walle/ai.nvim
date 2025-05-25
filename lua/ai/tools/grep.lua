---@type ToolDefinition
local tool = {
  definition = {
    name = 'grep',
    description = vim.trim([[
Use this tool to find relevant files using a grep search.

1. First a git grep search will be performed (git grep --show-function <search>)
2. If the result is too big, a ripgrep search will be performed, to only get the filenames (rg --smart-case --files-with-matches <search>)

Keep the search term generic enough to get matches.

## Examples
Prompt: Add a service to talk with openai.

Search 1: [Ss]ervice
Reasoning: Search for other services to figure out general structure

Search 2: [Oo]penai
Reasoning: Find out if relevant code already exists
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

    local command = {
      'git',
      'grep',
      '--show-function',
      '--break',
      '--line-number',
      '--heading',
      params.search,
    }

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
