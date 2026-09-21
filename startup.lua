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
  term.setTextColour(colours.cyan)
  term.clear()
  local title = "Slate"
  term.setCursorPos(math.floor((w - #title) / 2) + 1, math.floor(h / 2))
  term.write(title)
  term.setTextColour(colours.grey)
  local note = "starting"
  term.setCursorPos(math.floor((w - #note) / 2) + 1, math.floor(h / 2) + 1)
  term.write(note)
end

local function boot()
  splash()
  local theme = use("system/theme")
  local kernel = use("system/kernel")
  local desktop = use("system/desktop")

  theme.load()      -- accent and wallpaper chosen in Settings last time
  theme.apply()
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
