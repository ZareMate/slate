--[[ Zare's Antivirus - the cure for FreeRAM.exe.

  Scans (theatrically), finds the one thing there is to find, and clears the
  infection flag. Because FreeRAM only ever simulated damage, removing the
  flag genuinely restores everything - there is nothing left broken.

  Also offers to delete FreeRAM.exe itself, which stops it being run again but
  is NOT what cures the infection. That distinction is the whole joke.
]]

local use = ...
local ui = use("system/ui")
local theme = use("system/theme")
local sound = use("system/sound")
local infection = use("system/infection")
local catalog = use("system/catalog")

local app = {}

local SCAN = {
  "/startup.lua", "/system/kernel.lua", "/system/desktop.lua",
  "/apps/files.lua", "/apps/freeram.lua", "/system/theme.lua",
  "/apps/terminal.lua", "/games/snake.lua",
}

function app.run(ctx)
  local width, height = term.getSize()
  local state = "idle"
  local found = false

  local function centre(y, text, fg, bg)
    ui.centre(term, y, text, fg, bg, 1, width)
  end

  local function frame()
    term.setBackgroundColour(theme.colour.window)
    term.clear()
    ui.row(term, 1, 1, width, " " .. ui.spaced("Zare"),
      theme.colour.accentText, colours.green)
    ui.text(term, 2, 2, "Antivirus", theme.colour.mutedText, theme.colour.window)
  end

  local function idle()
    frame()
    if infection.active() then
      centre(5, " 1 THREAT ACTIVE ", colours.white, colours.red)
      centre(7, "FreeRAM.exe is on this computer.", theme.colour.windowText, theme.colour.window)
    else
      centre(5, " No threats found ", colours.white, colours.green)
      centre(7, "This computer is clean.", theme.colour.mutedText, theme.colour.window)
    end
    ui.row(term, 1, height, width, " [Enter] scan now",
      theme.colour.mutedText, theme.colour.muted)
  end

  local function scan()
    state = "scanning"
    found = infection.active()

    for index, path in ipairs(SCAN) do
      frame()
      centre(4, "Scanning...", theme.colour.windowText, theme.colour.window)
      ui.text(term, 2, 6, ui.clip(path, width - 2),
        theme.colour.mutedText, theme.colour.window)

      local bar = width - 4
      local filled = math.floor(bar * index / #SCAN + 0.5)
      ui.fill(term, 3, 8, bar, 1, theme.colour.muted)
      if filled > 0 then ui.fill(term, 3, 8, filled, 1, colours.green) end
      centre(10, index .. " of " .. #SCAN .. " files", theme.colour.mutedText, theme.colour.window)

      sound.note("bit", 1, 8 + index)
      sleep(0.35)
    end

    frame()
    if not found then
      centre(5, " Clean ", colours.white, colours.green)
      centre(7, "Nothing to remove.", theme.colour.mutedText, theme.colour.window)
      state = "idle"
      ui.row(term, 1, height, width, " [Enter] scan again",
        theme.colour.mutedText, theme.colour.muted)
      return
    end

    centre(4, " THREAT FOUND ", colours.white, colours.red)
    centre(6, "Trojan.FreeRAM", theme.colour.windowText, theme.colour.window)
    centre(8, "Remove it?", theme.colour.windowText, theme.colour.window)
    ui.row(term, 1, height, width, " [Y] remove    [N] leave it",
      theme.colour.mutedText, theme.colour.muted)
    state = "found"
  end

  local function remove()
    frame()
    centre(5, "Removing Trojan.FreeRAM...", theme.colour.windowText, theme.colour.window)
    sleep(0.8)

    infection.cure()

    -- Deleting the app is optional and separate: it stops FreeRAM being run
    -- again, but it is the flag above that was actually making a mess.
    if not catalog.isBuiltin("freeram") then
      pcall(catalog.uninstall, "freeram", ctx.root())
    end

    for _, pitch in ipairs({ 12, 16, 19, 24 }) do
      sound.note("bit", 1, pitch)
      sleep(0.12)
    end

    frame()
    centre(5, " Threat removed ", colours.white, colours.green)
    centre(7, "Your computer is clean.", theme.colour.windowText, theme.colour.window)
    centre(9, "You're welcome. - Zare", theme.colour.mutedText, theme.colour.window)
    ctx.notify("Zare removed Trojan.FreeRAM")
    ctx.redraw()
    state = "idle"
    ui.row(term, 1, height, width, " [Enter] scan again",
      theme.colour.mutedText, theme.colour.muted)
  end

  idle()

  while true do
    local event, key = os.pullEvent()
    if event == "key" then
      if state == "found" then
        if key == keys.y then remove()
        elseif key == keys.n then state = "idle"; idle() end
      elseif state == "idle" and key == keys.enter then
        scan()
      end
    elseif event == "term_resize" then
      width, height = term.getSize()
      if state == "idle" then idle() end
    end
  end
end

return app
