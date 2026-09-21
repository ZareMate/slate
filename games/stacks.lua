--[[ Stacks - falling blocks. Returns the score. ]]

local use = ...
local ui = use("system/ui")
local theme = use("system/theme")
local sound = use("system/sound")

local game = {}

local W, H = 10, 16

local SHAPES = {
  { colour = colours.cyan,      cells = { { 1, 1 }, { 2, 1 }, { 3, 1 }, { 4, 1 } } },  -- I
  { colour = colours.yellow,    cells = { { 1, 1 }, { 2, 1 }, { 1, 2 }, { 2, 2 } } },  -- O
  { colour = colours.purple,    cells = { { 2, 1 }, { 1, 2 }, { 2, 2 }, { 3, 2 } } },  -- T
  { colour = colours.lime,      cells = { { 2, 1 }, { 3, 1 }, { 1, 2 }, { 2, 2 } } },  -- S
  { colour = colours.red,       cells = { { 1, 1 }, { 2, 1 }, { 2, 2 }, { 3, 2 } } },  -- Z
  { colour = colours.blue,      cells = { { 1, 1 }, { 1, 2 }, { 2, 2 }, { 3, 2 } } },  -- J
  { colour = colours.orange,    cells = { { 3, 1 }, { 1, 2 }, { 2, 2 }, { 3, 2 } } },  -- L
}

function game.run(ctx)
  local width, height = term.getSize()
  local board = {}
  for y = 1, H do
    board[y] = {}
    for x = 1, W do board[y][x] = nil end
  end

  local piece, px, py
  local score, lines = 0, 0
  local over = false
  local fall = 0.5

  local function spawn()
    local shape = SHAPES[math.random(1, #SHAPES)]
    piece = { colour = shape.colour, cells = {} }
    for index, cell in ipairs(shape.cells) do
      piece.cells[index] = { cell[1], cell[2] }
    end
    px, py = math.floor(W / 2) - 1, 0
  end

  local function fits(cells, atX, atY)
    for _, cell in ipairs(cells) do
      local x, y = atX + cell[1], atY + cell[2]
      if x < 1 or x > W or y > H then return false end
      if y >= 1 and board[y][x] then return false end
    end
    return true
  end

  local function rotate()
    -- Rotate about the piece's own bounding box, clockwise.
    local maxY = 0
    for _, cell in ipairs(piece.cells) do maxY = math.max(maxY, cell[2]) end
    local turned = {}
    for index, cell in ipairs(piece.cells) do
      turned[index] = { maxY - cell[2] + 1, cell[1] }
    end
    if fits(turned, px, py) then piece.cells = turned end
  end

  local function settle()
    for _, cell in ipairs(piece.cells) do
      local x, y = px + cell[1], py + cell[2]
      if y < 1 then over = true return end
      board[y][x] = piece.colour
    end

    local cleared = 0
    for y = H, 1, -1 do
      local full = true
      for x = 1, W do
        if not board[y][x] then full = false break end
      end
      if full then
        table.remove(board, y)
        table.insert(board, 1, {})
        cleared = cleared + 1
        y = y + 1
      end
    end

    if cleared > 0 then
      lines = lines + cleared
      score = score + ({ 40, 100, 300, 1200 })[cleared]
      fall = math.max(0.12, 0.5 - lines * 0.01)
      sound.note("bit", 1, math.min(24, 14 + cleared * 3))
    end
    spawn()
    if not fits(piece.cells, px, py) then over = true end
  end

  local function draw()
    local ox = math.max(1, math.floor((width - W * 2) / 2) + 1)
    local oy = math.max(2, math.floor((height - H) / 2) + 1)

    term.setBackgroundColour(colours.black)
    term.clear()
    ui.row(term, 1, 1, width, " Stacks   " .. score .. "   lines " .. lines,
      theme.colour.accentText, theme.colour.accent)

    for y = 1, H do
      for x = 1, W do
        local cell = board[y][x]
        ui.fill(term, ox + (x - 1) * 2, oy + y - 1, 2, 1, cell or colours.grey)
      end
    end

    if not over then
      for _, cell in ipairs(piece.cells) do
        local x, y = px + cell[1], py + cell[2]
        if y >= 1 then
          ui.fill(term, ox + (x - 1) * 2, oy + y - 1, 2, 1, piece.colour)
        end
      end
    else
      ui.centre(term, oy + math.floor(H / 2), " game over ", colours.white, colours.red, 1, width)
      ui.centre(term, oy + math.floor(H / 2) + 1, " any key ", colours.white, colours.grey, 1, width)
    end

    ui.row(term, 1, height, width, " arrows move  [Up] rotate  [Space] drop",
      theme.colour.mutedText, theme.colour.muted)
  end

  spawn()
  draw()
  local tick = os.startTimer(fall)

  while true do
    local event, a = os.pullEvent()

    if event == "key" then
      if over then return score end
      if a == keys.left and fits(piece.cells, px - 1, py) then px = px - 1
      elseif a == keys.right and fits(piece.cells, px + 1, py) then px = px + 1
      elseif a == keys.down and fits(piece.cells, px, py + 1) then py = py + 1
      elseif a == keys.up then rotate()
      elseif a == keys.space then
        while fits(piece.cells, px, py + 1) do py = py + 1 end
        settle()
      elseif a == keys.backspace then return score
      end
      draw()

    elseif event == "timer" and a == tick then
      if not over then
        if fits(piece.cells, px, py + 1) then py = py + 1 else settle() end
        draw()
      end
      tick = os.startTimer(fall)

    elseif event == "term_resize" then
      draw()
    end
  end
end

return game
