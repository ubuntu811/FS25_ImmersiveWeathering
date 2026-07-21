--[[
    Immersive Weathering (FS25)

    Rebuilt on verified FS25 API patterns, cross-checked against real decompiled
    game source (field/FieldManager.lua, Vehicle.lua, IngameMapElement.lua) rather
    than guessed. Two spots are still marked UNVERIFIED — see comments below —
    because I could not confirm them against real source and don't want to hand
    you another confidently-wrong guess.

    STRUCTURAL FIXES vs previous version:
    1. Entry point: addModEventListener(...) + :loadMap()/:deleteMap(), NOT
       monkey-patching FSBaseMission.init/update. This is almost certainly why
       nothing was firing before — no error, just silently never called.
    2. Debug hotkey: g_inputBinding:registerActionEvent(...), event-driven,
       zero per-frame cost. NOT a polled inputManager:getButtonButtonHasEvent()
       (that method doesn't exist).
    3. Day/sleep hook: g_messageCenter:subscribe(MessageType.DAY_CHANGED, ...).
       Confirmed real (used by Vehicle.lua and animals/Dog.lua in the actual
       game scripts). Fires correctly whether the day passed in real time or
       was skipped via sleep, since sleep advances game time and the message
       fires as part of that — no separate "sleep event" needed.
    4. Density map writes: DensityMapModifier + DensityMapFilter +
       DensityValueCompareType, matching the real pattern in
       field/FieldManager.lua. The previous DensityMapConstraint / DetectionType
       classes do not exist.
]]

ImmersiveWeathering = {}
ImmersiveWeathering.gravelIndices = {}
ImmersiveWeathering.isInitialized = false

-- ============================================================
-- Entry point
-- ============================================================

function ImmersiveWeathering:loadMap(name)
    print("----------------------------------------------------------------------")
    print("Immersive Weathering (FS25): loadMap() called - initializing...")

    ImmersiveWeathering:findGravelLayers()

    -- Day-change hook. Fires once per in-game day, including through sleep-skip.
    -- Confirmed working from your own test log.
    g_messageCenter:subscribe(MessageType.DAY_CHANGED, ImmersiveWeathering.onDayChanged, ImmersiveWeathering)

    ImmersiveWeathering.isInitialized = true
    print("Immersive Weathering (FS25): ready.")
    print("----------------------------------------------------------------------")
end

function ImmersiveWeathering:deleteMap()
    g_inputBinding:removeActionEventsByTarget(ImmersiveWeathering)
    g_messageCenter:unsubscribeAll(ImmersiveWeathering)
end

addModEventListener(ImmersiveWeathering)

-- ============================================================
-- Debug hotkey registration
-- ============================================================
-- CONFIRMED WORKING PATTERN, taken directly from FS25_PowerTools (a real
-- published mod, confirmed running on this machine). Action events must be
-- registered inside PlayerInputComponent.registerGlobalPlayerActionEvents via
-- Utils.appendedFunction - NOT at general mod load time - or the game's input
-- system silently drops them when it rebuilds the action list. This was the
-- actual bug behind "nothing happens" and "doesn't show in the keybind HUD."

PlayerInputComponent.registerGlobalPlayerActionEvents = Utils.appendedFunction(PlayerInputComponent.registerGlobalPlayerActionEvents, function()
    local triggerUp, triggerDown, triggerAlways, startActive, callbackState, disableConflictingBindings = false, true, false, true, nil, true

    local success, actionEventId, otherEvents = g_inputBinding:registerActionEvent(
        InputAction.IMMERSIVE_WEATHERING_DEBUG,
        ImmersiveWeathering,
        ImmersiveWeathering.onDebugKeyPressed,
        triggerUp, triggerDown, triggerAlways, startActive,
        callbackState, disableConflictingBindings
    )

    if success then
        print("Immersive Weathering (FS25): successfully bound action key 1")
        g_inputBinding:setActionEventTextPriority(actionEventId, GS_PRIO_NORMAL)
        g_inputBinding:setActionEventTextVisibility(actionEventId, true)
    else
        print("Immersive Weathering (FS25): FAILED to register debug hotkey.")
    end


    success, actionEventId, otherEvents = g_inputBinding:registerActionEvent(
        InputAction.IMMERSIVE_WEATHERING_DEBUG2,
        ImmersiveWeathering,
        ImmersiveWeathering.onDebug2KeyPressed,
        triggerUp, triggerDown, triggerAlways, startActive,
        callbackState, disableConflictingBindings
    )
    if success then
        print("Immersive Weathering (FS25): successfully bound action key 2")
        g_inputBinding:setActionEventTextPriority(actionEventId, GS_PRIO_NORMAL)
        g_inputBinding:setActionEventTextVisibility(actionEventId, true)
    else
        print("Immersive Weathering (FS25): FAILED to register debug hotkey.")
    end



    local success, actionEventId, otherEvents = g_inputBinding:registerActionEvent(
        InputAction.IMMERSIVE_WEATHERING_DEBUG3,
        ImmersiveWeathering,
        ImmersiveWeathering.onDebug3KeyPressed,
        triggerUp, triggerDown, triggerAlways, startActive,
        callbackState, disableConflictingBindings
    )

    if success then
        print("Immersive Weathering (FS25): successfully bound action key 3")
        g_inputBinding:setActionEventTextPriority(actionEventId, GS_PRIO_NORMAL)
        g_inputBinding:setActionEventTextVisibility(actionEventId, true)
    else
        print("Immersive Weathering (FS25): FAILED to register debug hotkey.")
    end
end)

-- ============================================================
-- Callbacks
-- ============================================================

function ImmersiveWeathering:onDebugKeyPressed(actionName, inputValue, callbackState, isAnalog)
    print("Immersive Weathering (FS25): Hotkey triggered - running manual sweep.")
    ImmersiveWeathering:debugDumpGroundTypeMappings()
    ImmersiveWeathering:debugDumpGroundTypeManager()
    --ImmersiveWeathering:runWeatheringSweep()
end

function ImmersiveWeathering:onDebug2KeyPressed(actionName, inputValue, callbackState, isAnalog)
    print("Immersive Weathering (FS25): Debug 2 Key pressed")
    ImmersiveWeathering:what_am_i_looking_at()
end

function ImmersiveWeathering:onDebug3KeyPressed(actionName, inputValue, callbackState, isAnalog)
    print("Immersive Weathering (FS25): Debug 3 Key pressed")
    ImmersiveWeathering:place_grass()
end

function ImmersiveWeathering:onDayChanged()
    print("Immersive Weathering (FS25): Day changed - running weathering sweep.")
    --ImmersiveWeathering:runWeatheringSweep()
end

function ImmersiveWeathering:what_am_i_looking_at()
    local camera = g_cameraManager:getActiveCamera()
    local x, y, z = getWorldTranslation(camera)
    local dirX, dirY, dirZ = localDirectionToWorld(camera, 0, 0, -1) -- forward vector, confirmed pattern from PlayerCamera.lua

    self.debugFieldRaycastHit = nil
    raycastClosest(x, y, z, dirX, dirY, dirZ, 200, "onDebugFieldRaycastCallback", self, CollisionFlag.TERRAIN)

    if self.debugFieldRaycastHit ~= nil then
        local hx, hy, hz = unpack(self.debugFieldRaycastHit)
        local isOnField, densityBits, groundType = FSDensityMapUtil.getFieldDataAtWorldPosition(hx, hy, hz)

        print(string.format("[FieldData] pos=(%.2f, %.2f, %.2f) isOnField=%s densityBits=%s groundType=%s",
            hx, hy, hz, tostring(isOnField), tostring(densityBits), tostring(groundType)))

        local  r, g, b, depth, material_id = getTerrainAttributesAtWorldPos(g_terrainNode, hx, hy, hz, true, true, true, true, false)
        print(string.format("[TerrainAttributes] pos=(%.2f, %.2f, %.2f) rgb(%s,%s,%s) depth(%s) material(%s)",
               hx, hy, hz, tostring(r), tostring(g), tostring(b), tostring(depth), tostring(material_id)))
    else
        print("[FieldData] No terrain hit within raycast range")
    end
end

function ImmersiveWeathering:place_grass()

    local camera = g_cameraManager:getActiveCamera()
    local x, y, z = getWorldTranslation(camera)
    local dirX, dirY, dirZ = localDirectionToWorld(camera, 0, 0, -1)

    self.debugFieldRaycastHit = nil
    raycastClosest(x, y, z, dirX, dirY, dirZ, 200, "onDebugFieldRaycastCallback", self, CollisionFlag.TERRAIN)

    if self.debugFieldRaycastHit ~= nil then
        local hx, _, hz = unpack(self.debugFieldRaycastHit)
        local decoName = "grassShort" -- confirmed real mapping name from this map's map.xml

        if g_currentMission.foliageSystem:getIsDecoLayerDefined(decoName) then
            local size = 1.0
            g_currentMission.foliageSystem:applyDecoFoliage(decoName, hx, hz, hx + size, hz, hx, hz + size)
            print("Applied '" .. decoName .. "' at " .. hx .. ", " .. hz)
        else
            print("'" .. decoName .. "' not defined on this map")
        end
    end
end

function ImmersiveWeathering:onDebugFieldRaycastCallback(hitObjectId, x, y, z, distance, nx, ny, nz, subShapeIndex, shapeId, isLast)
    if hitObjectId ~= 0 then
        self.debugFieldRaycastHit = {x, y, z}
    end
    return false -- stop after first hit, raycastClosest only needs one
end

-- ============================================================
-- Gravel layer detection
-- ============================================================
-- UNVERIFIED. g_terrainOverlayManager.layerNameToIndex (previous version) is
-- NOT confirmed to exist anywhere in real source - I couldn't find it and
-- can't rule it in or out. Rather than hand you another guessed class name,
-- this version just DUMPS what's actually available on your loaded map so
-- you can find the real field/method name yourself in one test run.
--
-- Run the game with this in place, press LSHIFT+J once, then check your
-- log.txt for a block starting "GRAVEL DEBUG DUMP" - that will show you
-- what g_currentMission actually exposes for terrain/ground layers on your
-- specific map, which is more reliable than any of us guessing further.

function ImmersiveWeathering:findGravelLayers()
    print("Immersive Weathering (FS25): gravel-layer detection is UNVERIFIED - see debugDumpTerrainInfo()")
end

function ImmersiveWeathering:debugDumpTerrainInfo()
    print("GRAVEL DEBUG DUMP -----------------------------------------------------")
    if g_currentMission ~= nil then
        print("g_currentMission.terrainDetailId = " .. tostring(g_currentMission.terrainDetailId))
        print("g_currentMission.terrainRootNode = " .. tostring(g_currentMission.terrainRootNode))
        if g_currentMission.fieldGroundSystem ~= nil then
            print("g_currentMission.fieldGroundSystem exists - inspect its methods")
        end
    end
    if g_terrainNode ~= nil then
        print("g_terrainNode = " .. tostring(g_terrainNode))
    end
    print("If your map mod ships with a custom ground/gravel density layer, check")
    print("its own scripts or XML for the layer name - that's the fastest path.")
    print("-------------------------------------------------------------------------")
end

function ImmersiveWeathering:debugDumpGroundTypeManager()
    local manager = g_groundTypeManager

    if manager == nil then
        print("[ImmersiveWeathering] ERROR: g_groundTypeManager is nil")
        return
    end

    print("[ImmersiveWeathering] g_groundTypeManager fields:")

    for key, value in pairs(manager) do
        print(string.format(
            "[ImmersiveWeathering] manager.%s = %s (%s)",
            tostring(key),
            tostring(value),
            type(value)
        ))

        if type(value) == "table" then
            for nestedKey, nestedValue in pairs(value) do
                print(string.format(
                    "[ImmersiveWeathering]   [%s] = %s (%s)",
                    tostring(nestedKey),
                    tostring(nestedValue),
                    type(nestedValue)
                ))
            end
        end
    end
end

function ImmersiveWeathering:debugDumpGroundTypeMappings()
    local manager = g_groundTypeManager

    if manager == nil then
        print("[ImmersiveWeathering] ERROR: g_groundTypeManager is nil")
        return
    end

    print("[ImmersiveWeathering] ground type mappings:")

    for mappingName, mapping in pairs(manager.groundTypeMappings) do
        print(string.format(
            "[ImmersiveWeathering] mapping key=%s value=%s",
            tostring(mappingName),
            tostring(mapping)
        ))

        if type(mapping) == "table" then
            for fieldName, fieldValue in pairs(mapping) do
                print(string.format(
                    "[ImmersiveWeathering]   %s = %s (%s)",
                    tostring(fieldName),
                    tostring(fieldValue),
                    type(fieldValue)
                ))
            end
        end
    end
end

-- ============================================================
-- Weathering sweep
-- ============================================================
-- The DensityMapModifier / DensityMapFilter / DensityValueCompareType pattern
-- below IS confirmed real (matches field/FieldManager.lua). What's still a
-- placeholder is densityMapId/startChannel/numChannels/targetIndex - those
-- depend on answers from debugDumpTerrainInfo() above, since decorative grass
-- on non-field terrain isn't a fruitType and doesn't have a terrainDataPlaneId
-- the way crops do.

function ImmersiveWeathering:runWeatheringSweep()
    print("----------------------------------------------------------------------")
    print("Immersive Weathering (FS25): STARTING weathering sweep...")

    local startTime = getTimeSec()

    if g_currentMission == nil then
        print("Immersive Weathering ERROR: g_currentMission is nil.")
        return
    end

    -- PLACEHOLDER VALUES - fill in once findGravelLayers()/debugDumpTerrainInfo()
    -- gives you the real density map id + channel layout for your target layer.
    local densityMapId = nil       -- e.g. some grass-foliage density map id
    local startChannel = 0
    local numChannels = 4
    local targetGravelValue = nil  -- the value that means "this pixel is gravel"

    if densityMapId == nil or targetGravelValue == nil then
        print("Immersive Weathering: sweep skipped - densityMapId/targetGravelValue not set yet.")
        print("Run debugDumpTerrainInfo() first and fill these in.")
        print("----------------------------------------------------------------------")
        return
    end

    local modifier = DensityMapModifier.new(densityMapId, startChannel, numChannels, g_terrainNode)
    local filter = DensityMapFilter.new(modifier)
    filter:setValueCompareParams(DensityValueCompareType.EQUAL, targetGravelValue)

    -- executeSet(value, filter) writes `value` to every pixel matching the filter,
    -- within whatever rectangle/parallelogram is set on the modifier. Without a
    -- restricted area it operates map-wide - this is a native C-side op, so a
    -- full-map pass here is cheap (same class of operation FieldManager itself
    -- uses), unlike doing the equivalent in a Lua loop.
    modifier:executeSet(1, filter)

    local endTime = getTimeSec()
    print(string.format("Immersive Weathering (FS25): FINISHED in %.2f ms", (endTime - startTime)))
    print("----------------------------------------------------------------------")
end
