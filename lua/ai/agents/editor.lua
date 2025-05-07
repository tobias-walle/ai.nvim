local M = {}

local string_utils = require('ai.utils.strings')

---@param options { bufnr: number, patch: string }
---@param callback? fun(): nil
function M.apply_edits(options, callback)
  local adapter = require('ai.config').parse_model_string('default:nano')
  vim.notify(
    '[ai] Trigger edit with ' .. adapter.name .. ':' .. adapter.model,
    vim.log.levels.INFO
  )
  local bufnr = options.bufnr
  local patch = options.patch

  local content_lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local original_content = table.concat(content_lines, '\n')
  local language = vim.api.nvim_buf_get_option(bufnr, 'filetype')

  local function on_completion()
    if callback then
      callback()
    end
  end

  local notify_options = {
    id = 'ai_edit',
    title = 'AI Editor',
  }

  local diff_bufnr
  local function render_response(update, override)
    if not diff_bufnr then
      vim.notify('Missing diff_bufnr', vim.log.levels.ERROR)
      return
    end

    local code = require('ai.utils.treesitter').extract_code(update.response)
      or ''
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

  local chat = require('ai.utils.chat'):new({
    adapter = adapter,
    on_chat_start = function() end,
    on_chat_update = function(update)
      render_response(update, false)
    end,
    on_chat_exit = function(data)
      render_response(data, true)
      local elapsed_time = (vim.uv.hrtime() - vim.uv.hrtime()) / 1e9
      vim.notify(
        '[ai] Input Tokens: '
          .. (data.tokens and data.tokens.input or '')
          .. '; Output Tokens: '
          .. (data.tokens and data.tokens.output or '')
          .. '; Prediction Tokens: '
          .. (data.tokens and data.tokens.accepted_prediction_tokens or '')
          .. '; Time: '
          .. string.format('%.2f', elapsed_time)
          .. 's',
        vim.log.levels.INFO,
        notify_options
      )
      vim.api.nvim_buf_set_option(diff_bufnr, 'foldlevel', 0)
      on_completion()
    end,
  })

  ---@param msg string
  local function send(msg)
    chat:send({
      system_prompt = require('ai.prompts').system_prompt_editor,
      messages = {
        {
          role = 'user',
          content = msg,
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
    })
  end

  diff_bufnr = require('ai.utils.diff_view').render_diff_view({
    bufnr = bufnr,
    on_retry = function()
      vim.ui.input({ prompt = 'Retry' }, function(retry_prompt)
        if retry_prompt then
          send('Try again! ' .. retry_prompt)
        end
      end)
    end,
    callback = function()
      on_completion()
    end,
  })
  vim.api.nvim_buf_set_option(diff_bufnr, 'foldlevel', 0)

  send(
    string_utils.replace_placeholders(
      require('ai.prompts').user_prompt_editor,
      {
        language = language,
        original_content = original_content,
        patch_content = patch,
      }
    )
  )
end

return M
