-- Define a module
local M = {}

local TOKEN = '<|cursor_is_here|>'

local system_prompt = vim
  .trim([[
You are an intelligent code auto-completion assistant.
Your task is to provide accurate and context-aware code suggestions based on the given file content and cursor position.

INPUT:
- You are getting some code as input with the cursor position marked as {{TOKEN}}.
- Additional instructions might be added above the cursor as comments. If this is the case, try to solve the task in your completion.

OUTPUT:
- Complete the code at {{TOKEN}}.
- ONLY output your completion! NO SURROUNDING CODE!
- If there is already an ident before {{TOKEN}}, do not repeat it!
- Immitate the patterns and code style already existing in the file.

Provide clean code completions without additional explanations.

## Example 1
<input>
```javascript
function helloWorld() {
  {{TOKEN}}
}
```
</input>

<output>
```javascript
console.log('Hello World');
```
</output>

## Example 2
<input>
```typescript
function fizzBuzz(n: number): void {
    for (let i = 1; i <= n; i++) {
        {{TOKEN}}
    }
}
```
</input>

Note: We skip the first indent, as it is already there, but we make sure the rest of the code has leading whitepace.
<output>
```typescript
if (i % 15 === 0) {
            console.log("FizzBuzz");
        } else if (i % 3 === 0) {
            console.log("Fizz");
        } else if (i % 5 === 0) {
            console.log("Buzz");
        } else {
            console.log(i);
        }
```
</output>

## Example 3
<input>
```javascript
function add({{TOKEN}}) {
  return a + b;
}
```
</input>

<output>
```javascript
a, b
```
</output>

## Example 4
<input>
```lua
{{TOKEN}}
function say_hello(name)
  print("Hello " .. name)
end
```
</input>

<output>
```lua
---Print "Hello <name>" to the console.
---@param name string
---@return nil
```
</output>

## Example 5
<input>
```lua
const firstName = "Karl"
console.log(`Hello ${{{TOKEN}}}`);
```
</input>

<output>
```lua
firstName
```
</output>
]])
  :gsub('{{(.-)}}', { TOKEN = TOKEN })

local ns_id = vim.api.nvim_create_namespace('ai_completion')

function M.trigger_completion()
  local adapter = require('ai.config').get_completion_adapter()
  vim.notify(
    '[ai] Trigger completion with ' .. adapter.name .. ':' .. adapter.model,
    vim.log.levels.INFO
  )

  -- Get the buffer content
  local bufnr = vim.api.nvim_get_current_buf()
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)

  -- Get the cursor position
  local row, col = unpack(vim.api.nvim_win_get_cursor(0))

  -- Get language
  local lang = vim.api.nvim_get_option_value('filetype', { buf = bufnr })

  -- Insert the cursor marker at the current position
  local cursor_line = lines[row]
  local before = cursor_line:sub(1, col)
  local after = cursor_line:sub(col + 1)
  lines[row] = before .. TOKEN .. after

  table.insert(lines, 1, '```' .. lang)
  table.insert(lines, '```')

  -- Insert file name as well
  table.insert(lines, 1, 'FILE: ' .. vim.fn.expand('%'))

  local content = table.concat(lines, '\n')

  local cancelled = false
  local response_content = ''
  local suggestion = ''

  local render_ghost_text = function(text)
    require('ai.render').render_ghost_text({
      text = text,
      buffer = bufnr,
      ns_id = ns_id,
      row = row - 1,
      col = col,
    })
  end

  local messages = {
    { role = 'user', content = content },
  }
  local job
  local function send()
    -- Clear old completion if it existing
    if job then
      job:stop()
    end
    vim.api.nvim_buf_clear_namespace(bufnr, ns_id, 0, -1)
    cancelled = false
    response_content = ''
    suggestion = ''

    -- Start new
    render_ghost_text('...')
    job = adapter:chat_stream({
      system_prompt = system_prompt,
      messages = messages,
      temperature = 0,
      max_tokens = 500,
      on_update = function(update)
        if cancelled then
          return
        end
        response_content = update.response or ''
        -- Remove code block if present
        local extracted =
          require('ai.utils.markdown').extract_code(response_content)
        suggestion = extracted[#extracted] and extracted[#extracted].code
          or response_content
        suggestion = vim.trim(suggestion)
        render_ghost_text(suggestion or '...')
      end,
      on_exit = function()
        if cancelled then
          return
        end
        render_ghost_text(suggestion)
      end,
    })
  end

  -- Send it!
  send()

  -- Functions to accept or cancel the suggestion
  local autocmd_id

  local function cleanup()
    cancelled = true
    job:stop()
    vim.api.nvim_buf_clear_namespace(bufnr, ns_id, 0, -1)
    vim.api.nvim_del_autocmd(autocmd_id)
    vim.keymap.del(
      'i',
      require('ai.config').get().mappings.completion.accept_suggestion,
      { buffer = bufnr }
    )
    vim.keymap.del(
      'i',
      require('ai.config').get().mappings.completion.next_suggestion,
      { buffer = bufnr }
    )
    vim.keymap.del(
      'i',
      require('ai.config').get().mappings.completion.next_suggestion_with_prompt,
      { buffer = bufnr }
    )
  end

  local function next_suggestion(prompt)
    if cancelled then
      return
    end
    table.insert(messages, {
      role = 'assistant',
      content = response_content,
    })
    local msg =
      'The user rejected your suggestion, create another one that is meaningfully different.'
    if prompt then
      msg = msg .. '\n' .. 'Notes from the user: ' .. prompt
    end
    table.insert(messages, {
      role = 'user',
      content = msg,
    })
    send()
  end

  local function accept_suggestion()
    -- Insert the suggestion at the cursor
    vim.api.nvim_buf_set_text(
      bufnr,
      row - 1,
      col,
      row - 1,
      col,
      vim.split(suggestion, '\n')
    )
    cleanup()
  end

  -- Map Tab to accept the suggestion
  vim.keymap.set(
    'i',
    require('ai.config').get().mappings.completion.accept_suggestion,
    accept_suggestion,
    { buffer = bufnr, noremap = true }
  )

  -- Map Tab to generate the next suggestion
  vim.keymap.set(
    'i',
    require('ai.config').get().mappings.completion.next_suggestion,
    next_suggestion,
    { buffer = bufnr, noremap = true }
  )

  -- Map Tab to generate the next suggestion with a prompt
  vim.keymap.set(
    'i',
    require('ai.config').get().mappings.completion.next_suggestion_with_prompt,
    function()
      vim.ui.input({ prompt = 'Prompt' }, function(prompt)
        next_suggestion(prompt)
      end)
    end,
    { buffer = bufnr, noremap = true }
  )

  -- Set up autocmd to detect any keypress other than Tab
  autocmd_id = vim.api.nvim_create_autocmd(
    { 'CursorMoved', 'InsertLeave', 'InsertCharPre' },
    {
      callback = function()
        cleanup()
      end,
      buffer = bufnr,
    }
  )
end

return M
