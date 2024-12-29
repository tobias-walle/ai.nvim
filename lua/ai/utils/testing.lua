local M = {}

function M.setup(child)
  local U = {}

  function U.lua_wait_for(condition, timeout)
    timeout = timeout or 100
    child.lua(
      'vim.wait(' .. timeout .. ', function() return ' .. condition .. ' end)'
    )
    if not child.lua_get(condition) then
      error(
        string.format(
          'Failed check: %s (Timeout: %sms)\n--- Screen ---\n%s',
          condition,
          timeout,
          child.get_screenshot()
        )
      )
    end
  end

  ---@param bufnr integer|nil
  function U.buffer_content_normalized(bufnr)
    bufnr = bufnr or 0
    local lines = child.api.nvim_buf_get_lines(0, 0, -1, true)
    local text = vim.fn.join(lines, '\n')
    return vim.trim(text)
  end

  ---@param cmd table|string
  ---@return string
  function U.system(cmd)
    local result = vim.fn.system(cmd)
    if vim.v.shell_error ~= 0 then
      error(string.format('%s\nError: %s', table.concat(cmd, ' '), result))
    end
    return result
  end

  ---@return string
  function U.create_tmp_dir()
    local tmp_dir = vim.trim(U.system({ 'mktemp', '-d' }))
    MiniTest.finally(function()
      U.system({ 'rm', '-rf', tmp_dir })
    end)
    return tmp_dir
  end

  ---@return string
  function U.prepare_test_project()
    local tmp_dir = U.create_tmp_dir()
    local test_project_source = vim.fn.getcwd() .. '/tests/test-project'
    local test_project_dir = tmp_dir .. '/test-project'
    U.system({ 'cp', '-r', test_project_source, test_project_dir })
    return test_project_dir
  end

  function U.check_reference_screenshot()
    MiniTest.expect.reference_screenshot(
      child.get_screenshot(),
      nil,
      { force = os.getenv('UPDATE_SCREENSHOTS') == 'true' }
    )
  end

  local debug_info = {}

  function U.reset_debug_info()
    debug_info = {}
  end

  function U.add_debug_info(value)
    table.insert(debug_info, value)
  end

  function U.get_formatted_debug_info()
    if #debug_info == 0 then
      return nil
    end
    local result = ''
    for _, info in ipairs(debug_info) do
      if type(info) ~= 'string' then
        info = vim.inspect(info)
      end
      result = result .. info .. '\n'
    end
    return vim.trim(result)
  end

  function U.post_case_log_debug_info()
    if #MiniTest.current.case.exec.fails > 0 then
      local formatted_debug_info = U.get_formatted_debug_info()
      if formatted_debug_info then
        MiniTest.add_note('\nDebugInfo:\n' .. formatted_debug_info)
      end
      -- Log screenshot after test
      MiniTest.add_note('\nScreen:\n' .. tostring(child.get_screenshot()))
    end
    U.reset_debug_info()
  end

  return U
end

return M
