---@type VariableDefinition
return {
  name = 'file',
  resolve = function(_ctx, params)
    -- Ensure params is provided and has at least one element
    if not params or #params < 1 then
      error("The '#file' variable requires a file path as the first parameter.")
    end

    -- Get the file path from params
    local file_path = params[1]

    -- Read the file content
    local file = io.open(file_path, 'r')
    if not file then
      error('Could not open file: ' .. file_path)
    end

    local text = file:read('*all')
    file:close()

    -- Get the filetype based on the file extension
    local ft = vim.fn.fnamemodify(file_path, ':e')

    return string.format(
      vim.trim([[
Variable: #file - Contains the content of the specified file.
FILE: %s
```%s
%s
```
]]),
      file_path,
      ft,
      text
    )
  end,
}
