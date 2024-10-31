local M = {}

local system_prompt_template = vim.trim([[
You are a useful code assistant
]])

local function create_chat_buffer()
  -- Create a new buffer
  local bufnr = vim.api.nvim_create_buf(false, true)

  -- Set buffer options
  vim.api.nvim_buf_set_option(bufnr, 'buftype', 'nofile')
  vim.api.nvim_buf_set_option(bufnr, 'filetype', 'markdown')
  vim.api.nvim_buf_set_option(bufnr, 'modifiable', true)

  -- Open buffer in a vertical split
  vim.cmd('vsplit')
  vim.api.nvim_win_set_buf(0, bufnr)

  return bufnr
end

local function parse_messages(bufnr)
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local current_role = nil
  local current_content = {}
  local messages = {}

  for _, line in ipairs(lines) do
    if line:match('^## ') then
      if current_role then
        table.insert(messages, {
          role = current_role:lower(),
          content = table
            .concat(current_content, '\n')
            :gsub('^%s*(.-)%s*$', '%1'),
        })
      end
      current_role = line:gsub('^## ', '')
      current_content = {}
    elseif current_role and #line > 0 then
      table.insert(current_content, line)
    end
  end

  if current_role and #current_content > 0 then
    table.insert(messages, {
      role = current_role:lower(),
      content = table.concat(current_content, '\n'):gsub('^%s*(.-)%s*$', '%1'),
    })
  end

  dbg(messages)
  return messages
end

local function render_messages(bufnr, messages)
  local lines = {}
  for _, msg in ipairs(messages) do
    table.insert(lines, '## ' .. msg.role:gsub('^%l', string.upper))
    for _, line in ipairs(vim.split(msg.content, '\n')) do
      table.insert(lines, line)
    end
    table.insert(lines, '')
  end

  -- Add loading indicator if needed
  local last_message = messages[#messages]
  if
    vim.b[bufnr].is_loading
    and not (last_message.role == 'assistant' and #last_message.content > 0)
  then
    table.insert(lines, '## Assistant')
    table.insert(lines, '_Loading response..._')
    table.insert(lines, '')
  end

  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
end

local function send_message(bufnr)
  local adapter = require('ai.config').adapter
  local messages = parse_messages(bufnr)
  local last_message = messages[#messages]

  if not last_message or last_message.role ~= 'user' then
    vim.notify('No user message to send', vim.log.levels.ERROR)
    return
  end

  -- Prevent multiple requests
  if vim.b[bufnr].is_loading then
    vim.notify('A request is already in progress', vim.log.levels.WARN)
    return
  end
  vim.b[bufnr].is_loading = true
  render_messages(bufnr, messages)

  local current_response = {}
  local job = adapter:chat_stream({
    system_prompt = system_prompt_template,
    messages = messages,
    temperature = 0.3,
    on_update = function(update)
      current_response = vim.split(update.response, '\n')
      vim.schedule(function()
        local all_messages = vim.deepcopy(messages)
        table.insert(
          all_messages,
          { role = 'assistant', content = table.concat(current_response, '\n') }
        )
        render_messages(bufnr, all_messages)
      end)
    end,
    on_error = function(err)
      vim.b[bufnr].is_loading = false
      local all_messages = vim.deepcopy(messages)
      table.insert(
        all_messages,
        { role = 'assistant', content = '**Error:** ' .. err }
      )
      table.insert(all_messages, { role = 'user', content = '' })
      render_messages(bufnr, all_messages)
    end,
    on_exit = function(data)
      vim.b[bufnr].is_loading = false
      local all_messages = vim.deepcopy(messages)
      table.insert(
        all_messages,
        { role = 'assistant', content = data.response }
      )
      table.insert(all_messages, { role = 'user', content = '' })
      render_messages(bufnr, all_messages)
      -- Move cursor to the empty user message
      local line_count = vim.api.nvim_buf_line_count(bufnr)
      vim.api.nvim_win_set_cursor(0, { line_count - 1, 0 })
    end,
  })
end

function M.open_chat()
  local bufnr = create_chat_buffer()

  -- Set up keymaps
  vim.keymap.set('n', '<CR>', function()
    send_message(bufnr)
  end, { buffer = bufnr, noremap = true })

  -- Add initial message
  render_messages(bufnr, {
    { role = 'user', content = '' },
  })
  local line_count = vim.api.nvim_buf_line_count(bufnr)
  vim.api.nvim_win_set_cursor(0, { line_count - 1, 0 })
end

function M.setup()
  vim.api.nvim_create_user_command('AiChat', M.open_chat, {})
end

return M
