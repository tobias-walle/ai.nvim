local M = {}

---@class MarkdownCodeBlock
---@field file? string
---@field language? string
---@field lines string[]
---@field code string

---Extracts code blocks from a markdown string.
---@param markdown_content string The markdown content to parse.
---@return MarkdownCodeBlock[] List of { file = string|nil, code = string } blocks.
function M.extract_code(markdown_content)
  local blocks = {}
  local n_ticks = 3

  ---@type MarkdownCodeBlock | nil
  local current_block
  local add_block = function()
    if current_block then
      current_block.code = table.concat(current_block.lines, '\n')
      table.insert(blocks, current_block)
      current_block = nil
    end
  end

  for _, line in ipairs(vim.split(markdown_content, '\n')) do
    if not current_block then
      local ticks, language, file = line:match('^(```+)([^%s]*)%s*(.*)$')
      if ticks then
        n_ticks = #ticks
        current_block = {
          language = language ~= '' and language or nil,
          file = file ~= '' and file or nil,
          lines = {},
          code = '',
        }
      end
    else
      if line:match('^' .. string.rep('`', n_ticks, '')) then
        add_block()
      else
        table.insert(current_block.lines, line)
      end
    end
  end

  add_block()
  return blocks
end

return M
