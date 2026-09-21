--[[ Paint - draw pictures, saved as .nfp.

  .nfp is CraftOS's own image format (one hex colour character per pixel), so
  anything drawn here can be shown by paintutils.drawImage in your own
  programs, and existing .nfp files open fine.
]]

local use = ...
local ui = use("system/ui")
local theme = use("system/theme")

local app = {}

local PALETTE = {
  colours.white, colours.orange, colours.magenta, colours.lightBlue,
  colours.yellow, colours.lime, colours.pink, colours.grey,
  colours.lightGrey, colours.cyan, colours.purple, colours.blue,
  colours.brown, colours.green, colours.red, colours.black,
}

function app.run(ctx, openPath)
  local width, height = term.getSize()
  local canvasH = height - 2
  local canvasW = width - 3          -- last 3 columns are the palette
  local pixels = {}                  -- pixels[y][x] = colour or nil
  local colour = colours.red
  local path = openPath
  local notice, noticeUntil = nil, 0

  for y = 1, canvasH do pixels[y] = {} end

  local function say(text)
    notice, noticeUntil = text, os.clock() + 3
  end

  local function load(target)
    local ok, image = pcall(paintutils.loadImage, target)
    if not ok or type(image) ~= "table" then return false end
    for y = 1, canvasH do
      pixels[y] = {}
      local row = image[y]
      if row then
        for x = 1, canvasW do pixels[y][x] = row[x] end
      end
    end
    return true
  end

  local function save(target)
    local handle, err = fs.open(target, "w")
    if not handle then return false, tostring(err) end
    -- Trailing blank rows and columns are dropped so the file stays small.
    local lastRow = 0
    for y = 1, canvasH do
      for x = 1, canvasW do
        if pixels[y][x] then lastRow = y break end
      end
    end
    for y = 1, lastRow do
      local line = {}
      local lastCol = 0
      for x = 1, canvasW do if pixels[y][x] then lastCol = x end end
      for x = 1, lastCol do
        line[#line + 1] = pixels[y][x] and colours.toBlit(pixels[y][x]) or " "
      end
      handle.writeLine(table.concat(line))
    end
    handle.close()
    return true
  end

  local function draw()
    term.setBackgroundColour(theme.colour.window)
    term.clear()
    ui.row(term, 1, 1, width, " Paint  " .. (path and fs.getName(path) or "untitled"),
      theme.colour.accentText, theme.colour.accent)

    for y = 1, canvasH do
      for x = 1, canvasW do
        local cell = pixels[y][x]
        if cell then ui.fill(term, x, y + 1, 1, 1, cell) end
      end
    end

    -- Palette down the right edge, current colour marked.
    for index, entry in ipairs(PALETTE) do
      local y = index + 1
      if y <= height - 1 then
        ui.fill(term, width - 2, y, 3, 1, entry)
        if entry == colour then
          ui.text(term, width - 1, y, "o",
            entry == colours.white and colours.black or colours.white, entry)
        end
      end
    end

    if notice and os.clock() < noticeUntil then
      ui.row(term, 1, height, width, " " .. notice, colours.white, theme.colour.ok)
    else
      ui.row(term, 1, height, width, " click to paint  [S]ave  [O]pen  [C]lear",
        theme.colour.mutedText, theme.colour.muted)
    end
  end

  local function prompt(label)
    ui.fill(term, 1, height - 1, width, 1, colours.white)
    ui.text(term, 1, height - 1, label, colours.black, colours.white)
    term.setCursorPos(#label + 1, height - 1)
    term.setBackgroundColour(colours.white)
    term.setTextColour(colours.black)
    return read()
  end

  if path then load(path) end
  draw()

  while true do
    local event, a, x, y = os.pullEvent()

    if event == "mouse_click" or event == "mouse_drag" then
      if x >= width - 2 then
        local pick = PALETTE[y - 1]
        if pick then colour = pick end
      elseif y >= 2 and y <= canvasH + 1 and x <= canvasW then
        -- Right button erases, which is what everyone tries first.
        pixels[y - 1][x] = (a == 2) and nil or colour
      end
      draw()

    elseif event == "key" then
      if a == keys.s then
        local target = path or prompt(" save as: ")
        if target and target ~= "" then
          if not target:find("%.") then target = target .. ".nfp" end
          local ok, err = save(target)
          if ok then path = target; say("Saved") else say("Failed: " .. tostring(err)) end
        end
      elseif a == keys.o then
        local target = prompt(" open: ")
        if target and target ~= "" then
          if load(target) then path = target; say("Opened") else say("Could not open") end
        end
      elseif a == keys.c then
        for row = 1, canvasH do pixels[row] = {} end
        say("Cleared")
      end
      draw()

    elseif event == "term_resize" then
      draw()
    end
  end
end

return app
