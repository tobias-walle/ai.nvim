local M = {}

---@param bufnr integer
---@param diagnostics vim.Diagnostic[]
---@return string
function M.render(bufnr, diagnostics)
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, true)
  return vim
    .iter(diagnostics)
    :map(function(item)
      local data = item.user_data.lsp
      local start_line = data and data.range.start.line or item.lnum
      local end_line = data and data.range['end'].line or item.lnum
      local code = lines[start_line] or ''
      local diag_lines = 'Line ' .. start_line
      if start_line ~= end_line then
        diag_lines = diag_lines .. '-' .. end_line
        code = code .. '\n...\n' .. lines[end_line]
      end
      return diag_lines .. '\n' .. code .. '\n^^ ' .. (data.message or '')
    end)
    :join('\n\n')
end

---@param bufnr integer
---@param line_start? integer
---@param line_end? integer
---@return string
function M.get_diagnostics(bufnr, line_start, line_end)
  local diagnostics = vim
    .iter(vim.diagnostic.get(bufnr))
    :filter(function(item)
      local data = item.user_data.lsp
      if not data then
        return false
      end

      -- Only consider range if defined
      local start_line = data and data.range.start.line or item.lnum
      local end_line = data and data.range['end'].line or item.lnum
      if line_start and line_end then
        if start_line < line_start or end_line > line_end then
          return false
        end
      end

      return true
    end)
    :totable()
  return M.render(bufnr, diagnostics)
end

--- Helper to uniquely identify a diagnostic
---@param diag vim.Diagnostic
---@return string
local function diagnostic_key(diag)
  return table.concat({
    tostring(diag.bufnr),
    tostring(diag.lnum),
    tostring(diag.col),
    tostring(diag.code),
    tostring(diag.message),
    tostring(diag.source),
  }, ':')
end

--- Get diagnostics that are present in `after` but not in `before`
---@param before vim.Diagnostic[]
---@param after vim.Diagnostic[]
---@return vim.Diagnostic[]
function M.get_new_diagnostics(before, after)
  local before_set = {}
  for _, diag in ipairs(before or {}) do
    before_set[diagnostic_key(diag)] = true
  end
  local new_diags = {}
  for _, diag in ipairs(after or {}) do
    if not before_set[diagnostic_key(diag)] then
      table.insert(new_diags, diag)
    end
  end
  return new_diags
end

return M
