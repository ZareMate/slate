--[[ Furnace - a text web browser.

  CC can fetch a URL and nothing else: no JavaScript, no images, no CSS. So
  Furnace does the only honest thing - strips the markup and shows the text,
  with links numbered so they can be followed by keyboard.

  Search uses DuckDuckGo's Instant Answer API, which returns JSON rather than
  a page that needs rendering. That is the difference between a search that
  works on a Minecraft computer and one that does not.
]]

local use = ...
local ui = use("system/ui")
local theme = use("system/theme")

local app = {}

local SEARCH = "https://api.duckduckgo.com/?format=json&no_html=1&skip_disambig=1&q="
local MAX_BYTES = 120 * 1024      -- a page bigger than this is not readable anyway

local HOME = {
  { title = "CC: Tweaked docs", url = "https://tweaked.cc/" },
  { title = "Lua 5.2 manual", url = "https://www.lua.org/manual/5.2/" },
  { title = "Minecraft Wiki", url = "https://minecraft.wiki/" },
}

--------------------------------------------------------------------------
-- HTML to text
--------------------------------------------------------------------------

local ENTITIES = {
  amp = "&", lt = "<", gt = ">", quot = '"', apos = "'", nbsp = " ",
  mdash = "-", ndash = "-", hellip = "...", rsquo = "'", lsquo = "'",
  ldquo = '"', rdquo = '"',
}

local function decode(text)
  text = text:gsub("&#(%d+);", function(code)
    local number = tonumber(code)
    if number and number < 127 then return string.char(number) end
    return ""
  end)
  return (text:gsub("&(%a+);", function(name)
    return ENTITIES[name:lower()] or ""
  end))
end

