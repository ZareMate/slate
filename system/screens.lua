--[[ Screens - optional monitor output.

  Slate still needs no screen: the kernel always presents to term.native(),
  and this module starts with nothing enabled. Turning a monitor on in
  Settings makes it an additional output that mirrors the same composited
  frame, and an advanced monitor's touches come back as clicks.

  This is the only file in system/ allowed to touch peripherals, so the rest
  of the OS stays runnable on a bare computer.
]]

local use = ...
local peripherals = use("system/peripherals")

local screens = {}

local active = {}          -- [name] = wrapped monitor

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
  return active[name] ~= nil
end

function screens.count()
  local total = 0
  for _ in pairs(active) do total = total + 1 end
  return total
end

function screens.sizeOf(name)
  local monitor = active[name] or (isType(name, "monitor") and peripheral.wrap(name))
  if not monitor then return nil end
  local ok, w, h = pcall(monitor.getSize)
  if not ok then return nil end
  return w, h
end

function screens.enable(name)
  if active[name] then return true end
  if not isType(name, "monitor") then return false, "not a monitor" end
  local monitor = peripheral.wrap(name)
  if not monitor then return false, "could not wrap " .. name end
  -- The smallest text scale gives the most characters, which is what a
  -- mirrored desktop wants.
  pcall(monitor.setTextScale, 0.5)
  pcall(monitor.setBackgroundColour, colours.black)
  pcall(monitor.clear)
  pcall(monitor.setCursorBlink, false)
  active[name] = monitor
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

function screens.toggle(name)
  if active[name] then
    screens.disable(name)
    return false
  end
  local ok = screens.enable(name)
  return ok
end

-- Called when a peripheral goes away; the wrapped object would throw.
function screens.forget(name)
  active[name] = nil
end

function screens.clearAll()
  for name, monitor in pairs(active) do
    local ok = pcall(function()
      monitor.setBackgroundColour(colours.black)
      monitor.clear()
    end)
    if not ok then active[name] = nil end
  end
end

-- One pcall per monitor per frame rather than per row: a monitor that was
-- broken off mid-frame drops out instead of erroring the whole OS.
function screens.presentFrame(rows, getLine)
  for name, monitor in pairs(active) do
    local ok = pcall(function()
      local w, h = monitor.getSize()
      for y = 1, math.min(rows, h) do
        local text, fg, bg = getLine(y)
        monitor.setCursorPos(1, y)
        monitor.blit(text:sub(1, w), fg:sub(1, w), bg:sub(1, w))
      end
    end)
    if not ok then active[name] = nil end
  end
end

return screens
