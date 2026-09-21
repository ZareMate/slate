--[[ Stasis - pearl chamber control.

  A client for the stasis server's ComputerCraft API:

    GET  /api/computer/chambers            all reported chambers
    GET  /api/computer/chambers?base=1     one base
    GET  /api/computer/chambers?player=X   that player's chamber
    POST /api/computer/pull  {player, base?}

  Authenticated with X-Stasis-Token. The token is NOT in this file: it is
  asked for on first run and kept in CC's settings, because this file is
  published to a public repository and a committed token is a leaked token.

  If the server offers a websocket the app subscribes to it for live chamber
  updates, and falls back to refreshing by hand when it cannot connect. The
  connection is opened asynchronously so the window never hangs waiting on it.
]]

local use = ...
local ui = use("system/ui")
local theme = use("system/theme")

local app = {}

local URL_SETTING = "slate.stasis.url"
local WS_SETTING = "slate.stasis.ws"
local TOKEN_SETTING = "slate.stasis.token"

local STATUS_COLOUR = {
  ready = colours.lime,
  armed = colours.lime,
  empty = colours.grey,
  pulled = colours.orange,
  offline = colours.red,
  error = colours.red,
}

local function setting(name)
  local ok, value = pcall(settings.get, name)
  if ok and type(value) == "string" and value ~= "" then return value end
  return nil
end

local function save(name, value)
  pcall(function()
    if value == nil or value == "" then settings.unset(name) else settings.set(name, value) end
    settings.save()
  end)
end

--------------------------------------------------------------------------

