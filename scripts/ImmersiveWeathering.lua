--[[
    Immersive Weathering (FS25)

    Current MVP:
      * run a weathering sweep once per in-game day
      * sample random map coordinates
      * place grassShort on gravel
      * provide debug keys for terrain/foliage inspection and manual testing
]]

ImmersiveWeathering = {}

local MATERIAL = {
    DIRT   = 1,
    GRASS  = 2,
    SAND   = 3,
    GRAVEL = 6,
    STONE  = 7,
}

local WEATHERABLE_MATERIALS = {
    [MATERIAL.DIRT]   = true,
    [MATERIAL.SAND]   = true,
    [MATERIAL.GRASS]   = true,
    [MATERIAL.GRAVEL] = true,
}

local WEATHERING_COLLISION_FLAG_NAMES = {
    "TERRAIN", "TREE", "VEHICLE", "VEHICLE_FORK",
    "STATIC_OBJECT", "DYNAMIC_OBJECT", "BUILDING", "ROAD", "ANIMAL"
}

-- Every name confirmed in WAILA's Shift+K "decoFoliages" writable-layers
-- dump - the full real roster, not a guess.
local TEST_RIG_DECO_NAMES = {
    "decoFoliage", "decoBush", "decoFoliageEU", "decoBushUS",
    "forestGrass", "forestBush", "forestPlants", "groundFoliage", "waterPlants",
}
local TEST_RIG_SPACING = 2.0
local TEST_RIG_MEADOW_STATES = 9
local TEST_RIG_DECO_REPEAT_LEVELS = 9
local AREA_FILL_SIZE = 3.0
local AREA_FILL_STEP = 0.5

-- Reverted back to grassShort after proving meadow-sowing was a dead end:
-- FSDensityMapUtil.updateSowingArea only ever succeeds on ground that's
-- already a registered field (changedArea=0 every single time off-field,
-- confirmed directly via its own return values, all night) - and IW's
-- whole domain is off-field ground by design (fieldIsMaterial/isOnField
-- require not-a-field). So sowing can never place anything IW is actually
-- allowed to touch. grassShort is the one thing proven reliable all
-- session with zero exceptions - same old write/read name split as
-- before applies: writes as "grassShort", reads back as "decoFoliage"
-- (grassShort isn't in this map's own declared type list at all, so
-- getFoliageNameAt can never find it back by that name).
local GRASS_LOW_WRITE = "grassShort"
local GRASS_LOW_READ = "decoFoliage"
local EMPTY = "<empty>"
-- "decoBush" (Layer 1, type 3) is confirmed in decoFoliages - real,
-- writable in principle, used for the weed accent and the pre-existing
-- map bush - but flaky this session (rejected every attempt). Left wired
-- up as a harmless no-op rather than ripped out, same reasoning as fruit
-- below: costs nothing to leave in case a future session behaves
-- differently, same unexplained flip we saw once already.
local BUSH = "decoBush"
local DECO_ACCENT = BUSH

local NEIGHBOR_STEP = 1.0
local NEIGHBOR_OFFSETS = {
    {-1, -1}, {0, -1}, {1, -1},
    {-1,  0},          {1,  0},
    {-1,  1}, {0,  1}, {1,  1},
}

-- What a sampled spot may become next, keyed by what's there now. Each
-- state's options are mutually exclusive - one weighted pick, weights
-- don't need to sum to 1 (the remainder is "nothing happens"). Add rows
-- here for new transformations, and a matching action in
-- applyFoliageTransitions, instead of growing an if/elseif chain (e.g. a
-- future grass-paint <-> dirt-paint table for tyre wear would be the
-- same shape, walked the same way). "fruit" is effectively dead off-field
-- now (sowing never succeeds there, confirmed) - left in as a harmless
-- no-op alongside "weed", not removed, same reasoning as decoBush above.
local FOLIAGE_STATE_OPTIONS = {
    [EMPTY] = {
        {weight = 0.05, action = "seed"},
    },
    [GRASS_LOW_READ] = {
        {weight = 0.10, action = "weed"},   -- grassShort -> decoBush
        {weight = 0.10, action = "fruit"},  -- grassShort -> a random crop, why not
    },
}

-- Spreading to a neighbor is orthogonal to what a patch itself becomes,
-- so it's rolled separately rather than as one of the mutually exclusive
-- options above - a patch can weed/fruit AND spread on the same visit.
-- encroachesOnGrass lets a spread claim a neighbor that already has grass
-- on it instead of requiring empty ground - bushes push grass out, grass
-- doesn't push anything out.
local FOLIAGE_SPREAD_RULES = {
    [GRASS_LOW_READ] = {
        chance = 0.10,
        place = function(self, x, z) return self:placeFoliage(x, z, GRASS_LOW_WRITE) end,
    },
    [BUSH] = {
        chance = 0.05,
        place = function(self, x, z) return self:placeFoliage(x, z, BUSH) end,
        encroachesOnGrass = true,
    },
}

local function pickWeightedAction(options)
    local roll = math.random()
    local cumulative = 0

    for _, option in ipairs(options) do
        cumulative = cumulative + option.weight
        if roll <= cumulative then
            return option.action
        end
    end

    return nil
end

local function debugPrint(message)
    print("[ImmersiveWeathering] " .. tostring(message))
end

local function debugPrintf(formatString, ...)
    debugPrint(string.format(formatString, ...))
end

ImmersiveWeathering.mapI3dFilename = nil

BaseMission.loadMap = Utils.overwrittenFunction(
    BaseMission.loadMap,
    function(mission, superFunc, filename, ...)
        ImmersiveWeathering.mapI3dFilename = filename
        return superFunc(mission, filename, ...)
    end
)

-- ============================================================
-- Entry point
-- ============================================================

