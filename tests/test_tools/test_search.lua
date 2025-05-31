local eq = MiniTest.expect.equality
local T = MiniTest.new_set()

local Search = require('ai.tools.search')

T['Search'] = MiniTest.new_set()

T['Search']['execute should call rg and return result'] = function()
  local tool = Search.create_search_tool()
  -- Create a temp file to search in
  local tmpfile = os.tmpname()
  local f = io.open(tmpfile, 'w')
  f:write('hello\nworld\nhello again')
  f:close()
  local cwd = vim.fn.getcwd()
  local rel = tmpfile:gsub(cwd .. '/', '')
  local got_result = nil
  tool.execute({ query = 'hello', path = rel }, function(result)
    got_result = result
  end)
  vim.wait(500, function()
    return got_result ~= nil
  end)
  local decoded = vim.json.decode(got_result.result)
  eq(decoded.stdout:match('hello'), 'hello')
  os.remove(tmpfile)
end

T['Search']['render should show searching and results'] = function()
  local tool = Search.create_search_tool()
  local tool_call = { params = { query = 'foo', path = '.' } }
  local rendered = tool.render(tool_call)
  eq(rendered, { '⏳ Searching `foo` in `.`' })
  local tool_call_result = { result = vim.json.encode({ count = 2 }) }
  local rendered2 = tool.render(tool_call, tool_call_result)
  eq(rendered2, { '🔍 Searched `foo` in `.` (2 results)' })
end

return T
