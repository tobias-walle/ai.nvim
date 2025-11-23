# ai.nvim Context

## Project Overview

`ai.nvim` is a Neovim plugin designed to integrate Large Language Models (LLMs) directly into the editor. It aims to provide features similar to AI-powered editors like Cursor or tools like Aider, but within the Neovim environment.

### Key Features
*   **Autocompletion:** Context-aware code completion triggered via keymaps.
*   **AI Commands:** specialized commands for refactoring, fixing bugs, spell checking, and translating text (e.g., `:AiRewrite`, `:AiFix`, `:AiSpellCheck`).
*   **Chat Interface:** A sidebar chat interface for conversational interactions with the AI.
*   **Agent Panel:** A more advanced interface for complex tasks involving multiple tools.
*   **Multi-Provider Support:** Built-in adapters for OpenAI, Anthropic, Azure, Ollama, and OpenRouter.
*   **Model Switching:** Easy switching between different models (default, mini, nano, thinking) for different tasks.

## Tech Stack

*   **Language:** Lua (Neovim plugin)
*   **External Dependencies:**
    *   `curl` (likely used for HTTP requests via `plenary` or built-in `vim.system` - *Note: The code uses `ai.utils.requests` which likely wraps `curl` or a lua http client*)
*   **Neovim Dependencies (Test/Dev):**
    *   `mini.nvim` (for testing)
    *   `dressing.nvim` (for UI elements)
    *   `nvim-cmp` (for autocompletion integration)

## Architecture

*   **Core:** `lua/ai/init.lua` handles setup and public API.
*   **Configuration:** `lua/ai/config.lua` manages user settings, default models, and keymaps.
*   **Adapters:** `lua/ai/adapters/` contains implementations for different AI providers. The base `Adapter` class is in `lua/ai/adapters.lua`.
*   **Commands:** `lua/ai/commands.lua` defines the user commands (`:Ai...`).
*   **Tools:** `lua/ai/tools/` likely contains the implementations of tools that the "Agent" can use (e.g., file reading/writing).
*   **UI:** `lua/ai/ui/` contains UI components like the agent panel.
*   **Utils:** `lua/ai/utils/` provides helper functions for requests, JSON handling, string manipulation, etc.

## Development

### Setup

1.  Ensure `just` is installed.
2.  Install dependencies:
    ```sh
    just prepare
    ```

### Testing

Tests are located in `tests/` (unit) and `tests_api/` (integration).

*   **Run all unit tests:**
    ```sh
    just test
    ```
*   **Run a specific test file:**
    ```sh
    just test-file tests/test_async.lua
    ```
*   **Run API integration tests:**
    ```sh
    just test-api
    ```
    Use `--debug` to enable verbose output:
    ```sh
    just test-api --debug
    ```
    Use `--only` to run only some tests (e.g. for debugging):
    ```sh
    just test-api --only azure,anthropic,openai_responses
    ```
    Then debugging, you MUST focus your tests and activate debug logging for more insists: `just test-api --only openai_responses --debug`
*   **Update screenshots (for tests involving UI):**
    ```sh
    just test-update
    ```

### Coding Conventions

*   **Style:** Follows standard Lua formatting. Configuration is likely in `.stylua.toml`.
*   **Structure:** Modular design. New features should be separated into appropriate modules under `lua/ai/`.
*   **Configuration:** User configuration is merged with defaults in `lua/ai/config.lua`.

## Key Files

*   `.agents/docs`: Contains documentation about external libraries used for agents
*   `lua/ai/init.lua`: Plugin entry point.
*   `lua/ai/config.lua`: Configuration schema and defaults.
*   `lua/ai/commands.lua`: Registry of `:Ai*` commands.
*   `lua/ai/adapters.lua`: Base class for AI model adapters.
*   `lua/ai/adapters/*.lua`: Specific provider implementations.
*   `README.md`: User-facing documentation.
*   `justfile`: Task runner configuration.
