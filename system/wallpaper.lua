--[[ Wallpaper - the desktop background, animated or not.

  Every style draws over a base colour chosen in Settings, so the accent and
  wallpaper colours still drive the look; the animation is a layer on top.

  Two things keep this cheap enough to run at 5fps on a Minecraft computer:
  state is kept between frames rather than recomputed, and the desktop skips
  animation entirely when a fullscreen window is covering it - drawing frames
  nobody can see is the easiest performance mistake to make here.
]]

local use = ...

local wallpaper = {}

local KEY = "slate.wallpaper.style"

wallpaper.styles = {
  { id = "solid",   name = "Solid",   animated = false },
  { id = "stars",   name = "Stars",   animated = true },
  { id = "rain",    name = "Rain",    animated = true },
  { id = "waves",   name = "Waves",   animated = true },
  { id = "bubbles", name = "Bubbles", animated = true },
  { id = "matrix",  name = "Matrix",  animated = true },
}

wallpaper.style = 1

local frame = 0
local drops = {}
local bubbles = {}
local stars = {}

--------------------------------------------------------------------------

function wallpaper.current()
  return wallpaper.styles[wallpaper.style] or wallpaper.styles[1]
end

function wallpaper.animated()
  return wallpaper.current().animated == true
end

function wallpaper.setStyle(index)
  wallpaper.style = ((index - 1) % #wallpaper.styles) + 1
  drops, bubbles, stars = {}, {}, {}
end

function wallpaper.load()
  pcall(function()
    local saved = settings.get(KEY)
    if type(saved) == "number" then wallpaper.style = saved end
  end)
  wallpaper.style = ((wallpaper.style - 1) % #wallpaper.styles) + 1
end

function wallpaper.persist()
  pcall(function()
    settings.set(KEY, wallpaper.style)
    settings.save()
  end)
end

function wallpaper.tick()
  frame = frame + 1
end

--------------------------------------------------------------------------
-- styles
--------------------------------------------------------------------------

local function seed(list, count, make)
  while #list < count do list[#list + 1] = make() end
end

local function drawStars(win, W, H, fill)
  seed(stars, math.floor(W * H / 22), function()
    return { x = math.random(1, W), y = math.random(1, H), phase = math.random(0, 9) }
  end)
  for _, star in ipairs(stars) do
    local lit = (frame + star.phase) % 10
    if lit < 4 then
      fill(star.x, star.y, 1, lit < 2 and colours.white or colours.lightGrey)
    end
  end
end

local function drawRain(win, W, H, fill)
  seed(drops, math.floor(W / 2), function()
    return { x = math.random(1, W), y = math.random(1, H), speed = math.random(1, 2) }
  end)
  for _, drop in ipairs(drops) do
    drop.y = drop.y + drop.speed
    if drop.y > H then
      drop.y = 1
      drop.x = math.random(1, W)
    end
    fill(drop.x, math.floor(drop.y), 1, colours.lightBlue)
    if drop.y > 1 then fill(drop.x, math.floor(drop.y) - 1, 1, colours.blue) end
  end
end

local function drawWaves(win, W, H, fill)
  for y = 1, H do
    local offset = math.sin((y * 0.6) + frame * 0.35) * 3
    local x = math.floor(W / 2 + offset)
    fill(math.max(1, x - 2), y, math.min(5, W), colours.lightBlue)
  end
end

local function drawBubbles(win, W, H, fill)
  seed(bubbles, 7, function()
    return { x = math.random(1, W), y = H + math.random(0, 6), r = math.random(1, 2) }
  end)
  for _, bubble in ipairs(bubbles) do
    bubble.y = bubble.y - 0.45
    if bubble.y < -3 then
      bubble.y = H + math.random(0, 5)
      bubble.x = math.random(1, W)
      bubble.r = math.random(1, 2)
    end
    -- A ring, aspect-corrected the same way ui.ring does it.
    local cy = math.floor(bubble.y)
    for dy = -bubble.r, bubble.r do
      local outer = math.floor(math.sqrt(math.max(0, bubble.r * bubble.r - dy * dy)) * 1.8 + 0.5)
      local row = cy + dy
      if row >= 1 and row <= H then
        if math.abs(dy) >= bubble.r then
          fill(bubble.x - outer, row, outer * 2 + 1, colours.lightBlue)
        else
          fill(bubble.x - outer, row, 1, colours.lightBlue)
          fill(bubble.x + outer, row, 1, colours.lightBlue)
        end
      end
    end
  end
end

local function drawMatrix(win, W, H, fill)
  seed(drops, math.floor(W / 2), function()
    return { x = math.random(1, W), y = math.random(1, H), speed = 1, tail = math.random(3, 6) }
  end)
  for _, drop in ipairs(drops) do
    drop.y = drop.y + drop.speed
    if drop.y - drop.tail > H then
      drop.y = 0
      drop.x = math.random(1, W)
      drop.tail = math.random(3, 6)
    end
    for step = 0, drop.tail do
      local row = math.floor(drop.y) - step
      if row >= 1 and row <= H then
        fill(drop.x, row, 1, step == 0 and colours.lime or colours.green)
      end
    end
  end
end

local RENDER = {
  stars = drawStars, rain = drawRain, waves = drawWaves,
  bubbles = drawBubbles, matrix = drawMatrix,
}

--------------------------------------------------------------------------

-- base is the wallpaper colour from the theme; the style paints over it.
function wallpaper.draw(win, W, H, base)
  -- One blit per row for the base, then the style on top.
  local blank = (" "):rep(W)
  local run = colours.toBlit(base):rep(W)
  for y = 1, H do
    win.setCursorPos(1, y)
    win.blit(blank, run, run)
  end

  local render = RENDER[wallpaper.current().id]
  if not render then return end

  local function fill(x, y, w, colour)
    if y < 1 or y > H then return end
    local from = math.max(1, x)
    local span = math.min(w - (from - x), W - from + 1)
    if span < 1 then return end
    local text = (" "):rep(span)
    local colourRun = colours.toBlit(colour):rep(span)
    win.setCursorPos(from, y)
    win.blit(text, colourRun, colourRun)
  end

  render(win, W, H, fill)
end

return wallpaper
