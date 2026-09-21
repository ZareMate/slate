--[[ Store - browse and install apps.

  The catalogue is a JSON index next to the update source:

      <base>/store/index.json
        { "apps": [ { "id","title","file","w","h","blurb","icon":[..] } ] }

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
  local state = "loading"           -- loading | list | failed | busy
  local problem = nil
  local notice, noticeUntil = nil, 0

  local function say(text)
    notice, noticeUntil = text, os.clock() + 4
  end

  local function refresh()
    state = "loading"
    entries = {}
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
    if type(entry.file) ~= "string" or entry.file:find("%.%.") then
      say("Bad file name in the index")
      return
    end
    if entry.api and not compat.satisfies(entry.api) then
      say(compat.tooNew(entry.api))
      return
    end

    state = "busy"
    local base = update.url()
    local body, err = fetch(base .. "/store/" .. entry.file)
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

    catalog.install({
      id = entry.id,
      title = entry.title or entry.id,
      module = module,
      w = tonumber(entry.w) or 40,
      h = tonumber(entry.h) or 14,
      icon = type(entry.icon) == "table" and entry.icon or nil,
      single = entry.single == true,
      api = tonumber(entry.api),
    })
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
        if y > height - 1 then break end
        ui.text(term, 2, y, line, theme.colour.mutedText, theme.colour.window)
        y = y + 1
      end

    elseif #entries == 0 then
      ui.text(term, 2, 3, "No apps published yet.", theme.colour.mutedText, theme.colour.window)

    else
      local y = 3
      for position, entry in ipairs(entries) do
        if y > height - 2 then break end
        local on = (position == index)
        local have = catalog.isInstalled(entry.id)
        local tag = have and "installed"
          or (entry.api and not compat.satisfies(entry.api) and "too new" or "")
        local room = math.max(1, width - #tag - 4)
        ui.row(term, 1, y, width,
          (on and (ui.glyph.right .. " ") or "  ")
          .. ui.pad(ui.clip(entry.title or entry.id, room), room) .. " " .. tag,
          on and theme.colour.accentText or theme.colour.windowText,
          on and theme.colour.accent or theme.colour.window)
        ui.text(term, 4, y + 1, ui.clip(entry.blurb or "", width - 5),
          theme.colour.mutedText, theme.colour.window)
        y = y + 3
      end
    end

    if notice and os.clock() < noticeUntil then
      ui.row(term, 1, height, width, " " .. ui.clip(notice, width - 2),
        colours.white, theme.colour.ok)
    else
      local hint = state == "failed" and " [R] try again"
        or " [Enter] install   [Del] remove   [R] refresh"
      ui.row(term, 1, height, width, hint, theme.colour.mutedText, theme.colour.muted)
    end
  end

  refresh()
  draw()

  while true do
    local event, key, _, my = os.pullEvent()

    if event == "key" then
      if key == keys.down then index = math.min(#entries, index + 1)
      elseif key == keys.up then index = math.max(1, index - 1)
      elseif key == keys.r then refresh()
      elseif key == keys.enter and entries[index] then
        if catalog.isInstalled(entries[index].id) then
          say("Already installed")
        else
          draw()
          install(entries[index])
        end
      elseif key == keys.delete and entries[index] then
        remove(entries[index])
      end
      draw()

    elseif event == "mouse_click" then
      local clicked = math.floor((my - 3) / 3) + 1
      if entries[clicked] then
        if clicked == index and not catalog.isInstalled(entries[clicked].id) then
          draw()
          install(entries[clicked])
        else
          index = clicked
        end
      end
      draw()

    elseif event == "term_resize" then
      draw()
    end
  end
end

return app
