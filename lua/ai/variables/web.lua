---@class CachedWebUrl
---@field url string
---@field lastUsed string

---@param url string
local function update_web_urls_cache(url)
  local config = require('ai.config').get()
  local web_urls_path = config.data_dir .. '/web-urls.json'
  local web_urls = {}

  -- Load existing URLs
  local file = io.open(web_urls_path, 'r')
  if file then
    local content = file:read('*all')
    file:close()
    web_urls = vim.fn.json_decode(content) or {}
  end

  -- Add the new URL with the current date
  table.insert(
    web_urls,
    { url = url, lastUsed = os.date('!%Y-%m-%dT%H:%M:%SZ') }
  )

  -- Remove duplicate URLs, keeping only the latest date
  table.sort(web_urls, function(a, b)
    return a.lastUsed > b.lastUsed
  end)

  local unique_web_urls = {}
  local seen_urls = {}

  for _, entry in ipairs(web_urls) do
    if not seen_urls[entry.url] then
      table.insert(unique_web_urls, entry)
      seen_urls[entry.url] = true
    end
  end

  -- Save the updated URLs back to the file
  web_urls = unique_web_urls
  local ok, err = pcall(function()
    local file_handle = io.open(web_urls_path, 'w')
    if file_handle ~= nil then
      file_handle:write(vim.fn.json_encode(web_urls))
      file_handle:close()
    end
  end)

  if not ok then
    vim.notify('Failed to save web URLs: ' .. err, vim.log.levels.ERROR)
  end
end

---@return CachedWebUrl[]
local function load_web_urls_from_cache()
  local config = require('ai.config').get()
  local web_urls_path = config.data_dir .. '/web-urls.json'
  local web_urls = {}

  -- Load existing URLs
  local file = io.open(web_urls_path, 'r')
  if file then
    local content = file:read('*all')
    file:close()
    web_urls = vim.fn.json_decode(content) or {}
  end
  return web_urls
end

--- @type VariableDefinition
return {
  name = 'web',
  min_params = 1,
  max_params = 1,
  resolve = function(_ctx, params)
    -- Ensure params is provided and has at least one element
    if not params or #params < 1 then
      error("The '#web' variable requires a URL as the first parameter.")
    end

    -- Get the URL from params
    local url = params[1]

    -- Use curl to fetch the HTML content
    local curlResult = vim
      .system({
        'curl',
        '-s',
        url,
      }, { text = true })
      :wait()

    if curlResult.code ~= 0 then
      error('Failed to fetch URL: ' .. url)
    end

    -- Use pandoc to convert HTML to plain text
    local pandocResult = vim
      .system({
        'pandoc',
        '-f',
        'html',
        '-t',
        'plain',
        '--wrap=none',
      }, { stdin = curlResult.stdout })
      :wait()

    if pandocResult.code ~= 0 then
      error('Failed to convert HTML to text for URL: ' .. url)
    end

    update_web_urls_cache(url)

    return string.format(
      vim.trim([[
Variable: #web - Contains the content of the specified URL
URL: %s
```
%s
```
      ]]),
      url,
      pandocResult.stdout
    )
  end,
  cmp_items = function(cmp_ctx, callback)
    --- @type lsp.CompletionItem[]
    local items = {}

    local web_urls = load_web_urls_from_cache()

    -- Sort URLs by recency
    table.sort(web_urls, function(a, b)
      return a.lastUsed > b.lastUsed
    end)

    for _, entry in ipairs(web_urls) do
      table.insert(items, {
        label = '#web:`' .. entry.url .. '`',
        kind = require('blink.cmp.types').CompletionItemKind.Variable,
        documentation = 'URL: ' .. entry.url,
      })
    end

    callback(items)
  end,
}
