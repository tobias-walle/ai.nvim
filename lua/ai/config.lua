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

---@class AiKeyMapDiff
---@field accept_suggestion? string
---@field reject_suggestion? string

---@class AiKeyMap
---@field completion? AiKeyMapCompletion
---@field chat? AiKeyMapChat
---@field diff? AiKeyMapDiff

---@alias ModelMapping table<'default' | 'mini' | string, ModelString>

---@class AiConfig
---@field default_models? ModelMapping The default models to use in the format [adapter]:[model] e.g., openai:gpt-4
---@field selectable_models? ModelMapping[] Models that can be selected from via change_default_models
---@field adapters? table<string, AdapterOptions>
---@field data_dir? string Folder in which chats and other data is stored
---@field mappings? AiKeyMap Key mappings
---@field context_file? string Name of an optional file relative to the opened projects to define custom context for the LLM.
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
  default_models = {
    default = 'openai:gpt-4o',
    mini = 'openai:gpt-4o-mini',
  },
  selectable_models = {
    { default = 'openai:gpt-4o', mini = 'openai:gpt-4o-mini' },
    { default = 'azure:gpt-4o', mini = 'azure:gpt-4o-mini' },
    {
      default = 'anthropic:claude-3-5-sonnet-20241022',
      mini = 'anthropic:claude-3-5-haiku-20241022',
    },
    { default = 'openrouter:deepseek/deepseek-chat' },
    { default = 'ollama:qwen2.5-coder:32b' },
  },
  adapters = {
    anthropic = require('ai.adapters.anthropic'),
    azure = require('ai.adapters.azure'),
    ollama = require('ai.adapters.ollama'),
    openai = require('ai.adapters.openai'),
    openrouter = require('ai.adapters.openrouter'),
  },
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
    diff = {
      accept_suggestion = '<LocalLeader>a',
      reject_suggestion = '<LocalLeader>r',
    },
  },
  data_dir = vim.fn.stdpath('data') .. '/ai',
  context_file = '.ai-context.md',
  chat = {
    model = 'default',
  },
  command = {
    model = 'default',
  },
  completion = {
    model = 'default:mini',
  },
}

---@param config AiConfig
function Config.set(config)
  vim.g._ai_config = config
end

---@param config? AiConfig
function Config.merge(config)
  config = vim.tbl_deep_extend('force', Config.default_config, config or {})
  Config.set(config)
end

---@return AiConfig
function Config.get()
  local config = vim.g._ai_config
  if not config then
    error('[ai.nvim] You need run setup before using the plugin')
  end
  return config
end

---@param model_string ModelString
---@return Adapter
function Config.parse_model_string(model_string)
  local config = Config.get()
  local model_string_pattern = '([^:]+):?(.*)'

  local adapter_name, model_name = model_string:match(model_string_pattern)

  if adapter_name == 'default' then
    local default_model_default = 'default'
    model_string = config.default_models[model_name or default_model_default]
      or config.default_models[default_model_default]
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

local function stringify_model_mapping(model_mapping)
  local string_value = model_mapping.default .. '\n'
  for key, value in pairs(model_mapping) do
    if key ~= 'default' then
      string_value = string_value .. key .. '=' .. value .. '\n'
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
        label = label .. ' (Selected)'
      end
      return label
    end)
    :totable()

  vim.ui.select(options, {
    prompt = 'Select an AI model:',
  }, function(_, idx)
    Config.set(
      vim.tbl_extend(
        'force',
        Config.get(),
        { default_models = config.selectable_models[idx] }
      )
    )
    vim.notify(
      'Configured default models:\n'
        .. stringify_model_mapping(Config.get().default_models),
      vim.log.levels.INFO
    )
  end)
end

---@return Adapter
function Config.get_chat_adapter()
  local config = Config.get()
  return Config.parse_model_string(config.chat.model or 'default')
end

---@return Adapter
function Config.get_command_adapter()
  local config = Config.get()
  return Config.parse_model_string(config.command.model or 'default')
end

---@return Adapter
function Config.get_completion_adapter()
  local config = Config.get()
  return Config.parse_model_string(config.completion.model or 'default')
end

return Config
