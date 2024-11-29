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
    table.insert(items, {
      label = '@' .. require('ai.tools').get_tool_definition_name(tool),
      kind = cmp.lsp.CompletionItemKind.Function,
      documentation = 'Tool: '
        .. require('ai.tools').get_tool_definition_name(tool),
    })
  end

  callback({ items = items, isIncomplete = true })
end

function S:get_debug_name()
  return 'ai-tools'
end

return S
