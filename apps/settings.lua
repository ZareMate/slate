--[[ Settings - the knobs that actually change something, then the facts.

  Every row is reachable by arrow keys and by mouse, and every change takes
  effect immediately rather than on some "apply" button. Appearance choices are
  persisted through CC's settings API, so they survive a reboot.
]]

local use = ...
local ui = use("system/ui")
local theme = use("system/theme")
local screens = use("system/screens")
local update = use("system/update")
local dev = use("system/dev")

local app = {}

local VERSION = "Slate " .. update.VERSION
local BOOT_MARKER = "-- slate boot"

local function freeSpace()
  local ok, bytes = pcall(fs.getFreeSpace, "/")
  if not ok or type(bytes) ~= "number" then return "unknown" end
  if bytes >= 1048576 then return string.format("%.1f MB", bytes / 1048576) end
  return string.format("%.0f KB", bytes / 1024)
end

local function uptime()
  local seconds = math.floor(os.clock())
  if seconds < 60 then return seconds .. "s" end
  return string.format("%dm %02ds", math.floor(seconds / 60), seconds % 60)
end

local function countDevices()
  local ok, names = pcall(peripheral.getNames)
  if not ok then return 0 end
  return #names
end

--------------------------------------------------------------------------
-- boot script
--------------------------------------------------------------------------

local function bootPath() return "/startup.lua" end

-- "On" means /startup.lua is ours. A startup script somebody else wrote is
-- left alone and reported as such, rather than silently overwritten.
local function bootState(root)
  local path = bootPath()
  if not fs.exists(path) then return "off" end
  local handle = fs.open(path, "r")
  if not handle then return "unknown" end
  local body = handle.readAll() or ""
  handle.close()
  if body:find(BOOT_MARKER, 1, true) then return "on" end
  if fs.combine(root, "startup.lua") == fs.combine(path, "") then return "on" end
  return "foreign"
end

local function setBoot(root, on)
  local path = bootPath()
  if on then
    local target = fs.combine(root, "startup.lua")
    if fs.combine(target, "") == fs.combine(path, "") then
      return false, "Slate already is /startup.lua"
    end
    local handle, err = fs.open(path, "w")
    if not handle then return false, tostring(err) end
    handle.write(BOOT_MARKER .. "\nshell.run(" .. string.format("%q", target) .. ")\n")
    handle.close()
    return true
  end
  local ok, err = pcall(fs.delete, path)
  if not ok then return false, tostring(err) end
  return true
end

--------------------------------------------------------------------------

