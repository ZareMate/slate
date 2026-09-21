--[[ Snake. Returns the score so Minebit can keep a high score. ]]

local use = ...
local ui = use("system/ui")
local theme = use("system/theme")
local sound = use("system/sound")

local game = {}

function game.run(ctx)
  local width, height = term.getSize()
  local top = 2                          -- row 1 is the score bar
  local boardH = height - 1

  local snake = { { x = math.floor(width / 2), y = math.floor(height / 2) } }
  local dir = { x = 1, y = 0 }
  local nextDir = { x = 1, y = 0 }
  local score = 0
  local speed = 0.18
  local dead = false
  local food

  local function onSnake(x, y)
    for _, part in ipairs(snake) do
      if part.x == x and part.y == y then return true end
    end
    return false
  end

  local function placeFood()
    for _ = 1, 200 do
      local x = math.random(1, width)
      local y = math.random(top, top + boardH - 1)
      if not onSnake(x, y) then food = { x = x, y = y } return end
    end
    food = nil                            -- board full; player has won enough
  end

  local function draw()
    term.setBackgroundColour(colours.black)
    term.clear()
    ui.row(term, 1, 1, width, " Snake   " .. score,
      theme.colour.accentText, theme.colour.accent)

    if food then ui.fill(term, food.x, food.y, 1, 1, colours.red) end
    for index, part in ipairs(snake) do
      ui.fill(term, part.x, part.y, 1, 1, index == 1 and colours.lime or colours.green)
    end

    if dead then
      local text = " Game over - score " .. score .. " "
      ui.centre(term, math.floor(height / 2), text, colours.white, colours.red, 1, width)
      ui.centre(term, math.floor(height / 2) + 1, " any key to leave ",
        colours.white, colours.grey, 1, width)
    end
  end

  placeFood()
  draw()
  local tick = os.startTimer(speed)

  while true do
    local event, a = os.pullEvent()

    if event == "key" then
      local key = a
      if dead then return score end
      -- Reversing into yourself is a mistake, not an input.
      if key == keys.up and dir.y == 0 then nextDir = { x = 0, y = -1 }
      elseif key == keys.down and dir.y == 0 then nextDir = { x = 0, y = 1 }
      elseif key == keys.left and dir.x == 0 then nextDir = { x = -1, y = 0 }
      elseif key == keys.right and dir.x == 0 then nextDir = { x = 1, y = 0 }
      elseif key == keys.backspace then return score
      end

    elseif event == "timer" and a == tick then
      if not dead then
        dir = nextDir
        local head = snake[1]
        local nx, ny = head.x + dir.x, head.y + dir.y

        if nx < 1 or nx > width or ny < top or ny > top + boardH - 1 or onSnake(nx, ny) then
          dead = true
          sound.note("bit", 1, 4)
        else
          table.insert(snake, 1, { x = nx, y = ny })
          if food and nx == food.x and ny == food.y then
            score = score + 1
            speed = math.max(0.06, speed - 0.004)
            sound.note("bit", 1, math.min(24, 12 + score))
            placeFood()
          else
            table.remove(snake)
          end
        end
        draw()
      end
      tick = os.startTimer(speed)

    elseif event == "term_resize" then
      return score                        -- the board size is baked in; bail out
    end
  end
end

return game
