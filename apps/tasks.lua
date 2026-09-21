--[[ Tasks - what is running, and what is using the disk.

  One honesty note that shapes this whole app: CC gives no per-process memory
  figure. Lua's heap is shared by the kernel and every window at once, so a
  per-window "RAM" column would be invented. Instead this shows the real heap
  total for the computer, and per-process facts that are real: window size,
  how long it has been open, and whether it is responding.
]]

local use = ...
local ui = use("system/ui")
local theme = use("system/theme")
local kernel = use("system/kernel")

local app = {}

local function heapKB()
  return math.floor(collectgarbage("count"))
end

local function bytes(value)
  if value >= 1048576 then return string.format("%.1fM", value / 1048576) end
  if value >= 1024 then return string.format("%.0fK", value / 1024) end
  return value .. "B"
end

-- Walks a folder, but stops early: a deep tree on a slow server should not
-- freeze the window.
local function sizeOf(path, budget)
  local total = 0
  local stack = { path }
  while #stack > 0 and budget.count < budget.limit do
    local current = table.remove(stack)
    budget.count = budget.count + 1
    local ok, list = pcall(fs.list, current)
    if ok then
      for _, name in ipairs(list) do
        local child = fs.combine(current, name)
        if fs.isDir(child) then
          stack[#stack + 1] = child
        else
          local sized, size = pcall(fs.getSize, child)
          if sized then total = total + size end
        end
      end
    end
  end
  return total
end

function app.run(ctx)
  local view = "procs"          -- procs | storage
  local index = 1
  local storage = nil
  local notice, noticeUntil = nil, 0

  local function say(text)
    notice, noticeUntil = text, os.clock() + 3
  end

  local function scanStorage()
    local budget = { count = 0, limit = 400 }
    local rows = {}
    local ok, list = pcall(fs.list, "/")
    if ok then
      for _, name in ipairs(list) do
        local path = "/" .. name
        if not fs.isReadOnly(path) or name ~= "rom" then
          local size = fs.isDir(path) and sizeOf(path, budget) or select(2, pcall(fs.getSize, path))
          rows[#rows + 1] = { name = name, size = tonumber(size) or 0, dir = fs.isDir(path) }
        end
      end
    end
    table.sort(rows, function(a, b) return a.size > b.size end)
    storage = { rows = rows, truncated = budget.count >= budget.limit }
  end

  local function drawProcs()
    local width, height = term.getSize()
    local list = kernel.list()
    local rows = height - 4

    if index > #list then index = math.max(1, #list) end

    term.setBackgroundColour(theme.colour.window)
    term.clear()
    ui.row(term, 1, 1, width, " Tasks   " .. #list .. " running",
      theme.colour.accentText, theme.colour.accent)

    ui.row(term, 1, 2, width,
      " heap " .. heapKB() .. "K   up " .. math.floor(os.clock()) .. "s",
      theme.colour.mutedText, theme.colour.muted)

    if #list == 0 then
      ui.text(term, 2, 4, "Nothing running.", theme.colour.mutedText, theme.colour.window)
    end

    for row = 1, math.min(rows, #list) do
      -- kernel.list() is back-to-front; show the front window first.
      local proc = list[#list - row + 1]
      local on = (row == index)
      local tag = proc.minimised and "_" or (kernel.focused() == proc and ">" or " ")
      local size = proc.w .. "x" .. proc.h
      local room = math.max(1, width - #size - 6)
      ui.row(term, 1, row + 3, width,
        " " .. tag .. " " .. ui.pad(ui.clip(proc.title, room), room) .. " " .. size,
        on and theme.colour.accentText or theme.colour.windowText,
        on and theme.colour.accent or theme.colour.window)
    end

    if notice and os.clock() < noticeUntil then
      ui.row(term, 1, height, width, " " .. notice, colours.white, theme.colour.ok)
    else
      ui.row(term, 1, height, width, " [K]ill  [S]torage  [Enter] focus",
        theme.colour.mutedText, theme.colour.muted)
    end
  end

  local function drawStorage()
    local width, height = term.getSize()
    term.setBackgroundColour(theme.colour.window)
    term.clear()
    ui.row(term, 1, 1, width, " Storage", theme.colour.accentText, theme.colour.accent)

    local free = select(2, pcall(fs.getFreeSpace, "/")) or 0
    ui.row(term, 1, 2, width, " free " .. bytes(tonumber(free) or 0)
      .. (storage and storage.truncated and "   (partial scan)" or ""),
      theme.colour.mutedText, theme.colour.muted)

    if not storage then
      ui.text(term, 2, 4, "Scanning...", theme.colour.windowText, theme.colour.window)
    else
      local y = 4
      for _, row in ipairs(storage.rows) do
        if y > height - 1 then break end
        local size = bytes(row.size)
        local room = math.max(1, width - #size - 4)
        ui.text(term, 2, y, ui.pad(ui.clip((row.dir and "/" or " ") .. row.name, room), room),
          theme.colour.windowText, theme.colour.window)
        ui.text(term, width - #size, y, size, theme.colour.mutedText, theme.colour.window)
        y = y + 1
      end
    end

    ui.row(term, 1, height, width, " [R]escan   [Backspace] back",
      theme.colour.mutedText, theme.colour.muted)
  end

  local function draw()
    if view == "procs" then drawProcs() else drawStorage() end
  end

  draw()
  local ticker = os.startTimer(1)

  while true do
    local event, key = os.pullEvent()

    if event == "timer" and key == ticker then
      ticker = os.startTimer(1)
      if view == "procs" then draw() end

    elseif event == "key" then
      if view == "procs" then
        local list = kernel.list()
        if key == keys.down then index = math.min(#list, index + 1)
        elseif key == keys.up then index = math.max(1, index - 1)
        elseif key == keys.s then
          view = "storage"
          storage = nil
          draw()
          scanStorage()
        elseif key == keys.enter then
          local proc = list[#list - index + 1]
          if proc then kernel.focusOn(proc) end
        elseif key == keys.k then
          local proc = list[#list - index + 1]
          -- Refuse to close this window from inside itself.
          if proc and proc.title:find("Tasks") then
            say("Close Tasks with its own X")
          elseif proc then
            kernel.close(proc)
            say("Closed " .. proc.title)
          end
        end
        draw()
      else
        if key == keys.backspace then view = "procs"
        elseif key == keys.r then storage = nil; draw(); scanStorage()
        end
        draw()
      end

    elseif event == "mouse_click" then
      draw()

    elseif event == "term_resize" then
      draw()
    end
  end
end

return app
