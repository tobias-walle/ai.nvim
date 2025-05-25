local eq = MiniTest.expect.equality

local T = MiniTest.new_set()

T['decode_partial'] = MiniTest.new_set()

T['decode_partial']['should decode valid JSON'] = function()
  local Json = require('ai.utils.json')
  local result = Json.decode_partial('{"a":1,"b":2}')
  eq(result, { a = 1, b = 2 })
end

T['decode_partial']['should fix and decode partial JSON with missing brace'] = function()
  local Json = require('ai.utils.json')
  local result = Json.decode_partial('{"a":1,"b":2')
  eq(result, { a = 1, b = 2 })
end

T['decode_partial']['should fix and decode partial JSON with missing bracket'] = function()
  local Json = require('ai.utils.json')
  local result = Json.decode_partial('[1,2,3')
  eq(result, { 1, 2, 3 })
end

T['decode_partial']['should fix and decode partial JSON with missing quote'] = function()
  local Json = require('ai.utils.json')
  local result = Json.decode_partial('{"a":"hello')
  eq(result, { a = 'hello' })
end

T['decode_partial']['should return nil for completely broken JSON'] = function()
  local Json = require('ai.utils.json')
  local result = Json.decode_partial('not a json')
  eq(result, nil)
end

T['decode_partial']['should handle unterminated string'] = function()
  local Json = require('ai.utils.json')
  local result = Json.decode_partial('"hello')
  eq(result, 'hello')
end

T['decode_partial']['should decode very complex nested JSON'] = function()
  local Json = require('ai.utils.json')
  local json_str =
    [[{"level1": { "level2": { "level3": [ { "id": 1, "data": { "foo": "bar", "baz": [1, 2, 3, {"deep": "value]]
  local result = Json.decode_partial(json_str)
  eq(result, {
    level1 = {
      level2 = {
        level3 = {
          {
            id = 1,
            data = {
              foo = 'bar',
              baz = { 1, 2, 3, { deep = 'value' } },
            },
          },
        },
      },
    },
  })
end

T['decode_partial']['should return nil for empty string'] = function()
  local Json = require('ai.utils.json')
  local result = Json.decode_partial('')
  eq(result, nil)
end

T['decode_partial']['should return nil for nil input'] = function()
  local Json = require('ai.utils.json')
  local result = Json.decode_partial(nil)
  eq(result, nil)
end

T['decode_partial']['should handle trailing commas'] = function()
  local Json = require('ai.utils.json')
  local result = Json.decode_partial('{"a":1,"b":2,}')
  eq(result, { a = 1, b = 2 })
end

T['decode_partial']['should handle trailing commas in arrays'] = function()
  local Json = require('ai.utils.json')
  local result = Json.decode_partial('[1,2,3,]')
  eq(result, { 1, 2, 3 })
end

T['decode_partial']['should handle multiple missing closing characters'] = function()
  local Json = require('ai.utils.json')
  local result = Json.decode_partial('{"a":[1,2,{"b":"test')
  eq(result, { a = { 1, 2, { b = 'test' } } })
end

T['decode_partial']['should handle escaped quotes in strings'] = function()
  local Json = require('ai.utils.json')
  local result = Json.decode_partial('{"message":"He said \\"hello\\"')
  eq(result, { message = 'He said "hello"' })
end

T['decode_partial']['should handle whitespace around JSON'] = function()
  local Json = require('ai.utils.json')
  local result = Json.decode_partial('  {"a":1,"b":2}  ')
  eq(result, { a = 1, b = 2 })
end

T['decode_partial']['should handle mixed nested structures with missing closures'] = function()
  local Json = require('ai.utils.json')
  local result = Json.decode_partial(
    '{"users":[{"name":"John","tags":["admin","user"],"meta":{"active":true'
  )
  eq(result, {
    users = {
      {
        name = 'John',
        tags = { 'admin', 'user' },
        meta = { active = true },
      },
    },
  })
end

T['decode_partial']['should handle array of objects with missing closures'] = function()
  local Json = require('ai.utils.json')
  local result =
    Json.decode_partial('[{"id":1,"name":"first"},{"id":2,"name":"second"')
  eq(result, {
    { id = 1, name = 'first' },
    { id = 2, name = 'second' },
  })
end

return T
