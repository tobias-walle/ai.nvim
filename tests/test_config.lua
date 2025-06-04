local eq = MiniTest.expect.equality
local Config = require('ai.config')
local uv = vim.uv or vim.loop

local T = MiniTest.new_set()

local function write_file(path, content)
  local fd = uv.fs_open(path, 'w', 438)
  if not fd then return false end
  uv.fs_write(fd, content, 0)
  uv.fs_close(fd)
  return true
end

local function tmpfile(content, ext)
  ext = ext or 'md'
  local name = os.tmpname() .. '.' .. ext
  write_file(name, content)
  return name
end

local function tmpdir(files)
  local dir = os.tmpname() .. '_dir'
  uv.fs_mkdir(dir, 448)
  for fname, content in pairs(files) do
    local path = dir .. '/' .. fname
    write_file(path, content)
  end
  return dir
end

T['resolve_rules'] = MiniTest.new_set()

T['resolve_rules']['should return nil for nil input'] = function()
  eq(Config.resolve_rules(''), nil)
end

T['resolve_rules']['should return nil for non-existent file'] = function()
  eq(Config.resolve_rules('/tmp/this_file_does_not_exist.md'), nil)
end

T['resolve_rules']['should load a single file'] = function()
  local file = tmpfile('# Rule1\nHello')
  eq(Config.resolve_rules(file), '# Rule1\nHello')
  uv.fs_unlink(file)
end

T['resolve_rules']['should load the first existing file from a list'] = function()
  local file1 = tmpfile('# Rule1')
  local file2 = tmpfile('# Rule2')
  eq(Config.resolve_rules({ file1, file2 }), '# Rule1')
  uv.fs_unlink(file1)
  uv.fs_unlink(file2)
end

T['resolve_rules']['should load all markdown files in a directory'] = function()
  local dir = tmpdir({
    ['a.md'] = '# A',
    ['b.md'] = '# B',
    ['c.txt'] = 'not md',
  })
  local result = Config.resolve_rules(dir)
  assert(result ~= nil and result:find('# A'))
  assert(result ~= nil and result:find('# B'))
  assert(result ~= nil and not result:find('not md'))
  -- cleanup
  uv.fs_unlink(dir .. '/a.md')
  uv.fs_unlink(dir .. '/b.md')
  uv.fs_unlink(dir .. '/c.txt')
  uv.fs_rmdir(dir)
end

T['resolve_rules']['should handle relative paths'] = function()
  local cwd = vim.fn.getcwd()
  local file = 'test_rule.md'
  local path = cwd .. '/' .. file
  write_file(path, 'relpath')
  eq(Config.resolve_rules(file), 'relpath')
  uv.fs_unlink(path)
end

T['resolve_rules']['should return nil for empty string'] = function()
  eq(Config.resolve_rules(''), nil)
end

return T

