# ai.nvim

> [!CAUTION]
> This plugin is still in the early stages and highly experimental.
> It is very likely that I will add breaking changes in the future.
> I do not recommend using it (yet).

Neovim plugin to integrate LLMs for powerful code autocompletion and command-driven code manipulation.

Features:

- [Autocomplete sections of your code](#autocompletion)
- [Execute AI-powered commands on your code](#commands)
- Configurable LLM Providers (Use OpenAI, Anthropic, Azure, Ollama, or whatever you prefer).

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
    { '<Leader>am', '<cmd>AiChangeModels<cr>', mode = 'n', desc = 'Change AI models' },
  }
}
```

Please set up the following environment variables, depending on which model or feature you want to use:

- `OPENAI_API_KEY`: API key for OpenAI if you want to use their models.
- `ANTHROPIC_API_KEY`: API key for Anthropic if you want to use their models.
- `OPENROUTER_API_KEY`: API key for OpenRouter if you want to use their models.
- `PERPLEXITY_API_KEY`: API key for Perplexity.
- `AZURE_API_BASE`: Base URL for the Azure API if you want to use Azure models. (Note: The model name will be used for the deployment)
- `AZURE_API_VERSION`: API version for the Azure API.
- `AZURE_API_KEY`: API key for the Azure API.

## Configuration

No configuration is required.
In this case the anthropic models will be used (Just remember to set the `ANTHROPIC_API_KEY` environment variable).

You can find the default configuration here [lua/ai/config.lua](./lua/ai/config.lua).

```lua
-- Note: This is the default config. It is not recommended to copy all these settings if you don't need to change them.
require('ai').setup({
  -- The model that is used per default.
  -- The "mini" model is used for tasks which might use a lot of tokens or in which speed is especially important.
  -- You can customize which model should be used for which task in the "command" or "completion" settings.
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
  command = {
    model = 'default',
  },
  completion = {
    model = 'default',
  },
  -- ai.nvim is looking for a rules file at the root of your project and will load it into each prompt.
  -- You can use it to define the code style or other information that could be improving the output of the tasks.
  rules_file = '.ai-rules.md',
  -- The data dir is used to save cached data
  data_dir = vim.fn.stdpath('data') .. '/ai',
  -- Override the keymaps used by the plugin
  mappings = {
    completion = {
      accept_suggestion = '<Tab>',
      next_suggestion = '<C-n>',
      next_suggestion_with_prompt = '<S-C-n>',
    },
    buffers = {
      accept_suggestion = '<LocalLeader>a',
      cancel = '<LocalLeader>q',
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

The plugin provides several commands (e.g., `:AiRewrite`, `:AiFix`) to interact with the AI. These commands can operate on a visual selection or the entire file. You can provide instructions directly as arguments to the command (e.g., `:AiRewrite <your prompt>`) or, if no arguments are given, an input prompt will appear.

The changes will be displayed in a diff.
You can accept them with `<LocalLeader>a` or reject them with `<LocalLeader>r`
(I personally have mapped localleader to `,` with `vim.g.maplocalleader = ','`).
You can change these mappings in the config.

Available commands:

- `:AiRewrite <prompt>` - Rewrites the selection or entire file based on the given prompt. If no prompt is provided, an input field will appear.
- `:AiRewriteSelection <prompt>` - Similar to `AiRewrite`, but strictly operates on the current visual selection.
- `:AiSpellCheck` - Fixes grammar and spelling errors in the selection using predefined instructions.
- `:AiTranslate` - Translates the selection to English using predefined instructions. For other languages, use `:AiRewrite` with a specific translation prompt (e.g., `:AiRewrite translate this to German`).
- `:AiFix` - Attempts to fix bugs in the selection or file using predefined instructions and adds comments explaining the reasoning.

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
3. Run the tests with `just test` OR run the tests of a single file with `just test_file FILE`.
