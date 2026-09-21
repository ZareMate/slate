--[[ Developer mode.

  Off by default, and everything it turns on is additive: stats in the
  taskbar, the Console app, full tracebacks on a crash, and dev-only apps
  becoming visible. Nothing changes behaviour for people who leave it off.

  The flag lives in CC settings so it survives a reboot - handy when what you
  are debugging is the boot.
]]

local dev = {}

local KEY = "slate.dev"

function dev.enabled()
  local ok, value = pcall(settings.get, KEY)
  return ok and value == true
end

function dev.set(on)
  pcall(function()
    if on then settings.set(KEY, true) else settings.unset(KEY) end
    settings.save()
  end)
end

function dev.toggle()
  local now = not dev.enabled()
  dev.set(now)
  return now
end

-- Heap size in KB, or nil when this build has no collectgarbage. CC's sandbox
-- does not promise it, and dev mode used to call it straight from the
-- taskbar - which runs in the kernel, so a nil there took the whole OS down
-- rather than one window.
function dev.heapKB()
  if type(collectgarbage) ~= "function" then return nil end
  local ok, value = pcall(collectgarbage, "count")
  if not ok or type(value) ~= "number" then return nil end
  return math.floor(value)
end

-- A short line for the taskbar: heap and window count, the two numbers worth
-- watching while building something.
function dev.stats(windows)
  local heap = dev.heapKB()
  if not heap then return ("%dw"):format(windows or 0) end
  return ("%dK %dw"):format(heap, windows or 0)
end

return dev
