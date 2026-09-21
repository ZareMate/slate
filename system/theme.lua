--[[ Slate theme.

  Semantic colour names so nothing else in the OS reaches for a raw colour,
  plus a palette tweak on advanced computers. Basic computers render every
  colour as greyscale, so the UI must never rely on hue alone to tell two
  things apart - that is what the focus highlight and the [ ] markers are for.

  Accent and wallpaper are picked in Settings and persisted through CC's own
  settings API, so the choice survives a reboot without Slate owning a config
  file of its own.
]]

local theme = {}

theme.colour = {
  desktop     = colours.cyan,
  desktopText = colours.white,

  bar         = colours.grey,
  barText     = colours.white,
  barHot      = colours.lightGrey,

  window      = colours.white,
  windowText  = colours.black,

  titleOn     = colours.blue,
  titleOff    = colours.grey,
  titleText   = colours.white,

  accent      = colours.blue,
  accentText  = colours.white,
  muted       = colours.lightGrey,
  mutedText   = colours.grey,

  danger      = colours.red,
  ok          = colours.lime,
  warn        = colours.orange,
}

-- Offered in Settings. Kept short deliberately: every one of these has to stay
-- readable against white title text and in greyscale on a basic computer.
theme.accents = {
  { name = "Blue",   colour = colours.blue },
  { name = "Teal",   colour = colours.cyan },
  { name = "Green",  colour = colours.green },
  { name = "Purple", colour = colours.purple },
  { name = "Red",    colour = colours.red },
  { name = "Brown",  colour = colours.brown },
}

theme.wallpapers = {
  { name = "Teal",   colour = colours.cyan },
  { name = "Slate",  colour = colours.grey },
  { name = "Blue",   colour = colours.blue },
  { name = "Green",  colour = colours.green },
  { name = "Purple", colour = colours.purple },
  { name = "Black",  colour = colours.black },
}

theme.accent = 1
theme.wallpaper = 1

-- Only these get overridden; everything else keeps CraftOS's defaults so
-- programs running inside a Slate window still look the way they expect.
local palette = {
  [colours.cyan]      = 0x1d5b58,
  [colours.grey]      = 0x2b3440,
  [colours.lightGrey] = 0xa7b2bd,
  [colours.blue]      = 0x2f6fd0,
}

local applied = false

function theme.isColour()
  return term.isColour and term.isColour()
end

local function refresh()
  local accent = theme.accents[theme.accent] or theme.accents[1]
  local wallpaper = theme.wallpapers[theme.wallpaper] or theme.wallpapers[1]
  theme.colour.accent = accent.colour
  theme.colour.titleOn = accent.colour
  theme.colour.desktop = wallpaper.colour
end

function theme.setAccent(index)
  theme.accent = ((index - 1) % #theme.accents) + 1
  refresh()
end

function theme.setWallpaper(index)
  theme.wallpaper = ((index - 1) % #theme.wallpapers) + 1
  refresh()
end

function theme.load()
  -- A computer with no saved settings, or a read-only one, just keeps defaults.
  pcall(function()
    settings.load()
    local accent = settings.get("slate.accent")
    local wallpaper = settings.get("slate.wallpaper")
    if type(accent) == "number" then theme.accent = accent end
    if type(wallpaper) == "number" then theme.wallpaper = wallpaper end
  end)
  refresh()
end

function theme.persist()
  return pcall(function()
    settings.set("slate.accent", theme.accent)
    settings.set("slate.wallpaper", theme.wallpaper)
    settings.save()
  end)
end

function theme.apply()
  if applied or not theme.isColour() then return end
  for colour, hex in pairs(palette) do
    -- A terminal that refuses palette changes is not a reason to fail booting.
    pcall(term.setPaletteColour, colour, hex)
  end
  applied = true
end

function theme.restore()
  if not applied then return end
  for colour in pairs(palette) do
    pcall(term.setPaletteColour, colour, term.nativePaletteColour(colour))
  end
  applied = false
end

return theme
