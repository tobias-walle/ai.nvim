# ai.nvim

> [!CAUTION]
> This plugin is still in the early stages and highly experimental.
> It is very likely that I will add breaking changes in the future.
> I do not recommend using it (yet).

Neovim plugin to integrate LLMs for powerful code autocompletion, command-driven code manipulation, and an agent-style chat panel with tools.

Features:

- [Autocomplete sections of your code](#autocompletion)
- [Execute AI-powered commands on your code](#commands)
- [Agent Mode chat panel](#agent-mode) with tool use (file read/write, search, task completion, ask)
- Configurable LLM Providers (OpenAI, Anthropic, Azure, Ollama, OpenRouter)

This plugin is greatly inspired by the following tools:

- [Cursor Editor](https://www.cursor.com/)
- [Aider](https://aider.chat)
- [continue.dev (VSCode)](https://www.continue.dev/)

## Installation

Using [lazy.nvim](https://lazy.folke.io/):

```lua
{
  'tobias-walle/ai.nvim',
  event = 'BufEnter',
  config = function()
    require('ai').setup({})
  end,
  keys = {
    { '<C-x>', function() require('ai').trigger_completion() end, mode = 'i', desc = 'Trigger AI Completion' },
    { '<Leader>ar', '<cmd>AiRewrite<cr>', mode = 'v', desc = 'Rewrite selected text' },
    { '<Leader>aa', '<cmd>AiAgent<cr>', mode = 'n', desc = 'Open AI Agent panel' },
    { '<Leader>am', '<cmd>AiChangeModels<cr>', mode = 'n', desc = 'Change AI models' },
  }
}
```

Please set up the following environment variables, depending on which provider you want to use:

- `OPENAI_API_KEY`: API key for OpenAI.
- `ANTHROPIC_API_KEY`: API key for Anthropic.
- `OPENROUTER_API_KEY`: API key for OpenRouter.
- `AZURE_API_BASE`: Base URL for the Azure API (the model name corresponds to your deployment name).
- `AZURE_API_KEY`: API key for Azure. The adapter uses `api-version=preview`.

## Configuration

No configuration is required.
In this case the anthropic models will be used (Just remember to set the `ANTHROPIC_API_KEY` environment variable).

You can find the default configuration here [lua/ai/config.lua](./lua/ai/config.lua).

```lua
-- Note: This is the default config. It is not recommended to copy all these settings if you don't need to change them.
require('ai').setup({
  -- The model that is used per default.
  -- The "mini" model is used for tasks which might use a lot of tokens or where speed is important.
  -- You can customize which model should be used for each task in the "chat", "command" or "completion" settings.
  default_models = {
    default = 'anthropic:claude-3-7-sonnet-latest',
    mini = 'anthropic:claude-3-5-haiku-latest',
    nano = 'openai:gpt-4.1-nano',
    thinking = 'openai:o4-mini',
  },
  -- A list of models that can be easily switched between (using :AiChangeModels)
  selectable_models = {
    {
      default = 'anthropic:claude-3-7-sonnet-latest',
      mini = 'anthropic:claude-3-5-haiku-latest',
      nano = 'openai:gpt-4.1-nano',
      thinking = 'openai:o4-mini',
    },
    {
      default = 'openai:gpt-5',
      mini = 'openai:gpt-4.1-mini',
      nano = 'openai:gpt-4.1-nano',
      thinking = 'openai:o4-mini',
    },
  },
  -- Special request options for specific models
  model_overrides = {
    ['.*:o4%-mini'] = {
      request = { temperature = 1 },
    },
    ['.*:gpt%-5$'] = {
      request = { temperature = 1, reasoning = { effort = 'minimal' } },
    },
    ['.*:gpt%-5%.1.*'] = {
      request = { temperature = 1, reasoning = { effort = 'none' } },
    },
  },
  -- LLM provider adapters
  adapters = {
    anthropic = require('ai.adapters.anthropic'),
    azure = require('ai.adapters.azure'),
    ollama = require('ai.adapters.ollama'),
    openai = require('ai.adapters.openai'),
    openrouter = require('ai.adapters.openrouter'),
  },
  -- Customize which model is used for which task
  chat = { model = 'default' },
  completion = { model = 'default' },
  -- ai.nvim can load project rules and include them in prompts.
  -- You can provide a file or folder(s). If a folder is given, all markdown files in it will be loaded and combined.
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
})
```

## Features

### Autocompletion

You can press `<C-x>` (or `require('ai').trigger_completion()`) to trigger a completion at your cursor.
If you are happy with the suggestion, you can press `<Tab>` to accept it.

If not, you can get another suggestion with `<C-n>` or provide a custom prompt for your next suggestion with `<S-C-n>` (Shift + Control + n).

### Commands

The plugin provides several commands (e.g., `:AiRewrite`, `:AiFix`, `:AiAgent`) to interact with the AI. These commands can operate on a visual selection or the entire file. You can provide instructions directly as arguments to the command (e.g., `:AiRewrite <your prompt>`) or, if no arguments are given, an input prompt will appear.

The changes will be displayed in a diff.
You can accept them with `<LocalLeader>a` or `<LocalLeader>A` and reject them with `<LocalLeader>q` or `<LocalLeader>Q`.
(I personally have mapped localleader to `,` with `vim.g.maplocalleader = ','`).
You can change these mappings in the config.

Available commands:

- `:AiRewrite <prompt>` - Rewrites the selection or entire file based on the given prompt. If no prompt is provided, an input field will appear.
- `:AiRewriteSelection <prompt>` - Similar to `AiRewrite`, but strictly operates on the current visual selection.
- `:AiSpellCheck` - Fixes grammar and spelling errors in the selection using predefined instructions.
- `:AiTranslate` - Translates the selection to English using predefined instructions. For other languages, use `:AiRewrite` with a specific translation prompt (e.g., `:AiRewrite translate this to German`).
- `:AiFix` - Attempts to fix bugs in the selection or file using predefined instructions and adds comments explaining the reasoning.
- `:AiAgent` - Opens the agent panel for a guided chat with tool usage (file read/write/update, search, completion, ask). The agent can apply changes via diff views.
- `:AiChangeModels` - Switches the current default model set (default/mini/nano/thinking) via a selection UI.

### Agent Mode

Open the agent panel with `:AiAgent` (see installation example for a suggested keymap).
- Runs a chat with your configured model and uses tools to read/search files and apply changes.
- Shows token usage and streams responses.
- When the agent proposes changes, diff views open; accept with `<LocalLeader>a` or `<LocalLeader>A`, cancel with `<LocalLeader>q` or `<LocalLeader>Q`.

## Similar Plugins

There are several other plugins with similar goals.

- [Parrot.nvim](https://github.com/frankroeder/parrot.nvim)
- [llm.nvim](https://github.com/huggingface/llm.nvim)
- [cmp.ai](https://github.com/tzachar/cmp-ai)
- [codecompanion.nvim](https://github.com/olimorris/codecompanion.nvim)
- [avante.nvim](https://github.com/yetone/avante.nvim)

## Development

To run the tests:

1. Make sure you have [just](https://github.com/casey/just) installed.
2. Download the required dependencies with `just prepare` (This includes [mini.test](https://github.com/echasnovski/mini.nvim/blob/main/TESTING.md)).
3. Run all unit tests with `just test`.
4. Run a single test file with `just test-file FILE`.
5. Update screenshots for UI tests with `just test-update`.
6. Run API integration tests with `just test-api` (use `--debug` for verbose logging).
