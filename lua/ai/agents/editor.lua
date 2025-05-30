local string_utils = require('ai.utils.strings')
local EventEmitter = require('ai.utils.event_emitter')

---@class ai.Editor.Patch
---@field bufnr number
---@field patch string

---@class ai.Editor.FilePatch
---@field file string
---@field patch string

---@class ai.Editor.Job
---@field patch ai.Editor.Patch
---@field result string
---@field is_completed boolean
---@field apply_result? ai.ApplyResult
---@field retry fun()
---@field cancel fun()

---@class ai.Editor
---@field job_by_bufnr table<number, ai.Editor.Job>
---@field event_emitters_by_bufnr table<number, ai.EventEmitter<ai.Editor.Job>>
---@field diffviews_by_bufnr table<number, ai.RenderDiffView>
local Editor = {}
Editor.__index = Editor

---@return ai.Editor
function Editor:new()
  local instance = setmetatable({}, self)
  instance.job_by_bufnr = {}
  instance.event_emitters_by_bufnr = {}
  instance.diffviews_by_bufnr = {}
  return instance
end

---Check if there are any patches (jobs) currently tracked by the editor.
---@return boolean
function Editor:has_any_patches()
  for _, _ in pairs(self.job_by_bufnr) do
    return true
  end
  return false
end

---@param self ai.Editor
function Editor:reset()
  self:close_all_diffviews()
  for _, job in pairs(self.job_by_bufnr) do
    job.cancel()
  end
  self.job_by_bufnr = {}
  self.event_emitters_by_bufnr = {}
end

---@param bufnr number
---@param blocks MarkdownCodeBlock[]
---@param self ai.Editor
function Editor:add_markdown_block_patches(bufnr, blocks)
  local current_buf_filename = vim.api.nvim_buf_get_name(bufnr)
  for _, block in ipairs(blocks) do
    local absolute_block_filename = block.file
        and vim.fn.fnamemodify(block.file, ':p')
      or current_buf_filename

    local bufnr_to_edit = vim.fn.bufnr(absolute_block_filename, false)
    if bufnr_to_edit == -1 then
      bufnr_to_edit = vim.api.nvim_create_buf(true, false)
      vim.api.nvim_buf_set_name(bufnr_to_edit, absolute_block_filename)
      local filetype = vim.filetype.match({ filename = absolute_block_filename })
        or 'text'
      vim.api.nvim_set_option_value(
        'filetype',
        filetype,
        { buf = bufnr_to_edit }
      )
    end
    local code_lines = block.lines
    local code = vim.fn.join(code_lines, '\n')
    self:add_patch({
      bufnr = bufnr_to_edit,
      patch = code,
    })
  end
end

---@param patch ai.Editor.FilePatch
---@param self ai.Editor
---@return integer bufnr
function Editor:add_file_patch(patch)
  local absolute_block_filename = vim.fn.fnamemodify(patch.file, ':p')

  local bufnr_to_edit = vim.fn.bufnr(absolute_block_filename, false)
  if bufnr_to_edit == -1 then
    bufnr_to_edit = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_buf_set_name(bufnr_to_edit, absolute_block_filename)
    local filetype = vim.filetype.match({ filename = absolute_block_filename })
      or 'text'
    vim.api.nvim_set_option_value('filetype', filetype, { buf = bufnr_to_edit })
  end
  self:add_patch({
    bufnr = bufnr_to_edit,
    patch = patch.patch,
  })

  return bufnr_to_edit
end

