local M = {}

---Render a tool and it's result (if any) to text
---@param tool RealToolCall
---@return string|nil
function M.render(tool)
  local lines = {}

  -- Render tool header
  table.insert(lines, string.format('#### %s (%s)', tool.tool, tool.id))

  -- Render params or loading state
  if tool.params and next(tool.params) ~= nil then
    for key, value in pairs(tool.params) do
      local formatted_value = type(value) == 'string'
          and string.format('"%s"', value)
        or tostring(value)
      table.insert(lines, string.format('%s: %s', key, formatted_value))
    end
  elseif tool.is_loading then
    table.insert(lines, '...')
  end

  -- Add empty line before result
  table.insert(lines, '')

  -- Render result or loading state
  if tool.result then
    table.insert(lines, '```result')
    table.insert(lines, tool.result)
    table.insert(lines, '```')
  elseif tool.is_loading and tool.params then
    table.insert(lines, '```result')
    table.insert(lines, '...')
    table.insert(lines, '```')
  end

  return table.concat(lines, '\n')
end

---Parse all rendered tool calls out of a buffer
---@param content string
---@return RealToolCall[], string
function M.parse(content)
  -- Add newline to prevent parsing errors
  content = content .. '\n'
  local lines = vim.split(content, '\n')

  local parser = vim.treesitter.get_string_parser(content, 'markdown')

  -- Query to match our tool format
  local query = vim.treesitter.query.parse(
    'markdown',
    [[
    (
      section
      (atx_heading
        (atx_h4_marker)
        (inline) @tool_header
      )
      (paragraph) @params
      (fenced_code_block
        (fenced_code_block_delimiter)
        (info_string) @result_marker
        (code_fence_content) @result
      )? @result_code_block
    )
    ]]
  )

  ---@type string[]
  local content_without_tool_calls_lines = {}
  local previous_row_end = 1

  ---@type RealToolCall[]
  local tool_calls = {}
  ---@type RealToolCall| nil
  local current_tool = nil

  for _, match, _ in query:iter_matches(parser:parse()[1]:root(), content) do
    for id, node in pairs(match) do
      local text = vim.treesitter.get_node_text(node, content)
      local capture_name = query.captures[id]

      if capture_name == 'tool_header' then
        -- Extract tool name and id from header
        local tool_name, tool_id = text:match('([^%(]+)%s*%(([^%)]+)%)')
        if tool_name and tool_id then
          current_tool = {
            tool = vim.trim(tool_name),
            id = vim.trim(tool_id),
            is_loading = false,
          }
          table.insert(tool_calls, current_tool)
        end
      elseif capture_name == 'params' and current_tool then
        if vim.trim(text) == '...' then
          current_tool.is_loading = true
        else
          -- Parse params
          current_tool.params = {}
          for line in text:gmatch('[^\n]+') do
            local key, value = line:match('([^:]+):%s*(.+)')
            if key and value then
              key = vim.trim(key)
              value = vim.trim(value)
              -- Convert value to appropriate type
              if value:match('^".*"$') then
                value = value:sub(2, -2) -- Remove quotes
              elseif value == 'true' then
                value = true
              elseif value == 'false' then
                value = false
              elseif tonumber(value) then
                value = tonumber(value)
              end
              current_tool.params[key] = value
            end
          end
        end
      elseif capture_name == 'result' and current_tool then
        if vim.trim(text) == '...' then
          current_tool.is_loading = true
        else
          current_tool.result = vim.trim(text)
        end
      end
    end

    local start_row, _, _, _ = vim.treesitter.get_node_range(match[1])
    local _, _, end_row, _ = vim.treesitter.get_node_range(match[#match])
    for row = previous_row_end, start_row, 1 do
      local current_line_value = vim.trim(lines[row])
      local previous_line =
        content_without_tool_calls_lines[#content_without_tool_calls_lines]
      if
        previous_line ~= nil
        and previous_line == ''
        and current_line_value == ''
      then
        -- Skip empty lines if they follow each other
      else
        table.insert(content_without_tool_calls_lines, current_line_value)
      end
    end
    previous_row_end = end_row + 1
  end

  local content_without_tool_calls =
    vim.fn.join(content_without_tool_calls_lines, '\n')
  return tool_calls, content_without_tool_calls
end

return M
