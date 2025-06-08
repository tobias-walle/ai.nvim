local M = {}

local Messages = require('ai.utils.messages')

---@class ai.SearchTool.Params
---@field query string
---@field path? string

---@return ai.ToolDefinition
function M.create_search_tool()
  ---@type ai.ToolDefinition
  local tool = {
    definition = {
      name = 'search',
      description = vim.trim(
        [[Search for a pattern in files using ripgrep (rg). The result will be the stdout or stderr of ripgrep.]]
      ),
      parameters = {
        type = 'object',
        required = { 'query' },
        properties = {
          query = {
            type = 'string',
            description = 'The search regex pattern to look for',
            example = '([Hh]ello)|([Ww]orld)',
          },
          path = {
            type = 'string',
            description = 'Optional path to search in (relative to project root)',
            example = 'src/',
          },
        },
      },
    },
    execute = function(params, callback)
      local query = params.query
      local path = params.path or '.'
      assert(type(query) == 'string', 'search: Invalid parameters')
      local args = { query, path }
      local json_args = vim.deepcopy(args)
      table.insert(json_args, 1, '--json')
      vim.system(
        { 'rg', unpack(json_args) },
        { text = true },
        function(json_obj)
          local count = 0
          if json_obj.code == 0 or json_obj.code == 1 then
            count = #vim.split(json_obj.stdout, '\n', { trimempty = true })
          end
          vim.system({ 'rg', unpack(args) }, { text = true }, function(obj)
            local result = {
              count = count,
              stdout = obj.stdout,
              stderr = obj.stderr,
              code = obj.code,
            }
            vim.schedule(function()
              callback({ result = vim.json.encode(result) })
            end)
          end)
        end
      )
    end,
    render = function(tool_call, tool_call_result)
      local query = tool_call.params and tool_call.params.query or ''
      local path = tool_call.params and tool_call.params.path or '.'
      local ok, result = pcall(function()
        return tool_call_result
          and tool_call_result.result
          and vim.json.decode(Messages.extract_text(tool_call_result.result))
      end)
      if ok and result then
        local count = result.count or 0
        return {
          '🔍 Searched `'
            .. query
            .. '` in `'
            .. path
            .. '` ('
            .. count
            .. ' results)',
        }
      else
        return { '⏳ Searching `' .. query .. '` in `' .. path .. '`' }
      end
    end,
  }
  return tool
end

return M
