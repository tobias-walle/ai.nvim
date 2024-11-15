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
    '--fail-with-body',
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
  table.insert(cmd, vim.json.encode(options.json_body))

  local cancelled = false
  local stdout = ''
  local stderr = ''
  local buffer = '' -- Add a buffer for partial lines

  local function process_line(line)
    options.on_data(line)
  end

  local function on_output(_, data)
    if data == nil then
      return
    end
    stdout = stdout .. data

    -- Handle buffered data
    buffer = buffer .. data
    local lines = vim.split(buffer, '\n')

    -- Process complete lines
    for i = 1, #lines - 1 do
      process_line(lines[i])
    end

    -- Keep the last partial line in buffer
    buffer = lines[#lines]
    if buffer:match('[\r\n]$') then
      process_line(buffer)
      buffer = ''
    end
  end

  local function on_stderr(_, data)
    if data == nil then
      return
    end
    stderr = stderr .. data
  end

  local process = vim.system(
    cmd,
    {
      text = true,
      stdout = vim.schedule_wrap(on_output),
      stderr = vim.schedule_wrap(on_stderr),
    },
    vim.schedule_wrap(function(obj)
      -- Process any remaining buffered data
      if buffer ~= '' then
        process_line(buffer)
      end

      if obj.code ~= 0 then
        vim.notify(
          '[ai] curl failed.'
            .. '\nerror code: '
            .. obj.code
            .. '\nstderr: '
            .. stderr
            .. '\nstdout: '
            .. stdout,
          vim.log.levels.ERROR
        )
        if options.on_error then
          options.on_error(stdout)
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
