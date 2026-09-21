--[[ Weather - real-world weather for a place you pick.

  Worth being straight about: this is REAL weather, not Minecraft weather. A
  computer cannot see whether it is raining in your world - that needs a mod
  peripheral. What it can do is fetch a forecast over HTTP, so that is what
  this does.

  wttr.in is used because its format= parameter returns a single plain line
  rather than a page that would need rendering.
]]

local use = ...
local ui = use("system/ui")
local theme = use("system/theme")

local app = {}

-- location | temp | feels | humidity | wind | condition
local FORMAT = "%l|%t|%f|%h|%w|%C"
local KEY = "slate.weather.place"

local function savedPlace()
  local ok, value = pcall(settings.get, KEY)
  if ok and type(value) == "string" and value ~= "" then return value end
  return nil
end

local function savePlace(place)
  pcall(function()
    settings.set(KEY, place)
    settings.save()
  end)
end

local function fetch(place)
  if not http then return nil, "HTTP is disabled" end
  local url = "https://wttr.in/" .. textutils.urlEncode(place)
    .. "?m&format=" .. textutils.urlEncode(FORMAT)
  local response, err = http.get(url)
  if not response then return nil, tostring(err) end
  local body = (response.readAll() or ""):gsub("%s+$", "")
  response.close()

  local fields = {}
  for piece in (body .. "|"):gmatch("([^|]*)|") do fields[#fields + 1] = piece end
  if #fields < 6 then return nil, "Unexpected reply: " .. body:sub(1, 40) end

  return {
    place = fields[1], temp = fields[2], feels = fields[3],
    humidity = fields[4], wind = fields[5], condition = fields[6],
  }
end

function app.run(ctx)
  local place = savedPlace()
  local data, problem = nil, nil
  local state = place and "loading" or "ask"

  local function ask()
    local width, height = term.getSize()
    term.setBackgroundColour(theme.colour.window)
    term.clear()
    ui.row(term, 1, 1, width, " Weather", theme.colour.accentText, theme.colour.accent)
    ui.text(term, 2, 3, "Which place?", theme.colour.windowText, theme.colour.window)
    ui.text(term, 2, 4, "A town, city or postcode.", theme.colour.mutedText, theme.colour.window)
    ui.fill(term, 2, 6, width - 3, 1, colours.white)
    term.setCursorPos(2, 6)
    term.setBackgroundColour(colours.white)
    term.setTextColour(colours.black)
    local typed = read()
    if typed and typed ~= "" then
      place = typed
      savePlace(place)
      state = "loading"
    end
  end

  local function load()
    state = "loading"
    data, problem = fetch(place)
    state = data and "shown" or "failed"
  end

  local function draw()
    local width, height = term.getSize()
    term.setBackgroundColour(theme.colour.window)
    term.clear()
    ui.row(term, 1, 1, width, " Weather", theme.colour.accentText, theme.colour.accent)

    if state == "loading" then
      ui.centre(term, 4, "Checking the sky...", theme.colour.windowText, theme.colour.window, 1, width)

    elseif state == "failed" then
      ui.text(term, 2, 3, "Could not fetch", theme.colour.danger, theme.colour.window)
      local y = 5
      for _, line in ipairs(ui.wrap(problem or "", width - 2)) do
        if y > height - 2 then break end
        ui.text(term, 2, y, line, theme.colour.mutedText, theme.colour.window)
        y = y + 1
      end

    elseif data then
      ui.centre(term, 3, ui.clip(data.place, width - 2),
        theme.colour.windowText, theme.colour.window, 1, width)
      ui.centre(term, 5, data.temp, theme.colour.accent, theme.colour.window, 1, width)
      ui.centre(term, 6, ui.clip(data.condition, width - 2),
        theme.colour.mutedText, theme.colour.window, 1, width)

      ui.rule(term, 2, 8, width - 2, theme.colour.muted, theme.colour.window)
      local rows = {
        { "feels like", data.feels },
        { "humidity", data.humidity },
        { "wind", data.wind },
      }
      local y = 9
      for _, row in ipairs(rows) do
        if y > height - 1 then break end
        ui.text(term, 2, y, ui.pad(row[1], 12), theme.colour.mutedText, theme.colour.window)
        ui.text(term, 14, y, ui.clip(row[2], width - 15),
          theme.colour.windowText, theme.colour.window)
        y = y + 1
      end
    end

    ui.row(term, 1, height, width, " [R] refresh   [P] change place",
      theme.colour.mutedText, theme.colour.muted)
  end

  if state == "ask" then ask() end
  if state == "loading" then draw(); load() end
  draw()

  while true do
    local event, key = os.pullEvent()
    if event == "key" then
      if key == keys.r and place then draw(); load()
      elseif key == keys.p then ask(); if state == "loading" then draw(); load() end
      end
      draw()
    elseif event == "term_resize" then
      draw()
    end
  end
end

return app
