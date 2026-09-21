--[[ The built-in app registry.

  `icon` is 3 rows of 7 blit colour characters - real pixel art at character
  resolution, which is why the desktop no longer shows coloured squares with a
  letter in them. A space means "leave the wallpaper showing", so icons are not
  forced to be rectangles.

  blit colours: 0 white 1 orange 2 magenta 3 lightBlue 4 yellow 5 lime
                6 pink 7 grey 8 lightGrey 9 cyan a purple b blue
                c brown d green e red f black
]]

return {
  {
    id = "files", title = "Files", module = "apps/files", w = 40, h = 14,
    icon = { "111    ", "1111111", "1111111" },
  },
  {
    id = "browser", title = "Furnace", module = "apps/browser", w = 46, h = 16,
    icon = { " eeeee ", "e11111e", " e444e " },
  },
  {
    id = "terminal", title = "Terminal", module = "apps/terminal", w = 42, h = 14,
    icon = { "fffffff", "f5fffff", "fffffff" },
  },
  {
    id = "editor", title = "Editor", module = "apps/editor", w = 44, h = 15,
    icon = { "0000000", "0888880", "0088800" },
  },
  {
    id = "music", title = "Music", module = "apps/music", w = 44, h = 16,
    single = true,
    icon = { "  eeee ", "  e    ", "ee e   " },
  },
  {
    id = "messenger", title = "Messenger", module = "apps/messenger", w = 42, h = 15,
    single = true,
    icon = { "2222222", "2222222", " 2     " },
  },
  {
    id = "minebit", title = "Minebit", module = "apps/minebit", w = 44, h = 16,
    icon = { "5     5", "5555555", " 5   5 " },
  },
  {
    id = "store", title = "Store", module = "apps/store", w = 44, h = 15,
    single = true,
    icon = { " d   d ", "ddddddd", "ddddddd" },
  },
  {
    id = "tasks", title = "Tasks", module = "apps/tasks", w = 40, h = 14,
    single = true,
    icon = { "7 7    ", "7 7 7 7", "7 7 7 7" },
  },
  {
    id = "updater", title = "Update", module = "apps/updater", w = 40, h = 12,
    single = true,
    icon = { "   9   ", "  999  ", " 99999 " },
  },
  {
    id = "devices", title = "Devices", module = "apps/devices", w = 40, h = 13,
    icon = { "a   a  ", "aaaaaaa", "  aaa  " },
  },
  {
    id = "freeram", title = "FreeRAM.exe", module = "apps/freeram", w = 38, h = 12,
    icon = { " 55555 ", "5000005", " 55555 " },
  },
  {
    id = "zare", title = "Zare AV", module = "apps/zare", w = 38, h = 13,
    single = true,
    icon = { " ddddd ", "d00000d", " dd0dd " },
  },
  {
    id = "console", title = "Console", module = "apps/console", w = 44, h = 15,
    single = true, dev = true,
    icon = { "fffffff", "f5 ffff", "fffffff" },
  },
  {
    id = "settings", title = "Settings", module = "apps/settings", w = 36, h = 13,
    icon = { " b b b ", "bbbbbbb", " bbbbb " },
  },
}
