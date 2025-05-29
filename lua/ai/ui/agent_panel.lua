local EventEmitter = require('ai.utils.event_emitter')
local Buffers = require('ai.utils.buffers')

---@class ai.AgentPanel.Options
---@field adapter ai.Adapter
---@field focused_bufnr number

---@class ai.AgentPanel: ai.AgentPanel.Options
---@field editor ai.Editor
---@field on_completion ai.EventEmitter<ai.CompleteTaskTool.Result>
---@field chat ai.Chat
---@field chat_thinking_animation ai.ThinkingAnimation | nil
---@field chat_bufnr number
---@field chat_win number
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

  -- Render Layout
  self:_setup_layout()

  -- Setup Chat
  self.editor = Editor:new()
  self.on_completion = EventEmitter.new({ emit_initially = false })
  self.chat = require('ai.utils.chat'):new({
    adapter = opts.adapter,
    system_prompt = require('ai.prompts').system_prompt_agent,
    tools = {
      require('ai.tools.file_read').create_file_read_tool(),
      require('ai.tools.file_write').create_file_write_tool({
        editor = self.editor,
      }),
      require('ai.tools.file_update').create_file_update_tool({
        editor = self.editor,
      }),
      require('ai.tools.complete_task').create_complete_task_tool({
        on_completion = function(result)
          self.on_completion:notify(result)
        end,
      }),
    },
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
    after_all_tool_calls_started = function()
      self:_render_chat()
      if self.editor:has_any_patches() then
        self.editor:open_all_diff_views(function()
          -- Reset after all diff views were processed by the user
          self.editor:reset()
        end)
      end
    end,
    on_tool_call_finish = function()
      self:_render_chat()
    end,
  })
  return self
end

function AgentPanel:close()
  if vim.api.nvim_buf_is_valid(self.chat_bufnr) then
    vim.api.nvim_buf_delete(self.chat_bufnr, { force = true })
  end
end

---@param msg AdapterMessageContent
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

---@param self ai.AgentPanel
function AgentPanel:_stop_chat_thinking_animation()
  if self.thinking_animation then
    self.thinking_animation:stop()
    self.thinking_animation = nil
  end
end

---@param self ai.AgentPanel
function AgentPanel:_setup_layout()
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

---@param self ai.AgentPanel
function AgentPanel:_render_chat()
  local bufnr = self.chat_bufnr

  local lines = {}
  local function add(new_lines)
    vim.list_extend(lines, new_lines)
  end

  local messages = self.chat.messages
  for i_message, message in ipairs(messages) do
    if message.role == 'user' then
      -- Skip user messages for now. Just render a separator.
      if i_message > 1 then
        add({ '', '---', '' })
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

  local cursor = vim.api.nvim_win_get_cursor(self.chat_win)
  local last_line = vim.api.nvim_buf_line_count(bufnr)
  local should_scroll_down = cursor[1] == last_line

  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)

  if should_scroll_down then
    vim.api.nvim_win_set_cursor(
      self.chat_win,
      { vim.api.nvim_buf_line_count(bufnr), 0 }
    )
  end
end

return AgentPanel
