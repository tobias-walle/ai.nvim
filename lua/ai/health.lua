local M = {}

function M.check()
  vim.health.start('ai.nvim checks')

  -- if vim.F.npcall(require, 'plenary') then
  --   vim.health.ok("require('plenary') succeeded")
  -- else
  --   vim.health.info("require('plenary') failed")
  -- end

  local ok, ai = pcall(require, 'ai')
  if not ok then
    vim.health.error("require('ai') failed")
  else
    vim.health.ok("require('ai') succeeded")

    if ai.did_setup then
      vim.health.ok("require('ai').setup() has been called")
    else
      vim.health.error("require('ai').setup() has not been called")
    end
  end

  for _, name in ipairs({ 'curl' }) do
    if vim.fn.executable(name) == 1 then
      vim.health.ok(('`%s` is installed'):format(name))
    else
      vim.health.warn(('`%s` is not installed'):format(name))
    end
  end
end

return M
