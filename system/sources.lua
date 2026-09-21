--[[ App sources - where the Store looks for apps.

  Apps are not shipped with the OS and are not tied to one repository. A
  source is any URL serving an index.json plus the .lua files it names:

      <source>/index.json
        { "apps": [ { "id","title","file","blurb","w","h","icon","api" } ] }
      <source>/<file>

  `file` is a path relative to the source, so apps are served from wherever
  they already live in a repository - there is no separate store folder to
  keep in step, and installing is a download rather than a download and a
  move.

  That is deliberately the least a static host can do - raw GitHub, a pastebin
  mirror, an S3 bucket, a Worker, a folder on your own server. Anyone can
  publish apps without being given access to anybody else's repository, and
  anyone can add a source without asking permission.

  The official source follows whatever the update URL is set to, so pointing
  Slate at your own build points the Store at it too.
]]

local use = ...
local update = use("system/update")

local sources = {}

local KEY = "slate.sources"

local function saved()
  local ok, value = pcall(settings.get, KEY)
  if ok and type(value) == "table" then return value end
  return {}
end

local function persist(list)
  pcall(function()
    settings.set(KEY, list)
    settings.save()
  end)
end

local function tidy(url)
  return (tostring(url):gsub("%s", ""):gsub("/+$", ""))
end

-- The built-in source is derived, never stored: if the update URL changes,
-- the Store follows it rather than pointing at a stale host.
function sources.official()
  local base = update.url()
  if not base then return nil end
  return { name = "Slate", url = base, builtin = true }
end

function sources.list()
  local out = {}
  local first = sources.official()
  if first then out[#out + 1] = first end
  for _, entry in ipairs(saved()) do
    if type(entry) == "table" and type(entry.url) == "string" then
      out[#out + 1] = { name = entry.name or entry.url, url = entry.url, builtin = false }
    end
  end
  return out
end

function sources.add(name, url)
  url = tidy(url)
  if url == "" or not url:match("^https?://") then
    return false, "That is not an http address"
  end
  local official = sources.official()
  if official and tidy(official.url) == url then
    return false, "That is already the built-in source"
  end
  local list = saved()
  for _, entry in ipairs(list) do
    if tidy(entry.url) == url then return false, "Already added" end
  end
  list[#list + 1] = { name = (name ~= "" and name) or url, url = url }
  persist(list)
  return true
end

function sources.remove(url)
  url = tidy(url)
  local list = saved()
  for index, entry in ipairs(list) do
    if tidy(entry.url) == url then
      table.remove(list, index)
      persist(list)
      return true
    end
  end
  return false, "Built-in sources cannot be removed"
end

return sources
