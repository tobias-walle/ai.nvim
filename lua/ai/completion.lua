-- Define a module
local M = {}

local TOKEN = '<|CURSOR|>'

local system_prompt = vim
  .trim([[
You are an intelligent code auto-completion assistant.
Your task is to provide accurate and context-aware code suggestions based on the given file content and cursor position.

INPUT:
- You are getting some code as input with the cursor position marked as {{TOKEN}}.
- Additional instructions might be added above the cursor as comments. If this is the case, try to solve the task in your completion.

OUTPUT:
- Complete the code at {{TOKEN}}.
- Repeat the context given to you before and after {{TOKEN}}.
- Answer in a single code block.
- Try to immitate the patterns and code style already existing in the file.
- NEVER modify existing code, ONLY add new code
- NEVER add comments in places where they don't make sense syntactically

## Example 1
<input>
```javascript
function helloWorld() {
  {{TOKEN}}
}
```

Start with EXACTLY:
`function helloWorld() {
  `
End with EXACTLY:
`
}`
</input>

<output>
```javascript
function helloWorld() {
  console.log('Hello World')
}
```
</output>

## Example 2
<input>
```javascript
function add({{TOKEN}}) {
  return a + b;
}
```

Start with EXACTLY:
`function add(`

End with EXACTLY:
`) {
  return a + b;
}`
</input>

<output>
```javascript
function add(a, b) {
  return a + b;
}
```
</output>

## Example 3
<input>
```lua
{{TOKEN}}
function say_hello(name)
  print("Hello " .. name)
end
```

Start with EXACTLY:
``

End with EXACTLY:
`
function say_hello(name)
`
</input>

<output>
```lua
---Print "Hello <name>" to the console.
---@param name string
---@return nil
function say_hello(name)
```
</output>

## Example 4
<input>
```lua
const firstName = "Karl"
console.log(`Hello ${{{TOKEN}}}`);
```

Start with EXACTLY:
`console.log(`Hello ${`

End with EXACTLY:
`}`);
`
</input>

<output>
```lua
console.log(`Hello ${firstName}`);
```
</output>
]])
  :gsub('{{(.-)}}', { TOKEN = TOKEN })

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
  local before_in_line = cursor_line:sub(1, col)
  local after_in_line = cursor_line:sub(col + 1)
  lines[row] = before_in_line .. TOKEN .. after_in_line

  local lines_before = vim.list_slice(lines, row - 2, row - 1)
  local lines_after = vim.list_slice(lines, row + 1, row + 2)
  -- We ignore that is before and after in line, because this confuses the model
  local context_before = vim.list_extend(lines_before, { before_in_line })
  local context_after = vim.list_extend({ after_in_line }, lines_after)
  local context_before_str = table.concat(context_before, '\n')
  local context_after_str = table.concat(context_after, '\n')

  table.insert(lines, 1, '```' .. lang)
  table.insert(lines, '```')

  -- Insert file name as well
  table.insert(lines, 1, 'FILE: ' .. vim.fn.expand('%'))

  -- Make the task very clear
  local function format_context(context)
    table.insert(lines, '`' .. (context[1] or ''))
    lines = vim.list_extend(lines, vim.list_slice(context, 2, #context - 1))
    table.insert(lines, (context[#context] or '') .. '`')
  end

  table.insert(lines, '')
  table.insert(lines, 'Start your completion EXACTLY with:')
  format_context(context_before)
  table.insert(lines, '')
  table.insert(lines, 'And end EXACTLY with:')
  format_context(context_after)

  local content = table.concat(lines, '\n')
  print('REQUEST')
  print(content)
  print('REQUEST END')

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
      -- Remove code block
      local code = require('ai.utils.treesitter').extract_code(response_content)
      if code ~= nil then
        code = code.sub(code, #context_before_str + 1)
        code = code.sub(code, 1, #code - #after_in_line - #context_after_str)
        -- Remove prefix
        -- -- Extract content between tokens
        -- suggestion = string.match(
        --   response_content,
        --   TOKEN_START .. '(.-)' .. TOKEN_END
        -- ) or ''
        -- -- If <|END|> is not found, extract content to the end of the line
        -- if suggestion == '' then
        --   suggestion = string.match(response_content, TOKEN_START .. '(.-)\n')
        --     or ''
        -- end
        -- if suggestion == '' then
        --   suggestion = string.match(response_content, '(.-)' .. TOKEN_END) or ''
        -- end
        suggestion = code
        render_ghost_text(suggestion or '...')
      end
    end,
    on_exit = function()
      print('RESPONSE')
      print(response_content)
      print('RESPONSE END')
      -- if vim.trim(suggestion) == '' then
      --   -- Remove code block if present
      --   local fallback = require('ai.utils.treesitter').extract_code(
      --     response_content
      --   ) or response_content
      --   -- Remove tokens if present
      --   fallback = fallback:gsub(TOKEN_START, ''):gsub(TOKEN_END, '')
      --   render_ghost_text(fallback)
      -- else
      --   render_ghost_text(suggestion)
      -- end
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
