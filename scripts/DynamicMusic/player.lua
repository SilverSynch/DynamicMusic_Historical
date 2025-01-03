local ambient = require('openmw.ambient')
local self = require('openmw.self')
local vfs = require('openmw.vfs')
local types = require('openmw.types')
local core = require('openmw.core')

local playerStates = {
  combat = 'combat',
  explore = 'explore'
}

local gameState = {
  cellName = {
    current = nil,
    previous = nil
  },
  playtime = {
    current = os.time(),
    previous = -1
  },
  playerState = {
    current = nil,
    previous = nil
  },
  regionName = {
    current = nil,
    previous = nil
  },
  soundBank = {
    current = nil,
    previous = nil
  }
}

local soundBanks = {}
local cellNameDictionary = nil
local regionNameDictionary = nil
local tilesetNameDictionary = nil
local nearbyTileset = nil

local hostileActors = {}
local initialized = false

local currentPlaybacktime = -1
local currentTrackPath = nil
local currentTrackLength = -1

local function contains(elements, element)
  if not elements then
    return false
  end

  for _, tableElement in pairs(elements) do
    if tableElement == element then
      return true
    end
  end

  return false
end

local function countAvailableTracks(soundBank)
  if (not soundBank.tracks or #soundBank.tracks == 0) and (not soundBank.combatTracks or #soundBank.combatTracks == 0) then
    return 0
  end

  local availableTracks = 0

  if soundBank.tracks then
    for _, track in ipairs(soundBank.tracks) do
      if type(track) == "table" then
        track = track.path
      end

      if vfs.fileExists(track) then
        availableTracks = availableTracks + 1
      end
    end
  end

  if soundBank.combatTracks then
    for _, track in ipairs(soundBank.combatTracks) do
      if type(track) == "table" then
        track = track.path
      end

      if vfs.fileExists(track) then
        availableTracks = availableTracks + 1
      end
    end
  end

  return availableTracks
end

--- Collect sound banks.
-- Collects the user defined soundbanks that are stored inside the soundBanks folder
local function collectSoundBanks()
  local soundBanksPath = "scripts/DynamicMusic/soundBanks"
  print("collecting soundBanks from: " ..soundBanksPath)

  for file in vfs.pathsWithPrefix(soundBanksPath) do
    file = file.gsub(file, ".lua", "")
    print("requiring soundBank: " ..file)
    local soundBank = require(file)

    if type(soundBank) == 'table' then
      local availableTracks = countAvailableTracks(soundBank)

      if(availableTracks > 0) then
        table.insert(soundBanks,soundBank)
      else
        print('no tracks available: '..file)
      end
    else
      print("not a lua table: " ..file)
    end
  end
end

local function getPlayerState()
  for id, npc in pairs(hostileActors) do
    return playerStates.combat
  end

  return playerStates.explore
end

--- Returns if the given sondBank is allowed for the given cellname
-- Performs raw checks and does not use the dictionary
-- @param soundBank a soundBank
-- @paran cellName a cellName of type string
-- @returns true/false
local function isSoundBankAllowedForCellName(soundBank, cellName, useDictionary)
  if useDictionary and cellNameDictionary then
    return contains(cellNameDictionary[cellName], soundBank)
  end

  if soundBank.cellNamePatternsExclude then
    for  _, cellNameExcludePattern in ipairs(soundBank.cellNamePatternsExclude) do
      if string.find(cellName:lower(), cellNameExcludePattern:lower(), 1, true) then
        return false
      end
    end
  end

  if soundBank.cellNamePatterns then
    for  _, cellNamePattern in ipairs(soundBank.cellNamePatterns) do
      if string.find(cellName:lower(), cellNamePattern:lower(), 1, true) then
        return true
      end
    end
  end

  return false
end

local function isSoundBankAllowedForRegionName(soundBank, regionName, useDictionary)
  if not soundBank.regionNames then
    return false
  end

  if useDictionary and regionNameDictionary then
    return contains(regionNameDictionary[regionName], soundBank)
  end

  for _, allowedRegionName in ipairs(soundBank.regionNames) do
    if regionName:lower() == allowedRegionName:lower() then
      return true
    end
  end

  return false
end

local function isSoundBankAllowedForTilesetName(soundBank, tilesetName, useDictionary)
  if not soundBank.tilesetPatterns then
    return false
  end

  --if useDictionary and tilesetNameDictionary then
  --  return contains(tilesetNameDictionary[cellName], soundBank)
  --end


  for _, allowedTilesetName in ipairs(soundBank.tilesetPatterns) do
    for _,record in ipairs(tilesetName) do
      if string.find(record, allowedTilesetName:lower(), 1, true) then
        return true
      end
    end
  end

  return false
end

-- Creature names have no dictionary because creatures may or may not be staticly placed.
local function isSoundBankAllowedForHostileActors(soundBank, actors)
  if not soundBank.enemyNames then
    return false
  end
  for id, actor in pairs(actors) do
    for _, allowedCreatureName in ipairs(soundBank.enemyNames) do
      if types.Creature.record(actor).name:lower() ==  allowedCreatureName:lower() then
        return true
      end
    end
  end

  return false
end

---Check if sound bank is allowed
-- Returns if the specified soundbank is allowed to play in the current ingame situation.
-- @param soundBank the soundbank that should be checked
-- @return true/false
local function isSoundBankAllowed(soundBank)
  if not soundBank then
    return false
  end

  if gameState.playerState.current == playerStates.explore then
    if not soundBank.tracks or #soundBank.tracks == 0 then
      return false
    end
  end

  if gameState.playerState.current == playerStates.combat then
    if not soundBank.combatTracks or #soundBank.combatTracks == 0 then
      return false
    end
    if soundBank.combatTracks and not isSoundBankAllowedForHostileActors(soundBank, hostileActors) then
     return false
    end
  end

  if (soundBank.cellNames or soundBank.cellNamePatterns) and not isSoundBankAllowedForCellName(soundBank, gameState.cellName.current, true) then
    return false
  end

  if soundBank.regionNames and not isSoundBankAllowedForRegionName(soundBank, gameState.regionName.current,true) then
    return false
  end

  if soundBank.tilesetPatterns and not isSoundBankAllowedForTilesetName(soundBank, nearbyTileset, true) then
    return false
  end

  return true
end

---Fetche appropriate soundbank.
-- Chooses a soundbank that is allowed for the current ingame situation
-- @return a soundbank
local function fetchSoundBank()
  for _, soundBank in ipairs(soundBanks) do
    if isSoundBankAllowed(soundBank) then
      return soundBank
    end
  end

end

---Plays another track from an allowed soundbank
-- Chooses a fitting soundbank and plays a track from it
-- If no soundbank could be found a vanilla track is played
local function newMusic()
  print("newmusic")
  local soundBank = fetchSoundBank()

  -- force new music when strammusic was used in the ingame console
  if not ambient.isMusicPlaying() then
    gameState.soundBank.current = nil
  end

  if gameState.playerState.current == gameState.playerState.previous then
    if gameState.soundBank.current == soundBank and currentPlaybacktime < currentTrackLength then
      return
    end
  end

  if not soundBank then
    print("no matching soundbank found")
    if gameState.soundBank.current then
      ambient.streamMusic('')
    end
    currentTrackPath = nil
    currentPlaybacktime = -1
    gameState.soundBank.current = nil
    return
  end

  gameState.soundBank.current = soundBank
  print("fetch track from: " ..soundBank.id)
  local tracks = soundBank.tracks

  if gameState.playerState.current == playerStates.combat and soundBank.combatTracks then
    tracks = soundBank.combatTracks
  end

  local rnd = math.random(1,#tracks)
  local track = tracks[rnd]
  local trackPath = nil

  if type(track) == 'table' then
    trackPath = track.path
    if track.length then
      currentTrackLength = track.length
    end
  else
    currentTrackLength = -1
    trackPath = track
  end

  currentPlaybacktime = 0
  currentTrackPath = trackPath
  ambient.streamMusic(trackPath)
end

local function hasGameStateChanged()
  if gameState.playerState.previous ~= gameState.playerState.current then
    return true
  end

  if not ambient.isMusicPlaying() then
    return true
  end

  if currentTrackLength and currentPlaybacktime and currentPlaybacktime >= currentTrackLength then
    return true
  end

  if gameState.regionName.current ~= gameState.regionName.previous then
    return true
  end

  if gameState.cellName.current ~= gameState.cellName.previous then
    return true
  end

  return false
end

--- Prefetches dictionary.cells
-- Every sondBank is checked agains each cellName and the dictionary is populated if the soundBank is allowed for that cell
-- @param cellNames all cellNames of the game
local function createCellNameDictionary(cellNames, soundBanks)
  local dictionary = {}

  print("prefetching cells")
  for _, cellName in ipairs(cellNames) do
    for _, soundBank in ipairs(soundBanks) do
      if isSoundBankAllowedForCellName(soundBank, cellName, false) then
        local dict = dictionary[cellName]
        if not dict then
          dict = {}
          dictionary[cellName] = dict
        end
        --       print("adding: " ..tostring(soundBank.id) .." to " ..cellName)
        table.insert(dict, soundBank)
      end
    end
  end

  return dictionary
end

local function createRegionNameDictionary(regionNames, soundBanks)
  local dictionary = {}

  print("prefetching regions")
  for _, regionName in ipairs(regionNames) do
    for _, soundBank in ipairs(soundBanks) do
      if isSoundBankAllowedForRegionName(soundBank, regionName, false) then
        local dict = dictionary[regionName]
        if not dict then
          dict = {}
          dictionary[regionName] = dict
        end
        table.insert(dict, soundBank)
      end
    end
  end

  return dictionary
end

local function createTilesetNameDictionary(tilesetNames, soundBanks)
  local dictionary = {}

  print("prefetching tilesets")
  for cellName, _ in pairs(tilesetNames) do
    for _, soundBank in ipairs(soundBanks) do
      if isSoundBankAllowedForTilesetName(soundBank, cellName, tilesetNames, false) then
        local dict = dictionary[cellName]
        if not dict then
          dict = {}
          dictionary[cellName] = dict
        end
        table.insert(dict, soundBank)
      end
    end
  end

  return dictionary
end

local function onFrame(dt)
  gameState.cellName.current = self.cell and self.cell.name or ""
  gameState.playtime.current = os.time()
  gameState.regionName.current = self.cell and self.cell.region or ""
  gameState.playerState.current = getPlayerState()

  if currentPlaybacktime then
    currentPlaybacktime = currentPlaybacktime + (gameState.playtime.current - gameState.playtime.previous)
  end

  if hasGameStateChanged() then
    core.sendGlobalEvent("getNearbyStatics", gameState.cellName.current)
  end

  gameState.cellName.previous = gameState.cellName.current
  gameState.playtime.previous = gameState.playtime.current
  gameState.playerState.previous = gameState.playerState.current
  gameState.regionName.previous = gameState.regionName.current
  gameState.soundBank.previous = gameState.soundBank.current
end

local function engaging(eventData)
  if (not eventData.actor) then return end;
  hostileActors[eventData.actor.id] = eventData.actor;
end

local function disengaging(eventData)
  if (not eventData.actor) then return end;
  hostileActors[eventData.actor.id] = nil;
end

local function globalDataCollected(eventData)
  print("collecting global data")
  local data = eventData.data

  if data.cellNames then
    cellNameDictionary = createCellNameDictionary(data.cellNames, soundBanks)
  end

  if data.regionNames then
    regionNameDictionary = createRegionNameDictionary(data.regionNames, soundBanks)
  end

  --if data.tilesetNames then
  --  tilesetNameDictionary = createTilesetNameDictionary(data.tilesetNames, soundBanks)
  --end

  data = nil
end

local function tilesetDataCollected(eventData)
  local data = eventData.data
  print("collecting tileset data")
  nearbyTileset = data.tilesetNames
  newMusic()
end

local function initialize()
  if not initialized then
    print('initializing playerscript')
    collectSoundBanks()
    initialized = true
  end
end

local function onInit(initData)
  initialize()
end

local function onLoad(initData)
  initialize()
end

return {
  engineHandlers = {
    onFrame = onFrame,
    onInit = onInit,
    onLoad = onLoad
  },
  eventHandlers = {
    engaging = engaging,
    disengaging = disengaging,
    globalDataCollected = globalDataCollected,
    tilesetDataCollected = tilesetDataCollected
  },
}
