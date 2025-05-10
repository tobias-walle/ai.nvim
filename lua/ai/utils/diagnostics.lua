local M = {}

---@param bufnr integer
---@param line_start? integer
---@param line_end? integer
function M.get_diagnostics(bufnr, line_start, line_end)
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, true)
  return vim
    .iter(vim.diagnostic.get(bufnr))
    :map(function(item)
      local data = item.user_data.lsp
      if not data then
        return nil
      end

      -- Only consider range if defined
      local start_line = data.range.start.line
      local end_line = data.range['end'].line
      if line_start and line_end then
        if start_line + 1 < line_start or end_line + 1 > line_end then
          return nil
        end
      end

      local code = lines[start_line]
      local diag_lines = 'Line ' .. start_line
      if start_line ~= end_line then
        diag_lines = diag_lines .. '-' .. end_line
        code = code .. '\n...\n' .. lines[end_line]
      end
      return diag_lines
        .. '\n'
        .. code
        .. '\n^^ '
        .. data.code
        .. ' | '
        .. data.message
    end)
    :filter(function(item)
      return item ~= nil
    end)
    :join('\n\n')
end

return M
