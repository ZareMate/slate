--[[ Cloud apps - app code fetched on demand instead of shipped.

  An install carries the kernel, the system layer and the handful of apps a
  disconnected computer still needs. Everything else is marked `cloud = true`
  in the registry: its icon is on the desktop, but the code only arrives the
  first time you open it, and then it stays cached like any other file.

  Why that is worth doing on a Minecraft computer: a computer's disk is small
  and shared with whatever else you keep on it, and most people use four apps
  out of fifteen. Paying for the other eleven in disk and in update time makes
  no sense.

  What it costs, stated plainly: an app you have never opened will not open
  without a working HTTP connection to the update source. That is why Files,
  Terminal, Editor, Settings, Store, Tasks, Updater and Messenger are NOT
  cloud apps - a computer with no network is still a usable computer.
]]

local use = ...
local update = use("system/update")

local cloud = {}

-- Modules already pulled down this session, so a relaunch does not re-check
-- the disk for something we know is there.
local present = {}

function cloud.available()
  return http ~= nil and update.url() ~= nil
end

function cloud.isCached(module, root)
  if present[module] then return true end
  local there = fs.exists(fs.combine(root, module .. ".lua"))
  if there then present[module] = true end
  return there
end

-- Downloads <base>/<module>.lua into the install. Returns true, or nil and a
-- reason. The whole file is read before anything is written, so a dropped
-- connection leaves no half-file that would then fail to parse.
function cloud.fetch(module, root)
  if not http then return nil, "HTTP is disabled" end
  local base = update.url()
  if not base then return nil, "No source configured" end

  local response, err = http.get(base .. "/" .. module .. ".lua")
  if not response then return nil, tostring(err) end
  local body = response.readAll()
  response.close()
  if not body or body == "" then return nil, "Empty response" end

  local path = fs.combine(root, module .. ".lua")
  local folder = fs.getDir(path)
  if folder ~= "" and not fs.exists(folder) then
    local made = pcall(fs.makeDir, folder)
    if not made then return nil, "Could not create " .. folder end
  end

  local handle, openErr = fs.open(path, "w")
  if not handle then return nil, tostring(openErr) end
  handle.write(body)
  handle.close()
  present[module] = true
  return true
end

-- Makes sure a module is on disk, fetching it if it is not.
function cloud.ensure(module, root)
  if cloud.isCached(module, root) then return true end
  return cloud.fetch(module, root)
end

-- Deletes cached cloud modules to reclaim space. Never touches anything the
-- registry did not mark as a cloud app.
function cloud.evict(modules, root)
  local freed = 0
  for _, module in ipairs(modules) do
    local path = fs.combine(root, module .. ".lua")
    if fs.exists(path) then
      local sized, size = pcall(fs.getSize, path)
      if pcall(fs.delete, path) then
        freed = freed + ((sized and size) or 0)
        present[module] = nil
      end
    end
  end
  return freed
end

return cloud
