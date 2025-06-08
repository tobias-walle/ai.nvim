local M = {}

---@class ai.SummarizeChat.Result
---@field chat_summary string
---@field relevant_context string
---@field tasks string

---@class ai.SummarizeChat.Options
---@field on_summarization fun(result: string)

---@param opts ai.SummarizeChat.Options
---@return ai.ToolDefinition
function M.create_complete_task_tool(opts)
  opts = opts or {}
  ---@type ai.ToolDefinition
  local tool = {
    definition = {
      name = 'create_checkpoint',
      description = vim.trim([[
Summarize the current chat history.
Use this if it gets quite big and/or contains a lot of unrelated information.
Also do it after you did a lot of research for finding related context.
Then defining the summary, reason about what is relevant and what is not.
    ]]),
      parameters = {
        type = 'object',
        required = { 'chat_summary', 'relevant_context' },
        properties = {
          chat_summary = {
            type = 'string',
            description = vim.trim([[
A summary of the chat history in a numbered list.
Just focus on the main events.
Think about what might be relevant for the task.
            ]]),
            example = vim.trim([[
1. The user requested to document all packages in the project
2. I figured out that the project is a pnpm project by reading the package.json
3. I found the package folder via pnpm-workspaces.yaml
4. I found 3 packages
            ]]),
          },
          relevant_context = {
            type = 'string',
            description = vim.trim([[
Context that is relevant. Like files, functions, learnings about the project structure, best practices, etc.
You MUST use direct Citations! This way no important context is lost.
Never omit important details, like concrete line numbers, error messages, or literal code snippets if they can help solving the task at hand!
Don't repeat the project rules!
            ]]),
          },
          tasks = {
            type = 'string',
            description = vim.trim([[
Tasks that are already done and tasks that remain.
Treat this like a TODO list.
Extend or update this list, based on the new knowledge your are obtaining.
Use this to keep track of the overreaching task at hand.
Always start with task with `- [x]` if already completed or `- [ ]` if is still planned.
            ]]),
            example = vim.trim([[
- [x] Documented the `@example/utils`
- [ ] Documented the `@example/components`
- [ ] Documented the `@example/auth`
            ]]),
          },
        },
      },
    },
    execute = function(params, _)
      ---@cast params ai.SummarizeChat.Result
      local result = require('ai.utils.strings').replace_placeholders(
        vim.trim([[
Here is a summary of our conversation so far:
<summarized-chat-history>
{{summary}}
</summarized-chat-history>

<context>
{{context}}
</context>

<tasks>
{{tasks}}
</tasks>
        ]]),
        {
          summary = params.chat_summary,
          context = params.relevant_context,
          tasks = params.tasks,
        }
      )
      if opts.on_summarization then
        opts.on_summarization(result)
      end
    end,
    render = function(tool_call)
      local params = tool_call.params
      local lines = { '', '# 📝 Summarize Conversation' }
      if not params then
        return lines
      end
      table.insert(lines, '')
      table.insert(lines, '## Chat')
      table.insert(lines, params.chat_summary or '...')
      table.insert(lines, '')
      table.insert(lines, '## Context')
      table.insert(lines, params.relevant_context or '...')
      table.insert(lines, '')
      table.insert(lines, '## Tasks')
      table.insert(lines, params.tasks or '...')
      return lines
    end,
  }
  return tool
end

return M
