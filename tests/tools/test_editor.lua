---@diagnostic disable-next-line: unused-local
local expect, eq = MiniTest.expect, MiniTest.expect.equality

local child = MiniTest.new_child_neovim()

local U = require('ai.utils.testing').setup(child)

local project_dir

local T = MiniTest.new_set({
  hooks = {
    pre_case = function()
      -- Restart child process with custom 'init.lua' script
      child.restart({ '-u', 'scripts/minimal_init.lua' })
    end,
    post_case = U.post_case_log_debug_info,
    -- Stop once all test cases are finished
    post_once = child.stop,
  },
})

local setup = function()
  project_dir = U.prepare_test_project()
  child.cmd('cd ' .. project_dir)
  local tmp_dir = U.create_tmp_dir()
  ---@type AiConfig
  local options = {
    default_models = { default = 'openai:gpt-4o-mini' },
    data_dir = tmp_dir,
  }
  child.lua(string.format("require('ai').setup(%s)", vim.inspect(options)))
end

T['parsing'] = MiniTest.new_set()

T['parsing']['should parse simple replacements'] = function()
  local Editor = require('ai.tools.editor')
  local result = Editor.parse([[
Sure I will replace Hello with Hello World.

`````typescript src/hello.lua
<<<<<<< ORIGINAL
  print("Hello")
=======
  print("Hello World")
>>>>>>> UPDATED
`````
  ]])
  eq(result, {
    {
      file = 'src/hello.lua',
      calls = {
        {
          type = 'replacement',
          file = 'src/hello.lua',
          replacements = {
            {
              replacement = '  print("Hello World")',
              search = '  print("Hello")',
            },
          },
        },
      },
    },
  })
end

T['parsing']['should parse multiple code blocks'] = function()
  local Editor = require('ai.tools.editor')
  local result = Editor.parse([[
Sure I will replace Hello with Hello World.

`````typescript src/hello.lua
<<<<<<< ORIGINAL
  print("Hello")
=======
  print("Hello World")
>>>>>>> UPDATED
`````

`````typescript src/hello.lua
<<<<<<< ORIGINAL
  function say_hello()
=======
  function say_hello_world()
>>>>>>> UPDATED
`````

`````typescript src/hello2.lua
<<<<<<< ORIGINAL
  print("Hello 2")
=======
  print("Hello World 2")
>>>>>>> UPDATED
`````
  ]])
  eq(result, {
    {
      file = 'src/hello.lua',
      calls = {
        {
          type = 'replacement',
          file = 'src/hello.lua',
          replacements = {
            {
              replacement = '  print("Hello World")',
              search = '  print("Hello")',
            },
          },
        },
        {
          type = 'replacement',
          file = 'src/hello.lua',
          replacements = {
            {
              replacement = '  function say_hello_world()',
              search = '  function say_hello()',
            },
          },
        },
      },
    },
    {
      file = 'src/hello2.lua',
      calls = {
        {
          type = 'replacement',
          file = 'src/hello2.lua',
          replacements = {
            {
              replacement = '  print("Hello World 2")',
              search = '  print("Hello 2")',
            },
          },
        },
      },
    },
  })
end

T['parsing']['should parse replacements with content in between'] = function()
  local Editor = require('ai.tools.editor')
  local result = Editor.parse([[
`````typescript src/hello.lua
local M = {}

function M.say_hello()
<<<<<<< ORIGINAL
  print("Hello")
=======
  print("Hello World")
>>>>>>> UPDATED
end

<<<<<<< ORIGINAL
return T
=======
return M
>>>>>>> UPDATED
`````
  ]])
  eq(result, {
    {
      file = 'src/hello.lua',
      calls = {
        {
          type = 'replacement',
          file = 'src/hello.lua',
          replacements = {
            {
              replacement = '  print("Hello World")',
              search = '  print("Hello")',
            },
            {
              replacement = 'return M',
              search = 'return T',
            },
          },
        },
      },
    },
  })
end

