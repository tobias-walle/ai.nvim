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

Goals of ai.nvim:

- Configurable LLM Provider (Use OpenAI, Anthropic, Azure, Ollama or whatever you prefer)
- Hackable (Easily add new capabilities, modify prompts, add custom context information)
- Integration into the existing development workflow (We don't want to replace, but support you)

(Planned) features:

- [ ] Ghost text autocompletion
- [ ] Edit highlighted sections or whole filse with custom prompts and commands
- [ ] Intelligent & customizable context
- [ ] Efficient modification of big or multiple files (For example by using a search & replace strategy, similar to [Aider](https://aider.chat))
- [ ] Automated refactorings (Allow the LLM to create files)

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
