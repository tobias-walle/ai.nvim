local M = {}

---@class ApplyChangesStrategyOptions
---@field bufnr number
---@field prompt string
---@field start_line number
---@field end_line number

---@param options ApplyChangesStrategyOptions
function M.apply_changes_with_fast_edit_strategy(options)
  local adapter = require('ai.config').get_command_adapter()

  local bufnr = options.bufnr
  local prompt = options.prompt

  local cancelled = false

  -- Prepare cancellation of ai call
  local job
  local function cleanup()
    cancelled = true
    job:stop()
  end

  -- Prepare popup
  local preview_popup = require('ai.utils.popup').open_response_preview({
    bufnr = bufnr,
    on_cancel = cleanup,
    on_confirm = function(response_lines)
      local response = table.concat(response_lines, '\n')
      local code = require('ai.utils.treesitter').extract_code(response) or ''
      require('ai.agents.editor').apply_edits({
        bufnr = bufnr,
        patch = code,
      })
    end,
  })

  -- Clear content to be replaced
  vim.api.nvim_buf_set_lines(preview_popup.bufnr, 0, -1, false, {})

  local function render_preview(response)
    local code_lines = vim.split(response, '\n')
    vim.api.nvim_buf_set_lines(preview_popup.bufnr, 0, -1, false, code_lines)
  end
  job = adapter:chat_stream({
    system_prompt = require('ai.prompts').system_prompt,
    messages = {
      {
        role = 'user',
        content = prompt,
      },
    },
    temperature = 0.1,
    on_update = function(update)
      if cancelled then
        return
      end
      render_preview(update.response .. ' ⏳')
    end,
    on_exit = function(data)
      render_preview(data.response)
      cleanup()
    end,
  })
end

---@param options ApplyChangesStrategyOptions
function M.apply_changes_with_replace_selection_strategy(options)
  local adapter = require('ai.config').get_command_adapter()

  local bufnr = options.bufnr
  local prompt = options.prompt
  local start_line = options.start_line
  local end_line = options.end_line

  local cancelled = false

  -- Prepare cancellation of ai call
  local job
  local function cleanup()
    cancelled = true
    job:stop()
  end

  -- Diffview
  local diff_bufnr = require('ai.utils.diff_view').render_diff_view({
    bufnr = bufnr,
    callback = function()
      -- Cleanup after result was either rejected or accepted
      cleanup()
    end,
  })

  local function render_response(response)
    local code = require('ai.utils.treesitter').extract_code(response) or ''
    -- Replace trailing newline
    code = code:gsub('\n$', '')
    local code_lines = vim.split(code, '\n')
    vim.api.nvim_buf_set_lines(
      diff_bufnr,
      start_line - 1,
      end_line,
      false,
      code_lines
    )
    -- Update end_line to reflect changes
    end_line = start_line + #code_lines - 1
  end

  job = adapter:chat_stream({
    system_prompt = require('ai.prompts').system_prompt,
    messages = {
      {
        role = 'user',
        content = prompt,
      },
    },
    temperature = 0.1,
    on_update = function(update)
      if cancelled then
        return
      end
      render_response(update.response)
    end,
    on_exit = function(data)
      render_response(data.response)
      cleanup()
    end,
  })
end

return M
