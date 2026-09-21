--[[ Pong, against the computer. Returns your score. ]]

local use = ...
local ui = use("system/ui")
local theme = use("system/theme")
local sound = use("system/sound")

local game = {}

local PADDLE = 3

function game.run(ctx)
  local width, height = term.getSize()
  local top, bottom = 2, height
  local floorH = bottom - top + 1

  local you = math.floor((floorH - PADDLE) / 2) + top
  local cpu = you
  local ballX, ballY = width / 2, height / 2
  local dx, dy = -0.9, 0.5
  local score, theirs = 0, 0
  local over = false
  local speed = 0.08

  local function reset(towards)
    ballX, ballY = width / 2, math.random(top + 1, bottom - 1)
    dx = towards
    dy = (math.random() < 0.5 and -0.5 or 0.5)
  end

  local function draw()
    term.setBackgroundColour(colours.black)
    term.clear()
    ui.row(term, 1, 1, width, " Pong   you " .. score .. "   cpu " .. theirs,
      theme.colour.accentText, theme.colour.accent)

    for offset = 0, PADDLE - 1 do
      ui.fill(term, 2, you + offset, 1, 1, colours.lime)
      ui.fill(term, width - 1, cpu + offset, 1, 1, colours.red)
    end
    ui.fill(term, math.floor(ballX), math.floor(ballY), 1, 1, colours.white)

    if over then
      local text = score > theirs and " you win " or " you lose "
      ui.centre(term, math.floor(height / 2), text, colours.black,
        score > theirs and colours.lime or colours.red, 1, width)
      ui.centre(term, math.floor(height / 2) + 1, " any key ",
        colours.white, colours.grey, 1, width)
    end
  end

  reset(-0.9)
  draw()
  local tick = os.startTimer(speed)

  while true do
    local event, a = os.pullEvent()

    if event == "key" then
      if over then return score end
      if a == keys.up then you = math.max(top, you - 2)
      elseif a == keys.down then you = math.min(bottom - PADDLE + 1, you + 2)
      elseif a == keys.backspace then return score
      end
      draw()

    elseif event == "timer" and a == tick then
      if not over then
        ballX = ballX + dx
        ballY = ballY + dy

        if ballY <= top then ballY, dy = top, -dy end
        if ballY >= bottom then ballY, dy = bottom, -dy end

        -- The paddle tracks the ball, but slowly enough to be beatable.
        local aim = ballY - math.floor(PADDLE / 2)
        if cpu < aim then cpu = math.min(cpu + 1, bottom - PADDLE + 1)
        elseif cpu > aim then cpu = math.max(cpu - 1, top) end

        local by = math.floor(ballY)
        if ballX <= 3 and dx < 0 then
          if by >= you and by < you + PADDLE then
            dx = -dx
            dy = dy + (by - (you + 1)) * 0.25
            sound.note("bit", 1, 14)
          else
            theirs = theirs + 1
            sound.note("bit", 1, 3)
            if theirs >= 5 then over = true else reset(0.9) end
          end
        elseif ballX >= width - 2 and dx > 0 then
          if by >= cpu and by < cpu + PADDLE then
            dx = -dx
            dy = dy + (by - (cpu + 1)) * 0.25
            sound.note("bit", 1, 16)
          else
            score = score + 1
            sound.note("bit", 1, 20)
            if score >= 5 then over = true else reset(-0.9) end
          end
        end

        dy = math.max(-1, math.min(1, dy))
        draw()
      end
      tick = os.startTimer(speed)

    elseif event == "term_resize" then
      return score
    end
  end
end

return game
