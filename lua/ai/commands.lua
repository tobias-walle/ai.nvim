-- Define a module
local M = {}

local string_utils = require('ai.utils.strings')

---@class CommandDefinition
---@field name string
---@field instructions? string
---@field only_replace_selection? boolean

local prompt_template_selection = vim.trim([[
<selection>
{{filename}}[{{start_line}}-{{end_line}}]
```{{language}}
{{selection_content}}
```
</selection>
]])

local prompt_template_file = vim.trim([[
<file>
```{{language}} {{filename}}
{{content}}
```
</file>
{{selection}}
<instructions>
{{intructions}}
</instructions>

- Follow the <instructions> and respond with the code replacing the file content in the <file> code block!
- Always wrap the response in a code block with the filename in the header.
- Preserve leading whitespace
- Only reply with the changed code. Use placeholder comments like `…` to hide unchanged code, but keep important sourrounding context like function signatures.
- Keep your response as short as possible and avoid repeating code that doesn't need to change!
- Avoid comments explaining your changes

Example:
```typescript src/updatedFile.ts
// …
export interface EventsApi {
  // …
  updateEvents(events: EventInput[]): Promise<void>;
}
// …
function createEventsApi(client: Client): EventsApi {
  // …
  return {
    // …
    updateEvents: (events) => client.patch('events', { json: events }).json(),
  };
}
// …
```typescript

]])

local prompt_template_edit_selection_only = vim.trim([[
<file>
```{{language}} {{filename}}
{{content}}
```
</file>
{{selection}}
<instructions>
{{intructions}}
</instructions>

- Follow the <instructions> and respond with the code replacing ONLY the <selection> content in the code block!
- Preserve leading whitespace
- Avoid comments explaining your changes
]])

local function apply_changes_with_fast_edit_strategy(options)
  local adapter = require('ai.config').get_command_adapter()

  local bufnr = options.bufnr
  local prompt = options.prompt

  local cancelled = false

  -- Prepare cancellation of ai call
  local job
  local function cleanup()
    cancelled = true
    job:stop()
  end

  -- Prepare popup
  local preview_popup = require('ai.utils.popup').open_response_preview({
    bufnr = bufnr,
    on_cancel = cleanup,
    on_confirm = function(response_lines)
      local response = table.concat(response_lines, '\n')
      local code = require('ai.utils.treesitter').extract_code(response) or ''
      require('ai.agents.editor').apply_edits({
        bufnr = bufnr,
        patch = code,
      })
    end,
  })

  -- Clear content to be replaced
  vim.api.nvim_buf_set_lines(preview_popup.bufnr, 0, -1, false, {})

  local function render_preview(response)
    local code_lines = vim.split(response, '\n')
    vim.api.nvim_buf_set_lines(preview_popup.bufnr, 0, -1, false, code_lines)
  end
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
      render_preview(update.response .. ' ⏳')
    end,
    on_exit = function(data)
      render_preview(data.response)
      cleanup()
    end,
  })
end

local function apply_changes_with_replace_selection_strategy(options)
  local adapter = require('ai.config').get_command_adapter()

  local bufnr = options.bufnr
  local prompt = options.prompt
  local start_line = options.start_line
  local end_line = options.end_line

  local cancelled = false

  -- Prepare cancellation of ai call
  local job
  local function cleanup()
    cancelled = true
    job:stop()
  end

  -- Diffview
  local diff_bufnr = require('ai.utils.diff_view').render_diff_view({
    bufnr = bufnr,
    callback = function()
      -- Cleanup after result was either rejected or accepted
      cleanup()
    end,
  })

  local function render_response(response)
    local code = require('ai.utils.treesitter').extract_code(response) or ''
    -- Replace trailing newline
    code = code:gsub('\n$', '')
    local code_lines = vim.split(code, '\n')
    vim.api.nvim_buf_set_lines(
      diff_bufnr,
      start_line - 1,
      end_line,
      false,
      code_lines
    )
    -- Update end_line to reflect changes
    end_line = start_line + #code_lines - 1
  end

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
      render_response(update.response)
    end,
    on_exit = function(data)
      render_response(data.response)
      cleanup()
    end,
  })
end

---@param definition CommandDefinition
---@param opts table
---@param instructions string
local function execute_ai_command(definition, opts, instructions)
  local bufnr = vim.api.nvim_get_current_buf()
  local language = vim.api.nvim_get_option_value('filetype', { buf = bufnr })
  local filename = vim.fn.expand('%:.')

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

  local selection = ''
  if not is_whole_file then
    selection =
      string_utils.replace_placeholders(prompt_template_selection, placeholders)
  end
  placeholders.selection = selection

  local prompt = ''
  if definition.only_replace_selection then
    prompt = string_utils.replace_placeholders(
      prompt_template_edit_selection_only,
      placeholders
    )
    apply_changes_with_replace_selection_strategy({
      bufnr = bufnr,
      prompt = prompt,
      start_line = start_line,
      end_line = end_line,
    })
  else
    prompt =
      string_utils.replace_placeholders(prompt_template_file, placeholders)
    apply_changes_with_fast_edit_strategy({ bufnr = bufnr, prompt = prompt })
  end
end

---@param definition CommandDefinition
local function create_command(definition)
  local function cmd_fn(opts)
    if definition.instructions and definition.instructions ~= '' then
      return execute_ai_command(definition, opts, definition.instructions)
    elseif opts.args and opts.args ~= '' then
      return execute_ai_command(definition, opts, opts.args)
    else
      vim.ui.input({ prompt = 'Instructions' }, function(instructions)
        execute_ai_command(definition, opts, instructions)
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
    name = 'RewriteSelection',
    only_replace_selection = true,
  })
  create_command({
    name = 'SpellCheck',
    instructions = 'Fix all grammar and spelling errors without changing the meaning of the text.',
    only_replace_selection = true,
  })
  create_command({
    name = 'Translate',
    instructions = 'Translate all foreign words to english.',
    only_replace_selection = true,
  })
  create_command({
    name = 'Fix',
    instructions = 'Fix any bugs you find. Add a comment above the fixes, explaining your reasoning.',
    only_replace_selection = true,
  })
end

return M
