# ai.nvim

> This plugin is still in the early stages.
> It is very likely that I will add breaking changes in the future.
> Please use with care.

Neovim plugin to integrate LLMs and other AI tools into Neovim to assist the development flow.

This plugin is inspired by the following tools:

- [continue.dev VSCode Plugin](https://www.continue.dev/)
- [Cursor Editor](https://www.cursor.com/)
- [Codeium](https://codeium.com/)
- [Aider](https://aider.chat)

There are similar plugins, which didn't match my workflow completely.

- [Parrot.nvim](https://github.com/frankroeder/parrot.nvim) - Awesome plugin and pretty similar as it also focuses on providing code editing tools for Neovim. The goal of ai.nvim is to bring the ideas to the next level.
- [llm.nvim](https://github.com/huggingface/llm.nvim) - LLM autocompletion similar to GitHub Copilot. But the architecture with a custom LSP seems overly complicated. I also had some issues last time I tried it.
- [cmp.ai](https://github.com/tzachar/cmp-ai) - Another solution for LLM autocompletion which is integrated into cmp. This worked pretty well, but again I missed some configuration options.
- [codecompanion.nvim](https://github.com/olimorris/codecompanion.nvim) - Mix of Copilot and Zen.ai. Provides chat interface and inline commands with integrations to the various contexts (like the buffer, other buffers, lsp).
  It looks awesome and I am not sure if my plugin will reach the same amount of polish.

Goals of ai.nvim:

- Configurable LLM Provider (Use OpenAI, Anthropic, Azure, Ollama or whatever you prefer)
- Hackable (Easily add new capabilities, modify prompts, add custom context information)
- Integration into the existing development workflow (We don't want to replace, but support you)

(Planned) features:

- [x] Ghost text autocompletion
- [ ] Edit highlighted sections or whole files with custom prompts and commands
- [x] Intelligent & customizable context
- [x] Efficient modification of big or multiple files (For example by using a search & replace strategy, similar to [Aider](https://aider.chat))
- [x] Automated refactorings (Allow the LLM to create files)

## Installation

Using [lazy.nvim](https://lazy.folke.io/):

```lua
{
  'tobias-walle/ai.nvim',
  event = 'BufEnter',
  config = function()
    require('ai').setup({
      -- Your options here
    })
  end,
}
```

Please setup the following environment variables, depending on which feature you want to use:

- `OPENAI_API_KEY`: Api key for OpenAI if you want to use their models
- `ANTHROPIC_API_KEY`: Api key for Anthropic if you want to use their models
- `PERPLEXITY_API_KEY`: Api key for Perplexity if you want to the @web tool

## Development

To run the tests:

1. Download the required dependencies with `just prepare` (This includes [mini.test](https://github.com/echasnovski/mini.nvim/blob/main/TESTING.md))
2. Run the tests with `just test` OR run the tests of a single file with `just test_file FILE`
