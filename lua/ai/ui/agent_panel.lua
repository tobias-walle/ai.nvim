local EventEmitter = require('ai.utils.event_emitter')
local Buffers = require('ai.utils.buffers')
local Numbers = require('ai.utils.numbers')
local Strings = require('ai.utils.strings')

---@class DisabledTools
---@field selection_write? boolean
---@field file_read? boolean
---@field file_write? boolean
---@field file_update? boolean
---@field search? boolean
---@field execute_code? boolean
---@field execute_command? boolean
---@field complete_task? boolean
---@field ask? boolean
---@field summarize_chat? boolean

---@class ai.AgentPanel.Options
---@field adapter ai.Adapter
---@field focused_bufnr number
---@field disable_tools? DisabledTools

---@class ai.AgentPanel.UserInput
---@field question string
---@field choices? string[]
---@field on_answer fun(text: ai.AdapterMessageContent)

---@class ai.AgentPanel: ai.AgentPanel.Options
---@field editor ai.Editor
---@field on_completion ai.EventEmitter<ai.CompleteTaskTool.Result>
---@field chat ai.Chat
---@field chat_thinking_animation ai.ThinkingAnimation | nil
---@field chat_bufnr number
---@field chat_win number
---@field token_info_bufnr number
---@field token_info_win number
---@field token_info_ns number
---@field user_input? ai.AgentPanel.UserInput
local AgentPanel = {}
AgentPanel.__index = AgentPanel

local ThinkingAnimation = require('ai.utils.thinking_animation')
local Messages = require('ai.utils.messages')
local Tools = require('ai.utils.tools')
local Editor = require('ai.agents.editor')

---@param opts ai.AgentPanel.Options
---@return ai.AgentPanel
function AgentPanel.new(opts)
  local self = setmetatable({}, AgentPanel)
  vim.tbl_extend('force', self, opts)

  -- Setup namespace
  self.token_info_ns = vim.api.nvim_create_namespace('AgentPanelTokenInfo')

  -- Render Layout
  self:_setup_layout()

  -- Setup Tools
  self.editor = Editor:new()
  self.on_completion = EventEmitter.new({ emit_initially = false })
  ---@type ai.ToolDefinition[]
  local tools = {}
  local disable_tools = opts.disable_tools or {}
  if not disable_tools.selection_write then
    table.insert(
      tools,
      require('ai.tools.selection_write').create_selection_write_tool({
        editor = self.editor,
        bufnr = opts.focused_bufnr,
      })
    )
  end
  if not disable_tools.file_read then
    table.insert(tools, require('ai.tools.file_read').create_file_read_tool())
  end
  if not disable_tools.file_write then
    table.insert(
      tools,
      require('ai.tools.file_write').create_file_write_tool({
        editor = self.editor,
      })
    )
  end
  if not disable_tools.file_update then
    table.insert(
      tools,
      require('ai.tools.file_update').create_file_update_tool({
        editor = self.editor,
      })
    )
  end
  if not disable_tools.search then
    table.insert(tools, require('ai.tools.search').create_search_tool())
  end
  if not disable_tools.execute_code then
    table.insert(
      tools,
      require('ai.tools.execute_code').create_execute_code_tool()
    )
  end
  if not disable_tools.execute_command then
    table.insert(
      tools,
      require('ai.tools.execute_command').create_execute_command_tool()
    )
  end
  if not disable_tools.complete_task then
    table.insert(
      tools,
      require('ai.tools.complete_task').create_complete_task_tool({
        on_completion = function(result)
          self.on_completion:notify(result)
        end,
        ask_user = function(params, callback)
          self.user_input = {
            question = params.question,
            choices = params.choices,
            on_answer = callback,
          }
          self:_render_chat()
        end,
      })
    )
  end
  if not disable_tools.summarize_chat then
    table.insert(
      tools,
      require('ai.tools.summarize_chat').create_complete_task_tool({
        on_summarization = function(result)
          local first_message = self.chat.messages[1]
          self.chat.messages = {
            first_message, -- Preserve the first message, as it contains a lot of relevant info
            { role = 'assistant', content = result },
          }
          self:_render_chat()
          self:send(vim.trim([[
You are in autonomous mode.
- If you are done with your task use the `complete_task` tool.
- If the task failed also use the `complete_task` tool.
- If you need input from me, use the `ask` tool.
- Otherwise continue with your task given above.
          ]]))
        end,
      })
    )
  end
  if not disable_tools.ask then
    table.insert(
      tools,
      require('ai.tools.ask').create_ask_tool({
        ask_user = function(params, callback)
          self.user_input = {
            question = params.question,
            choices = params.choices,
            on_answer = callback,
          }
          self:_render_chat()
        end,
      })
    )
  end

  -- Setup Chat
  self.chat = require('ai.utils.chat'):new({
    adapter = opts.adapter,
    system_prompt = require('ai.prompts').system_prompt_agent,
    tools = tools,
    on_chat_start = function()
      self.editor:reset()
      self:_start_chat_thinking_animation()
    end,
    on_chat_update = function()
      self:_stop_chat_thinking_animation()
      self:_render_chat()
    end,
    on_chat_exit = function()
      self:_render_chat()
    end,
    after_all_tool_calls_started = function(data)
      self:_render_chat()
      if self.editor:has_any_patches() then
        self.editor:open_all_diff_views(function(results)
          for _, result in ipairs(results) do
            if result.exit_afterwards then
              self:close()
            end
          end
          -- Reset after all diff views were processed by the user
          self.editor:reset()
        end)
      end
      if not data.tool_calls or #data.tool_calls == 0 then
        -- No tool calls, this means that the chat just stopped. For continuation.
        self:send(vim.trim([[
You are in autonomous mode.
- If you are done with your task use the `complete_task` tool.
- If the task failed also use the `complete_task` tool.
- If you need input from me, use the `ask` tool.
- Otherwise continue with your task given above.
        ]]))
      end
    end,
    on_tool_call_finish = function()
      self:_render_chat()
    end,
  })
  return self
