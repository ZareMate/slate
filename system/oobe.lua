--[[ First-run setup.

  Runs once, before the desktop exists, on the real terminal. Five short
  steps: hello, name, accent, wallpaper, updates. Everything it sets is a
  thing you would otherwise have had to find in Settings, and it is skippable
  at any point with Esc.

  The "done" flag lives in CC settings, so reinstalling Slate does not make
  you do this again, and clearing slate.setup replays it.
]]

local use = ...
local ui = use("system/ui")
local theme = use("system/theme")
local sound = use("system/sound")
local update = use("system/update")

local oobe = {}

function oobe.needed()
  local ok, value = pcall(settings.get, "slate.setup")
  return not (ok and value == true)
end

local function markDone()
  pcall(function()
    settings.set("slate.setup", true)
    settings.save()
  end)
end

local function chrome(native, W, H, step, steps, title)
  native.setBackgroundColour(colours.black)
  native.clear()
  ui.centre(native, 2, ui.spaced("Slate"), theme.colour.accent, colours.black, 1, W)

  -- Step pips rather than a progress bar: less blocky, and it fits.
  local pips = ""
  for index = 1, steps do
    pips = pips .. (index == step and ui.glyph.bullet or "-") .. " "
  end
  ui.centre(native, 3, pips:gsub(" $", ""), theme.colour.muted, colours.black, 1, W)

  ui.centre(native, 5, title, colours.white, colours.black, 1, W)
end

local function chooser(native, W, y, options, index, label)
  local total = 0
  for _, option in ipairs(options) do total = total + #option.name + 3 end
  local x = math.max(2, math.floor((W - total) / 2) + 1)

  for position, option in ipairs(options) do
    local on = (position == index)
    ui.fill(native, x, y, 2, 1, option.colour)
    ui.text(native, x + 2, y, " " .. option.name .. " ",
      on and colours.black or colours.lightGrey,
      on and colours.white or colours.black)
    x = x + #option.name + 5
  end
  ui.centre(native, y + 2, label, theme.colour.muted, colours.black, 1, W)
end

-- Returns true when setup finished, false when it was skipped.
function oobe.run()
  local native = term.native()
  term.redirect(native)
  local W, H = native.getSize()
  local STEPS = 5
  local step = 1
  local accent, wallpaper = theme.accent, theme.wallpaper
  local wantUpdates = true
  local middle = math.floor(H / 2)

  sound.note("bit", 1, 12)

  while true do
    if step == 1 then
      chrome(native, W, H, 1, STEPS, "")
      ui.centre(native, middle - 1, "Hello.", colours.white, colours.black, 1, W)
      ui.centre(native, middle + 1, "This is Slate, a desktop for this computer.",
        theme.colour.muted, colours.black, 1, W)
      ui.centre(native, H - 2, "[Enter] to begin    [Esc] to skip",
        theme.colour.muted, colours.black, 1, W)

      local _, key = os.pullEvent("key")
      if key == keys.enter then step = 2; sound.note("bit", 1, 14)
      elseif key == keys.escape then break end

    elseif step == 2 then
      chrome(native, W, H, 2, STEPS, "What should this computer be called?")
      ui.centre(native, 7, "It shows on the network and in Messenger.",
        theme.colour.muted, colours.black, 1, W)
      local boxX = math.max(2, math.floor(W / 2) - 12)
      ui.fill(native, boxX, 9, 24, 1, colours.white)
      native.setCursorPos(boxX + 1, 9)
      native.setBackgroundColour(colours.white)
      native.setTextColour(colours.black)
      ui.centre(native, H - 2, "[Enter] to continue, blank to leave it",
        theme.colour.muted, colours.black, 1, W)

      local typed = read()
      if typed and typed ~= "" then os.setComputerLabel(typed) end
      step = 3
      sound.note("bit", 1, 15)

    elseif step == 3 then
      chrome(native, W, H, 3, STEPS, "Pick an accent colour")
      chooser(native, W, 8, theme.accents, accent, "left and right to choose")
      ui.centre(native, H - 2, "[Enter] to continue", theme.colour.muted, colours.black, 1, W)

      local _, key = os.pullEvent("key")
      if key == keys.right then accent = (accent % #theme.accents) + 1
      elseif key == keys.left then accent = ((accent - 2) % #theme.accents) + 1
      elseif key == keys.enter then step = 4; sound.note("bit", 1, 17)
      elseif key == keys.escape then break end
      theme.setAccent(accent)

    elseif step == 4 then
      chrome(native, W, H, 4, STEPS, "Pick a wallpaper")
      chooser(native, W, 8, theme.wallpapers, wallpaper, "left and right to choose")
      ui.centre(native, H - 2, "[Enter] to continue", theme.colour.muted, colours.black, 1, W)

      local _, key = os.pullEvent("key")
      if key == keys.right then wallpaper = (wallpaper % #theme.wallpapers) + 1
      elseif key == keys.left then wallpaper = ((wallpaper - 2) % #theme.wallpapers) + 1
      elseif key == keys.enter then step = 5; sound.note("bit", 1, 19)
      elseif key == keys.escape then break end
      theme.setWallpaper(wallpaper)

    else
      chrome(native, W, H, 5, STEPS, "Keep Slate up to date?")
      ui.centre(native, 7, "Checks at startup and installs new versions.",
        theme.colour.muted, colours.black, 1, W)
      ui.centre(native, 9, wantUpdates and " Yes, keep it updated " or " No, I'll do it myself ",
        colours.black, wantUpdates and theme.colour.ok or colours.lightGrey, 1, W)
      ui.centre(native, 11, "left and right to change", theme.colour.muted, colours.black, 1, W)
      ui.centre(native, H - 2, "[Enter] to finish", theme.colour.muted, colours.black, 1, W)

      local _, key = os.pullEvent("key")
      if key == keys.left or key == keys.right then wantUpdates = not wantUpdates
      elseif key == keys.enter then
        update.setAuto(wantUpdates)
        theme.persist()
        markDone()

        native.setBackgroundColour(colours.black)
        native.clear()
        ui.centre(native, middle - 1, "All set.", colours.white, colours.black, 1, W)
        ui.centre(native, middle + 1, "Drag the icons around. Try the Store.",
          theme.colour.muted, colours.black, 1, W)
        for _, pitch in ipairs({ 12, 16, 19, 24 }) do
          sound.note("bit", 1, pitch)
          sleep(0.12)
        end
        sleep(1.2)
        return true
      elseif key == keys.escape then break end
    end
  end

  -- Skipped: remember that, or it would ask again every single boot.
  theme.persist()
  markDone()
  return false
end

return oobe
