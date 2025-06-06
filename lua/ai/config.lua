local Config = {}

---@class AiKeyMapCompletion
---@field accept_suggestion? string
---@field next_suggestion? string
---@field next_suggestion_with_prompt? string

---@class AiKeyMapChat
---@field submit? string
---@field new_chat? string
---@field goto_prev_chat? string
---@field goto_next_chat? string
---@field goto_chat_with_telescope? string
---@field delete_previous_msg? string
---@field copy_last_code_block? string

---@class AiKeyMapBuffers
---@field accept_suggestion? string
---@field accept_suggestion_and_exit? string
---@field cancel? string
---@field cancel_and_exit? string
---@field retry? string

---@class AiKeyMap
---@field completion? AiKeyMapCompletion
---@field chat? AiKeyMapChat
---@field buffers? AiKeyMapBuffers

---@alias ModelMapping table<'default' | 'mini' | 'nano' | 'thinking' | string, ModelString>

---@class AiModelOverrideOptions
---@field request? table
---@field headers? table

---@class AiConfig
---@field default_models? ModelMapping The default models to use in the format [adapter]:[model] e.g., openai:gpt-4
---@field selectable_models? ModelMapping[] Models that can be selected from via change_default_models
---@field model_overrides? table<string, AiModelOverrideOptions> Override request options for specific model lua patterns
---@field adapters? table<string, AdapterOptions>
---@field data_dir? string Folder in which chats and other data is stored
---@field mappings? AiKeyMap Key mappings
---@field rules_file? string | string[] Name of an optional file or folder(s) relative to the opened project to define custom rules for the LLM
---@field chat? AiChatConfig
---@field command? AiCommandConfig
---@field completion? AiCommandConfig

---@class AiChatConfig
---@field model? ModelString The model to use for the chat

---@class AiCommandConfig
---@field model? ModelString The model to use for the commands

---@class AiCompletionConfig
---@field model? ModelString The model to use for the completion

---@alias ModelString string

---@type AiConfig
Config.default_config = {
  -- The model that is used per default.
  -- The "mini" model is used for tasks which might use a lot of tokens or in which speed is especially important.
  -- You can customize which model should be used for which task in the "chat", "command" or "completion" settings.
  default_models = {
    default = 'anthropic:claude-3-7-sonnet-latest',
    mini = 'anthropic:claude-3-5-haiku-latest',
    nano = 'openai:gpt-4.1-nano',
    thinking = 'openai:o4-mini',
  },
  -- A list of model that can be easily switched between (using :AiChangeModels)
  selectable_models = {
    {
      default = 'anthropic:claude-3-7-sonnet-latest',
      mini = 'anthropic:claude-3-5-haiku-latest',
      nano = 'openai:gpt-4.1-nano',
      thinking = 'openai:o4-mini',
    },
    {
      default = 'openai:gpt-4.1',
      mini = 'openai:gpt-4.1-mini',
      nano = 'openai:gpt-4.1-nano',
      thinking = 'openai:o4-mini',
    },
  },
  -- Special request options for specific models
  model_overrides = {
    ['.*:o4%-mini'] = {
      request = {
        temperature = 1,
      },
    },
  },
  -- You can add custom adapters if you are missing a LLM provider.
  adapters = {
    anthropic = require('ai.adapters.anthropic'),
    azure = require('ai.adapters.azure'),
    ollama = require('ai.adapters.ollama'),
    openai = require('ai.adapters.openai'),
    openrouter = require('ai.adapters.openrouter'),
  },
  -- Customize which model is used for which task
  -- You can pass the model name directly (like "openai:gpt-4o") or refer to one of the default models.
  chat = {
    model = 'default',
  },
  completion = {
    model = 'default',
  },
  -- ai.nvim is looking for a rules file at the root of your project and will load it into each prompt.
  -- You can use it to define the code style or other information that could be improving the output of the tasks.
  -- You can now provide a list of files or folders. If a folder is given, all markdown files in it will be loaded and combined.
  rules_file = { '.ai/rules', '.ai-rules.md', '.roo/rules' },
  -- The data dir is used to save cached data (like the chat history)
  data_dir = vim.fn.stdpath('data') .. '/ai',
  -- Override the keymaps used by the plugin
  mappings = {
    completion = {
      accept_suggestion = '<Tab>',
      next_suggestion = '<C-n>',
      next_suggestion_with_prompt = '<S-C-n>',
    },
    chat = {
      submit = '<CR>',
      new_chat = '<LocalLeader>x',
      goto_prev_chat = '<LocalLeader>p',
      goto_next_chat = '<LocalLeader>n',
      goto_chat_with_telescope = '<LocalLeader>s',
      delete_previous_msg = '<LocalLeader>d',
      copy_last_code_block = '<LocalLeader>y',
    },
    buffers = {
      accept_suggestion = '<LocalLeader>a',
      accept_suggestion_and_exit = '<LocalLeader>A',
      cancel = '<LocalLeader>q',
      cancel_and_exit = '<LocalLeader>Q',
      retry = '<LocalLeader>r',
    },
  },
}

