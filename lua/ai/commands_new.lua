-- Define a module
local M = {}

local string_utils = require('ai.utils.strings')
local ui = require('ai.ui')

---@class CommandDefinition
---@field name string

local system_prompt_template_file = vim.trim([[]])

local prompt_template_file = vim.trim([[
<context>
{{filename}}
```{{language}}
{{content}}
```
</context>

<instructions>
{{intructions}}
</intructions>

- Respond exclusively with the code replacing the file content in the code block!
- Do not wrap the response in a code block.
]])

local system_prompt_template_selection = vim.trim([[]])

local prompt_template_selection = vim.trim([[
<context>
{{filename}}
```{{language}}
{{content}}
```
</context>

<selection>
{{filename}}[{{start_line}}-{{end_line}}]
```{{language}}
{{selection_content}}
```
</selection>

<instructions>
{{intructions}}
</intructions>

- Respond exclusively with the code replacing the <selection>!
- Do not wrap the response in a code block or with a <selection> tag.
- Preserve leading whitespace and indent.
]])

local ns_id = vim.api.nvim_create_namespace('ai_command')

---@param definition CommandDefinition
---@param opts table
---@param instructions string
---@return string
local function rewrite_with_instructions(definition, opts, instructions)
  local adapter = require('ai.config').adapter
  vim.notify(
    '[ai] Trigger command with ' .. adapter.name .. ':' .. adapter.model,
    vim.log.levels.INFO
  )

  local bufnr = vim.api.nvim_get_current_buf()
  local language = vim.api.nvim_get_option_value('filetype', { buf = bufnr })
  local filename = vim.fn.expand('%')

  local first_line = 1
  local last_line = vim.fn.line('$')
  local start_line = opts.line1 or first_line
  local end_line = opts.line2 or last_line
  local is_whole_file = start_line == start_line and end_line == last_line
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local content = table.concat(lines, '\n')

  local prompt, system_prompt
  if is_whole_file then
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
  else
    local selection_content =
      table.concat(vim.list_slice(lines, start_line, end_line), '\n')
    local placeholders = {
      filename = filename,
      content = content,
      selection_content = selection_content,
      language = language,
      intructions = instructions,
      start_line = start_line,
      end_line = end_line,
    }
    prompt =
      string_utils.replace_placeholders(prompt_template_selection, placeholders)
    system_prompt = string_utils.replace_placeholders(
      system_prompt_template_selection,
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

---@param definition CommandDefinition
local function create_command(definition)
  local function cmd_fn(opts)
    if opts.args and opts.args ~= '' then
      return rewrite_with_instructions(definition, opts, opts.args)
    else
      ui.input({ prompt = 'Instructions' }, function(instructions)
        return rewrite_with_instructions(definition, opts, instructions)
      end)
    end
  end

  vim.api.nvim_create_user_command(
    'Ai' .. definition.name,
    cmd_fn,
    { range = true, nargs = '*' }
  )
end

function M.setup()
  create_command({
    name = 'Rewrite',
  })
end

return M
