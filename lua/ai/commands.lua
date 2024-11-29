-- Define a module
local M = {}

local string_utils = require('ai.utils.strings')
local ui = require('ai.ui')

---@class CommandDefinition
---@field name string
---@field instructions? string

local prompt_template_file = vim.trim([[
## Full File
{{filename}}
```{{language}}
{{content}}
```

## Instructions
{{intructions}}

- Respond exclusively with the code replacing the file content in the code block!
- Always wrap the response in a code block.
- Preserve leading whitespace
]])

local prompt_template_selection = vim.trim([[
## Full File
{{filename}}
```{{language}}
{{content}}
```

## Selection
{{filename}}[{{start_line}}-{{end_line}}]
```{{language}}
{{selection_content}}
```

## Instructions
{{intructions}}

- Respond exclusively with the code replacing the selection!
- Always wrap the response in a code block.
- Preserve leading whitespace
]])

---@param definition CommandDefinition
---@param opts table
---@param instructions string
local function rewrite_with_instructions(definition, opts, instructions)
  local config = require('ai.config').get()
  local adapter = require('ai.config').get_command_adapter()
  vim.notify(
    '[ai] Trigger command with ' .. adapter.name .. ':' .. adapter.model,
    vim.log.levels.INFO
  )

  local bufnr = vim.api.nvim_get_current_buf()
  local language = vim.api.nvim_get_option_value('filetype', { buf = bufnr })
  local filename = vim.fn.expand('%')

  local start_line, end_line
  local last_line = vim.fn.line('$')
  if opts.range ~= 0 then
    start_line = opts.line1
    end_line = opts.line2
  else
    start_line = 1
    end_line = last_line
  end
  local is_whole_file = start_line == 1 and end_line == last_line
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local content = table.concat(lines, '\n')

  local prompt
  if is_whole_file then
    local placeholders = {
      filename = filename,
      content = content,
      language = language,
      intructions = instructions,
    }
    prompt =
      string_utils.replace_placeholders(prompt_template_file, placeholders)
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
  end

  local cancelled = false

  -- Prepare cancellation of ai call
  local job
  local function cleanup()
    cancelled = true
    job:stop()
  end

  -- Prepare diff view
  local diff_bufnr = require('ai.utils.diff_view').render_diff_view({
    bufnr = bufnr,
    callback = function()
      -- Cleanup after result was either rejected or accepted
      cleanup()
    end,
  })

  -- Clear content to be replaced
  vim.api.nvim_buf_set_lines(
    diff_bufnr,
    start_line - 1,
    end_line - 1,
    false,
    {}
  )

  local new_end_line = start_line
  job = adapter:chat_stream({
    system_prompt = require('ai.prompts').system_prompt,
    messages = {
      {
        role = 'user',
        content = prompt,
      },
    },
    temperature = 0.1,
    on_update = function(update)
      if cancelled then
        return
      end
      local code = vim.trim(
        require('ai.utils.treesitter').extract_code(update.response) or ''
      )
      local code_lines = vim.split(code, '\n')
      vim.api.nvim_buf_set_lines(
        diff_bufnr,
        start_line - 1,
        new_end_line,
        false,
        code_lines
      )
      new_end_line = start_line - 1 + #code_lines
    end,
    on_exit = function(data)
      vim.notify(
        '[ai] Input Tokens: '
          .. data.input_tokens
          .. '; Output Tokens: '
          .. data.output_tokens,
        vim.log.levels.INFO
      )
      cleanup()
    end,
  })
end

---@param definition CommandDefinition
local function create_command(definition)
  local function cmd_fn(opts)
    if definition.instructions and definition.instructions ~= '' then
      return rewrite_with_instructions(
        definition,
        opts,
        definition.instructions
      )
    elseif opts.args and opts.args ~= '' then
      return rewrite_with_instructions(definition, opts, opts.args)
    else
      ui.input({ prompt = 'Instructions' }, function(instructions)
        rewrite_with_instructions(definition, opts, instructions)
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
  create_command({
    name = 'SpellCheck',
    instructions = 'Fix all grammar and spelling errors without changing the meaning of the text.',
  })
  create_command({
    name = 'Translate',
    instructions = 'Translate all foreign words to english.',
  })
  create_command({
    name = 'Fix',
    instructions = 'Fix any bugs you find. Add a comment above the fixes, explaining your reasoning.',
  })
end

return M
