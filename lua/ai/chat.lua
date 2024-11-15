local M = {}

local Buffer = require('ai.chat.buffer')
local Tools = require('ai.tools')
local Cache = require('ai.utils.cache')
local Promise = require('ai.utils.promise')

---@class ChatContext
---(Empty for now)

local function get_chat_text(bufnr)
  return vim.fn.join(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false), '\n')
end

local function move_cursor_to_end(bufnr)
  local line_count = vim.api.nvim_buf_line_count(bufnr)
  pcall(vim.api.nvim_win_set_cursor, 0, { line_count - 1, 0 })
end

local function save_current_chat(bufnr)
  local chat = get_chat_text(bufnr)
  Cache.save_chat(chat)
end

---@param bufnr number
---@param messages AdapterMessage[]
---@param save? boolean
local function update_messages(bufnr, messages, save)
  Buffer.render(bufnr, messages)
  if save then
    save_current_chat(bufnr)
  end
  move_cursor_to_end(bufnr)
end

---@param bufnr number
---@param chat string
local function set_chat_text(bufnr, chat)
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, vim.split(chat, '\n'))
  move_cursor_to_end(bufnr)
end

---@param buffer ParsedChatBuffer
---@return AdapterMessage[]
local function create_messages(buffer)
  local config = require('ai.config').config

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
    :totable()

  ---@type AdapterMessage[]
  local variable_messages = {}
  for i = #buffer.messages, 1, -1 do
    if buffer.messages[i].role == 'user' then
      for _, variable in ipairs(buffer.messages[i].variables or {}) do
        local msg = {
          role = 'user',
          content = variable.resolve({}, {}),
        }
        table.insert(variable_messages, msg)
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

local function create_system_prompt(parsed)
  local system_prompt_parts = {
    'Current time: ' .. os.date('%Y-%m-%d %H:%M:%S'),
    require('ai.chat.prompts').system_prompt,
  }
  for _, fake_tool in ipairs(parsed.fake_tools or {}) do
    table.insert(system_prompt_parts, fake_tool)
  end
  return vim.fn.join(system_prompt_parts, '\n\n---\n\n')
end

local function send_message(bufnr)
  local adapter = require('ai.config').adapter
  local parsed = Buffer.parse(bufnr)
  local messages_before_send = parsed.messages
  local last_message = messages_before_send[#messages_before_send]

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

  vim.b[bufnr].running_job = adapter:chat_stream({
    temperature = 0.3,
    system_prompt = create_system_prompt(parsed),
    messages = create_messages(parsed),
    tools = tool_definitions,
    on_update = function(update)
      local all_messages = vim.deepcopy(messages_before_send)
      table.insert(all_messages, {
        role = 'assistant',
        content = update.response,
        tool_calls = update.tool_calls,
      })
      update_messages(bufnr, all_messages, false)
    end,
    on_exit = function(data)
      vim.b[bufnr].running_job = nil
      if data.cancelled then
        -- If cancelled, just render the messages before send
        update_messages(bufnr, messages_before_send, true)
      elseif data.exit_code == 0 then
        -- Add message only if the request was an success

        -- Print out the amount of tokens used
        local tokens = data.input_tokens + data.output_tokens
        vim.notify(
          string.format(
            '%d tokens used (%d input, %d output)',
            tokens,
            data.input_tokens,
            data.output_tokens
          ),
          vim.log.levels.INFO
        )

        -- Render the final message
        local all_messages = vim.deepcopy(messages_before_send)
        local assistant_message = {
          role = 'assistant',
          content = data.response,
          tool_calls = data.tool_calls,
        }
        table.insert(all_messages, assistant_message)
        update_messages(bufnr, all_messages, true)

        -- Execute "fake" tools in sequence
        local fake_tool_uses =
          Tools.find_fake_tool_uses(parsed.fake_tools or {}, data.response)
        local function execute_next_fake_tool(index, callback)
          local tool_use = fake_tool_uses[index]
          if not tool_use then
            callback()
            return
          end
          for _, call in ipairs(tool_use.calls) do
            tool_use.tool.execute({}, call, function()
              execute_next_fake_tool(index + 1, callback)
            end)
          end
        end

        -- Execute "real" tools
        local function execute_next_tool(index)
          local tool_call = assistant_message.tool_calls[index]
          if not tool_call then
            update_messages(bufnr, all_messages, true)
            -- Rerun to allow agentic workflows
            send_message(bufnr)
            return
          end

          if not tool_call.result then
            local tool = Tools.find_real_tool_by_name(tool_call.tool)
            if tool then
              tool_call.is_loading = true
              tool.execute({}, tool_call.params, function(result)
                ---@diagnostic disable-next-line: inject-field
                tool_call.result = result
                tool_call.is_loading = false
                update_messages(bufnr, all_messages, true)
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
        end

        execute_next_fake_tool(1, function()
          if #assistant_message.tool_calls > 0 then
            execute_next_tool(1)
          else
            table.insert(all_messages, { role = 'user', content = '' })
            update_messages(bufnr, all_messages, true)
          end
        end)
      end
    end,
    on_error = function(err)
      -- Remove ^M from err
      err = vim.trim(err:gsub('\r', ''))
      local err_msg = 'Error'
      if #err > 0 then
        err_msg = err_msg .. ':\n' .. err
      end
      table.insert(
        messages_before_send,
        { role = 'assistant', content = err_msg }
      )
      vim.b[bufnr].running_job = nil
      update_messages(bufnr, parsed.messages, true)
    end,
  })

  update_messages(bufnr, parsed.messages, true)
end

function M.open_chat()
  local bufnr = Buffer.toggle()

  if bufnr ~= nil then
    vim.api.nvim_create_autocmd('BufLeave', {
      buffer = bufnr,
      callback = function()
        save_current_chat(bufnr)
      end,
    })

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

    vim.keymap.set('n', 'gx', function()
      save_current_chat(bufnr)
      Cache.new_chat()
      update_messages(bufnr, {
        { role = 'user', content = '' },
      })
    end, { buffer = bufnr, noremap = true })

    vim.keymap.set('n', 'gn', function()
      save_current_chat(bufnr)
      local chat = Cache.next_chat()
      if chat then
        set_chat_text(bufnr, chat)
      end
    end, { buffer = bufnr, noremap = true })

    vim.keymap.set('n', 'gp', function()
      save_current_chat(bufnr)
      local chat = Cache.previous_chat()
      if chat then
        set_chat_text(bufnr, chat)
      end
    end, { buffer = bufnr, noremap = true })

    vim.keymap.set('n', 'gs', function()
      save_current_chat(bufnr)
      Cache.search_chats({}, function()
        local chat = Cache.load_chat()
        if chat then
          set_chat_text(bufnr, chat)
        end
      end)
    end, { buffer = bufnr, noremap = true })

    local existing_chat = Cache.load_chat()
    if existing_chat then
      set_chat_text(bufnr, existing_chat)
      move_cursor_to_end(bufnr)
    else
      -- Add initial message
      update_messages(bufnr, {
        { role = 'user', content = '' },
      })
    end
  end
end

function M.setup()
  vim.api.nvim_create_user_command('AiChat', M.open_chat, {})
end

--- Parse the messages of the current buffer (0) and render them again in a split
function M.debug_parsing()
  local parsed = Buffer.parse(0)
  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_option(bufnr, 'filetype', 'markdown')
  vim.cmd('vsplit')
  vim.api.nvim_win_set_buf(0, bufnr)
  update_messages(bufnr, parsed.messages)
end

return M
