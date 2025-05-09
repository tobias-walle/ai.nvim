local M = {}

local open_prompt_input = require('ai.utils.prompt_input').open_prompt_input
local ThinkingAnimation = require('ai.utils.thinking_animation')

---@class ApplyChangesStrategyOptions
---@field adapter Adapter
---@field bufnr number
---@field prompt string
---@field start_line number
---@field end_line number

---@param options ApplyChangesStrategyOptions
function M.apply_changes_with_fast_edit_strategy(options)
  local adapter = options.adapter
  local adapter_thinking =
    require('ai.config').parse_model_string('default:thinking')

  local bufnr = options.bufnr
  local prompt = options.prompt

  ---@type ResponsePreviewResult
  local preview_popup

  local thinking_animation
  local chat = require('ai.utils.chat'):new({
    adapter = adapter,
    on_chat_start = function()
      assert(
        preview_popup ~= nil,
        'preview_popup must be initialized before chat starts'
      )
      -- Reset view with animation
      if thinking_animation then
        thinking_animation:stop()
      end
      thinking_animation = ThinkingAnimation:new(preview_popup.bufnr)
      thinking_animation:start()
    end,
    on_chat_update = function(update)
      if thinking_animation then
        thinking_animation:stop()
        thinking_animation = nil
      end
      local code_lines = vim.split(update.response, '\n')
      vim.api.nvim_buf_set_lines(preview_popup.bufnr, 0, -1, false, code_lines)
      local last_row = #code_lines
      local last_col = #code_lines > 0 and #code_lines[last_row] or 0
      vim.api.nvim_win_set_cursor(0, { last_row, last_col })
    end,
  })

  ---@param msg string
  ---@param override_adapter? Adapter
  local function send(msg, override_adapter)
    chat:send({
      adapter = override_adapter,
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

  -- Prepare popup
  preview_popup = require('ai.utils.popup').open_response_preview({
    bufnr = bufnr,
    on_cancel = function()
      chat:cancel()
    end,
    on_retry = function()
      open_prompt_input({
        prompt = 'Retry',
        enable_thinking_option = true,
      }, function(retry_prompt, flags)
        if retry_prompt then
          send(
            retry_prompt == '' and 'Try again!' or retry_prompt,
            flags.model == 'thinking' and adapter_thinking or nil
          )
        end
      end)
    end,
    on_confirm = function(response_lines)
      local response = table.concat(response_lines, '\n')
      local blocks = require('ai.utils.markdown').extract_code(response)
      require('ai.agents.editor').apply_markdown_code_blocks(bufnr, blocks)
    end,
  })

  send(prompt)
end

---@param options ApplyChangesStrategyOptions
function M.apply_changes_with_replace_selection_strategy(options)
  local adapter = options.adapter

  local bufnr = options.bufnr
  local prompt = options.prompt
  local start_line = options.start_line
  local end_line = options.end_line

  local diff_bufnr
  local function render_response(response)
    if not diff_bufnr then
      vim.notify('Missing diff_bufnr', vim.log.levels.ERROR)
      return
    end
    local extracted = require('ai.utils.markdown').extract_code(response)
    local code_lines = extracted[#extracted].lines
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

  local chat = require('ai.utils.chat'):new({
    adapter = adapter,
    on_chat_start = function()
      vim.notify(
        '[ai] Edit with ' .. adapter.name .. ':' .. adapter.model,
        vim.log.levels.INFO
      )

      -- Reset diffview
      vim.api.nvim_buf_set_lines(
        diff_bufnr,
        0,
        -1,
        true,
        vim.api.nvim_buf_get_lines(bufnr, 0, -1, true)
      )

      -- Reset state
      start_line = options.start_line
      end_line = options.end_line
    end,
    on_chat_update = function(update)
      render_response(update.response)
    end,
  })

  ---@param msg string
  local function send(msg)
    chat:send({
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

  diff_bufnr = require('ai.utils.diff_view').render_diff_view({
    bufnr = bufnr,
    callback = function()
      -- Cleanup after result was either rejected or accepted
      chat:cancel()
    end,
    on_retry = function()
      open_prompt_input({ prompt = 'Retry' }, function(retry_prompt)
        if retry_prompt then
          send(retry_prompt == '' and 'Try again!' or retry_prompt)
        end
      end)
    end,
  })

  send(prompt)
end

return M
