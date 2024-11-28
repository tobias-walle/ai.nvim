---@type VariableDefinition
return {
  name = 'files',
  resolve = function(_ctx, params)
    -- Get the folder path from params, default to current directory if not provided
    local folder_path = params and params[1] or '.'

    -- Read the .ignore file and prepare the ignore pattern
    local ignore_file = io.open('.ignore', 'r')
    local ignore_pattern = ''
    if ignore_file then
      ignore_pattern = ignore_file:read('*all'):gsub('\n', '|')
      ignore_file:close()
    end

    -- Get the folders with eza
    local result = vim
      .system({ 'eza', '-I', ignore_pattern, '-R', folder_path })
      :wait().stdout

    -- Return the result as a formatted string
    return string.format(
      vim.trim([[
Variable: #files - Contains the list of files in the specified folder.
Folder: %s
```
%s
```
]]),
      folder_path,
      result
    )
  end,
}
