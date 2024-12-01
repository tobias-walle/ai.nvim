local M = {}

local Buffer = require('ai.chat.buffer')
local Tools = require('ai.tools')
local Cache = require('ai.utils.cache')
local Async = require('ai.utils.async')

---@class ChatContextSelection
---@field line_start number
---@field col_start number
---@field line_end number
---@field col_end number

---@class ChatContext
---@field chat_bufnr number
---@field left_bufnr? number Bufnr of the associated code on the left side
---@field left_buf_selection? ChatContextSelection

local function get_chat_text(bufnr)
  return vim.fn.join(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false), '\n')
end

local function move_cursor_to_end(bufnr)
  local line_count = vim.api.nvim_buf_line_count(bufnr)
  pcall(vim.api.nvim_win_set_cursor, 0, { line_count, 0 })
end

function M.save_current_chat(bufnr)
  local chat = get_chat_text(bufnr)
  Cache.save_chat(chat)
end

---@param bufnr number
---@param messages AdapterMessage[]
---@param save? boolean
function M.update_messages(bufnr, messages, save)
  Buffer.render(bufnr, messages)
  if save then
    M.save_current_chat(bufnr)
  end
  move_cursor_to_end(bufnr)
end

---@param bufnr number
---@param chat string
function M.set_chat_text(bufnr, chat)
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, vim.split(chat, '\n'))
  move_cursor_to_end(bufnr)
end

