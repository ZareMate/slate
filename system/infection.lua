--[[ Infection state - the "virus" FreeRAM.exe leaves behind.

  A deliberate design choice: this SIMULATES corruption instead of causing it.
  Nothing is deleted, nothing is overwritten, no file is harmed. What it does
  is set a flag in CC's settings and make the desktop look wrecked while that
  flag is set.

  That is what makes the joke work. Closing the window does not help. Deleting
  FreeRAM.exe does not help. Rebooting does not help, because the flag is in
  settings. Only Zare's Antivirus clears it - and it genuinely can, because
  there was never any real damage to undo.

  It also cannot touch the real computer: this is Lua inside ComputerCraft,
  with no reach beyond the in-game filesystem.
]]

local infection = {}

local KEY = "slate.infected"
local popupTimer = 0
local popups = 0

local SCARY = {
  "MEMORY LEAK DETECTED",
  "ur pc is corrupted :)",
  "FREE RAM RUNNING LOW",
  "kernel32.dll not found",
  "0xC0FFEE FATAL",
  "deleting system32...",
  "haha nice computer",
  "REGISTRY DAMAGED",
}

function infection.active()
  local ok, value = pcall(settings.get, KEY)
  return ok and value == true
end

function infection.infect()
  pcall(function()
    settings.set(KEY, true)
    settings.save()
  end)
end

function infection.cure()
  pcall(function()
    settings.unset(KEY)
    settings.save()
  end)
  popups = 0
end

function infection.message()
  return SCARY[math.random(1, #SCARY)]
end

-- Cosmetic noise over the wallpaper. Deliberately drawn UNDER the icons and
-- never over the taskbar, so the desktop stays usable and Zare can be reached.
function infection.glitch(win, W, H)
  for _ = 1, 26 do
    local x = math.random(1, W)
    local y = math.random(1, H)
    local colour = ({ colours.red, colours.green, colours.lime, colours.black })[math.random(1, 4)]
    local glyph = ({ "#", "%", "?", "@", "!", "0", "1" })[math.random(1, 7)]
    win.setCursorPos(x, y)
    win.setBackgroundColour(colour)
    win.setTextColour(colours.white)
    win.write(glyph)
  end
end

function infection.banner()
  return " !! SYSTEM COMPROMISED !! "
end

-- Popups arrive every few seconds, capped so the desktop never drowns.
function infection.tick(spawnPopup)
  if not infection.active() then return end
  popupTimer = popupTimer + 1
  if popupTimer < 7 then return end
  popupTimer = 0
  if popups >= 3 then return end
  popups = popups + 1
  spawnPopup(infection.message(), function() popups = math.max(0, popups - 1) end)
end

return infection
