local M = {}

local Yaml = require('ai.utils.yaml')
local Tools = require('ai.tools')

function M.render(bufnr, messages)
  local lines = {}
  for _, msg in ipairs(messages) do
    table.insert(lines, '## ' .. msg.role:gsub('^%l', string.upper) .. ' ##')
    for _, line in ipairs(vim.split(msg.content, '\n')) do
      table.insert(lines, line)
    end
    if msg.tool_calls then
      for _, tool_call in ipairs(msg.tool_calls) do
        table.insert(lines, '')
        table.insert(lines, '```yaml')
        table.insert(lines, '# tool:call')
        local tool_call_copy = vim.tbl_deep_extend('force', tool_call, {})
        tool_call_copy.result = nil
        tool_call_copy.content = nil
        local tool_call_yaml = Yaml.encode(tool_call_copy)
        for _, line in ipairs(vim.split(tool_call_yaml, '\n')) do
          table.insert(lines, line)
        end
        if tool_call.result then
          table.insert(lines, '# tool:call:result')
          local result_yaml = Yaml.encode(tool_call.result)
          for _, line in ipairs(vim.split(result_yaml, '\n')) do
            table.insert(lines, line)
          end
        end
        table.insert(lines, '```')
      end
    end
    table.insert(lines, '')
  end

  -- Add loading indicator if needed
  local last_message = messages[#messages]
  if
    vim.b[bufnr].running_job
    and not (last_message.role == 'assistant' and #last_message.content > 0)
  then
    table.insert(lines, '## Assistant ##')
    table.insert(lines, '⏳')
    table.insert(lines, '')
  end

  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)

  -- Move cursor to the end
  local line_count = vim.api.nvim_buf_line_count(bufnr)
  vim.api.nvim_win_set_cursor(0, { line_count - 1, 0 })
end

function M.parse(bufnr)
  local messages = {}
  local parser = vim.treesitter.get_parser(bufnr, 'markdown')
  local tree = parser:parse()[1]
  local root = tree:root()

  local section_query = vim.treesitter.query.parse(
    'markdown',
    [[
      (section
        (atx_heading
          (atx_h2_marker)
          (inline) @role)
        ((_) @content)*)
    ]]
  )

  local tool_call_query = vim.treesitter.query.parse(
    'markdown',
    [[
      (fenced_code_block
        (code_fence_content) @code_content
        (#match? @code_content "# tool:call")
        )
    ]]
  )

  local tools = {}

  local get_text = function(captures, source, delim)
    return vim
      .iter(captures)
      :map(function(c)
        return vim.treesitter.get_node_text(c, source)
      end)
      :filter(function(v)
        return v
      end)
      :join(delim or '')
  end

  for _, matches, _ in
    section_query:iter_matches(root, bufnr, 0, -1, { all = true })
  do
    local role_matches = matches[1]
    local content_matches = matches[2] or {}

    local role = get_text(role_matches, bufnr)
    role = role:gsub('^%s*(.-)[#%s]*$', '%1'):lower()

    -- Parse tool calls
    local tool_calls = {}
    content_matches = vim.iter(content_matches):filter(function(content_match)
      local content_match_text =
        vim.treesitter.get_node_text(content_match, bufnr)
      local content_match_root = vim.treesitter
        .get_string_parser(content_match_text, 'markdown')
        :parse()[1]
        :root()
      local _, match, _ =
        tool_call_query:iter_matches(content_match_root, content_match_text)()
      if match then
        local tool_call_match_text =
          vim.treesitter.get_node_text(match[1], content_match_text)
        local tool_call
        local lines = vim.split(tool_call_match_text, '\n')
        local yaml_content = {}
        local collecting_yaml = false
        for _, line in ipairs(lines) do
          if line:match('# tool:call%s*$') then
            collecting_yaml = true
            yaml_content = {}
          elseif line:match('# tool:call:result%s*$') and tool_call then
            collecting_yaml = true
            yaml_content = {}
          elseif collecting_yaml and #line > 0 and not line:match('^#') then
            table.insert(yaml_content, line)
          elseif collecting_yaml and #yaml_content > 0 then
            local yaml_str = table.concat(yaml_content, '\n')
            local ok, parsed = pcall(Yaml.decode, yaml_str)
            if ok then
              if not tool_call then
                tool_call = parsed
                table.insert(tool_calls, tool_call)
              else
                tool_call.result = parsed
              end
            else
              vim.notify(
                'Failed to parse tool call result ('
                  .. parsed
                  .. '):\n'
                  .. yaml_str,
                vim.log.levels.ERROR
              )
            end
            collecting_yaml = false
            yaml_content = {}
          end
        end
      end
      return not match
    end)

    local content = get_text(content_matches, bufnr, '\n\n')

    -- Find tool uses
    for _, tool in ipairs(Tools.all) do
      if content:match('@' .. tool.definition.name) then
        if
          not vim.iter(tools):find(function(existing_tool)
            return existing_tool.definition.name == tool.definition.name
          end)
        then
          table.insert(tools, tool)
        end
      end
    end

    table.insert(messages, {
      role = role,
      content = content,
      tool_calls = tool_calls,
    })
  end

  -- vim.notify('Messages: ' .. vim.inspect(messages), vim.log.levels.DEBUG)
  -- vim.notify('Tools: ' .. vim.inspect(tools), vim.log.levels.DEBUG)
  return { messages = messages, tools = tools }
end

return M
