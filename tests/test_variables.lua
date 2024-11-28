---@diagnostic disable-next-line: unused-local
local expect, eq = MiniTest.expect, MiniTest.expect.equality

local T = MiniTest.new_set()

T['parse_variable_uses'] = MiniTest.new_set()

T['parse_variable_uses']['should parse variable uses'] = function()
  local Variables = require('ai.variables')
  local result = Variables.parse_variable_uses([[
    Please find all the errors in my #buffer using #diagnostics.
  ]])
  eq(result, {
    { raw = '#buffer', name = 'buffer', params = {} },
    { raw = '#diagnostics', name = 'diagnostics', params = {} },
  })
end

T['parse_variable_uses']['should omit duplicate variable uses'] = function()
  local Variables = require('ai.variables')
  local result = Variables.parse_variable_uses([[ #buffer #buffer ]])
  eq(result, {
    { raw = '#buffer', name = 'buffer', params = {} },
  })
end

T['parse_variable_uses']['parse parameter'] = function()
  local Variables = require('ai.variables')
  local result = Variables.parse_variable_uses([[ #buffer:parameter ]])
  eq(result, {
    {
      raw = '#buffer:parameter',
      name = 'buffer',
      params = { 'parameter' },
    },
  })
end

T['parse_variable_uses']['parse multiple parameters'] = function()
  local Variables = require('ai.variables')
  local result = Variables.parse_variable_uses([[ #buffer:p1:p2:p3 ]])
  eq(result, {
    {
      raw = '#buffer:p1:p2:p3',
      name = 'buffer',
      params = { 'p1', 'p2', 'p3' },
    },
  })
end

T['parse_variable_uses']['parse parameters wrapped in `'] = function()
  local Variables = require('ai.variables')
  local result =
    Variables.parse_variable_uses([[ #buffer:`param 1`:`param:2` ]])
  eq(result, {
    {
      raw = '#buffer:`param 1`:`param:2`',
      name = 'buffer',
      params = { 'param 1', 'param:2' },
    },
  })
end

return T