-- Returns plain text plus the links found, in document order.
local function htmlToText(html)
  local links = {}

  -- Anything inside these is markup or code, never prose.
  html = html:gsub("<!%-%-.-%-%->", " ")
  html = html:gsub("<[sS][cC][rR][iI][pP][tT].-</[sS][cC][rR][iI][pP][tT]>", " ")
  html = html:gsub("<[sS][tT][yY][lL][eE].-</[sS][tT][yY][lL][eE]>", " ")
  html = html:gsub("<[hH][eE][aA][dD].-</[hH][eE][aA][dD]>", " ")

  -- Turn anchors into "text [n]" and remember where n goes.
  html = html:gsub('<[aA]%s+[^>]-[hH][rR][eE][fF]%s*=%s*"([^"]*)"[^>]*>(.-)</[aA]>',
    function(href, label)
      label = label:gsub("<[^>]->", ""):gsub("%s+", " "):gsub("^ ", ""):gsub(" $", "")
      if label == "" or href == "" or href:sub(1, 1) == "#" then return label end
      links[#links + 1] = { label = decode(label), url = href }
      return decode(label) .. " [" .. #links .. "]"
    end)

  html = html:gsub("<[bB][rR]%s*/?>", "\n")
  html = html:gsub("</[pP]>", "\n\n")
  html = html:gsub("</[hH][1-6]>", "\n\n")
  html = html:gsub("</[lL][iI]>", "\n")
  html = html:gsub("<[^>]->", "")

  html = decode(html)
  html = html:gsub("\r", "")
  html = html:gsub("[ \t]+", " ")
  html = html:gsub(" ?\n ?", "\n")
  html = html:gsub("\n\n\n+", "\n\n")
  html = html:gsub("^%s+", "")

  return html, links
end

local function absolute(base, href)
  if href:match("^https?://") then return href end
  local scheme, host = base:match("^(https?://)([^/]+)")
  if not scheme then return href end
  if href:sub(1, 2) == "//" then return "https:" .. href end
  if href:sub(1, 1) == "/" then return scheme .. host .. href end
  local dir = base:match("^(.*/)") or (scheme .. host .. "/")
  return dir .. href
end

--------------------------------------------------------------------------

function app.run(ctx, startUrl)
  local width, height = term.getSize()
  local view = "home"               -- home | loading | page | error
  local url, title = nil, ""
  local lines, links = {}, {}
  local scroll = 0
  local problem = nil
  local history = {}
  local typed = {}

  local function render(text)
    lines = {}
    for _, line in ipairs(ui.wrap(text, width - 2)) do
      lines[#lines + 1] = line
    end
    scroll = 0
  end

  local function open(target)
    if not http then
      view, problem = "error", "HTTP is disabled in computercraft-server.toml"
      return
    end
    view = "loading"
    url = target
    ctx.setTitle("Furnace")

    local response, err = http.get(target)
    if not response then
      view, problem = "error", tostring(err)
      return
    end
    local body = response.readAll() or ""
    response.close()
    if #body > MAX_BYTES then body = body:sub(1, MAX_BYTES) end

    title = body:match("<[tT][iI][tT][lL][eE]>(.-)</[tT][iI][tT][lL][eE]>") or target
    title = decode(title:gsub("%s+", " "))

    local text
    text, links = htmlToText(body)
    if text:gsub("%s", "") == "" then
      view, problem = "error", "Nothing readable on that page"
      return
    end
    render(text)
    history[#history + 1] = target
    ctx.setTitle(ui.clip(title, 16))
    view = "page"
  end

  local function search(query)
    if not http then
      view, problem = "error", "HTTP is disabled"
      return
    end
    view = "loading"
    local response, err = http.get(SEARCH .. textutils.urlEncode(query))
    if not response then
      view, problem = "error", tostring(err)
      return
    end
    local body = response.readAll()
    response.close()

    local data = textutils.unserialiseJSON(body)
    if type(data) ~= "table" then
      view, problem = "error", "Search returned nothing usable"
      return
    end

    links = {}
    local out = {}
    if data.Heading and data.Heading ~= "" then out[#out + 1] = data.Heading end
    if data.AbstractText and data.AbstractText ~= "" then
      out[#out + 1] = ""
      out[#out + 1] = data.AbstractText
      if data.AbstractURL and data.AbstractURL ~= "" then
        links[#links + 1] = { label = data.Heading or query, url = data.AbstractURL }
        out[#out + 1] = "Source [" .. #links .. "]"
      end
    end

    local related = data.RelatedTopics or {}
    if #related > 0 then
      out[#out + 1] = ""
      out[#out + 1] = "Related"
    end
    for _, topic in ipairs(related) do
      if type(topic) == "table" and topic.Text and topic.FirstURL then
        links[#links + 1] = { label = topic.Text, url = topic.FirstURL }
        out[#out + 1] = ui.glyph.bullet .. " " .. topic.Text .. " [" .. #links .. "]"
      end
    end

    if #out == 0 then
      out[1] = "No instant answer for \"" .. query .. "\"."
      out[2] = ""
      out[3] = "DuckDuckGo's answer API only covers topics it has"
      out[4] = "a summary for. Try a broader term, or type a URL."
    end

    title = "Search: " .. query
    render(table.concat(out, "\n"))
    ctx.setTitle("Search")
    view = "page"
  end

  local function drawHome()
    term.setBackgroundColour(theme.colour.window)
    term.clear()
    ui.row(term, 1, 1, width, " " .. ui.spaced("Furnace"),
      theme.colour.accentText, theme.colour.accent)

    ui.centre(term, 3, "Search the web, or type a URL",
      theme.colour.mutedText, theme.colour.window, 1, width)

    ui.fill(term, 3, 5, width - 4, 1, colours.white)
    ui.text(term, 4, 5, ui.glyph.right .. " type to begin", theme.colour.mutedText, colours.white)

    ui.text(term, 3, 7, "Bookmarks", theme.colour.mutedText, theme.colour.window)
    ui.rule(term, 3, 8, width - 4, theme.colour.muted, theme.colour.window)
    for position, entry in ipairs(HOME) do
      ui.text(term, 3, 8 + position,
        position .. ". " .. ui.clip(entry.title, width - 7),
        theme.colour.windowText, theme.colour.window)
    end

    ui.row(term, 1, height, width, " [/] search   [1-3] bookmark",
      theme.colour.mutedText, theme.colour.muted)
  end

  local function drawPage()
    term.setBackgroundColour(theme.colour.window)
    term.clear()
    ui.row(term, 1, 1, width, " " .. ui.clip(title, width - 2),
      theme.colour.accentText, theme.colour.accent)

    local body = height - 2
    for row = 1, body do
      local line = lines[scroll + row]
      if line then
        ui.text(term, 2, row + 1, line, theme.colour.windowText, theme.colour.window)
      end
    end
    ui.scrollbar(term, width, 2, body, #lines, scroll, theme.colour.muted, theme.colour.accent)

    ui.row(term, 1, height, width,
      " [G]o  [F]ollow  [B]ack  " .. #links .. " links",
      theme.colour.mutedText, theme.colour.muted)
  end

  local function draw()
    if view == "home" then drawHome()
    elseif view == "loading" then
      term.setBackgroundColour(theme.colour.window)
      term.clear()
      ui.row(term, 1, 1, width, " " .. ui.spaced("Furnace"),
        theme.colour.accentText, theme.colour.accent)
      ui.centre(term, math.floor(height / 2), "Loading...",
        theme.colour.windowText, theme.colour.window, 1, width)
    elseif view == "error" then
      term.setBackgroundColour(theme.colour.window)
      term.clear()
      ui.row(term, 1, 1, width, " Could not load", colours.white, theme.colour.danger)
      local y = 3
      for _, line in ipairs(ui.wrap(problem or "", width - 2)) do
        if y > height - 2 then break end
        ui.text(term, 2, y, line, theme.colour.mutedText, theme.colour.window)
        y = y + 1
      end
      ui.row(term, 1, height, width, " [G]o   [B]ack",
        theme.colour.mutedText, theme.colour.muted)
    else drawPage() end
  end

  local function ask(label)
    ui.fill(term, 1, height - 1, width, 1, colours.white)
    ui.text(term, 1, height - 1, label, colours.black, colours.white)
    term.setCursorPos(#label + 1, height - 1)
    term.setBackgroundColour(colours.white)
    term.setTextColour(colours.black)
    return read(nil, typed)
  end

  local function go()
    local entry = ask(" url or search: ")
    if not entry or entry == "" then return end
    typed[#typed + 1] = entry
    if entry:match("^https?://") then open(entry)
    elseif entry:match("^[%w%-%.]+%.%a%a+") then open("https://" .. entry)
    else search(entry) end
  end

  if startUrl then open(startUrl) end
  draw()

  while true do
    local event, key = os.pullEvent()

    if event == "key" then
      if view == "home" then
        if key == keys.slash or key == keys.g then go()
        elseif key >= keys.one and key <= keys.three then
          local pick = HOME[key - keys.one + 1]
          if pick then open(pick.url) end
        end

      elseif view == "page" or view == "error" then
        if key == keys.g then go()
        elseif key == keys.b then
          table.remove(history)
          local previous = history[#history]
          if previous then
            table.remove(history)
            open(previous)
          else
            view = "home"
          end
        elseif key == keys.f and #links > 0 then
          local pick = tonumber(ask(" follow link number: "))
          if pick and links[pick] then open(absolute(url or "", links[pick].url)) end
        elseif key == keys.down then scroll = math.min(math.max(0, #lines - (height - 2)), scroll + 1)
        elseif key == keys.up then scroll = math.max(0, scroll - 1)
        elseif key == keys.pageDown then
          scroll = math.min(math.max(0, #lines - (height - 2)), scroll + height - 3)
        elseif key == keys.pageUp then scroll = math.max(0, scroll - (height - 3))
        end
      end
      draw()

    elseif event == "mouse_scroll" then
      scroll = math.max(0, math.min(math.max(0, #lines - (height - 2)), scroll + key))
      draw()

    elseif event == "term_resize" then
      width, height = term.getSize()
      draw()
    end
  end
end

return app
