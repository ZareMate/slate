--[[ Music - YouTube audio through a speaker.

  Ported from Xella's "ipod" player (the ipod-2to6magyna-uc.a.run.app API and
  its DFPWM streaming are theirs). The playback path is kept faithful; what
  changed is everything that assumed it owned the computer:

    * all state is local to run(), so the app has no module-level globals to
      share with a second window or leak into other Slate modules
    * a missing speaker draws a panel instead of error()ing the process
    * the layout reads term.getSize() per run and clips to the window
    * closing the window stops the speakers, via ctx.onClose

  Needs a speaker attached and HTTP enabled. Search terms and video ids are
  sent to that third-party API - it is what resolves and transcodes the audio.
]]

local use = ...
local ui = use("system/ui")
local theme = use("system/theme")

local app = {}

local API_BASE = "https://ipod-2to6magyna-uc.a.run.app/"
local API_VERSION = "2.1"

-- A full-window message, for the cases where the app cannot start at all.
local function panel(title, lines)
  local width, height = term.getSize()
  term.setBackgroundColour(theme.colour.window)
  term.clear()
  ui.row(term, 1, 1, width, " " .. title, colours.white, theme.colour.danger)
  for index, line in ipairs(lines) do
    ui.text(term, 2, index + 2, ui.clip(line, width - 2),
      theme.colour.windowText, theme.colour.window)
  end
  ui.row(term, 1, height, width, " Any key to close",
    theme.colour.mutedText, theme.colour.muted)
  os.pullEvent("key")
end

