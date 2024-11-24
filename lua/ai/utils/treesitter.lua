local M = {}

---Extracts a single code block from a markdown string using Tree-sitter.
---@param markdown_content string The markdown content to parse.
---@return string|nil The extracted code from the code block, or nil if no code block is found.
function M.extract_code(markdown_content)
  -- Add newline at the end to prevent parsing errors
  markdown_content = markdown_content .. '\n'
  -- Get the parser for markdown
  local parser = vim.treesitter.get_string_parser(markdown_content, 'markdown')
  local tree = parser:parse()[1]
  local root = tree:root()

  -- Define a query to find code blocks
  local query = vim.treesitter.query.parse(
    'markdown',
    [[
    (
      (fenced_code_block
        (code_fence_content) @code
      )
    )
    ]]
  )

  -- Iterate over the captures and extract the first code block
  for id, node in query:iter_captures(root, markdown_content, 0, -1) do
    if query.captures[id] == 'code' then
      local text = vim.treesitter.get_node_text(node, markdown_content)
      return text
    end
  end
  return nil
end

return M
