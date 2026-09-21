--[[ Notes - short notes kept on this computer.

  Notes live as plain text files in /notes, so they are readable from the
  shell and survive Slate being reinstalled. Editing hands off to Slate's
  Editor rather than growing a second text editor.
]]

local use = ...
local ui = use("system/ui")
local theme = use("system/theme")

local app = {}

local DIR = "/notes"

local function ensureDir()
  if not fs.exists(DIR) then pcall(fs.makeDir, DIR) end
end

local function list()
  ensureDir()
  local out = {}
  local ok, names = pcall(fs.list, DIR)
  if not ok then return out end
  for _, name in ipairs(names) do
    local path = fs.combine(DIR, name)
    if not fs.isDir(path) then
      local sized, size = pcall(fs.getSize, path)
      out[#out + 1] = { name = name, path = path, size = sized and size or 0 }
    end
  end
  table.sort(out, function(a, b) return a.name:lower() < b.name:lower() end)
  return out
end

local function firstLine(path)
  local handle = fs.open(path, "r")
  if not handle then return "" end
  local line = handle.readLine() or ""
  handle.close()
  return line
end

function app.run(ctx)
  local notes = list()
  local index = 1
  local notice, noticeUntil = nil, 0

  local function say(text)
    notice, noticeUntil = text, os.clock() + 3
  end

  local function refresh()
    notes = list()
    if index > #notes then index = math.max(1, #notes) end
  end

  local function prompt(label)
    local width, height = term.getSize()
    ui.fill(term, 1, height - 2, width, 2, theme.colour.muted)
    ui.text(term, 2, height - 2, label, colours.black, theme.colour.muted)
    ui.fill(term, 2, height - 1, width - 3, 1, colours.white)
    term.setCursorPos(2, height - 1)
    term.setBackgroundColour(colours.white)
    term.setTextColour(colours.black)
    return read()
  end

  local function draw()
    local width, height = term.getSize()
    term.setBackgroundColour(theme.colour.window)
    term.clear()
    ui.row(term, 1, 1, width, " Notes  " .. #notes,
      theme.colour.accentText, theme.colour.accent)

    if #notes == 0 then
      ui.text(term, 2, 3, "No notes yet.", theme.colour.mutedText, theme.colour.window)
      ui.text(term, 2, 5, "Press N to write one.", theme.colour.mutedText, theme.colour.window)
    end

    local rows = math.floor((height - 2) / 2)
    local first = math.max(1, index - rows + 1)
    local y = 3
    for position = first, math.min(#notes, first + rows - 1) do
      local note = notes[position]
      local on = (position == index)
      ui.row(term, 1, y, width,
        (on and (ui.glyph.right .. " ") or "  ") .. ui.clip(note.name, width - 4),
        on and theme.colour.accentText or theme.colour.windowText,
        on and theme.colour.accent or theme.colour.window)
      ui.text(term, 4, y + 1, ui.clip(firstLine(note.path), width - 5),
        theme.colour.mutedText, theme.colour.window)
      y = y + 2
    end

    if notice and os.clock() < noticeUntil then
      ui.row(term, 1, height, width, " " .. notice, colours.white, theme.colour.ok)
    else
      ui.row(term, 1, height, width, " [Enter] open  [N]ew  [Del]ete",
        theme.colour.mutedText, theme.colour.muted)
    end
  end

  draw()

  while true do
    local event, key = os.pullEvent()

    if event == "key" then
      if key == keys.down then index = math.min(#notes, index + 1)
      elseif key == keys.up then index = math.max(1, index - 1)
      elseif key == keys.r then refresh()

      elseif key == keys.enter and notes[index] then
        ctx.launch("editor", { notes[index].path })

      elseif key == keys.n then
        local name = prompt("Name for the note:")
        if name and name ~= "" then
          if not name:find("%.") then name = name .. ".txt" end
          ensureDir()
          local path = fs.combine(DIR, name)
          if fs.exists(path) then
            say("That note already exists")
          else
            local handle = fs.open(path, "w")
            if handle then handle.close() end
            refresh()
            ctx.launch("editor", { path })
          end
        end

      elseif key == keys.delete and notes[index] then
        local note = notes[index]
        local answer = prompt("Delete " .. note.name .. "? (y/n)")
        if answer and answer:lower():sub(1, 1) == "y" then
          pcall(fs.delete, note.path)
          say("Deleted")
          refresh()
        end
      end
      draw()

    elseif event == "mouse_click" then
      draw()
    elseif event == "term_resize" then
      draw()
    end
  end
end

return app