function app.run(ctx)
  local base = (setting(URL_SETTING) or ""):gsub("/+$", "")
  local wsUrl = setting(WS_SETTING)
  local token = setting(TOKEN_SETTING)

  local chambers = {}
  local index = 1
  local scroll = 0
  local state = "idle"            -- idle | loading | failed
  local problem = nil
  local confirming = nil
  local socket = nil
  local live = false
  local notice, noticeUntil = nil, 0
  local buttons = {}

  local function say(text)
    notice, noticeUntil = text, os.clock() + 4
  end

  local function headers()
    return { ["X-Stasis-Token"] = token, ["Content-Type"] = "application/json" }
  end

  ------------------------------------------------------------------
  -- server
  ------------------------------------------------------------------

  local function request(path, body)
    if not http then return nil, "HTTP is disabled" end
    if base == "" then return nil, "No server set" end
    if not token then return nil, "No token set" end

    local url = base .. path
    local ok, response = pcall(function()
      if body then return http.post(url, body, headers()) end
      return http.get(url, headers())
    end)
    if not ok or not response then return nil, "Could not reach " .. base end

    local status = response.getResponseCode()
    local raw = response.readAll()
    response.close()

    local parsed = nil
    if raw and raw ~= "" then
      local parsedOk, value = pcall(textutils.unserialiseJSON, raw)
      if parsedOk then parsed = value end
    end

    if status < 200 or status >= 300 then
      local detail = "HTTP " .. tostring(status)
      if type(parsed) == "table" and parsed.error then
        detail = detail .. ": " .. tostring(parsed.error)
      end
      return nil, detail
    end
    return parsed or {}
  end

  local function refresh()
    state = "loading"
    local data, err = request("/api/computer/chambers")
    if not data then
      state, problem = "failed", err
      return
    end
    chambers = type(data.chambers) == "table" and data.chambers or {}
    if index > #chambers then index = math.max(1, #chambers) end
    state = "idle"
  end

  local function pull(entry)
    -- base is sent only when the server reported one; omitting it lets the
    -- server fall back to the player's configured default, which is what its
    -- API is designed to do.
    local payload = { player = entry.player }
    if entry.base then payload.base = entry.base end

    local data, err = request("/api/computer/pull", textutils.serialiseJSON(payload))
    if not data then
      say("Pull failed: " .. tostring(err))
      return
    end
    -- A player at several bases with no default comes back with a list
    -- instead of a pull; that is an answer, not a failure.
    if type(data.bases) == "table" and #data.bases > 0 then
      local names = {}
      for _, item in ipairs(data.bases) do
        names[#names + 1] = tostring(type(item) == "table" and (item.baseName or item.base) or item)
      end
      say("Pick a base: " .. table.concat(names, ", "))
      return
    end
    say("Pulled " .. tostring(entry.player))
    ctx.notify("Pulled " .. tostring(entry.player))
    refresh()
  end

  ------------------------------------------------------------------
  -- live updates
  ------------------------------------------------------------------

  local function connectLive()
    if not wsUrl or not http or not http.websocketAsync then return end
    -- Async: a server that never answers must not freeze the window.
    pcall(http.websocketAsync, wsUrl, { ["X-Stasis-Token"] = token })
  end

  ctx.onClose(function()
    if socket then pcall(socket.close) end
  end)

  ------------------------------------------------------------------
  -- setup
  ------------------------------------------------------------------

  local function ask(label, value, masked)
    local width, height = term.getSize()
    ui.panel(term, 2, 4, width - 2, 6, theme.colour.muted, theme.colour.accent)
    ui.text(term, 4, 5, label, colours.black, theme.colour.muted)
    ui.fill(term, 4, 7, width - 6, 1, colours.white)
    term.setCursorPos(4, 7)
    term.setBackgroundColour(colours.white)
    term.setTextColour(colours.black)
    if masked then return read("*") end
    return read(nil, nil, nil, value)
  end

  local function setup()
    local url = ask("Server URL (http://host:4000):", base ~= "" and base or "http://")
    if url and url ~= "" then
      base = url:gsub("/+$", "")
      save(URL_SETTING, base)
    end
    -- Masked, and never drawn back: this file ends up in a public repo and
    -- the token should not be on screen either.
    local given = ask("Stasis token:", nil, true)
    if given and given ~= "" then
      token = given
      save(TOKEN_SETTING, given)
    end
    local ws = ask("Websocket for live updates (optional):", wsUrl or "wss://")
    if ws and ws ~= "" and ws ~= "wss://" then
      wsUrl = ws
      save(WS_SETTING, ws)
      connectLive()
    end
  end

  ------------------------------------------------------------------
  -- drawing
  ------------------------------------------------------------------

  local function rows()
    local _, height = term.getSize()
    return math.max(1, height - 3)
  end

  local function draw()
    local width, height = term.getSize()
    buttons = {}

    if index < scroll + 1 then scroll = index - 1 end
    if index > scroll + rows() then scroll = index - rows() end
    scroll = ui.clampScroll(scroll, #chambers, rows())

    term.setBackgroundColour(theme.colour.window)
    term.clear()
    ui.row(term, 1, 1, width, " " .. ui.spaced("Stasis")
      .. (live and "   live" or ""), theme.colour.accentText, theme.colour.accent)

    if base == "" or not token then
      ui.text(term, 2, 3, "Not set up yet.", theme.colour.windowText, theme.colour.window)
      ui.text(term, 2, 5, "Press S to enter the server", theme.colour.mutedText, theme.colour.window)
      ui.text(term, 2, 6, "address and your token.", theme.colour.mutedText, theme.colour.window)

    elseif state == "loading" then
      ui.text(term, 2, 3, "Loading chambers...", theme.colour.windowText, theme.colour.window)

    elseif state == "failed" then
      ui.text(term, 2, 3, "Cannot reach the server", theme.colour.danger, theme.colour.window)
      local y = 5
      for _, line in ipairs(ui.wrap(problem or "", width - 2)) do
        if y > height - 2 then break end
        ui.text(term, 2, y, line, theme.colour.mutedText, theme.colour.window)
        y = y + 1
      end

    elseif #chambers == 0 then
      ui.text(term, 2, 3, "No chambers reported.", theme.colour.mutedText, theme.colour.window)

    else
      for offset = 0, rows() - 1 do
        local entry = chambers[scroll + offset + 1]
        if not entry then break end
        local y = 2 + offset
        local on = (scroll + offset + 1 == index)

        local status = tostring(entry.status or "?")
        local tag = "#" .. tostring(entry.chamber or "?")
        local who = tostring(entry.player or entry.label or "(empty)")
        local room = math.max(1, width - #status - #tag - 5)

        ui.row(term, 1, y, width - 1,
          " " .. tag .. " " .. ui.pad(ui.clip(who, room), room) .. " " .. status,
          on and theme.colour.accentText or theme.colour.windowText,
          on and theme.colour.accent or theme.colour.window)

        if not on then
          ui.text(term, width - #status, y, status,
            STATUS_COLOUR[status] or theme.colour.mutedText, theme.colour.window)
        end
      end
      ui.scrollbar(term, width, 2, rows(), #chambers, scroll,
        theme.colour.muted, theme.colour.accent)
    end

    if confirming then
      ui.panel(term, 3, math.floor(height / 2) - 1, width - 6, 5,
        theme.colour.muted, theme.colour.danger)
      ui.centre(term, math.floor(height / 2),
        "Pull " .. ui.clip(tostring(confirming.player or "?"), 16) .. "?",
        colours.black, theme.colour.muted, 4, width - 8)
      ui.centre(term, math.floor(height / 2) + 1, "Y / N",
        theme.colour.mutedText, theme.colour.muted, 4, width - 8)
    end

    local ready = #chambers > 0 and chambers[index] and not confirming
    buttons = ui.buttonRow(term, 2, height - 1, {
      { name = "pull", label = "Pull", bg = theme.colour.danger, fg = colours.white,
        disabled = not ready },
      { name = "refresh", label = "Refresh", bg = theme.colour.muted },
      { name = "setup", label = "Setup", bg = theme.colour.muted },
    })

    if notice and os.clock() < noticeUntil then
      ui.row(term, 1, height, width, " " .. ui.clip(notice, width - 2),
        colours.white, theme.colour.ok)
    else
      ui.row(term, 1, height, width,
        " " .. #chambers .. " chambers   [S]etup  [R]efresh",
        theme.colour.mutedText, theme.colour.muted)
    end
  end

  ------------------------------------------------------------------

  if base == "" or not token then
    draw()
  else
    draw()
    refresh()
    connectLive()
  end
  draw()

  local ticker = os.startTimer(15)

  while true do
    local event = { os.pullEvent() }
    local name = event[1]

    if name == "timer" and event[2] == ticker then
      ticker = os.startTimer(15)
      -- A live socket means the server tells us; polling is the fallback.
      if not live and base ~= "" and token then refresh() end
      draw()

    elseif name == "websocket_success" and event[2] == wsUrl then
      socket = event[3]
      live = true
      say("Live updates connected")
      draw()

    elseif name == "websocket_failure" and event[2] == wsUrl then
      live = false
      say("Live updates unavailable")
      draw()

    elseif name == "websocket_closed" and event[2] == wsUrl then
      socket, live = nil, false
      draw()

    elseif name == "websocket_message" and event[2] == wsUrl then
      -- Any message means something moved; the list is the source of truth.
      refresh()
      draw()

    elseif name == "key" then
      local key = event[2]
      if confirming then
        if key == keys.y then
          local entry = confirming
          confirming = nil
          draw()
          pull(entry)
        elseif key ~= nil then
          confirming = nil
        end
        draw()
      else
        if key == keys.down then index = math.min(#chambers, index + 1)
        elseif key == keys.up then index = math.max(1, index - 1)
        elseif key == keys.r then draw(); refresh()
        elseif key == keys.s then setup(); draw(); refresh()
        elseif key == keys.enter and chambers[index] then
          confirming = chambers[index]
        end
        draw()
      end

    elseif name == "mouse_click" then
      local mx, my = event[3], event[4]
      if confirming then
        confirming = nil
      elseif ui.inButton(buttons.pull, mx, my) then
        confirming = chambers[index]
      elseif ui.inButton(buttons.refresh, mx, my) then
        draw()
        refresh()
      elseif ui.inButton(buttons.setup, mx, my) then
        setup()
        draw()
        refresh()
      else
        local clicked = scroll + my - 1
        if chambers[clicked] and my >= 2 then
          if clicked == index then confirming = chambers[clicked] else index = clicked end
        end
      end
      draw()

    elseif name == "mouse_scroll" then
      scroll = ui.clampScroll(scroll + event[2], #chambers, rows())
      index = math.max(scroll + 1, math.min(scroll + rows(), index))
      draw()

    elseif name == "term_resize" then
      draw()
    end
  end
end

return app
