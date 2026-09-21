--[[ Mines - minesweeper. Score is the number of safe squares uncovered. ]]

local use = ...
local ui = use("system/ui")
local theme = use("system/theme")
local sound = use("system/sound")

local game = {}

local NUMBER_COLOUR = {
  [1] = colours.lightBlue, [2] = colours.lime, [3] = colours.red,
  [4] = colours.purple, [5] = colours.orange, [6] = colours.cyan,
  [7] = colours.magenta, [8] = colours.grey,
}

function game.run(ctx)
  local width, height = term.getSize()
  local W = math.max(6, math.min(24, math.floor((width - 2) / 2)))
  local H = math.max(5, math.min(14, height - 3))
  local MINES = math.floor(W * H * 0.15)

  local grid = {}
  local seeded = false
  local dead, won = false, false
  local uncovered = 0
  local cx, cy = 1, 1

  for y = 1, H do
    grid[y] = {}
    for x = 1, W do
      grid[y][x] = { mine = false, open = false, flag = false, near = 0 }
    end
  end

  local function forNeighbours(x, y, fn)
    for oy = -1, 1 do
      for ox = -1, 1 do
        local nx, ny = x + ox, y + oy
        if not (ox == 0 and oy == 0) and grid[ny] and grid[ny][nx] then
          fn(nx, ny)
        end
      end
    end
  end

  -- Mines are placed after the first click, so the first move is never a loss.
  local function seed(safeX, safeY)
    local placed = 0
    while placed < MINES do
      local x, y = math.random(1, W), math.random(1, H)
      local cell = grid[y][x]
      local adjacent = math.abs(x - safeX) <= 1 and math.abs(y - safeY) <= 1
      if not cell.mine and not adjacent then
        cell.mine = true
        placed = placed + 1
      end
    end
    for y = 1, H do
      for x = 1, W do
        local count = 0
        forNeighbours(x, y, function(nx, ny)
          if grid[ny][nx].mine then count = count + 1 end
        end)
        grid[y][x].near = count
      end
    end
    seeded = true
  end

  local function open(x, y)
    local cell = grid[y] and grid[y][x]
    if not cell or cell.open or cell.flag then return end
    cell.open = true
    if cell.mine then
      dead = true
      sound.note("bit", 1, 2)
      return
    end
    uncovered = uncovered + 1
    if cell.near == 0 then
      forNeighbours(x, y, open)     -- flood the empty region
    end
  end

  local function checkWin()
    if uncovered >= W * H - MINES then
      won = true
      sound.note("bit", 1, 24)
    end
  end

  local function draw()
    local ox = math.max(1, math.floor((width - W * 2) / 2) + 1)
    local oy = 3

    term.setBackgroundColour(theme.colour.window)
    term.clear()
    local flags = 0
    for y = 1, H do for x = 1, W do if grid[y][x].flag then flags = flags + 1 end end end
    ui.row(term, 1, 1, width, " Mines   " .. (MINES - flags) .. " left",
      theme.colour.accentText, theme.colour.accent)

    for y = 1, H do
      for x = 1, W do
        local cell = grid[y][x]
        local px = ox + (x - 1) * 2
        local py = oy + y - 1
        if py > height - 1 then break end

        local bg, text, fg = colours.grey, "  ", colours.white
        if cell.open then
          bg = colours.lightGrey
          if cell.mine then bg, text, fg = colours.red, " *", colours.white
          elseif cell.near > 0 then
            text = " " .. cell.near
            fg = NUMBER_COLOUR[cell.near] or colours.black
          end
        elseif cell.flag then
          bg, text, fg = colours.orange, " F", colours.black
        end

        ui.fill(term, px, py, 2, 1, bg)
        ui.text(term, px, py, text, fg, bg)

        if x == cx and y == cy and not dead and not won then
          ui.text(term, px, py, "[", theme.colour.accent, bg)
        end
      end
    end

    if dead then
      ui.centre(term, height, " boom - any key ", colours.white, colours.red, 1, width)
    elseif won then
      ui.centre(term, height, " cleared! - any key ", colours.black, colours.lime, 1, width)
    else
      ui.row(term, 1, height, width, " [Enter] dig  [F] flag  arrows move",
        theme.colour.mutedText, theme.colour.muted)
    end
    return ox, oy
  end

  local ox, oy = draw()

  while true do
    local event, a, mx, my = os.pullEvent()

    if event == "key" then
      if dead or won then return uncovered end
      if a == keys.up then cy = math.max(1, cy - 1)
      elseif a == keys.down then cy = math.min(H, cy + 1)
      elseif a == keys.left then cx = math.max(1, cx - 1)
      elseif a == keys.right then cx = math.min(W, cx + 1)
      elseif a == keys.backspace then return uncovered
      elseif a == keys.f then
        local cell = grid[cy][cx]
        if not cell.open then cell.flag = not cell.flag end
      elseif a == keys.enter then
        if not seeded then seed(cx, cy) end
        open(cx, cy)
        if not dead then checkWin() end
      end
      ox, oy = draw()

    elseif event == "mouse_click" then
      if dead or won then return uncovered end
      local x = math.floor((mx - ox) / 2) + 1
      local y = my - oy + 1
      if grid[y] and grid[y][x] then
        cx, cy = x, y
        if a == 2 then
          local cell = grid[y][x]
          if not cell.open then cell.flag = not cell.flag end
        else
          if not seeded then seed(x, y) end
          open(x, y)
          if not dead then checkWin() end
        end
      end
      ox, oy = draw()

    elseif event == "term_resize" then
      return uncovered
    end
  end
end

return game
