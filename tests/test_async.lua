---@diagnostic disable-next-line: unused-local
local expect, eq = MiniTest.expect, MiniTest.expect.equality

local child = MiniTest.new_child_neovim()

local U = require('ai.utils.testing').setup(child)
local lua_wait_for = U.lua_wait_for

local T = MiniTest.new_set({
  hooks = {
    pre_case = function()
      -- Restart child process with custom 'init.lua' script
      child.restart({ '-u', 'scripts/minimal_init.lua' })
      child.lua([[
      Async = require('ai.utils.async')
      ]])
    end,
    -- Stop once all test cases are finished
    post_once = child.stop,
  },
})

T['should create and run async functions'] = function()
  child.lua([[
    local sleep = Async.wrap_1(function(timeout, callback)
      vim.defer_fn(callback, timeout)
    end)

    result = nil
    Async.async(function()
      Async.await(sleep(10))
      result = 42
    end)()
  ]])

  lua_wait_for('result ~= nil')

  eq(child.lua_get('result'), 42)
end

T['should work with vim.ui.input and dressing'] = function()
  child.lua([[
    require('dressing').setup({})
    local ui_input = Async.wrap_1(vim.ui.input)
    result = nil
    Async.async(function()
      result = Async.await(ui_input({ prompt = "Enter a value:" }))
    end)()
  ]])

  eq(child.lua_get('result'), vim.NIL)

  child.type_keys('Hello World', '<cr>')

  lua_wait_for('result ~= nil')

  eq(child.lua_get('result'), 'Hello World')
end

T['should work with vim.system'] = function()
  child.lua([[
    local system = Async.wrap_2(vim.system)
    result = nil
    Async.async(function()
      result = Async.await(system({ 'echo', 'Hello from the CLI :)' })).stdout
    end)()
  ]])

  eq(child.lua_get('result'), vim.NIL)

  lua_wait_for('result ~= nil')

  eq(child.lua_get('result'), 'Hello from the CLI :)\n')
end

T['should run cli command and output to new buffer'] = function()
  child.lua([[
    local system = Async.wrap_2(vim.system)
    local schedule = Async.wrap_1(function (callback, after_schedule)
      vim.schedule(function()
        after_schedule(callback())
      end)
    end)

    result = nil
    bufnr = nil
    Async.async(function()
      result = Async.await(system({ 'echo', 'Hello from the CLI :)' })).stdout
      result = Async.await(schedule(function()
        bufnr = vim.api.nvim_create_buf(false, false)
        vim.api.nvim_set_current_buf(bufnr)
        vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, vim.split(result, '\n'))
        return "DONE"
      end))
    end)()
  ]])

  lua_wait_for('result ~= nil')
  lua_wait_for('bufnr ~= nil')

  local buffer_content = child.lua_get([[
    table.concat(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false), '\n')
  ]])

  eq(buffer_content, 'Hello from the CLI :)\n')
  eq(child.lua_get('result'), 'DONE')
  expect.reference_screenshot(child.get_screenshot())
end

return T