end

function AgentPanel:_setup_layout()
  self:_setup_chat()
  self:_setup_token_info()
  self:_setup_cleanup()
end

function AgentPanel:_setup_chat()
  self.chat_bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_set_option_value(
    'filetype',
    'markdown',
    { buf = self.chat_bufnr }
  )
  vim.cmd('tabnew')
  local ai_buf = Buffers.find_buf_by_name('AI')
  if ai_buf and vim.api.nvim_buf_is_valid(ai_buf) then
    vim.api.nvim_buf_delete(ai_buf, { force = true })
  end
  vim.api.nvim_set_current_buf(self.chat_bufnr)
  vim.api.nvim_buf_set_name(self.chat_bufnr, 'AI')
  self.chat_win = vim.api.nvim_get_current_win()
  vim.api.nvim_set_option_value('wrap', true, { win = self.chat_win })
end

function AgentPanel:_setup_cleanup()
  if self._chat_cleanup_augroup then
    pcall(vim.api.nvim_del_augroup_by_id, self._chat_cleanup_augroup)
    self._chat_cleanup_augroup = nil
  end
  self._chat_cleanup_augroup = vim.api.nvim_create_augroup(
    'AgentPanelChatCleanup' .. self.chat_bufnr,
    { clear = true }
  )
  vim.api.nvim_create_autocmd({ 'BufWipeout', 'BufDelete' }, {
    group = self._chat_cleanup_augroup,
    buffer = self.chat_bufnr,
    callback = function()
      if self and self.close then
        self:close()
      end
    end,
  })
  vim.api.nvim_create_autocmd({ 'WinClosed' }, {
    group = self._chat_cleanup_augroup,
    callback = function(args)
      local winid = tonumber(args.match)
      if winid == self.chat_win then
        if self and self.close then
          self:close()
        end
      end
    end,
  })
end

function AgentPanel:close()
  if self.editor then
    self.editor:close_all_diffviews()
  end
  if self.chat then
    self.chat:cancel()
  end
  if self._chat_cleanup_augroup then
    pcall(vim.api.nvim_del_augroup_by_id, self._chat_cleanup_augroup)
    self._chat_cleanup_augroup = nil
  end
  if self._token_info_augroup then
    pcall(vim.api.nvim_del_augroup_by_id, self._token_info_augroup)
    self._token_info_augroup = nil
  end
  if vim.api.nvim_buf_is_valid(self.chat_bufnr) then
    vim.api.nvim_buf_delete(self.chat_bufnr, { force = true })
  end
  if vim.api.nvim_win_is_valid(self.token_info_win) then
    vim.api.nvim_win_close(self.token_info_win, true)
  end
  if vim.api.nvim_buf_is_valid(self.token_info_bufnr) then
    vim.api.nvim_buf_delete(self.token_info_bufnr, { force = true })
  end
