---@diagnostic disable: need-check-nil
local eq = MiniTest.expect.equality
local T = MiniTest.new_set()

local FileWrite = require('ai.tools.file_write')

T['FileWrite'] = MiniTest.new_set()

T['FileWrite']['execute should call editor and callback with accepted'] = function()
  local called_patch = nil
  local called_subscribe = false
  local tool = FileWrite.create_file_write_tool({
    ---@diagnostic disable-next-line: missing-fields
    editor = {
      add_patch = function(_, args)
        called_patch = args
        return 1
      end,
      subscribe = function(_, bufnr, cb)
        called_subscribe = true
        cb({ diffview_result = { result = 'ACCEPTED' } })
      end,
    },
  })
  local got_result = nil
  tool.execute({ file = 'foo.txt', content = 'abc' }, function(result)
    got_result = result
  end)
  eq(called_patch.bufnr, 'foo.txt')
  eq(called_patch.patch, 'abc')
  eq(called_subscribe, true)
  assert(got_result.result:match('accepted'), 'Should mention accepted')
end

T['FileWrite']['execute should callback with rejected'] = function()
  local tool = FileWrite.create_file_write_tool({
    ---@diagnostic disable-next-line: missing-fields
    editor = {
      add_patch = function()
        return 1
      end,
      subscribe = function(_, bufnr, cb)
        cb({ diffview_result = { result = 'REJECTED', reason = 'Test reason' } })
      end,
    },
  })
  local got_result = nil
  tool.execute({ file = 'foo.txt', content = 'abc' }, function(result)
    got_result = result
  end)
  assert(got_result.result:lower():match('rejected'), 'Should mention rejected')
end

T['FileWrite']['render should show file and content'] = function()
  local tool = FileWrite.create_file_write_tool({ editor = {} })
  local tool_call = { params = { file = 'foo.lua', content = '-- content' } }
  local rendered = tool.render(tool_call)
  eq(rendered, {
    '`````lua foo.lua (File Write)',
    '-- content',
    '`````',
  })
end

return T
