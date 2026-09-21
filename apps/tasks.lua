--[[ Tasks - what is running, and what is using the disk.

  One honesty note that shapes this whole app: CC gives no per-process memory
  figure. Lua's heap is shared by the kernel and every window at once, so a
  per-window "RAM" column would be invented. Instead this shows the real heap
  total for the computer, and per-process facts that are real: window size,
  how long it has been open, and whether it is focused.

  The storage scan is INCREMENTAL. An earlier version walked the whole disk in
  one go inside the event loop, which froze the desktop and, on a big tree,
  tripped CC's "too long without yielding" and killed the window. It now does
  a slice of work per tick and yields between slices, so the OS stays alive
  and the scan simply takes a moment.
]]

local use = ...
local ui = use("system/ui")
local theme = use("system/theme")
local kernel = use("system/kernel")

local app = {}

local SLICE = 40          -- directory entries per slice
local MAX_ENTRIES = 3000  -- hard ceiling, so a huge tree still finishes

local dev = use("system/dev")

local function heapKB()
  return dev.heapKB() or 0
end

local function bytes(value)
  if value >= 1048576 then return string.format("%.1fM", value / 1048576) end
  if value >= 1024 then return string.format("%.0fK", value / 1024) end
  return value .. "B"
end

function app.run(ctx)
  local view = "procs"          -- procs | storage
  local index = 1
  local shown = {}              -- the process list as drawn, front window first
  local storage = nil
  local scan = nil              -- in-progress scan state
  local notice, noticeUntil = nil, 0
  local confirming = nil

  local function say(text)
    notice, noticeUntil = text, os.clock() + 3
  end

  ------------------------------------------------------------------
  -- incremental storage scan
  ------------------------------------------------------------------

  local function beginScan()
    local roots = {}
    local ok, names = pcall(fs.list, "/")
    if ok then
      for _, name in ipairs(names) do
        local path = "/" .. name
        -- Read-only mounts are the ROM and treasure disks: not your storage,
        -- and enormous. Skipping them is the difference between a scan that
        -- finishes and one that does not.
        if not fs.isReadOnly(path) then
          roots[#roots + 1] = { name = name, path = path, dir = fs.isDir(path) }
        end
      end
    end
    scan = { roots = roots, at = 1, stack = {}, total = 0, seen = 0, rows = {} }
    storage = nil
  end

  -- Returns true when there is still work left.
  local function stepScan()
    if not scan then return false end
    local work = 0

    while work < SLICE do
      local current = scan.roots[scan.at]
      if not current then
        table.sort(scan.rows, function(a, b) return a.size > b.size end)
        storage = { rows = scan.rows, truncated = scan.seen >= MAX_ENTRIES }
        scan = nil
        return false
      end

      if not current.dir then
        local sized, size = pcall(fs.getSize, current.path)
        scan.rows[#scan.rows + 1] = {
          name = current.name, size = (sized and tonumber(size)) or 0, dir = false,
        }
        scan.at = scan.at + 1
        scan.total = 0
        work = work + 1
      else
        if #scan.stack == 0 and scan.total == 0 and not scan.started then
          scan.stack = { current.path }
          scan.started = true
        end

        if #scan.stack == 0 then
          scan.rows[#scan.rows + 1] = { name = current.name, size = scan.total, dir = true }
          scan.at = scan.at + 1
          scan.total = 0
          scan.started = false
        else
          local folder = table.remove(scan.stack)
          local ok, names = pcall(fs.list, folder)
          if ok then
            for _, name in ipairs(names) do
              scan.seen = scan.seen + 1
              if scan.seen >= MAX_ENTRIES then break end
              local child = fs.combine(folder, name)
              if fs.isDir(child) then
                scan.stack[#scan.stack + 1] = child
              else
                local sized, size = pcall(fs.getSize, child)
                if sized then scan.total = scan.total + (tonumber(size) or 0) end
              end
              work = work + 1
            end
          end
          if scan.seen >= MAX_ENTRIES then scan.stack = {} end
        end
      end
    end
    return true
  end

  ------------------------------------------------------------------
  -- processes
  ------------------------------------------------------------------

  local function processList()
    local list = kernel.list()
    local out = {}
    -- kernel.list() is back to front; the front window should be at the top.
    for position = #list, 1, -1 do out[#out + 1] = list[position] end
    return out
  end

  local function drawProcs()
    local width, height = term.getSize()
    shown = processList()
    if index > #shown then index = math.max(1, #shown) end

    term.setBackgroundColour(theme.colour.window)
    term.clear()
    ui.row(term, 1, 1, width, " Tasks   " .. #shown .. " running",
      theme.colour.accentText, theme.colour.accent)
    ui.row(term, 1, 2, width, " heap " .. heapKB() .. "K   up " .. math.floor(os.clock()) .. "s",
      theme.colour.mutedText, theme.colour.muted)

    if #shown == 0 then
      ui.text(term, 2, 4, "Nothing running.", theme.colour.mutedText, theme.colour.window)
    end

    local rows = height - 4
    for row = 1, math.min(rows, #shown) do
      local proc = shown[row]
      local on = (row == index)
      local tag = proc.minimised and ui.glyph.down
        or (kernel.focused() == proc and ui.glyph.right or " ")
      local size = proc.w .. "x" .. proc.h
      local room = math.max(1, width - #size - 6)
      ui.row(term, 1, row + 3, width,
        " " .. tag .. " " .. ui.pad(ui.clip(proc.title, room), room) .. " " .. size,
        on and theme.colour.accentText or theme.colour.windowText,
        on and theme.colour.accent or theme.colour.window)
    end

    if confirming then
      ui.panel(term, 3, math.floor(height / 2) - 1, width - 6, 4,
        theme.colour.muted, theme.colour.danger)
      ui.centre(term, math.floor(height / 2), "Close " .. ui.clip(confirming.title, 14) .. "?",
        colours.black, theme.colour.muted, 4, width - 8)
      ui.centre(term, math.floor(height / 2) + 1, "Y / N",
        theme.colour.mutedText, theme.colour.muted, 4, width - 8)
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

    local ok, free = pcall(fs.getFreeSpace, "/")
    ui.row(term, 1, 2, width, " free " .. bytes((ok and tonumber(free)) or 0)
      .. (storage and storage.truncated and "   (partial)" or ""),
      theme.colour.mutedText, theme.colour.muted)

    if scan then
      ui.text(term, 2, 4, "Scanning... " .. scan.seen .. " files",
        theme.colour.windowText, theme.colour.window)
      local bar = width - 4
      local done = math.min(bar, math.floor(bar * scan.seen / MAX_ENTRIES))
      ui.fill(term, 3, 6, bar, 1, theme.colour.muted)
      if done > 0 then ui.fill(term, 3, 6, done, 1, theme.colour.accent) end
    elseif storage then
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

  ------------------------------------------------------------------

  draw()
  local ticker = os.startTimer(1)

  while true do
    -- A scan in progress drives the loop itself, yielding between slices so
    -- the rest of the OS keeps running.
    if scan then
      if stepScan() then
        draw()
        sleep(0)
      else
        draw()
      end
    end

    local event, key, mx, my = os.pullEvent()

    if event == "timer" and key == ticker then
      ticker = os.startTimer(1)
      if view == "procs" then draw() end

    elseif event == "key" then
      if confirming then
        if key == keys.y then
          kernel.close(confirming)
          say("Closed " .. confirming.title)
        end
        confirming = nil
        draw()

      elseif view == "procs" then
        if key == keys.down then index = math.min(#shown, index + 1)
        elseif key == keys.up then index = math.max(1, index - 1)
        elseif key == keys.s then
          view = "storage"
          beginScan()
        elseif key == keys.enter then
          local proc = shown[index]
          if proc then kernel.focusOn(proc) end
        elseif key == keys.k then
          local proc = shown[index]
          -- Identity, not the title: renaming a window must not make it
          -- killable from inside itself.
          if proc and proc.appId == "tasks" then
            say("Close Tasks with its own X")
          elseif proc then
            confirming = proc
          end
        end
        draw()

      else
        if key == keys.backspace then view = "procs"
        elseif key == keys.r then beginScan()
        end
        draw()
      end

    elseif event == "mouse_click" then
      if view == "procs" and my then
        local row = my - 3
        if shown[row] then
          if row == index and shown[row].appId ~= "tasks" then
            confirming = shown[row]
          else
            index = row
            kernel.focusOn(shown[row])
          end
        end
      end
      draw()

    elseif event == "term_resize" then
      draw()
    end
  end
end

return app
