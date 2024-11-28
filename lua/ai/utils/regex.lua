local M = {}

---@param text string
---@param vim_regex_pattern string
---@return string[][] matches
function M.find_all_regex_matches(text, vim_regex_pattern)
  local matches = {}
  local start_pos = 0
  while true do
    -- Use vim.fn.matchlist to find matches in the line
    local match = vim.fn.matchlist(text, vim_regex_pattern, start_pos)
    if match == nil or #match == 0 then
      break
    end
    table.insert(matches, match)
    local match_pos = vim.fn.match(text, vim_regex_pattern, start_pos)
    start_pos = match_pos + #match[1]
  end
  return matches
end

return M
