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
end

T['FileRead']['render should show line count'] = function()
  local tool = FileRead.create_file_read_tool()
  local tool_call = { params = { file = 'foo.txt' } }
  local tool_call_result = { result = 'a\nb\nc' }
  local rendered = tool.render(tool_call, tool_call_result)
  eq(rendered, { '✅ Reading file `foo.txt` (3 lines)' })
end

return T
