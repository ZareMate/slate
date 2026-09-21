--[[ The Slate desktop: wallpaper, icons, taskbar and start menu.

  The kernel owns windows; this owns everything outside them. It is registered
  with the kernel as the "shell", which calls back into it to paint the layers
  below and above the window stack, and to handle clicks that miss every
  window.
]]

local use = ...
local theme = use("system/theme")
local ui = use("system/ui")
local registry = use("system/apps")
local notify = use("system/notify")

local desktop = {}

local kernel
local loadModule

local ICON_W, ICON_H = 11, 4
local COLUMNS = 4

local menuOpen = false
local menuIndex = 1
local selected = 1            -- keyboard selection on the desktop
local clockTimer
local status                  -- transient message shown in the taskbar
local statusUntil = 0

local MENU_POWER = {
  { label = "Shut down", action = "shutdown" },
  { label = "Reboot",    action = "reboot" },
  { label = "Exit Slate", action = "exit" },
}

--------------------------------------------------------------------------
-- launching
--------------------------------------------------------------------------

local function appById(id)
  for _, app in ipairs(registry) do
    if app.id == id then return app end
  end
  return nil
end

function desktop.launch(id, args)
  local app = appById(id)
  if not app then return nil end

  -- A single-instance app raises the window it already has instead of opening
  -- a second one that would compete with it for hardware.
  if app.single then
    for _, proc in ipairs(kernel.list()) do
      if proc.appId == id then
        kernel.focusOn(proc)
        return proc
      end
    end
  end

  local module = loadModule(app.module)
  local proc = kernel.spawn({
    title = app.title,
    w = app.w, h = app.h,
    run = module.run,
    args = args,
  })
  if proc then proc.appId = id end
  return proc
end

--------------------------------------------------------------------------
-- layout
--------------------------------------------------------------------------

local function iconRect(index)
  local column = (index - 1) % COLUMNS
  local row = math.floor((index - 1) / COLUMNS)
  return 2 + column * (ICON_W + 1), 2 + row * ICON_H
end

--------------------------------------------------------------------------
-- painting
--------------------------------------------------------------------------