function ImmersiveWeathering:loadMap(_)
    debugPrint("----------------------------------------------------------------------")
    debugPrint("Immersive Weathering (FS25): loadMap() called - initializing...")

    g_messageCenter:subscribe(
        MessageType.DAY_CHANGED,
        ImmersiveWeathering.onDayChanged,
        self
    )

    debugPrint("Immersive Weathering (FS25): ready.")
    debugPrint("----------------------------------------------------------------------")
end

function ImmersiveWeathering:deleteMap()
    g_inputBinding:removeActionEventsByTarget(self)
    g_messageCenter:unsubscribeAll(self)
end

addModEventListener(ImmersiveWeathering)

-- ============================================================
-- Debug hotkeys
-- ============================================================

PlayerInputComponent.registerGlobalPlayerActionEvents =
    Utils.appendedFunction(
        PlayerInputComponent.registerGlobalPlayerActionEvents,
        function()
            local triggerUp = false
            local triggerDown = true
            local triggerAlways = false
            local startActive = true
            local callbackState = nil
            local disableConflictingBindings = true

            local function registerDebugAction(inputAction, callback, label)
                local success, actionEventId = g_inputBinding:registerActionEvent(
                    inputAction,
                    ImmersiveWeathering,
                    callback,
                    triggerUp,
                    triggerDown,
                    triggerAlways,
                    startActive,
                    callbackState,
                    disableConflictingBindings
                )

                if success then
                    debugPrintf(
                            "Immersive Weathering (FS25): successfully bound %s",
                            label
                        )
                    g_inputBinding:setActionEventTextPriority(
                        actionEventId,
                        GS_PRIO_NORMAL
                    )
                    g_inputBinding:setActionEventTextVisibility(
                        actionEventId,
                        true
                    )
                else
                    debugPrintf(
                            "Immersive Weathering (FS25): FAILED to register %s",
                            label
                        )
                end
            end

            registerDebugAction(
                InputAction.IMMERSIVE_WEATHERING_DEBUG,
                ImmersiveWeathering.onDebugKeyPressed,
                "debug key 1"
            )

            registerDebugAction(
                InputAction.IMMERSIVE_WEATHERING_DEBUG2,
                ImmersiveWeathering.onDebug2KeyPressed,
                "debug key 2"
            )

            registerDebugAction(
                InputAction.IMMERSIVE_WEATHERING_DEBUG3,
                ImmersiveWeathering.onDebug3KeyPressed,
                "debug key 3"
            )

            registerDebugAction(
                InputAction.IMMERSIVE_WEATHERING_DEBUG4,
                ImmersiveWeathering.onDebug4KeyPressed,
                "debug key 4"
            )
        end
    )

-- ============================================================
-- Callbacks
-- ============================================================

function ImmersiveWeathering:onDebugKeyPressed(
    actionName,
    inputValue,
    callbackState,
    isAnalog
)
    debugPrint("Immersive Weathering (FS25): Debug 1 key pressed")

    self:placeFoliageTestRig()
end

function ImmersiveWeathering:onDebug2KeyPressed(
    actionName,
    inputValue,
    callbackState,
    isAnalog
)
    debugPrint("Immersive Weathering (FS25): Debug 2 key pressed")
    self:weatherAtCrosshair()
end

function ImmersiveWeathering:onDebug4KeyPressed(
    actionName,
    inputValue,
    callbackState,
    isAnalog
)
    debugPrint("Immersive Weathering (FS25): Debug 4 key pressed")
    self:placeFoliageAreaFill()
end

function ImmersiveWeathering:onDebug3KeyPressed(
    actionName,
    inputValue,
    callbackState,
    isAnalog
)
    debugPrint("Immersive Weathering (FS25): Debug 3 key pressed")
    --self:placeGrassAtCrosshair()
    self:runWeatheringSweep()
end

function ImmersiveWeathering:onDayChanged()
    self:runWeatheringSweep()
end

-- ============================================================
-- Debug helpers
-- ============================================================

function ImmersiveWeathering:debugDumpFoliageLayers()
    local foliageSystem = g_currentMission.foliageSystem

    debugPrint("DECO FOLIAGES")
    for index, foliage in ipairs(foliageSystem.decoFoliages) do
        if foliage ~= nil and foliage.layerName ~= nil then
            debugPrint(
                string.format(
                    "%s [%s] : %s",
                    tostring(foliage.terrainDataPlaneId),
                    tostring(index),
                    tostring(foliage.layerName)
                )
            )
        end
    end

    debugPrint("PAINTABLE FOLIAGES")
    for index, foliage in ipairs(foliageSystem.paintableFoliages) do
        if foliage ~= nil and foliage.layerName ~= nil then
            debugPrint(
                string.format(
                    "%s [%s] : %s",
                    tostring(foliage.terrainDataPlaneId),
                    tostring(index),
                    tostring(foliage.layerName)
                )
            )
        end
    end
end