---@param ctx ChatContext
---@param buffer ParsedChatBuffer
---@return AdapterMessage[]
function M.create_messages(ctx, buffer)
  local config = require('ai.config').get()

  ---@type AdapterMessage[]
  local context_messages = {}

  if vim.fn.filereadable(config.context_file) == 1 then
    local project_context_lines = vim.fn.readfile(config.context_file)
    local project_context = table.concat(project_context_lines, '\n')
    table.insert(context_messages, {
      role = 'user',
      content = 'Please consider the following project context instructions, defined by the developers:\n\n'
        .. project_context,
    })
  end

  local chat_messages = vim
    .iter(buffer.messages)
    :map(function(m)
      local content = m.content
      for _, tool in ipairs(Tools.all) do
        content = content:gsub('@' .. Tools.get_tool_definition_name(tool), '')
      end
      local msg = {
        role = m.role,
        content = content,
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
    :totable()

  ---@type AdapterMessage[]
  local variable_messages = {}
  for i = #buffer.messages, 1, -1 do
    if buffer.messages[i].role == 'user' then
      for _, variable_use in ipairs(buffer.messages[i].variables or {}) do
        local variable = require('ai.variables').find_by_name(variable_use.name)
        if variable ~= nil then
          local msg = {
            role = 'user',
            content = variable.resolve(ctx, variable_use.params),
          }
          table.insert(variable_messages, msg)
        end
      end
      break
    end
  end

  -- Merge all messages.
  local result = vim.fn.deepcopy(context_messages)
  for i = 1, #chat_messages - 1 do
    table.insert(result, chat_messages[i])
  end
  vim.list_extend(result, variable_messages)
  table.insert(result, chat_messages[#chat_messages])
  return result
end

--- Create a system prompt for the chat based on parsed data.
---@param parsed ParsedChatBuffer
---@return string
function M.create_system_prompt(parsed)
  local system_prompt_parts = {
    require('ai.prompts').system_prompt_chat,
  }
  for _, fake_tool in ipairs(parsed.fake_tools or {}) do
    table.insert(system_prompt_parts, fake_tool)
  end
  return vim.fn.join(system_prompt_parts, '\n\n---\n\n')
end

---@param data AdapterStreamExitData
local function notify_about_token_usage(data)
  local tokens = data.input_tokens + data.output_tokens
  local cached_msg = ''
  if data.input_tokens_cached > 0 then
    cached_msg = ' [Cached: ' .. data.input_tokens_cached .. ']'
  end
  vim.notify(
    tokens
      .. ' tokens used ('
      .. data.input_tokens
      .. cached_msg
      .. ', '
      .. data.output_tokens
      .. ' output)',
    vim.log.levels.INFO
  )
end

---@param bufnr number
---@param messages_before_send AdapterMessage[]
---@param data AdapterStreamExitData
---@return AdapterMessage
local function render_assistant_message(bufnr, messages_before_send, data)
  local all_messages = vim.deepcopy(messages_before_send)
  local assistant_message = {
    role = 'assistant',
    content = data.response,
    tool_calls = data.tool_calls,
  }
  table.insert(all_messages, assistant_message)
  M.update_messages(bufnr, all_messages, true)
  return assistant_message
end

--- Execute real tools and update the messages.
---@param bufnr number The buffer number for the chat.
---@param ctx ChatContext The chat context.
---@param assistant_message AdapterMessage The assistant message.
---@param all_messages AdapterMessage[] All messages including the assistant message.
---@return boolean Whether the agentic workflow should be triggered.
local function execute_real_tools(bufnr, ctx, assistant_message, all_messages)
  local number_of_tool_results = 0
  local jobs = vim
    .iter(assistant_message.tool_calls)
    :filter(function(tool_call)
      return not tool_call.result
    end)
    :map(function(tool_call)
      return Async.async(function()
        local tool = Tools.find_real_tool_by_name(tool_call.tool)
        if not tool then
          vim.notify('Tool not found: ' .. tool_call.tool, vim.log.levels.ERROR)
          return nil
        end

        tool_call.is_loading = true

        local execute = Async.wrap_2(tool.execute)
        local result = Async.await(execute(ctx, tool_call.params))
        tool_call.result = result
        tool_call.is_loading = false
        number_of_tool_results = number_of_tool_results + 1
        M.update_messages(bufnr, all_messages, true)
      end)
    end)
    :totable()
  Async.await_all(jobs)

  return #assistant_message.tool_calls > 0
    and #assistant_message.tool_calls == number_of_tool_results
end

--- Execute fake tools in sequence.
---@param parsed ParsedChatBuffer
---@param data AdapterStreamExitData
---@param ctx ChatContext
---@param cancelled boolean
local function execute_fake_tools(parsed, data, ctx, cancelled)
  local fake_tool_uses =
    Tools.find_fake_tool_uses(parsed.fake_tools or {}, data.response)
  for _, tool_use in ipairs(fake_tool_uses) do
    local execute = Async.wrap_2(tool_use.tool.execute)
    for _, call in ipairs(tool_use.calls) do
      Async.await(execute(ctx, call))
      if cancelled then
        return
      end
    end
  end
end

--- Prepare the next user message content.
---@param messages_before_send AdapterMessage[] The messages before sending.
---@param bufnr number The buffer number for the chat.
---@return string[] The lines of the next user message content.
local function prepare_next_user_message_content(messages_before_send, bufnr)
  local next_message_content_lines = {}

  ---@type ChatMessage | nil
  local last_user_message = vim
    .iter(messages_before_send)
    :filter(function(msg)
      return msg.role == 'user'
    end)
    :last()

  local latest_messages = Buffer.parse(bufnr).messages
  ---@type ChatMessage | nil
  local last_assistant_message = vim
    .iter(latest_messages)
    :filter(function(msg)
      return msg.role == 'assistant'
    end)
    :last()

  local last_user_message_variable_uses = last_user_message
      and last_user_message.variables
    or {}
  for _, variable in ipairs(last_user_message_variable_uses) do
    table.insert(next_message_content_lines, variable.raw)
  end

  if last_assistant_message and last_assistant_message.variables then
    -- Remove variables already defined by user
    local request_assistant_variables =
      require('ai.variables').remove_duplicates(
        last_assistant_message.variables,
        last_user_message_variable_uses
      )
    -- Add a bit of space if there is already something in the message
    if #next_message_content_lines > 0 then
      table.insert(next_message_content_lines, '')
    end
    -- Add the variables
    for _, variable in ipairs(request_assistant_variables) do
      -- Only add variables with parameters, other variables don't really make sense
      if variable.params then
        table.insert(next_message_content_lines, variable.raw)
      end
    end
  end

  return next_message_content_lines
end

--- Handle the exit of the chat stream.
---@param data AdapterStreamExitData The data returned from the chat stream.
---@param bufnr number
---@param messages_before_send AdapterMessage[]
---@param parsed ParsedChatBuffer
---@param ctx ChatContext
---@param cancelled boolean
local function handle_exit(
  data,
  bufnr,
  messages_before_send,
  parsed,
  ctx,
  cancelled
)
  Async.async(function()
    vim.b[bufnr].running_job = nil
    if data.cancelled or cancelled then
      return
    elseif data.exit_code == 0 then
      -- Add message only if the request was a success

      -- Print out the amount of tokens used
      notify_about_token_usage(data)

      -- Render the final message
      local assistant_message =
        render_assistant_message(bufnr, messages_before_send, data)

      -- Execute "real" tools
      local all_messages = vim.deepcopy(messages_before_send)
      table.insert(all_messages, assistant_message)
      local should_trigger_agentic_workflow =
        execute_real_tools(bufnr, ctx, assistant_message, all_messages)

      if not should_trigger_agentic_workflow then
        vim.g._ai_is_loading = false
      end

      -- Execute "fake" tools
      execute_fake_tools(parsed, data, ctx, cancelled)

      if should_trigger_agentic_workflow then
        M.update_messages(bufnr, all_messages, true)
        -- If tools were executed, send the message again to allow agentic workflows
        M.send_message(bufnr)
      else
        -- Otherwise it is the user's turn again

        -- Copy the last variable uses into the next message
        local next_message_content_lines =
          prepare_next_user_message_content(messages_before_send, bufnr)

        table.insert(all_messages, {
          role = 'user',
          content = vim.fn.join(next_message_content_lines, '\n'),
        })
        M.update_messages(bufnr, all_messages, true)
      end
    end
  end)()
end

--- Handle errors that occur during the chat stream.
---@param err string
---@param bufnr number
---@param messages_before_send AdapterMessage[]
---@param parsed ParsedChatBuffer
local function handle_chat_stream_error(
  err,
  bufnr,
  messages_before_send,
  parsed
)
  -- Remove ^M from err
  err = vim.trim(err:gsub('\r', ''))
  local err_msg = 'Error'
  if #err > 0 then
    err_msg = err_msg .. ':\n' .. err
  end
  table.insert(messages_before_send, { role = 'assistant', content = err_msg })
  vim.b[bufnr].running_job = nil
  M.update_messages(bufnr, parsed.messages, true)
end

---@param bufnr integer
---@return ChatContext
function M.get_chat_context(bufnr)
  local wins = vim.api.nvim_tabpage_list_wins(0)
  local leftmost_win = wins[1]
  local left_bufnr
  if leftmost_win ~= nil then
    left_bufnr = vim.api.nvim_win_get_buf(leftmost_win)
  end
  local left_buf_selection
  if left_bufnr ~= nil then
    -- Get the line and column numbers of markers '<' and '>'
    local line_start, col_start =
      unpack(vim.api.nvim_buf_get_mark(left_bufnr, '<'))
    local line_end, col_end = unpack(vim.api.nvim_buf_get_mark(left_bufnr, '>'))

    -- Check if selection exists
    if line_start ~= 0 and line_end ~= 0 then
      if
        line_start > line_end
        or (line_start == line_end and col_start > col_end)
      then
        -- Ensure line_start is less than or equal to line_end
        line_start, col_start, line_end, col_end =
          line_end, col_end, line_start, col_start
      end

      left_buf_selection = {
        line_start = line_start,
        col_start = col_start,
        line_end = line_end,
        col_end = col_end,
      }
    end
  end
  return {
    left_bufnr = left_bufnr,
    chat_bufnr = bufnr,
    left_buf_selection = left_buf_selection,
  }
end

---@param bufnr integer
function M.send_message(bufnr)
  local adapter = require('ai.config').get_chat_adapter()
  local parsed = Buffer.parse(bufnr)
  local messages_before_send = parsed.messages
  local last_message = messages_before_send[#messages_before_send]

  local ctx = M.get_chat_context(bufnr)

  if
    not last_message
    or (last_message.role ~= 'user' and #last_message.tool_calls == 0)
  then
    vim.notify('No user message to send', vim.log.levels.ERROR)
    return
  end

  local tool_definitions = vim
    .iter(parsed.tools)
    :map(function(tool)
      return tool.definition
    end)
    :totable()

  local cancelled = false
  vim.keymap.set('n', 'q', function()
    cancelled = true
    local job = vim.b[bufnr].running_job
    if job then
      job:stop()
      vim.b[bufnr].running_job = nil
    end
    M.update_messages(bufnr, messages_before_send, true)
  end, { buffer = bufnr, noremap = true })

  vim.g._ai_is_loading = true
  vim.b[bufnr].running_job = adapter:chat_stream({
    temperature = 0,
    system_prompt = M.create_system_prompt(parsed),
    messages = M.create_messages(ctx, parsed),
    tools = tool_definitions,
    on_update = function(update)
      local all_messages = vim.deepcopy(messages_before_send)
      table.insert(all_messages, {
        role = 'assistant',
        content = update.response,
        tool_calls = update.tool_calls,
      })
      M.update_messages(bufnr, all_messages, false)
    end,
    on_exit = function(data)
      handle_exit(data, bufnr, messages_before_send, parsed, ctx, cancelled)
    end,
    on_error = function(err)
      handle_chat_stream_error(err, bufnr, messages_before_send, parsed)
    end,
  })

  M.update_messages(bufnr, parsed.messages, true)
end

---@param content? string
---@return {role: string, content: string}
function M.get_initial_msg(content)
  return {
    role = 'user',
    content = content or '',
  }
end

local visual_selection_highlight =
  vim.api.nvim_create_namespace('highlight_between_markers')

--- Highlight the selected text in the left buffer.
---@param bufnr number
function M.highlight_selection(bufnr)
  local ctx = M.get_chat_context(bufnr)
  local selection = ctx.left_buf_selection
  if not selection then
    return
  end

  local line_start = selection.line_start
  local col_start = selection.col_start
  local line_end = selection.line_end
  local col_end = selection.col_end

  -- Clear any existing highlights
  vim.api.nvim_buf_clear_namespace(
    ctx.left_bufnr,
    visual_selection_highlight,
    0,
    -1
  )

  -- Highlight the selected lines
  for line = line_start, line_end do
    local start_col = (line == line_start) and col_start or 0
    local end_col = (line == line_end) and col_end or -1
    vim.api.nvim_buf_add_highlight(
      ctx.left_bufnr,
      visual_selection_highlight,
      'Visual',
      line - 1,
      start_col,
      end_col
    )
  end
end

---@param bufnr number
function M.clear_highlight_selection(bufnr)
  local ctx = M.get_chat_context(bufnr)
  vim.api.nvim_buf_clear_namespace(
    ctx.left_bufnr,
    visual_selection_highlight,
    0,
    -1
  )
end

function M.toggle_chat(cmd_opts)
  local bufnr = Buffer.toggle()
  -- For simplicity sake we just expect something to be selected if there is any range
  -- TODO: Use the correct range supplied by the user and add it to the ctx
  local is_something_selected = cmd_opts.range == 2
  local initial_message = cmd_opts.args

  if bufnr ~= nil then
    vim.api.nvim_create_autocmd('BufLeave', {
      buffer = bufnr,
      callback = function()
        M.save_current_chat(bufnr)
        M.clear_highlight_selection(bufnr)
      end,
    })

    vim.api.nvim_create_autocmd('BufEnter', {
      buffer = bufnr,
      callback = M.highlight_selection,
    })

    require('ai.chat.keymaps').setup_chat_keymaps(bufnr)

    if is_something_selected or initial_message ~= '' then
      local msg_lines = {}
      if is_something_selected then
        table.insert(msg_lines, '#selection')
      end
      if initial_message ~= '' then
        msg_lines = vim.list_extend(msg_lines, vim.split(initial_message, '\n'))
      end
      M.update_messages(bufnr, {
        M.get_initial_msg(table.concat(msg_lines, '\n')),
      })
    else
      local existing_chat = Cache.load_chat()
      if existing_chat then
        M.set_chat_text(bufnr, existing_chat)
        move_cursor_to_end(bufnr)
      else
        -- Add initial message
        M.update_messages(bufnr, { M.get_initial_msg() })
      end
    end

    M.highlight_selection(bufnr)
  end
end

function M.setup()
  vim.api.nvim_create_user_command('AiChat', M.toggle_chat, {
    nargs = '*',
    range = true,
  })
end

--- Parse the messages of the current buffer (0) and render them again in a split
function M.debug_parsing()
  local parsed = Buffer.parse(0)
  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_option(bufnr, 'filetype', 'markdown')
  vim.cmd('vsplit')
  vim.api.nvim_win_set_buf(0, bufnr)
  M.update_messages(bufnr, parsed.messages)
end

return M
