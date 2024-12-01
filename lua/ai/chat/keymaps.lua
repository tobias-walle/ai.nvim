local M = {}

local Cache = require('ai.utils.cache')
local Buffer = require('ai.chat.buffer')
local send_message = require('ai.chat').send_message
local save_current_chat = require('ai.chat').save_current_chat
local update_messages = require('ai.chat').update_messages
local set_chat_text = require('ai.chat').set_chat_text
local get_initial_msg = require('ai.chat').get_initial_msg

--- Setup keymaps for chat buffer
---@param bufnr number
function M.setup_chat_keymaps(bufnr)
  local config = require('ai.config').get()

  vim.keymap.set('n', config.mappings.chat.submit, function()
    if not vim.b[bufnr].running_job then
      send_message(bufnr)
    end
  end, { desc = 'Submit the current chat', buffer = bufnr, noremap = true })

  vim.keymap.set('n', config.mappings.chat.new_chat, function()
    save_current_chat(bufnr)
    Cache.new_chat()
    update_messages(bufnr, {
      get_initial_msg(),
    })
  end, { desc = 'Start a new chat session', buffer = bufnr, noremap = true })

  vim.keymap.set('n', config.mappings.chat.goto_next_chat, function()
    save_current_chat(bufnr)
    local chat = Cache.next_chat()
    if chat then
      set_chat_text(bufnr, chat)
    end
  end, { desc = 'Go to the next chat session', buffer = bufnr, noremap = true })

  vim.keymap.set(
    'n',
    config.mappings.chat.goto_prev_chat,
    function()
      save_current_chat(bufnr)
      local chat = Cache.previous_chat()
      if chat then
        set_chat_text(bufnr, chat)
      end
    end,
    { desc = 'Go to the previous chat session', buffer = bufnr, noremap = true }
  )

  vim.keymap.set('n', config.mappings.chat.goto_chat_with_telescope, function()
    save_current_chat(bufnr)
    Cache.search_chats({}, function()
      local chat = Cache.load_chat()
      if chat then
        set_chat_text(bufnr, chat)
      end
    end)
  end, {
    desc = 'Search and go to a chat using telescope',
    buffer = bufnr,
    noremap = true,
  })

  vim.keymap.set('n', config.mappings.chat.delete_previous_msg, function()
    save_current_chat(bufnr)
    local messages = Buffer.parse(bufnr).messages
    Cache.new_chat()
    if #messages > 0 then
      table.remove(messages, #messages) -- Remove the last message
      while #messages > 0 and messages[#messages].role ~= 'user' do
        table.remove(messages, #messages) -- Every message until the next user message
      end
      update_messages(bufnr, messages, true)
    end
  end, { desc = 'Delete the previous message', buffer = bufnr, noremap = true })

  vim.keymap.set('n', config.mappings.chat.copy_last_code_block, function()
    local last_code_block = Buffer.parse_last_code_block(bufnr)
    if last_code_block then
      -- Default register
      vim.fn.setreg('"', last_code_block)
      -- System register
      vim.fn.setreg('+', last_code_block)
      vim.notify('Last code block copied to clipboard', vim.log.levels.INFO)
    else
      vim.notify('No code block found', vim.log.levels.WARN)
    end
  end, {
    desc = 'Copy the last code block to clipboard',
    buffer = bufnr,
    noremap = true,
  })
end

return M
