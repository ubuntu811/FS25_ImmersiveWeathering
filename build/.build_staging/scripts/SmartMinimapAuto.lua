--[[
    SmartMinimapAuto.lua -- entry point

    Drives FS25_minimapPlus's existing overlay system instead of rebuilding
    field-state detection. On entering a job-relevant vehicle, this sets
    g_currentMission.mapOverlayGenerator.mMapPlusSelectedOverlayType to the
    matching MinimapPlus overlay ID and forces a regenerate -- exactly what
    Alt+9/Ctrl+9 does manually, just picked automatically instead of cycled.

    Requires FS25_minimapPlus active. Without it, the base game's
    MapOverlayGenerator still exists and still has generateSoilStateOverlay/
    generateGrowthStateOverlay, but nothing renders those overlays onto the
    small minimap widget -- that rendering hook is MinimapPlus's own
    drawFields patch. So this mod checks for MinimapPlus and no-ops (with a
    one-time log message) if it isn't found, rather than silently doing
    nothing.

    KNOWN GAP: harvest jobs (grain/root headers) fall back to MinimapPlus's
    existing CROPS overlay (all fruit types, color-coded), not filtered down
    to just the header's supported fruits (e.g. only beets+carrots). True
    filtering needs read/write access to MinimapPlus's internal overlay
    handle, which is a `local MMapPlus` table in MMapPlus.lua -- invisible
    to other mods as written. If you want real fruit filtering, the fix is a
    one-line change to MinimapPlus's own source: change
        local MMapPlus = {}
    to
        MMapPlus = {}
    in MMapPlus.lua, which exposes it as a global your add-on can drive
    directly (call generateGrowthStateOverlay/generateFruitTypeOverlay with
    your own fruit-type set, then set MMapPlus.overlay = handle yourself).
    Left out of this v1 to avoid quietly patching someone else's mod file
    for you without you deciding that's what you want.
]]

SmartMinimapAuto = {}
SmartMinimapAuto.DISCOVERY_MODE = true
SmartMinimapAuto.hasWarnedNoMinimapPlus = false

local SmartMinimapAuto_mt = Class(SmartMinimapAuto)

-- job category -> MinimapPlus overlay id (only for categories with a direct,
-- unfiltered match -- see KNOWN GAP above for harvest jobs)
local JOB_TO_OVERLAY_ID = {
    -- filled in on first use once MMapPlusMapIDs is confirmed present,
    -- see resolveJobOverlayMap()
}

local function resolveJobOverlayMap()
    if MMapPlusMapIDs == nil then
        return nil
    end
    return {
        ROLLING       = MMapPlusMapIDs.NEEDS_ROLLING,
        TILLAGE       = MMapPlusMapIDs.NEEDS_PLOWING,
        WEEDING       = MMapPlusMapIDs.WEEDS,
        HARVEST_GRAIN = MMapPlusMapIDs.CROPS, -- unfiltered, see KNOWN GAP
        HARVEST_ROOT  = MMapPlusMapIDs.CROPS, -- unfiltered, see KNOWN GAP
        -- SOWING intentionally unmapped: no built-in "ready to sow" overlay
    }
end

function SmartMinimapAuto.new()
    local self = setmetatable({}, SmartMinimapAuto_mt)
    self.previousOverlayId = nil
    return self
end

function SmartMinimapAuto:isMinimapPlusActive()
    local gen = g_currentMission ~= nil and g_currentMission.mapOverlayGenerator
    return MMapPlusMapIDs ~= nil and gen ~= nil and gen.mMapPlusSelectedOverlayType ~= nil
end

function SmartMinimapAuto:onVehicleEntered(vehicle, isControlling)
    if not isControlling or vehicle == nil then
        return
    end

    if SmartMinimapAuto.DISCOVERY_MODE then
        Discovery.checkMinimapPlusPresence()
        Discovery.dumpWorkAreaTypeEnum()
        Discovery.dumpVehicle(vehicle)
        return
    end

    if not self:isMinimapPlusActive() then
        if not SmartMinimapAuto.hasWarnedNoMinimapPlus then
            log("SmartMinimapAuto: FS25_minimapPlus not detected/active -- nothing to drive, skipping.")
            SmartMinimapAuto.hasWarnedNoMinimapPlus = true
        end
        return
    end

    local jobCategory = VehicleClassifier.classify(vehicle)
    if jobCategory == nil then
        return -- not a job-relevant vehicle, leave the map alone
    end

    local jobOverlayMap = resolveJobOverlayMap()
    local overlayId = jobOverlayMap[jobCategory]
    if overlayId == nil then
        return -- e.g. SOWING, no matching overlay yet
    end

    local gen = g_currentMission.mapOverlayGenerator
    self.previousOverlayId = gen.mMapPlusSelectedOverlayType
    gen.mMapPlusSelectedOverlayType = overlayId
    gen:generateSelectedOverlay(true)
end

function SmartMinimapAuto:onVehicleLeft(vehicle)
    if not self:isMinimapPlusActive() then
        return
    end
    local gen = g_currentMission.mapOverlayGenerator
    gen.mMapPlusSelectedOverlayType = MMapPlusMapIDs.FIELDS
    gen:generateSelectedOverlay(true)
end

-- ---- wiring into the game ----

g_smartMinimapAuto = SmartMinimapAuto.new()

g_messageCenter:subscribe(MessageType.VEHICLE_ENTERED, function(vehicle, isControlling)
    g_smartMinimapAuto:onVehicleEntered(vehicle, isControlling)
end, g_smartMinimapAuto)

g_messageCenter:subscribe(MessageType.VEHICLE_LEFT, function(vehicle)
    g_smartMinimapAuto:onVehicleLeft(vehicle)
end, g_smartMinimapAuto)
