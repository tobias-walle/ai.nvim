local M = {}

local FilesContext = require('ai.utils.files_context')
local Images = require('ai.utils.images')

---@class PromptInputOptions
---@field prompt string
---@field modify_text? fun(text: string): string
---@field enable_thinking_option? boolean
---@field enable_files_context_option? boolean
---@field width? number  -- Optional custom width for the prompt input window
---@field save_to_history? boolean  -- Whether to save the prompt to history (default: true)

---@class PromptInputFlags
---@field model? 'default' | 'thinking'

---@param opts PromptInputOptions
---@param callback fun(input: ai.AdapterMessageContent, flags: PromptInputFlags)
---@return nil
function M.open_prompt_input(opts, callback)
  M.load_history()

  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_set_option_value('ft', 'markdown', { buf = bufnr })

  local maximize = false

  -- History navigation state
  local history_index = nil
  local original_lines = nil

  ---@type PromptInputFlags
  local flags = { model = nil }

  --- @return vim.api.keyset.win_config
  local function get_win_options()
    local screen_width = vim.o.columns
    local screen_height = vim.o.lines
    local win_row = 3
    local width
    if maximize then
      width = screen_width - 6
    elseif opts.width then
      width = opts.width
    else
      width = 50
    end
    local height = maximize and screen_height - 6 - win_row or 10
    local win_col = math.floor((screen_width - width) / 2)
    local footer_items = {}
    if opts.enable_thinking_option then
      table.insert(footer_items, flags.model or 'default')
    end
    if opts.enable_files_context_option then
      local files_label = FilesContext.enabled and #FilesContext.get_files()
        or '-'
      table.insert(footer_items, files_label .. ' ')
    end
    return {
      relative = 'editor',
      width = width,
      height = height,
      row = win_row,
      col = win_col,
      title = ' ' .. (opts.prompt or '') .. ' ',
      title_pos = 'center',
      style = 'minimal',
      border = 'rounded',
      focusable = true,
      zindex = 100,
      footer = #footer_items > 0
          and ' ' .. table.concat(footer_items, ' | ') .. ' '
        or nil,
      footer_pos = #footer_items > 0 and 'center' or nil,
    }
  end

  local win = vim.api.nvim_open_win(bufnr, true, get_win_options())
  vim.api.nvim_set_option_value('wrap', true, { win = win })
  vim.cmd('startinsert')

  local function refresh_options()
    if vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_set_config(win, get_win_options())
    end
  end

  local autocmd_id = vim.api.nvim_create_autocmd('User', {
    group = vim.api.nvim_create_augroup(
      'PromptInputFilesContext',
      { clear = true }
    ),
    pattern = 'AiFilesContextChanged',
    callback = refresh_options,
  })

  local function cleanup_autocmds()
    pcall(vim.api.nvim_del_autocmd, autocmd_id)
  end

  vim.api.nvim_create_autocmd('BufWipeout', {
    buffer = bufnr,
    once = true,
    callback = cleanup_autocmds,
  })

  local function cycle_model()
    if flags.model == nil or flags.model == 'default' then
      flags.model = 'thinking'
    else
      flags.model = 'default'
    end
    refresh_options()
  end

  local function toggle_maximize()
    maximize = not maximize
    refresh_options()
  end

  local function cancel()
    cleanup_autocmds()
    vim.api.nvim_win_close(win, true)
  end

  local function confirm()
    cleanup_autocmds()
    vim.api.nvim_win_close(win, true)
    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, true)
    local text = table.concat(lines, '\n')
    local save_to_history = opts.save_to_history
    if save_to_history == nil or save_history then
      table.insert(M.history, text)
      M.save_history()
    end

    if opts.modify_text then
      text = opts.modify_text(text)
    end

    callback(M._parse_prompt_content(text), flags)
  end

  local keymap_opts = { buffer = bufnr, silent = true }
  vim.keymap.set('n', '<ESC>', cancel, keymap_opts)
  vim.keymap.set('n', '<CR>', confirm, keymap_opts)
  vim.keymap.set({ 'n', 'i' }, '<S-CR>', confirm, keymap_opts)
  vim.keymap.set('n', '<localleader>m', toggle_maximize, keymap_opts)
  vim.keymap.set(
    'n',
    '<localleader>i',
    Images.paste_image_as_markdown,
    keymap_opts
  )

  if opts.enable_thinking_option then
    vim.keymap.set('n', '<tab>', cycle_model, keymap_opts)
  end

  local function set_buffer_lines(lines)
    local split_lines = vim.split(lines, '\n')
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, true, split_lines)
    local last_line = #split_lines
    local last_col = #split_lines[#split_lines] or 0
    vim.api.nvim_win_set_cursor(win, { last_line, last_col })
  end

  local function history_up()
    if #M.history == 0 then
      return
    end
    if history_index == nil then
      original_lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, true)
      history_index = #M.history
    elseif history_index > 1 then
      history_index = history_index - 1
    end
    set_buffer_lines(M.history[history_index])
  end

  local function history_down()
    if history_index ~= nil and history_index < #M.history then
      history_index = history_index + 1
      set_buffer_lines(M.history[history_index])
    else
      -- Restore original input
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, true, original_lines or { '' })
      history_index = nil
    end
  end

  vim.keymap.set({ 'n', 'i' }, '<Up>', history_up, keymap_opts)
  vim.keymap.set({ 'n', 'i' }, '<Down>', history_down, keymap_opts)
end

M.history = {}

---@return string
local function get_history_file()
  local config = require('ai.config').get()
  return config.data_dir .. '/prompt_input_history.json'
end

function M.save_history()
  local ok, encoded = pcall(vim.fn.json_encode, M.history)
  if ok and encoded then
    vim.fn.writefile({ encoded }, get_history_file())
  end
end

function M.load_history()
  if vim.fn.filereadable(get_history_file()) == 1 then
    local lines = vim.fn.readfile(get_history_file())
    if lines and #lines > 0 then
      local ok, decoded = pcall(vim.fn.json_decode, table.concat(lines, ''))
      if ok and type(decoded) == 'table' then
        M.history = decoded
      end
    end
  end
end

---@param prompt string
---@return AdapterMessageContentItem[]
function M._parse_prompt_content(prompt)
  local content_items = {}
  for img_path in prompt:gmatch('!%[%]%((.-)%)') do
    table.insert(content_items, {
      type = 'image',
      media_type = 'image/png',
      base64 = Images.read_image_as_base64(img_path),
    })
  end
  table.insert(content_items, { type = 'text', text = prompt })
  return content_items
end

return M
