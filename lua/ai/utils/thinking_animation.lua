---@class ai.ThinkingAnimation
---@field bufnr number
---@field timer uv.uv_timer_t?
---@field frames string[]
---@field i number
---@field started_at number?
local ThinkingAnimation = {}
ThinkingAnimation.__index = ThinkingAnimation

function ThinkingAnimation:new(bufnr)
  local obj = setmetatable({
    bufnr = bufnr,
    timer = nil,
    frames = {
      '🤔 Thinking…',
      '🧠 Thinking…',
      '💭 Thinking…',
      '⏳ Thinking…',
      '🔄 Thinking…',
      '✨ Thinking…',
      '🤖 Thinking…',
      '💡 Thinking…',
    },
    i = 1,
    started_at = nil,
  }, self)
  return obj
end

function ThinkingAnimation:start()
  self:stop()
  self.started_at = vim.loop.hrtime()
  self.timer = vim.uv.new_timer()
  self.timer:start(
    0,
    500,
    vim.schedule_wrap(function()
      if not vim.api.nvim_buf_is_valid(self.bufnr) then
        self:stop()
        return
      end
      local frame = self.frames[self.i]
      local seconds = 0
      if self.started_at then
        seconds = math.floor((vim.loop.hrtime() - self.started_at) / 1e9)
      end
      local frame_with_time = frame .. ' (' .. seconds .. 's)'
      local win = vim.fn.bufwinid(self.bufnr)
      local width = vim.api.nvim_win_get_width(win)
      local pad = math.max(
        0,
        math.floor((width - vim.fn.strdisplaywidth(frame_with_time)) / 2)
      )
      local centered = string.rep(' ', pad) .. frame_with_time

      -- compute vertical padding for full centering
      local height = vim.api.nvim_win_get_height(win)
      local vpad = math.max(0, math.floor((height - 1) / 2))
      local bottom = height - vpad - 1
      local lines = {}
      for _ = 1, vpad do
        lines[#lines + 1] = ''
      end
      lines[#lines + 1] = centered
      for _ = 1, bottom do
        lines[#lines + 1] = ''
      end

      vim.api.nvim_buf_set_lines(self.bufnr, 0, -1, false, lines)
      self.i = self.i % #self.frames + 1
    end)
  )
end

function ThinkingAnimation:stop()
  if self.timer then
    self.timer:stop()
    self.timer:close()
    self.timer = nil
  end
  self.started_at = nil
end

return ThinkingAnimation
