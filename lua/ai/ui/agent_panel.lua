---@class AgentPanel.Options
---@field adapter Adapter
---@field focused_bufnr number

---@class AgentPanel: AgentPanel.Options
---@field editor Editor
---@field chat Chat
---@field chat_thinking_animation ThinkingAnimation | nil
---@field chat_bufnr number
local AgentPanel = {}
AgentPanel.__index = AgentPanel

local ThinkingAnimation = require('ai.utils.thinking_animation')
local Editor = require('ai.agents.editor')

---@param opts AgentPanel.Options
---@return AgentPanel
function AgentPanel.new(opts)
  local self = setmetatable({}, AgentPanel)
  vim.tbl_extend('force', self, opts)

  -- Render Layout
  self:_setup_layout()

  -- Setup Editor
  self.editor = Editor:new()

  -- Setup Chat
  self.chat = require('ai.utils.chat'):new({
    adapter = opts.adapter,
    on_chat_start = function()
      self.editor:reset()
      self:_start_chat_thinking_animation()
    end,
    on_chat_update = function()
      self:_stop_chat_thinking_animation()
      self:_render_chat()
    end,
    on_chat_exit = function(update)
      self:_render_chat()
      local blocks = require('ai.utils.markdown').extract_code(update.response)
      -- self.editor:reset()
      -- self.editor:add_markdown_block_patches(self.focused_bufnr, blocks)
    end,
    on_tool_call_start = function()
      self:_render_chat()
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
---@param self AgentPanel
function AgentPanel:send(msg)
  self.chat:send({
    system_prompt = require('ai.prompts').system_prompt,
    temperature = 0.1,
    messages = {
      {
        role = 'user',
        content = msg,
      },
    },
  })
end

---@param self AgentPanel
function AgentPanel:_start_chat_thinking_animation()
  self:_stop_chat_thinking_animation()
  self.thinking_animation = ThinkingAnimation:new(self.chat_bufnr)
  self.thinking_animation:start()
end

---@param self AgentPanel
function AgentPanel:_stop_chat_thinking_animation()
  if self.thinking_animation then
    self.thinking_animation:stop()
    self.thinking_animation = nil
  end
end

---@param self AgentPanel
function AgentPanel:_setup_layout()
  self.chat_bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_set_option_value(
    'filetype',
    'markdown',
    { buf = self.chat_bufnr }
  )
  vim.cmd('tabnew')
  vim.api.nvim_set_current_buf(self.chat_bufnr)
  vim.api.nvim_buf_set_name(self.chat_bufnr, 'AI')
  local win = vim.api.nvim_get_current_win()
  vim.api.nvim_set_option_value('wrap', true, { win = win })
end

---@param self AgentPanel
function AgentPanel:_render_chat()
  local bufnr = self.chat_bufnr
  vim.api.nvim_set_option_value('modifiable', true, { buf = bufnr })

  local messages = self.chat.messages
  for i_message, message in ipairs(messages) do
    vim.api.nvim_buf_set_lines(
      bufnr,
      -1,
      -1,
      false,
      vim.split(
        require('ai.utils.messages').extract_text(message.content),
        '\n'
      )
    )
    for i_tool_call, tool_call in ipairs(message.tool_calls) do
      vim.api.nvim_buf_set_lines(bufnr, -1, -1, false, { '' })
      local tool_call_result = message.tool_call_results
        and message.tool_call_results[i_tool_call]
      if tool_call_result then
        vim.api.nvim_buf_set_lines(
          bufnr,
          -1,
          -1,
          false,
          { '✅ Using tool "' .. tool_call.tool .. '"' }
        )
      else
        vim.api.nvim_buf_set_lines(
          bufnr,
          -1,
          -1,
          false,
          { '⏳ Using tool "' .. tool_call.tool .. '"' }
        )
      end
    end
    if i_message < #messages then
      vim.api.nvim_buf_set_lines(bufnr, -1, -1, false, { '', '---', '' })
    end
  end

  -- Scroll to end
  local win = vim.fn.bufwinid(bufnr)
  if win ~= -1 and win == vim.api.nvim_get_current_win() then
    vim.api.nvim_win_set_cursor(win, { vim.api.nvim_buf_line_count(bufnr), 0 })
  end

  vim.api.nvim_set_option_value('modifiable', false, { buf = bufnr })
  vim.api.nvim_set_option_value('readonly', true, { buf = bufnr })
  vim.api.nvim_set_option_value('filetype', 'markdown', { buf = bufnr })
end

return AgentPanel
