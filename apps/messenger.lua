--[[ Messenger - talk to other computers over rednet.

  Needs a modem (wireless reaches anything in range; wired reaches whatever
  shares the cable network). Peers announce themselves on the "slate.msg"
  protocol, so the peer list fills in by itself rather than making you type
  computer ids.

  Two things here are less obvious than they look:

  * Messages that arrive while you are typing would be swallowed by read(),
    which pulls events itself and drops the ones it does not understand. So
    read() runs alongside a listener, and the listener restores the cursor
    afterwards so the half-typed line is not disturbed.
  * The modem is only closed on exit if this app was the one that opened it.
    Another program may be using rednet too.

  rednet is unauthenticated: anything in range can send you a message or read
  a broadcast, and can claim any name it likes.
]]

local use = ...
local ui = use("system/ui")
local theme = use("system/theme")
local peripherals = use("system/peripherals")

local app = {}

local PROTOCOL = "slate.msg"
local BROADCAST = "all"

local function panel(title, lines)
  local width, height = term.getSize()
  term.setBackgroundColour(theme.colour.window)
  term.clear()
  ui.row(term, 1, 1, width, " " .. title, colours.white, theme.colour.danger)
  for index, line in ipairs(lines) do
    ui.text(term, 2, index + 2, ui.clip(line, width - 2),
      theme.colour.windowText, theme.colour.window)
  end
  ui.row(term, 1, height, width, " Any key to close",
    theme.colour.mutedText, theme.colour.muted)
  os.pullEvent("key")
end

-- Wireless first: a wired modem only reaches computers on the same cable.
local function findModem()
  local wired = nil
  for _, name in ipairs(peripherals.names()) do
    if peripherals.isType(name, "modem") then
      local device = peripheral.wrap(name)
      local wireless = false
      if device and device.isWireless then
        local queried, value = pcall(device.isWireless)
        wireless = queried and value == true
      end
      if wireless then return name, true end
      wired = wired or name
    end
  end
  if wired then return wired, false end
  return nil, false
end