function app.run(ctx)
  local root = ctx.root()
  local index = 1
  local scroll = 0
  local notice = nil
  local noticeUntil = 0

  local function say(text)
    notice = text
    noticeUntil = os.clock() + 4
  end

  local function rename()
    local width = term.getSize()
    ui.fill(term, 1, 2, width, 4, theme.colour.muted)
    ui.text(term, 2, 2, "New label (blank clears it):", colours.black, theme.colour.muted)
    ui.fill(term, 2, 4, width - 2, 1, colours.white)
    term.setCursorPos(2, 4)
    term.setBackgroundColour(colours.white)
    term.setTextColour(colours.black)
    local value = read()
    if value == nil or value == "" then
      os.setComputerLabel(nil)
      say("Label cleared")
    else
      os.setComputerLabel(value)
      say("Renamed")
    end
  end

  -- Rows are rebuilt each draw so the values shown are never stale.
  local function rows()
    local boot = bootState(root)
    local list = {
      { kind = "head", label = "Appearance" },
      {
        kind = "item", label = "Accent",
        value = theme.accents[theme.accent].name,
        swatch = theme.colour.accent,
        act = function()
          theme.setAccent(theme.accent + 1)
          theme.persist()
          ctx.redraw()
        end,
      },
      {
        kind = "item", label = "Wallpaper",
        value = theme.wallpapers[theme.wallpaper].name,
        swatch = theme.colour.desktop,
        act = function()
          theme.setWallpaper(theme.wallpaper + 1)
          theme.persist()
          ctx.redraw()
        end,
      },

      { kind = "head", label = "This computer" },
      {
        kind = "item", label = "Label",
        value = os.getComputerLabel() or "(none)",
        act = rename,
      },
      {
        kind = "item", label = "Start with world",
        value = boot == "on" and "On" or (boot == "foreign" and "Other script" or "Off"),
        act = function()
          if boot == "foreign" then
            say("/startup.lua is not Slate's")
            return
          end
          local ok, err = setBoot(root, boot ~= "on")
          say(ok and (boot == "on" and "Boot script removed" or "Slate will boot")
            or ("Failed: " .. tostring(err)))
        end,
      },

      { kind = "head", label = "Screens" },
    }

    -- Monitors are optional extra output. Slate keeps drawing to the computer
    -- itself either way, so turning them all off is always safe.
    local monitors = screens.available()
    if #monitors == 0 then
      list[#list + 1] = { kind = "fact", label = "Monitors", value = "none attached" }
    else
      for _, monitor in ipairs(monitors) do
        local w, h = screens.sizeOf(monitor)
        local size = (w and (w .. "x" .. h)) or "?"
        list[#list + 1] = {
          kind = "item",
          label = ui.clip(monitor, 12) .. " " .. size,
          value = screens.isOn(monitor) and "Mirrored" or "Off",
          act = function()
            screens.toggle(monitor)
            ctx.redraw()
            say(screens.isOn(monitor) and "Mirroring to " .. monitor or "Stopped mirroring")
          end,
        }
      end
    end

    for _, extra in ipairs({
      { kind = "head", label = "Updates" },
      {
        kind = "item", label = "Check for updates", value = "",
        act = function() ctx.launch("updater") end,
      },
      {
        kind = "item", label = "Auto update",
        value = update.auto() and "On" or "Off",
        act = function() update.setAuto(not update.auto()) end,
      },
      {
        kind = "item", label = "Update source",
        value = update.url() and "set" or "not set",
        act = function()
          local w = term.getSize()
          ui.fill(term, 1, 2, w, 4, theme.colour.muted)
          ui.text(term, 2, 2, "Update base URL (blank clears):", colours.black, theme.colour.muted)
          ui.fill(term, 2, 4, w - 2, 1, colours.white)
          term.setCursorPos(2, 4)
          term.setBackgroundColour(colours.white)
          term.setTextColour(colours.black)
          update.setUrl(read())
          say("Saved")
        end,
      },

      { kind = "head", label = "Developer" },
      {
        kind = "item", label = "Developer mode",
        value = dev.enabled() and "On" or "Off",
        act = function()
          local now = dev.toggle()
          ctx.redraw()
          say(now and "Console and stats enabled" or "Developer mode off")
        end,
      },

      { kind = "head", label = "Power" },
      { kind = "item", label = "Reboot", act = function() ctx.power("reboot") end },
      { kind = "item", label = "Shut down", act = function() ctx.power("shutdown") end },

      { kind = "head", label = "About" },
      { kind = "fact", label = "System", value = VERSION },
      { kind = "fact", label = "CraftOS", value = tostring(os.version()) },
      { kind = "fact", label = "Computer", value = "#" .. os.getComputerID() },
      { kind = "fact", label = "Devices", value = tostring(countDevices()) },
      { kind = "fact", label = "Free space", value = freeSpace() },
      { kind = "fact", label = "Uptime", value = uptime() },
    }) do
      list[#list + 1] = extra
    end
    return list
  end

  local function selectable(list, from, delta)
    local at = from
    for _ = 1, #list do
      at = at + delta
      if at < 1 then at = #list end
      if at > #list then at = 1 end
      if list[at].kind == "item" then return at end
    end
    return from
  end

  local function draw()
    local width, height = term.getSize()
    local list = rows()
    local body = height - 2
    local top = 2

    if index < scroll + 1 then scroll = index - 1 end
    if index > scroll + body then scroll = index - body end
    if scroll < 0 then scroll = 0 end

    term.setBackgroundColour(theme.colour.window)
    term.clear()
    ui.row(term, 1, 1, width, " Settings", theme.colour.accentText, theme.colour.accent)

    for offset = 0, body - 1 do
      local entry = list[scroll + offset + 1]
      local y = top + offset
      if entry then
        if entry.kind == "head" then
          ui.row(term, 1, y, width, " " .. entry.label,
            theme.colour.mutedText, theme.colour.muted)
        else
          local on = (scroll + offset + 1 == index) and entry.kind == "item"
          local bg = on and theme.colour.accent or theme.colour.window
          local fg = on and theme.colour.accentText
            or (entry.kind == "fact" and theme.colour.mutedText or theme.colour.windowText)

          local value = entry.value or ""
          local room = width - 3 - #value
          ui.row(term, 1, y, width,
            " " .. ui.pad(ui.clip(entry.label, math.max(1, room)), math.max(1, room))
            .. " " .. value, fg, bg)

          -- A colour row shows the colour itself, which is the only honest way
          -- to preview it - and on a basic computer the name still carries it.
          if entry.swatch then
            ui.fill(term, width, y, 1, 1, entry.swatch)
          end
        end
      end
    end

    ui.scrollbar(term, width, top, body, #list, scroll,
      theme.colour.muted, theme.colour.accent)

    if notice and os.clock() < noticeUntil then
      ui.row(term, 1, height, width, " " .. ui.clip(notice, width - 2),
        colours.white, theme.colour.ok)
    else
      ui.row(term, 1, height, width, " Enter to change  Ctrl+F fullscreen",
        theme.colour.mutedText, theme.colour.muted)
    end
  end

  -- Start on the first thing you can actually change, not on a heading.
  index = selectable(rows(), 0, 1)
  draw()

  local ticker = os.startTimer(1)

  while true do
    local event = { os.pullEvent() }
    local name = event[1]

    if name == "timer" and event[2] == ticker then
      ticker = os.startTimer(1)
      draw()

    elseif name == "key" then
      local key = event[2]
      local list = rows()
      if key == keys.down then index = selectable(list, index, 1); draw()
      elseif key == keys.up then index = selectable(list, index, -1); draw()
      elseif key == keys.enter or key == keys.space then
        local entry = list[index]
        if entry and entry.act then entry.act() end
        draw()
      end

    elseif name == "mouse_click" then
      local list = rows()
      local clicked = scroll + event[4] - 1
      local entry = list[clicked]
      if entry and entry.kind == "item" then
        index = clicked
        if entry.act then entry.act() end
      end
      draw()

    elseif name == "mouse_scroll" then
      local list = rows()
      index = selectable(list, index, event[2] > 0 and 1 or -1)
      draw()

    elseif name == "term_resize" then
      draw()
    end
  end
end

return app