function ImmersiveWeathering:whatAmILookingAt()
    local camera = g_cameraManager:getActiveCamera()
    local x, y, z = getWorldTranslation(camera)
    local dirX, dirY, dirZ = localDirectionToWorld(camera, 0, 0, -1)

    self.debugFieldRaycastHit = nil

    raycastClosest(
        x,
        y,
        z,
        dirX,
        dirY,
        dirZ,
        200,
        "onDebugFieldRaycastCallback",
        self,
        CollisionFlag.TERRAIN
    )

    if self.debugFieldRaycastHit == nil then
        debugPrint("[FieldData] No terrain hit within raycast range")
        return
    end

    local hx, hy, hz = unpack(self.debugFieldRaycastHit)
    local isOnField, densityBits, groundType =
        FSDensityMapUtil.getFieldDataAtWorldPosition(hx, hy, hz)

    debugPrintf(
            "[FieldData] pos=(%.2f, %.2f, %.2f) isOnField=%s densityBits=%s groundType=%s",
            hx,
            hy,
            hz,
            tostring(isOnField),
            tostring(densityBits),
            tostring(groundType)
        )

    local r, g, b, depth, materialId =
        getTerrainAttributesAtWorldPos(
            g_terrainNode,
            hx,
            hy,
            hz,
            true,
            true,
            true,
            true,
            false
        )

    debugPrintf(
            "[TerrainAttributes] pos=(%.2f, %.2f, %.2f) rgb(%s,%s,%s) depth(%s) material(%s)",
            hx,
            hy,
            hz,
            tostring(r),
            tostring(g),
            tostring(b),
            tostring(depth),
            tostring(materialId)
        )


    --self:dumpFoliageAtWorldPosition(hx, hz)

    self:scanFoliageArea(hx, hz)
end

function ImmersiveWeathering:placeGrassAtCrosshair()
    local camera = g_cameraManager:getActiveCamera()
    local x, y, z = getWorldTranslation(camera)
    local dirX, dirY, dirZ = localDirectionToWorld(camera, 0, 0, -1)

    self.debugFieldRaycastHit = nil

    raycastClosest(
        x,
        y,
        z,
        dirX,
        dirY,
        dirZ,
        200,
        "onDebugFieldRaycastCallback",
        self,
        CollisionFlag.TERRAIN
    )

    if self.debugFieldRaycastHit == nil then
        debugPrint("[ImmersiveWeathering] No terrain hit within raycast range")
        return
    end

    local hx, _, hz = unpack(self.debugFieldRaycastHit)
    self:placeFoliage(hx, hz)
end

-- Runs the exact same per-sample logic the daily sweep uses, but on one
-- targeted spot instead of 1000 random ones - point at a specific patch
-- and see what it is, what got rolled, and what it became, instead of
-- waiting on blind resampling luck to ever land there again.
function ImmersiveWeathering:weatherAtCrosshair()
    local camera = g_cameraManager:getActiveCamera()
    local x, y, z = getWorldTranslation(camera)
    local dirX, dirY, dirZ = localDirectionToWorld(camera, 0, 0, -1)

    self.debugFieldRaycastHit = nil

    raycastClosest(
        x, y, z,
        dirX, dirY, dirZ,
        200,
        "onDebugFieldRaycastCallback",
        self,
        CollisionFlag.TERRAIN
    )

    if self.debugFieldRaycastHit == nil then
        debugPrint("[Weather] No terrain hit within raycast range")
        return
    end

    local hx, _, hz = unpack(self.debugFieldRaycastHit)
    local before = self:getFoliageNameAt(hx, hz) or EMPTY
    local stats = {}

    self:applyFoliageTransitions(hx, hz, stats, true)

    local after = self:getFoliageNameAt(hx, hz) or EMPTY

    debugPrintf(
        "[Weather] (%.2f %.2f) before=%s after=%s seeded=%d spread=%d weeded=%d fruited=%d",
        hx, hz, before, after,
        stats.seeded or 0, stats.spread or 0, stats.weeded or 0, stats.fruited or 0
    )
end

-- For the "annoying bush" question: does densely surrounding it with
-- grassShort do anything to it? Bet is no - everything tonight pointed at
-- it not being part of the density-map system at all (plow/mow/deco-clear
-- all passed through it untouched) - but cheap to actually check instead
-- of assuming. Fills a real 3x3m area (not a row) around the crosshair
-- position with grassShort, ignoring every gate (material/field/clear-
-- spot checks) since this is a deliberate manual test, not ambient
-- weathering - ok to try even in a normally-excluded spot.
function ImmersiveWeathering:placeFoliageAreaFill()
    local camera = g_cameraManager:getActiveCamera()
    local x, y, z = getWorldTranslation(camera)
    local dirX, dirY, dirZ = localDirectionToWorld(camera, 0, 0, -1)

    self.debugFieldRaycastHit = nil

    raycastClosest(
        x, y, z,
        dirX, dirY, dirZ,
        200,
        "onDebugFieldRaycastCallback",
        self,
        CollisionFlag.TERRAIN
    )

    if self.debugFieldRaycastHit == nil then
        debugPrint("[AreaFill] No terrain hit within raycast range")
        return
    end

    local hx, _, hz = unpack(self.debugFieldRaycastHit)
    local half = AREA_FILL_SIZE * 0.5
    local placed = 0

    for px = hx - half, hx + half, AREA_FILL_STEP do
        for pz = hz - half, hz + half, AREA_FILL_STEP do
            if self:placeFoliage(px, pz, GRASS_LOW_WRITE) then
                placed = placed + 1
            end
        end
    end

    debugPrintf("[AreaFill] %dx%dm around (%.2f %.2f): %d/%d stamps placed",
        AREA_FILL_SIZE, AREA_FILL_SIZE, hx, hz, placed, ((AREA_FILL_SIZE / AREA_FILL_STEP) + 1) ^ 2)
end

