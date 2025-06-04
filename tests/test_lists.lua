local eq = MiniTest.expect.equality

local T = MiniTest.new_set()

local lists = require('ai.utils.lists')

T['replace_lines'] = MiniTest.new_set()

T['replace_lines']['should replace a middle section'] = function()
  local lines = { 'a', 'b', 'c', 'd', 'e' }
  local result = lists.replace_lines(lines, 2, 4, { 'x', 'y' })
  eq(result, { 'a', 'x', 'y', 'e' })
end

T['replace_lines']['should replace the start'] = function()
  local lines = { 'a', 'b', 'c' }
  local result = lists.replace_lines(lines, 1, 2, { 'x' })
  eq(result, { 'x', 'c' })
end

T['replace_lines']['should replace the end'] = function()
  local lines = { 'a', 'b', 'c' }
  local result = lists.replace_lines(lines, 2, 3, { 'x', 'y' })
  eq(result, { 'a', 'x', 'y' })
end

T['replace_lines']['should replace the entire list'] = function()
  local lines = { 'a', 'b', 'c' }
  local result = lists.replace_lines(lines, 1, 3, { 'x' })
  eq(result, { 'x' })
end

T['replace_lines']['should delete a section'] = function()
  local lines = { 'a', 'b', 'c', 'd' }
  local result = lists.replace_lines(lines, 2, 3, {})
  eq(result, { 'a', 'd' })
end

T['replace_lines']['should handle idx_start > idx_end (no replacement)'] = function()
  local lines = { 'a', 'b', 'c' }
  local result = lists.replace_lines(lines, 3, 2, { 'x' })
  eq(result, { 'a', 'b', 'x', 'c' })
end

T['replace_lines']['should handle empty input'] = function()
  local lines = {}
  local result = lists.replace_lines(lines, 1, 0, { 'x' })
  eq(result, { 'x' })
end

return T
