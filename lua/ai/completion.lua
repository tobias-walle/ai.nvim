-- Define a module
local M = {}

local system_prompt = [[
You are acting as a autocompletion engine.
You are getting some code as input with the cursor position marked as <|cursor|> and ONLY answer with the autocompletion suggestion without repeating the input or the cursor position.
DO NOT wrap your response in a code block.
]]

local ns_id = vim.api.nvim_create_namespace('ai_completion')

function M.trigger_completion()
  local config = require('ai.config').config
  vim.notify(
    '[ai] Trigger completion with '
      .. config.provider.name
      .. ':'
      .. config.provider.model,
    vim.log.levels.INFO
  )
  -- Get the API key from environment variable
  local api_key = os.getenv('OPENAI_API_KEY')
  if not api_key then
    vim.notify(
      '[ai] OpenAI API key not found in environment variable OPENAI_API_KEY',
      vim.log.levels.ERROR
    )
    return
  end

  -- Get the buffer content
  local bufnr = vim.api.nvim_get_current_buf()
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)

  -- Get the cursor position
  local row, col = unpack(vim.api.nvim_win_get_cursor(0))

  -- Insert the cursor marker at the current position
  local cursor_line = lines[row]
  local before = cursor_line:sub(1, col)
  local after = cursor_line:sub(col + 1)
  lines[row] = before .. '<|cursor|>' .. after

  local content = table.concat(lines, '\n')

  local suggestion = ''

  local job_id = config.provider:stream({
    system_prompt = system_prompt,
    messages = {
      { role = 'user', content = content },
    },
    temperature = 0,
    max_tokens = 128,
    on_data = function(delta)
      suggestion = suggestion .. delta
      require('ai.render').render_ghost_text({
        text = suggestion,
        buffer = bufnr,
        ns_id = ns_id,
        row = row,
        col = col,
      })
    end,
  })

  -- Functions to accept or cancel the suggestion
  local autocmd_id

  local function cleanup()
    vim.fn.jobstop(job_id)
    vim.api.nvim_buf_clear_namespace(bufnr, ns_id, 0, -1)
    vim.keymap.del(
      'i',
      require('ai.config').config.mappings.accept_suggestion,
      { buffer = bufnr }
    )
    vim.api.nvim_del_autocmd(autocmd_id)
  end

  local function accept_suggestion()
    -- Insert the suggestion at the cursor
    vim.api.nvim_buf_set_text(
      bufnr,
      row - 1,
      col,
      row - 1,
      col,
      vim.split(suggestion, '\n')
    )
    cleanup()
  end

  -- Map Tab to accept the suggestion
  vim.keymap.set(
    'i',
    require('ai.config').config.mappings.accept_suggestion,
    accept_suggestion,
    { buffer = bufnr, noremap = true }
  )

  -- Set up autocmd to detect any keypress other than Tab
  autocmd_id = vim.api.nvim_create_autocmd(
    { 'CursorMoved', 'InsertLeave', 'InsertCharPre' },
    {
      callback = function()
        cleanup()
      end,
      buffer = bufnr,
    }
  )
end

return M
