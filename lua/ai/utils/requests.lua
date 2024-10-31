local M = {}

local Job = require('ai.utils.jobs').Job

--- @class StreamRequestOptions
--- @field url string
--- @field headers table
--- @field json_body table
--- @field on_data fun(data: string): nil
--- @field on_exit (fun(code: integer, cancelled: boolean): nil)?
--- @field on_error (fun(error: string): nil)?

--- @param options StreamRequestOptions
--- @return Job
function M.stream(options)
  local cmd = {
    'curl',
    '-i',
    '--silent',
    '--no-buffer',
    '-X',
    'POST',
    options.url,
    '-H',
    'Content-Type: application/json',
  }
  for key, value in pairs(options.headers) do
    table.insert(cmd, '-H')
    table.insert(cmd, key .. ': ' .. value)
  end
  -- Add body
  table.insert(cmd, '-d')
  table.insert(cmd, vim.fn.json_encode(options.json_body))

  local cancelled = false

  local function on_output(_, data)
    if data == nil then
      return
    end
    for _, line in ipairs(vim.split(data, '\n')) do
      options.on_data(line)
    end
  end

  local process = vim.system(
    cmd,
    {
      text = true,
      stdout = vim.schedule_wrap(on_output),
    },
    vim.schedule_wrap(function(obj)
      if obj.code ~= 0 then
        vim.notify(
          '[ai] curl failed.'
            .. ' error code: '
            .. obj.code
            .. ', stderr: '
            .. obj.stderr,
          vim.log.levels.ERROR
        )
        if options.on_error then
          options.on_error(obj.stdout)
        end
      end
      if options.on_exit then
        options.on_exit(obj.code, cancelled)
      end
    end)
  )
  return Job:new({
    stop = function()
      cancelled = true
      --- process:kill doesn't work correctly, so we do it like this
      vim.system({ 'kill', '-INT', '' .. process.pid }):wait()
    end,
  })
end

---Parse an sse data chunk
---See also: https://developer.mozilla.org/en-US/docs/Web/API/Server-sent%5Fevents/Using%5Fserver-sent%5Fevents
---@param chunk string
---@return string|nil data The data or nil
function M.parse_sse_data(chunk)
  return chunk:match('^data: (.+)')
end

return M
