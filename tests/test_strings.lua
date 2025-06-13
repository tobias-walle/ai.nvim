local eq = MiniTest.expect.equality

local T = MiniTest.new_set()

T['replace_placeholders'] = MiniTest.new_set()

T['replace_placeholders']['should replace single placeholder'] = function()
  local Strings = require('ai.utils.strings')
  local result =
    Strings.replace_placeholders('Hello, {{name}}!', { name = 'World' })
  eq(result, 'Hello, World!')
end

T['replace_placeholders']['should replace multiple placeholders'] = function()
  local Strings = require('ai.utils.strings')
  local result = Strings.replace_placeholders(
    'Hi {{first}} {{last}}',
    { first = 'John', last = 'Doe' }
  )
  eq(result, 'Hi John Doe')
end

T['replace_placeholders']['should handle missing placeholders'] = function()
  local Strings = require('ai.utils.strings')
  local result = Strings.replace_placeholders(
    'Hello, {{name}} {{surname}}!',
    { name = 'Alice' }
  )
  eq(result, 'Hello, Alice {{surname}}!')
end

T['replace_placeholders']['should handle numeric values'] = function()
  local Strings = require('ai.utils.strings')
  local result =
    Strings.replace_placeholders('You have {{count}} messages', { count = 5 })
  eq(result, 'You have 5 messages')
end

T['replace_placeholders']['should handle repeated placeholders'] = function()
  local Strings = require('ai.utils.strings')
  local result =
    Strings.replace_placeholders('{{word}} {{word}}', { word = 'echo' })
  eq(result, 'echo echo')
end

T['replace_placeholders']['should not replace when no placeholders'] = function()
  local Strings = require('ai.utils.strings')
  local result =
    Strings.replace_placeholders('No placeholders here', { foo = 'bar' })
  eq(result, 'No placeholders here')
end

T['replace_placeholders']['should handle empty template'] = function()
  local Strings = require('ai.utils.strings')
  local result = Strings.replace_placeholders('', { foo = 'bar' })
  eq(result, '')
end

T['strip_ansi_codes'] = MiniTest.new_set()

T['strip_ansi_codes']['should remove ANSI codes from string'] = function()
  local Strings = require('ai.utils.strings')
  local input = '\27[31mRed\27[0m Normal'
  local result = Strings.strip_ansi_codes(input)
  eq(result, 'Red Normal')
end

T['strip_ansi_codes']['should not change string without ANSI codes'] = function()
  local Strings = require('ai.utils.strings')
  local input = 'Just plain text'
  local result = Strings.strip_ansi_codes(input)
  eq(result, 'Just plain text')
end

T['strip_ansi_codes']['should handle empty string'] = function()
  local Strings = require('ai.utils.strings')
  local result = Strings.strip_ansi_codes('')
  eq(result, '')
end

T['strip_ansi_codes']['should return input if not a string'] = function()
  local Strings = require('ai.utils.strings')
  local result = Strings.strip_ansi_codes(12345)
  eq(result, 12345)
end

T['strip_ansi_codes']['should remove multiple ANSI codes'] = function()
  local Strings = require('ai.utils.strings')
  local input = '\27[32mGreen\27[0m and \27[34mBlue\27[0m'
  local result = Strings.strip_ansi_codes(input)
  eq(result, 'Green and Blue')
end

T['flatten_lines'] = MiniTest.new_set()

T['flatten_lines']['should flatten lines with newlines'] = function()
  local Strings = require('ai.utils.strings')
  local input = { 'a', 'b\nc', 'd' }
  local result = Strings.flatten_lines(input)
  eq(result, { 'a', 'b', 'c', 'd' })
end

T['flatten_lines']['should handle empty input'] = function()
  local Strings = require('ai.utils.strings')
  local input = {}
  local result = Strings.flatten_lines(input)
  eq(result, {})
end

T['flatten_lines']['should handle only empty strings'] = function()
  local Strings = require('ai.utils.strings')
  local input = { '', '', '' }
  local result = Strings.flatten_lines(input)
  eq(result, { '', '', '' })
end

T['flatten_lines']['should handle strings with only newlines'] = function()
  local Strings = require('ai.utils.strings')
  local input = { '\n', '\n\n', '' }
  local result = Strings.flatten_lines(input)
  eq(result, { '', '', '', '', '', '' })
end

T['flatten_lines']['should handle multiple consecutive newlines'] = function()
  local Strings = require('ai.utils.strings')
  local input = { 'a\n\n\nb', 'c' }
  local result = Strings.flatten_lines(input)
  eq(result, { 'a', '', '', 'b', 'c' })
end

T['flatten_lines']['should handle input with no newlines'] = function()
  local Strings = require('ai.utils.strings')
  local input = { 'a', 'b', 'c' }
  local result = Strings.flatten_lines(input)
  eq(result, { 'a', 'b', 'c' })
end

T['flatten_lines']['should handle numbers as input'] = function()
  local Strings = require('ai.utils.strings')
  local input = { 1, '2\n3', 4 }
  local result = Strings.flatten_lines(input)
  eq(result, { '1', '2', '3', '4' })
end

T['flatten_lines']['should preserve leading and trailing newlines'] = function()
  local Strings = require('ai.utils.strings')
  local input = { '\na', 'b\n', '\nc\n' }
  local result = Strings.flatten_lines(input)
  eq(result, { '', 'a', 'b', '', '', 'c', '' })
end

return T
