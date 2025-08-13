local MiniTest = require('mini.test')

MiniTest.setup({
  collect = {
    find_files = function()
      return vim.fn.globpath('tests', 'test_*.lua', true, true)
    end,
  },
})

MiniTest.run()