function app.run(ctx)
  local modem, wireless = findModem()
  if not modem then
    return panel("No modem", {
      "Messenger talks over rednet, which",
      "needs a modem.",
      "",
      "Attach a wireless modem to reach any",
      "computer in range, or a wired modem",
      "to reach others on the same cable.",
    })
  end

  local alreadyOpen = rednet.isOpen(modem)
  if not alreadyOpen then
    local ok, err = pcall(rednet.open, modem)
    if not ok then
      return panel("Could not open rednet", { tostring(err) })
    end
  end

  local me = os.getComputerID()
  local myName = os.getComputerLabel() or ("computer " .. me)

  pcall(rednet.host, PROTOCOL, myName)

  ctx.onClose(function()
    pcall(rednet.unhost, PROTOCOL)
    -- Only hand the modem back if we were the ones who took it.
    if not alreadyOpen then pcall(rednet.close, modem) end
  end)

  ------------------------------------------------------------------
  -- state
  ------------------------------------------------------------------

  local peers = {}              -- [id] = { id, name, unread }
  local logs = { [BROADCAST] = {} }
  local view = "peers"          -- or "chat"
  local target = nil            -- peer id, or BROADCAST
  local index = 1
  local scroll = 0
  local chatScroll = 0
  local history = {}
  local notice = nil
  local noticeUntil = 0

  -- Counters exist so a silent failure can be told apart from a quiet network.
  -- modem vs rednet is the diagnostic that matters: raw modem traffic arriving
  -- with no rednet messages means the daemon is not converting for this modem.
  local stats = { modem = 0, rednet = 0, mine = 0, sent = 0, lastFrom = "-" }
  local announceTimer = nil

  local function say(text)
    notice = text
    noticeUntil = os.clock() + 3
  end

  local function totalUnread()
    local count = 0
    for _, peer in pairs(peers) do count = count + (peer.unread or 0) end
    return count
  end

  local function retitle()
    local unread = totalUnread()
    ctx.setTitle(unread > 0 and ("Messenger (" .. unread .. ")") or "Messenger")
  end

  local function peerList()
    local list = { { id = BROADCAST, name = "Everyone", unread = 0 } }
    local ids = {}
    for id in pairs(peers) do ids[#ids + 1] = id end
    table.sort(ids)
    for _, id in ipairs(ids) do list[#list + 1] = peers[id] end
    return list
  end

  local function logFor(id)
    logs[id] = logs[id] or {}
    return logs[id]
  end

  local function append(id, who, text)
    local entry = { who = who, text = text, time = textutils.formatTime(os.time(), true) }
    local log = logFor(id)
    log[#log + 1] = entry
    -- Keep memory bounded; this is a chat window, not an archive.
    if #log > 200 then table.remove(log, 1) end
  end

  local function seePeer(id, name)
    if id == me then return end
    local peer = peers[id]
    if peer then
      if name then peer.name = name end
    else
      peers[id] = { id = id, name = name or ("computer " .. id), unread = 0 }
    end
  end

  ------------------------------------------------------------------
  -- drawing
  ------------------------------------------------------------------

  local function drawPeers()
    local width, height = term.getSize()
    local list = peerList()
    local rows = height - 2

    if index > #list then index = #list end
    if index < 1 then index = 1 end
    if index < scroll + 1 then scroll = index - 1 end
    if index > scroll + rows then scroll = index - rows end
    if scroll < 0 then scroll = 0 end

    term.setBackgroundColour(theme.colour.window)
    term.clear()
    ui.row(term, 1, 1, width, " " .. ui.clip(myName .. "  #" .. me, width - 2),
      theme.colour.accentText, theme.colour.accent)

    if #list == 1 then
      ui.text(term, 2, 3, "No other computers yet.", theme.colour.mutedText, theme.colour.window)
      ui.text(term, 2, 5, "They need Messenger open too,", theme.colour.mutedText, theme.colour.window)
      ui.text(term, 2, 6, wireless and "and to be in modem range."
        or "and to share this cable network.", theme.colour.mutedText, theme.colour.window)
      ui.text(term, 2, 8, "You can still message Everyone.", theme.colour.mutedText, theme.colour.window)
    end

    for row = 1, rows do
      local entry = list[scroll + row]
      if entry then
        local on = (scroll + row == index)
        local bg = on and theme.colour.accent or theme.colour.window
        local fg = on and theme.colour.accentText or theme.colour.windowText
        local tag = entry.id == BROADCAST and "*" or ("#" .. entry.id)
        local unread = (entry.unread or 0) > 0 and ("(" .. entry.unread .. ")") or ""
        local room = width - #tag - #unread - 4
        ui.row(term, 1, row + 1, width,
          " " .. tag .. " " .. ui.pad(ui.clip(entry.name, room), room) .. " " .. unread, fg, bg)
      end
    end

    ui.scrollbar(term, width, 2, rows, #list, scroll, theme.colour.muted, theme.colour.accent)

    if notice and os.clock() < noticeUntil then
      ui.row(term, 1, height, width, " " .. ui.clip(notice, width - 2),
        colours.white, theme.colour.ok)
    else
      ui.row(term, 1, height, width, " [Enter] open  [R] find  [D] why?",
        theme.colour.mutedText, theme.colour.muted)
    end
  end

  -- Renders the conversation into wrapped lines, newest at the bottom.
  local function chatLines(width)
    local out = {}
    for _, entry in ipairs(logFor(target)) do
      local prefix = entry.who == "me" and "you" or entry.who
      local wrapped = ui.wrap(prefix .. ": " .. entry.text, width)
      for _, line in ipairs(wrapped) do
        out[#out + 1] = { text = line, mine = entry.who == "me" }
      end
    end
    return out
  end

  local function drawChat(keepCursor)
    local width, height = term.getSize()
    local cx, cy = term.getCursorPos()
    local fg, bg = term.getTextColour(), term.getBackgroundColour()

    local name = target == BROADCAST and "Everyone"
      or ((peers[target] and peers[target].name) or ("computer " .. tostring(target)))
    local rows = height - 3
    local lines = chatLines(width - 2)
    local maxScroll = math.max(0, #lines - rows)
    if chatScroll > maxScroll then chatScroll = maxScroll end
    if chatScroll < 0 then chatScroll = 0 end

    term.setBackgroundColour(theme.colour.window)
    term.clear()
    ui.row(term, 1, 1, width, " < " .. ui.clip(name, width - 4),
      theme.colour.accentText, theme.colour.accent)

    -- Newest at the bottom. chatScroll counts lines back from the newest, and
    -- a short conversation sits at the base of the pane rather than the top.
    local total = #lines
    local first = math.max(1, total - rows + 1 - chatScroll)
    local count = math.min(rows, total - first + 1)
    for i = 1, count do
      local line = lines[first + i - 1]
      ui.text(term, 2, 1 + (rows - count) + i, line.text,
        line.mine and theme.colour.accent or theme.colour.windowText, theme.colour.window)
    end

    ui.row(term, 1, height - 1, width, " > ", theme.colour.windowText, theme.colour.muted)
    ui.row(term, 1, height, width, " [Enter] write   [Backspace] back",
      theme.colour.mutedText, theme.colour.muted)

    if keepCursor then
      term.setTextColour(fg)
      term.setBackgroundColour(bg)
      term.setCursorPos(cx, cy)
    end
  end

  -- Everything needed to work out why nothing is arriving, on one screen.
  local function drawDiagnostics()
    local width, height = term.getSize()
    term.setBackgroundColour(theme.colour.window)
    term.clear()
    ui.row(term, 1, 1, width, " Diagnostics", theme.colour.accentText, theme.colour.accent)

    local openNow = false
    local okOpen, value = pcall(rednet.isOpen, modem)
    if okOpen then openNow = value == true end

    local lines = {
      { "modem", tostring(modem) },
      { "types", (function()
          local a, b = peripheral.getType(modem)
          return tostring(a) .. (b and ("," .. tostring(b)) or "")
        end)() },
      { "wireless", tostring(wireless) },
      { "rednet open", tostring(openNow) },
      { "my id", "#" .. me },
      { "my name", myName },
      { "protocol", PROTOCOL },
      { "modem msgs", tostring(stats.modem) },
      { "rednet msgs", tostring(stats.rednet) },
      { "ours", tostring(stats.mine) },
      { "sent", tostring(stats.sent) },
      { "last from", tostring(stats.lastFrom) },
      { "peers", tostring(#peerList() - 1) },
    }

    local y = 2
    for _, row in ipairs(lines) do
      if y > height - 1 then break end
      ui.text(term, 2, y, ui.pad(row[1], 12), theme.colour.mutedText, theme.colour.window)
      ui.text(term, 14, y, ui.clip(row[2], width - 15),
        theme.colour.windowText, theme.colour.window)
      y = y + 1
    end

    ui.row(term, 1, height, width, " [P]ing   [Backspace] back",
      theme.colour.mutedText, theme.colour.muted)
  end

  local function draw()
    if view == "peers" then drawPeers()
    elseif view == "diag" then drawDiagnostics()
    else drawChat(false) end
  end

  ------------------------------------------------------------------
  -- networking
  ------------------------------------------------------------------

  -- Re-announced on a timer, not just at startup: whichever computer opens
  -- Messenger first must still find the ones that come later, and a peer that
  -- reboots has to be re-learned without anyone pressing anything.
  local function announce()
    local ok = pcall(rednet.broadcast, { kind = "hello", name = myName }, PROTOCOL)
    if ok then stats.sent = stats.sent + 1 end
    announceTimer = os.startTimer(10)
  end

  local function deliver(sender, message)
    stats.mine = stats.mine + 1
    stats.lastFrom = "#" .. tostring(sender)
    if type(message) ~= "table" or type(message.kind) ~= "string" then return false end

    if message.kind == "hello" then
      seePeer(sender, type(message.name) == "string" and message.name or nil)
      pcall(rednet.send, sender, { kind = "here", name = myName }, PROTOCOL)
      return true

    elseif message.kind == "here" then
      seePeer(sender, type(message.name) == "string" and message.name or nil)
      return true

    elseif message.kind == "msg" and type(message.text) == "string" then
      seePeer(sender, type(message.name) == "string" and message.name or nil)
      local box = message.to == BROADCAST and BROADCAST or sender
      append(box, peers[sender] and peers[sender].name or ("computer " .. sender),
        message.text:sub(1, 400))
      -- Only count it unread if you are not already looking at it.
      if not (view == "chat" and target == box) then
        if peers[sender] then peers[sender].unread = (peers[sender].unread or 0) + 1 end
        local who = (peers[sender] and peers[sender].name) or ("#" .. sender)
        ctx.notify(who .. ": " .. message.text:sub(1, 40))
      end
      retitle()
      return true
    end
    return false
  end

  local function send(text)
    if text == nil or text == "" then return end
    local payload = { kind = "msg", name = myName, text = text, to = target }
    if target == BROADCAST then
      pcall(rednet.broadcast, payload, PROTOCOL)
    else
      local ok = pcall(rednet.send, target, payload, PROTOCOL)
      if not ok then say("Could not send") end
    end
    append(target, "me", text)
    history[#history + 1] = text
  end

  -- read() consumes events itself, so anything arriving mid-message would be
  -- lost. The listener runs beside it and puts the cursor back afterwards.
  local function compose()
    local width, height = term.getSize()
    local typed
    parallel.waitForAny(
      function()
        term.setCursorPos(4, height - 1)
        term.setBackgroundColour(theme.colour.muted)
        term.setTextColour(colours.black)
        typed = read(nil, history)
      end,
      function()
        while true do
          local event, sender, message, protocol = os.pullEvent()
          if event == "rednet_message" and protocol == PROTOCOL then
            if deliver(sender, message) then drawChat(true) end
          end
        end
      end
    )
    return typed
  end

  ------------------------------------------------------------------

  announce()
  retitle()
  draw()

  while true do
    local event = { os.pullEvent() }
    local name = event[1]

    if name == "modem_message" then
      -- Counted but not acted on. If this climbs while "rednet msgs" stays at
      -- zero, the modem is receiving but rednet is not open on it.
      stats.modem = stats.modem + 1
      if view == "diag" then draw() end

    elseif name == "rednet_message" then
      stats.rednet = stats.rednet + 1
      if event[4] == PROTOCOL and deliver(event[2], event[3]) then
        draw()
      elseif view == "diag" then
        draw()
      end

    elseif name == "timer" and event[2] == announceTimer then
      announce()
      if view == "diag" then draw() end

    elseif name == "key" then
      local key = event[2]

      if view == "diag" then
        if key == keys.backspace then view = "peers"
        elseif key == keys.p then announce(); say("Ping sent")
        end
        draw()

      elseif view == "peers" then
        local list = peerList()
        if key == keys.down then index = math.min(#list, index + 1); draw()
        elseif key == keys.up then index = math.max(1, index - 1); draw()
        elseif key == keys.r then
          announce()
          say("Looking for peers...")
          draw()
        elseif key == keys.d then
          view = "diag"
          draw()
        elseif key == keys.enter then
          local entry = list[index]
          if entry then
            target = entry.id
            if peers[target] then peers[target].unread = 0 end
            retitle()
            view = "chat"
            chatScroll = 0
            draw()
          end
        end

      else
        if key == keys.backspace then
          view = "peers"
          draw()
        elseif key == keys.up then chatScroll = chatScroll + 1; draw()
        elseif key == keys.down then chatScroll = math.max(0, chatScroll - 1); draw()
        elseif key == keys.enter then
          send(compose())
          chatScroll = 0
          draw()
        end
      end

    elseif name == "mouse_click" then
      local my = event[4]
      if view == "peers" then
        local list = peerList()
        local clicked = scroll + my - 1
        if list[clicked] then
          index = clicked
          target = list[clicked].id
          if peers[target] then peers[target].unread = 0 end
          retitle()
          view = "chat"
          chatScroll = 0
        end
        draw()
      elseif view == "diag" then
        if my == 1 then view = "peers" end
        draw()
      else
        local _, height = term.getSize()
        if my == 1 then
          view = "peers"
        elseif my == height - 1 then
          send(compose())
          chatScroll = 0
        end
        draw()
      end

    elseif name == "mouse_scroll" then
      if view == "peers" then
        local list = peerList()
        index = math.max(1, math.min(#list, index + event[2]))
      else
        chatScroll = math.max(0, chatScroll - event[2])
      end
      draw()

    elseif name == "term_resize" then
      draw()
    end
  end
end

return app
