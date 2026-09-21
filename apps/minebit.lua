--[[ Minebit - the game launcher.

  Games run inside this window rather than spawning their own: on a 51x19
  screen a game wants every row it can get, and handing it the launcher's
  window is the simplest way to do that. A game returns its score, Minebit
  records the high score, and the list comes back.
]]

local use = ...
local ui = use("system/ui")
local theme = use("system/theme")
local catalogue = use("system/games")

local app = {}

local function highScore(id)
  local ok, value = pcall(settings.get, "slate.score." .. id)
  if ok and type(value) == "number" then return value end
  return 0
end

local function setHighScore(id, score)
  pcall(function()
    settings.set("slate.score." .. id, score)
    settings.save()
  end)
end

function app.run(ctx)
  local index = 1
  local notice = nil
  local noticeUntil = 0

  local function draw()
    local width, height = term.getSize()
    term.setBackgroundColour(theme.colour.window)
    term.clear()
    ui.row(term, 1, 1, width, " MINEBIT", theme.colour.accentText, theme.colour.accent)

    local y = 3
    for position, entry in ipairs(catalogue) do
      if y > height - 2 then break end
      local on = (position == index)
      local best = highScore(entry.id)
      local right = best > 0 and ("best " .. best) or ""
      local room = math.max(1, width - #right - 6)

      ui.fill(term, 2, y, 3, 1, entry.colour)
      ui.text(term, 3, y, entry.title:sub(1, 1), colours.black, entry.colour)
      ui.row(term, 5, y, width - 5,
        " " .. ui.pad(ui.clip(entry.title, room), room) .. " " .. right,
        on and theme.colour.accentText or theme.colour.windowText,
        on and theme.colour.accent or theme.colour.window)
      ui.text(term, 6, y + 1, ui.clip(entry.blurb, width - 7),
        theme.colour.mutedText, theme.colour.window)
      y = y + 3
    end

    if notice and os.clock() < noticeUntil then
      ui.row(term, 1, height, width, " " .. notice, colours.white, theme.colour.ok)
    else
      ui.row(term, 1, height, width, " [Enter] play   arrows to choose",
        theme.colour.mutedText, theme.colour.muted)
    end
  end

  local function play(entry)
    local ok, game = pcall(use, entry.module)
    if not ok or type(game) ~= "table" or type(game.run) ~= "function" then
      notice = "Could not load " .. entry.title
      noticeUntil = os.clock() + 4
      return
    end

    ctx.setTitle("Minebit - " .. entry.title)
    -- A game that crashes must not take the launcher with it.
    local played, score = pcall(game.run, ctx)
    ctx.setTitle("Minebit")

    if not played then
      notice = entry.title .. " crashed"
      noticeUntil = os.clock() + 4
      return
    end

    score = tonumber(score) or 0
    if score > highScore(entry.id) then
      setHighScore(entry.id, score)
      notice = "New best: " .. score .. "!"
    else
      notice = "Scored " .. score
    end
    noticeUntil = os.clock() + 4
  end

  draw()

  while true do
    local event, a, _, y = os.pullEvent()

    if event == "key" then
      if a == keys.down then index = math.min(#catalogue, index + 1)
      elseif a == keys.up then index = math.max(1, index - 1)
      elseif a == keys.enter then play(catalogue[index])
      end
      draw()

    elseif event == "mouse_click" then
      local clicked = math.floor((y - 3) / 3) + 1
      if catalogue[clicked] then
        if clicked == index then play(catalogue[clicked]) else index = clicked end
      end
      draw()

    elseif event == "term_resize" then
      draw()
    end
  end
end

return app
