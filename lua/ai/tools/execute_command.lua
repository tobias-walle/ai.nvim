local M = {}

local Messages = require('ai.utils.messages')
local Strings = require('ai.utils.strings')

function M.create_execute_command_tool()
  ---@type ai.ToolDefinition
  local tool = {
    definition = {
      name = 'execute_command',
      description = vim.trim([[
Run a shell command using bash.
Use this tool to execute CLI commands for tasks for which you don't have a specialized tool for.

You can expect all core utils to be installed. And other modern tools like `rg`, `fd`, etc.
]]),
      parameters = {
        type = 'object',
        required = { 'command' },
        properties = {
          command = {
            type = 'string',
            description = 'The shell command to execute. It will be run with bash -c.',
            example = 'ls -la',
          },
        },
      },
    },
    execute = function(params, callback)
      local command = params.command
      assert(type(command) == 'string', 'execute_command: Invalid parameters')
      -- Ask for user confirmation before executing
      vim.schedule(function()
        vim.ui.input({
          prompt = 'Execute command: ' .. command .. ' ? Type y to confirm: ',
        }, function(input)
          if input == nil or (input ~= 'y' and input ~= 'Y') then
            callback({
              result = vim.json.encode({
                error = 'Command execution denied by user. Reason: ' .. input,
              }),
            })
            return
          end
          local cmd = 'bash'
          local args = { '-c', command }
          vim.system(
            vim.iter({ cmd, args }):flatten():totable(),
            { text = true, timeout = 10000 },
            function(obj)
              local result = {
                stdout = obj.stdout,
                stderr = obj.stderr,
                code = obj.code,
              }
              vim.schedule(function()
                callback({ result = vim.json.encode(result) })
              end)
            end
          )
        end)
      end)
    end,
    render = function(tool_call, tool_call_result)
      local lines = {}
      local command = tool_call.params and tool_call.params.command or ''
      local result = tool_call_result
        and tool_call_result.result
        and vim.json.decode(Messages.extract_text(tool_call_result.result))

      table.insert(lines, '`````bash')
      vim.list_extend(
        lines,
        vim.split('> ' .. vim.trim(command), '\n', { plain = true })
      )

      if result then
        if result.error then
          table.insert(lines, '❌ Error: ' .. result.error)
        else
          local output = (result.stdout and #result.stdout > 0)
              and result.stdout
            or result.stderr
            or ''
          vim.list_extend(
            lines,
            vim.split(
              Strings.strip_ansi_codes(vim.trim(output)),
              '\n',
              { plain = true }
            )
          )
        end
      else
        table.insert(lines, '⏳ Running command...')
      end

      table.insert(lines, '`````')
      return lines
    end,
  }
  return tool
end

return M
