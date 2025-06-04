local M = {}

local open_prompt_input = require('ai.utils.prompt_input').open_prompt_input

---@class ApplyChangesStrategyOptions
---@field adapter ai.Adapter
---@field bufnr number
---@field prompt ai.AdapterMessageContent
---@field start_line number
---@field end_line number

---@param options ApplyChangesStrategyOptions
function M.apply_changes_with_replace_selection_strategy(options)
  local adapter = options.adapter

  local bufnr = options.bufnr
  local prompt = options.prompt
  local start_line = options.start_line
  local end_line = options.end_line

  ---@type ai.RenderDiffView | nil
  local diffview
  local function render_response(response)
    if not diffview then
      vim.notify('Missing diffview', vim.log.levels.ERROR)
      return
    end
    local extracted = require('ai.utils.markdown').extract_code(response)
    local code_lines = extracted[#extracted] and extracted[#extracted].lines
      or {}
    vim.api.nvim_buf_set_lines(
      diffview.bufnr,
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
        ---@diagnostic disable-next-line: need-check-nil
        diffview.bufnr,
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

  ---@param msg ai.AdapterMessageContent
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

  diffview = require('ai.utils.diff_view').render_diff_view({
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
