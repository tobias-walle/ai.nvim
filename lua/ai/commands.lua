-- Define a module
local M = {}

local string_utils = require('ai.utils.string')
local ui = require('ai.ui')

local system_prompt = vim.trim([[
Follow the instructions and respond exclusively with the code snippet that should replace the code in the context!
Do not wrap the response in a code block!
]])

local prompt_template_file = vim.trim([[
<context>
File {{filename}}. CONTENT:
```{{language}}
{{content}}
```
</context>

<instructions>
{{intructions}}
</intructions>

Respond exclusively with the code replacing the CONTENT above! Do not wrap the response in a code block.
]])

local prompt_template_selection = vim.trim([[
<context>
File {{filename}}. CONTENT:
```{{language}}
{{content}}
```

The SELECTION is marked with {{selection_start_token}} and {{selection_end_token}}.
</context>

<instructions>
{{intructions}}
</intructions>

- Respond exclusively with the code replacing the SELECTION above!
- Do not wrap the response in a code block!
- Preserve leading whitespace and indent.
- Never output the selection tokens directly!
]])

local selection_start_token = '<|START|>'
local selection_end_token = '<|END|>'

local ns_id = vim.api.nvim_create_namespace('ai_command')

local function rewrite_with_instructions(opts, instructions)
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

  local is_selection = false
  local start_line, end_line
  if opts.range == 0 then
    -- Whole file
    start_line = 1
    end_line = vim.fn.line('$')
  else
    -- Visual selection
    is_selection = true
    start_line = opts.line1
    end_line = opts.line2
  end
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)

  local prompt
  if is_selection then
    table.insert(lines, end_line + 1, selection_end_token)
    table.insert(lines, start_line, selection_start_token)
    local content = table.concat(lines, '\n')
    prompt = string_utils.replace_placeholders(prompt_template_selection, {
      filename = filename,
      content = content,
      language = language,
      intructions = instructions,
      selection_start_token = selection_start_token,
      selection_end_token = selection_end_token,
    })
  else
    local content = table.concat(lines, '\n')
    prompt = string_utils.replace_placeholders(prompt_template_file, {
      filename = filename,
      content = content,
      language = language,
      intructions = instructions,
    })
  end

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

local function rewrite(opts)
  if opts.args and opts.args ~= '' then
    return rewrite_with_instructions(opts, opts.args)
  else
    ui.input({ prompt = 'Instructions' }, function(instructions)
      return rewrite_with_instructions(opts, instructions)
    end)
  end
end

function M.setup()
  vim.api.nvim_create_user_command(
    'AiRewrite',
    rewrite,
    { range = true, nargs = '*' }
  )
end

return M
