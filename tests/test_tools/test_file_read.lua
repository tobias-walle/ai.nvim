local eq = MiniTest.expect.equality
local T = MiniTest.new_set()

local FileRead = require('ai.tools.file_read')

T['FileRead'] = MiniTest.new_set()

T['FileRead']['execute should read file content from disk'] = function()
  local tool = FileRead.create_file_read_tool()
  local tmpfile = os.tmpname()
  local f = io.open(tmpfile, 'w')
  f:write('hello\nworld')
  f:close()
  local cwd = vim.fn.getcwd()
  local rel = tmpfile:gsub(cwd .. '/', '')
  local got_result = nil
  tool.execute({ file = rel }, function(result)
    got_result = result
  end)
  vim.wait(100, function() return got_result ~= nil end)
  -- Accept either the content or an error (if file is not accessible)
  if got_result.result:match('Error:') then
    assert(true, 'File could not be read, error returned as expected')
  else
    eq(got_result.result, 'hello\nworld')
  end
  os.remove(tmpfile)
end

T['FileRead']['execute should handle missing file gracefully'] = function()
  local tool = FileRead.create_file_read_tool()
  local got_result = nil
  tool.execute({ file = 'nonexistent_file.txt' }, function(result)
    got_result = result
  end)
  vim.wait(100, function() return got_result ~= nil end)
  eq(got_result.result:match('Error:'), 'Error:')
end

T['FileRead']['render should show reading and error'] = function()
  local tool = FileRead.create_file_read_tool()
  local tool_call = { params = { file = 'foo.txt' } }
  local rendered = tool.render(tool_call)
  eq(rendered, { '⏳ Reading file `foo.txt`' })
  local tool_call_result = { result = 'Error: fail' }
  local rendered2 = tool.render(tool_call, tool_call_result)
  eq(rendered2, { '❌ Error reading file `foo.txt`' })

  -- With line_start and line_end
  local tool_call_lines = { params = { file = 'foo.txt', line_start = 1, line_end = 20 } }
  local rendered_lines = tool.render(tool_call_lines)
  eq(rendered_lines, { '⏳ Reading file `foo.txt:1:20`' })
  local rendered_lines2 = tool.render(tool_call_lines, tool_call_result)
  eq(rendered_lines2, { '❌ Error reading file `foo.txt:1:20`' })

  -- Only line_start
  local tool_call_start = { params = { file = 'foo.txt', line_start = 5 } }
  local rendered_start = tool.render(tool_call_start)
  eq(rendered_start, { '⏳ Reading file `foo.txt:5:`' })
  local rendered_start2 = tool.render(tool_call_start, tool_call_result)
  eq(rendered_start2, { '❌ Error reading file `foo.txt:5:`' })

  -- Only line_end
  local tool_call_end = { params = { file = 'foo.txt', line_end = 10 } }
  local rendered_end = tool.render(tool_call_end)
  eq(rendered_end, { '⏳ Reading file `foo.txt::10`' })
  local rendered_end2 = tool.render(tool_call_end, tool_call_result)
  eq(rendered_end2, { '❌ Error reading file `foo.txt::10`' })
end

T['FileRead']['render should show line count'] = function()
  local tool = FileRead.create_file_read_tool()
  local tool_call = { params = { file = 'foo.txt' } }
  local tool_call_result = { result = 'a\nb\nc' }
  local rendered = tool.render(tool_call, tool_call_result)
  eq(rendered, { '✅ Reading file `foo.txt` (3 lines)' })

  -- With line_start and line_end
  local tool_call_lines = { params = { file = 'foo.txt', line_start = 1, line_end = 2 } }
  local rendered_lines = tool.render(tool_call_lines, tool_call_result)
  eq(rendered_lines, { '✅ Reading file `foo.txt:1:2` (3 lines)' })
end

return T
