--[[ Devices - what is attached, what it can do, and actually doing it.

  Four views: the device list, a Tools panel, that device's raw methods, and
  the result of calling one. Arguments are typed as a Lua-ish list
  (1, "text", true, nil) and parsed rather than eval'd, so a typo is a
  message and not a crash.

  Tools exist for hardware that has no interface of its own - monitors,
  speakers, printers and disk drives. They are driven from this app, on the
  advanced computer, so the device itself needs no GUI. Anything without a
  tool set (or reached with [M]) still opens the raw method list.

  The kernel broadcasts events it does not route to a window, so `peripheral`
  and `peripheral_detach` arrive here on their own and the list stays honest
  without polling.
]]

local use = ...
local ui = use("system/ui")
local theme = use("system/theme")
local peripherals = use("system/peripherals")

local app = {}

-- Parses an argument list without running it. Accepts numbers, true/false/nil,
-- and quoted or bare strings, separated by commas.
local function parseArgs(text)
  local args = {}
  local count = 0
  if text == nil then return args, 0 end
  text = text:gsub("^%s+", ""):gsub("%s+$", "")
  if text == "" then return args, 0 end

  for piece in (text .. ","):gmatch("([^,]*),") do
    piece = piece:gsub("^%s+", ""):gsub("%s+$", "")
    count = count + 1
    local quoted = piece:match('^"(.*)"$') or piece:match("^'(.*)'$")
    if quoted then
      args[count] = quoted
    elseif piece == "true" then
      args[count] = true
    elseif piece == "false" then
      args[count] = false
    elseif piece == "nil" or piece == "" then
      args[count] = nil
    elseif tonumber(piece) then
      args[count] = tonumber(piece)
    else
      args[count] = piece
    end
  end
  return args, count
end

local function show(value)
  local kind = type(value)
  if kind == "string" then return string.format("%q", value) end
  if kind == "table" then
    local ok, text = pcall(textutils.serialise, value, { compact = true })
    return ok and text or "<table>"
  end
  return tostring(value)
end

----------------------------------------------------------------------
-- tools: per-kind control panels for hardware with no GUI of its own
----------------------------------------------------------------------

-- Lower-cased colour names -> values, so "lightBlue", "lightblue" and
-- "LIGHTBLUE" all work when typed on a keyboard.
local colourByName = {}
for name, value in pairs(colours) do
  if type(value) == "number" then colourByName[name:lower()] = value end
end
local COLOUR_HINT = "white orange magenta lightBlue yellow lime pink gray lightGray cyan purple blue brown green red black"

local function parseColour(text)
  local value = colourByName[(text or ""):lower():gsub("%s", "")]
  if not value then error("Unknown colour: " .. tostring(text), 0) end
  return value
end

-- Type tests live in system/peripherals; getType returns several values as of
-- CC:Tweaked 1.99 and only one place should have to know that.
local function has(name, kind)
  return peripherals.isType(name, kind)
end

-- Calls a method and returns its first two results, or nil when it fails.
local function ask(dev, method, ...)
  local ok, a, b = pcall(peripheral.call, dev, method, ...)
  if ok then return a, b end
  return nil
end

-- Shows a one-line prompt over the top of the screen and reads the answer.
-- Returns the text, or nil if it was left empty.
local function prompt(title, hint, default)
  local width = term.getSize()
  ui.fill(term, 1, 2, width, 5, theme.colour.muted)
  ui.text(term, 2, 2, ui.clip(title, width - 2), colours.black, theme.colour.muted)
  ui.text(term, 2, 3, ui.clip(hint or "", width - 2), theme.colour.mutedText, theme.colour.muted)
  ui.fill(term, 2, 5, width - 2, 1, colours.white)
  term.setCursorPos(2, 5)
  term.setBackgroundColour(colours.white)
  term.setTextColour(colours.black)
  local text = read(nil, nil, nil, default)
  if text == nil or text == "" then return nil end
  return text
end

