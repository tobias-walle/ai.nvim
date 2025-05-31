local eq = MiniTest.expect.equality
local T = MiniTest.new_set()

local SelectionWrite = require('ai.tools.selection_write')

T['SelectionWrite'] = MiniTest.new_set()

T['SelectionWrite']['execute should overwrite selection and update marks'] = function()
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, true, {
    'line1',
    'line2',
    'line3',
  })
  -- Select 'line2' (row 2)
  vim.api.nvim_buf_set_mark(buf, '<', 2, 0, {})
  vim.api.nvim_buf_set_mark(buf, '>', 2, 4, {})
  local tool = SelectionWrite.create_selection_write_tool({ bufnr = buf })
  local called = false
  tool.execute({ bufnr = buf, content = 'hello\nworld' }, function(result)
    called = true
  end)
  eq(
    vim.api.nvim_buf_get_lines(buf, 0, -1, true),
    { 'line1', 'hello', 'world', 'line3' }
  )
  local new_start = vim.api.nvim_buf_get_mark(buf, '<')
  local new_end = vim.api.nvim_buf_get_mark(buf, '>')
  eq(new_start[1], 2)
  eq(new_start[2], 0)
  eq(new_end[1], 3)
  eq(new_end[2], 5)
  assert(called, 'Callback should have been called')
end

T['SelectionWrite']['render should show location'] = function()
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, true, {
    '',
    '',
    '',
    '',
    '',
    '',
    '',
    '',
    '',
    '',
    '',
    '',
    '',
    '',
    '',
    '',
    '',
    '',
    '',
    '',
  })
  vim.api.nvim_buf_set_name(buf, 'my/file')
  vim.api.nvim_buf_set_mark(buf, '<', 13, 19, {})
  vim.api.nvim_buf_set_mark(buf, '>', 19, 0, {})
  local tool = SelectionWrite.create_selection_write_tool({ bufnr = buf })
  ---@diagnostic disable-next-line: missing-fields
  local rendered = tool.render({})
  eq(rendered[1], '📝 Overwrite selection in `my/file:14:20`')
end

return T
