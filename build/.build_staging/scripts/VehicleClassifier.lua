--[[
    VehicleClassifier.lua

    Turns "what did the player just enter" into a job category:
        "ROLLING", "TILLAGE", "WEEDING", "SOWING", "HARVEST_GRAIN", "HARVEST_ROOT"

    Deliberately built around WorkAreaType rather than guessing spec_* names,
    since work area type is what the engine itself uses to decide ground
    effects -- it's the most stable hook point across versions. The exact
    enum member names (left as TODO below) must be confirmed with
    Discovery.dumpWorkAreaTypeEnum() on your install/patch.

    For harvest headers, fruit compatibility is read from spec_cutter (or
    the harvester itself for non-modular root-crop machines) rather than
    hardcoded per-vehicle, so any modded header/harvester works automatically.
]]

VehicleClassifier = {}

-- TODO: confirm these against your log.txt dump (Discovery.dumpWorkAreaTypeEnum())
-- placeholder names based on typical FS22/FS25 conventions -- verify before relying on them
local WORKAREA_TO_JOB = {
    ROLLER          = "ROLLING",
    CULTIVATOR      = "TILLAGE",
    WEEDER          = "WEEDING",
    SOWINGMACHINE   = "SOWING",
    PLOW            = "TILLAGE",
    CUTTER          = "HARVEST", -- refined below using fruit type
}

-- fruit type names (indices) that count as "root crop" for our purposes
local ROOT_CROP_FRUITS = {
    SUGARBEET = true,
    FODDERBEET = true,
    CARROT = true,
    POTATO = true,
}

local function getWorkAreaJob(object)
    if object.spec_workArea == nil or object.spec_workArea.workAreas == nil then
        return nil
    end

    for _, workArea in ipairs(object.spec_workArea.workAreas) do
        -- workArea.type is numeric at runtime; we need the *name* to look it up.
        -- WorkAreaType is normally exposed both ways (WorkAreaType.ROLLER == 7, etc,
        -- and WorkAreaType.NAME_BY_VALUE or similar reverse table on some versions).
        local typeName = nil
        if WorkAreaType ~= nil then
            for name, value in pairs(WorkAreaType) do
                if value == workArea.type then
                    typeName = name
                    break
                end
            end
        end

        if typeName ~= nil and WORKAREA_TO_JOB[typeName] ~= nil then
            return WORKAREA_TO_JOB[typeName], typeName
        end
    end

    return nil
end

-- returns a set of fruitTypeIndex this cutter/harvester can process, e.g. {SUGARBEET=true, CARROT=true}
local function getSupportedFruits(object)
    local fruits = {}

    -- modular grain/root header
    if object.spec_cutter ~= nil then
        -- TODO: confirm real field name via Discovery dump of spec_cutter --
        -- candidates seen across versions: .fruitTypes, .validFruitTypes, .cutterFruitTypes
        local list = object.spec_cutter.fruitTypes or object.spec_cutter.validFruitTypes
        if list ~= nil then
            for _, fruitTypeIndex in pairs(list) do
                local fruitName = g_fruitTypeManager and g_fruitTypeManager:getFruitTypeNameByIndex(fruitTypeIndex)
                if fruitName ~= nil then
                    fruits[fruitName] = true
                end
            end
        end
    end

    -- whole-machine root crop harvester (no separate header)
    if object.spec_combine ~= nil and object.spec_combine.fruitType ~= nil then
        local fruitName = g_fruitTypeManager and g_fruitTypeManager:getFruitTypeNameByIndex(object.spec_combine.fruitType)
        if fruitName ~= nil then
            fruits[fruitName] = true
        end
    end

    return fruits
end

local function isRootCropSet(fruits)
    for name, _ in pairs(fruits) do
        if ROOT_CROP_FRUITS[name] then
            return true
        end
    end
    return false
end

--- Classifies the vehicle the player just entered, walking attached implements too.
-- @return jobCategory (string) one of ROLLING/TILLAGE/WEEDING/SOWING/HARVEST_GRAIN/HARVEST_ROOT, or nil
-- @return fruitFilter (table|nil) set of fruit names relevant for harvest jobs
function VehicleClassifier.classify(vehicle)
    if vehicle == nil then
        return nil
    end

    local objectsToCheck = { vehicle }
    if vehicle.getAttachedImplements ~= nil then
        for _, implement in pairs(vehicle:getAttachedImplements()) do
            if implement.object ~= nil then
                table.insert(objectsToCheck, implement.object)
            end
        end
    end

    for _, object in ipairs(objectsToCheck) do
        local job, workAreaTypeName = getWorkAreaJob(object)

        if job == "HARVEST" then
            local fruits = getSupportedFruits(object)
            if next(fruits) ~= nil then
                if isRootCropSet(fruits) then
                    return "HARVEST_ROOT", fruits
                else
                    return "HARVEST_GRAIN", fruits
                end
            end
        elseif job ~= nil then
            return job, nil
        end
    end

    return nil
end
