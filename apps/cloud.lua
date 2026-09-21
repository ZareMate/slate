--[[ Cloud - what is stored remotely, and what is actually on this disk.

  Slate's storage is split in two. A small set of files is installed; the rest
  lives in cloud storage and comes down when it is needed. This is the view of
  that: everything published, what you have cached, and how much room it is
  taking.

  Read comes from the update source, which is a plain static host - that is
  why browsing works with no server to run. Writing back is not something a
  raw file host can do, so this manages the local side of the pairing:
  download, cache, and free up.
]]

local use = ...
local ui = use("system/ui")
local theme = use("system/theme")
local update = use("system/update")
local cloud = use("system/cloud")

local app = {}

local REFRESH = 60

local function bytes(value)
  if value >= 1048576 then return string.format("%.1fM", value / 1048576) end
  if value >= 1024 then return string.format("%.0fK", value / 1024) end
  return value .. "B"
end

function app.run(ctx)
  local root = ctx.root()
  local entries = {}
  local index, scroll = 1, 0
  local state = "loading"
  local problem = nil
  local notice, noticeUntil = nil, 0
  local buttons = {}

  local function say(text)
    notice, noticeUntil = text, os.clock() + 4
  end

  local function rows()
    local _, height = term.getSize()
    return math.max(1, height - 3)
  end

  local function fetchJson(path)
    if not http then return nil, "HTTP is disabled" end
    local base = update.url()
    if not base then return nil, "No source configured" end
    local response, err = http.get(base .. path)
    if not response then return nil, tostring(err) end
    local body = response.readAll()
    response.close()
    local ok, parsed = pcall(textutils.unserialiseJSON, body)
    if not ok or type(parsed) ~= "table" then return nil, "Bad JSON at " .. path end
    return parsed
  end

  local function localSize(path)
    local full = fs.combine(root, path)
    if not fs.exists(full) then return nil end
    local ok, size = pcall(fs.getSize, full)
    return ok and size or 0
  end

  local function refresh()
    state = "loading"
    entries = {}

    local manifest, err = fetchJson("/manifest.json")
    if not manifest then
      state, problem = "failed", err
      return
    end

    local function add(path, kind)
      entries[#entries + 1] = { path = path, kind = kind, size = localSize(path) }
    end

    for _, path in ipairs(manifest.files or {}) do add(path, "installed") end
    for _, path in ipairs(manifest.cloud or {}) do add(path, "on demand") end

    -- Store apps live under store/ and install into apps/, so they are shown
    -- by where they land rather than where they are published.
    local store = fetchJson("/store/index.json")
    if store then
      for _, entry in ipairs(store.apps or {}) do
        if entry.id then
          entries[#entries + 1] = {
            path = "apps/" .. entry.id .. ".lua",
            remote = "store/" .. (entry.file or ""),
            kind = "store",
            size = localSize("apps/" .. entry.id .. ".lua"),
          }
        end
      end
    end

    if index > #entries then index = math.max(1, #entries) end
    state = "ready"
  end

  local function download(entry)
    local module = entry.path:gsub("%.lua$", "")
    local source = entry.remote and entry.remote:gsub("%.lua$", "") or module
    local ok, why = cloud.fetch(source, root)
    if not ok then
      say("Failed: " .. tostring(why))
      return
    end
    -- A store app publishes under store/ but must land in apps/, so it is
    -- moved into place after the fetch.
    if entry.remote then
      local from = fs.combine(root, source .. ".lua")
      local to = fs.combine(root, entry.path)
      if from ~= to and fs.exists(from) then
        pcall(fs.delete, to)
        pcall(fs.move, from, to)
      end
    end
    entry.size = localSize(entry.path)
    say("Downloaded " .. fs.getName(entry.path))
  end

  local function remove(entry)
    if entry.kind == "installed" then
      say("Installed files are not removable here")
      return
    end
    local freed = cloud.evict({ entry.path:gsub("%.lua$", "") }, root)
    entry.size = localSize(entry.path)
    say(freed > 0 and ("Freed " .. bytes(freed)) or "Was not cached")
  end

  local function draw()
    local width, height = term.getSize()
    buttons = {}

    if index < scroll + 1 then scroll = index - 1 end
    if index > scroll + rows() then scroll = index - rows() end
    scroll = ui.clampScroll(scroll, #entries, rows())

    term.setBackgroundColour(theme.colour.window)
    term.clear()

    local cached, total = 0, 0
    for _, entry in ipairs(entries) do
      total = total + 1
      if entry.size then cached = cached + entry.size end
    end
    ui.row(term, 1, 1, width, " " .. ui.spaced("Cloud") .. "   " .. bytes(cached) .. " here",
      theme.colour.accentText, theme.colour.accent)

    if state == "loading" then
      ui.text(term, 2, 3, "Reading the catalogue...", theme.colour.windowText, theme.colour.window)

    elseif state == "failed" then
      ui.text(term, 2, 3, "Cannot reach cloud storage", theme.colour.danger, theme.colour.window)
      local y = 5
      for _, line in ipairs(ui.wrap(problem or "", width - 2)) do
        if y > height - 2 then break end
        ui.text(term, 2, y, line, theme.colour.mutedText, theme.colour.window)
        y = y + 1
      end

    else
      for offset = 0, rows() - 1 do
        local entry = entries[scroll + offset + 1]
        if not entry then break end
        local y = 2 + offset
        local on = (scroll + offset + 1 == index)
        local here = entry.size and bytes(entry.size) or "cloud"
        local room = math.max(1, width - #here - 4)

        ui.row(term, 1, y, width - 1,
          " " .. ui.pad(ui.clip(entry.path, room), room) .. " " .. here,
          on and theme.colour.accentText or theme.colour.windowText,
          on and theme.colour.accent or theme.colour.window)

        if not on then
          ui.text(term, width - #here, y, here,
            entry.size and theme.colour.ok or theme.colour.mutedText, theme.colour.window)
        end
      end
      ui.scrollbar(term, width, 2, rows(), #entries, scroll,
        theme.colour.muted, theme.colour.accent)
    end

    local entry = entries[index]
    buttons = ui.buttonRow(term, 2, height - 1, {
      { name = "get", label = entry and entry.size and "Re-get" or "Get",
        bg = theme.colour.ok, fg = colours.white, disabled = not entry },
      { name = "free", label = "Free", bg = theme.colour.muted,
        disabled = not (entry and entry.size and entry.kind ~= "installed") },
      { name = "refresh", label = "Refresh", bg = theme.colour.muted },
    })

    if notice and os.clock() < noticeUntil then
      ui.row(term, 1, height, width, " " .. ui.clip(notice, width - 2),
        colours.white, theme.colour.ok)
    else
      ui.row(term, 1, height, width,
        " " .. total .. " files   " .. (entry and entry.kind or ""),
        theme.colour.mutedText, theme.colour.muted)
    end
  end

  draw()
  refresh()
  draw()
  -- Pages that show remote state refresh themselves; being told to press R to
  -- see the truth is not a feature.
  local ticker = os.startTimer(REFRESH)

  while true do
    local event, a, mx, my = os.pullEvent()

    if event == "timer" and a == ticker then
      ticker = os.startTimer(REFRESH)
      if state ~= "loading" then refresh() end
      draw()

    elseif event == "key" then
      if a == keys.down then index = math.min(#entries, index + 1)
      elseif a == keys.up then index = math.max(1, index - 1)
      elseif a == keys.r then draw(); refresh()
      elseif a == keys.enter and entries[index] then draw(); download(entries[index])
      elseif a == keys.delete and entries[index] then remove(entries[index])
      end
      draw()

    elseif event == "mouse_click" then
      if ui.inButton(buttons.get, mx, my) then
        draw()
        download(entries[index])
      elseif ui.inButton(buttons.free, mx, my) then
        remove(entries[index])
      elseif ui.inButton(buttons.refresh, mx, my) then
        draw()
        refresh()
      else
        local clicked = scroll + my - 1
        if entries[clicked] and my >= 2 then index = clicked end
      end
      draw()

    elseif event == "mouse_scroll" then
      scroll = ui.clampScroll(scroll + a, #entries, rows())
      index = math.max(scroll + 1, math.min(scroll + rows(), index))
      draw()

    elseif event == "term_resize" then
      draw()
    end
  end
end

return app
