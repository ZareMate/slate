--[[ Slate - a windowed OS for ComputerCraft.

  Runs on the computer's own terminal. No monitor, no modem, no peripherals
  of any kind required.

  This file is the entry point and the module loader. Modules are loaded with
  loadfile() against this program's environment rather than require(), because
  that way Slate does not care what package.path happens to be, and modules
  still see `shell` - which the Terminal and Editor apps need.
]]

local ROOT = fs.getDir(shell.getRunningProgram())
local ENV = _ENV or _G

local loaded = {}

local function use(name)
  local cached = loaded[name]
  if cached ~= nil then return cached end

  local path = fs.combine(ROOT, name .. ".lua")
  if not fs.exists(path) then
    error("Slate: missing module '" .. name .. "' (looked in " .. path .. ")", 0)
  end

  local chunk, err = loadfile(path, nil, ENV)
  if not chunk then error("Slate: " .. tostring(err), 0) end

  local result = chunk(use)
  if result == nil then result = true end
  loaded[name] = result
  return result
end

local function splash()
  local w, h = term.getSize()
  term.setBackgroundColour(colours.black)
  term.clear()

  -- A ring, drawn with the same aspect correction the rest of the UI uses,
  -- so the logo is a circle and not an egg.
  local cx, cy = math.floor(w / 2), math.floor(h / 2) - 1
  for dy = -2, 2 do
    local outer = math.floor(math.sqrt(math.max(0, 4 - dy * dy)) * 1.8 + 0.5)
    local inner = math.floor(math.sqrt(math.max(0, 1 - dy * dy)) * 1.8 + 0.5)
    term.setBackgroundColour(colours.cyan)
    if math.abs(dy) >= 1 then
      term.setCursorPos(cx - outer, cy + dy)
      term.write((" "):rep(outer * 2 + 1))
    else
      term.setCursorPos(cx - outer, cy + dy)
      term.write((" "):rep(math.max(0, outer - inner)))
      term.setCursorPos(cx + inner + 1, cy + dy)
      term.write((" "):rep(math.max(0, outer - inner)))
    end
  end

  term.setBackgroundColour(colours.black)
  term.setTextColour(colours.cyan)
  local title = "S L A T E"
  term.setCursorPos(math.floor((w - #title) / 2) + 1, cy + 4)
  term.write(title)
end

local function boot()
  splash()
  local theme = use("system/theme")
  local kernel = use("system/kernel")
  local desktop = use("system/desktop")

  theme.load()      -- accent and wallpaper chosen in Settings last time
  theme.apply()

  -- First run gets a short setup before the desktop ever appears.
  local oobe = use("system/oobe")
  if oobe.needed() then oobe.run() end
  kernel.setRoot(ROOT)
  kernel.setDesktop(desktop)
  desktop.init(kernel, use)
  kernel.run()
end

term.setCursorBlink(false)
local ok, err = pcall(boot)

-- However Slate ended - clean exit, crash, or a module that would not load -
-- the terminal has to be handed back in a usable state.
local theme = loaded["system/theme"]
if type(theme) == "table" and theme.restore then pcall(theme.restore) end

term.redirect(term.native())
term.setBackgroundColour(colours.black)
term.setTextColour(colours.white)
term.clear()
term.setCursorPos(1, 1)
term.setCursorBlink(true)

if ok then
  print("Slate closed.")
else
  printError("Slate stopped: " .. tostring(err))
  print("")
  print("Run it again with: " .. shell.getRunningProgram())
end
