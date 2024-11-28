-- Define a module
local M = {}

local TOKEN_START = '<|COMPLETION_START|>'
local TOKEN_END = '<|COMPLETION_END|>'

local system_prompt = vim
  .trim([[
You are an intelligent code auto-completion assistant.
Your task is to provide accurate and context-aware code suggestions based on the given file content and cursor position.

INPUT:
- You are getting some code as input with the cursor position marked as {{TOKEN_START}}{{TOKEN_END}}.
- Additional instructions might be added above the cursor as comments. If this is the case, try to solve the task in your completion.

OUTPUT:
- Complete the code between {{TOKEN_START}}{{TOKEN_END}}.
- ALWAYS wrap your completion with {{TOKEN_START}} and {{TOKEN_END}}. NEVER OMIT THESE MARKERS.
- ONLY output your completion! NO SURROUNDING CODE!
- If there is already an ident before {{TOKEN_START}}, do not repeat it!
- Try to immitate the patterns and code style already existing in the file.

Provide clean, well-documented code completions without additional explanations.

## Example 1
<input>
```javascript
function helloWorld() {
  {{TOKEN_START}}{{TOKEN_END}}
}
```
</input>

<output>
  {{TOKEN_START}}console.log('Hello World'){{TOKEN_END}}
</output>

## Example 2
<input>
```javascript
function add({{TOKEN_START}}{{TOKEN_END}}) {
  return a + b;
}
```
</input>

<output>
{{TOKEN_START}}a, b{{TOKEN_END}}
</output>

## Example 3
<input>
```lua
{{TOKEN_START}}{{TOKEN_END}}
function say_hello(name)
  print("Hello " .. name)
end
```
</input>

<output>
{{TOKEN_START}}---Print "Hello <name>" to the console.
---@param name string
---@return nil{{TOKEN_END}}
</output>

## Example 4
<input>
```lua
const firstName = "Karl"
console.log(`Hello ${{{TOKEN_START}}{{TOKEN_END}}}`);
```
</input>

<output>
{{TOKEN_START}}firstName{{TOKEN_END}}
</output>
]])
  :gsub('{{(.-)}}', { TOKEN_START = TOKEN_START, TOKEN_END = TOKEN_END })

local ns_id = vim.api.nvim_create_namespace('ai_completion')

function M.trigger_completion()
  local config = require('ai.config').get()
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

  render_ghost_text('...')
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
      response_content = update.response or ''
      -- Extract content between tokens
      suggestion = string.match(
        response_content,
        TOKEN_START .. '(.-)' .. TOKEN_END
      ) or ''
      -- If <|END|> is not found, extract content to the end of the line
      if suggestion == '' then
        suggestion = string.match(response_content, TOKEN_START .. '(.-)\n')
          or ''
      end
      if suggestion == '' then
        suggestion = string.match(response_content, '(.-)' .. TOKEN_END) or ''
      end
      render_ghost_text(suggestion or '...')
    end,
    on_exit = function()
      if vim.trim(suggestion) == '' then
        -- Remove code block if present
        local fallback = require('ai.utils.treesitter').extract_code(
          response_content
        ) or response_content
        -- Remove tokens if present
        fallback = fallback:gsub(TOKEN_START, ''):gsub(TOKEN_END, '')
        render_ghost_text(fallback)
      else
        render_ghost_text(suggestion)
      end
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
      require('ai.config').get().mappings.completion.accept_suggestion,
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
    require('ai.config').get().mappings.completion.accept_suggestion,
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
