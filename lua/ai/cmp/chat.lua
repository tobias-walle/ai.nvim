--- @module 'blink.cmp'
--- @class blink.cmp.Source
local source = {}

function source.new(opts)
  local self = setmetatable({}, { __index = source })
  self.opts = opts or {}
  return self
end

function source:enabled()
  if vim.bo.filetype ~= 'markdown' then
    return false
  end
  local name = vim.api.nvim_buf_get_name(0)
  -- Name ends with ai-chat
  return name:match('ai%-chat$') ~= nil
end

function source:get_trigger_characters()
  return { '#', '@' }
end

function source:get_completions(ctx, callback)
  --- @type lsp.CompletionItem[]
  local items = {}

  local running = 1
  local complete = function()
    running = running - 1
    if running <= 0 then
      callback({
        items = items,
        is_incomplete_backward = false,
        is_incomplete_forward = false,
      })
    end
  end

  -- Add variable completions
  if ctx.line:match('^#') then
    for _, variable in ipairs(require('ai.variables').all) do
      local label = '#' .. variable.name
      if variable.min_params and variable.min_params > 0 then
        label = label .. ':'
      end
      table.insert(items, {
        label = label,
        kind = require('blink.cmp.types').CompletionItemKind.Variable,
        documentation = 'Variable: ' .. variable.name,
      })
      if variable.cmp_items ~= nil then
        running = running + 1
        variable.cmp_items(ctx, function(new_items)
          for _, item in ipairs(new_items) do
            table.insert(items, item)
          end
          complete()
        end)
      end
    end
  end

  -- Add tool completions
  if ctx.line:match('^@') then
    for _, tool in ipairs(require('ai.tools').all) do
      local name = require('ai.tools').get_tool_definition_name(tool)
      table.insert(items, {
        label = '@' .. name,
        kind = require('blink.cmp.types').CompletionItemKind.Class,
        documentation = '@'
          .. name
          .. ' '
          .. (tool.system_prompt or tool.definition.description),
      })
    end

    -- Add tool aliases
    for name, tools in pairs(require('ai.tools').aliases) do
      table.insert(items, {
        label = '@' .. name,
        kind = require('blink.cmp.types').CompletionItemKind.Module,
        documentation = 'Alias for ' .. vim
          .iter(tools)
          :map(function(tool)
            return '@' .. tool
          end)
          :join(' '),
      })
    end
  end

  complete()
  return function() end
end

function source:execute(ctx, item, callback, default_implementation)
  default_implementation()
  callback()
end

return source