---@param config AiConfig
function Config.set(config)
  vim.g._ai_config = config
end

---@param config? AiConfig
function Config.merge(config)
  if config then
    -- Override the options that shouldn't be deep merged
    local result = vim.tbl_extend('force', Config.default_config, {
      default_models = config.default_models,
    })
    -- Merge the rest of the options
    result = vim.tbl_deep_extend('force', result, config)
    Config.set(result)
  end
end

---@return AiConfig
function Config.get()
  local config = vim.g._ai_config
  if not config then
    error('[ai.nvim] You need run setup before using the plugin')
  end
  return config
end

local function stringify_model_mapping(model_mapping)
  local string_value = model_mapping.default .. ' '
  for key, value in pairs(model_mapping) do
    if key ~= 'default' then
      string_value = string_value .. key .. '=' .. value .. ' '
    end
  end
  return vim.trim(string_value)
end

function Config.change_default_models()
  local config = Config.get()
  local currently_selected = stringify_model_mapping(config.default_models)
  local options = vim
    .iter(config.selectable_models)
    :map(function(option)
      local label = stringify_model_mapping(option)
      if label == currently_selected then
        label = '✅ ' .. label
      end
      return label
    end)
    :totable()

  vim.ui.select(options, {
    prompt = 'Select an AI model:',
  }, function(selection, idx)
    if selection then
      Config.set(
        vim.tbl_extend(
          'force',
          Config.get(),
          { default_models = config.selectable_models[idx] }
        )
      )
    end
    vim.notify(
      'Configured ' .. stringify_model_mapping(Config.get().default_models),
      vim.log.levels.INFO
    )
  end)
end

---@return ai.Adapter
function Config.get_chat_adapter()
  local config = Config.get()
  return Config.parse_model_string(config.chat.model or 'default')
end

---@return ai.Adapter
function Config.get_completion_adapter()
  local config = Config.get()
  return Config.parse_model_string(config.completion.model or 'default')
end

---@param model_string ModelString
---@return ai.Adapter
function Config.parse_model_string(model_string)
  local config = Config.get()
  local model_string_pattern = '([^:]+):?(.*)'

  local adapter_name, model_name = model_string:match(model_string_pattern)

  if adapter_name == 'default' then
    model_string = config.default_models[model_name or 'default']
      or config.default_models.default
    adapter_name, model_name = model_string:match(model_string_pattern)
  end

  -- Parse model string
  if not adapter_name then
    error(
      '[ai.nvim] Invalid model string format. Expected format: [adapter]:[model]'
    )
  end
  local adapter_config = config.adapters[adapter_name]
  if not adapter_config then
    error('[ai.nvim] Adapter not found: ' .. adapter_name)
  end
  local adapter = require('ai.adapters').Adapter:new(adapter_config)
  adapter.model = model_name or adapter.model
  return adapter
end

--- Utility to resolve rules_file(s) into a single string of rules
---@param rules_file string | string[]
---@return string|nil
function Config.resolve_rules(rules_file)
  if rules_file == nil or rules_file == '' then
    return nil
  end
  local uv = vim.uv or vim.loop
  local cwd = vim.fn.getcwd()
  local files_to_load = {}

  local function is_dir(path)
    local stat = uv.fs_stat(path)
    return stat and stat.type == 'directory'
  end

  local function is_file(path)
    local stat = uv.fs_stat(path)
    return stat and stat.type == 'file'
  end

  local function find_markdown_files_in_dir(dir)
    local files = {}
    local handle = uv.fs_scandir(dir)
    if not handle then
      return files
    end
    while true do
      local name, t = uv.fs_scandir_next(handle)
      if not name then
        break
      end
      if t == 'file' and name:match('%.md$') then
        table.insert(files, dir .. '/' .. name)
      end
    end
    return files
  end

  local candidates = type(rules_file) == 'table' and rules_file
    or { rules_file }

  for _, entry in ipairs(candidates) do
    local path = entry
    if type(path) == 'table' then
      goto continue
    end
    if type(path) ~= 'string' then
      goto continue
    end
    if not path:match('^/') then
      path = cwd .. '/' .. path
    end
    if is_file(path) then
      table.insert(files_to_load, path)
      break -- first matching file
    elseif is_dir(path) then
      local md_files = find_markdown_files_in_dir(path)
      vim.list_extend(files_to_load, md_files)
    end
    ::continue::
  end

  if #files_to_load == 0 then
    return nil
  end

  local rules = {}
  for _, file in ipairs(files_to_load) do
    local fd = uv.fs_open(file, 'r', 438)
    if fd then
      local stat = uv.fs_fstat(fd)
      local content = nil
      if stat and stat.size then
        content = uv.fs_read(fd, stat.size, 0)
      end
      uv.fs_close(fd)
      if content then
        table.insert(rules, content)
      end
    end
  end

  return table.concat(rules, '\n')
end

return Config
