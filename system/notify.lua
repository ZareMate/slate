--[[ Notifications: a toast, and a dot on whatever is waiting for you.

  Unread counts are per app id, so the dot survives the toast expiring and
  keeps showing on the desktop icon and taskbar button until you actually
  open the thing. Focusing a window clears its app's dot.
]]

local notify = {}

local unread = {}          -- [appId] = count
local toast = nil          -- { text, from, expires }

local LIFETIME = 5

function notify.push(appId, text)
  if appId then unread[appId] = (unread[appId] or 0) + 1 end
  toast = { text = tostring(text), from = appId, expires = os.clock() + LIFETIME }
end

function notify.count(appId)
  return unread[appId] or 0
end

function notify.total()
  local sum = 0
  for _, count in pairs(unread) do sum = sum + count end
  return sum
end

function notify.clear(appId)
  if appId then unread[appId] = nil end
end

-- nil once it has expired, so callers never have to check the clock.
function notify.active()
  if toast and os.clock() < toast.expires then return toast end
  toast = nil
  return nil
end

function notify.dismiss()
  toast = nil
end

return notify
