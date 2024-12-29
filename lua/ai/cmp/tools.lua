local cmp = require('cmp')

local S = {}

S.new = function()
  return setmetatable({}, { __index = S })
end

function S:get_keyword_pattern()
  return [[@\k*]]
end

function S:complete(request, callback)
  local items = {}

  -- Add tool completions
  for _, tool in ipairs(require('ai.tools').all) do
    local name = require('ai.tools').get_tool_definition_name(tool)
    table.insert(items, {
      label = '@' .. name,
      kind = cmp.lsp.CompletionItemKind.Function,
      documentation = '@'
        .. name
        .. ' '
        .. (tool.system_prompt or tool.definition.description),
    })
  end

  for name, tools in pairs(require('ai.tools').aliases) do
    table.insert(items, {
      label = '@' .. name,
      kind = cmp.lsp.CompletionItemKind.Function,
      documentation = 'Alias for ' .. vim
        .iter(tools)
        :map(function(tool)
          return '@' .. tool
        end)
        :join(' '),
    })
  end

  callback({ items = items, isIncomplete = true })
end

function S:get_debug_name()
  return 'ai-tools'
end

return S