local function monitorTools()
  return {
    {
      label = "Write text",
      run = function(dev)
        local text = prompt("Write text", "Printed on the screen, then the cursor drops a line")
        if not text then return nil end
        local _, height = peripheral.call(dev, "getSize")
        local _, y = peripheral.call(dev, "getCursorPos")
        if y > height then
          peripheral.call(dev, "scroll", 1)
          y = height
        end
        peripheral.call(dev, "setCursorPos", 1, y)
        peripheral.call(dev, "write", text)
        peripheral.call(dev, "setCursorPos", 1, y + 1)
        return "Wrote " .. #text .. " characters on line " .. y
      end,
    },
    {
      label = "Clear screen",
      run = function(dev)
        peripheral.call(dev, "clear")
        peripheral.call(dev, "setCursorPos", 1, 1)
        return "Screen cleared"
      end,
    },
    {
      label = "Text scale",
      run = function(dev)
        local text = prompt("Text scale", "0.5 to 5, in steps of 0.5 (smaller = more room)", "1")
        if not text then return nil end
        local scale = tonumber(text)
        if not scale then error("Not a number: " .. text, 0) end
        peripheral.call(dev, "setTextScale", scale)
        return "Text scale set to " .. scale
      end,
    },
    {
      label = "Text colour",
      run = function(dev)
        local text = prompt("Text colour", COLOUR_HINT)
        if not text then return nil end
        peripheral.call(dev, "setTextColour", parseColour(text))
        return "Text colour set to " .. text
      end,
    },
    {
      label = "Background colour",
      run = function(dev)
        local text = prompt("Background colour", COLOUR_HINT)
        if not text then return nil end
        peripheral.call(dev, "setBackgroundColour", parseColour(text))
        return "Background set to " .. text .. " (Clear screen to apply)"
      end,
    },
    {
      label = "Colour bars (test)",
      run = function(dev)
        local width, height = peripheral.call(dev, "getSize")
        local text = string.rep(" ", width)
        local fg = string.rep("0", width)
        local cells = {}
        for x = 1, width do
          local bar = math.floor((x - 1) * 16 / width)
          cells[x] = colours.toBlit(2 ^ bar)
        end
        local bg = table.concat(cells)
        for y = 1, height do
          peripheral.call(dev, "setCursorPos", 1, y)
          peripheral.call(dev, "blit", text, fg, bg)
        end
        return "Drew 16 colour bars"
      end,
    },
  }
end

local function speakerTools()
  return {
    {
      label = "Play note",
      run = function(dev)
        local text = prompt("Play note", "instrument, volume, pitch (0-24)", "harp, 1, 12")
        if not text then return nil end
        local args = parseArgs(text)
        local played = peripheral.call(dev, "playNote", args[1] or "harp", args[2] or 1, args[3] or 12)
        if not played then error("Speaker is busy - too many sounds at once", 0) end
        return "Played " .. tostring(args[1] or "harp")
      end,
    },
    {
      label = "Play sound",
      run = function(dev)
        local text = prompt("Play sound", "sound id, volume, pitch",
          "minecraft:entity.experience_orb.pickup, 1, 1")
        if not text then return nil end
        local args = parseArgs(text)
        if type(args[1]) ~= "string" then error("Give a sound id", 0) end
        local played = peripheral.call(dev, "playSound", args[1], args[2] or 1, args[3] or 1)
        if not played then error("Speaker is busy - too many sounds at once", 0) end
        return "Played " .. args[1]
      end,
    },
    {
      label = "Stop all sound",
      run = function(dev)
        peripheral.call(dev, "stop")
        return "Stopped"
      end,
    },
  }
end

