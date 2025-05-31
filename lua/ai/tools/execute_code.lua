local M = {}

local Messages = require('ai.utils.messages')

---@class ai.ExecuteCodeTool.Params
---@field language 'javascript_node' | 'lua_neovim' | 'python'
---@field code string

---@return ai.ToolDefinition
function M.create_execute_code_tool()
  ---@type ai.ToolDefinition
  local tool = {
    definition = {
      name = 'execute_code',
      description = vim.trim([[
Run code in the specified language and runtime.
Use this tool to perform calculations, count items, or test code snippets.
Only standard language features are allowed.
Do not import any external libraries or dependencies.
After the code was run, you will get the stdout and stderr as a result.
]]),
      parameters = {
        type = 'object',
        required = { 'language', 'code' },
        properties = {
          language = {
            type = 'string',
            enum = { 'javascript_node', 'lua_neovim', 'python' },
            description = 'The language to execute the code in. Must be one of: javascript_node, lua_neovim, python.',
            example = 'python',
          },
          code = {
            type = 'string',
            description = 'The code to execute. Only use standard language features, no external libraries. The code can span multiple lines. Print all results you are interested in.',
            example = 'print(1 + 1)',
          },
        },
      },
    },
    execute = function(params, callback)
      local language = params.language
      local code = params.code
      assert(
        type(language) == 'string' and type(code) == 'string',
        'execute_code: Invalid parameters'
      )
      local cmd, args
      if language == 'python' then
        cmd = 'python'
        args = { '-c', code }
      elseif language == 'javascript_node' then
        cmd = 'node'
        args = { '-e', code }
      elseif language == 'lua_neovim' then
        cmd = 'nvim'
        args = { '--headless', '-c', 'lua ' .. code, '+qall' }
      else
        callback({
          result = vim.json.encode({
            error = 'Unsupported language: ' .. language,
          }),
        })
        return
      end
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
    end,
    render = function(tool_call, tool_call_result)
      local lines = {}
      local language = tool_call.params and tool_call.params.language or ''
      local markdown_block_language = language == 'javascript_node'
          and 'javascript'
        or language == 'lua_neovim' and 'lua'
        or language == 'python' and 'python'
        or language
      local code = tool_call.params and tool_call.params.code or ''
      local result = tool_call_result
        and tool_call_result.result
        and vim.json.decode(Messages.extract_text(tool_call_result.result))

      table.insert(lines, '`````' .. markdown_block_language)
      vim.list_extend(lines, vim.split(vim.trim(code), '\n', { plain = true }))
      table.insert(lines, '`````')
      table.insert(lines, '')

      if result then
        table.insert(lines, 'Output:')
        if result.error then
          table.insert(lines, '`````')
          table.insert(lines, '❌ Error: ' .. result.error)
          table.insert(lines, '`````')
          return lines
        end
        local output = (result.stdout and #result.stdout > 0) and result.stdout
          or result.stderr
          or ''
        table.insert(lines, '`````')
        vim.list_extend(
          lines,
          vim.split(vim.trim(output), '\n', { plain = true })
        )
        table.insert(lines, '`````')
        return lines
      else
        return lines
      end
    end,
  }
  return tool
end

return M
