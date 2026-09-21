--[[ Sound - optional speaker output.

  Part of the hardware layer: the only other file allowed to touch peripherals
  besides screens.lua and peripherals.lua. Everything here is a no-op when no
  speaker is attached, so nothing that makes noise has to check first.
]]

local use = ...
local peripherals = use("system/peripherals")

local sound = {}

local function speaker()
  local names = peripherals.ofType("speaker")
  if #names == 0 then return nil end
  return peripheral.wrap(names[1])
end

function sound.available()
  return speaker() ~= nil
end

-- pitch is 0-24, volume 0-3. Silence is a valid outcome, never an error.
function sound.note(instrument, volume, pitch)
  local device = speaker()
  if not device then return false end
  return pcall(device.playNote, instrument or "harp", volume or 1, pitch or 12)
end

function sound.beep(pitch)
  return sound.note("bit", 1, pitch or 12)
end

-- Short recognisable jingles. Rising = something arrived, falling = it left.
local CHIMES = {
  connect = { { "pling", 12 }, { "pling", 16 }, { "pling", 19 }, { "pling", 24 } },
  disconnect = { { "bass", 14 }, { "bass", 10 }, { "bass", 6 } },
  alert = { { "bit", 18 }, { "bit", 14 } },
}

-- Runs for about a third of a second. It yields between notes, so events keep
-- queueing while it plays and are handled the moment it finishes.
function sound.chime(kind)
  local notes = CHIMES[kind]
  if not notes or not sound.available() then return false end
  for index, entry in ipairs(notes) do
    sound.note(entry[1], 1, entry[2])
    if index < #notes then sleep(0.09) end
  end
  return true
end

return sound
