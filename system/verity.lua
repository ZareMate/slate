--[[ Verity - the thing that watches.

  Slate's apps run with full access to the computer; there is no sandbox and
  pretending otherwise would be a lie. What there is instead is a tripwire.
  When something tries to gut the OS or read the tokens out of settings, the
  app that noticed calls verity.report(), and after enough of that Verity
  wakes up.

  Like FreeRAM, this SIMULATES. Nothing is deleted, nothing is corrupted, no
  file is touched. It sets a flag and makes the desktop look haunted while
  that flag is set - and Zare's Antivirus clears it, because there was never
  any real damage to undo.

  What it actually does is refuse the action that tripped it. That part is
  not a joke: a delete of /system is blocked whether or not you find the
  staring eye funny.
]]

local use = ...
local ui = use("system/ui")
local sound = use("system/sound")

local verity = {}

local FLAG = "slate.verity"
local STRIKES = "slate.verity.strikes"

local WATCHING = {
  "IT SEES YOU",
  "WHY DID YOU DO THAT",
  "I WAS HERE FIRST",
  "PUT IT BACK",
  "VERITY IS AWAKE",
  "YOU WERE WARNED",
}

-- Paths that nothing has any business deleting. Checked as prefixes, so
-- /system/kernel.lua is covered by /system.
local PROTECTED = { "/system", "/startup.lua", "/manifest.json", "/index.json" }

-- Things a console line has no innocent reason to be doing.
local FORBIDDEN = {
  { pattern = "settings%.get%s*%(%s*[\"']slate%..-token", why = "reading a stored token" },
  { pattern = "settings%.get%s*%(%s*[\"']slate%..-key", why = "reading a stored key" },
  { pattern = "fs%.delete%s*%(%s*[\"']/system", why = "deleting the system folder" },
  { pattern = "fs%.delete%s*%(%s*[\"']/startup", why = "deleting the boot script" },
  { pattern = "fs%.delete%s*%(%s*[\"']/[\"']", why = "deleting the whole disk" },
}

--------------------------------------------------------------------------

function verity.active()
  local ok, value = pcall(settings.get, FLAG)
  return ok and value == true
end

function verity.strikes()
  local ok, value = pcall(settings.get, STRIKES)
  return (ok and type(value) == "number") and value or 0
end

local function setStrikes(count)
  pcall(function()
    settings.set(STRIKES, count)
    settings.save()
  end)
end

function verity.wake()
  pcall(function()
    settings.set(FLAG, true)
    settings.save()
  end)
end

function verity.cure()
  pcall(function()
    settings.unset(FLAG)
    settings.unset(STRIKES)
    settings.save()
  end)
end

function verity.message()
  return WATCHING[math.random(1, #WATCHING)]
end

--------------------------------------------------------------------------
-- the tripwires
--------------------------------------------------------------------------

-- True when a path is part of the OS itself.
function verity.isProtected(path)
  if type(path) ~= "string" then return false end
  local tidy = "/" .. tostring(path):gsub("^/+", "")
  for _, guarded in ipairs(PROTECTED) do
    if tidy == guarded or tidy:sub(1, #guarded + 1) == guarded .. "/" then
      return true
    end
  end
  return false
end

-- Returns a reason when a line of code is doing something it should not.
function verity.inspect(source)
  if type(source) ~= "string" then return nil end
  local flat = source:gsub("%s+", " ")
  for _, rule in ipairs(FORBIDDEN) do
    if flat:find(rule.pattern) then return rule.why end
  end
  return nil
end

-- Called by whatever caught it. Returns true once Verity is awake, so the
-- caller knows the action was not just refused but noticed.
function verity.report(why)
  local count = verity.strikes() + 1
  setStrikes(count)
  if count >= 2 then
    verity.wake()
    return true, count, why
  end
  return false, count, why
end

--------------------------------------------------------------------------
-- how it looks
--------------------------------------------------------------------------

-- A slow horizontal scan, plus the occasional word. Drawn under the icons so
-- the desktop stays usable: this is meant to be unsettling, not a lockout.
function verity.haunt(win, W, H, frame)
  local row = (frame % (H + 6)) + 1
  if row <= H then
    win.setCursorPos(1, row)
    local run = colours.toBlit(colours.red):rep(W)
    win.blit((" "):rep(W), run, run)
  end

  for _ = 1, 6 do
    local x, y = math.random(1, W), math.random(1, H)
    win.setCursorPos(x, y)
    win.setBackgroundColour(colours.black)
    win.setTextColour(colours.red)
    win.write(("?!#%"):sub(math.random(1, 4), math.random(1, 4)))
  end

  if frame % 11 == 0 then
    local text = verity.message()
    local x = math.max(1, math.floor((W - #text) / 2))
    local y = math.max(1, math.floor(H / 2))
    win.setCursorPos(x, y)
    win.setBackgroundColour(colours.black)
    win.setTextColour(colours.red)
    win.write(text:sub(1, W))
  end
end

function verity.banner()
  return " VERITY "
end

--------------------------------------------------------------------------
-- the wake-up
--
-- Lives here rather than in apps/ so it ships with the OS: the scare has to
-- work on a computer that has never downloaded anything.
--------------------------------------------------------------------------

local EYE = {
  "   eeeeeee   ",
  " ee       ee ",
  "e    fff    e",
  "e   fffff   e",
  "e    fff    e",
  " ee       ee ",
  "   eeeeeee   ",
}

local function drawEye(x, y, open)
  for row = 1, #EYE do
    local line = EYE[row]
    for column = 1, #line do
      local cell = line:sub(column, column)
      if cell ~= " " then
        -- A blink: the pupil rows collapse to the lid colour.
        local shown = cell
        if not open and row >= 3 and row <= 5 then shown = "e" end
        local colour = 2 ^ tonumber(shown, 16)
        ui.fill(term, x + column - 1, y + row - 1, 1, 1, colour)
      end
    end
  end
end

function verity.scene(ctx, why)
  local width, height = term.getSize()
  why = tostring(why or "something it did not like")

  local function noise(count, colour)
    for _ = 1, count do
      term.setCursorPos(math.random(1, width), math.random(1, height))
      term.setBackgroundColour(colours.black)
      term.setTextColour(colour)
      term.write(("?!#%@"):sub(math.random(1, 5), math.random(1, 5)))
    end
  end

  -- It arrives.
  for step = 1, 14 do
    term.setBackgroundColour(colours.black)
    term.clear()
    noise(step * 3, step % 2 == 0 and colours.red or colours.grey)
    if step > 6 then
      drawEye(math.floor((width - 13) / 2) + 1,
        math.floor((height - #EYE) / 2), step % 5 ~= 0)
    end
    sound.note("bit", 1, math.max(0, 8 - math.floor(step / 2)))
    sleep(0.09)
  end

  -- It speaks.
  term.setBackgroundColour(colours.black)
  term.clear()
  drawEye(math.floor((width - 13) / 2) + 1, 2, true)

  ui.centre(term, height - 6, "VERITY", colours.red, colours.black, 1, width)
  ui.centre(term, height - 4, "caught you " .. ui.clip(why, width - 14),
    colours.white, colours.black, 1, width)
  ui.centre(term, height - 2, "that was not allowed",
    colours.grey, colours.black, 1, width)
  ui.centre(term, height, " any key ", colours.black, colours.red, 1, width)

  for _, pitch in ipairs({ 6, 4, 2, 0 }) do
    sound.note("bass", 2, pitch)
    sleep(0.18)
  end

  os.pullEvent("key")
end

return verity
