---@type VariableDefinition
return {
  name = 'sh',
  resolve = function(_ctx, params)
    if not params or #params < 1 then
      error(
        "The '#sh' variable requires a shell command as the first parameter."
      )
    end

    local shell_command = params[1]

    local handle = io.popen(shell_command)
    if not handle then
      error('Could not execute shell command: ' .. shell_command)
    end

    local result = handle:read('*all')
    handle:close()

    return string.format(
      vim.trim([[
Variable: #sh - Contains the output of the specified shell command with cwd as the project root.
Command: %s
```
%s
```
]]),
      shell_command,
      result
    )
  end,
}
