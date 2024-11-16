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

  return U
end

return M
