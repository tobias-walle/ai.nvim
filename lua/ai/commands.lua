-- Define a module
local M = {}

local string_utils = require('ai.utils.strings')
local open_prompt_input = require('ai.utils.prompt_input').open_prompt_input
local get_diagnostics = require('ai.utils.diagnostics').get_diagnostics
local FilesContext = require('ai.utils.files_context')
local Messages = require('ai.utils.messages')
local Prompts = require('ai.prompts')
local AgentPanel = require('ai.ui.agent_panel')

---@class CommandDefinition
---@field name string
---@field input_prompt? string
---@field instructions? ai.AdapterMessageContent
---@field model? string
---@field only_replace_selection? boolean

---@param definition CommandDefinition
---@param opts table
---@param task ai.AdapterMessageContent
local function execute_ai_command(definition, opts, task)
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

  local diagnostics = get_diagnostics(bufnr)
  local diagnostics_selection = get_diagnostics(bufnr, start_line, end_line)

  local selection_content =
    table.concat(vim.list_slice(lines, start_line, end_line), '\n')

  ---@type AdapterMessageContentItem[]
  local prompt = {}

  vim.list_extend(prompt, FilesContext.get_images())
  vim.list_extend(prompt, Messages.extract_images(task))

  ---@type Placeholders
  local placeholders = {
    custom_rules = require('ai.utils.rules').load_custom_rules() or '',
    filename = filename,
    content = content,
    selection_content = selection_content,
    language = language,
    task = Messages.extract_text(task),
    start_line = start_line,
    end_line = end_line,
    diagnostics = definition.only_replace_selection and diagnostics_selection
      or diagnostics,
    instructions = definition.only_replace_selection
        and Prompts.selection_only_instructions
      or Prompts.default_instructions,
    files_context = FilesContext.get_prompt(),
  }

  local selection = ''
  if not is_whole_file then
    selection = string_utils.replace_placeholders(
      Prompts.commands_selection,
      placeholders
    )
  end
  placeholders.selection = selection

  local adapter =
    require('ai.config').parse_model_string(definition.model or 'default')
  ---@type AdapterMessageContentItem
  local text_content = {
    type = 'text',
    text = string_utils.replace_placeholders(
      Prompts.prompt_agent,
      placeholders
    ),
  }
  table.insert(prompt, text_content)
  local agent = AgentPanel.new({
    adapter = adapter,
    focused_bufnr = bufnr,
    disable_tools = {
      selection_write = not definition.only_replace_selection,
      file_write = definition.only_replace_selection,
      file_update = definition.only_replace_selection,
    },
  })
  agent:send(prompt)
end

---@param definition CommandDefinition
local function create_command(definition)
  local function cmd_fn(opts)
    if definition.instructions and definition.instructions ~= '' then
      return execute_ai_command(definition, opts, definition.instructions)
    elseif opts.args and opts.args ~= '' then
      return execute_ai_command(definition, opts, opts.args)
    else
      open_prompt_input({
        prompt = definition.input_prompt or definition.name,
        enable_thinking_option = true,
        enable_files_context_option = true,
      }, function(instructions, flags)
        local updated_definition = definition
        if flags.model then
          ---@diagnostic disable-next-line: missing-fields
          updated_definition = vim.tbl_extend('force', {}, definition, {
            model = flags.model == 'thinking' and 'default:thinking'
              or 'default',
          })
        end
        execute_ai_command(updated_definition, opts, instructions)
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
    input_prompt = 'AI Rewrite',
  })
  create_command({
    name = 'Agent',
    input_prompt = 'AI Agent Mode',
  })
  create_command({
    name = 'RewriteSelection',
    input_prompt = 'AI Rewrite Selection',
    only_replace_selection = true,
  })
  create_command({
    name = 'SpellCheck',
    input_prompt = 'AI Spell Check',
    instructions = 'Fix all grammar and spelling errors without changing the meaning of the text.',
    only_replace_selection = true,
  })
  create_command({
    name = 'Translate',
    input_prompt = 'AI Translate',
    instructions = 'Translate all foreign words to english.',
    only_replace_selection = true,
  })
  create_command({
    name = 'Fix',
    input_prompt = 'AI Fix',
    instructions = 'Fix any bugs you find. Add a comment above the fixes, explaining your reasoning.',
    only_replace_selection = true,
  })
end

return M
