--[[ Catalog - the app list the desktop actually shows.

  Built-ins come from system/apps.lua and can never be removed. Store installs
  are kept in CC's settings so they survive a reboot, and their code lives in
  apps/ like everything else. Icon order is stored here too, because dragging
  an icon is only useful if it stays where you put it.
]]

local use = ...
local builtin = use("system/apps")
local dev = use("system/dev")

local catalog = {}

---@type table Store-installed apps; filled by load() before any read.
local installed

---@type table Desktop icon order as a list of app ids; filled by load().
local order

---@type table Hotbar slots as a list of app ids; filled by load().
local pinned

-- What a fresh desktop starts with on the hotbar.
local DEFAULT_PINS = { "files", "terminal", "store" }

local function load()
  if installed then return end
  installed, order, pinned = {}, {}, {}
  pcall(function()
    local saved = settings.get("slate.installed")
    if type(saved) == "table" then installed = saved end
    local savedOrder = settings.get("slate.iconorder")
    if type(savedOrder) == "table" then order = savedOrder end
    local savedPins = settings.get("slate.pinned")
    if type(savedPins) == "table" then pinned = savedPins end
  end)
  if #pinned == 0 then
    for _, id in ipairs(DEFAULT_PINS) do pinned[#pinned + 1] = id end
  end
end

local function persist()
  pcall(function()
    settings.set("slate.installed", installed)
    settings.set("slate.iconorder", order)
    settings.set("slate.pinned", pinned)
    settings.save()
  end)
end

function catalog.builtins()
  return builtin
end

-- Built-ins first in their declared order, then store apps, then reordered by
-- whatever the user has dragged things into.
function catalog.all()
  load()
  local list, seen = {}, {}
  local showDev = dev.enabled()
  for _, app in ipairs(builtin) do
    -- Dev-only apps simply are not in the list unless dev mode is on, so
    -- nothing else has to know they exist.
    if showDev or not app.dev then
      list[#list + 1] = app
      seen[app.id] = app
    end
  end
  for _, app in ipairs(installed) do
    if not seen[app.id] then
      list[#list + 1] = app
      seen[app.id] = app
    end
  end

  if #order == 0 then return list end

  local sorted, used = {}, {}
  for _, id in ipairs(order) do
    if seen[id] and not used[id] then
      sorted[#sorted + 1] = seen[id]
      used[id] = true
    end
  end
  for _, app in ipairs(list) do
    if not used[app.id] then sorted[#sorted + 1] = app end
  end
  return sorted
end

function catalog.byId(id)
  for _, app in ipairs(catalog.all()) do
    if app.id == id then return app end
  end
  return nil
end

function catalog.isBuiltin(id)
  for _, app in ipairs(builtin) do
    if app.id == id then return true end
  end
  return false
end

function catalog.isInstalled(id)
  load()
  for _, app in ipairs(installed) do
    if app.id == id then return true end
  end
  return catalog.isBuiltin(id)
end

function catalog.install(entry)
  load()
  if catalog.isBuiltin(entry.id) then return false, "that is a built-in app" end
  for index, app in ipairs(installed) do
    if app.id == entry.id then installed[index] = entry; persist(); return true end
  end
  installed[#installed + 1] = entry
  persist()
  return true
end

function catalog.uninstall(id, root)
  load()
  if catalog.isBuiltin(id) then return false, "built-in apps cannot be removed" end
  for index, app in ipairs(installed) do
    if app.id == id then
      table.remove(installed, index)
      -- Take the code with it, or the next install of the same id would run
      -- whatever was left behind.
      if root and app.module then
        pcall(fs.delete, fs.combine(root, app.module .. ".lua"))
      end
      persist()
      return true
    end
  end
  return false, "not installed"
end

--------------------------------------------------------------------------
-- desktop icon order
--------------------------------------------------------------------------

--------------------------------------------------------------------------
-- hotbar
--------------------------------------------------------------------------

-- Only pins that still resolve to a real app; an uninstalled app leaves no
-- dead slot behind.
function catalog.pinned()
  load()
  local out = {}
  for _, id in ipairs(pinned) do
    if catalog.byId(id) then out[#out + 1] = id end
  end
  return out
end

function catalog.isPinned(id)
  for _, pin in ipairs(catalog.pinned()) do
    if pin == id then return true end
  end
  return false
end

function catalog.pin(id)
  load()
  if catalog.isPinned(id) or #pinned >= 9 then return false end
  pinned[#pinned + 1] = id
  persist()
  return true
end

function catalog.unpin(id)
  load()
  for index, pin in ipairs(pinned) do
    if pin == id then
      table.remove(pinned, index)
      persist()
      return true
    end
  end
  return false
end

--------------------------------------------------------------------------
-- autostart
--------------------------------------------------------------------------

local function overrides()
  local ok, value = pcall(settings.get, "slate.autostart")
  if ok and type(value) == "table" then return value end
  return {}
end

-- Registry defaults, with the user's on/off overrides applied. Stored as a
-- map rather than a list so turning something off is remembered even though
-- the registry still says it should start.
function catalog.autostart()
  local chosen = overrides()
  local out = {}
  for _, app in ipairs(catalog.all()) do
    local wanted = chosen[app.id]
    if wanted == nil then wanted = app.autostart == true end
    if wanted then out[#out + 1] = app.id end
  end
  return out
end

function catalog.setAutostart(id, on)
  local chosen = overrides()
  chosen[id] = on and true or false
  pcall(function()
    settings.set("slate.autostart", chosen)
    settings.save()
  end)
end

function catalog.setOrder(ids)
  load()
  order = ids
  persist()
end

-- Moves one app to a slot, shuffling everything else along.
function catalog.moveTo(id, slot)
  local list = catalog.all()
  local ids = {}
  for _, app in ipairs(list) do
    if app.id ~= id then ids[#ids + 1] = app.id end
  end
  slot = math.max(1, math.min(#ids + 1, slot))
  table.insert(ids, slot, id)
  catalog.setOrder(ids)
end

return catalog
