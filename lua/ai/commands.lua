-- Define a module
local M = {}

local string_utils = require('ai.utils.string')

local system_prompt = vim.trim([[
Follow the instructions and respond exclusively with the code snippet that should replace the code in the context!
Do not wrap the response in a code block!
]])

local prompt_template = vim.trim([[
<context>
You are in the file {{filename}}:

```{{language}}
{{content}}
```
</context>

<instructions>
{{intructions}}
</intructions>

Respond exclusively with the code snippet! Do not wrap the response in a code block.
]])

local ns_id = vim.api.nvim_create_namespace('ai_command')

local function rewrite(opts)
  local config = require('ai.config').config
  vim.notify(
    '[ai] Trigger command with '
      .. config.provider.name
      .. ':'
      .. config.provider.model,
    vim.log.levels.INFO
  )

  local bufnr = vim.api.nvim_get_current_buf()
  local language = vim.api.nvim_get_option_value('filetype', { buf = bufnr })
  local filename = vim.fn.expand('%')

  local start_line, end_line
  if opts.range == 0 then
    -- Whole file
    start_line = 1
    end_line = vim.fn.line('$')
  else
    -- Visual selection
    start_line = opts.line1
    end_line = opts.line2
  end
  local lines =
    vim.api.nvim_buf_get_lines(bufnr, start_line - 1, end_line, false)
  local content = table.concat(lines, '\n')

  local prompt = string_utils.replace_placeholders(prompt_template, {
    filename = filename,
    content = content,
    language = language,
    intructions = opts.args,
  })

  local cancelled = false
  local response = ''

  -- Clear area
  vim.api.nvim_buf_set_lines(bufnr, start_line - 1, end_line, true, { '' })

  -- Functions to accept or cancel the suggestion
  local job

  local function cleanup()
    cancelled = true
    job:kill('SIGTERM')
    vim.api.nvim_buf_clear_namespace(bufnr, ns_id, 0, -1)
    vim.keymap.del({ 'i', 'n' }, '<C-c>', { buffer = bufnr })
  end

  -- Cancel with C-c is pressed
  vim.keymap.set({ 'i', 'n' }, '<C-c>', function()
    cleanup()
    vim.cmd.undo()
  end, { buffer = bufnr, noremap = true })

  job = config.provider:stream({
    system_prompt = system_prompt,
    messages = {
      {
        role = 'user',
        content = prompt,
      },
    },
    temperature = 0.3,
    on_data = function(delta)
      if cancelled then
        return
      end
      response = response .. delta
      require('ai.render').render_ghost_text({
        text = response,
        buffer = bufnr,
        row = start_line - 1,
        col = 0,
        ns_id = ns_id,
      })
    end,
    on_exit = function()
      vim.cmd.undojoin()
      vim.api.nvim_buf_set_lines(
        bufnr,
        start_line - 1,
        start_line,
        false,
        vim.split(response, '\n')
      )
      cleanup()
    end,
  })
end

function M.setup()
  vim.api.nvim_create_user_command(
    'AiRewrite',
    rewrite,
    { range = true, nargs = '+' }
  )
end

return M