end

---@param msg ai.AdapterMessageContent
---@param self ai.AgentPanel
function AgentPanel:send(msg)
  self.chat:send({
    temperature = 0.1,
    messages = {
      {
        role = 'user',
        content = msg,
      },
    },
  })
end

---@param self ai.AgentPanel
function AgentPanel:_start_chat_thinking_animation()
  self:_stop_chat_thinking_animation()
  if #self.chat.messages == 0 then
    self.thinking_animation = ThinkingAnimation:new(self.chat_bufnr)
    self.thinking_animation:start()
  end
end

function AgentPanel:_stop_chat_thinking_animation()
  if self.thinking_animation then
    self.thinking_animation:stop()
    self.thinking_animation = nil
  end
end

function AgentPanel:_render_chat()
  local bufnr = self.chat_bufnr
  if
    not vim.api.nvim_buf_is_valid(bufnr)
    or not vim.api.nvim_win_is_valid(self.chat_win)
  then
    return
  end

  vim.api.nvim_set_option_value('readonly', false, { buf = bufnr })

  local lines = {}
  local function add(new_lines)
    vim.list_extend(lines, Strings.flatten_lines(new_lines))
  end

  local messages = self.chat.messages
  for i_message, message in ipairs(messages) do
    if message.role == 'user' then
      -- Never show user messages
      if i_message > 1 then
        add({ '' })
      end
      goto continue
    end
    local text = vim.trim(Messages.extract_text(message.content))
    if text ~= '' then
      add(vim.split(text, '\n'))
      if message.tool_calls and #message.tool_calls > 0 then
        add({ '' })
      end
    end
    for i_tool_call, tool_call in ipairs(message.tool_calls or {}) do
      local tool_call_result = message.tool_call_results
        and message.tool_call_results[i_tool_call]
      local tool_definition =
        Tools.find_tool_definition(self.chat.tools, tool_call.tool)
      if tool_definition and tool_definition.render then
        add(tool_definition.render(tool_call, tool_call_result))
      elseif tool_call_result then
        add({ '✅ Using tool "' .. tool_call.tool .. '"' })
      else
        add({ '⏳ Using tool "' .. tool_call.tool .. '"' })
      end
    end
    if message.tool_calls and #message.tool_calls > 0 then
      add({ '' })
    end
    ::continue::
  end

  -- Add bottom padding for token info window
  local padding = 5
  for _ = 1, padding do
    add({ '' })
  end

  local cursor = vim.api.nvim_win_get_cursor(self.chat_win)
  local last_line = vim.api.nvim_buf_line_count(bufnr)
  local should_scroll_down = cursor[1] >= (last_line - padding)

  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)

  if should_scroll_down or self.user_input then
    vim.api.nvim_win_set_cursor(
      self.chat_win,
      { math.max(1, vim.api.nvim_buf_line_count(bufnr) - padding + 1), 0 }
    )
  end

  if self.user_input then
    vim.keymap.set('n', 'i', function()
      require('ai.utils.prompt_input').open_prompt_input({
        prompt = self.user_input.question,
        width = 80,
        save_to_history = false,
      }, function(answer)
        self.user_input.on_answer(answer)
      end)
    end, { buffer = self.chat_bufnr, nowait = true })
  end

  vim.api.nvim_set_option_value('readonly', true, { buf = bufnr })
  self:_render_token_info()
