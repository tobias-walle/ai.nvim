# ai.nvim

> [!CAUTION]
> This plugin is still in the early stages and highly experimental.
> It is very likely that I will add breaking changes in the future.
> I don't recommend using it (yet).

Neovim plugin to integrate LLMs and other AI tools into Neovim to assist the development flow.

This plugin is inspired by the following tools:

- [continue.dev (VSCode)](https://www.continue.dev/)
- [Cursor Editor](https://www.cursor.com/)
- [Codeium](https://codeium.com/)
- [Aider](https://aider.chat)

There are similar plugins, which didn't match my workflow completely.

- [Parrot.nvim](https://github.com/frankroeder/parrot.nvim) - Awesome plugin and pretty similar as it also focuses on providing code editing tools for Neovim. The goal of ai.nvim is to bring the ideas to the next level.
- [llm.nvim](https://github.com/huggingface/llm.nvim) - LLM autocompletion similar to GitHub Copilot. But the architecture with a custom LSP seems overly complicated. I also had some issues last time I tried it.
- [cmp.ai](https://github.com/tzachar/cmp-ai) - Another solution for LLM autocompletion which is integrated into cmp. This worked pretty well, but again I missed some configuration options.
- [codecompanion.nvim](https://github.com/olimorris/codecompanion.nvim) - Mix of Copilot and Zen.ai. Provides chat interface and inline commands with integrations to the various contexts (like the buffer, other buffers, lsp).

Goals of ai.nvim:

- Scratching my own itch and find the ideal way of integrating AI into my workflow.
- Configurable LLM Provider (Use OpenAI, Anthropic, Azure, Ollama, or whatever you prefer).
- Hackable (Easily add new capabilities, modify prompts, add custom context information).
- Integration into the existing development workflow (It doesn't want to replace, but support you).

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

Please set up the following environment variables, depending on which feature you want to use:

- `OPENAI_API_KEY`: API key for OpenAI if you want to use their models.
- `ANTHROPIC_API_KEY`: API key for Anthropic if you want to use their models.
- `PERPLEXITY_API_KEY`: API key for Perplexity if you want to use the @web tool.

## Development

To run the tests:

1. Make sure you have [just](https://github.com/casey/just) installed
2. Download the required dependencies with `just prepare` (This includes [mini.test](https://github.com/echasnovski/mini.nvim/blob/main/TESTING.md))
3. Run the tests with `just test` OR run the tests of a single file with `just test_file FILE`
