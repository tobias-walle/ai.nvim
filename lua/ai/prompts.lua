local M = {}

local build_prompt = require('ai.utils.prompt_builder').build_prompt
local replace_placeholders = require('ai.utils.strings').replace_placeholders

M.placeholder_unchanged = '... existing code ...'

M._system_prompt_general_rules = vim.trim([[
===

# CODING AND FORMATTING

- Always use best practices when coding.
- Respect and use existing conventions that are already present in the code base.
- If a library that is already used, could solve the specified problem, prefer it's use over your own implementation.
- Try to stay DRY, but duplicate code if it makes sense.
- Create a new line after each sentence.
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
As an agent, you act autonomously. You fulfill the given tasks using the tools provided to you.
  ]],
  '',
  M._system_prompt_general_rules,
  [[
===

# TOOL USE

You have access to a set of tools that are executed upon the user's approval.
You can multiple tools per message, and will receive the result of that tool use in the user's response.
You use tools step-by-step to accomplish a given task, with each tool use informed by the result of the previous tool use.
  ]],
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
===

# USER RULES

{{custom_rules}}

===

# RELEVANT FILES CONTEXT

{{files_context}}

===

# DIAGNOSTICS CONTEXT

```text {{filename}}
{{diagnostics}}
```

===

# CURRENT FILE CONTEXT

```{{language}} {{filename}}
{{content}}
```

===

# INSTRUCTIONS

- Fullfill the task below by using the tools provided to you. Focus your changes on the FILE, but also take other files in the context into account.
- Only fix the DIAGNOSTICS if explicitly instructed.
- Formulate a plan first, explain your intended changes and then use the right tools for the job to do them.

===

# TASK

{{intructions}}
]])

M.commands_edit_file = vim.trim([[
# Example
## User
<instructions>
Add a new function to update events.
</instructions

## Assistant
The user asked me the add a new function to update events. For this:
- I will update the EventsApi interface, to contain the new function `updateEvents`
- I will imlement the new function in createEventsApi
- The rest should remain unchanged.

```typescript src/events.ts
// ... existing code ...

export interface EventsApi {
  // ... existing code ...
  updateEvents(events: EventInput[]): Promise<void>;
}

function createEventsApi(client: Client): EventsApi {
  // ... existing code ...
  return {
    // ... existing code ...
    updateEvents: (events) => client.patch('events', { json: events }).json(),
  };
}

// ... existing code ...
```

# Actual Task
{{files_context}}
<diagnostics>
```text {{filename}}
{{diagnostics}}
```
</diagnostics>
<file>
```{{language}} {{filename}}
{{content}}
```
</file>
{{selection}}
<instructions>
{{intructions}}
Output only the changed code
</instructions>

{{custom_rules}}

- Follow the <instructions> and respond with the code replacing the file content in the <file> code block!
- Only fix the <diagnostics> if explicitly instructed
- If a selection is provided, focus your changes on the selection, but still do related changes outside of it, like updating references.
- Preserve leading whitespace
- Before outputting the code EXPLAIN YOUR CHANGES.
- ALWAYS PUT THE FILENAME IN THE HEADER, RIGHT TO THE ```<lang>. You can create or edit other files, but only do it if instructed and stay in the same file per default.
- Use the code comment `... existing code ...` to hide unchanged code. Always use the correct comment syntax of the specific language (`// ... existing code ...`, `# ... existing code ...`, `-- ... existing code ...`, etc.).
]])

M.commands_edit_selection = vim.trim([[
<diagnostics>
```text {{filename}}
{{diagnostics_selection}}
```
</diagnostics>

<file>
```{{language}} {{filename}}
{{content}}
```
</file>
{{selection}}
<instructions>
{{intructions}}
</instructions>

{{custom_rules}}

- Follow the <instructions> and respond with the code replacing ONLY the <selection> content in the code block!
- Only fix the <diagnostics> if explicitly instructed
- Preserve leading whitespace
- Avoid comments explaining your changes
]])

M.commands_fast_edit_retry = build_prompt({
  [[
<notes>
{{notes}}
</notes>

I wasn't happy with the result. Please retry considering the notes above if given.
As only your last response will be considered, please repeat all changes that are still relevant.
  ]],
})

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