-- Deterministic test rig: no dice rolls, no waiting on the sweep to find
-- the right spot. Places one row of every confirmed-writable deco species
-- (TEST_RIG_DECO_NAMES, straight from WAILA's Shift+K writable-layers
-- dump) and a second row of meadow at explicit growth states 1-9, all at
-- once, all logged with exact positions - so "is this texture difference
-- just a growth-state thing" is a direct visual comparison, not a guess.
function ImmersiveWeathering:placeFoliageTestRig()
    local camera = g_cameraManager:getActiveCamera()
    local x, y, z = getWorldTranslation(camera)
    local dirX, dirY, dirZ = localDirectionToWorld(camera, 0, 0, -1)

    self.debugFieldRaycastHit = nil

    raycastClosest(
        x, y, z,
        dirX, dirY, dirZ,
        200,
        "onDebugFieldRaycastCallback",
        self,
        CollisionFlag.TERRAIN
    )

    if self.debugFieldRaycastHit == nil then
        debugPrint("[TestRig] No terrain hit within raycast range")
        return
    end

    local hx, _, hz = unpack(self.debugFieldRaycastHit)

    debugPrint("[TestRig] --- deco/paintable species row ---")
    for i, name in ipairs(TEST_RIG_DECO_NAMES) do
        local px = hx + (i - 1) * TEST_RIG_SPACING
        local ok = self:placeFoliage(px, hz, name)
        debugPrintf("[TestRig] [%d] %s at (%.2f %.2f) -> %s", i, name, px, hz, tostring(ok))
    end

    debugPrint("[TestRig] --- meadow growth-state row ---")
    local meadowIndex = self:getMeadowFruitTypeIndex()

    if meadowIndex == nil then
        debugPrint("[TestRig] meadow fruit type unavailable")
    else
        local rowZ = hz + TEST_RIG_SPACING * 1.5

        for state = 1, TEST_RIG_MEADOW_STATES do
            local px = hx + (state - 1) * TEST_RIG_SPACING
            self:sowFruit(px, rowZ, meadowIndex, state)
            debugPrintf("[TestRig] meadow L%d at (%.2f %.2f)", state, px, rowZ)
        end
    end

    -- applyDecoFoliage has no growth-level parameter at all (unlike
    -- sowing's explicit growthState) - this is an experiment, not a known
    -- mechanic: does repeat-stamping the same spot accumulate density the
    -- way this engine's real paint tools often work? Column N gets N
    -- applyDecoFoliage calls on the exact same spot. Using grassShort
    -- since it's the one name proven reliable all session.
    debugPrint("[TestRig] --- grassShort repeat-stamp row (experiment) ---")
    local repeatRowZ = hz + TEST_RIG_SPACING * 3

    for repeatCount = 1, TEST_RIG_DECO_REPEAT_LEVELS do
        local px = hx + (repeatCount - 1) * TEST_RIG_SPACING

        for _ = 1, repeatCount do
            self:placeFoliage(px, repeatRowZ, GRASS_LOW_WRITE)
        end

        debugPrintf("[TestRig] grassShort x%d at (%.2f %.2f)", repeatCount, px, repeatRowZ)
    end
end

function ImmersiveWeathering:onDebugFieldRaycastCallback(
    hitObjectId,
    x,
    y,
    z,
    distance,
    nx,
    ny,
    nz,
    subShapeIndex,
    shapeId,
    isLast
)
    if hitObjectId ~= 0 then
        self.debugFieldRaycastHit = {x, y, z}
    end

    return false
end

function ImmersiveWeathering:debugDumpGroundTypeManager()
    local manager = g_groundTypeManager

    if manager == nil then
        debugPrint("ERROR: g_groundTypeManager is nil")
        return
    end

    debugPrint("g_groundTypeManager fields:")

    for key, value in pairs(manager) do
        debugPrint(
            string.format(
                "manager.%s = %s (%s)",
                tostring(key),
                tostring(value),
                type(value)
            )
        )

        if type(value) == "table" then
            for nestedKey, nestedValue in pairs(value) do
                debugPrint(
                    string.format(
                        "  [%s] = %s (%s)",
                        tostring(nestedKey),
                        tostring(nestedValue),
                        type(nestedValue)
                    )
                )
            end
        end
    end
end

function ImmersiveWeathering:debugDumpGroundTypeMappings()
    local manager = g_groundTypeManager

    if manager == nil then
        debugPrint("ERROR: g_groundTypeManager is nil")
        return
    end

    if manager.groundTypeMappings == nil then
        debugPrint("ERROR: g_groundTypeManager.groundTypeMappings is nil")
        return
    end

    debugPrint("ground type mappings:")

    for mappingName, mapping in pairs(manager.groundTypeMappings) do
        debugPrint(
            string.format(
                "mapping key=%s value=%s",
                tostring(mappingName),
                tostring(mapping)
            )
        )

        if type(mapping) == "table" then
            for fieldName, fieldValue in pairs(mapping) do
                debugPrint(
                    string.format(
                        "  %s = %s (%s)",
                        tostring(fieldName),
                        tostring(fieldValue),
                        type(fieldValue)
                    )
                )
            end
        end
    end
end

-- ============================================================
-- Weathering
-- ============================================================

function ImmersiveWeathering:placeFoliage(x, z, decoName)
    decoName = decoName or "grassShort"

    local foliageSystem = g_currentMission.foliageSystem
    if not foliageSystem:getIsDecoLayerDefined(decoName) then
        debugPrint(string.format("foliage layer '%s' is not defined", decoName))
        return false
    end

    -- applyDecoFoliage only ever takes a parallelogram - there's no round
    -- brush at this API level (checked: no native function anywhere takes
    -- a BrushType, that enum belongs to GIANTS Editor / the in-game
    -- construction-brush system, neither of which this call goes through).
    -- Randomizing size and rotation per stamp is the cheap way to stop
    -- every patch reading as the same axis-aligned square.
    local halfSize = 0.35 + math.random() * 0.35
    local angle = math.random() * math.pi * 2
    local cosA, sinA = math.cos(angle), math.sin(angle)

    local function corner(dx, dz)
        return x + dx * cosA - dz * sinA, z + dx * sinA + dz * cosA
    end

    local x0, z0 = corner(-halfSize, -halfSize)
    local x1, z1 = corner(halfSize, -halfSize)
    local x2, z2 = corner(-halfSize, halfSize)

    foliageSystem:applyDecoFoliage(decoName, x0, z0, x1, z1, x2, z2)

    debugPrint(string.format("%s to (%.2f %.2f)", decoName, x, z))
    return true
end

function ImmersiveWeathering:getWeatheringCollisionMask()
    if self.weatheringCollisionMask == nil then
        local mask = 0
        for _, name in ipairs(WEATHERING_COLLISION_FLAG_NAMES) do
            if CollisionFlag[name] ~= nil then
                mask = bit32.bor(mask, CollisionFlag[name])
            end
        end
        self.weatheringCollisionMask = mask
    end

    return self.weatheringCollisionMask
end

function ImmersiveWeathering:onWeatheringRaycastCallback(hitObjectId)
    if hitObjectId ~= nil and hitObjectId ~= 0 then
        self.weatheringRaycastHit = hitObjectId
    end

    return false
end

-- Roads, rails and buildings sit on top of terrain that is often still
-- painted GRAVEL/DIRT underneath, so the material check alone can't tell
-- them apart from open ground. Raycast straight down and bail unless the
-- closest thing under the sky is the terrain itself.
function ImmersiveWeathering:isSpotClearForFoliage(x, z)
    local terrainHeight = getTerrainHeightAtWorldPos(g_terrainNode, x, 0, z)

    self.weatheringRaycastHit = nil

    raycastClosest(
        x, terrainHeight + 3, z,
        0, -1, 0,
        6,
        "onWeatheringRaycastCallback",
        self,
        self:getWeatheringCollisionMask()
    )

    return self.weatheringRaycastHit == nil
        or self.weatheringRaycastHit == g_terrainNode
        or self.weatheringRaycastHit == g_currentMission.terrainRootNode
end

local function decodeFoliageBitsAt(layerData, x, z)
    local planeId = layerData.terrainDataPlaneId
    local numTypeChannels = layerData.numTypeIndexChannels

    if planeId == nil or numTypeChannels == nil or numTypeChannels <= 0 then
        return nil
    end

    local bits = getDensityAtWorldPos(planeId, x, 0, z)
    local typeMask = 2 ^ numTypeChannels - 1
    local typeIndex = bitAND(bits, typeMask)

    if typeIndex <= 0 then
        return nil
    end

    local value = bitShiftRight(bits, numTypeChannels)

    if value <= 0 then
        return nil
    end

    return layerData.types[typeIndex]
end

function ImmersiveWeathering:getFoliageNameAt(x, z)
    local data = self:loadFoliageDebugData()

    if data == nil then
        return nil
    end

    self:resolveFoliagePlaneIds(data)

    for _, layerData in ipairs(data.multilayers) do
        local name = decodeFoliageBitsAt(layerData, x, z)

        if name ~= nil then
            return name
        end
    end

    return nil
end

function ImmersiveWeathering:getSeedbedGroundTypeValue()
    if self.seedbedGroundTypeValue == nil then
        self.seedbedGroundTypeValue = FieldGroundType.getValueByType(FieldGroundType.SEEDBED)
    end

    return self.seedbedGroundTypeValue
end

-- Shared by plantRandomFruit and plantMeadow - sows a real crop via the
-- same call SowingMachine/TreePlanter use, painting SEEDBED ground type
-- underneath it (unlike the deco-foliage placements, which are purely
-- cosmetic and leave the terrain material untouched).
-- Never trusted this call's actual result before now - it was always
-- assumed to succeed. If it silently no-ops off-field the same way
-- cultivator/plow do without createField, every "sprouted"/"seeded" log
-- so far could have been claiming success for nothing. Check for real.
function ImmersiveWeathering:sowFruit(x, z, fruitIndex, growthState)
    local halfSize = 0.5

    local changedArea, totalArea = FSDensityMapUtil.updateSowingArea(
        fruitIndex,
        x - halfSize, z - halfSize,
        x + halfSize, z - halfSize,
        x - halfSize, z + halfSize,
        self:getSeedbedGroundTypeValue(),
        false,
        0,
        growthState
    )

    debugPrintf(
        "[Sow] fruitIndex=%d at (%.2f %.2f) changedArea=%s totalArea=%s",
        fruitIndex, x, z, tostring(changedArea), tostring(totalArea)
    )

    return changedArea ~= nil and changedArea > 0
end

-- "why not" - plants a random registered crop at growth state 1.
function ImmersiveWeathering:plantRandomFruit(x, z)
    local fruitTypes = g_fruitTypeManager:getFruitTypes()

    if fruitTypes == nil or #fruitTypes == 0 then
        return false
    end

    local fruitType = fruitTypes[math.random(#fruitTypes)]

    if not self:sowFruit(x, z, fruitType.index) then
        return false
    end

    debugPrintf(
        "a wild %s sprouted at (%.2f %.2f)",
        tostring(fruitType.name or fruitType.index),
        x,
        z
    )

    return true
end

function ImmersiveWeathering:getMeadowFruitTypeIndex()
    if self.meadowFruitTypeIndex == nil then
        local meadow = g_fruitTypeManager:getFruitTypeByName("MEADOW")

        if meadow == nil then
            debugPrint("ERROR: no 'MEADOW' fruit type registered on this map")
            self.meadowFruitTypeIndex = false
        else
            self.meadowFruitTypeIndex = meadow.index
        end
    end

    return self.meadowFruitTypeIndex or nil
end

-- Picks one mutually-exclusive outcome from FOLIAGE_STATE_OPTIONS for
-- whatever is at (x, z), then separately rolls FOLIAGE_SPREAD_RULES so
-- spreading can happen on the same visit as growing. New outcomes need a
-- table row above and one more branch here, not a new nested if/elseif
-- per existing state.
function ImmersiveWeathering:runFoliageAction(action, x, z, stats)
    if action == "seed" then
        if self:fieldIsMaterial(x, z, WEATHERABLE_MATERIALS)
            and self:isSpotClearForFoliage(x, z)
            and self:placeFoliage(x, z, GRASS_LOW_WRITE)
        then
            stats.seeded = (stats.seeded or 0) + 1
        end
    elseif action == "weed" then
        if not self:isOnField(x, z) and self:placeFoliage(x, z, DECO_ACCENT) then
            stats.weeded = (stats.weeded or 0) + 1
        end
    elseif action == "fruit" then
        if not self:isOnField(x, z) and self:plantRandomFruit(x, z) then
            stats.fruited = (stats.fruited or 0) + 1
        end
    end
end

-- force=true skips every dice roll and tries everything possible for the
-- sampled spot instead of one weighted pick - used by weatherAtCrosshair
-- so a manual debug press always shows something instead of "nothing,
-- try again" ~95% of the time on empty ground. The real sweep always
-- calls this with force=false (or omitted) so ambient weathering stays
-- genuinely rare - only the deliberate single-point tool is deterministic.
function ImmersiveWeathering:applyFoliageTransitions(x, z, stats, force)
    local name = self:getFoliageNameAt(x, z) or EMPTY
    local options = FOLIAGE_STATE_OPTIONS[name]

    if options ~= nil then
        if force then
            for _, option in ipairs(options) do
                self:runFoliageAction(option.action, x, z, stats)
            end
        else
            local action = pickWeightedAction(options)

            if action ~= nil then
                self:runFoliageAction(action, x, z, stats)
            end
        end
    end

    local spreadRule = FOLIAGE_SPREAD_RULES[name]

    if spreadRule ~= nil and (force or math.random() <= spreadRule.chance) then
        local offset = NEIGHBOR_OFFSETS[math.random(#NEIGHBOR_OFFSETS)]
        local nx = x + offset[1] * NEIGHBOR_STEP
        local nz = z + offset[2] * NEIGHBOR_STEP
        local neighborName = self:getFoliageNameAt(nx, nz)

        local canClaimNeighbor =
            neighborName == nil
            or (spreadRule.encroachesOnGrass and neighborName == GRASS_LOW_READ)

        if canClaimNeighbor
            and self:fieldIsMaterial(nx, nz, WEATHERABLE_MATERIALS)
            and self:isSpotClearForFoliage(nx, nz)
            and spreadRule.place(self, nx, nz)
        then
            stats.spread = (stats.spread or 0) + 1
        end
    end
end

function ImmersiveWeathering:fieldIsMaterial(x,z,materials)
    local  _, _, _, _, material_id = getTerrainAttributesAtWorldPos(g_terrainNode, x, 0, z, true, true, true, true, false)

    local isOnField, _, _ = FSDensityMapUtil.getFieldDataAtWorldPosition(x, 0, z)

    return not isOnField and materials[material_id]
end

-- Fields are the one thing that must never get touched, full stop - not
-- just at placement time (seed/spread already checked this) but for
-- anything that acts on ground that's already meadow, since a real
-- farmed field reads as "meadow" exactly the same as anything IW planted.
function ImmersiveWeathering:isOnField(x, z)
    local isOnField, _, _ = FSDensityMapUtil.getFieldDataAtWorldPosition(x, 0, z)
    return isOnField
end

function ImmersiveWeathering:randomCoordinate()
    local terrainSize = g_currentMission.terrainSize
    local halfSize = terrainSize * 0.5

    local x = -halfSize + math.random() * terrainSize
    local z = -halfSize + math.random() * terrainSize

    return x, z
end

function ImmersiveWeathering:runWeatheringSweep()
    debugPrint("----------------------------------------------------------------------")
    debugPrint("Immersive Weathering (FS25): STARTING weathering sweep...")

    if g_currentMission == nil then
        debugPrint("Immersive Weathering ERROR: g_currentMission is nil.")
        return
    end

    local sampleCount = 1000
    local stats = {}
    local startTime = getTimeSec()

    for i = 1, sampleCount do
        if i % 100 == 0 then
            debugPrintf( "Weathering sweep done %d%%", i / sampleCount * 100 )
        end

        local x, z = self:randomCoordinate()
        self:applyFoliageTransitions(x, z, stats)
    end

    local elapsedMs = (getTimeSec() - startTime) * 1000

    debugPrintf(
            "Immersive Weathering (FS25): FINISHED %d samples, seeded=%d spread=%d weeded=%d fruited=%d, %.3f ms",
            sampleCount,
            stats.seeded or 0,
            stats.spread or 0,
            stats.weeded or 0,
            stats.fruited or 0,
            elapsedMs
        )
    debugPrint("----------------------------------------------------------------------")
end

function ImmersiveWeathering:dumpFoliageAtWorldPosition(x, z)
    local data = self:loadFoliageDebugData()

    if data == nil then
        return
    end

    self:resolveFoliagePlaneIds(data)

    debugPrintf(
        "[ImmersiveWeathering] Foliage at x=%.3f z=%.3f",
        x,
        z
    )

    local found = false

    for layerIndex, layerData in ipairs(data.multilayers) do
        local planeId = layerData.terrainDataPlaneId
        local numChannels = layerData.numTypeIndexChannels

        if planeId ~= nil and numChannels ~= nil then
            local bits = getDensityAtWorldPos(
                planeId,
                x,
                0,
                z
            )

            local typeMask = 2 ^ numChannels - 1
            local typeIndex = bitAND(bits, typeMask)
            local value = bitShiftRight(bits, numChannels)

            if value > 0 or typeIndex > 0 then
                local foliageName =
                    layerData.types[typeIndex]
                    or "<unknown>"

                debugPrintf(
                    "  multilayer=%d plane=%s bits=%d type=%d name=%s value=%d",
                    layerIndex,
                    tostring(planeId),
                    bits,
                    typeIndex,
                    foliageName,
                    value
                )

                found = true
            end
        else
            debugPrintf(
                "  multilayer=%d unresolved plane; densityMapId=%s",
                layerIndex,
                tostring(layerData.densityMapId)
            )
        end
    end

    if not found then
        debugPrint("  no multilayer foliage found")
    end
end

function ImmersiveWeathering:loadFoliageDebugData()
    if self.foliageDebugData ~= nil then
        return self.foliageDebugData
    end

    local filename = self.mapI3dFilename

    if filename == nil then
        debugPrint("[ImmersiveWeathering] No map I3D filename captured")
        return nil
    end

    local xmlFile = XMLFile.load(
        "ImmersiveWeatheringMapI3D",
        filename
    )

    if xmlFile == nil then
        debugPrintf(
            "[ImmersiveWeathering] Could not open map I3D: %s",
            tostring(filename)
        )
        return nil
    end

    local rootKey =
        "i3D.Scene.TerrainTransformGroup.Layers.FoliageSystem"

    local data = {
        multilayers = {}
    }

    local layerIndex = 0

    while true do
        local layerKey = string.format(
            "%s.FoliageMultiLayer(%d)",
            rootKey,
            layerIndex
        )

        if not xmlFile:hasProperty(layerKey) then
            break
        end

        local layerData = {
            densityMapId =
                xmlFile:getInt(layerKey .. "#densityMapId"),

            numTypeIndexChannels =
                xmlFile:getInt(
                    layerKey .. "#numTypeIndexChannels",
                    0
                ),

            types = {}
        }

        local typeIndex = 0

        while true do
            local typeKey = string.format(
                "%s.FoliageType(%d)",
                layerKey,
                typeIndex
            )

            if not xmlFile:hasProperty(typeKey) then
                break
            end

            -- Density-map type indices are effectively 1-based here.
            local decodedIndex = typeIndex + 1

            layerData.types[decodedIndex] =
                xmlFile:getString(
                    typeKey .. "#name",
                    "<unnamed>"
                )

            typeIndex = typeIndex + 1
        end

        data.multilayers[layerIndex + 1] = layerData
        layerIndex = layerIndex + 1
    end

    xmlFile:delete()

    self.foliageDebugData = data

    debugPrintf(
        "[ImmersiveWeathering] Loaded %d foliage multilayers",
        #data.multilayers
    )

    return data
end

function ImmersiveWeathering:resolveFoliagePlaneIds(data)
    if data == nil or data.planeIdsResolved then
        return
    end

    local foliageSystem = g_currentMission.foliageSystem
    local foliageByName = {}

    local function collect(foliages)
        for _, foliage in ipairs(foliages or {}) do
            if foliage.layerName ~= nil then
                foliageByName[foliage.layerName] = foliage
            end
        end
    end

    collect(foliageSystem.decoFoliages)
    collect(foliageSystem.paintableFoliages)

    for _, layerData in ipairs(data.multilayers) do
        for _, foliageName in pairs(layerData.types) do
            local foliage = foliageByName[foliageName]

            if foliage ~= nil
                    and foliage.terrainDataPlaneId ~= nil then
                layerData.terrainDataPlaneId =
                    foliage.terrainDataPlaneId

                break
            end
        end
    end

    data.planeIdsResolved = true
end

function ImmersiveWeathering:scanFoliageArea(
    centerX,
    centerZ,
    radius,
    step
)
    radius = radius or 10
    step = step or 0.5

    local data = self:loadFoliageDebugData()

    if data == nil then
        return
    end

    self:resolveFoliagePlaneIds(data)

    local counts = {}
    local unresolvedLayers = {}
    local sampleCount = 0
    local foliageSampleCount = 0

    for layerIndex, layerData in ipairs(data.multilayers) do
        local planeId = layerData.terrainDataPlaneId
        local numTypeChannels =
            layerData.numTypeIndexChannels

        if planeId == nil then
            table.insert(
                unresolvedLayers,
                {
                    layerIndex = layerIndex,
                    densityMapId = layerData.densityMapId
                }
            )
        elseif numTypeChannels ~= nil then
            for x = centerX - radius, centerX + radius, step do
                for z = centerZ - radius, centerZ + radius, step do
                    sampleCount = sampleCount + 1

                    local bits = getDensityAtWorldPos(
                        planeId,
                        x,
                        0,
                        z
                    )

                    local typeMask =
                        2 ^ numTypeChannels - 1

                    local typeIndex =
                        bitAND(bits, typeMask)

                    local value =
                        bitShiftRight(
                            bits,
                            numTypeChannels
                        )

                    if typeIndex > 0 and value > 0 then
                        local foliageName =
                            layerData.types[typeIndex]
                            or string.format(
                                "<unknown type %d>",
                                typeIndex
                            )

                        local key = string.format(
                            "%d:%d",
                            layerIndex,
                            typeIndex
                        )

                        local entry = counts[key]

                        if entry == nil then
                            entry = {
                                layerIndex = layerIndex,
                                planeId = planeId,
                                typeIndex = typeIndex,
                                name = foliageName,
                                total = 0,
                                values = {}
                            }

                            counts[key] = entry
                        end

                        entry.total =
                            entry.total + 1

                        entry.values[value] =
                            (entry.values[value] or 0) + 1

                        foliageSampleCount =
                            foliageSampleCount + 1
                    end
                end
            end
        end
    end

    local sortedEntries = {}

    for _, entry in pairs(counts) do
        table.insert(sortedEntries, entry)
    end

    table.sort(
        sortedEntries,
        function(a, b)
            if a.total == b.total then
                if a.layerIndex == b.layerIndex then
                    return a.typeIndex < b.typeIndex
                end

                return a.layerIndex < b.layerIndex
            end

            return a.total > b.total
        end
    )

    debugPrintf(
        "[FoliageScan] center=(%.3f, %.3f) size=%.1fx%.1f step=%.2f",
        centerX,
        centerZ,
        radius * 2,
        radius * 2,
        step
    )

    debugPrintf(
        "[FoliageScan] samples=%d foliageHits=%d types=%d",
        sampleCount,
        foliageSampleCount,
        #sortedEntries
    )

    for _, entry in ipairs(sortedEntries) do
        debugPrintf(
            "[FoliageScan] %5d  layer=%d plane=%s type=%d name=%s",
            entry.total,
            entry.layerIndex,
            tostring(entry.planeId),
            entry.typeIndex,
            entry.name
        )

        local sortedValues = {}

        for value, count in pairs(entry.values) do
            table.insert(
                sortedValues,
                {
                    value = value,
                    count = count
                }
            )
        end

        table.sort(
            sortedValues,
            function(a, b)
                return a.value < b.value
            end
        )

        local valueParts = {}

        for _, valueEntry in ipairs(sortedValues) do
            table.insert(
                valueParts,
                string.format(
                    "%d=%d",
                    valueEntry.value,
                    valueEntry.count
                )
            )
        end

        debugPrintf(
            "[FoliageScan]        values: %s",
            table.concat(valueParts, ", ")
        )
    end

    for _, unresolved in ipairs(unresolvedLayers) do
        debugPrintf(
            "[FoliageScan] unresolved layer=%d densityMapId=%s",
            unresolved.layerIndex,
            tostring(unresolved.densityMapId)
        )
    end

    if #sortedEntries == 0 then
        debugPrint(
            "[FoliageScan] no foliage found in scanned area"
        )
    end
end

-- ============================================================
-- Tyre foliage destruction
-- ============================================================

local TYRE_CLEAR_DISTANCE = 0.35
local TYRE_CLEAR_CHANCE = 0.35

function ImmersiveWeathering:clearWheelFoliage(wheelDestruction)
    local wheel = wheelDestruction.wheel

    if wheel.physics.contact ~= WheelContactType.GROUND then
        return
    end

    for _, destructionNode in ipairs(wheelDestruction.destructionNodes) do
        local repr = wheel.repr
        local width = destructionNode.width * 0.5
        local length = math.min(0.5, destructionNode.width * 0.5)

        local xShift, yShift, zShift =
            localToLocal(
                destructionNode.node,
                repr,
                0,
                0,
                0
            )

        local x0, _, z0 =
            localToWorld(
                repr,
                xShift + width,
                yShift,
                zShift - length
            )

        local x1, _, z1 =
            localToWorld(
                repr,
                xShift - width,
                yShift,
                zShift - length
            )

        local x2, _, z2 =
            localToWorld(
                repr,
                xShift + width,
                yShift,
                zShift + length
            )

        -- Centre of the parallelogram.
        local centerX = (x1 + x2) * 0.5
        local centerZ = (z1 + z2) * 0.5

        if self:fieldIsMaterial(
            centerX,
            centerZ,
            WEATHERABLE_MATERIALS
        ) then
            local clearedName = self:getFoliageNameAt(centerX, centerZ)

            FSDensityMapUtil.clearDecoArea(
                x0,
                z0,
                x1,
                z1,
                x2,
                z2
            )

            if clearedName ~= nil then
                debugPrintf(
                    "[TyreClear] wiped %s at (%.2f %.2f)",
                    clearedName,
                    centerX,
                    centerZ
                )
            end
        end
    end
end

function ImmersiveWeathering:onWheelDestructionUpdate(
    wheelDestruction,
    dt,
    allowFoliageDestruction
)
    -- Density-map changes belong on the server.
    if g_server == nil then
        return
    end

    local vehicle = wheelDestruction.vehicle
    local wheel = wheelDestruction.wheel
    local isGrounded = wheel.physics.contact == WheelContactType.GROUND

    -- Log only on transitions (not every physics tick) - if ground contact
    -- is flickering true/false rapidly over a specific spot (e.g. a dense
    -- foliage mesh interfering with contact detection), this shows it
    -- directly instead of us guessing whether the vanilla wheel destruction
    -- module even sees that spot as ground at all.
    if isGrounded ~= wheelDestruction.immersiveWeatheringWasGrounded then
        wheelDestruction.immersiveWeatheringWasGrounded = isGrounded
        local x, _, z = getWorldTranslation(wheel.repr)
        debugPrintf("[TyreDebug] wheel contact -> %s at (%.2f %.2f)", tostring(isGrounded), x, z)
    end

    if vehicle.lastSpeedReal <= 0.0002 then
        wheelDestruction.immersiveWeatheringDistance = 0
        return
    end

    if not isGrounded then
        wheelDestruction.immersiveWeatheringDistance = 0
        return
    end

    local distance =
        wheelDestruction.immersiveWeatheringDistance or 0

    distance = distance + math.abs(vehicle.lastMovedDistance or 0)

    if distance < TYRE_CLEAR_DISTANCE then
        wheelDestruction.immersiveWeatheringDistance = distance
        return
    end

    wheelDestruction.immersiveWeatheringDistance =
        distance % TYRE_CLEAR_DISTANCE

    if math.random() <= TYRE_CLEAR_CHANCE then
        self:clearWheelFoliage(wheelDestruction)
    end
end

WheelDestruction.update =
    Utils.appendedFunction(
        WheelDestruction.update,
        function(wheelDestruction, dt, allowFoliageDestruction)
            ImmersiveWeathering:onWheelDestructionUpdate(
                wheelDestruction,
                dt,
                allowFoliageDestruction
            )
        end
    )