function desktop.drawBackground(win)
  local W, _, DESK_H = kernel.size()
  ui.fill(win, 1, 1, W, DESK_H, theme.colour.desktop)

  for index, app in ipairs(registry) do
    local x, y = iconRect(index)
    if y + 2 <= DESK_H then
      local active = (selected == index and kernel.focused() == nil)
      -- The tile is a 5x2 block of the app's colour with its letter in it.
      ui.fill(win, x + 3, y, 5, 2, app.colour)
      ui.text(win, x + 5, y, app.letter,
        app.colour == colours.black and colours.white or colours.white, app.colour)
      -- Unread dot, top-right of the tile.
      if notify.count(app.id) > 0 then
        ui.text(win, x + 8, y, "*", colours.red, app.colour)
      end
      local label = ui.clip(app.title, ICON_W)
      local labelX = x + math.floor((ICON_W - #label) / 2)
      ui.text(win, labelX, y + 2, label,
        active and theme.colour.desktop or theme.colour.desktopText,
        active and theme.colour.desktopText or theme.colour.desktop)
    end
  end
end

function desktop.drawTaskbar(target)
  local W, H = kernel.size()
  ui.fill(target, 1, H, W, 1, theme.colour.bar)

  ui.text(target, 1, H, menuOpen and "[*]" or "[=]",
    theme.colour.barText, menuOpen and theme.colour.accent or theme.colour.bar)

  local clock = textutils.formatTime(os.time(), true)
  local clockX = W - #clock + 1
  ui.text(target, clockX, H, clock, theme.colour.barText, theme.colour.bar)

  if status and os.clock() < statusUntil then
    ui.text(target, 5, H, ui.clip(status, clockX - 6), theme.colour.warn, theme.colour.bar)
    return
  end

  local x = 5
  for _, proc in ipairs(kernel.list()) do
    local width = 11
    if x + width > clockX - 1 then break end
    local focused = (kernel.focused() == proc)
    local bg = focused and theme.colour.barHot or theme.colour.bar
    local fg = focused and colours.black or theme.colour.barText
    local mark = proc.minimised and "_" or " "
    if proc.appId and notify.count(proc.appId) > 0 then mark = "*" end
    ui.text(target, x, H, ui.pad(mark .. ui.clip(proc.title, width - 1), width), fg, bg)
    proc.taskX, proc.taskW = x, width
    x = x + width + 1
  end
end

local function menuItems()
  local items = {}
  for _, app in ipairs(registry) do
    items[#items + 1] = { label = app.title, id = app.id }
  end
  items[#items + 1] = { separator = true }
  for _, entry in ipairs(MENU_POWER) do items[#items + 1] = entry end
  return items
end

local function menuRect()
  local _, H = kernel.size()
  local items = menuItems()
  local width = 15
  local height = #items + 2
  return 1, H - height, width, height, items
end

function desktop.drawOverlay(target)
  -- Toast sits just above the taskbar, right-aligned, over everything.
  local toast = notify.active()
  if toast then
    local W, H = kernel.size()
    local text = " " .. ui.clip(toast.text, math.min(#toast.text, W - 4)) .. " "
    local x = math.max(1, W - #text)
    ui.row(target, x, H - 1, #text, text, colours.white, theme.colour.accent)
  end

  if not menuOpen then return end
  local x, y, w, h, items = menuRect()

  ui.fill(target, x, y, w, h, theme.colour.window)
  ui.row(target, x, y, w, " Slate", theme.colour.accentText, theme.colour.accent)

  for index, item in ipairs(items) do
    local row = y + index
    if item.separator then
      ui.text(target, x, row, ("-"):rep(w), theme.colour.muted, theme.colour.window)
    else
      local on = (index == menuIndex)
      ui.row(target, x, row, w, " " .. item.label,
        on and theme.colour.accentText or theme.colour.windowText,
        on and theme.colour.accent or theme.colour.window)
    end
  end
end

--------------------------------------------------------------------------
-- menu behaviour
--------------------------------------------------------------------------

function desktop.toggleMenu()
  menuOpen = not menuOpen
  if menuOpen then
    menuIndex = 1
  end
  kernel.invalidate()
end

local function runMenuItem(item)
  if not item or item.separator then return end
  menuOpen = false
  kernel.invalidate()
  if item.id then
    desktop.launch(item.id)
  elseif item.action == "shutdown" then
    kernel.power("shutdown")
  elseif item.action == "reboot" then
    kernel.power("reboot")
  elseif item.action == "exit" then
    kernel.stop()
  end
end

local function stepMenu(delta)
  local _, _, _, _, items = menuRect()
  for _ = 1, #items do
    menuIndex = menuIndex + delta
    if menuIndex < 1 then menuIndex = #items end
    if menuIndex > #items then menuIndex = 1 end
    if not items[menuIndex].separator then break end
  end
  kernel.invalidate()
end

function desktop.overlayKey(event)
  if not menuOpen then return false end
  if event[1] ~= "key" then return event[1] == "char" end
  local key = event[2]
  if key == keys.up then stepMenu(-1)
  elseif key == keys.down then stepMenu(1)
  elseif key == keys.enter then
    local _, _, _, _, items = menuRect()
    runMenuItem(items[menuIndex])
  else
    menuOpen = false
    kernel.invalidate()
  end
  return true
end

function desktop.overlayClick(name, button, mx, my)
  if not menuOpen then return false end
  if name ~= "mouse_click" then return true end
  local x, y, w, h, items = menuRect()
  if not ui.hit(mx, my, x, y, w, h) then
    menuOpen = false
    kernel.invalidate()
    return true
  end
  local index = my - y
  if items[index] then
    menuIndex = index
    runMenuItem(items[index])
  end
  return true
end

--------------------------------------------------------------------------
-- clicks that miss every window
--------------------------------------------------------------------------

function desktop.taskbarClick(name, button, mx, my)
  if name ~= "mouse_click" then return end
  if mx <= 3 then return desktop.toggleMenu() end
  for _, proc in ipairs(kernel.list()) do
    if proc.taskX and mx >= proc.taskX and mx < proc.taskX + proc.taskW then
      if kernel.focused() == proc and not proc.minimised then
        kernel.minimise(proc)
      else
        kernel.focusOn(proc)
      end
      return
    end
  end
end

function desktop.desktopClick(name, button, mx, my)
  if name ~= "mouse_click" then return end
  for index in ipairs(registry) do
    local x, y = iconRect(index)
    if ui.hit(mx, my, x, y, ICON_W, 3) then
      selected = index
      desktop.launch(registry[index].id)
      return
    end
  end
  kernel.invalidate()
end

-- Keyboard navigation of the icon grid, for computers with no mouse at all.
function desktop.desktopKey(event)
  if event[1] ~= "key" then return end
  local key = event[2]
  if key == keys.right then selected = math.min(#registry, selected + 1)
  elseif key == keys.left then selected = math.max(1, selected - 1)
  elseif key == keys.down then selected = math.min(#registry, selected + COLUMNS)
  elseif key == keys.up then selected = math.max(1, selected - COLUMNS)
  elseif key == keys.enter then desktop.launch(registry[selected].id)
  end
  kernel.invalidate()
end

--------------------------------------------------------------------------
-- system
--------------------------------------------------------------------------

function desktop.notify(text)
  status = text
  statusUntil = os.clock() + 3
  kernel.invalidate()
end

function desktop.systemEvent(event)
  if event[1] == "timer" and event[2] == clockTimer then
    clockTimer = os.startTimer(1)
    kernel.invalidate()
  end
end

function desktop.init(k, loader)
  kernel = k
  loadModule = loader
  kernel.launcher = function(id, args) return desktop.launch(id, args) end
  clockTimer = os.startTimer(1)

  -- Auto-update runs as a visible window, never silently.
  local update = loadModule("system/update")
  if update.auto() and update.url() and http then
    desktop.launch("updater", { "auto" })
  end
end

return desktop
