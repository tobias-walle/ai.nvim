-- Define a module
local M = {}

local string_utils = require('ai.utils.strings')

---@class CommandDefinition
---@field name string
---@field instructions? string
---@field only_replace_selection? boolean

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
    selection = string_utils.replace_placeholders(
      require('ai.prompts').commands_selection,
      placeholders
    )
  end
  placeholders.selection = selection

  if definition.only_replace_selection then
    local prompt = string_utils.replace_placeholders(
      require('ai.prompts').commands_edit_selection,
      placeholders
    )
    require('ai.command.apply_changes').apply_changes_with_replace_selection_strategy({
      bufnr = bufnr,
      prompt = prompt,
      start_line = start_line,
      end_line = end_line,
    })
  else
    local prompt = string_utils.replace_placeholders(
      require('ai.prompts').commands_edit_file,
      placeholders
    )
    require('ai.command.apply_changes').apply_changes_with_fast_edit_strategy({
      bufnr = bufnr,
      prompt = prompt,
      start_line = start_line,
      end_line = end_line,
    })
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
