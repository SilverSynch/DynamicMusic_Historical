local world = require('openmw.world')
local types = require('openmw.types')

local initialized = false

local function globalDataCollected(data)
  for _,player in ipairs(world.players) do
    player:sendEvent("globalDataCollected", { data = data });
  end
end

local function tilesetDataCollected(data)
  for _,player in ipairs(world.players) do
    player:sendEvent("tilesetDataCollected", { data = data });
  end
end

local function initialize()
  if initialized then
    return
  end

  print("initializing global script")
  local cellNames = {}
  local regionNames = {}
  local regionNamesSet = {}


  for _,cell in ipairs(world.cells) do
    if cell.name ~= '' then
      --   print("addingCell: " ..cell.name)
      table.insert(cellNames,cell.name)
      regionNamesSet[cell.region] = true

    end

  end

  for regionName,_ in pairs(regionNamesSet) do
    table.insert(regionNames, regionName)
  end


  globalDataCollected({
    cellNames = cellNames,
    regionNames = regionNames,
  })
  initialized = true
end

local function onLoad()
  initialize()
end

local function onInit()
  initialize()
end

local function getNearbyStatics(cellName)
  local tilesetNames = {}
  local tilesetNamesSet = {}
  local cell = world.getCellByName(cellName)
  if not cell.isExterior then
    for _,static in ipairs(cell:getAll(types.Static)) do
      if static:isValid() and static.enabled then
        tilesetNamesSet[static.recordId] = true
      end
    end
    for static,_ in pairs(tilesetNamesSet) do
      table.insert(tilesetNames, static)
    end
  end
  tilesetDataCollected({tilesetNames = tilesetNames})
end

return {
  engineHandlers = {
    onInit = onInit,
    onLoad = onLoad
  },
  eventHandlers = {
    getNearbyStatics = getNearbyStatics
  }
}
