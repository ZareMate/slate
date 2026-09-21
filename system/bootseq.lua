--[[ Boot sequence - the screen a reboot or shutdown actually shows.

  Takes over the real terminal after the kernel loop has ended, works through
  a list of stages for about 40 seconds, then calls os.reboot/os.shutdown for
  real. Each stage beeps if a speaker is attached.

  It runs on term.native() rather than in a window because by this point there
  are no windows: the desktop is gone and this is the whole machine.
]]

local use = ...
local ui = use("system/ui")
local theme = use("system/theme")
local sound = use("system/sound")

local bootseq = {}

-- Seconds per stage. Totals 7: long enough to read what it is doing, short
-- enough that restarting is not a chore.
local STAGES = {
  { "Closing windows",  1.5, 6 },
  { "Saving settings",  1.5, 10 },
  { "Flushing disk",    1.5, 13 },
  { "Unmounting /",     1.5, 16 },
  { "Powering down",    1.0, 19 },
}

local function total()
  local sum = 0
  for _, stage in ipairs(STAGES) do sum = sum + stage[2] end
  return sum
end

function bootseq.run(mode)
  local native = term.native()
  term.redirect(native)
  local width, height = native.getSize()
  local reboot = (mode == "reboot")
  local title = reboot and "Restarting Slate" or "Shutting down"

  local duration = total()
  local elapsed = 0
  local done = {}

  local function paint(stageName, fraction)
    native.setBackgroundColour(colours.black)
    native.setTextColour(colours.white)
    native.clear()
    native.setCursorBlink(false)

    ui.centre(native, 2, title, theme.colour.accent, colours.black, 1, width)

    -- Progress bar
    local barWidth = width - 6
    local filled = math.floor(barWidth * fraction + 0.5)
    ui.fill(native, 4, 4, barWidth, 1, colours.grey)
    if filled > 0 then ui.fill(native, 4, 4, filled, 1, theme.colour.accent) end

    local percent = math.floor(fraction * 100 + 0.5) .. "%"
    ui.centre(native, 5, percent .. "   " .. math.floor(elapsed) .. "s of " .. duration .. "s",
      colours.lightGrey, colours.black, 1, width)

    ui.centre(native, 7, stageName .. " ...", colours.white, colours.black, 1, width)

    -- Completed stages scroll upward under the bar.
    local first = math.max(1, #done - (height - 10))
    local y = 9
    for i = first, #done do
      if y > height - 1 then break end
      ui.text(native, 4, y, "ok  " .. done[i], colours.green, colours.black)
      y = y + 1
    end
  end

  for index, stage in ipairs(STAGES) do
    local name, seconds, pitch = stage[1], stage[2], stage[3]
    sound.note("bit", 1, pitch)

    local steps = math.max(1, math.floor(seconds * 4))  -- redraw 4x a second
    for step = 1, steps do
      paint(name, elapsed / duration)
      sleep(0.25)
      elapsed = elapsed + 0.25
    end
    done[#done + 1] = name
    if index == #STAGES then break end
  end

  paint(reboot and "Restarting" or "Goodbye", 1)

  -- A short rising flourish, then the real thing.
  for _, pitch in ipairs({ 12, 16, 19, 24 }) do
    sound.note("bit", 1, pitch)
    sleep(0.12)
  end

  native.setBackgroundColour(colours.black)
  native.clear()
  ui.centre(native, math.floor(height / 2), reboot and "Restarting..." or "It is now safe to",
    colours.white, colours.black, 1, width)
  if not reboot then
    ui.centre(native, math.floor(height / 2) + 1, "turn off this computer.",
      colours.white, colours.black, 1, width)
  end
  sleep(1.5)

  if reboot then os.reboot() else os.shutdown() end
end

return bootseq
