local M = {}

local Tools = require('ai.tools')
local Variables = require('ai.variables')

local BUF_NAME = 'ai-chat'

---@return integer|nil The buffer number of the created buffer
function M.create()
  -- Create a new buffer
  local bufnr = vim.api.nvim_create_buf(false, true)

  -- Set buffer options
  vim.api.nvim_buf_set_name(bufnr, BUF_NAME)
  vim.api.nvim_buf_set_option(bufnr, 'buftype', 'nofile')
  vim.api.nvim_buf_set_option(bufnr, 'filetype', 'markdown')
  vim.api.nvim_buf_set_option(bufnr, 'modifiable', true)

  -- Open buffer in a vertical split with 40% of the available width
  vim.cmd(
    'rightbelow vsplit | vertical resize ' .. math.floor(vim.o.columns * 0.45)
  )
  -- Set wrap
  vim.api.nvim_win_set_option(0, 'wrap', true)

  vim.api.nvim_win_set_buf(0, bufnr)

  -- Highlight
  -- Configure highlights for editor special syntax
  vim.cmd.syntax('match Keyword "^FILE:"')
  -- Configure tools highlight
  for _, tool in ipairs(Tools.all) do
    vim.fn.matchadd('Special', '@' .. Tools.get_tool_definition_name(tool))
  end

  -- Configure variables highlight
  for _, variable in ipairs(Variables.all) do
    vim.fn.matchadd(
      'Identifier',
      '#' .. variable.name .. require('ai.variables').pattern_multi_param
    )
  end

  -- Load cmp source if cmp is installed
  local _, cmp = pcall(require, 'cmp')
  if cmp ~= nil then
    cmp.register_source('ai-variables', require('ai.cmp.variables').new())
    cmp.register_source('ai-tools', require('ai.cmp.tools').new())
    local sources = {
      { name = 'ai-variables' },
      { name = 'ai-tools' },
    }

    for _, variable in ipairs(Variables.all) do
      if variable.cmp_source then
        local name = 'ai-variable-' .. variable.name
        local source = variable.cmp_source().new()
        cmp.register_source(name, source)
        table.insert(sources, { name = name })
      end
    end

    cmp.setup.buffer({ sources = sources })
  end

  return bufnr
end

---@return boolean success Whether the buffer was successfully closed
function M.close()
  local bufnr = vim.fn.bufnr(BUF_NAME)

  -- Get windows displaying the buffer
  local wins = vim.fn.win_findbuf(bufnr)

  -- Close all windows displaying the buffer
  for _, win in ipairs(wins) do
    vim.api.nvim_win_close(win, true)
  end

  -- Delete the buffer
  vim.api.nvim_buf_delete(bufnr, { force = true })
  return true
end

---@return integer|nil bufnr The buffer number of the toggled buffer (if opened)
function M.toggle()
  local bufnr = vim.fn.bufnr(BUF_NAME)
  local wins = vim.fn.win_findbuf(bufnr)
  if vim.api.nvim_buf_is_valid(bufnr) then
    if #wins > 0 then
      M.close()
      return nil
    else
      vim.api.nvim_buf_delete(bufnr, { force = true })
      return M.create()
    end
  else
    return M.create()
  end
end

---Render the messages to the given buffer
---@param bufnr integer
---@param messages ChatMessage[]
function M.render(bufnr, messages)
  local some_tool_call_is_loading = false
  local lines = {}
  for _, msg in ipairs(messages) do
    local content = vim.trim(msg.content)
    local has_tool_calls = msg.tool_calls and #msg.tool_calls > 0
    table.insert(lines, '## ' .. msg.role:gsub('^%l', string.upper) .. ' ##')
    if #content > 0 then
      for _, line in ipairs(vim.split(content, '\n')) do
        table.insert(lines, line)
      end
    end
    if has_tool_calls then
      for _, tool_call in ipairs(msg.tool_calls) do
        table.insert(lines, '')

        local rendered = require('ai.tools.utils.render').render(tool_call)
          or ''
        for _, line in ipairs(vim.split(rendered, '\n')) do
          table.insert(lines, line)
        end

        if tool_call.is_loading then
          some_tool_call_is_loading = true
        end
      end
    end
    table.insert(lines, '')
  end

  -- Add loading indicator if needed
  if vim.b[bufnr].running_job and not some_tool_call_is_loading then
    table.insert(lines, '...')
    table.insert(lines, '')
  end

  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
