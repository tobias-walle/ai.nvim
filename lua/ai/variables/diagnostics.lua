---@type VariableDefinition
return {
  name = 'diagnostics',
  resolve = function(ctx, params)
    -- Get the text of the leftmost buffer in the current tab and call the callback with it
    -- Let's expect a vertical split setup
    local wins = vim.api.nvim_tabpage_list_wins(0)
    local leftmost_win = wins[1]
    local buf = vim.api.nvim_win_get_buf(leftmost_win)

    -- Get diagnostics for the current buffer
    local diagnostics = vim.diagnostic.get(buf)

    -- If no diagnostics, return a message
    if #diagnostics == 0 then
      return 'No diagnostics found for the current buffer.'
    end

    -- Format diagnostics into a readable string
    local diagnostic_lines = {}

    -- Sort diagnostics by severity (most severe first)
    table.sort(diagnostics, function(a, b)
      return a.severity < b.severity
    end)

    -- Map severity numbers to readable strings
    local severity_map = {
      [vim.diagnostic.severity.ERROR] = 'ERROR',
      [vim.diagnostic.severity.WARN] = 'WARNING',
      [vim.diagnostic.severity.INFO] = 'INFO',
      [vim.diagnostic.severity.HINT] = 'HINT',
    }

    -- Process each diagnostic
    for _, diag in ipairs(diagnostics) do
      local severity = severity_map[diag.severity] or 'UNKNOWN'
      local location =
        string.format('Line %d, Col %d', diag.lnum + 1, diag.col + 1)
      local line = string.format(
        '[%s] %s: %s (%s)',
        severity,
        location,
        diag.message,
        diag.source or 'unknown source'
      )
      table.insert(diagnostic_lines, line)
    end

    -- Return formatted diagnostics
    local path = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(buf), ':.')
    return string.format(
      vim.trim([[
Variable: #diagnostics - Contains the diagnostics messages of the current buffer (like errors and warnings). It is always updated and contains all the changes made before.
FILE: %s
```
%s
```
]]),
      path,
      table.concat(diagnostic_lines, '\n')
    )
  end,
}
