local M = {}

--- Get the mime type string for a file.
---@param filepath string
---@return string
function M.get_mime(filepath)
  local result = vim
    .system({ 'file', '-b', '--mime', filepath }, { text = true })
    :wait()
  if result.code ~= 0 then
    error('Failed to get mime type for file: ' .. filepath)
  end
  return result.stdout
end

--- Get the media type (type/subtype) from a file's mime type.
---@param filepath string
---@return string
function M.get_media_type(filepath)
  local mime = M.get_mime(filepath)
  local media_type = mime:match('^([%w%-%+%.]+/[%w%-%+%.]+)')
  return media_type
end

--- Check if a file is binary by inspecting its mime type.
---@param filepath string
---@return boolean
function M.is_binary(filepath)
  local mime = M.get_mime(filepath)
  if not mime then
    return false
  end
  if mime:match('charset=binary') then
    return true
  else
    return false
  end
end

--- Check if a file is an image by inspecting its mime type.
---@param filepath string
---@return boolean
function M.is_image(filepath)
  local mime = M.get_mime(filepath)
  if not mime then
    return false
  end
  if mime:match('^image/') then
    return true
  else
    return false
  end
end

return M
