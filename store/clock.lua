--[[ Clock - big in-game time, with the real time underneath.

  A Slate store app. Drawn with a 3x5 block font because at 51x19 a clock you
  can read from across the room is the whole point.
]]

local use = ...
local ui = use("system/ui")
local theme = use("system/theme")

local app = {}

local DIGITS = {
  ["0"] = { "###", "# #", "# #", "# #", "###" },
  ["1"] = { "  #", "  #", "  #", "  #", "  #" },
  ["2"] = { "###", "  #", "###", "#  ", "###" },
  ["3"] = { "###", "  #", "###", "  #", "###" },
  ["4"] = { "# #", "# #", "###", "  #", "  #" },
  ["5"] = { "###", "#  ", "###", "  #", "###" },
  ["6"] = { "###", "#  ", "###", "# #", "###" },
  ["7"] = { "###", "  #", "  #", "  #", "  #" },
  ["8"] = { "###", "# #", "###", "# #", "###" },
  ["9"] = { "###", "# #", "###", "  #", "###" },
  [":"] = { "   ", " # ", "   ", " # ", "   " },
}

local function drawBig(x, y, text, colour, bg)
  for index = 1, #text do
    local glyph = DIGITS[text:sub(index, index)]
    if glyph then
      for row = 1, 5 do
        local line = glyph[row]
        for column = 1, 3 do
          if line:sub(column, column) == "#" then
            ui.fill(term, x + (index - 1) * 4 + column - 1, y + row - 1, 1, 1, colour)
          end
        end
      end
    end
  end
end

-- Minecraft days are 20 real minutes; a day counter is more use than a date.
local function inGame()
  return textutils.formatTime(os.time(), true)
end

local function realTime()
  local ok, value = pcall(os.date, "%H:%M")
  if ok and type(value) == "string" then return value end
  return nil
end

function app.run(ctx)
  local showReal = false

  local function draw()
    local width, height = term.getSize()
    term.setBackgroundColour(theme.colour.window)
    term.clear()

    local text = showReal and (realTime() or inGame()) or inGame()
    local big = #text * 4 - 1
    local x = math.max(1, math.floor((width - big) / 2) + 1)
    local y = math.max(2, math.floor((height - 5) / 2))

    drawBig(x, y, text, theme.colour.accent, theme.colour.window)

    ui.centre(term, y + 6, showReal and "real time" or "in-game time",
      theme.colour.mutedText, theme.colour.window, 1, width)

    local day = "Day " .. tostring(os.day())
    ui.centre(term, y + 7, day, theme.colour.windowText, theme.colour.window, 1, width)

    ui.row(term, 1, height, width, " [T] toggle real / in-game",
      theme.colour.mutedText, theme.colour.muted)
  end

  draw()
  local ticker = os.startTimer(1)

  while true do
    local event, key = os.pullEvent()
    if event == "timer" and key == ticker then
      ticker = os.startTimer(1)
      draw()
    elseif event == "key" then
      if key == keys.t then showReal = not showReal end
      draw()
    elseif event == "term_resize" then
      draw()
    end
  end
end

return app
