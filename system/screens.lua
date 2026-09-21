--[[ Screens - optional monitor output.

  Two modes, because "put it on the big screen" means two different things:

    MIRROR  the monitor shows a copy of the computer's own 51x19 desktop,
            clipped if the monitor is smaller.

    DISPLAY the monitor IS the desktop. The kernel asks this module how big
            the display is, so on a 3x2 monitor the desktop lays itself out
            at whatever that works out to - more icon slots, wider windows,
            a longer taskbar. Nothing is scaled or letterboxed; the OS is
            simply built at the size of the screen it is on.

  Slate still needs no screen at all: nothing here is enabled by default and
  the kernel always keeps drawing to term.native().

  With screens.lua and peripherals.lua this is the hardware layer - the only
  place in system/ allowed to touch peripherals.
]]

local use = ...
local peripherals = use("system/peripherals")

local screens = {}

local active = {}          -- [name] = wrapped monitor, mirroring
local fresh = {}           -- monitors needing one full paint
local primaryName = nil    -- the monitor acting as the display, if any
local primaryTerm = nil

local function isType(name, kind)
  return peripherals.isType(name, kind)
end

function screens.available()
  return peripherals.ofType("monitor")
end

function screens.isOn(name)
  return active[name] ~= nil
end

function screens.owns(name)
  return active[name] ~= nil or primaryName == name
end

function screens.count()
  local total = 0
  for _ in pairs(active) do total = total + 1 end
  return total
end

-- "off" | "mirror" | "display"
function screens.modeOf(name)
  if primaryName == name then return "display" end
  if active[name] then return "mirror" end
  return "off"
end

function screens.sizeOf(name)
  local monitor = active[name] or (primaryName == name and primaryTerm)
    or (isType(name, "monitor") and peripheral.wrap(name))
  if not monitor then return nil end
  local ok, w, h = pcall(monitor.getSize)
  if not ok then return nil end
  return w, h
end

local function prepare(monitor)
  -- The smallest text scale gives the most characters, which is the whole
  -- point of putting the desktop on a bigger screen.
  pcall(monitor.setTextScale, 0.5)
  pcall(monitor.setBackgroundColour, colours.black)
  pcall(monitor.clear)
  pcall(monitor.setCursorBlink, false)
end

function screens.enable(name)
  if active[name] then return true end
  if not isType(name, "monitor") then return false, "not a monitor" end
  local monitor = peripheral.wrap(name)
  if not monitor then return false, "could not wrap " .. name end
  prepare(monitor)
  active[name] = monitor
  fresh[name] = true
  return true
end

function screens.disable(name)
  local monitor = active[name]
  if not monitor then return end
  active[name] = nil
  pcall(monitor.setBackgroundColour, colours.black)
  pcall(monitor.clear)
  pcall(monitor.setCursorPos, 1, 1)
end

--------------------------------------------------------------------------
-- display mode
--------------------------------------------------------------------------

function screens.primary()
  return primaryTerm
end

function screens.primaryName()
  return primaryName
end

function screens.setPrimary(name)
  screens.clearPrimary()
  if not name then return false end
  if not isType(name, "monitor") then return false, "not a monitor" end
  local monitor = peripheral.wrap(name)
  if not monitor then return false, "could not wrap " .. name end
  screens.disable(name)          -- a display is not also a mirror
  prepare(monitor)
  primaryName, primaryTerm = name, monitor
  fresh[name] = true
  return true
end

function screens.clearPrimary()
  if not primaryTerm then return end
  pcall(primaryTerm.setBackgroundColour, colours.black)
  pcall(primaryTerm.clear)
  pcall(primaryTerm.setCursorPos, 1, 1)
  primaryName, primaryTerm = nil, nil
end

-- Cycles off -> mirror -> display -> off, which is what a single Settings
-- row can drive.
function screens.cycle(name)
  local mode = screens.modeOf(name)
  if mode == "off" then
    screens.enable(name)
    return "mirror"
  elseif mode == "mirror" then
    screens.setPrimary(name)
    return "display"
  end
  screens.clearPrimary()
  return "off"
end

-- The size the desktop should be built at. Falls back to the computer's own
-- terminal whenever there is no display monitor, which is the normal case.
function screens.displaySize(fallback)
  if primaryTerm then
    local ok, w, h = pcall(primaryTerm.getSize)
    if ok and w and h and w > 0 and h > 0 then return w, h end
    -- A monitor that has been broken off must not freeze the layout.
    screens.clearPrimary()
  end
  return fallback()
end

--------------------------------------------------------------------------

function screens.forget(name)
  active[name] = nil
  if primaryName == name then
    primaryName, primaryTerm = nil, nil
  end
end

function screens.clearAll()
  for name, monitor in pairs(active) do
    local ok = pcall(function()
      monitor.setBackgroundColour(colours.black)
      monitor.clear()
    end)
    if not ok then active[name] = nil end
  end
  screens.clearPrimary()
end

-- One pcall per monitor per frame rather than per row: a monitor broken off
-- mid-frame drops out instead of erroring the whole OS.
-- changed is the list of rows the kernel actually repainted. A monitor that
-- has just been switched on has nothing on it yet, so it gets one full paint
-- first and only changes after that.
local function paint(monitor, rows, getLine, changed, full)
  local w, h = monitor.getSize()
  if full or not changed then
    for y = 1, math.min(rows, h) do
      local text, fg, bg = getLine(y)
      monitor.setCursorPos(1, y)
      monitor.blit(text:sub(1, w), fg:sub(1, w), bg:sub(1, w))
    end
    return
  end
  for _, y in ipairs(changed) do
    if y <= h then
      local text, fg, bg = getLine(y)
      monitor.setCursorPos(1, y)
      monitor.blit(text:sub(1, w), fg:sub(1, w), bg:sub(1, w))
    end
  end
end

function screens.presentFrame(rows, getLine, changed)
  local name = primaryName
  if primaryTerm and name then
    local ok = pcall(paint, primaryTerm, rows, getLine, changed, fresh[name])
    fresh[name] = nil
    if not ok then screens.clearPrimary() end
  end

  for name, monitor in pairs(active) do
    local ok = pcall(paint, monitor, rows, getLine, changed, fresh[name])
    fresh[name] = nil
    if not ok then active[name] = nil end
  end
end

return screens
