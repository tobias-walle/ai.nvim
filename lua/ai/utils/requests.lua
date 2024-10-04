local M = {}

--- @class RequestOptions
--- @field url string
--- @field headers table
--- @field json_body table
--- @field on_data fun(data: table): nil
--- @field on_exit (fun(): nil)?

--- @param options RequestOptions
--- @return vim.SystemObj
function M.stream(options)
  local cmd = {
    'curl',
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

  local function on_output(err, data)
    if data == nil then
      return
    end
    if err then
      vim.notify('[ai] ' .. err, vim.log.levels.ERROR)
      return
    end
    for _, line in ipairs(vim.split(data, '\n')) do
      if line ~= '' and line:sub(1, 5) == 'data:' then
        local payload = line:sub(6)
        if payload ~= '[DONE]' then
          local decoded = vim.fn.json_decode(payload)
          options.on_data(decoded)
        end
      end
    end
  end

  return vim.system(
    cmd,
    {
      text = true,
      stdout = vim.schedule_wrap(on_output),
      stderr = vim.schedule_wrap(function(err, stderr)
        if err or stderr then
          vim.notify('[ai] ' .. (err or stderr), vim.log.levels.ERROR)
        end
      end),
    },
    vim.schedule_wrap(function(_)
      if options.on_exit then
        options.on_exit()
      end
    end)
  )
end

return M
