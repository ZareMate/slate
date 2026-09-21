--[[ Store - browse and install apps.

  The catalogue is a JSON index next to the update source:

      <base>/store/index.json
        { "apps": [ { "id","title","file","w","h","blurb","icon":[..],"api" } ] }

  Installing downloads <base>/store/<file> into apps/<id>.lua and registers it
  with the catalog. The download is checked before anything is written, and a
  built-in app can never be overwritten by a store entry claiming its id.
]]

local use = ...
local ui = use("system/ui")
local theme = use("system/theme")
local catalog = use("system/catalog")
local update = use("system/update")
local compat = use("system/compat")

local app = {}

local ROW_H = 3                 -- title row, blurb row, gap

local function fetch(url)
  if not http then return nil, "HTTP is disabled" end
  local response, err = http.get(url)
  if not response then return nil, tostring(err) end
  local body = response.readAll()
  response.close()
  return body
end

function app.run(ctx)
  local root = ctx.root()
  local entries = {}
  local index = 1
  local scroll = 0                 -- first visible entry, 0-based
  local state = "loading"
  local problem = nil
  local notice, noticeUntil = nil, 0
  local buttons = {}

  local function say(text)
    notice, noticeUntil = text, os.clock() + 4
  end

  local function visibleRows()
    local _, height = term.getSize()
    return math.max(1, math.floor((height - 3) / ROW_H))
  end

  -- Keeps the selection on screen. This is what was missing before: index
  -- moved but scroll never did, so anything past the first page was
  -- unreachable.
  local function follow()
    local rows = visibleRows()
    if index < scroll + 1 then scroll = index - 1 end
    if index > scroll + rows then scroll = index - rows end
    scroll = ui.clampScroll(scroll, #entries, rows)
  end

  local function refresh()
    state = "loading"
    entries = {}
    index, scroll = 1, 0
    local base = update.url()
    if not base then
      state, problem = "failed", "No store source set (Settings > Updates)"
      return
    end
    local body, err = fetch(base .. "/store/index.json")
    if not body then
      state, problem = "failed", err
      return
    end
    local parsed = textutils.unserialiseJSON(body)
    if type(parsed) ~= "table" or type(parsed.apps) ~= "table" then
      state, problem = "failed", "Store index is not valid"
      return
    end
    entries = parsed.apps
    state = "list"
  end

  local function install(entry)
    if catalog.isBuiltin(entry.id) then
      say("That id belongs to a built-in app")
      return
    end
    if type(entry.id) ~= "string" or not entry.id:match("^[%w_-]+$") then
      say("Bad app id in the index")
      return
    end
    if type(entry.file) ~= "string" or entry.file:find("%.%.") or entry.file:match("^/") then
      say("Bad file name in the index")
      return
    end
    if entry.api and not compat.satisfies(entry.api) then
      say(compat.tooNew(entry.api))
      return
    end

    state = "busy"
    local base = update.url()
    local source = type(entry.source) == "string" and entry.source:gsub("/+$", "") or (base .. "/store")
    local body, err = fetch(source .. "/" .. entry.file)
    if not body then
      state = "list"
      say("Download failed: " .. tostring(err))
      return
    end

    -- Only touch the disk once the whole file is in hand.
    local module = "apps/" .. entry.id
    local path = fs.combine(root, module .. ".lua")
    local handle, openErr = fs.open(path, "w")
    if not handle then
      state = "list"
      say("Could not write: " .. tostring(openErr))
      return
    end
    handle.write(body)
    handle.close()

    local registered, registerErr = catalog.install({
      id = entry.id,
      title = entry.title or entry.id,
      module = module,
      w = tonumber(entry.w) or 40,
      h = tonumber(entry.h) or 14,
      icon = type(entry.icon) == "table" and entry.icon or nil,
      single = entry.single == true,
      api = tonumber(entry.api),
    }, root)

    if not registered then
      pcall(fs.delete, path)
      state = "list"
      say("Could not register app: " .. tostring(registerErr))
      return
    end
    state = "list"
    say("Installed " .. (entry.title or entry.id))
    ctx.notify((entry.title or entry.id) .. " installed")
  end

  local function remove(entry)
    local ok, err = catalog.uninstall(entry.id, root)
    say(ok and ("Removed " .. (entry.title or entry.id)) or tostring(err))
  end

  local function draw()
    local width, height = term.getSize()
    buttons = {}
    follow()

    term.setBackgroundColour(theme.colour.window)
    term.clear()
    ui.row(term, 1, 1, width, " " .. ui.spaced("Store"),
      theme.colour.accentText, theme.colour.accent)

    if state == "loading" then
      ui.text(term, 2, 3, "Loading catalogue...", theme.colour.windowText, theme.colour.window)

    elseif state == "busy" then
      ui.text(term, 2, 3, "Installing...", theme.colour.windowText, theme.colour.window)

    elseif state == "failed" then
      ui.text(term, 2, 3, "Store unavailable", theme.colour.danger, theme.colour.window)
      local y = 5
      for _, line in ipairs(ui.wrap(problem or "", width - 2)) do
        if y > height - 3 then break end
        ui.text(term, 2, y, line, theme.colour.mutedText, theme.colour.window)
        y = y + 1
      end

    elseif #entries == 0 then
      ui.text(term, 2, 3, "No apps published yet.", theme.colour.mutedText, theme.colour.window)

    else
      local rows = visibleRows()
      for offset = 0, rows - 1 do
        local position = scroll + offset + 1
        local entry = entries[position]
        if not entry then break end

        local y = 3 + offset * ROW_H
        local on = (position == index)
        local have = catalog.isInstalled(entry.id)
        local tooNew = entry.api and not compat.satisfies(entry.api)
        local tag = have and "installed" or (tooNew and "too new" or "")
        local room = math.max(1, width - #tag - 5)

        ui.row(term, 1, y, width - 1,
          (on and (ui.glyph.right .. " ") or "  ")
          .. ui.pad(ui.clip(entry.title or entry.id, room), room) .. " " .. tag,
          on and theme.colour.accentText or theme.colour.windowText,
          on and theme.colour.accent or theme.colour.window)

        ui.text(term, 4, y + 1, ui.clip(entry.blurb or "", width - 5),
          theme.colour.mutedText, theme.colour.window)
      end

      ui.scrollbar(term, width, 3, rows * ROW_H, #entries * ROW_H, scroll * ROW_H,
        theme.colour.muted, theme.colour.accent)
    end

    -- Buttons rather than a line of keyboard hints.
    local current = entries[index]
    local installed = current and catalog.isInstalled(current.id)
    if state == "list" and current then
      buttons = ui.buttonRow(term, 2, height - 1, {
        {
          name = "action",
          label = installed and "Remove" or "Install",
          bg = installed and theme.colour.danger or theme.colour.ok,
          fg = colours.white,
          disabled = (not installed) and current.api
            and not compat.satisfies(current.api) or false,
        },
        { name = "refresh", label = "Refresh", bg = theme.colour.muted },
      })
    elseif state == "failed" then
      buttons = ui.buttonRow(term, 2, height - 1, {
        { name = "refresh", label = "Try again", bg = theme.colour.muted },
      })
    end

    if notice and os.clock() < noticeUntil then
      ui.row(term, 1, height, width, " " .. ui.clip(notice, width - 2),
        colours.white, theme.colour.ok)
    else
      ui.row(term, 1, height, width,
        " " .. #entries .. " apps   arrows or scroll wheel",
        theme.colour.mutedText, theme.colour.muted)
    end
  end

  local function act()
    local entry = entries[index]
    if not entry then return end
    if catalog.isInstalled(entry.id) then
      remove(entry)
    else
      draw()
      install(entry)
    end
  end

  refresh()
  draw()
  local ticker = os.startTimer(60)

  while true do
    local event, a, mx, my = os.pullEvent()

    if event == "timer" and a == ticker then
      ticker = os.startTimer(60)
      -- Quietly: a catalogue that reloads under your cursor should not also
      -- throw away where you were.
      if state == "list" or state == "failed" then
        local keep = entries[index] and entries[index].id
        refresh()
        if keep then
          for position, entry in ipairs(entries) do
            if entry.id == keep then index = position break end
          end
        end
      end
      draw()

    elseif event == "key" then
      local rows = visibleRows()
      if a == keys.down then index = math.min(#entries, index + 1)
      elseif a == keys.up then index = math.max(1, index - 1)
      elseif a == keys.pageDown then index = math.min(#entries, index + rows)
      elseif a == keys.pageUp then index = math.max(1, index - rows)
      elseif a == keys.home then index = 1
      elseif a == keys["end"] then index = math.max(1, #entries)
      elseif a == keys.r then refresh()
      elseif a == keys.enter then act()
      elseif a == keys.delete and entries[index] then remove(entries[index])
      end
      draw()

    elseif event == "mouse_scroll" then
      -- The wheel moves the page; the selection follows it rather than the
      -- other way round, which is what people expect from a list.
      local rows = visibleRows()
      scroll = ui.clampScroll(scroll + a, #entries, rows)
      index = math.max(scroll + 1, math.min(scroll + rows, index))
      draw()

    elseif event == "mouse_click" then
      if ui.inButton(buttons.action, mx, my) then
        act()
      elseif ui.inButton(buttons.refresh, mx, my) then
        refresh()
      else
        local clicked = scroll + math.floor((my - 3) / ROW_H) + 1
        if entries[clicked] and my >= 3 then
          if clicked == index then act() else index = clicked end
        end
      end
      draw()

    elseif event == "term_resize" then
      draw()
    end
  end
end

return app
