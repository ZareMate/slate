--[[ Slate drawing helpers.

  Everything here takes an explicit target terminal (a window, or the native
  term) rather than drawing to whatever happens to be redirected. The kernel
  composites windows by hand, so "where am I drawing" must never be implicit.
]]

local ui = {}

-- blit wants one colour character per cell, so cache the repeats we use most.
local function blitRun(colour, width)
  return colours.toBlit(colour):rep(width)
end

function ui.fill(target, x, y, w, h, bg)
  if w < 1 or h < 1 then return end
  local blank = (" "):rep(w)
  local run = blitRun(bg, w)
  for row = y, y + h - 1 do
    target.setCursorPos(x, row)
    target.blit(blank, run, run)
  end
end

function ui.text(target, x, y, text, fg, bg)
  target.setCursorPos(x, y)
  if bg then target.setBackgroundColour(bg) end
  if fg then target.setTextColour(fg) end
  target.write(text)
end

-- Pad or truncate to exactly `width`, so a row never leaves stale characters.
function ui.pad(text, width)
  text = tostring(text)
  if #text > width then return ui.clip(text, width) end
  return text .. (" "):rep(width - #text)
end

function ui.clip(text, width)
  text = tostring(text)
  if width <= 0 then return "" end
  if #text <= width then return text end
  if width <= 2 then return text:sub(1, width) end
  return text:sub(1, width - 2) .. ".."
end

function ui.row(target, x, y, w, text, fg, bg)
  ui.text(target, x, y, ui.pad(text, w), fg, bg)
end

function ui.centre(target, y, text, fg, bg, x, w)
  text = ui.clip(text, w)
  ui.text(target, x + math.floor((w - #text) / 2), y, text, fg, bg)
end

function ui.hit(mx, my, x, y, w, h)
  return mx >= x and mx <= x + w - 1 and my >= y and my <= y + h - 1
end

-- A one-column scrollbar. Drawn only when there is something to scroll, so a
-- short list does not grow a decorative stripe.
function ui.scrollbar(target, x, y, h, total, offset, track, thumb)
  if total <= h then return end
  ui.fill(target, x, y, 1, h, track)
  local size = math.max(1, math.floor(h * h / total))
  local span = h - size
  local maxOffset = total - h
  local pos = maxOffset > 0 and math.floor(span * offset / maxOffset + 0.5) or 0
  ui.fill(target, x, y + pos, 1, size, thumb)
end

-- CC has exactly one font at one weight: there is no bold, and no `&l`. What
-- reads as bold on a terminal is inverse video, so that is what "strong" means
-- here. Everything below is a way of getting emphasis without a second font.

-- Inverse-video run. The nearest thing to bold CC can actually draw.
function ui.strong(target, x, y, text, fg, bg)
  ui.text(target, x, y, " " .. text .. " ", bg, fg)
end

-- Letter-spaced heading: "S L A T E". Wide text reads as heavier without
-- needing a heavier face.
function ui.spaced(text)
  return (tostring(text):upper():gsub("(.)", "%1 "):gsub(" $", ""))
end

-- A title row with an accent underline - the blockiness goes away when a
-- heading is a line of colour rather than a filled bar of it.
function ui.heading(target, x, y, w, text, fg, bg, accent)
  ui.row(target, x, y, w, " " .. text, fg, bg)
  ui.fill(target, x + 1, y + 1, math.min(w - 2, #text + 1), 1, accent)
end

-- A real button: padded label, its own colours, and it hands back the rect so
-- the caller hit-tests the same geometry it drew instead of guessing.
-- opts = { fg, bg, disabled, active, key }
function ui.button(target, x, y, label, opts)
  opts = opts or {}
  local text = " " .. label .. " "
  local bg = opts.bg or colours.lightGrey
  local fg = opts.fg or colours.black
  if opts.disabled then bg, fg = colours.grey, colours.lightGrey end
  if opts.active then bg, fg = opts.activeBg or colours.white, colours.black end

  ui.text(target, x, y, text, fg, bg)
  return { x = x, y = y, w = #text, h = 1, disabled = opts.disabled }
end

-- Lays out buttons left to right from x, returning their rects by name.
function ui.buttonRow(target, x, y, list)
  local rects = {}
  local at = x
  for _, entry in ipairs(list) do
    rects[entry.name] = ui.button(target, at, y, entry.label, entry)
    at = at + #entry.label + 3
  end
  return rects
end

function ui.inButton(rect, mx, my)
  return rect and not rect.disabled and ui.hit(mx, my, rect.x, rect.y, rect.w, rect.h)
end

-- Clamps a scroll offset so a list can never show past its own end. Returns
-- the corrected offset; every scrolling view in Slate goes through this.
function ui.clampScroll(offset, total, visible)
  local maxOffset = math.max(0, total - visible)
  return math.max(0, math.min(maxOffset, offset)), maxOffset
end

-- A thin rule instead of a solid divider.
function ui.rule(target, x, y, w, colour, bg)
  ui.text(target, x, y, ("-"):rep(w), colour, bg)
end

-- Arrow glyphs that CC's font genuinely has (CP437 range), used widely by
-- CraftOS programs. Safer than guessing at box-drawing characters.
ui.glyph = {
  up = "\30", down = "\31", right = "\16", left = "\17",
  bullet = "\7", dot = "\7",
}

-- Word-wrap to a column width, keeping existing line breaks. Used by the crash
-- screen and by Messenger, so it lives here rather than in both.
function ui.wrap(text, width)
  local out = {}
  if width < 1 then return out end
  for line in (tostring(text) .. "\n"):gmatch("([^\n]*)\n") do
    if line == "" then
      out[#out + 1] = ""
    end
    while #line > width do
      -- Break on the last space that fits; fall back to a hard cut for a word
      -- longer than the whole column.
      local cut = line:sub(1, width + 1):match(".*%s()")
      if not cut or cut < 2 then cut = width + 1 end
      local piece = line:sub(1, cut - 1):gsub("%s+$", "")
      out[#out + 1] = piece
      line = line:sub(cut):gsub("^%s+", "")
    end
    if #line > 0 then out[#out + 1] = line end
  end
  return out
end

-- Draws a label with a bracketed hotkey, e.g. "[D]elete". Basic computers have
-- no mouse, so every action needs a visible key.
function ui.key(target, x, y, key, label, fg, bg, keyFg)
  ui.text(target, x, y, "[", fg, bg)
  target.setTextColour(keyFg or fg)
  target.write(key)
  target.setTextColour(fg)
  target.write("]" .. label)
  return x + 3 + #label
end

return ui
