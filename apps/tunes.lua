--[[ Tunes - a step sequencer for the speaker.

  Eight pitches down, sixteen steps across. Toggle cells, press play, and it
  loops. Needs a speaker; without one it says so instead of silently doing
  nothing, which is the confusing version.
]]

local use = ...
local ui = use("system/ui")
local theme = use("system/theme")
local sound = use("system/sound")

local app = {}

local ROWS, STEPS = 8, 16
-- A pentatonic-ish run, so random patterns still sound deliberate.
local PITCHES = { 21, 19, 17, 16, 14, 12, 9, 7 }
local ROW_COLOUR = {
  colours.red, colours.orange, colours.yellow, colours.lime,
  colours.green, colours.cyan, colours.lightBlue, colours.purple,
}

function app.run(ctx)
  if not sound.available() then
    local width, height = term.getSize()
    term.setBackgroundColour(theme.colour.window)
    term.clear()
    ui.row(term, 1, 1, width, " No speaker", colours.white, theme.colour.danger)
    ui.text(term, 2, 3, "Tunes plays through a speaker.", theme.colour.windowText, theme.colour.window)
    ui.text(term, 2, 5, "Attach one to this computer and", theme.colour.mutedText, theme.colour.window)
    ui.text(term, 2, 6, "open Tunes again.", theme.colour.mutedText, theme.colour.window)
    ui.row(term, 1, height, width, " Any key to close", theme.colour.mutedText, theme.colour.muted)
    os.pullEvent("key")
    return
  end

  local grid = {}
  for row = 1, ROWS do
    grid[row] = {}
    for step = 1, STEPS do grid[row][step] = false end
  end

  local playing = false
  local step = 0
  local tempo = 0.18
  local ticker = nil
  local instrument = 1
  local INSTRUMENTS = { "bit", "harp", "bass", "pling", "banjo" }

  local function draw()
    local width, height = term.getSize()
    local ox = math.max(2, math.floor((width - STEPS * 2) / 2) + 1)
    local oy = 3

    term.setBackgroundColour(theme.colour.window)
    term.clear()
    ui.row(term, 1, 1, width, " Tunes  " .. (playing and "playing" or "stopped")
      .. "  " .. INSTRUMENTS[instrument],
      theme.colour.accentText, theme.colour.accent)

    for row = 1, ROWS do
      for column = 1, STEPS do
        local on = grid[row][column]
        local here = (playing and column == step)
        local cell = on and ROW_COLOUR[row]
          or (here and theme.colour.muted or theme.colour.window)
        ui.fill(term, ox + (column - 1) * 2, oy + row - 1, 2, 1, cell)
        if not on and (column - 1) % 4 == 0 then
          ui.text(term, ox + (column - 1) * 2, oy + row - 1, ".",
            theme.colour.muted, cell)
        end
      end
    end

    ui.row(term, 1, height, width,
      " [Space] play  [C]lear  [I]nstrument  +/- tempo",
      theme.colour.mutedText, theme.colour.muted)
    return ox, oy
  end

  local ox, oy = draw()

  local function playStep()
    for row = 1, ROWS do
      if grid[row][step] then
        sound.note(INSTRUMENTS[instrument], 1, PITCHES[row])
      end
    end
  end

  while true do
    local event, a, x, y = os.pullEvent()

    if event == "timer" and a == ticker and playing then
      step = (step % STEPS) + 1
      playStep()
      ticker = os.startTimer(tempo)
      ox, oy = draw()

    elseif event == "mouse_click" then
      local column = math.floor((x - ox) / 2) + 1
      local row = y - oy + 1
      if row >= 1 and row <= ROWS and column >= 1 and column <= STEPS then
        grid[row][column] = not grid[row][column]
        if grid[row][column] then sound.note(INSTRUMENTS[instrument], 1, PITCHES[row]) end
      end
      ox, oy = draw()

    elseif event == "key" then
      if a == keys.space then
        playing = not playing
        if playing then
          step = 0
          ticker = os.startTimer(tempo)
        end
      elseif a == keys.c then
        for row = 1, ROWS do
          for column = 1, STEPS do grid[row][column] = false end
        end
      elseif a == keys.i then
        instrument = (instrument % #INSTRUMENTS) + 1
      elseif a == keys.equals or a == keys.numPadAdd then
        tempo = math.max(0.06, tempo - 0.02)
      elseif a == keys.minus or a == keys.numPadSubtract then
        tempo = math.min(0.6, tempo + 0.02)
      end
      ox, oy = draw()

    elseif event == "term_resize" then
      ox, oy = draw()
    end
  end
end

return app
