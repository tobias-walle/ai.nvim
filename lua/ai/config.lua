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

---@class AiConfig
---@field default_model? ModelString The default model to use in the format [adapter]:[model] e.g., openai:gpt-4
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
  default_model = 'openai:gpt-4o',
  adapters = {
    anthropic = require('ai.adapters.anthropic'),
    openai = require('ai.adapters.openai'),
    azure = require('ai.adapters.azure'),
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
    -- model = "openai:gpt-4o",
  },
  command = {
    -- model = "openai:gpt-4o",
  },
  completion = {
    -- model = "openai:gpt-4o-mini",
  },
}

---@param config? AiConfig
function Config.set(config)
  config = vim.tbl_deep_extend('force', Config.default_config, config or {})

  vim.g._ai_config = config
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

  -- Parse model string
  local adapter_name, model_name = model_string:match('([^:]+):?(.*)')
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

---@return Adapter
function Config.get_chat_adapter()
  local config = Config.get()
  return Config.parse_model_string(
    config.chat and config.chat.model or config.default_model
  )
end

---@return Adapter
function Config.get_command_adapter()
  local config = Config.get()
  return Config.parse_model_string(
    config.command and config.command.model or config.default_model
  )
end

---@return Adapter
function Config.get_completion_adapter()
  local config = Config.get()
  return Config.parse_model_string(
    config.completion and config.completion.model or config.default_model
  )
end

return Config
