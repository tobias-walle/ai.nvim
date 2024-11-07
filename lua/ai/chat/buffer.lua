local M = {}

local Tools = require('ai.tools')
local Variables = require('ai.variables')

local Yaml = require('ai.utils.yaml')

function M.create()
  -- Create a new buffer
  local bufnr = vim.api.nvim_create_buf(false, true)

  -- Set buffer options
  vim.api.nvim_buf_set_option(bufnr, 'buftype', 'nofile')
  vim.api.nvim_buf_set_option(bufnr, 'filetype', 'markdown')
  vim.api.nvim_buf_set_option(bufnr, 'modifiable', true)

  -- Open buffer in a vertical split
  vim.cmd('vsplit')

  -- Highlight
  vim.api.nvim_win_set_buf(0, bufnr)
  -- Configure tools highlight
  for _, tool in ipairs(Tools.all) do
    vim.cmd.syntax('match Special "@' .. tool.definition.name .. '"')
  end
  -- Configure variables highlight
  for _, variable in ipairs(Variables.all) do
    vim.cmd.syntax('match Identifier "#' .. variable.name .. '"')
  end

  return bufnr
end

function M.render(bufnr, messages)
  local some_tool_call_is_loading = false
  local lines = {}
  for _, msg in ipairs(messages) do
    local content = vim.trim(msg.content)
    local has_tool_calls = msg.tool_calls and #msg.tool_calls > 0
    table.insert(lines, '## ' .. msg.role:gsub('^%l', string.upper) .. ' ##')
    if #content > 0 then
      for _, line in ipairs(vim.split(content, '\n')) do
        table.insert(lines, line)
      end
    end
    if has_tool_calls then
      for _, tool_call in ipairs(msg.tool_calls) do
        table.insert(lines, '')
        table.insert(lines, '`````yaml')
        table.insert(lines, '# tool:call')
        local tool_call_copy = vim.deepcopy(tool_call)
        tool_call_copy.result = nil
        tool_call_copy.content = nil
        tool_call_copy.is_loading = nil
        local tool_call_yaml = Yaml.encode(tool_call_copy)
        for _, line in ipairs(vim.split(tool_call_yaml, '\n')) do
          table.insert(lines, line)
        end
        if tool_call.is_loading then
          some_tool_call_is_loading = true
          table.insert(lines, '⏳ ' .. #(tool_call.content or ''))
        end
        if tool_call.result then
          table.insert(lines, '# tool:call:result')
          local result_yaml = Yaml.encode(tool_call.result)
          for _, line in ipairs(vim.split(result_yaml, '\n')) do
            table.insert(lines, line)
          end
        end
        table.insert(lines, '`````')
      end
    end
    table.insert(lines, '')
  end

  -- Add loading indicator if needed
  if vim.b[bufnr].running_job and not some_tool_call_is_loading then
    table.insert(lines, '...')
    table.insert(lines, '')
  end

  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
end

---@class ParsedChatBuffer
---@field messages table[] The chat messages
---@field tools ToolDefinition[] The tools used in the chat
---@field variables VariableDefinition[] The variables used in the chat

---@param bufnr integer
---@return ParsedChatBuffer
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
  local variables = {}

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

        local lines = vim.split(tool_call_match_text, '\n')
        local yaml_content = {}
        local collecting_yaml = false
        local tool_call = nil

        local get_yaml_content = function()
          if #yaml_content == 0 then
            return nil
          end
          local yaml_str = table.concat(yaml_content, '\n')
          local ok, parsed = pcall(Yaml.decode, yaml_str)
          if ok then
            return parsed
          else
            vim.notify(
              'Failed to parse tool call yaml (' .. parsed .. '):\n' .. yaml_str,
              vim.log.levels.ERROR
            )
          end
          return nil
        end

        for _, line in ipairs(lines) do
          if line:match('^#') or line:match('^```') then
            local yaml_parsed = get_yaml_content()
            if yaml_parsed then
              if tool_call == nil then
                tool_call = yaml_parsed
                table.insert(tool_calls, tool_call)
              else
                tool_call.result = yaml_parsed
              end
              yaml_content = {}
            end
            if
              line:match('^# tool:call%s*$')
              or line:match('^# tool:call:result%s*$')
            then
              collecting_yaml = true
            end
          elseif collecting_yaml then
            table.insert(yaml_content, line)
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

    -- Find variable uses
    for _, variable in ipairs(Variables.all) do
      if content:match('#' .. variable.name) then
        if
          not vim.iter(variables):find(function(existing_variable)
            return existing_variable.name == variable.name
          end)
        then
          table.insert(variables, variable)
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
  -- vim.notify('Variables: ' .. vim.inspect(variables), vim.log.levels.DEBUG)
  return { messages = messages, tools = tools, variables = variables }
end

return M
