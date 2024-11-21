---@diagnostic disable-next-line: unused-local
local expect = MiniTest.expect
local eq, no_eq = expect.equality, expect.no_equality

local child = MiniTest.new_child_neovim()

local U = require('ai.utils.testing').setup(child)
local lua_wait_for = U.lua_wait_for
local create_tmp_dir = U.create_tmp_dir
local prepare_test_project = U.prepare_test_project
local buffer_content_normalized = U.buffer_content_normalized
local check_reference_screenshot = U.check_reference_screenshot

local project_dir

local T = MiniTest.new_set({
  hooks = {
    pre_case = function()
      -- Restart child process with custom 'init.lua' script
      child.restart({ '-u', 'scripts/minimal_init.lua' })
    end,
    post_case = function()
      if #MiniTest.current.case.exec.fails > 0 then
        local formatted_debug_info = U.get_formatted_debug_info()
        if formatted_debug_info then
          MiniTest.add_note('\nDebugInfo:\n' .. formatted_debug_info)
        end
        -- Log screenshot after test
        MiniTest.add_note('\nScreen:\n' .. tostring(child.get_screenshot()))
      end
      U.reset_debug_info()
    end,
    -- Stop once all test cases are finished
    post_once = child.stop,
  },
})

local setup = function()
  project_dir = prepare_test_project()
  child.cmd('cd ' .. project_dir)
  local tmp_dir = create_tmp_dir()
  ---@type AiConfig
  local options = {
    default_model = 'openai:gpt-4o-mini',
    data_dir = tmp_dir,
  }
  child.lua(string.format("require('ai').setup(%s)", vim.inspect(options)))
end

T['should open and close chat'] = function()
  setup()
  child.cmd([[edit add.lua]])
  child.lua([[ require('ai').toggle_chat() ]])

  no_eq(child.fn.bufnr('ai-chat'), -1)
  check_reference_screenshot()

  child.lua([[ require('ai').toggle_chat() ]])

  eq(child.fn.bufnr('ai-chat'), -1)
  check_reference_screenshot()
end

T['should fix bug using ai'] = function()
  setup()
  child.cmd([[edit add.lua]])
  child.lua([[ require('ai').toggle_chat() ]])

  -- Ignore vim.notify to not disrupt screenshot
  child.lua([[vim.notify = function() end]])

  -- Setup the chat message
  child.api.nvim_buf_set_lines(0, -2, -1, true, {
    '#buffer',
    '@editor',
    'Fix ONLY the bug using the replacement syntax. Do no other changes!',
  })
  -- Sent it!
  child.type_keys('<cr>')

  -- We will wait until the answer was generated
  lua_wait_for('not vim.g._ai_is_loading', 10000)

  -- Now we will see a diff in which we can accept the changes
  -- We accept it
  child.type_keys('ga')

  -- Add the chat content to the debug info
  U.add_debug_info(buffer_content_normalized(0))

  -- Let's close the chat again
  child.lua([[ require('ai').toggle_chat() ]])

  -- Verify that the bug was fixed
  local buffer_content = buffer_content_normalized(0)
  eq(
    buffer_content,
    vim.trim([[
local function add(a, b)
  return a + b
end
  ]])
  )
end

return T
