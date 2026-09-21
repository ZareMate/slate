--[[ Blocks - slide and merge to 2048. Returns the score. ]]

local use = ...
local ui = use("system/ui")
local theme = use("system/theme")
local sound = use("system/sound")

local game = {}

local SIZE = 4
local CELL_W, CELL_H = 6, 2

local TILE = {
  [2] = colours.lightGrey, [4] = colours.white,   [8] = colours.orange,
  [16] = colours.yellow,   [32] = colours.lime,   [64] = colours.green,
  [128] = colours.cyan,    [256] = colours.lightBlue, [512] = colours.blue,
  [1024] = colours.purple, [2048] = colours.magenta,
}

function game.run(ctx)
  local width, height = term.getSize()
  local board = {}
  local score = 0
  local over = false
  local won = false

  for y = 1, SIZE do
    board[y] = {}
    for x = 1, SIZE do board[y][x] = 0 end
  end

  local function freeCells()
    local free = {}
    for y = 1, SIZE do
      for x = 1, SIZE do
        if board[y][x] == 0 then free[#free + 1] = { x = x, y = y } end
      end
    end
    return free
  end

  local function spawn()
    local free = freeCells()
    if #free == 0 then return false end
    local cell = free[math.random(1, #free)]
    board[cell.y][cell.x] = (math.random() < 0.9) and 2 or 4
    return true
  end

  -- Slide one line toward index 1, merging each pair once.
  local function collapse(line)
    local out, moved = {}, false
    for _, value in ipairs(line) do
      if value ~= 0 then out[#out + 1] = value end
    end
    local merged = {}
    local i = 1
    while i <= #out do
      if out[i + 1] and out[i] == out[i + 1] then
        merged[#merged + 1] = out[i] * 2
        score = score + out[i] * 2
        if out[i] * 2 == 2048 then won = true end
        i = i + 2
        moved = true
      else
        merged[#merged + 1] = out[i]
        i = i + 1
      end
    end
    for n = 1, SIZE do
      local value = merged[n] or 0
      if line[n] ~= value then moved = true end
      line[n] = value
    end
    return moved
  end

  local function readLine(index, dir)
    local line = {}
    for n = 1, SIZE do
      local step = (dir == "left" or dir == "up") and n or (SIZE - n + 1)
      line[n] = (dir == "left" or dir == "right") and board[index][step] or board[step][index]
    end
    return line
  end

  local function writeLine(index, dir, line)
    for n = 1, SIZE do
      local step = (dir == "left" or dir == "up") and n or (SIZE - n + 1)
      if dir == "left" or dir == "right" then
        board[index][step] = line[n]
      else
        board[step][index] = line[n]
      end
    end
  end

  local function slide(dir)
    local moved = false
    for index = 1, SIZE do
      local line = readLine(index, dir)
      if collapse(line) then moved = true end
      writeLine(index, dir, line)
    end
    return moved
  end

  local function canMove()
    if #freeCells() > 0 then return true end
    for y = 1, SIZE do
      for x = 1, SIZE do
        if x < SIZE and board[y][x] == board[y][x + 1] then return true end
        if y < SIZE and board[y][x] == board[y + 1][x] then return true end
      end
    end
    return false
  end

  local function draw()
    local boardW, boardH = SIZE * CELL_W, SIZE * CELL_H
    local ox = math.max(1, math.floor((width - boardW) / 2) + 1)
    local oy = math.max(2, math.floor((height - boardH) / 2) + 1)

    term.setBackgroundColour(colours.black)
    term.clear()
    ui.row(term, 1, 1, width, " Blocks   " .. score,
      theme.colour.accentText, theme.colour.accent)

    for y = 1, SIZE do
      for x = 1, SIZE do
        local value = board[y][x]
        local cx = ox + (x - 1) * CELL_W
        local cy = oy + (y - 1) * CELL_H
        local bg = value == 0 and colours.grey or (TILE[value] or colours.red)
        ui.fill(term, cx, cy, CELL_W - 1, CELL_H, bg)
        if value ~= 0 then
          local label = tostring(value)
          ui.text(term, cx + math.floor((CELL_W - 1 - #label) / 2), cy,
            label, value >= 8 and colours.white or colours.black, bg)
        end
      end
    end

    if over then
      ui.centre(term, height, " no moves left - any key ", colours.white, colours.red, 1, width)
    elseif won then
      ui.centre(term, height, " 2048! keep going ", colours.black, colours.lime, 1, width)
    else
      ui.centre(term, height, " arrows to slide, backspace to quit ",
        theme.colour.mutedText, colours.black, 1, width)
    end
  end

  spawn()
  spawn()
  draw()

  while true do
    local event, key = os.pullEvent()

    if event == "key" then
      if over then return score end
      local dir
      if key == keys.left then dir = "left"
      elseif key == keys.right then dir = "right"
      elseif key == keys.up then dir = "up"
      elseif key == keys.down then dir = "down"
      elseif key == keys.backspace then return score
      end

      if dir then
        if slide(dir) then
          spawn()
          sound.note("bit", 1, 14)
        end
        if not canMove() then
          over = true
          sound.note("bit", 1, 4)
        end
        draw()
      end

    elseif event == "term_resize" then
      draw()
    end
  end
end

return game
