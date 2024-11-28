--- @type VariableDefinition
return {
  name = 'web',
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
        '--reference-links',
      })
      :wait()

    if pandocResult.code ~= 0 then
      error('Failed to convert HTML to text for URL: ' .. url)
    end

    return string.format(
      'Variable: #web - Contains the content of the specified URL.\nURL: %s\nContent:\n%s',
      url,
      pandocResult.stdout
    )
  end,
}