end

---@class ChatMessage
---@field role string The role of the message (e.g., 'user', 'assistant')
---@field content string The text content of the message
---@field tool_calls? RealToolCall[] Optional list of tool calls associated with the message
---@field fake_tool_uses? FakeToolUse[] The fake tools used in this message
---@field variables? VariableUse[] Optional list of variables used in the message

---@class ParsedChatBuffer
---@field messages ChatMessage[] The chat messages
---@field tools RealToolDefinition[] The tools used in the chat
---@field fake_tools FakeToolDefinition[] The fake tools used in the chat

---@param bufnr integer
---@return ParsedChatBuffer
function M.parse(bufnr)
  local messages = {}
  local parser = vim.treesitter.get_parser(bufnr, 'markdown')
  local tree = parser:parse()[1]
  local root = tree:root()

  local section_query = vim.treesitter.query.parse(
    'markdown',
    [[
    (
      (section
        (atx_heading
          (atx_h2_marker)
          (inline) @role)
        ((_) @content)*)
    )
    ]]
  )

  ---@type RealToolDefinition[]
  local tools = {}
  ---@type FakeToolDefinition[]
  local fake_tools = {}
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
    local content_matches = matches[2] or {}
    local content = get_text(content_matches, bufnr, '\n\n')

    local role = get_text(role_matches, bufnr)
    role = role:gsub('^%s*(.-)[#%s]*$', '%1'):lower()

    -- Parse tool calls
    local parsed_tool_calls, content_without_tool_calls =
      require('ai.tools.utils.render').parse(content)
    ---@type RealToolCall[]
    local tool_calls = {}
    if parsed_tool_calls and #parsed_tool_calls > 0 then
      vim.list_extend(tool_calls, parsed_tool_calls)
      content = content_without_tool_calls
    end

    -- Find tool activations
    for _, tool in ipairs(Tools.all) do
      if content:match('@' .. Tools.get_tool_definition_name(tool)) then
        local tools_of_the_same_type
        if tool.is_fake then
          tools_of_the_same_type = fake_tools
        else
          tools_of_the_same_type = tools
        end
        if
          not vim.iter(tools_of_the_same_type):find(function(existing_tool)
            return Tools.is_tool_definition_matching_name(
              existing_tool,
              Tools.get_tool_definition_name(tool)
            )
          end)
        then
          table.insert(tools_of_the_same_type, tool)
        end
      end
    end

    -- Find fake tool uses uses
    ---@type FakeToolUse[]
    local fake_tool_uses = {}
    if role == 'assistant' then
      local fake_tool_use = Tools.find_fake_tool_uses(fake_tools, content)
      if fake_tool_use then
        table.insert(fake_tool_uses, fake_tool_use)
      end
    end

    -- Find variable uses
    local current_message_variables =
      require('ai.variables').parse_variable_uses(content)

    table.insert(messages, {
      role = role,
      content = content,
      tool_calls = tool_calls,
      fake_tool_uses = fake_tool_uses,
      variables = #current_message_variables > 0 and current_message_variables
        or nil,
    })
  end

  -- print('Messages: ' .. vim.inspect(messages))
  -- print('Tools: ' .. vim.inspect(tools))
  -- print('Fake Tools: ' .. vim.inspect(fake_tools))
  return { messages = messages, tools = tools, fake_tools = fake_tools }
end

---@param bufnr integer
---@return nil
function M.rerender(bufnr)
  M.render(bufnr, M.parse(bufnr))
end

---Parse the last code block from the last assistant message
---@param bufnr integer
---@return string|nil code
function M.parse_last_code_block(bufnr)
  local parsed = M.parse(bufnr)

  local last_assistant_message = vim
    .iter(parsed.messages)
    :filter(function(msg)
      return msg.role == 'assistant'
    end)
    :last()

  if not last_assistant_message then
    return nil
  end

  local parser = vim.treesitter.get_parser(bufnr, 'markdown')
  local tree = parser:parse()[1]
  local root = tree:root()

  local code_block_query = vim.treesitter.query.parse(
    'markdown',
    [[
    (fenced_code_block
      (info_string)
      (code_fence_content) @code)
    ]]
  )

  local last_code_block = nil
  for _, captures, _ in code_block_query:iter_matches(root, bufnr, 0, -1) do
    last_code_block = vim.treesitter.get_node_text(captures[1], bufnr)
  end

  return last_code_block
end

return M
