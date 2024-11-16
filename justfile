_default:
  just --list

# Download the test dependencies
prepare:
  #!/usr/bin/env sh
  if [ ! -d "deps/mini.nvim" ]; then
    git clone --filter=blob:none https://github.com/echasnovski/mini.nvim deps/mini.nvim
  fi
  if [ ! -d "deps/dressing.nvim" ]; then
    git clone --filter=blob:none https://github.com/stevearc/dressing.nvim -b v3.1.0 deps/dressing.nvim
  fi

# Run all test files
test:
    nvim --headless --noplugin -u ./scripts/minimal_init.lua -c "lua MiniTest.run()"

# Run test a single test file
test_file FILE:
    nvim --headless --noplugin -u ./scripts/minimal_init.lua -c "lua MiniTest.run_file('{{FILE}}')"