end
function AgentPanel:_setup_token_info()
  self.token_info_bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_set_option_value(
    'bufhidden',
    'wipe',
    { buf = self.token_info_bufnr }
  )
  -- Make the token info window relative to the chat window, not the editor
  local chat_win = self.chat_win
  local chat_win_width = vim.api.nvim_win_get_width(chat_win)
  local chat_win_height = vim.api.nvim_win_get_height(chat_win)
  local token_info_height = 2
  self.token_info_win = vim.api.nvim_open_win(self.token_info_bufnr, false, {
    relative = 'win',
    win = chat_win,
    anchor = 'SW',
    row = chat_win_height,
    col = 0,
    width = chat_win_width,
    height = token_info_height,
    style = 'minimal',
    border = {
      '',
      '─',
      '',
      '',
      '',
      '─',
      '',
      '',
    },
    noautocmd = true,
  })
  vim.api.nvim_set_option_value(
    'winhl',
    'NormalFloat:NormalFloat,FloatBorder:FloatBorder',
    { win = self.token_info_win }
  )

  self:_render_token_info()

  -- Setup autocommand to rerender token info on window or chat window resize
  self._token_info_augroup = vim.api.nvim_create_autocmd(
    { 'VimResized', 'WinResized' },
    {
      group = self._token_info_augroup,
      callback = function()
        self:_render_token_info()
      end,
    }
  )
end

function AgentPanel:_render_token_info()
  local bufnr = self.token_info_bufnr
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end

  local total = self.chat and self.chat:get_total_tokens_used() or {}
  local last = self.chat and self.chat.tokens_used[#self.chat.tokens_used] or {}

  vim.api.nvim_buf_clear_namespace(bufnr, self.token_info_ns, 0, -1)

  ---@param t AdapterTokenInfo
  local function fmt_tokens(t)
    local costs = self.chat and self.chat.adapter:get_costs(t)
    local input = t.input or 0
    local output = t.output or 0
    local input_cost = costs and costs.input or nil
    local output_cost = costs and costs.output or nil
    local total_cost = costs and costs.total or nil

    local result = Numbers.format_integer(input + output)
    if total_cost then
      result = result .. ' [' .. string.format('%.2f', total_cost) .. '$]'
    end
    result = result .. ' (Input: ' .. Numbers.format_integer(input)
    if input_cost then
      result = result .. ' [' .. string.format('%.2f', input_cost) .. '$]'
    end
    result = result .. ' - Output: ' .. Numbers.format_integer(output)
    if output_cost then
      result = result .. ' [' .. string.format('%.2f', output_cost) .. '$])'
    end
    return result
  end

  local lines = {
    'Session: ' .. fmt_tokens(total),
    'Last Message: ' .. fmt_tokens(last),
  }

  -- Use the chat window's width for centering
  local width = vim.api.nvim_win_get_width(self.chat_win)
  local centered_lines = {}
  for _, line in ipairs(lines) do
    local padding = math.floor((width - #line) / 2)
    if padding > 0 then
      table.insert(centered_lines, string.rep(' ', padding) .. line)
    else
      table.insert(centered_lines, line)
    end
  end

  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, centered_lines)

  -- Highlighting
  for i, line in ipairs(centered_lines) do
    local token_start, token_end = string.find(line, '[%d,]+')
    if token_start and token_end then
      vim.api.nvim_buf_set_extmark(
        bufnr,
        self.token_info_ns,
        i - 1,
        token_start - 1,
        {
          end_col = token_end,
          hl_group = 'Number',
        }
      )
    end
    local price_start, price_end = string.find(line, '%[0%.%d%d%$%]')
    if price_start and price_end then
      vim.api.nvim_buf_set_extmark(
        bufnr,
        self.token_info_ns,
        i - 1,
        price_start - 1,
        {
          end_col = price_end,
          hl_group = 'Constant',
        }
      )
    end
    local bracket_start, bracket_end = string.find(line, '%b()')
    if bracket_start and bracket_end then
      vim.api.nvim_buf_set_extmark(
        bufnr,
        self.token_info_ns,
        i - 1,
        bracket_start - 1,
        {
          end_col = bracket_end,
          hl_group = 'Comment',
        }
      )
    end
  end

  local chat_win_height = vim.api.nvim_win_get_height(self.chat_win)
  vim.api.nvim_win_set_config(self.token_info_win, {
    anchor = 'SW',
    width = width,
    height = #centered_lines,
    row = chat_win_height,
    col = 0,
    relative = 'win',
    win = self.chat_win,
  })
end

return AgentPanel