---@param patch ai.Editor.Patch
---@param self ai.Editor
function Editor:add_patch(patch)
  local adapter_mini = require('ai.config').parse_model_string('default:mini')
  local bufnr = patch.bufnr
  local content_lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local original_content = table.concat(content_lines, '\n')
  local language = vim.api.nvim_get_option_value('filetype', { buf = bufnr })

  ---@type ai.Editor.Job
  local job = {
    patch = patch,
    result = '',
    is_completed = false,
    retry = function() end,
    cancel = function() end,
  }
  self:_ensure_event_emitter(bufnr)
  self.job_by_bufnr[bufnr] = job

  ---@param update string
  ---@param completed boolean
  local function process_update(update, completed)
    local extracted = require('ai.utils.markdown').extract_code(update)
    local patched_content = extracted[#extracted] and extracted[#extracted].code
    job.result = patched_content or update
    job.is_completed = completed
    self:notify_subscribers(bufnr)
  end

  local prompt = string_utils.replace_placeholders(
    require('ai.prompts').editor_user_prompt,
    {
      language = language,
      original_content = original_content,
      patch_content = patch.patch,
    }
  )

  local chat

  ---@param msg string
  ---@param adapter ai.Adapter
  local function send(msg, adapter)
    vim.notify(
      '[ai] Trigger edit with ' .. adapter.name .. ':' .. adapter.model,
      vim.log.levels.INFO
    )
    chat:send({
      adapter = adapter,
      system_prompt = require('ai.prompts').editor_system_prompt,
      messages = {
        { role = 'user', content = msg },
      },
      prediction = {
        type = 'content',
        content = string_utils.replace_placeholders(
          require('ai.prompts').editor_predicted_output,
          {
            language = language,
            original_content = original_content,
          }
        ),
      },
      temperature = 0,
    })
  end

  function job.retry()
    chat:clear()
    -- Use an upgraded model
    send(prompt, adapter_mini)
  end

  local placeholder = require('ai.prompts').placeholder_unchanged

  chat = require('ai.utils.chat'):new({
    adapter = adapter_mini,
    on_chat_update = function(update)
      local has_still_placeholders = update.response:find(placeholder) ~= nil
      if has_still_placeholders then
        job.retry()
      else
        process_update(update.response, false)
      end
    end,
    on_chat_exit = function(data)
      process_update(data.response, true)
    end,
  })

  function job.cancel()
    chat:clear()
  end

  local has_placeholders = patch.patch:find(placeholder) ~= nil
  if has_placeholders then
    send(prompt, adapter_mini)
  else
    -- If there are no placeholders we can just apply the patch directly
    process_update(patch.patch, true)
  end
end

---@param self ai.Editor
---@param callback? fun()
function Editor:open_all_diff_views(callback)
  self:close_all_diffviews()
  local total = 0
  local completed = 0
  for bufnr, _ in pairs(self.job_by_bufnr) do
    total = total + 1
    self:open_diff_view(bufnr, function()
      completed = completed + 1
      if completed == total and callback then
        callback()
      end
    end)
  end
  if total == 0 and callback then
    callback()
  end
end

---@param self ai.Editor
---@param bufnr number
---@param callback? fun()
function Editor:open_diff_view(bufnr, callback)
  self:close_diffview(bufnr)
  local job = self.job_by_bufnr[bufnr]
  if not job then
    vim.notify(
      'Job for bufnr "' .. bufnr .. '" not found',
      vim.log.levels.ERROR
    )
    return
  end

  local diffview = require('ai.utils.diff_view').render_diff_view({
    bufnr = bufnr,
    on_retry = job.retry,
    callback = function(result)
      job.apply_result = result
      self:notify_subscribers(bufnr)
      -- Cleanup afterwards
      job.cancel()
      self.job_by_bufnr[bufnr] = nil
      self:close_diffview(bufnr)
      if callback then
        callback()
      end
      self.diffviews_by_bufnr[bufnr] = nil
      self:_clear_event_emitter(bufnr)
    end,
  })

  -- Store the diffview references
  self.diffviews_by_bufnr[bufnr] = diffview
  vim.api.nvim_set_option_value('foldlevel', 0, { win = diffview.win })

  self:subscribe(bufnr, function(update)
    if not vim.api.nvim_buf_is_valid(diffview.bufnr) then
      return
    end
    vim.api.nvim_buf_set_lines(
      diffview.bufnr,
      0,
      -1,
      false,
      vim.split(update.result, '\n')
    )
    if update.is_completed and vim.api.nvim_win_is_valid(diffview.win) then
      vim.api.nvim_set_option_value('foldlevel', 0, { win = diffview.win })
    end
  end)
end

---@param self ai.Editor
---@param bufnr number
function Editor:close_diffview(bufnr)
  local diffview = self.diffviews_by_bufnr[bufnr]
  if not diffview then
    return
  end
  self:_clear_event_emitter(bufnr)
  diffview.close()
  self.diffviews_by_bufnr[bufnr] = nil
end

---@param self ai.Editor
function Editor:close_all_diffviews()
  for bufnr, _ in pairs(self.diffviews_by_bufnr) do
    self:close_diffview(bufnr)
  end
end

---@param bufnr number
---@param callback fun(job: ai.Editor.Job)
function Editor:subscribe(bufnr, callback)
  self:_ensure_event_emitter(bufnr)
  self.event_emitters_by_bufnr[bufnr]:subscribe(callback)
end

---@param bufnr number
function Editor:notify_subscribers(bufnr)
  if self.event_emitters_by_bufnr[bufnr] and self.job_by_bufnr[bufnr] then
    self.event_emitters_by_bufnr[bufnr]:notify(self.job_by_bufnr[bufnr])
  end
end

---@param self ai.Editor
---@param bufnr number
function Editor:_ensure_event_emitter(bufnr)
  if not self.event_emitters_by_bufnr[bufnr] then
    self.event_emitters_by_bufnr[bufnr] =
      EventEmitter.new({ emit_initially = true })
  end
end

---@param self ai.Editor
---@param bufnr number
function Editor:_clear_event_emitter(bufnr)
  self.event_emitters_by_bufnr[bufnr] = nil
end

return Editor
