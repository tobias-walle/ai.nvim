local M = {}

---Decode partial json values and add missing closing brackets and quotes if necessary
---@param str string | nil
---@return any | nil
function M.decode_partial(str)
  if not str or str == '' then
    return nil
  end

  -- Remove leading/trailing whitespace
  str = vim.trim(str)

  -- Track opening characters that need closing
  local stack = {}
  local in_string = false
  local escaped = false
  local i = 1

  while i <= #str do
    local char = str:sub(i, i)

    if escaped then
      escaped = false
    elseif char == '\\' and in_string then
      escaped = true
    elseif char == '"' then
      if in_string then
        -- Closing quote
        in_string = false
        -- Remove the opening quote from stack
        if #stack > 0 and stack[#stack] == '"' then
          table.remove(stack)
        end
      else
        -- Opening quote
        in_string = true
        table.insert(stack, '"')
      end
    elseif not in_string then
      if char == '{' then
        table.insert(stack, '{')
      elseif char == '[' then
        table.insert(stack, '[')
      elseif char == '}' then
        -- Remove matching opening brace from stack
        for j = #stack, 1, -1 do
          if stack[j] == '{' then
            table.remove(stack, j)
            break
          end
        end
      elseif char == ']' then
        -- Remove matching opening bracket from stack
        for j = #stack, 1, -1 do
          if stack[j] == '[' then
            table.remove(stack, j)
            break
          end
        end
      end
    end

    i = i + 1
  end

  -- Remove trailing commas (but not inside strings)
  local cleaned = str:gsub(',%s*([%]}])', '%1')

  -- Add missing closing characters
  local result = cleaned
  for i = #stack, 1, -1 do
    local opener = stack[i]
    if opener == '{' then
      result = result .. '}'
    elseif opener == '[' then
      result = result .. ']'
    elseif opener == '"' then
      result = result .. '"'
    end
  end

  -- Try to decode the fixed JSON
  local success, decoded = pcall(vim.json.decode, result)
  if success then
    return decoded
  end

  -- If it still fails, return nil
  return nil
end

return M
