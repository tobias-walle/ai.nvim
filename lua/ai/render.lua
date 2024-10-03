local M = {}

--- @param opts {text: string, buffer: integer, row: integer, col: integer, ns_id: integer}
function M.render_ghost_text(opts)
  -- Update ghost text
  vim.api.nvim_buf_clear_namespace(opts.buffer, opts.ns_id, 0, -1)
  local lines = vim.split(opts.text, '\n')
  vim.api.nvim_buf_set_extmark(
    opts.buffer,
    opts.ns_id,
    opts.row,
    opts.col,
    {
      virt_text = { { lines[1], 'comment' } },
      virt_lines = vim.tbl_map(function(line)
        return { { line, 'comment' } }
      end, vim.list_slice(lines, 2)),
      virt_text_pos = 'inline',
    }
  )
end

return M
