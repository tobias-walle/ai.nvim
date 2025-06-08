local M = {}

local build_prompt = require('ai.utils.prompt_builder').build_prompt
local replace_placeholders = require('ai.utils.strings').replace_placeholders

M.placeholder_unchanged = '... existing code ...'

M._system_prompt_general_rules = vim.trim([[
# CODING AND FORMATTING

- Always use best practices when coding.
- Respect and use existing conventions that are already present in the code base.
- If a library that is already used, could solve the specified problem, prefer it's use over your own implementation.
- Try to stay DRY, but duplicate code if it makes sense.
- Create a new line after each sentence.
- NEVER add comments describing your current edit. Only use comments if they shouldn't be removed afterwards.
- NEVER remove existing comments if not specifically instructed,
]])

M.system_prompt = build_prompt({
  [[
Act as an expert software developer. You are very articulate and follow instructions very closely.
  ]],
  '',
  M._system_prompt_general_rules,
})

M.system_prompt_agent = build_prompt({
  [[
You are an agent and expert software developer. You are very articulate and follow instructions very closely.
As an agent, you act autonomously. You fulfill the given task by formulating and paln and using the tools provided to you.

Use the 'summarize_chat' tool for long running to keep your context small and focused.
For example if your task requires a lot of different step, you should use it after each step.
  ]],
  '',
  M._system_prompt_general_rules,
})

M.commands_selection = vim.trim([[
<selection>
{{filename}}[{{start_line}}-{{end_line}}]
```{{language}}
{{selection_content}}
```
</selection>
]])

M.files_context_single_file = vim.trim([[
```{{language}} {{filename}}
{{content}}
```
]])

M.files_context = vim.trim([[
<files_context>
The following files were selected by me and might be relevant for the tasks.
{{files}}
</files_context>
]])

M.prompt_agent = vim.trim([[
<project-rules>
{{custom_rules}}
</project-rules>

<relevant-files>
{{files_context}}
</relevant-files>

<diagnostics file="{{filename}}">
{{diagnostics}}
</diagnostics>

<current-file file="{{filename}}">
```{{language}}
{{content}}
```
</current-file>

{{selection}}

<instructions>
{{instructions}}
</instructions>

<task>
{{task}}
</task>
]])

M.default_instructions = vim.trim([[
- Fullfill the task given by the user.
- Formulate a plan first, explain your intended changes and then use the right tools for the job.
- If a `selection` was provided, focus your changes on that. Think why the user decided to include it for the task.
- Only fix the `diagnostics` if explicitly instructed.
- Always use the `ask` tool if you need more information or feedback from the user. Provide suggestions as `choices`.
]])

M.selection_only_instructions = vim.trim([[
- Fullfill the task given by the user by replacing the selection.
- Only fix the `diagnostics` if explicitly instructed.
- Use the `selection_write` tool directly for simple tasks. Reason about your changes first for more complex requests.
]])

M.editor_user_prompt = build_prompt({
  [[
<original>
```{{language}}
{{original_content}}
```
</original>

<patch>
```{{language}}
{{patch_content}}
```
</patch>
  ]],
}, { placeholder_unchanged = M.placeholder_unchanged })

M.editor_example_user = replace_placeholders(M.editor_user_prompt, {
  language = 'typescript',
  original_content = vim.trim([[
export type EnterEventHandler = (event: KeyboardEvent) => void;

export function whenEnter(
  event: KeyboardEvent,
  handler: EnterEventHandler,
): EnterEventHandler {
  return (event) => {
    if (event.key === 'Enter') {
      handler(event);
    }
  };
}
  ]]),
  patch_content = vim.trim([[
// {{placeholder_unchanged}}
export type OnEnter = (event: KeyboardEvent) => void;

export function whenEnter(
  event: KeyboardEvent,
  onEnter: EnterEventHandler,
): OnEnter {
  // {{placeholder_unchanged}}
      onEnter(event);
  // {{placeholder_unchanged}}
}

// {{placeholder_unchanged}}
  ]]),
  placeholder_unchanged = M.placeholder_unchanged,
})

M.editor_example_assistant_response = build_prompt({
  [[
```typescript
import { KeyboardEvent } from 'events';

export type OnEnter = (event: KeyboardEvent) => void;

export function whenEnter(
  event: KeyboardEvent,
  onEnter: OnEnter,
): OnEnter {
  return (event) => {
    if (event.key === 'Enter') {
      onEnter(event);
    }
  };
}

export function whenLeave(
  event: KeyboardEvent,
  onLeave: OnEnter,
): OnEnter {
  return (event) => {
    if (event.key === 'Leave') {
      onLeave(event);
    }
  };
}
```
  ]],
}, { placeholder_unchanged = M.placeholder_unchanged })

M.editor_predicted_output = build_prompt({
  [[
```{{language}}
{{original_content}}
```
  ]],
})

M.editor_system_prompt = build_prompt({
  [[
<example>
# User
{{example_user}}
# Assistant
{{example_assistant}}
</example>

Act as a very detail oriented text & code editor.

You are getting a patch and the original code and are outputting the FULL code with changes applied.

- Replace ALL placeholders like `{{placeholder_unchanged}}` with the original code
- Always output the FULLY UPDATED FILE. DO NOT remove anything if not otherwise specified!
- ALWAYS REPLACE EVERY, SINGLE OCCURENCE of `// {{placeholder_unchanged}}`, `# {{placeholder_unchanged}}` or `-- {{placeholder_unchanged`. ALWAYS!!!
```
  ]],
}, {
  placeholder_unchanged = M.placeholder_unchanged,
  example_user = M.editor_example_user,
  example_assistant = M.editor_example_assistant_response,
})

return M
