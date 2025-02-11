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

## Example
### User
Build a Google Search CLI tool in Rust.

### Assistant
Sure! Before build a Google Search CLI tool in Rust I will research the APIs that I will need to use.

- @web tool call 1: { "query": "How to parse cli arguments in rust?" }
- @web tool call 2: { "query": "How to use the Google search api (using rust)?" }
- @web tool call 3: { "query": "How to send a request in rust?" }
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
    if not params then
      local error = 'Tool (web): Missing parameter'
      vim.notify(error, vim.log.levels.ERROR)
      return callback('Error: ' .. error)
    end
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

    local request_body = vim.json.encode({
      model = 'sonar',
      messages = {
        {
          role = 'system',
          content = [[
ALWAYS SEARCH ON THE WEB FOR AN ANSWER!

STRICTLY FOLLOW THE STRUCTURE FROM THE FOLLOWING EXAMPLE!

<example>
<user>
How can I send a request in python?
</user>
<assistant>
You have several options
- Use the `requests` library
- Use `urllib` if you don't want to use any external libraries

```python
# Example: requests (https://docs.python-requests.org/en/v2.0.0/user/quickstart)
import requests

# Different HTTP methods
r = requests.get('https://api.example.com/items')
r = requests.post('https://api.example.com/items', data={'key': 'value'})
r = requests.put('https://api.example.com/items/1')
r = requests.delete('https://api.example.com/items/1')
r = requests.head('https://api.example.com/items')
r = requests.options('https://api.example.com/items')

# URL parameters
params = {'key1': 'value1', 'key2': 'value2'}
r = requests.get('https://api.example.com/items', params=params)

# Custom headers
headers = {'content-type': 'application/json'}
r = requests.post(url, headers=headers)

# POST data
# Form encoded
data = {'key1': 'value1', 'key2': 'value2'}
r = requests.post(url, data=data)

# JSON
import json
payload = {'key': 'value'}
r = requests.post(url, data=json.dumps(payload))

# File upload
files = {'file': open('report.xls', 'rb')}
r = requests.post(url, files=files)

# Cookies
cookies = {'session_id': '123'}
r = requests.get(url, cookies=cookies)

# Response handling
r.status_code      # HTTP status code
r.text             # Response content as unicode
r.content          # Response content as bytes
r.json()           # Response parsed as JSON
r.headers          # Response headers
r.cookies          # Response cookies
r.history          # Response redirection history
r.raise_for_status()  # Raise exception for bad HTTP status codes

# Timeouts and error handling
try:
    r = requests.get(url, timeout=0.001)
except requests.exceptions.RequestException as e:
    print(f"Request failed: {e}")
```

```python
# Example: urllib (https://docs.python.org/3/library/urllib.html)
import json
import urllib.request

body = {"con1":40, "con2":20, "con3":99, "con4":40, "password":"1234"}
req = urllib.request.Request('http://httpbin.org/post', data=json.dumps(newConditions).encode('utf8'), headers={'content-type': 'application/json'})
res = urllib.request.urlopen(req)
print(res.read().decode('utf8'))
```
</assistant>
</example>
]],
        },
        {
          role = 'user',
          content = [[
As sources prioritize (In this order!)
1. Official API Documentations (https://docs.python.org, https://doc.rust-lang.org, https://neovim.io/doc/, etc.)
2. Forums like Stackoverflow & Reddit
3. Blogposts describing the specific problems

- Focus on facts and SHORT code examples!
- AVOID headers and unnecessary descriptions between examples
- Be extremly consise!
]]
            .. '<user>'
            .. params.query
            .. '</user>',
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

        local success, response = pcall(
          vim.json.decode,
          obj.stdout,
          { luanil = { object = true, array = true } }
        )

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
          citation_text = 'Citations:\n'
          for i, citation in ipairs(citations) do
            citation_text = citation_text
              .. string.format('[%d] %s\n', i, citation)
          end
        end

        callback(citation_text .. '\n\n' .. search_result)
      end)
    )
  end,
}

return tool