function app.run(ctx)
  local width, height = term.getSize()

  local speakers = { peripheral.find("speaker") }
  if #speakers == 0 then
    return panel("No speaker", {
      "Music needs a speaker attached to",
      "this computer.",
      "",
      "Place one against the computer, or",
      "connect it with a wired modem, then",
      "open Music again.",
    })
  end

  if not http then
    return panel("HTTP disabled", {
      "Music streams audio over HTTP.",
      "",
      "Set enabled = true under [http] in",
      "computercraft-server.toml.",
    })
  end

  local hasDecoder, dfpwm = pcall(require, "cc.audio.dfpwm")
  if not hasDecoder or type(dfpwm) ~= "table" then
    return panel("Missing audio library", {
      "cc.audio.dfpwm is not available.",
      "Music needs CC:Tweaked 1.100 or newer.",
    })
  end

  ------------------------------------------------------------------
  -- state (per window, never module level)
  ------------------------------------------------------------------

  local tab = 1
  local waiting_for_input = false
  local last_search, last_search_url, search_results = nil, nil, nil
  local search_error = false
  local in_search_result = false
  local clicked_result = nil

  local playing = false
  local queue = {}
  local now_playing = nil
  local looping = 0
  local volume = 1.5

  local playing_id = nil
  local last_download_url = nil
  local playing_status = 0
  local is_loading = false
  local is_error = false

  local player_handle, start, size, buffer = nil, nil, nil, nil
  local decoder = dfpwm.make_decoder()
  local needs_next_chunk = 0

  -- The volume bar is 24 wide on a full screen but must fit the window.
  local sliderW = math.max(8, math.min(24, width - 4))

  -- Abandoning the coroutine would leave whatever is already queued playing.
  ctx.onClose(function()
    for _, speaker in ipairs(speakers) do pcall(speaker.stop) end
  end)

  local redrawScreen, drawNowPlaying, drawSearch

  ------------------------------------------------------------------
  -- drawing
  ------------------------------------------------------------------

  function drawNowPlaying()
    term.setBackgroundColour(colours.black)
    if now_playing ~= nil then
      term.setTextColour(colours.white)
      term.setCursorPos(2, 3)
      term.write(ui.clip(now_playing.name, width - 2))
      term.setTextColour(colours.lightGrey)
      term.setCursorPos(2, 4)
      term.write(ui.clip(now_playing.artist, width - 2))
    else
      term.setTextColour(colours.lightGrey)
      term.setCursorPos(2, 3)
      term.write("Not playing")
    end

    if is_loading then
      term.setTextColour(colours.grey)
      term.setCursorPos(2, 5)
      term.write("Loading...")
    elseif is_error then
      term.setTextColour(colours.red)
      term.setCursorPos(2, 5)
      term.write("Network error")
    end

    local live = (now_playing ~= nil or #queue > 0)

    term.setBackgroundColour(colours.grey)
    term.setTextColour(playing and colours.white or (live and colours.white or colours.lightGrey))
    term.setCursorPos(2, 6)
    term.write(playing and " Stop " or " Play ")

    term.setTextColour(live and colours.white or colours.lightGrey)
    term.setCursorPos(9, 6)
    term.write(" Skip ")

    if looping ~= 0 then
      term.setTextColour(colours.black)
      term.setBackgroundColour(colours.white)
    else
      term.setTextColour(colours.white)
      term.setBackgroundColour(colours.grey)
    end
    term.setCursorPos(16, 6)
    if looping == 0 then term.write(" Loop Off ")
    elseif looping == 1 then term.write(" Loop Queue ")
    else term.write(" Loop Song ") end

    paintutils.drawBox(2, 8, 1 + sliderW, 8, colours.grey)
    local filled = math.floor(sliderW * (volume / 3) + 0.5) - 1
    if filled >= 0 then
      paintutils.drawBox(2, 8, 2 + filled, 8, colours.white)
    end
    local label = math.floor(100 * (volume / 3) + 0.5) .. "%"
    if volume < 0.6 then
      term.setCursorPos(2 + filled + 2, 8)
      term.setBackgroundColour(colours.grey)
      term.setTextColour(colours.white)
    else
      term.setCursorPos(2 + filled - #label, 8)
      term.setBackgroundColour(colours.white)
      term.setTextColour(colours.black)
    end
    term.write(label)

    -- The queue is clipped to the window rather than running off the bottom.
    term.setBackgroundColour(colours.black)
    local slots = math.floor((height - 9) / 2)
    for i = 1, math.min(#queue, slots) do
      term.setTextColour(colours.white)
      term.setCursorPos(2, 10 + (i - 1) * 2)
      term.write(ui.clip(queue[i].name, width - 2))
      term.setTextColour(colours.lightGrey)
      term.setCursorPos(2, 11 + (i - 1) * 2)
      term.write(ui.clip(queue[i].artist, width - 2))
    end
    if #queue > slots and slots > 0 then
      term.setTextColour(colours.grey)
      term.setCursorPos(2, height)
      term.write("+" .. (#queue - slots) .. " more")
    end
  end

  function drawSearch()
    paintutils.drawFilledBox(2, 3, width - 1, 5, colours.lightGrey)
    term.setBackgroundColour(colours.lightGrey)
    term.setCursorPos(3, 4)
    term.setTextColour(colours.black)
    term.write(ui.clip(last_search or "Search...", width - 4))

    if search_results ~= nil then
      term.setBackgroundColour(colours.black)
      local slots = math.floor((height - 6) / 2)
      for i = 1, math.min(#search_results, slots) do
        term.setTextColour(colours.white)
        term.setCursorPos(2, 7 + (i - 1) * 2)
        term.write(ui.clip(search_results[i].name, width - 2))
        term.setTextColour(colours.lightGrey)
        term.setCursorPos(2, 8 + (i - 1) * 2)
        term.write(ui.clip(search_results[i].artist, width - 2))
      end
    else
      term.setCursorPos(2, 7)
      term.setBackgroundColour(colours.black)
      if search_error then
        term.setTextColour(colours.red)
        term.write("Network error")
      elseif last_search_url ~= nil then
        term.setTextColour(colours.lightGrey)
        term.write("Searching...")
      else
        term.setTextColour(colours.lightGrey)
        term.setCursorPos(2, 7)
        term.write("Tip: paste a YouTube video")
        term.setCursorPos(2, 8)
        term.write("or playlist link.")
      end
    end

    if in_search_result then
      -- The results can be replaced underneath the menu by a late http reply,
      -- so the chosen row is re-checked rather than assumed to still be there.
      local chosen = search_results and clicked_result and search_results[clicked_result]
      if not chosen then
        in_search_result = false
      else
        term.setBackgroundColour(colours.black)
        term.clear()
        term.setCursorPos(2, 2)
        term.setTextColour(colours.white)
        term.write(ui.clip(chosen.name, width - 2))
        term.setCursorPos(2, 3)
        term.setTextColour(colours.lightGrey)
        term.write(ui.clip(chosen.artist, width - 2))

        term.setBackgroundColour(colours.grey)
        term.setTextColour(colours.white)
        for _, item in ipairs({ { 6, "Play now" }, { 8, "Play next" },
                                { 10, "Add to queue" }, { 13, "Cancel" } }) do
          term.setCursorPos(2, item[1])
          term.clearLine()
          term.write(item[2])
        end
      end
    end
  end

  function redrawScreen()
    if waiting_for_input then return end

    term.setCursorBlink(false)
    term.setBackgroundColour(colours.black)
    term.clear()

    term.setCursorPos(1, 1)
    term.setBackgroundColour(colours.grey)
    term.clearLine()

    local tabs = { " Now Playing ", " Search " }
    for i = 1, #tabs do
      if tab == i then
        term.setTextColour(colours.black)
        term.setBackgroundColour(colours.white)
      else
        term.setTextColour(colours.white)
        term.setBackgroundColour(colours.grey)
      end
      term.setCursorPos(math.floor((width / #tabs) * (i - 0.5)) - math.ceil(#tabs[i] / 2) + 1, 1)
      term.write(tabs[i])
    end

    if tab == 1 then drawNowPlaying() else drawSearch() end
  end

  ------------------------------------------------------------------
  -- loops
  ------------------------------------------------------------------

  local function setVolumeFrom(x)
    volume = math.max(0, math.min(3, (x - 1) / sliderW * 3))
  end

  local function startSearch(input)
    if #input > 0 then
      last_search = input
      last_search_url = API_BASE .. "?v=" .. API_VERSION .. "&search=" .. textutils.urlEncode(input)
      http.request(last_search_url)
    else
      last_search, last_search_url = nil, nil
    end
    search_results = nil
    search_error = false
  end

  local function stopSpeakers()
    for _, speaker in ipairs(speakers) do
      speaker.stop()
      os.queueEvent("playback_stopped")
    end
  end

  local function uiLoop()
    redrawScreen()

    while true do
      if waiting_for_input then
        parallel.waitForAny(
          function()
            term.setCursorPos(3, 4)
            term.setBackgroundColour(colours.white)
            term.setTextColour(colours.black)
            startSearch(read())
            waiting_for_input = false
            os.queueEvent("redraw_screen")
          end,
          function()
            while waiting_for_input do
              local _, _, x, y = os.pullEvent("mouse_click")
              if y < 3 or y > 5 or x < 2 or x > width - 1 then
                waiting_for_input = false
                os.queueEvent("redraw_screen")
                break
              end
            end
          end
        )
      else
        parallel.waitForAny(
          function()
            local _, button, x, y = os.pullEvent("mouse_click")
            if button ~= 1 then return end

            if not in_search_result and y == 1 then
              tab = (x < width / 2) and 1 or 2
              redrawScreen()
            end

            if tab == 2 and not in_search_result then
              if y >= 3 and y <= 5 and x >= 1 and x <= width - 1 then
                paintutils.drawFilledBox(2, 3, width - 1, 5, colours.white)
                term.setBackgroundColour(colours.white)
                waiting_for_input = true
              end

              if search_results then
                for i = 1, #search_results do
                  if y == 7 + (i - 1) * 2 or y == 8 + (i - 1) * 2 then
                    in_search_result = true
                    clicked_result = i
                    redrawScreen()
                  end
                end
              end

            elseif tab == 2 and in_search_result then
              local choice = search_results and clicked_result
                and search_results[clicked_result]
              if not choice then
                in_search_result = false
                redrawScreen()
                return
              end

              if y == 6 then
                in_search_result = false
                stopSpeakers()
                playing = true
                is_error = false
                playing_id = nil
                if choice.type == "playlist" then
                  now_playing = choice.playlist_items[1]
                  queue = {}
                  for i = 2, #choice.playlist_items do
                    table.insert(queue, choice.playlist_items[i])
                  end
                else
                  now_playing = choice
                end
                os.queueEvent("audio_update")

              elseif y == 8 then
                in_search_result = false
                if choice.type == "playlist" then
                  for i = #choice.playlist_items, 1, -1 do
                    table.insert(queue, 1, choice.playlist_items[i])
                  end
                else
                  table.insert(queue, 1, choice)
                end
                os.queueEvent("audio_update")

              elseif y == 10 then
                in_search_result = false
                if choice.type == "playlist" then
                  for i = 1, #choice.playlist_items do
                    table.insert(queue, choice.playlist_items[i])
                  end
                else
                  table.insert(queue, choice)
                end
                os.queueEvent("audio_update")

              elseif y == 13 then
                in_search_result = false
              end

              redrawScreen()

            elseif tab == 1 and not in_search_result then
              if y == 6 then
                if x >= 2 and x < 8 then
                  if playing then
                    playing = false
                    stopSpeakers()
                    playing_id = nil
                    is_loading = false
                    is_error = false
                    os.queueEvent("audio_update")
                  elseif now_playing ~= nil then
                    playing_id = nil
                    playing = true
                    is_error = false
                    os.queueEvent("audio_update")
                  elseif #queue > 0 then
                    now_playing = table.remove(queue, 1)
                    playing_id = nil
                    playing = true
                    is_error = false
                    os.queueEvent("audio_update")
                  end
                end

                if x >= 9 and x < 15 then
                  if now_playing ~= nil or #queue > 0 then
                    is_error = false
                    if playing then stopSpeakers() end
                    if #queue > 0 then
                      if looping == 1 then table.insert(queue, now_playing) end
                      now_playing = table.remove(queue, 1)
                      playing_id = nil
                    else
                      now_playing = nil
                      playing = false
                      is_loading = false
                      playing_id = nil
                    end
                    os.queueEvent("audio_update")
                  end
                end

                if x >= 16 and x < 28 then
                  looping = (looping + 1) % 3
                end
              end

              if y == 8 and x >= 1 and x < 2 + sliderW then
                setVolumeFrom(x)
              end

              redrawScreen()
            end
          end,
          function()
            local _, button, x, y = os.pullEvent("mouse_drag")
            if button == 1 and tab == 1 and not in_search_result then
              if y >= 7 and y <= 9 and x >= 1 and x < 2 + sliderW then
                setVolumeFrom(x)
                redrawScreen()
              end
            end
          end,
          function()
            os.pullEvent("redraw_screen")
            redrawScreen()
          end,
          function()
            -- Fullscreen really resizes the window, so the layout has to be
            -- recomputed rather than keeping the size it opened at.
            os.pullEvent("term_resize")
            width, height = term.getSize()
            sliderW = math.max(8, math.min(24, width - 4))
            redrawScreen()
          end
        )
      end
    end
  end

  local function audioLoop()
    while true do
      if playing and now_playing then
        local thisnowplayingid = now_playing.id

        if playing_id ~= thisnowplayingid then
          playing_id = thisnowplayingid
          last_download_url = API_BASE .. "?v=" .. API_VERSION
            .. "&id=" .. textutils.urlEncode(playing_id)
          playing_status = 0
          needs_next_chunk = 1
          http.request({ url = last_download_url, binary = true })
          is_loading = true
          os.queueEvent("redraw_screen")
          os.queueEvent("audio_update")

        elseif playing_status == 1 and needs_next_chunk == 1 then
          while true do
            -- Losing the handle mid-track should drop back to idle, not take
            -- the whole app down with a nil index.
            if not player_handle then
              playing_status = 0
              needs_next_chunk = 0
              is_error = true
              os.queueEvent("redraw_screen")
              break
            end
            local chunk = player_handle.read(size)
            if not chunk then
              if looping == 2 or (looping == 1 and #queue == 0) then
                playing_id = nil
              elseif looping == 1 and #queue > 0 then
                table.insert(queue, now_playing)
                now_playing = table.remove(queue, 1)
                playing_id = nil
              elseif #queue > 0 then
                now_playing = table.remove(queue, 1)
                playing_id = nil
              else
                now_playing = nil
                playing = false
                playing_id = nil
                is_loading = false
                is_error = false
              end

              os.queueEvent("redraw_screen")
              player_handle.close()
              needs_next_chunk = 0
              break
            else
              if start then
                chunk, start = start .. chunk, nil
                size = size + 4
              end

              buffer = decoder(chunk)

              local fn = {}
              for i, speaker in ipairs(speakers) do
                fn[i] = function()
                  local name = peripheral.getName(speaker)
                  if #speakers > 1 then
                    if speaker.playAudio(buffer, volume) then
                      parallel.waitForAny(
                        function()
                          repeat until select(2, os.pullEvent("speaker_audio_empty")) == name
                        end,
                        function() os.pullEvent("playback_stopped") end
                      )
                      if not playing or playing_id ~= thisnowplayingid then return end
                    end
                  else
                    while not speaker.playAudio(buffer, volume) do
                      parallel.waitForAny(
                        function()
                          repeat until select(2, os.pullEvent("speaker_audio_empty")) == name
                        end,
                        function() os.pullEvent("playback_stopped") end
                      )
                      if not playing or playing_id ~= thisnowplayingid then return end
                    end
                  end
                  if not playing or playing_id ~= thisnowplayingid then return end
                end
              end

              local ok = pcall(parallel.waitForAll, table.unpack(fn))
              if not ok then
                needs_next_chunk = 2
                is_error = true
                break
              end

              if not playing or playing_id ~= thisnowplayingid then break end
            end
          end
          os.queueEvent("audio_update")
        end
      end

      os.pullEvent("audio_update")
    end
  end

  local function httpLoop()
    while true do
      parallel.waitForAny(
        function()
          local _, url, handle = os.pullEvent("http_success")
          if url == last_search_url then
            search_results = textutils.unserialiseJSON(handle.readAll())
            handle.close()
            os.queueEvent("redraw_screen")
          elseif url == last_download_url then
            is_loading = false
            player_handle = handle
            start = handle.read(4)
            size = 16 * 1024 - 4
            playing_status = 1
            os.queueEvent("redraw_screen")
            os.queueEvent("audio_update")
          end
        end,
        function()
          local _, url = os.pullEvent("http_failure")
          if url == last_search_url then
            search_error = true
            os.queueEvent("redraw_screen")
          elseif url == last_download_url then
            is_loading = false
            is_error = true
            playing = false
            playing_id = nil
            os.queueEvent("redraw_screen")
            os.queueEvent("audio_update")
          end
        end
      )
    end
  end

  parallel.waitForAny(uiLoop, audioLoop, httpLoop)
end

return app
