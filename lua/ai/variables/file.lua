---@type VariableDefinition
return {
  name = 'file',
  min_params = 1,
  max_params = 1,
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
  cmp_items = function(cmp_ctx, callback)
    --- @type lsp.CompletionItem[]
    local items = {}
    local base_path = vim.fn.getcwd()
    vim.system(
      { 'fd', '--type', 'f', '--full-path', base_path },
      {},
      function(result)
        local stdout = result.stdout or ''
        local paths = {}
        for _, line in ipairs(vim.split(stdout, '\n')) do
          line = vim.trim(line)
          if line ~= '' then
            table.insert(paths, line)
          end
        end

        for _, relative_path in ipairs(paths) do
          table.insert(items, {
            label = '#file:`' .. relative_path .. '`',
            kind = require('blink.cmp.types').CompletionItemKind.File,
            documentation = 'File: ' .. relative_path,
          })
        end

        callback(items)
      end
    )
  end,
}
