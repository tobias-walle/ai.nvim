-- Define a module
local M = {}

local system_prompt = vim.trim([[
You are an intelligent code auto-completion assistant.
Your task is to provide accurate and context-aware code suggestions based on the given file content and cursor position.

INPUT:
- You are getting some code as input with the cursor position marked as <|START|><|END|>.
- Additional instructions might be added above the cursor as comments. If this is the case, try to solve the task in your completion.

OUTPUT:
- Complete the code between <|START|><|END|>.
- ALWAYS wrap your completion with <|START|> and <|END|>. NEVER omit these markers.
- ONLY output your completion in the code block. NO SURROUNDING CODE!
- Try to immitate the patterns and code style already existing in the file.

Provide clean, well-documented code completions without additional explanations.

## Example 1
<input>
```javascript
function helloWorld() {
<|START|><|END|>
}
```
</input>

<output>
```javascript
<|START|>  console.log('Hello World')<|END|>
```
</output>

## Example 2
<input>
```javascript
function add(<|START|><|END|>) {
  return a + b;
}
```
</input>

<output>
```javascript
<|START|>a, b<|END|>
```
</output>

## Example 3
<input>
```lua
<|START|><|END|>
function say_hello(name)
  print("Hello " .. name)
end
```
</input>

<output>
```lua
<|START|>---Print "Hello <name>" to the console.
---@param name string
---@return nil<|END|>
```
</output>
]])

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
  lines[row] = before .. '<|START|><|END|>' .. after

  table.insert(lines, 1, '```' .. lang)
  table.insert(lines, '```')

  -- Insert file name as well
  table.insert(lines, 1, 'FILE: ' .. vim.fn.expand('%'))

  local content = table.concat(lines, '\n')

  local cancelled = false
  local suggestion = ''

  print(content)
  local job = adapter:chat_stream({
    system_prompt = system_prompt,
    messages = {
      { role = 'user', content = content },
    },
    temperature = 0,
    max_tokens = 500,
    on_update = function(update)
      if cancelled then
        return
      end
      -- Extract content between tokens
      suggestion = string.match(update.response, '<|START|>(.-)<|END|>')
      -- If <|END|> is not found, extract content to the end of the line
      if not suggestion then
        suggestion = string.match(update.response, '<|START|>(.-)\n')
      end
      if not suggestion then
        suggestion = update.response
      end
      require('ai.render').render_ghost_text({
        text = suggestion,
        buffer = bufnr,
        ns_id = ns_id,
        row = row - 1,
        col = col,
      })
    end,
  })

  -- Functions to accept or cancel the suggestion
  local autocmd_id

  local function cleanup()
    cancelled = true
    job:stop()
    vim.api.nvim_buf_clear_namespace(bufnr, ns_id, 0, -1)
    vim.keymap.del(
      'i',
      require('ai.config').get().mappings.accept_suggestion,
      { buffer = bufnr }
    )
    vim.api.nvim_del_autocmd(autocmd_id)
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
    require('ai.config').get().mappings.accept_suggestion,
    accept_suggestion,
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
