local M = {}

local string_utils = require('ai.utils.strings')

---@param options { bufnr: number, patch: string }
---@param callback? fun(): nil
function M.apply_edits(options, callback)
  local adapter_nano = require('ai.config').parse_model_string('default:nano')
  local adapter_mini = require('ai.config').parse_model_string('default:mini')
  local bufnr = options.bufnr
  local patch = options.patch

  local content_lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local original_content = table.concat(content_lines, '\n')
  local language = vim.api.nvim_get_option_value('filetype', { buf = bufnr })

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
  local diff_win
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

  local start_time
  local chat = require('ai.utils.chat'):new({
    adapter = adapter_nano,
    on_chat_start = function()
      start_time = vim.uv.hrtime()
    end,
    on_chat_update = function(update)
      render_response(update, false)
    end,
    on_chat_exit = function(data)
      render_response(data, true)
      local elapsed_time = (vim.uv.hrtime() - start_time) / 1e9
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
      vim.api.nvim_set_option_value('foldlevel', 0, { win = diff_win })
      on_completion()
    end,
  })

  ---@param msg string
  ---@param adapter Adapter
  local function send(msg, adapter)
    vim.notify(
      '[ai] Trigger edit with ' .. adapter.name .. ':' .. adapter.model,
      vim.log.levels.INFO
    )
    chat:send({
      adapter = adapter,
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

  local prompt = string_utils.replace_placeholders(
    require('ai.prompts').user_prompt_editor,
    {
      language = language,
      original_content = original_content,
      patch_content = patch,
    }
  )

  diff_bufnr, diff_win = require('ai.utils.diff_view').render_diff_view({
    bufnr = bufnr,
    on_retry = function()
      chat:clear()
      send(prompt, adapter_mini)
    end,
    callback = function()
      on_completion()
    end,
  })
  vim.api.nvim_set_option_value('foldlevel', 0, { win = diff_win })

  local placeholder = require('ai.prompts').unchanged_placeholder
  local has_placeholders = patch:find(placeholder) ~= nil
  if has_placeholders then
    send(prompt, adapter_nano)
  else
    -- If there are no placeholders we can just apply the patch directly
    vim.api.nvim_buf_set_lines(diff_bufnr, 0, -1, false, vim.split(patch, '\n'))
  end
end

return M
