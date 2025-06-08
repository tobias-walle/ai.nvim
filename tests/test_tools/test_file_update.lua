local eq = MiniTest.expect.equality
local T = MiniTest.new_set()

local FileUpdate = require('ai.tools.file_update')

T['FileUpdate'] = MiniTest.new_set()

T['FileUpdate']['execute should call editor and callback with accepted'] = function()
  local called_patch = nil
  local called_subscribe = false
  local tool = FileUpdate.create_file_update_tool({
    ---@diagnostic disable-next-line: missing-fields
    editor = {
      add_patch = function(_, args)
        called_patch = args
        return 1
      end,
      subscribe = function(_, _, cb)
        called_subscribe = true
        cb({ diffview_result = { result = 'ACCEPTED' } })
      end,
    },
  })
  local got_result = nil
  tool.execute({ file = 'foo.txt', update = 'patch' }, function(result)
    got_result = result
  end)
  eq(called_patch.bufnr, 'foo.txt')
  eq(called_patch.patch, 'patch')
  eq(called_subscribe, true)
  assert(got_result.result:match('accepted'), 'Should mention accepted')
end

T['FileUpdate']['execute should callback with rejected'] = function()
  local tool = FileUpdate.create_file_update_tool({
    ---@diagnostic disable-next-line: missing-fields
    editor = {
      add_patch = function()
        return 1
      end,
      subscribe = function(_, _, cb)
        cb({ diffview_result = { result = 'REJECTED' } })
      end,
    },
  })
  local got_result = nil
  tool.execute({ file = 'foo.txt', update = 'patch' }, function(result)
    got_result = result
  end)
  assert(got_result.result:match('REJECTED'), 'Should mention rejected')
end

T['FileUpdate']['render should show file and update'] = function()
  local tool = FileUpdate.create_file_update_tool({ editor = {} })
  local tool_call = { params = { file = 'foo.lua', update = '-- update' } }
  local rendered = tool.render(tool_call)
  eq(rendered, {
    '`````lua foo.lua (File Update)',
    '-- update',
    '`````',
  })
end

return T
