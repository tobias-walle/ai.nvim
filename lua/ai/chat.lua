local M = {}

local Buffer = require('ai.chat.buffer')
local Tools = require('ai.tools')

---@class ChatContext
---(Empty for now)

local system_prompt_template = vim.trim([[
You are a useful code assistant
]])

---@param buffer ParsedChatBuffer
---@return AdapterMessage[]
local function create_messages(buffer)
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
  for _, variable in ipairs(buffer.variables) do
    local msg = {
      role = 'user',
      content = variable.resolve({}, {}),
    }
    table.insert(variable_messages, msg)
  end

  -- Merge chat and variable messages. Include the variables before the last chat message.
  local result = {}
  for i = 1, #chat_messages - 1 do
    table.insert(result, chat_messages[i])
  end
  vim.list_extend(result, variable_messages)
  table.insert(result, chat_messages[#chat_messages])
  dbg(result)
  return result
end

local function send_message(bufnr)
  local adapter = require('ai.config').adapter
  local parsed = Buffer.parse(bufnr)
  local last_message = parsed.messages[#parsed.messages]

  if not last_message or last_message.role ~= 'user' then
    vim.notify('No user message to send', vim.log.levels.ERROR)
    return
  end

  local current_response = {}
  vim.b[bufnr].running_job = adapter:chat_stream({
    system_prompt = system_prompt_template,
    messages = create_messages(parsed),
    tools = vim
      .iter(parsed.tools)
      :map(function(tool)
        return tool.definition
      end)
      :totable(),
    temperature = 0.3,
    on_update = function(update)
      current_response = vim.split(update.response, '\n')
      local all_messages = vim.deepcopy(parsed.messages)
      table.insert(all_messages, {
        role = 'assistant',
        content = table.concat(current_response, '\n'),
        tool_calls = update.tool_calls,
      })
      Buffer.render(bufnr, all_messages)
    end,
    on_error = function(err)
      local all_messages = vim.deepcopy(parsed.messages)
      table.insert(
        all_messages,
        { role = 'assistant', content = '**Error:** ' .. err }
      )
      Buffer.render(bufnr, all_messages)
    end,
    on_exit = function(data)
      vim.b[bufnr].running_job = nil
      local all_messages = vim.deepcopy(parsed.messages)
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

        Buffer.render(bufnr, all_messages)

        vim.defer_fn(function()
          local function execute_next_tool(index)
            local tool_call = assistant_message.tool_calls[index]
            if not tool_call then
              table.insert(all_messages, { role = 'user', content = '' })
              Buffer.render(bufnr, all_messages)
              return
            end

            local tool = Tools.find_tool_by_name(tool_call.tool)
            if tool then
              tool.execute({}, tool_call.params, function(result)
                ---@diagnostic disable-next-line: inject-field
                tool_call.result = result
                Buffer.render(bufnr, all_messages)
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
      elseif data.exit_code == 0 then
        Buffer.render(bufnr, all_messages)
      end
    end,
  })

  Buffer.render(bufnr, parsed.messages)
end

--- Parse the messages of the current buffer (0) and render them again in a split
function M.debug_parsing()
  local parsed = Buffer.parse(0)
  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_option(bufnr, 'filetype', 'markdown')
  vim.cmd('vsplit')
  vim.api.nvim_win_set_buf(0, bufnr)
  Buffer.render(bufnr, parsed.messages)
end

function M.open_chat()
  local bufnr = Buffer.create()

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
  Buffer.render(bufnr, {
    { role = 'user', content = '' },
  })
end

function M.setup()
  vim.api.nvim_create_user_command('AiChat', M.open_chat, {})
end

return M
