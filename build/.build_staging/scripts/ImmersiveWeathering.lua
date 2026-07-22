--[[
    Immersive Weathering (FS25)

    Current MVP:
      * run a weathering sweep once per in-game day
      * sample random map coordinates
      * place grassShort on gravel
      * provide debug keys for terrain/foliage inspection and manual testing
]]

ImmersiveWeathering = {}

local function debugPrint(message)
    print("[ImmersiveWeathering] " .. tostring(message))
end

local function debugPrintf(formatString, ...)
    debugPrint(string.format(formatString, ...))
end

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

    self:debugDumpGroundTypeMappings()
    self:debugDumpGroundTypeManager()
    self:debugDumpFoliageLayers()
end

function ImmersiveWeathering:onDebug2KeyPressed(
    actionName,
    inputValue,
    callbackState,
    isAnalog
)
    debugPrint("Immersive Weathering (FS25): Debug 2 key pressed")
    self:whatAmILookingAt()
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

    local halfSize = 0.5

    foliageSystem:applyDecoFoliage(
        decoName,
        x - halfSize,
        z - halfSize,
        x + halfSize,
        z - halfSize,
        x - halfSize,
        z + halfSize
    )

    debugPrint(string.format("%s to (%.2f %.2f)", decoName, x, z))
    return true
end

function ImmersiveWeathering:isGravel(x, z)
    local _, _, _, _, materialId =
        getTerrainAttributesAtWorldPos(
            g_terrainNode,
            x,
            0,
            z,
            true,
            true,
            true,
            true,
            false
        )

    return materialId == 6
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
    local gravelHits = 0
    local startTime = getTimeSec()

    for i = 1, sampleCount do
        if i % 100 == 0 then
            debugPrintf(
                    "Weathering sweep done %d%%",
                    i / sampleCount * 100
                )
        end

        local x, z = self:randomCoordinate()

        if self:isGravel(x, z) then
            gravelHits = gravelHits + 1
            self:placeFoliage(x, z)
        end
    end

    local elapsedMs = (getTimeSec() - startTime) * 1000

    debugPrintf(
            "Immersive Weathering (FS25): FINISHED %d samples, %d gravel hits, %.3f ms",
            sampleCount,
            gravelHits,
            elapsedMs
        )
    debugPrint("----------------------------------------------------------------------")
end
