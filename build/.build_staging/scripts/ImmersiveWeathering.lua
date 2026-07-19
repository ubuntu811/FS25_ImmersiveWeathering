ImmersiveWeathering = {}
ImmersiveWeathering.gravelIndices = {} -- Stores discovered gravel texture layer IDs

function ImmersiveWeathering:init()
    -- Hook into map loading to auto-detect gravel texture indices
    FSBaseMission.registerModifierFunction(FSBaseMission, "onLoad", ImmersiveWeathering.onMapLoad)
    
    -- Hook into the night skipping / sleep event
    FSBaseMission.registerModifierFunction(FSBaseMission, "onNightSkipped", ImmersiveWeathering.onNightSkipped)
end

function ImmersiveWeathering:onMapLoad()
    if g_currentMission == nil or g_currentMission.terrainDetailId == nil then return end

    print("Immersive Weathering: Scanning map data to identify gravel materials...")
    
    -- Dynamically read map textures to find anything named "gravel"
    local layers = g_terrainOverlayManager:getLayers()
    for index, layer in pairs(layers) do
        local layerName = string.lower(layer.name)
        if string.find(layerName, "gravel") then
            table.insert(ImmersiveWeathering.gravelIndices, index)
            print(string.format("Immersive Weathering: Found target layer '%s' at Index ID: %d", layer.name, index))
        end
    end
    
    if #ImmersiveWeathering.gravelIndices == 0 then
        print("Immersive Weathering WARNING: No gravel texture layers detected on this map!")
    end
end

function ImmersiveWeathering:update(dt)
    -- Ensure the game and player are fully loaded before checking inputs
    if g_currentMission == nil or g_currentMission.inputManager == nil then return end

    -- DEBUG TRIGGER: Check if the player is holding Left Shift AND taps 'J'
    -- (We use the game engine's raw keyboard input codes)
    if g_currentMission.inputManager:getInputButton(Input.KEY_lshift) and g_currentMission.inputManager:getInputButtonHasEvent(Input.KEY_j) then
        print("Immersive Weathering: [DEBUG] Manual override hotkey triggered via LSHIFT + J!")
        -- Call our exact same weathering function on demand!
        ImmersiveWeathering:onNightSkipped()
    end
end

function ImmersiveWeathering:onNightSkipped()
    print("----------------------------------------------------------------------")
    print("Immersive Weathering: STARTING full-map grass invasion sweep...")
    
    -- Start our benchmark timer (using the internal CPU clock in milliseconds)
    local startTime = curTime()

    local terrainId = g_currentMission.terrainDetailId
    local grassSystem = g_currentMission.fruits[FruitType.GRASS]
    
    -- Safety checks
    if grassSystem == nil then
        print("Immersive Weathering ERROR: Could not access the game's global Grass Foliage system.")
        print("----------------------------------------------------------------------")
        return
    end
    
    if #ImmersiveWeathering.gravelIndices == 0 then
        print("Immersive Weathering CANCELLED: Skipping processing because no gravel layers exist.")
        print("----------------------------------------------------------------------")
        return
    end
    
    -- Instantiate the C++ DensityMapModifier pointing to the grass layer's layout ID
    local modifier = DensityMapModifier.new(grassSystem.getDensityMapId(), 0, 4)
    
    -- Target a 2km x 2km bounding box (covers standard base-game maps entirely)
    modifier:setRectangle(0, 0, 2048, 2048)
    
    -- Process each gravel type discovered
    for _, targetIndex in ipairs(ImmersiveWeathering.gravelIndices) do
        -- Tell the C++ core: ONLY modify pixels where the ground texture EXACTLY matches this gravel layer ID
        modifier:setConstraint(DensityMapConstraint.new(terrainId, 0, 4, DetectionType.EQUALS, targetIndex))
        
        -- Value 1 represents the smallest visible stage of wild green grass
        modifier:executeSet(1)
    end
    
    -- End benchmark timer
    local endTime = curTime()
    local totalExecutionTime = endTime - startTime
    
    print(string.format("Immersive Weathering: FINISHED. Native C++ global operation took: %.2f ms", totalExecutionTime))
    print("----------------------------------------------------------------------")
end

-- Initialize the script hook instantly
ImmersiveWeathering:init()