T['parsing']['should parse multiple replacements'] = function()
  local Editor = require('ai.tools.editor')
  local result = Editor.parse([[
`````typescript pkgs/client/src/utils/theme.ts
<<<<<<< ORIGINAL
default: '#FF0000',
light: transparentize(0.7, '#9edac7'),
inverted: '#419F81',
=======
default: '#FF5733',
light: transparentize(0.7, '#FF5733'),
inverted: '#C70039',
>>>>>>> UPDATED
<<<<<<< ORIGINAL
default: '#419F81',
inverted: '#9edac7',
=======
default: '#C70039',
inverted: '#FF5733',
>>>>>>> UPDATED
<<<<<<< ORIGINAL
default: transparentize(0.7, '#000'),
=======
default: transparentize(0.7, '#900C3F'),
>>>>>>> UPDATED
<<<<<<< ORIGINAL
default: '#a5afd7',
light: transparentize(0.7, '#a5afd7'),
inverted: '#354791',
=======
default: '#DAF7A6',
light: transparentize(0.7, '#DAF7A6'),
inverted: '#FFC300',
>>>>>>> UPDATED
<<<<<<< ORIGINAL
default: '#354791',
inverted: '#a5afd7',
=======
default: '#FFC300',
inverted: '#DAF7A6',
>>>>>>> UPDATED
<<<<<<< ORIGINAL
primary: 'rgba(0, 0, 0, 87%)',
secondary: 'rgba(0, 0, 0, 60%)',
dimmed: 'rgba(0, 0, 0, 40%)',
disabled: 'rgba(0, 0, 0, 24%)',
=======
primary: 'rgba(50, 50, 50, 87%)',
secondary: 'rgba(50, 50, 50, 60%)',
dimmed: 'rgba(50, 50, 50, 40%)',
disabled: 'rgba(50, 50, 50, 24%)',
>>>>>>> UPDATED
<<<<<<< ORIGINAL
primary: 'rgba(255, 255, 255, 87%)',
secondary: 'rgba(255, 255, 255, 60%)',
dimmed: 'rgba(255, 255, 255, 40%)',
disabled: 'rgba(255, 255, 255, 38%)',
=======
primary: 'rgba(200, 200, 200, 87%)',
secondary: 'rgba(200, 200, 200, 60%)',
dimmed: 'rgba(200, 200, 200, 40%)',
disabled: 'rgba(200, 200, 200, 38%)',
>>>>>>> UPDATED
<<<<<<< ORIGINAL
error: '#ea3a3a',
=======
error: '#FF5733',
>>>>>>> UPDATED
<<<<<<< ORIGINAL
default: 'rgba(0, 0, 0, 60%)',
light: 'rgba(0, 0, 0, 40%)',
veryLight: 'rgba(0, 0, 0, 20%)',
inverted: 'rgba(255, 255, 255, 60%)',
=======
default: 'rgba(100, 100, 100, 60%)',
light: 'rgba(100, 100, 100, 40%)',
veryLight: 'rgba(100, 100, 100, 20%)',
inverted: 'rgba(200, 200, 200, 60%)',
>>>>>>> UPDATED
<<<<<<< ORIGINAL
page: '#FFFFFF',
error: '#ea3a3a',
success: '#419F81',
successLight: '#d8f3ec',
=======
page: '#F0F0F0',
error: '#FF5733',
success: '#C70039',
successLight: '#FFC300',
>>>>>>> UPDATED
`````
  ]])
  eq(result, {
    {
      file = 'pkgs/client/src/utils/theme.ts',
      calls = {
        {
          type = 'replacement',
          file = 'pkgs/client/src/utils/theme.ts',
          replacements = {
            {
              replacement = "default: '#FF5733',\nlight: transparentize(0.7, '#FF5733'),\ninverted: '#C70039',",
              search = "default: '#FF0000',\nlight: transparentize(0.7, '#9edac7'),\ninverted: '#419F81',",
            },
            {
              replacement = "default: '#C70039',\ninverted: '#FF5733',",
              search = "default: '#419F81',\ninverted: '#9edac7',",
            },
            {
              replacement = "default: transparentize(0.7, '#900C3F'),",
              search = "default: transparentize(0.7, '#000'),",
            },
            {
              replacement = "default: '#DAF7A6',\nlight: transparentize(0.7, '#DAF7A6'),\ninverted: '#FFC300',",
              search = "default: '#a5afd7',\nlight: transparentize(0.7, '#a5afd7'),\ninverted: '#354791',",
            },
            {
              replacement = "default: '#FFC300',\ninverted: '#DAF7A6',",
              search = "default: '#354791',\ninverted: '#a5afd7',",
            },
            {
              replacement = "primary: 'rgba(50, 50, 50, 87%)',\nsecondary: 'rgba(50, 50, 50, 60%)',\ndimmed: 'rgba(50, 50, 50, 40%)',\ndisabled: 'rgba(50, 50, 50, 24%)',",
              search = "primary: 'rgba(0, 0, 0, 87%)',\nsecondary: 'rgba(0, 0, 0, 60%)',\ndimmed: 'rgba(0, 0, 0, 40%)',\ndisabled: 'rgba(0, 0, 0, 24%)',",
            },
            {
              replacement = "primary: 'rgba(200, 200, 200, 87%)',\nsecondary: 'rgba(200, 200, 200, 60%)',\ndimmed: 'rgba(200, 200, 200, 40%)',\ndisabled: 'rgba(200, 200, 200, 38%)',",
              search = "primary: 'rgba(255, 255, 255, 87%)',\nsecondary: 'rgba(255, 255, 255, 60%)',\ndimmed: 'rgba(255, 255, 255, 40%)',\ndisabled: 'rgba(255, 255, 255, 38%)',",
            },
            {
              replacement = "error: '#FF5733',",
              search = "error: '#ea3a3a',",
            },
            {
              replacement = "default: 'rgba(100, 100, 100, 60%)',\nlight: 'rgba(100, 100, 100, 40%)',\nveryLight: 'rgba(100, 100, 100, 20%)',\ninverted: 'rgba(200, 200, 200, 60%)',",
              search = "default: 'rgba(0, 0, 0, 60%)',\nlight: 'rgba(0, 0, 0, 40%)',\nveryLight: 'rgba(0, 0, 0, 20%)',\ninverted: 'rgba(255, 255, 255, 60%)',",
            },
            {
              replacement = "page: '#F0F0F0',\nerror: '#FF5733',\nsuccess: '#C70039',\nsuccessLight: '#FFC300',",
              search = "page: '#FFFFFF',\nerror: '#ea3a3a',\nsuccess: '#419F81',\nsuccessLight: '#d8f3ec',",
            },
          },
        },
      },
    },
  })
