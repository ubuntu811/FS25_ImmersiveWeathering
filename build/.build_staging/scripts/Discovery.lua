--[[
    Discovery.lua

    Two separate things left to verify on your install before this is fully
    trustworthy:

    1) Vehicle/implement classification (WorkAreaType names) -- still a guess
       in VehicleClassifier.lua, unlike the overlay side which is now
       confirmed via MinimapPlus's own source.
    2) That MinimapPlus is actually active and its globals are visible to
       this mod (MMapPlusMapIDs, mMapPlusSelectedOverlayType).

    Flip SmartMinimapAuto.DISCOVERY_MODE = true in SmartMinimapAuto.lua, load
    a save with both mods active, enter each vehicle type once, and read
    log.txt for the dumps below.
]]

Discovery = {}

function Discovery.checkMinimapPlusPresence()
    log("===== SmartMinimapAuto Discovery: MinimapPlus presence =====")
    log("  MMapPlusMapIDs global present: " .. tostring(MMapPlusMapIDs ~= nil))
    if g_currentMission ~= nil and g_currentMission.mapOverlayGenerator ~= nil then
        local gen = g_currentMission.mapOverlayGenerator
        log("  mapOverlayGenerator.mMapPlusSelectedOverlayType present: " .. tostring(gen.mMapPlusSelectedOverlayType ~= nil))
        log("  mapOverlayGenerator.generateSelectedOverlay present: " .. tostring(gen.generateSelectedOverlay ~= nil))
        log("  mapOverlayGenerator.generateSoilStateOverlay present: " .. tostring(gen.generateSoilStateOverlay ~= nil))
        log("  mapOverlayGenerator.generateGrowthStateOverlay present: " .. tostring(gen.generateGrowthStateOverlay ~= nil))
    else
        log("  g_currentMission.mapOverlayGenerator not available yet")
    end

    if MapOverlayGenerator ~= nil and MapOverlayGenerator.SOIL_STATE_INDEX ~= nil then
        log("  -- SOIL_STATE_INDEX --")
        for k, v in pairs(MapOverlayGenerator.SOIL_STATE_INDEX) do
            log("    " .. tostring(k) .. " = " .. tostring(v))
        end
    end
    if MapOverlayGenerator ~= nil and MapOverlayGenerator.GROWTH_STATE_INDEX ~= nil then
        log("  -- GROWTH_STATE_INDEX --")
        for k, v in pairs(MapOverlayGenerator.GROWTH_STATE_INDEX) do
            log("    " .. tostring(k) .. " = " .. tostring(v))
        end
    end
    log("===== end presence check =====")
end

function Discovery.dumpVehicle(vehicle)
    if vehicle == nil then
        return
    end

    log("===== SmartMinimapAuto Discovery: " .. tostring(vehicle.typeName) .. " =====")

    log("-- specializations (spec_*) --")
    for key, _ in pairs(vehicle) do
        if type(key) == "string" and key:sub(1, 5) == "spec_" then
            log("  " .. key)
        end
    end

    if vehicle.spec_workArea ~= nil and vehicle.spec_workArea.workAreas ~= nil then
        log("-- work areas (spec_workArea.workAreas[i].type) --")
        for i, workArea in ipairs(vehicle.spec_workArea.workAreas) do
            log(string.format("  [%d] type=%s", i, tostring(workArea.type)))
        end
    end

    if vehicle.getAttachedImplements ~= nil then
        for _, implement in pairs(vehicle:getAttachedImplements()) do
            if implement.object ~= nil then
                Discovery.dumpVehicle(implement.object)
            end
        end
    end

    if vehicle.spec_cutter ~= nil then
        log("-- spec_cutter fields --")
        for k, v in pairs(vehicle.spec_cutter) do
            if type(v) ~= "table" and type(v) ~= "function" then
                log("  " .. tostring(k) .. " = " .. tostring(v))
            end
        end
    end

    log("===== end dump =====")
end

function Discovery.dumpWorkAreaTypeEnum()
    if WorkAreaType == nil then
        log("SmartMinimapAuto Discovery: global WorkAreaType enum not found under that name.")
        return
    end
    log("-- WorkAreaType enum --")
    for name, value in pairs(WorkAreaType) do
        log(string.format("  %s = %s", tostring(name), tostring(value)))
    end
end
