-- Define a module
local M = {}

local string_utils = require('ai.utils.strings')
local ui = require('ai.ui')

local system_prompt_template_file = vim.trim([[
- Respond exclusively with the code replacing the CONTENT!
- Do not wrap the response in a code block.
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

- Respond exclusively with the code replacing the CONTENT above!
- Do not wrap the response in a code block.
]])

local system_prompt_template_selection = vim.trim([[
- The SELECTION is marked with {{selection_start_token}} and {{selection_end_token}}.
- Respond exclusively with the code replacing the SELECTION!
- Do not wrap the response in a code block.
- Preserve leading whitespace and indent.
- DO NOT include the selection tokens in your response.
]])

local prompt_template_selection = vim.trim([[
<context>
File {{filename}}. CONTENT:
```{{language}}
{{content}}
```
</context>

<instructions>
{{intructions}}
</intructions>
]])

local selection_start_token = '<|selection-start|>'
local selection_end_token = '<|selection-end|>'

local ns_id = vim.api.nvim_create_namespace('ai_command')

local function rewrite_with_instructions(opts, instructions)
  local adapter = require('ai.config').adapter
  vim.notify(
    '[ai] Trigger command with ' .. adapter.name .. ':' .. adapter.model,
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

  local prompt, system_prompt
  if is_selection then
    table.insert(lines, end_line + 1, selection_end_token)
    table.insert(lines, start_line, selection_start_token)
    local content = table.concat(lines, '\n')
    local placeholders = {
      filename = filename,
      content = content,
      language = language,
      intructions = instructions,
      selection_start_token = selection_start_token,
      selection_end_token = selection_end_token,
    }
    prompt =
      string_utils.replace_placeholders(prompt_template_selection, placeholders)
    system_prompt = string_utils.replace_placeholders(
      system_prompt_template_selection,
      placeholders
    )
  else
    local content = table.concat(lines, '\n')
    local placeholders = {
      filename = filename,
      content = content,
      language = language,
      intructions = instructions,
    }
    prompt =
      string_utils.replace_placeholders(prompt_template_file, placeholders)
    system_prompt = string_utils.replace_placeholders(
      system_prompt_template_file,
      placeholders
    )
  end

  local cancelled = false

  -- Clear area
  vim.api.nvim_buf_set_lines(bufnr, start_line - 1, end_line, true, { '' })

  -- Functions to accept or cancel the suggestion
  local job

  local function cleanup()
    cancelled = true
    job:stop()
    vim.api.nvim_buf_clear_namespace(bufnr, ns_id, 0, -1)
    vim.keymap.del({ 'i', 'n' }, '<C-c>', { buffer = bufnr })
  end

  -- Cancel with C-c is pressed
  vim.keymap.set({ 'i', 'n' }, '<C-c>', function()
    cleanup()
    vim.cmd.undo()
  end, { buffer = bufnr, noremap = true })

  job = adapter:chat_stream({
    system_prompt = system_prompt,
    messages = {
      {
        role = 'user',
        content = prompt,
      },
    },
    temperature = 0.3,
    on_update = function(update)
      if cancelled then
        return
      end
      require('ai.render').render_ghost_text({
        text = update.response,
        buffer = bufnr,
        row = start_line - 1,
        col = 0,
        ns_id = ns_id,
      })
    end,
    on_exit = function(data)
      vim.cmd.undojoin()
      vim.notify(
        '[ai] Input Tokens: '
          .. data.input_tokens
          .. '; Output Tokens: '
          .. data.output_tokens,
        vim.log.levels.INFO
      )
      vim.api.nvim_buf_set_lines(
        bufnr,
        start_line - 1,
        start_line,
        false,
        vim.split(data.response, '\n')
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
