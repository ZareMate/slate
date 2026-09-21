--[[ Peripheral helpers - one place that knows CC:Tweaked's type rules.

  The rule that matters: peripheral.getType returns MULTIPLE types as of
  CC:Tweaked 1.99, because a peripheral can be several things at once (a wired
  modem is also a peripheral_hub). Writing

      if peripheral.getType(name) == "modem" then

  compares only the first type and silently misses the rest. That was a real
  bug in Messenger, so the correct test lives here and nothing else reimplements
  it.
]]

local peripherals = {}

function peripherals.names()
  local ok, list = pcall(peripheral.getNames)
  if not ok or type(list) ~= "table" then return {} end
  table.sort(list)
  return list
end

-- Every type a peripheral reports, as a list.
function peripherals.typeList(name)
  local ok, first, second, third = pcall(peripheral.getType, name)
  if not ok or not first then return {} end
  local list = { first }
  if second then list[#list + 1] = second end
  if third then list[#list + 1] = third end
  return list
end

function peripherals.typeText(name)
  local list = peripherals.typeList(name)
  if #list == 0 then return "?" end
  return table.concat(list, ",")
end

-- hasType is the right answer on 1.99+; the list walk covers older builds.
function peripherals.isType(name, kind)
  if peripheral.hasType then
    local ok, result = pcall(peripheral.hasType, name, kind)
    if ok then return result == true end
  end
  for _, candidate in ipairs(peripherals.typeList(name)) do
    if candidate == kind then return true end
  end
  return false
end

function peripherals.ofType(kind)
  local found = {}
  for _, name in ipairs(peripherals.names()) do
    if peripherals.isType(name, kind) then found[#found + 1] = name end
  end
  return found
end

return peripherals
