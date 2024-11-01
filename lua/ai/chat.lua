local Tools = require('ai.tools')

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

local function parse_chat_buffer(bufnr)
  local messages = {}
  local parser = vim.treesitter.get_parser(bufnr, 'markdown')
  local tree = parser:parse()[1]
  local root = tree:root()

  local query = vim.treesitter.query.parse(
    'markdown',
    [[
      (section
        (atx_heading
          (atx_h2_marker)
          (inline) @role)
        (paragraph) @content)
    ]]
  )

  local tools = {}
  for _, match, _ in query:iter_matches(root, bufnr) do
    local role = vim.treesitter.get_node_text(match[1], bufnr)
    local content = vim.treesitter.get_node_text(match[2], bufnr)

    -- Clean up the role and content
    role = role:gsub('^%s*(.-)[#%s]*$', '%1'):lower()
    content = content:gsub('^%s*(.-)%s*$', '%1')

    if content:match('@editor') then
      local tool = vim.iter(Tools.all):find(function(tool)
        return tool.definition.name == 'editor'
      end)
      if tool then
        table.insert(tools, tool)
      end
    end

    if #content > 0 then
      table.insert(messages, {
        role = role,
        content = content,
      })
    end
  end

  -- vim.notify('Messages: ' .. vim.inspect(messages), vim.log.levels.DEBUG)
  -- vim.notify('Tools: ' .. vim.inspect(tools), vim.log.levels.DEBUG)
  return { messages = messages, tools = tools }
end

local function render_messages(bufnr, messages)
  local lines = {}
  for _, msg in ipairs(messages) do
    table.insert(lines, '## ' .. msg.role:gsub('^%l', string.upper) .. ' ##')
    for _, line in ipairs(vim.split(msg.content, '\n')) do
      table.insert(lines, line)
    end
    table.insert(lines, '')
  end

  -- Add loading indicator if needed
  local last_message = messages[#messages]
  if
    vim.b[bufnr].running_job
    and not (last_message.role == 'assistant' and #last_message.content > 0)
  then
    table.insert(lines, '## Assistant ##')
    table.insert(lines, '⏳')
    table.insert(lines, '')
  end

  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)

  -- Move cursor to the end
  local line_count = vim.api.nvim_buf_line_count(bufnr)
  local line =
    vim.api.nvim_buf_get_lines(bufnr, line_count - 2, line_count - 1, false)[1]
  vim.api.nvim_win_set_cursor(0, { line_count - 1, #line })
end

local function send_message(bufnr)
  local adapter = require('ai.config').adapter
  local parsed = parse_chat_buffer(bufnr)
  local messages = parsed.messages
  local tools = parsed.tools
  local last_message = messages[#messages]

  if not last_message or last_message.role ~= 'user' then
    vim.notify('No user message to send', vim.log.levels.ERROR)
    return
  end

  local current_response = {}
  vim.b[bufnr].running_job = adapter:chat_stream({
    system_prompt = system_prompt_template,
    messages = messages,
    tools = vim
      .iter(tools)
      :map(function(tool)
        return tool.definition
      end)
      :totable(),
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
      local all_messages = vim.deepcopy(messages)
      table.insert(
        all_messages,
        { role = 'assistant', content = '**Error:** ' .. err }
      )
      table.insert(all_messages, { role = 'user', content = '' })
      render_messages(bufnr, all_messages)
    end,
    on_exit = function(data)
      vim.b[bufnr].running_job = nil
      local all_messages = vim.deepcopy(messages)
      if not data.cancelled then
        -- Add message only if the request was an success
        table.insert(
          all_messages,
          { role = 'assistant', content = data.response }
        )
        table.insert(all_messages, { role = 'user', content = '' })
        local tokens = data.input_tokens + data.output_tokens
        vim.notify(
          tokens
            .. ' tokens used ('
            .. data.input_tokens
            .. ' input, '
            .. data.output_tokens
            .. ' output)',
          vim.log.levels.INFO
        )

        render_messages(bufnr, all_messages)

        for _, tool_call in pairs(data.tool_calls) do
          local tool = Tools.find_tool_by_name(tool_call.tool)
          if tool then
            tool.execute({}, tool_call.params)
          else
            vim.notify(
              'Tool not found: ' .. tool_call.tool,
              vim.log.levels.ERROR
            )
          end
        end
      else
        render_messages(bufnr, all_messages)
      end
    end,
  })

  render_messages(bufnr, messages)
end

function M.open_chat()
  local bufnr = create_chat_buffer()

  -- Set up keymaps
  vim.keymap.set('n', '<CR>', function()
    if not vim.b[bufnr].running_job then
      send_message(bufnr)
    end
  end, { buffer = bufnr, noremap = true })

  vim.keymap.set('n', 'q', function()
    local job = vim.b[bufnr].running_job
    if job then
      job:stop()
      vim.b[bufnr].running_job = nil
    end
  end, { buffer = bufnr, noremap = true })

  -- Add initial message
  render_messages(bufnr, {
    { role = 'user', content = '' },
  })
end

function M.setup()
  vim.api.nvim_create_user_command('AiChat', M.open_chat, {})
end

return M
