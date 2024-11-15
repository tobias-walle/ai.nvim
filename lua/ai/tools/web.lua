---@type RealToolDefinition
local tool = {
  definition = {
    name = 'web',
    description = vim.trim([[
Use this tool to search on the web.
You can provide a search term or question to look for and will get as a result a string providing a summary of the findings.
Perplexity will be used for the search.

Always search the web if you relying on current information, like:
- Documentation of libraries
- Facts and News

Try to formulate your queries generic enough to find common knowledge.
Avoid searching for a very specific combination.
For example let's take the task "Build a Google Search CLI tool in Rust". You could split the search into:
- How to parse cli arguments in rust
- Google Search API Documentation
    ]]),
    parameters = {
      type = 'object',
      required = { 'query' },
      properties = {
        query = {
          type = 'string',
          description = 'The search query or question to search on the web',
        },
      },
    },
  },
  execute = function(ctx, params, callback)
    if not params.query then
      local error = 'Tool (web): Missing query parameter'
      vim.notify(error, vim.log.levels.ERROR)
      return callback('Error: ' .. error)
    end

    local api_key = os.getenv('PERPLEXITY_API_KEY')
    if not api_key then
      local error = 'Tool (web): Expected PERPLEXITY_API_KEY env variable'
      vim.notify(error, vim.log.levels.ERROR)
      return callback('Error: ' .. error)
    end

    local request_body = vim.fn.json_encode({
      model = 'llama-3.1-sonar-small-128k-online',
      messages = {
        {
          role = 'system',
          content = 'ALWAYS SEARCH ON THE WEB FOR AN ANSWER! Cite the most important search results in your summary with reference to the source. Just focus on your sources and do not make up anything.',
        },
        {
          role = 'user',
          content = params.query,
        },
      },
    })

    vim.system(
      {
        'curl',
        '--silent',
        '-X',
        'POST',
        '--fail-with-body',
        'https://api.perplexity.ai/chat/completions',
        '-H',
        'Content-Type: application/json',
        '-H',
        'Authorization: Bearer ' .. api_key,
        '-d',
        request_body,
      },
      {},
      vim.schedule_wrap(function(obj)
        if obj.code ~= 0 then
          local error = 'Tool (web): Curl request failed: '
            .. (obj.stderr or 'Unknown error')
          vim.notify(error, vim.log.levels.ERROR)
          return callback(error)
        end

        local success, response = pcall(vim.json.decode, obj.stdout)

        if not success then
          local error = string.format(
            'Tool (web): Failed to parse perplexity json response (%s):\n%s',
            response,
            obj.stdout
          )
          vim.notify(error, vim.log.levels.ERROR)
          return callback(error)
        end

        local search_result = response.choices
          and response.choices[1]
          and response.choices[1].message
          and response.choices[1].message.content

        local citations = response.citations or {}
        local citation_text = ''
        if #citations > 0 then
          citation_text = '\n\nCitations:\n'
          for i, citation in ipairs(citations) do
            citation_text = citation_text
              .. string.format('[%d] %s\n', i, citation)
          end
        end

        callback(search_result .. citation_text)
      end)
    )
  end,
}
return tool
