local M = {}

---@param content ai.AdapterMessageContent
---@return string
function M.extract_text(content)
  if type(content) == 'string' then
    return content
  else
    local result = ''
    for _, item in ipairs(content) do
      if item.type == 'text' then
        result = result .. ' ' .. item.text
      end
    end
    return result
  end
end

---@param content ai.AdapterMessageContent
---@return AdapterMessageContentItem[]
function M.extract_images(content)
  if type(content) == 'string' then
    return {}
  else
    return vim
      .iter(content)
      :filter(function(item)
        ---@cast item AdapterMessageContentItem
        return item.type == 'image'
      end)
      :totable()
  end
end

return M
