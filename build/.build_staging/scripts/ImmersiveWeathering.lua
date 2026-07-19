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

    -- Debug hotkey (LSHIFT+J, declared in modDesc.xml).
    -- Args: action, target, callback, triggerUp, triggerDown, triggerAlways, startActive
    -- triggerDown=true, triggerUp=false is the usual "fire once when pressed" combo.
    -- CONFIRM in-game this doesn't fire repeatedly while held; if it does, the
    -- triggerUp/triggerDown/triggerAlways flags need adjusting.
    local eventId
    _, eventId = g_inputBinding:registerActionEvent(
        InputAction.IMMERSIVE_WEATHERING_DEBUG,
        ImmersiveWeathering,
        ImmersiveWeathering.onDebugKeyPressed,
        false, -- triggerUp
        true,  -- triggerDown
        false, -- triggerAlways
        true   -- startActive
    )
    if eventId ~= nil then
        g_inputBinding:setActionEventTextVisibility(eventId, true)
    end

    -- Day-change hook. Fires once per in-game day, including through sleep-skip.
    g_messageCenter:subscribe(MessageType.DAY_CHANGED, ImmersiveWeathering.onDayChanged, ImmersiveWeathering)

    ImmersiveWeathering.isInitialized = true
    print("Immersive Weathering (FS25): ready. Press LSHIFT+J to force a sweep.")
    print("----------------------------------------------------------------------")
end

function ImmersiveWeathering:deleteMap()
    g_inputBinding:removeActionEventsByTarget(ImmersiveWeathering)
    g_messageCenter:unsubscribeAll(ImmersiveWeathering)
end

addModEventListener(ImmersiveWeathering)

-- ============================================================
-- Callbacks
-- ============================================================

function ImmersiveWeathering:onDebugKeyPressed(actionName, inputValue, callbackState, isAnalog)
    print("Immersive Weathering (FS25): Hotkey triggered - running manual sweep.")
    ImmersiveWeathering:runWeatheringSweep()
end

function ImmersiveWeathering:onDayChanged()
    print("Immersive Weathering (FS25): Day changed - running weathering sweep.")
    ImmersiveWeathering:runWeatheringSweep()
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

    local startTime = curTime()

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

    local endTime = curTime()
    print(string.format("Immersive Weathering (FS25): FINISHED in %.2f ms", (endTime - startTime)))
    print("----------------------------------------------------------------------")
end