local function printerTools()
  return {
    {
      label = "Print text",
      run = function(dev)
        local text = prompt("Print text", "Wrapped onto a single page; first 16 letters become the title")
        if not text then return nil end
        if not peripheral.call(dev, "newPage") then error("Needs paper and ink", 0) end
        local width, height = peripheral.call(dev, "getPageSize")
        peripheral.call(dev, "setPageTitle", text:sub(1, 16))
        local lines = ui.wrap(text, width)
        local written = 0
        for i, line in ipairs(lines) do
          if i > height then break end
          peripheral.call(dev, "setCursorPos", 1, i)
          peripheral.call(dev, "write", line)
          written = i
        end
        if not peripheral.call(dev, "endPage") then error("Output tray is full", 0) end
        if written < #lines then
          return "Printed " .. written .. " lines (" .. (#lines - written) .. " did not fit)"
        end
        return "Printed " .. written .. " lines"
      end,
    },
  }
end

local function driveTools()
  return {
    {
      label = "Eject disk",
      run = function(dev)
        peripheral.call(dev, "ejectDisk")
        return "Ejected"
      end,
    },
    {
      label = "Set disk label",
      run = function(dev)
        local text = prompt("Set disk label", "Leave empty to cancel")
        if not text then return nil end
        peripheral.call(dev, "setDiskLabel", text)
        return "Label set to " .. text
      end,
    },
    {
      label = "Play audio disc",
      run = function(dev)
        if not peripheral.call(dev, "hasAudio") then error("No audio disc inserted", 0) end
        peripheral.call(dev, "playAudio")
        return "Playing"
      end,
    },
    {
      label = "Stop audio disc",
      run = function(dev)
        peripheral.call(dev, "stopAudio")
        return "Stopped"
      end,
    },
  }
end

-- The tools a device offers, built from every type it reports.
local function toolsFor(dev)
  local tools = {}
  local function add(list)
    for _, tool in ipairs(list) do tools[#tools + 1] = tool end
  end
  if has(dev, "monitor") then add(monitorTools()) end
  if has(dev, "speaker") then add(speakerTools()) end
  if has(dev, "printer") then add(printerTools()) end
  if has(dev, "drive") then add(driveTools()) end
  return tools
end

-- Status lines shown above the tool list. Each read is guarded: a value that
-- cannot be read is left out rather than breaking the panel.
local function infoFor(dev)
  local lines = {}
  if has(dev, "monitor") then
    local width, height = ask(dev, "getSize")
    if width then lines[#lines + 1] = "Size: " .. width .. " x " .. height .. " characters" end
    local colour = ask(dev, "isColour")
    if colour ~= nil then lines[#lines + 1] = "Colour: " .. (colour and "yes (advanced)" or "no (basic)") end
    local scale = ask(dev, "getTextScale")
    if scale then lines[#lines + 1] = "Text scale: " .. scale end
  end
  if has(dev, "speaker") then
    lines[#lines + 1] = "harp bass bell flute chime guitar pling banjo bit"
    lines[#lines + 1] = "snare hat basedrum cow_bell xylophone didgeridoo"
  end
  if has(dev, "printer") then
    local paper = ask(dev, "getPaperLevel")
    local ink = ask(dev, "getInkLevel")
    if paper then lines[#lines + 1] = "Paper: " .. paper end
    if ink then lines[#lines + 1] = "Ink: " .. ink end
  end
  if has(dev, "drive") then
    local present = ask(dev, "isDiskPresent")
    lines[#lines + 1] = "Disk: " .. (present and "inserted" or "none")
    if present then
      local label = ask(dev, "getDiskLabel")
      local id = ask(dev, "getDiskID")
      if label then lines[#lines + 1] = "Label: " .. label end
      if id then lines[#lines + 1] = "ID: " .. id end
      if ask(dev, "hasAudio") then
        lines[#lines + 1] = "Audio: " .. tostring(ask(dev, "getAudioTitle") or "disc")
      end
    end
  end
  return lines
end

function app.run(ctx)
  local names = {}
  local view = "devices"         -- devices | tools | methods | result
  local device = nil
  local methods = {}
  local tools = {}
  local index, scroll = 1, 0
  local methodIndex, methodScroll = 1, 0
  local toolIndex, toolScroll = 1, 0
  local toolsTop = 2             -- first list row of the Tools view, set when drawn
  local toolStatus = nil         -- { text, ok } shown under the tool list
  local result = nil
  local lastArgs = {}

  local function refresh()
    names = peripherals.names()
    if index > #names then index = math.max(1, #names) end
  end

  local function loadMethods()
    methods = {}
    if not device then return end
    local ok, list = pcall(peripheral.getMethods, device)
    if ok and type(list) == "table" then
      methods = list
      table.sort(methods)
    end
    methodIndex, methodScroll = 1, 0
  end

  -- Devices with tools open on the Tools view; the rest go straight to methods.
  local function openDevice(name)
    device = name
    loadMethods()
    tools = toolsFor(device)
    toolIndex, toolScroll = 1, 0
    toolStatus = nil
    view = (#tools > 0) and "tools" or "methods"
  end

  local function backFromMethods()
    view = (#tools > 0) and "tools" or "devices"
  end

  ------------------------------------------------------------------
  -- input
  ------------------------------------------------------------------

  local function askArgs(method)
    local width, height = term.getSize()
    ui.fill(term, 1, 2, width, 5, theme.colour.muted)
    ui.text(term, 2, 2, ui.clip(method .. "(...)", width - 2), colours.black, theme.colour.muted)
    ui.text(term, 2, 3, "Arguments, comma separated:", theme.colour.mutedText, theme.colour.muted)
    ui.text(term, 2, 4, 'e.g. 1, "text", true', theme.colour.mutedText, theme.colour.muted)
    ui.fill(term, 2, 5, width - 2, 1, colours.white)
    term.setCursorPos(2, 5)
    term.setBackgroundColour(colours.white)
    term.setTextColour(colours.black)
    return read(nil, lastArgs)
  end

  local function invoke(method)
    local typed = askArgs(method)
    if typed and typed ~= "" then lastArgs[#lastArgs + 1] = typed end
    local args, count = parseArgs(typed)

    local returned = table.pack(pcall(peripheral.call, device, method,
      table.unpack(args, 1, count)))
    result = {
      method = method,
      args = typed or "",
      ok = returned[1],
      values = {},
    }
    for i = 2, returned.n do
      result.values[#result.values + 1] = show(returned[i])
    end
    if #result.values == 0 then
      result.values[1] = result.ok and "(no return value)" or "(no message)"
    end
    view = "result"
  end

  -- Runs a tool; its outcome lands in the status line, not a separate view,
  -- so quick actions like "Clear screen" cost one keypress.
  local function runTool(tool)
    local ok, message = pcall(tool.run, device)
    if ok then
      if message then toolStatus = { text = message, ok = true } end
    else
      toolStatus = { text = tostring(message), ok = false }
    end
  end

  ------------------------------------------------------------------
  -- drawing
  ------------------------------------------------------------------

  local function drawDevices()
    local width, height = term.getSize()
    local rows = height - 2

    if index < scroll + 1 then scroll = index - 1 end
    if index > scroll + rows then scroll = index - rows end
    if scroll < 0 then scroll = 0 end

    term.setBackgroundColour(theme.colour.window)
    term.clear()
    ui.row(term, 1, 1, width, " Devices (" .. #names .. ")",
      theme.colour.accentText, theme.colour.accent)

    if #names == 0 then
      ui.text(term, 2, 3, "Nothing attached.", theme.colour.mutedText, theme.colour.window)
      ui.text(term, 2, 5, "Place a modem, speaker, drive,", theme.colour.mutedText, theme.colour.window)
      ui.text(term, 2, 6, "printer or screen against the", theme.colour.mutedText, theme.colour.window)
      ui.text(term, 2, 7, "computer, or use a wired modem.", theme.colour.mutedText, theme.colour.window)
    end

    for row = 1, rows do
      local entry = scroll + row
      local name = names[entry]
      if name then
        local on = (entry == index)
        local kind = peripherals.typeText(name)
        local room = math.max(1, width - #kind - 3)
        ui.row(term, 1, row + 1, width - 1,
          " " .. ui.pad(ui.clip(name, room), room) .. " " .. kind,
          on and theme.colour.accentText or theme.colour.windowText,
          on and theme.colour.accent or theme.colour.window)
      end
    end
    ui.scrollbar(term, width, 2, rows, #names, scroll, theme.colour.muted, theme.colour.accent)

    ui.row(term, 1, height, width, " [Enter] open   [R] refresh",
      theme.colour.mutedText, theme.colour.muted)
  end

  local function drawTools()
    local width, height = term.getSize()

    term.setBackgroundColour(theme.colour.window)
    term.clear()
    ui.row(term, 1, 1, width, " < " .. ui.clip(device or "?", width - 4),
      theme.colour.accentText, theme.colour.accent)

    local ok, info = pcall(infoFor, device)
    if not ok or type(info) ~= "table" then info = {} end

    local y = 2
    for _, line in ipairs(info) do
      if y >= height - 3 then break end
      ui.text(term, 2, y, ui.clip(line, width - 2), theme.colour.mutedText, theme.colour.window)
      y = y + 1
    end
    if #info > 0 then y = y + 1 end
    toolsTop = y

    -- List rows run from toolsTop to height - 2; height - 1 is the status line.
    local rows = math.max(1, height - toolsTop - 1)
    if toolIndex < toolScroll + 1 then toolScroll = toolIndex - 1 end
    if toolIndex > toolScroll + rows then toolScroll = toolIndex - rows end
    if toolScroll < 0 then toolScroll = 0 end

    for row = 1, rows do
      local entry = toolScroll + row
      local tool = tools[entry]
      if tool then
        local on = (entry == toolIndex)
        ui.row(term, 1, toolsTop + row - 1, width - 1, " " .. ui.clip(tool.label, width - 3),
          on and theme.colour.accentText or theme.colour.windowText,
          on and theme.colour.accent or theme.colour.window)
      end
    end
    ui.scrollbar(term, width, toolsTop, rows, #tools, toolScroll,
      theme.colour.muted, theme.colour.accent)

    if toolStatus then
      ui.text(term, 2, height - 1, ui.clip(toolStatus.text, width - 2),
        toolStatus.ok and theme.colour.ok or theme.colour.danger, theme.colour.window)
    end

    ui.row(term, 1, height, width, " [Enter] run   [M] methods   [Backspace] back",
      theme.colour.mutedText, theme.colour.muted)
  end

  local function drawMethods()
    local width, height = term.getSize()
    local rows = height - 2

    if methodIndex < methodScroll + 1 then methodScroll = methodIndex - 1 end
    if methodIndex > methodScroll + rows then methodScroll = methodIndex - rows end
    if methodScroll < 0 then methodScroll = 0 end

    term.setBackgroundColour(theme.colour.window)
    term.clear()
    ui.row(term, 1, 1, width, " < " .. ui.clip(device or "?", width - 4),
      theme.colour.accentText, theme.colour.accent)

    if #methods == 0 then
      ui.text(term, 2, 3, "No methods reported.", theme.colour.mutedText, theme.colour.window)
    end

    for row = 1, rows do
      local entry = methodScroll + row
      local method = methods[entry]
      if method then
        local on = (entry == methodIndex)
        ui.row(term, 1, row + 1, width - 1, " " .. ui.clip(method, width - 3),
          on and theme.colour.accentText or theme.colour.windowText,
          on and theme.colour.accent or theme.colour.window)
      end
    end
    ui.scrollbar(term, width, 2, rows, #methods, methodScroll,
      theme.colour.muted, theme.colour.accent)

    ui.row(term, 1, height, width, " [Enter] call   [Backspace] back",
      theme.colour.mutedText, theme.colour.muted)
  end

  local function drawResult()
    -- Only reachable after invoke() has run, but a view left stale by a
    -- detach should fall back rather than index a nil.
    if not result then
      view = "devices"
      return
    end
    local width, height = term.getSize()
    term.setBackgroundColour(theme.colour.window)
    term.clear()
    ui.row(term, 1, 1, width, " " .. ui.clip(result.method .. "(" .. result.args .. ")", width - 2),
      theme.colour.accentText, result.ok and theme.colour.accent or theme.colour.danger)

    ui.text(term, 2, 2, result.ok and "returned" or "error",
      result.ok and theme.colour.ok or theme.colour.danger, theme.colour.window)

    local y = 4
    for _, value in ipairs(result.values) do
      for _, line in ipairs(ui.wrap(value, width - 2)) do
        if y > height - 1 then break end
        ui.text(term, 2, y, line, theme.colour.windowText, theme.colour.window)
        y = y + 1
      end
    end

    ui.row(term, 1, height, width, " [Enter] again   [Backspace] back",
      theme.colour.mutedText, theme.colour.muted)
  end

  local function draw()
    if view == "devices" then drawDevices()
    elseif view == "tools" then drawTools()
    elseif view == "methods" then drawMethods()
    else drawResult() end
  end

  ------------------------------------------------------------------

  refresh()
  draw()

  while true do
    local event = { os.pullEvent() }
    local name = event[1]

    if name == "key" then
      local key = event[2]

      if view == "devices" then
        if key == keys.down then index = math.min(#names, index + 1)
        elseif key == keys.up then index = math.max(1, index - 1)
        elseif key == keys.r then refresh()
        elseif key == keys.enter and names[index] then
          openDevice(names[index])
        end

      elseif view == "tools" then
        if key == keys.down then toolIndex = math.min(#tools, toolIndex + 1)
        elseif key == keys.up then toolIndex = math.max(1, toolIndex - 1)
        elseif key == keys.backspace then view = "devices"
        elseif key == keys.m then view = "methods"
        elseif key == keys.enter and tools[toolIndex] then
          runTool(tools[toolIndex])
        end

      elseif view == "methods" then
        if key == keys.down then methodIndex = math.min(#methods, methodIndex + 1)
        elseif key == keys.up then methodIndex = math.max(1, methodIndex - 1)
        elseif key == keys.backspace then backFromMethods()
        elseif key == keys.enter and methods[methodIndex] then
          invoke(methods[methodIndex])
        end

      else
        if key == keys.backspace then view = "methods"
        elseif key == keys.enter and result then invoke(result.method)
        end
      end
      draw()

    elseif name == "mouse_click" then
      local my = event[4]
      local _, height = term.getSize()
      if view == "devices" then
        local clicked = scroll + my - 1
        if names[clicked] then
          if clicked == index then
            openDevice(names[clicked])
          else
            index = clicked
          end
        end
      elseif view == "tools" then
        if my == 1 then
          view = "devices"
        elseif my == height then
          view = "methods"
        elseif my >= toolsTop and my < height - 1 then
          local clicked = toolScroll + my - toolsTop + 1
          if tools[clicked] then
            if clicked == toolIndex then runTool(tools[clicked]) else toolIndex = clicked end
          end
        end
      elseif view == "methods" then
        if my == 1 then
          backFromMethods()
        else
          local clicked = methodScroll + my - 1
          if methods[clicked] then
            if clicked == methodIndex then invoke(methods[clicked]) else methodIndex = clicked end
          end
        end
      else
        if my == 1 then view = "methods" end
      end
      draw()

    elseif name == "mouse_scroll" then
      if view == "devices" then
        index = math.max(1, math.min(#names, index + event[2]))
      elseif view == "tools" then
        toolIndex = math.max(1, math.min(#tools, toolIndex + event[2]))
      elseif view == "methods" then
        methodIndex = math.max(1, math.min(#methods, methodIndex + event[2]))
      end
      draw()

    elseif name == "peripheral" or name == "peripheral_detach" then
      refresh()
      -- The device being inspected may have just been broken off.
      if device and not peripheral.isPresent(device) then view = "devices" end
      draw()

    elseif name == "term_resize" then
      draw()
    end
  end
end

return app