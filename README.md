# Slate

A windowed OS for ComputerCraft that runs on the computer's own terminal.
No monitor, no modem, nothing attached. (Music is the one app that wants
hardware - a speaker - and it says so politely instead of failing.)

```
slate/startup.lua
```

Copy the `slate` folder onto a computer and run that. Put it at the root as
`/startup.lua` if you want it to boot with the world.

## What you get

Overlapping, draggable windows on a 51x19 screen, fullscreen, a taskbar, a
start menu, and seven apps:

| App | What it is |
|---|---|
| **Files** | Browse, open, create, delete. Opens files in the editor. |
| **Terminal** | A real CraftOS shell in a window. Anything you can run on a computer runs here. |
| **Editor** | CraftOS's `edit`, in a window. |
| **Music** | YouTube audio through a speaker. Search, queue, loop, volume. |
| **Messenger** | Message other computers over rednet. Peers find each other automatically. |
| **Devices** | Attached peripherals, their types, and calling their methods with arguments. |
| **Settings** | Accent and wallpaper, rename, boot-with-world, mirror to monitors, power, system facts. |

Settings changes apply immediately, and the appearance choices are saved
through CC's own `settings` API so they survive a reboot. **Start with world**
writes a `/startup.lua` that launches Slate — and refuses to clobber a startup
script somebody else wrote, reporting it as "Other script" instead.

Messenger needs a modem — wireless to reach anything in range, wired to reach
whatever shares the cable network. Peers announce themselves on the `slate.msg`
protocol so the list fills in by itself; there is also an **Everyone** entry for
broadcasts. Unread counts show in the window title, so you can see them from the
taskbar with the window minimised. rednet is unauthenticated: anything in range
can send you a message, read a broadcast, and claim any name it likes.

Music needs a speaker attached and HTTP enabled. It streams through
`ipod-2to6magyna-uc.a.run.app` (Xella's ipod API, which is what resolves and
transcodes the audio), so search terms and video ids go to that third-party
service.

## Controls

| | |
|---|---|
| Click a desktop icon | Open that app |
| Drag a title bar | Move the window |
| `_` `^` `X` on the title bar | Minimise / fullscreen / close |
| `Ctrl` + `F` | Fullscreen the focused window |
| Click a taskbar button | Focus it, or minimise if already focused |
| `Ctrl` + `Tab` | Next window |
| `Ctrl` + `W` | Close the focused window |
| `Ctrl` + `E` | Start menu |
| `Ctrl` + `T` | Stop what's in the focused window |
| Arrow keys + `Enter` | Move around the icon grid when no window is focused |

Every action has a key as well as a click, because a **basic** computer has no
mouse at all. Slate runs there too — it just renders in greyscale, which is why
nothing in the UI uses colour alone to tell two things apart.

## How it works

The interesting part is the compositor, in `system/kernel.lua`.

CC's window API draws straight through to its parent, so if you make several
windows visible they paint over each other in whatever order they happen to
write — there is no z-order. Slate gets around that by giving every process two
windows:

```
frame    window.create(native, 1, 1, w, h, false)   <- INVISIBLE, holds the title bar
  content  window.create(frame, 1, 2, w, h-1, true) <- visible *relative to frame*
```

An app's writes land in `content`, which writes through into `frame`'s buffer,
which — being invisible — never reaches the real terminal on its own. Each
frame the kernel walks the process list back to front, reads each frame's
buffer with `window.getLine()`, splices the slices into one string per screen
row, and issues a single `blit` per row. Nineteen blits a frame, correct
z-order, no flicker and no tearing.

Apps are ordinary CC programs. The kernel redirects `term` to a process's
content window before resuming its coroutine and restores it after, so an app
just calls `os.pullEvent` and `term.write` like any other program — which is
exactly why the Terminal app can be four lines that run `/rom/programs/shell.lua`.

Windows are clamped fully on screen, which is what lets the splice be a plain
substring replacement instead of a clipping routine.

Windows open centred, with a small stagger so a second window of the same size
is not hidden exactly behind the first. Fullscreen genuinely resizes the frame
and content windows and then hands the app a `term_resize` event, so an app
relayouts for real rather than being drawn bigger.

Because unrouted events are broadcast to every process, a background window
keeps running - Music keeps playing while you browse files.

**Screens.** The kernel composes one frame into an offscreen buffer, then
*presents* it: always to `term.native()`, and additionally to any monitor turned
on in Settings. Monitors are mirrors, never required, and `monitor_touch` comes
back as a click (never a drag - a touch has no matching mouse_up, which would
stick a window to the cursor).

## Layout

```
startup.lua        entry point and the module loader
system/
  kernel.lua       processes, windows, compositing, event routing
  screens.lua      optional monitor mirroring + touch (the only monitor code)
  peripherals.lua  CC:Tweaked type rules in one place
  desktop.lua      wallpaper, icons, taskbar, start menu
  ui.lua           drawing helpers, all taking an explicit target
  theme.lua        semantic colours + the advanced-computer palette
  apps.lua         the app registry
apps/
  files.lua  terminal.lua  editor.lua  music.lua
  messenger.lua  devices.lua  settings.lua
```

Modules are loaded with `loadfile()` against the entry program's environment
rather than `require()`. That means Slate does not depend on whatever
`package.path` happens to be, and modules can still see `shell` — which the
Terminal and Editor need, and which is *not* a true global.

## Adding an app

1. Write `apps/yours.lua` returning a table with `run(ctx, ...)`.
2. Add a row to `system/apps.lua`.

Nothing else changes. `ctx` gives you `close()`, `setTitle(text)`,
`launch(id, args)`, `size()` and `redraw()`. Inside `run`, `term` is already
pointed at your window, so write normal CC code.

`ctx.onClose(fn)` registers cleanup that runs when the window closes; anything
holding hardware needs it, which is how Music stops its speakers. Mark an app
`single = true` in the registry and Slate raises its existing window instead of
opening a second one.

```lua
local app = {}
function app.run(ctx)
  term.setBackgroundColour(colours.white)
  term.clear()
  term.setCursorPos(1, 1)
  term.setTextColour(colours.black)
  print("hello")
  os.pullEvent("key")   -- returning closes the window
end
return app
```

## What has been checked

Run from `cc-scripts/`:

```bash
node tools/wiring-check.js
```

Verifies the modules actually fit together: every `use()` target resolves,
every `desktop.*` the kernel calls exists, every `ui.*` and `theme.colour.*`
is defined, every registered app has a file that exports `run`, apps only use
context fields the kernel provides, nothing anywhere asks for a monitor, the
system layer touches no peripherals at all, any app that grabs hardware
registers `ctx.onClose`, every registered app still fits the icon grid, and
single-instance apps are actually tagged so the check that enforces them can
match. The monitor and peripheral rules are the
"no screen required" brief, enforced rather than trusted.

Also passing: `lua-language-server --check` over the whole folder with CC's
globals declared in `.luarc.json` (no undefined globals, no nil-safety gaps),
and a Lua parse of all thirteen files. The wiring check is itself
mutation-tested — breaking a rule it guards has to make it fail. That caught a
real dead rule: the hardware-cleanup check was written as `rednet.open(`, which
never matched because Messenger passes the function to `pcall` as a value, so
the rule silently applied to nothing.

**Not checked:** Slate has never run inside ComputerCraft. The compositor is
built on documented CC:Tweaked behaviour — an invisible parent window still
buffers a visible child's writes, and `window.getLine()` returns that buffer —
but that is reasoning, not a run. The kernel checks for `getLine` at boot and
refuses with a clear message rather than drawing garbage if it is absent.
