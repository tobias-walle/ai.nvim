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
  cmp_source = function()
    local S = {}

    local cmp = require('cmp')

    S.new = function()
      return setmetatable({}, { __index = S })
    end

    function S:get_keyword_pattern()
      return [[#file:\S\+]]
    end

    function S:complete(request, callback)
      local items = {}
      local base_path = vim.fn.getcwd()

      local text = request.context.cursor_line or ''
      local search = text:gsub('#file:?', '')

      if search == '' then
        return {}
      end

      -- Add .* between each char of search
      local pattern = search:gsub('(.)', '%1.*')
      local paths = {}
      local stdout = vim
        .system({ 'fd', '--type', 'f', '--full-path', pattern, base_path })
        :wait().stdout or ''
      for _, line in ipairs(vim.split(stdout, '\n')) do
        table.insert(paths, line:sub(#base_path + 2)) -- make relative
      end

      for _, relative_path in ipairs(paths) do
        table.insert(items, {
          label = '#file:`' .. relative_path .. '`',
          kind = cmp.lsp.CompletionItemKind.File,
          documentation = 'File: ' .. relative_path,
        })
      end

      callback({ items = items, isIncomplete = true })
    end

    function S:get_debug_name()
      return 'ai-variable-file'
    end

    return S
  end,
}
