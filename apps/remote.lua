--[[ Remote - see and drive another computer's desktop over rednet.

  Consent first, and it is not optional: nothing here can look at a computer
  that is not running this app with sharing switched on. The host generates a
  six-character key each time it starts sharing, and a viewer must send that
  exact key to get a single frame. Stop sharing and every viewer is dropped.

  How it works:

    HOST    registers a frame watcher with the kernel, so every row the
            compositor repaints is forwarded to connected viewers. Only
            changed rows go on the wire - the same trick that makes the local
            desktop smooth keeps this usable over rednet.

    VIEWER  paints the rows it receives and forwards your keys and clicks
            back, which the host injects with os.queueEvent so they arrive
            exactly like local input.

  The key is not encryption. Anything in modem range can see the traffic;
  this stops someone connecting, not someone listening.
]]

local use = ...
local ui = use("system/ui")
local theme = use("system/theme")
local kernel = use("system/kernel")
local peripherals = use("system/peripherals")
local screens = use("system/screens")

local app = {}

local PROTOCOL = "slate.remote"
local KEY_CHARS = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"   -- no I/O/0/1 to read aloud
local FRAME_GAP = 0.25

local function makeKey()
  local out = {}
  for index = 1, 6 do
    local at = math.random(1, #KEY_CHARS)
    out[index] = KEY_CHARS:sub(at, at)
  end
  return table.concat(out)
end

local function findModem()
  for _, name in ipairs(peripherals.names()) do
    if peripherals.isType(name, "modem") then return name end
  end
  return nil
end

function app.run(ctx)
  local modem = findModem()
  if not modem then
    local width, height = term.getSize()
    term.setBackgroundColour(theme.colour.window)
    term.clear()
    ui.row(term, 1, 1, width, " No modem", colours.white, theme.colour.danger)
    ui.text(term, 2, 3, "Remote needs a modem to reach", theme.colour.windowText, theme.colour.window)
    ui.text(term, 2, 4, "other computers.", theme.colour.windowText, theme.colour.window)
    ui.row(term, 1, height, width, " Any key to close",
      theme.colour.mutedText, theme.colour.muted)
    os.pullEvent("key")
    return
  end

  local weOpened = not rednet.isOpen(modem)
  if weOpened then pcall(rednet.open, modem) end

  local me = os.getComputerID()
  local mode = "menu"              -- menu | hosting | viewing
  local key = nil
  local viewers = {}               -- [id] = true
  local watcher = nil
  local lastSend = 0

  -- viewer state
  local hostId, typedKey = nil, ""
  local status = ""
  local canvas = nil               -- rows received from the host
  local wall = nil                 -- monitor showing the shared screen
  local wallSize = nil

  local function stopHosting()
    if watcher then
      kernel.unwatch(watcher)
      watcher = nil
    end
    for id in pairs(viewers) do
      pcall(rednet.send, id, { kind = "bye" }, PROTOCOL)
    end
    viewers = {}
    key = nil
  end

  ctx.onClose(function()
    if wall then pcall(screens.release, wall) end
    if watcher then pcall(kernel.unwatch, watcher) end
    for id in pairs(viewers) do pcall(rednet.send, id, { kind = "bye" }, PROTOCOL) end
    if weOpened then pcall(rednet.close, modem) end
  end)

  ------------------------------------------------------------------
  -- hosting
  ------------------------------------------------------------------

  local function sendRows(id, rows, w, h, full)
    pcall(rednet.send, id, {
      kind = "frame", rows = rows, w = w, h = h, full = full,
    }, PROTOCOL)
  end

  local function startHosting()
    key = makeKey()
    viewers = {}
    -- Every repaint is forwarded, but no faster than FRAME_GAP: rednet is not
    -- a video link and flooding it just makes both computers stutter.
    watcher = kernel.watch(function(changed, getLine, w, h)
      if not next(viewers) then return end
      local now = os.clock()
      if now - lastSend < FRAME_GAP then return end
      lastSend = now

      local rows = {}
      for _, y in ipairs(changed) do
        local text, fg, bg = getLine(y)
        rows[#rows + 1] = { y, text, fg, bg }
      end
      if #rows == 0 then return end
      for id in pairs(viewers) do sendRows(id, rows, w, h, false) end
    end)
    mode = "hosting"
  end

  local function acceptViewer(id, given)
    if not key or given ~= key then
      pcall(rednet.send, id, { kind = "denied" }, PROTOCOL)
      return false
    end
    viewers[id] = true
    local snapshot, w, h = kernel.snapshot()
    local rows = {}
    for y, row in ipairs(snapshot) do
      rows[#rows + 1] = { y, row[1], row[2], row[3] }
    end
    pcall(rednet.send, id, { kind = "accepted" }, PROTOCOL)
    sendRows(id, rows, w, h, true)
    return true
  end

  ------------------------------------------------------------------
  -- drawing
  ------------------------------------------------------------------

  local function drawMenu()
    local width, height = term.getSize()
    term.setBackgroundColour(theme.colour.window)
    term.clear()
    ui.row(term, 1, 1, width, " " .. ui.spaced("Remote"),
      theme.colour.accentText, theme.colour.accent)

    ui.text(term, 2, 3, "This computer is #" .. me,
      theme.colour.mutedText, theme.colour.window)

    ui.panel(term, 2, 5, width - 2, 4, theme.colour.muted, theme.colour.accent)
    ui.text(term, 4, 6, "[S] Share this screen", colours.black, theme.colour.muted)
    ui.text(term, 4, 7, "gives you a key to hand out", theme.colour.mutedText, theme.colour.muted)

    ui.panel(term, 2, 10, width - 2, 4, theme.colour.muted, theme.colour.accent)
    ui.text(term, 4, 11, "[V] View another computer", colours.black, theme.colour.muted)
    ui.text(term, 4, 12, "needs their id and key", theme.colour.mutedText, theme.colour.muted)

    ui.row(term, 1, height, width, " " .. status,
      theme.colour.mutedText, theme.colour.muted)
  end

  local function drawHosting()
    local width, height = term.getSize()
    term.setBackgroundColour(theme.colour.window)
    term.clear()
    ui.row(term, 1, 1, width, " Sharing", colours.white, theme.colour.ok)

    ui.centre(term, 3, "Your key", theme.colour.mutedText, theme.colour.window, 1, width)
    ui.centre(term, 5, " " .. (key or "?") .. " ", colours.black, colours.white, 1, width)
    ui.centre(term, 7, "id #" .. me, theme.colour.windowText, theme.colour.window, 1, width)

    local count = 0
    for _ in pairs(viewers) do count = count + 1 end
    ui.centre(term, 9, count == 0 and "nobody connected"
      or (count .. " watching"), theme.colour.mutedText, theme.colour.window, 1, width)

    ui.text(term, 2, 11, "They can see and control this", theme.colour.mutedText, theme.colour.window)
    ui.text(term, 2, 12, "computer while connected.", theme.colour.mutedText, theme.colour.window)

    ui.row(term, 1, height, width, " [X] stop sharing",
      theme.colour.mutedText, theme.colour.muted)
  end

  local function drawViewing()
    local width, height = term.getSize()
    if not canvas then
      term.setBackgroundColour(theme.colour.window)
      term.clear()
      ui.row(term, 1, 1, width, " Connecting...", theme.colour.accentText, theme.colour.accent)
      ui.text(term, 2, 3, status, theme.colour.mutedText, theme.colour.window)
      ui.row(term, 1, height, width, " [M] monitor   [X] disconnect",
        theme.colour.mutedText, theme.colour.muted)
      return
    end

    -- The host's screen is very likely bigger than this window, so it is
    -- clipped rather than scaled: a scaled character grid is unreadable.
    for y = 1, height - 1 do
      local row = canvas[y]
      if row then
        term.setCursorPos(1, y)
        term.blit(row[1]:sub(1, width), row[2]:sub(1, width), row[3]:sub(1, width))
      end
    end
    ui.row(term, 1, height, width,
      " #" .. tostring(hostId) .. (wall and ("  on " .. wall) or "")
      .. "   [M] monitor  [X] stop",
      colours.white, theme.colour.accent)
  end

  local function draw()
    if mode == "menu" then drawMenu()
    elseif mode == "hosting" then drawHosting()
    else drawViewing() end
  end

  ------------------------------------------------------------------
  -- viewer
  ------------------------------------------------------------------

  local function ask(label)
    local width, height = term.getSize()
    ui.fill(term, 1, height - 1, width, 1, colours.white)
    ui.text(term, 1, height - 1, label, colours.black, colours.white)
    term.setCursorPos(#label + 1, height - 1)
    term.setBackgroundColour(colours.white)
    term.setTextColour(colours.black)
    return read()
  end

  local function connect()
    local id = tonumber(ask(" computer id: "))
    if not id then status = "Not a number" return end
    typedKey = (ask(" key: ") or ""):upper()
    hostId = id
    canvas = nil
    status = "Asking #" .. id .. "..."
    mode = "viewing"
    pcall(rednet.send, id, { kind = "hello", key = typedKey }, PROTOCOL)
  end

  local function applyFrame(message)
    if message.full or not canvas then
      canvas = {}
      if wall then screens.clearClaimed(wall) end
    end
    for _, row in ipairs(message.rows or {}) do
      canvas[row[1]] = { row[2], row[3], row[4] }
      -- Straight onto the monitor at its own size. No clipping into a window
      -- and no scaling, which is the whole point of putting it on a screen.
      if wall then
        if not screens.blitRow(wall, row[1], row[2], row[3], row[4]) then
          wall, wallSize = nil, nil
          status = "Monitor went away"
        end
      end
    end
  end

  -- Cycles through the attached monitors and back to window-only.
  local function nextWall()
    local monitors = screens.available()
    if #monitors == 0 then
      status = "No monitor attached"
      return
    end
    local at = 0
    for position, name in ipairs(monitors) do
      if name == wall then at = position break end
    end
    if wall then screens.release(wall) end

    local pick = monitors[at + 1]
    if not pick then
      wall, wallSize = nil, nil
      status = "Showing in the window"
      return
    end
    local ok, why = screens.claim(pick)
    if not ok then
      wall, wallSize = nil, nil
      status = tostring(why)
      return
    end
    wall = pick
    local w, h = screens.claimedSize(pick)
    wallSize = w and (w .. "x" .. h) or nil
    status = "Showing on " .. pick
    -- Ask the host for a complete frame: the monitor is blank and only
    -- changed rows arrive from here on.
    pcall(rednet.send, hostId, { kind = "hello", key = typedKey }, PROTOCOL)
  end

  ------------------------------------------------------------------

  draw()

  while true do
    local event = { os.pullEvent() }
    local name = event[1]

    if name == "rednet_message" then
      local sender, message, protocol = event[2], event[3], event[4]
      if protocol == PROTOCOL and type(message) == "table" then

        if message.kind == "hello" and mode == "hosting" then
          if acceptViewer(sender, message.key) then
            ctx.notify("#" .. sender .. " connected")
          end
          draw()

        elseif message.kind == "accepted" and mode == "viewing" then
          status = "Connected"
          draw()

        elseif message.kind == "denied" and mode == "viewing" then
          status = "Wrong key, or they stopped sharing"
          mode = "menu"
          draw()

        elseif message.kind == "frame" and mode == "viewing" and sender == hostId then
          applyFrame(message)
          draw()

        elseif message.kind == "bye" then
          if mode == "viewing" and sender == hostId then
            status = "They stopped sharing"
            mode = "menu"
          else
            viewers[sender] = nil
          end
          draw()

        elseif message.kind == "input" and mode == "hosting" and viewers[sender] then
          -- Injected as real events, so the host cannot tell the difference
          -- between a remote key and one typed at the keyboard.
          local input = message.event
          if type(input) == "table" and type(input[1]) == "string" then
            os.queueEvent(input[1], input[2], input[3], input[4])
          end
        end
      end

    elseif name == "key" or name == "char" or name == "mouse_click" then
      if mode == "menu" then
        if name == "key" then
          if event[2] == keys.s then startHosting()
          elseif event[2] == keys.v then connect()
          end
          draw()
        end

      elseif mode == "hosting" then
        if name == "key" and event[2] == keys.x then
          stopHosting()
          mode = "menu"
          status = "Sharing stopped"
          draw()
        end

      elseif mode == "viewing" then
        if name == "key" and event[2] == keys.m then
          nextWall()
          draw()
        elseif name == "key" and event[2] == keys.x then
          pcall(rednet.send, hostId, { kind = "bye" }, PROTOCOL)
          if wall then screens.release(wall) end
          wall, wallSize = nil, nil
          mode = "menu"
          canvas = nil
          status = "Disconnected"
          draw()
        else
          pcall(rednet.send, hostId, {
            kind = "input",
            event = { name, event[2], event[3], event[4] },
          }, PROTOCOL)
        end
      end

    elseif name == "monitor_touch" and mode == "viewing" and event[2] == wall then
      -- The monitor is showing the host's desktop, so a touch on it is a
      -- click on the host, at exactly the coordinates shown.
      pcall(rednet.send, hostId, {
        kind = "input",
        event = { "mouse_click", 1, event[3], event[4] },
      }, PROTOCOL)

    elseif name == "term_resize" then
      draw()
    end
  end
end

return app
