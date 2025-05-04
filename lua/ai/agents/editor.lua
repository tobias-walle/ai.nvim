local M = {}

local string_utils = require('ai.utils.strings')

---@param options { bufnr: number, patch: string }
---@param callback? fun(): nil
function M.apply_edits(options, callback)
  local adapter = require('ai.config').get_editor_adapter()
  vim.notify(
    '[ai] Trigger edit with ' .. adapter.name .. ':' .. adapter.model,
    vim.log.levels.INFO
  )
  local bufnr = options.bufnr
  local patch = options.patch

  local content_lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local original_content = table.concat(content_lines, '\n')
  local language = vim.api.nvim_buf_get_option(bufnr, 'filetype')

  local job
  local start_time = vim.uv.hrtime()

  local cancelled = false
  local function cleanup()
    cancelled = true
    job:stop()
    if callback then
      callback()
    end
  end

  local diff_bufnr = require('ai.utils.diff_view').render_diff_view({
    bufnr = bufnr,
    callback = function()
      -- Cleanup after result was either rejected or accepted
      cleanup()
    end,
  })

  vim.api.nvim_buf_set_option(diff_bufnr, 'foldlevel', 0)

  local notify_options = {
    id = 'ai_edit',
    title = 'AI Editor',
  }
  local function render_response(code, override)
    -- Remove trailing line break
    code = code:gsub('\n$', '')
    local code_lines = vim.split(code, '\n')
    if override == true then
      vim.api.nvim_buf_set_lines(diff_bufnr, 0, -1, false, code_lines)
    else
      vim.api.nvim_buf_set_lines(diff_bufnr, 0, #code_lines, false, code_lines)
    end
    vim.notify(
      '⏳ Fast Edit ' .. #code_lines .. '/' .. #content_lines,
      vim.log.levels.INFO,
      notify_options
    )
  end

  job = adapter:chat_stream({
    system_prompt = require('ai.prompts').system_prompt_editor,
    messages = {
      {
        role = 'user',
        content = string_utils.replace_placeholders(
          require('ai.prompts').user_prompt_editor,
          {
            language = language,
            original_content = original_content,
            patch_content = patch,
          }
        ),
      },
    },
    prediction = {
      type = 'content',
      content = string_utils.replace_placeholders(
        require('ai.prompts').prediction_editor,
        {
          language = language,
          original_content = original_content,
        }
      ),
    },
    temperature = 0,
    on_update = function(update)
      if cancelled then
        return
      end

      local code = require('ai.utils.treesitter').extract_code(update.response)
        or ''
      render_response(code .. ' ⏳')
    end,
    on_exit = function(data)
      local code = require('ai.utils.treesitter').extract_code(data.response)
        or ''
      render_response(code, true)
      local elapsed_time = (vim.uv.hrtime() - start_time) / 1e9
      vim.notify(
        '[ai] Input Tokens: '
          .. data.tokens.input
          .. '; Output Tokens: '
          .. data.tokens.output
          .. '; Prediction Tokens: '
          .. data.tokens.accepted_prediction_tokens
          .. '; Time: '
          .. string.format('%.2f', elapsed_time)
          .. 's',
        vim.log.levels.INFO,
        notify_options
      )
      vim.api.nvim_buf_set_option(diff_bufnr, 'foldlevel', 0)
      cleanup()
    end,
  })
end

return M