end

T['execution'] = MiniTest.new_set()

T['execution']['should execute simple replacement'] = function()
  setup()

  local test_file = project_dir .. '/hello.lua'
  child.cmd('edit ' .. test_file)

  -- Create the editor tool call
  local tool_call = {
    file = 'hello.lua',
    calls = {
      {
        type = 'replacement',
        file = 'hello.lua',
        replacements = {
          {
            search = "  print('Hello')",
            replacement = "  print('Hello World')",
          },
        },
      },
    },
  }

  -- Execute the tool
  child.lua(string.format('tool_call = %s', vim.inspect(tool_call)))
  child.lua([[
    local Editor = require('ai.tools.editor')
    vim.g.callback_called = false
    Editor.execute({}, tool_call)
  ]])

  child.type_keys(',a')

  -- Verify the file content
  local updated_content = vim.fn.readfile(test_file)
  eq(updated_content, {
    'local M = {}',
    '',
    'function M.say_hello()',
    "  print('Hello World')",
    'end',
    '',
    'return M',
  })
end

T['execution']['should execute multiple replacements'] = function()
  setup()

  local test_file = project_dir .. '/hello.lua'
  child.cmd('edit ' .. test_file)

  -- Create the editor tool call
  local tool_call = {
    file = 'hello.lua',
    calls = {
      {
        type = 'replacement',
        file = 'hello.lua',
        replacements = {
          {
            search = "  print('Hello')",
            replacement = "  print('Hello Universe')",
          },
          {
            search = 'function M.say_hello()',
            replacement = 'function M.say_hello_universe()',
          },
        },
      },
    },
  }

  -- Execute the tool
  child.lua(string.format('tool_call = %s', vim.inspect(tool_call)))
  child.lua([[
    local Editor = require('ai.tools.editor')
    vim.g.callback_called = false
    Editor.execute({}, tool_call)
  ]])

  child.type_keys(',a')

  -- Verify the file content
  local updated_content = vim.fn.readfile(test_file)
  eq(updated_content, {
    'local M = {}',
    '',
    'function M.say_hello_universe()',
    "  print('Hello Universe')",
    'end',
    '',
    'return M',
  })
end

T['execution']['should create new file'] = function()
  setup()

  local test_file = project_dir .. '/new_file.lua'

  -- Create the editor tool call
  local tool_call = {
    file = 'new_file.lua',
    calls = {
      {
        type = 'replacement',
        file = 'new_file.lua',
        replacements = {
          {
            search = '',
            replacement = 'print("New file")',
          },
        },
      },
    },
  }

  -- Execute the tool
  child.lua(string.format('tool_call = %s', vim.inspect(tool_call)))
  child.lua([[
    local Editor = require('ai.tools.editor')
    vim.g.callback_called = false
    Editor.execute({}, tool_call)
  ]])

  child.type_keys(',a')

  -- Verify the file content
  local updated_content = vim.fn.readfile(test_file)
  eq(updated_content, {
    'print("New file")',
  })
end

T['execution']['should append to file if original block is empty (or only whitespace)'] = function()
  setup()

  local test_file = project_dir .. '/hello.lua'
  child.cmd('edit ' .. test_file)

  -- Create the editor tool call
  local tool_call = {
    file = 'hello.lua',
    calls = {
      {
        type = 'replacement',
        file = 'hello.lua',
        replacements = {
          {
            search = '\n',
            replacement = "print('Hello World')",
          },
        },
      },
    },
  }

  -- Execute the tool
  child.lua(string.format('tool_call = %s', vim.inspect(tool_call)))
  child.lua([[
    local Editor = require('ai.tools.editor')
    vim.g.callback_called = false
    Editor.execute({}, tool_call)
  ]])

  child.type_keys(',a')

  -- Verify the file content
  local updated_content = vim.fn.readfile(test_file)
  eq(updated_content, {
    'local M = {}',
    '',
    'function M.say_hello()',
    "  print('Hello')",
    'end',
    '',
    'return M',
    "print('Hello World')",
  })
end

return T
