# ai.nvim

> [!CAUTION]
> This plugin is still in the early stages and highly experimental.
> It is very likely that I will add breaking changes in the future.
> I do not recommend using it (yet).

Neovim plugin to integrate LLMs into Neovim to assist the development flow.

Features:

- [Autocomplete sections of your code](#autocompletion)
- [Rewrite your selections using AI](#rewrites)
- [Chat with your codebase and do changes utilizing agentic workflows](#chat)
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
    { '<Leader>aa', '<cmd>AiChat<cr>', mode = 'n', desc = 'Toggle AI chat' },
    { '<Leader>ar', '<cmd>AiRewrite<cr>', mode = 'v', desc = 'Rewrite selected text' },
    { '<Leader>am', '<cmd>AiChangeModels<cr>', mode = 'n', desc = 'Change AI models' },
  }
}
```

Please set up the following environment variables, depending on which model or feature you want to use:

- `OPENAI_API_KEY`: API key for OpenAI if you want to use their models.
- `ANTHROPIC_API_KEY`: API key for Anthropic if you want to use their models.
- `OPENROUTER_API_KEY`: API key for OpenRouter if you want to use their models.
- `PERPLEXITY_API_KEY`: API key for Perplexity if you want to use the @web tool.
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
  -- You can customize which model should be used for which task in the "chat", "command" or "completion" settings.
  default_models = {
    default = 'anthropic:claude-3-5-sonnet-20241022',
    mini = 'anthropic:claude-3-5-haiku-20241022',
  },
  -- A list of model that can be easily switched between (using :AiChangeModels)
  selectable_models = {
    {
      default = 'anthropic:claude-3-5-sonnet-20241022',
      mini = 'anthropic:claude-3-5-haiku-20241022',
    },
    { default = 'openai:gpt-4o', mini = 'openai:gpt-4o-mini' },
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
  command = {
    model = 'default',
  },
  completion = {
    model = 'default:mini',
  },
  -- ai.nvim is looking for a context file at the root of your project and will load it into each prompt.
  -- You can use it to define the code style or other information that could be improving the output of the tasks.
  context_file = '.ai-context.md',
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
    diff = {
      accept_suggestion = '<LocalLeader>a',
      reject_suggestion = '<LocalLeader>r',
    },
  },
})
```

## Features

### Autocompletion

You can press `<C-x>` (or `require('ai').trigger_completion()`) to trigger a completion at your cursor.
If you are happy with the suggestion, you can press `<Tab>` to accept it.

If not, you can get another suggestion with `<C-n>` or provide a custom prompt for your next suggestion with `<S-C-n>` (Shift + Control + n).

### Rewrites

Select a section of text and use `:AiRewrite` to rewrite it.
The LLM will be given your selection and the file as context.

Optionally, you can pass a direct prompt as the second argument `:AiRewrite <prompt>`.

The changes will be displayed in a diff.
You can accept them with `<LocalLeader>a` or reject them with `<LocalLeader>r`
(I personally have mapped localleader to `,` with `vim.g.maplocalleader = ','`).
You can change these mappings in the config.

Other commands:

- `:AiRewrite <prompt>` - Rewrites the selection based on the given prompt
- `:AiSpellCheck` - Fix grammar and spelling errors in the selection
- `:AiTranslate <lang>` - Translate the selection to another language
- `:AiFix` - Fix bugs in the selection

### Chat

You can open a chat on the side with `:AiChat`.

The chat supports a lot of special variables (starting with `#`) to give the LLM more context:

- `#buffer` - Gives the AI access to the file on the left to the chat window.
- `#selection` - Your last selection in the buffer.
- `#diagnostics` - All errors and warnings in the buffer.
- `#sh` - Runs a command and provides the output as context.
- `#file:"src/utils.ts"` - A file in your codebase.
- `#web:"https://google.de"` - The content of a website (Note: You need `pandoc` and `curl` for this feature).

Additionally, you can give access to tools, which the LLM can use to interact with the outside world. These start with `@`.

- `@editor` - Allows the LLM to edit any file in the project.
- `@grep` - With this tool, the codebase can be grepped by specific keywords.
- `@web` - Perform web searches using Perplexity (You need to configure `PERPLEXITY_API_KEY` for this).
- `@file` - Allow the LLM to read files.

These tools can trigger feedback loops (agentic workflows). For example, the LLM might decide to research an API before applying the changes.

You can always force the LLM to cancel by pressing `q`.

More tools to run commands or get diagnostics automatically will be added soon.

> [!CAUTION]
> The tools are still a subject of change.
> I need to gather more experience to really get it right, so expect breaking changes in the future.

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
