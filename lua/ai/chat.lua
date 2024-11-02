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
  for _, tool in ipairs(Tools.all) do
    vim.cmd.syntax('match Special "@' .. tool.definition.name .. '"')
  end

  return bufnr
end

function M.parse_chat_buffer(bufnr)
  local messages = {}
  local parser = vim.treesitter.get_parser(bufnr, 'markdown')
  local tree = parser:parse()[1]
  local root = tree:root()

  local section_query = vim.treesitter.query.parse(
    'markdown',
    [[
      (section
        (atx_heading
          (atx_h2_marker)
          (inline) @role)
        ((_) @content)+)
    ]]
  )

  local tool_call_query = vim.treesitter.query.parse(
    'markdown',
    [[
      (fenced_code_block
        (code_fence_content) @code_content
        (#match? @code_content "// tool:call")
        )
    ]]
  )

  local tools = {}

  local get_text = function(captures, source, delim)
    return vim
      .iter(captures)
      :map(function(c)
        return vim.treesitter.get_node_text(c, source)
      end)
      :filter(function(v)
        return v
      end)
      :join(delim or '')
  end

  for _, matches, _ in
    section_query:iter_matches(root, bufnr, 0, -1, { all = true })
  do
    local role_matches = matches[1]
    local content_matches = matches[2]

    local role = get_text(role_matches, bufnr)
    role = role:gsub('^%s*(.-)[#%s]*$', '%1'):lower()

    -- Parse tool calls
    local tool_calls = {}
    content_matches = vim.iter(content_matches):filter(function(content_match)
      local content_match_text =
        vim.treesitter.get_node_text(content_match, bufnr)
      local content_match_root = vim.treesitter
        .get_string_parser(content_match_text, 'markdown')
        :parse()[1]
        :root()
      local _, match, _ =
        tool_call_query:iter_matches(content_match_root, content_match_text)()
      if match then
        local tool_call_match_text =
          vim.treesitter.get_node_text(match[1], content_match_text)
        local tool_call
        local lines = vim.split(tool_call_match_text, '\n')
        for i, line in ipairs(lines) do
          if line:match('// tool:call%s*$') and lines[i + 1] then
            local ok, parsed = pcall(vim.json.decode, lines[i + 1])
            if ok then
              tool_call = parsed
              table.insert(tool_calls, tool_call)
            else
              vim.notify(
                'Failed to parse tool call: ' .. lines[i + 1],
                vim.log.levels.ERROR
              )
            end
          end
          if
            line:match('// tool:call:result%s*$')
            and lines[i + 1]
            and tool_call
          then
            local ok, parsed = pcall(vim.json.decode, lines[i + 1])
            if ok then
              tool_call.result = parsed
            else
              vim.notify(
                'Failed to parse tool call result: ' .. lines[i + 1],
                vim.log.levels.ERROR
              )
            end
          end
        end
      end
      return not match
    end)

    local content = get_text(content_matches, bufnr, '\n\n')

    -- Find tool uses
    for _, tool in ipairs(Tools.all) do
      if content:match('@' .. tool.definition.name) then
        if
          not vim.iter(tools):find(function(existing_tool)
            return existing_tool.definition.name == tool.definition.name
          end)
        then
          table.insert(tools, tool)
        end
      end
    end

    if #content > 0 then
      table.insert(messages, {
        role = role,
        content = content,
        tool_calls = tool_calls,
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
    if msg.tool_calls then
      for _, tool_call in ipairs(msg.tool_calls) do
        table.insert(lines, '')
        table.insert(lines, '```jsonc')
        table.insert(lines, '// tool:call')
        local tool_call_copy = vim.tbl_deep_extend('force', tool_call, {})
        tool_call_copy.result = nil
        tool_call_copy.content = nil
        table.insert(lines, vim.json.encode(tool_call_copy))
        if tool_call.result then
          table.insert(lines, '// tool:call:result')
          table.insert(lines, vim.json.encode(tool_call.result))
        end
        table.insert(lines, '```')
      end
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
  vim.api.nvim_win_set_cursor(0, { line_count - 1, 0 })
end

local function send_message(bufnr)
  local adapter = require('ai.config').adapter
  local parsed = M.parse_chat_buffer(bufnr)
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
    messages = vim
      .iter(messages)
      :map(function(m)
        local msg = {
          role = m.role,
          content = m.content,
          tool_calls = {},
          tool_call_results = {},
        }
        if m.tool_calls then
          for _, tool_call in ipairs(m.tool_calls) do
            table.insert(msg.tool_calls, {
              tool = tool_call.tool,
              id = tool_call.id,
              params = tool_call.params,
            })
            if tool_call.result then
              table.insert(
                msg.tool_call_results,
                { id = tool_call.id, result = tool_call.result }
              )
            end
          end
        end
        return msg
      end)
      :totable(),
    tools = vim
      .iter(tools)
      :map(function(tool)
        return tool.definition
      end)
      :totable(),
    temperature = 0.3,
    on_update = function(update)
      current_response = vim.split(update.response, '\n')
      local all_messages = vim.deepcopy(messages)
      table.insert(all_messages, {
        role = 'assistant',
        content = table.concat(current_response, '\n'),
        tool_calls = update.tool_calls,
      })
      render_messages(bufnr, all_messages)
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
        local assistant_message = {
          role = 'assistant',
          content = data.response,
          tool_calls = data.tool_calls,
        }
        table.insert(all_messages, assistant_message)
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

        vim.defer_fn(function()
          local function execute_next_tool(index)
            local tool_call = assistant_message.tool_calls[index]
            if not tool_call then
              table.insert(all_messages, { role = 'user', content = '' })
              render_messages(bufnr, all_messages)
              return
            end

            local tool = Tools.find_tool_by_name(tool_call.tool)
            if tool then
              tool.execute({}, tool_call.params, function(result)
                ---@diagnostic disable-next-line: inject-field
                tool_call.result = result
                render_messages(bufnr, all_messages)
                execute_next_tool(index + 1)
              end)
            else
              vim.notify(
                'Tool not found: ' .. tool_call.tool,
                vim.log.levels.ERROR
              )
              execute_next_tool(index + 1)
            end
          end

          execute_next_tool(1)
        end, 300)
      else
        render_messages(bufnr, all_messages)
      end
    end,
  })

  render_messages(bufnr, messages)
end

--- Parse the messages of the current buffer (0) and render them again in a split
function M.debug_parsing()
  local parsed = M.parse_chat_buffer(0)
  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_option(bufnr, 'filetype', 'markdown')
  vim.cmd('vsplit')
  vim.api.nvim_win_set_buf(0, bufnr)
  render_messages(bufnr, parsed.messages)
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
