--[[ Store - install apps from anywhere.

  Apps are not on the computer and are not tied to one repository. The Store
  reads every configured source (see system/sources.lua), merges what they
  publish, and installs the file the chosen entry names.

  Three ways to get an app:

    * from a source's catalogue, the normal way
    * by adding somebody else's source, so their whole catalogue appears
    * from a direct .lua URL, for a one-off or something you wrote yourself

  Nothing needs write access to anyone else's repository, which is the point:
  publishing is putting an index.json and some .lua files on any static host.
]]

local use = ...
local ui = use("system/ui")
local theme = use("system/theme")
local catalog = use("system/catalog")
local compat = use("system/compat")
local sources = use("system/sources")

local app = {}

local ROW_H = 3

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
  local index, scroll = 1, 0
  local view = "apps"              -- apps | sources
  local state = "loading"
  local problem = nil
  local notice, noticeUntil = nil, 0
  local buttons = {}
  local sourceIndex = 1

  local function say(text)
    notice, noticeUntil = text, os.clock() + 4
  end

  local function visibleRows()
    local _, height = term.getSize()
    return math.max(1, math.floor((height - 3) / ROW_H))
  end

  local function follow(count, perRow)
    local rows = perRow or visibleRows()
    if index < scroll + 1 then scroll = index - 1 end
    if index > scroll + rows then scroll = index - rows end
    scroll = ui.clampScroll(scroll, count, rows)
  end

  ------------------------------------------------------------------
  -- catalogue
  ------------------------------------------------------------------

  local function refresh()
    state = "loading"
    entries = {}
    local seen = {}
    local failures = {}

    for _, source in ipairs(sources.list()) do
      local body, err = fetch(source.url .. "/index.json")
      if not body then
        failures[#failures + 1] = source.name .. ": " .. tostring(err)
      else
        local ok, parsed = pcall(textutils.unserialiseJSON, body)
        if not ok or type(parsed) ~= "table" or type(parsed.apps) ~= "table" then
          failures[#failures + 1] = source.name .. ": bad index"
        else
          for _, entry in ipairs(parsed.apps) do
            -- First source to claim an id wins, so adding a third-party
            -- source can never quietly replace an app you already trust.
            if type(entry) == "table" and entry.id and not seen[entry.id] then
              seen[entry.id] = true
              entry.sourceName = source.name
              -- A catalogue may serve its files from elsewhere; index-level
              -- "source" says where. (ZareMate.)
              entry.sourceUrl = (type(parsed.source) == "string"
                and parsed.source:gsub("/+$", "")) or source.url
              entries[#entries + 1] = entry
            end
          end
        end
      end
    end

    if index > #entries then index = math.max(1, #entries) end
    if #entries == 0 and #failures > 0 then
      state, problem = "failed", table.concat(failures, "; ")
    else
      state = "list"
      if #failures > 0 then say(#failures .. " source(s) unreachable") end
    end
  end

  ------------------------------------------------------------------
  -- installing
  ------------------------------------------------------------------

  local function writeApp(id, body, meta)
    local module = "apps/" .. id
    local path = fs.combine(root, module .. ".lua")
    local handle, err = fs.open(path, "w")
    if not handle then return false, tostring(err) end
    handle.write(body)
    handle.close()

    local registered, why = catalog.install({
      id = id,
      title = (meta and meta.title) or id,
      module = module,
      w = tonumber(meta and meta.w) or 40,
      h = tonumber(meta and meta.h) or 14,
      icon = type(meta and meta.icon) == "table" and meta.icon or nil,
      single = (meta and meta.single) == true,
      api = tonumber(meta and meta.api),
    }, root)

    -- Roll back on a failed registration: a file on disk the catalog does not
    -- know about is an app you can neither run nor uninstall. (ZareMate.)
    if not registered then
      pcall(fs.delete, path)
      return false, tostring(why)
    end
    return true
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
    -- An index may host its payloads somewhere other than the index itself,
    -- and an entry may override that again. Falls back to the source the
    -- catalogue came from. (ZareMate, PR #1.)
    local origin = (type(entry.source) == "string" and entry.source:gsub("/+$", ""))
      or entry.sourceUrl
    local body, err = fetch(origin .. "/" .. entry.file)
    state = "list"
    if not body or body == "" then
      say("Download failed: " .. tostring(err or "empty"))
      return
    end

    local ok, why = writeApp(entry.id, body, entry)
    if not ok then
      say("Could not write: " .. tostring(why))
      return
    end
    say("Installed " .. (entry.title or entry.id))
    ctx.notify((entry.title or entry.id) .. " installed")
  end

  local function remove(entry)
    local ok, err = catalog.uninstall(entry.id, root)
    say(ok and ("Removed " .. (entry.title or entry.id)) or tostring(err))
  end

  ------------------------------------------------------------------
  -- prompts
  ------------------------------------------------------------------

  local function ask(label, value)
    local width, height = term.getSize()
    ui.fill(term, 1, height - 1, width, 1, colours.white)
    ui.text(term, 1, height - 1, label, colours.black, colours.white)
    term.setCursorPos(#label + 1, height - 1)
    term.setBackgroundColour(colours.white)
    term.setTextColour(colours.black)
    return read(nil, nil, nil, value)
  end

  local function addSource()
    local url = ask(" source url: ", "https://")
    if not url or url == "" or url == "https://" then return end
    local name = ask(" name it: ", "")
    local ok, why = sources.add(name or "", url)
    say(ok and "Source added" or tostring(why))
    if ok then refresh() end
  end

  -- The smallest possible "add your own app": point at a .lua file.
  local function installFromUrl()
    local url = ask(" app .lua url: ", "https://")
    if not url or url == "" or url == "https://" then return end
    local id = ask(" id (one word): ", "")
    if not id or id == "" then say("An id is needed") return end
    id = id:lower():gsub("[^%w]", "")
    if id == "" then say("That id has no letters in it") return end
    if catalog.isBuiltin(id) then say("That id is a built-in app") return end

    local body, err = fetch(url)
    if not body or body == "" then
      say("Download failed: " .. tostring(err or "empty"))
      return
    end
    local title = ask(" title: ", id)
    local ok, why = writeApp(id, body, { title = title })
    say(ok and ("Installed " .. id) or tostring(why))
  end

  ------------------------------------------------------------------
  -- drawing
  ------------------------------------------------------------------

  local function drawApps()
    local width, height = term.getSize()
    follow(#entries)

    ui.row(term, 1, 1, width, " " .. ui.spaced("Store"),
      theme.colour.accentText, theme.colour.accent)

    if state == "loading" then
      ui.text(term, 2, 3, "Reading sources...", theme.colour.windowText, theme.colour.window)
    elseif state == "busy" then
      ui.text(term, 2, 3, "Installing...", theme.colour.windowText, theme.colour.window)
    elseif state == "failed" then
      ui.text(term, 2, 3, "No source reachable", theme.colour.danger, theme.colour.window)
      local y = 5
      for _, line in ipairs(ui.wrap(problem or "", width - 2)) do
        if y > height - 3 then break end
        ui.text(term, 2, y, line, theme.colour.mutedText, theme.colour.window)
        y = y + 1
      end
    elseif #entries == 0 then
      ui.text(term, 2, 3, "No apps published yet.", theme.colour.mutedText, theme.colour.window)
      ui.text(term, 2, 5, "[O] add a source", theme.colour.mutedText, theme.colour.window)
      ui.text(term, 2, 6, "[U] install from a url", theme.colour.mutedText, theme.colour.window)
    else
      local rows = visibleRows()
      for offset = 0, rows - 1 do
        local entry = entries[scroll + offset + 1]
        if not entry then break end
        local y = 3 + offset * ROW_H
        local on = (scroll + offset + 1 == index)
        local have = catalog.isInstalled(entry.id)
        local tooNew = entry.api and not compat.satisfies(entry.api)
        local tag = have and "installed" or (tooNew and "too new" or "")
        local room = math.max(1, width - #tag - 5)

        ui.row(term, 1, y, width - 1,
          (on and (ui.glyph.right .. " ") or "  ")
          .. ui.pad(ui.clip(entry.title or entry.id, room), room) .. " " .. tag,
          on and theme.colour.accentText or theme.colour.windowText,
          on and theme.colour.accent or theme.colour.window)

        ui.text(term, 4, y + 1,
          ui.clip((entry.blurb or "") .. "  - " .. (entry.sourceName or ""), width - 5),
          theme.colour.mutedText, theme.colour.window)
      end
      ui.scrollbar(term, width, 3, rows * ROW_H, #entries * ROW_H, scroll * ROW_H,
        theme.colour.muted, theme.colour.accent)
    end

    local current = entries[index]
    local installed = current and catalog.isInstalled(current.id)
    buttons = ui.buttonRow(term, 2, height - 1, {
      { name = "action", label = installed and "Remove" or "Install",
        bg = installed and theme.colour.danger or theme.colour.ok, fg = colours.white,
        disabled = not current or ((not installed) and current.api
          and not compat.satisfies(current.api) or false) },
      { name = "sources", label = "Sources", bg = theme.colour.muted },
    })
  end

  local function drawSources()
    local width, height = term.getSize()
    local list = sources.list()
    sourceIndex = math.min(sourceIndex, math.max(1, #list))

    ui.row(term, 1, 1, width, " Sources", theme.colour.accentText, theme.colour.accent)
    ui.text(term, 2, 2, "Anyone can publish: index.json + .lua",
      theme.colour.mutedText, theme.colour.window)

    for position, source in ipairs(list) do
      local y = 3 + position
      if y > height - 2 then break end
      local on = (position == sourceIndex)
      local tag = source.builtin and "built in" or ""
      local room = math.max(1, width - #tag - 4)
      ui.row(term, 1, y, width,
        " " .. ui.pad(ui.clip(source.name, room), room) .. " " .. tag,
        on and theme.colour.accentText or theme.colour.windowText,
        on and theme.colour.accent or theme.colour.window)
    end

    buttons = ui.buttonRow(term, 2, height - 1, {
      { name = "add", label = "Add", bg = theme.colour.ok, fg = colours.white },
      { name = "drop", label = "Remove", bg = theme.colour.muted,
        disabled = not list[sourceIndex] or list[sourceIndex].builtin },
      { name = "back", label = "Back", bg = theme.colour.muted },
    })
  end

  local function draw()
    local width, height = term.getSize()
    buttons = {}
    term.setBackgroundColour(theme.colour.window)
    term.clear()

    if view == "apps" then drawApps() else drawSources() end

    if notice and os.clock() < noticeUntil then
      ui.row(term, 1, height, width, " " .. ui.clip(notice, width - 2),
        colours.white, theme.colour.ok)
    else
      ui.row(term, 1, height, width,
        view == "apps" and (" " .. #entries .. " apps  [O]sources  [U]rl  [R]efresh")
          or " [A]dd  [Del]remove  [Backspace] back",
        theme.colour.mutedText, theme.colour.muted)
    end
  end

  local function act()
    local entry = entries[index]
    if not entry then return end
    if catalog.isInstalled(entry.id) then remove(entry) else draw(); install(entry) end
  end

  ------------------------------------------------------------------

  draw()
  refresh()
  draw()
  local ticker = os.startTimer(60)

  while true do
    local event, a, mx, my = os.pullEvent()

    if event == "timer" and a == ticker then
      ticker = os.startTimer(60)
      if view == "apps" and (state == "list" or state == "failed") then
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
      if view == "apps" then
        local rows = visibleRows()
        if a == keys.down then index = math.min(#entries, index + 1)
        elseif a == keys.up then index = math.max(1, index - 1)
        elseif a == keys.pageDown then index = math.min(#entries, index + rows)
        elseif a == keys.pageUp then index = math.max(1, index - rows)
        elseif a == keys.r then draw(); refresh()
        elseif a == keys.o then view = "sources"
        elseif a == keys.u then installFromUrl()
        elseif a == keys.enter then act()
        elseif a == keys.delete and entries[index] then remove(entries[index])
        end
      else
        local list = sources.list()
        if a == keys.down then sourceIndex = math.min(#list, sourceIndex + 1)
        elseif a == keys.up then sourceIndex = math.max(1, sourceIndex - 1)
        elseif a == keys.a then addSource()
        elseif a == keys.backspace then view = "apps"
        elseif a == keys.delete and list[sourceIndex] then
          local ok, why = sources.remove(list[sourceIndex].url)
          say(ok and "Source removed" or tostring(why))
          if ok then refresh() end
        end
      end
      draw()

    elseif event == "mouse_click" then
      if view == "apps" then
        if ui.inButton(buttons.action, mx, my) then act()
        elseif ui.inButton(buttons.sources, mx, my) then view = "sources"
        else
          local clicked = scroll + math.floor((my - 3) / ROW_H) + 1
          if entries[clicked] and my >= 3 then
            if clicked == index then act() else index = clicked end
          end
        end
      else
        if ui.inButton(buttons.add, mx, my) then addSource()
        elseif ui.inButton(buttons.back, mx, my) then view = "apps"
        elseif ui.inButton(buttons.drop, mx, my) then
          local list = sources.list()
          if list[sourceIndex] then
            local ok, why = sources.remove(list[sourceIndex].url)
            say(ok and "Source removed" or tostring(why))
            if ok then refresh() end
          end
        else
          local clicked = my - 3
          if sources.list()[clicked] then sourceIndex = clicked end
        end
      end
      draw()

    elseif event == "mouse_scroll" then
      if view == "apps" then
        scroll = ui.clampScroll(scroll + a, #entries, visibleRows())
        index = math.max(scroll + 1, math.min(scroll + visibleRows(), index))
      end
      draw()

    elseif event == "term_resize" then
      draw()
    end
  end
end

return app
