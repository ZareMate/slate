--[[ The app registry.

  One place that knows what Slate can run, what each app is called, and how
  big its window wants to be. Adding an app is adding a row here plus a file
  in apps/ - nothing else in the OS needs to change.
]]

return {
  {
    id = "files", title = "Files", letter = "F", colour = colours.orange,
    module = "apps/files", w = 40, h = 14,
  },
  {
    id = "terminal", title = "Terminal", letter = ">", colour = colours.black,
    module = "apps/terminal", w = 42, h = 14,
  },
  {
    id = "editor", title = "Editor", letter = "E", colour = colours.green,
    module = "apps/editor", w = 44, h = 15,
  },
  {
    -- single: one speaker, one player. A second window would fight the first
    -- over speaker_audio_empty events and play two songs at once.
    id = "music", title = "Music", letter = "M", colour = colours.red,
    module = "apps/music", w = 44, h = 16, single = true,
  },
  {
    -- single: it hosts a name on the rednet protocol, and two windows would
    -- both answer every hello and double up every incoming message.
    id = "messenger", title = "Messenger", letter = "@", colour = colours.magenta,
    module = "apps/messenger", w = 42, h = 15, single = true,
  },
  {
    id = "minebit", title = "Minebit", letter = "#", colour = colours.lime,
    module = "apps/minebit", w = 44, h = 16,
  },
  {
    id = "tasks", title = "Tasks", letter = "%", colour = colours.brown,
    module = "apps/tasks", w = 40, h = 14, single = true,
  },
  {
    id = "updater", title = "Update", letter = "^", colour = colours.cyan,
    module = "apps/updater", w = 40, h = 12, single = true,
  },
  {
    id = "devices", title = "Devices", letter = "D", colour = colours.purple,
    module = "apps/devices", w = 40, h = 13,
  },
  {
    id = "settings", title = "Settings", letter = "S", colour = colours.blue,
    module = "apps/settings", w = 36, h = 13,
  },
}
