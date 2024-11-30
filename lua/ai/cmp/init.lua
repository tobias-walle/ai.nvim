local M = {}

---@return { name: string, source: any }[]
local function get_all_source_definitions()
  local definitions = {
    { name = 'ai-variables', source = require('ai.cmp.variables').new() },
    { name = 'ai-tools', source = require('ai.cmp.tools').new() },
  }

  local Variables = require('ai.variables')
  for _, variable in ipairs(Variables.all) do
    if variable.cmp_source then
      local name = 'ai-variable-' .. variable.name
      local source = variable.cmp_source().new()
      table.insert(definitions, { name = name, source = source })
    end
  end

  return definitions
end

function M.register_sources()
  local cmp_exists, cmp = pcall(require, 'cmp')
  if cmp_exists then
    for _, definition in ipairs(get_all_source_definitions()) do
      cmp.register_source(definition.name, definition.source)
    end
  end
end

function M.setup_buffer()
  local cmp_exists, cmp = pcall(require, 'cmp')
  if cmp_exists then
    local sources = vim
      .iter(get_all_source_definitions())
      :map(function(definition)
        return { name = definition.name }
      end)
      :totable()
    cmp.setup.buffer({ sources = sources })
  end
end

return M
