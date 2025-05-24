local M = {}

--- Read an image file and return its base64-encoded contents as a string.
---@param filepath string
---@return string
function M.read_image_as_base64(filepath)
  local result = vim
    .system({ 'base64', '-w', '0', filepath }, { text = true })
    :wait()
  if result.code ~= 0 then
    error('Failed to base64 encode image file: ' .. filepath)
  end
  return result.stdout
end

--- Paste the image from the clipboard to a new temporary PNG file.
--- Returns the image path if successful, or nil if not.
---@return string|nil
function M.paste_image()
  local img_path = vim.fn.tempname() .. '.png'
  local result = vim.system({ 'pngpaste', img_path }, { text = true }):wait()
  if result.code == 0 then
    return img_path
  else
    vim.notify(
      'No image in clipboard or failed to paste image',
      vim.log.levels.ERROR
    )
    return nil
  end
end

---Paste the image from the clipboard and insert it as markdown at the cursor position.
---@return nil
function M.paste_image_as_markdown()
  local img_path = M.paste_image()
  if not img_path then
    return
  end
  local buf = vim.api.nvim_get_current_buf()
  local row, col = unpack(vim.api.nvim_win_get_cursor(0))
  local markdown = '![](' .. img_path .. ')'
  -- Insert markdown image syntax at cursor
  vim.api.nvim_buf_set_text(buf, row - 1, col, row - 1, col, { markdown })
end

return M
