local S = {}

S.new = function()
  return setmetatable({}, { __index = S })
end

function S:get_keyword_pattern()
  return [[#\k*]]
end

function S:complete(request, callback)
  local cmp = require('cmp')
  local items = {}

  -- Add variable completions
  for _, variable in ipairs(require('ai.variables').all) do
    local label = '#' .. variable.name
    if variable.min_params and variable.min_params > 0 then
      label = label .. ':'
    end
    table.insert(items, {
      label = label,
      kind = cmp.lsp.CompletionItemKind.Variable,
      documentation = 'Variable: ' .. variable.name,
    })
  end

  callback({ items = items, isIncomplete = true })
end

function S:get_debug_name()
  return 'ai-variables'
end

return S
