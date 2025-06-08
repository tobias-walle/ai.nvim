---@diagnostic disable: missing-fields
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
  local called = false
  local tool = SelectionWrite.create_selection_write_tool({
    bufnr = buf,
    editor = {
      add_patch = function(_, patch)
        eq(patch.patch, 'hello\nworld')
        vim.api.nvim_buf_set_lines(buf, 0, -1, true, {
          'line1',
          'hello',
          'world',
          'line3',
        })
        return patch.bufnr
      end,
      subscribe = function(_, _, cb)
        cb({ diffview_result = { result = 'ACCEPTED' } })
      end,
    },
  })
  tool.execute({ bufnr = buf, content = 'hello\nworld' }, function(result)
    called = true
  end)
  local new_start = vim.api.nvim_buf_get_mark(buf, '<')
  local new_end = vim.api.nvim_buf_get_mark(buf, '>')
  eq(new_start[1], 2)
  eq(new_start[2], 0)
  eq(new_end[1], 3)
  eq(new_end[2], 0)
  assert(called, 'Callback should have been called')
end

return T
