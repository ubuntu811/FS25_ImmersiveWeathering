-- Persists the set of specific world coordinates IW is actively tracking
-- for guaranteed (not randomly-sampled) processing every sweep - see
-- ImmersiveWeathering:processTrackedPatches and IWFoliagePalette's own
-- trackPatch/trackedSpreadChance/trackedRejuvenateChance fields for why.
-- Real motivation, not a hypothetical: even a 10000-sample nightly sweep
-- has a low chance of ever landing near any one small patch, no matter
-- how reliably it's detected once it's found (see
-- ImmersiveWeathering:getFoliageNameNearby) - this file is what turns
-- "might get checked eventually" into "checked every single sweep" for
-- the handful of patches actually worth tracking.
--
-- Per-savegame world state, not a global mod setting - deliberately NOT
-- IWConfig.lua's pattern (getUserProfileAppPath()/modSettings, one
-- global file shared across every save) - these coordinates only mean
-- anything for the specific save they were found in. Same
-- savegameDirectory + schema-less XMLFile.create/load pattern
-- FS25_Hammer's own sandboxtools.xml uses (a proven, working pattern for
-- exactly this kind of per-save dynamic-length coordinate list) -
-- deliberately named iw-save.xml, not iw.xml/iw-map.xml, so the
-- per-save runtime file and the map-author-supplied palette config
-- (renamed to iw-map.xml specifically to avoid this collision) never
-- read as the same thing in a log or a file listing.
IWTrackedPatches = {}
local IWTrackedPatches_mt = Class(IWTrackedPatches)

local SAVEGAME_FILENAME = "iw-save.xml"

-- Hard ceiling on how many patches get tracked at once - spread
-- registers a NEW tracked instance each time it fires, so without a cap
-- even a low trackedSpreadChance compounds without bound over enough
-- sweeps/days. Far more than any map realistically needs actively
-- tracked at once; a full list just means new discoveries stop being
-- added until something ages out via processTrackedPatches removing a
-- gone/mutated-away entry.
local MAX_TRACKED_PATCHES = 300

-- Dedupe radius for registerIfNeeded - deliberately wider than
-- ImmersiveWeathering.lua's own FOLIAGE_DETECT_RADIUS (0.4, sized for
-- "did I miss reading a stamp that's right here"); this is "is this
-- close enough to already be the same patch," a coarser question.
local DEDUPE_RADIUS = 1.5

function IWTrackedPatches.new()
    local self = setmetatable({}, IWTrackedPatches_mt)
    self.patches = {}
    return self
end

local function getSavegamePath()
    if g_currentMission == nil
        or g_currentMission.missionInfo == nil
        or g_currentMission.missionInfo.savegameDirectory == nil then
        return nil
    end

    return g_currentMission.missionInfo.savegameDirectory .. "/" .. SAVEGAME_FILENAME
end

-- Public: load the tracked list from this save's iw-save.xml, replacing
-- whatever's currently in memory. Deferred to CURRENT_MISSION_START by
-- the caller (see ImmersiveWeathering.lua's BaseMission.loadMap hook) -
-- mirrors FS25_Hammer's own real, confirmed fix for a load-time hang
-- (a physics/density-map query fired too early inside loadMap itself),
-- even though this particular load is just reading a coordinate list
-- with no physics query of its own - consistency with a proven-safe
-- pattern costs nothing here.
function IWTrackedPatches:load()
    self.patches = {}

    local path = getSavegamePath()
    if path == nil then
        return
    end

    local xmlFile = XMLFile.load("IWTrackedPatches", path)
    if xmlFile == nil then
        print(string.format("[IWTrackedPatches] no saved state found (%s)", SAVEGAME_FILENAME))
        return
    end

    local index = 0
    while true do
        local key = string.format("iwSave.trackedPatch(%d)", index)

        if not xmlFile:hasProperty(key) then
            break
        end

        local name = xmlFile:getString(key .. "#name")
        local x = xmlFile:getFloat(key .. "#x")
        local y = xmlFile:getFloat(key .. "#y")
        local z = xmlFile:getFloat(key .. "#z")

        if name ~= nil and x ~= nil and y ~= nil and z ~= nil then
            table.insert(self.patches, { name = name, x = x, y = y, z = z })
        end

        index = index + 1
    end

    xmlFile:delete()

    print(string.format("[IWTrackedPatches] loaded %d tracked patch(es) from %s", #self.patches, path))
end

-- Public: write the current tracked list to this save's iw-save.xml.
-- Called on every registration/removal (a rare, deliberate change, not
-- per-frame/per-sweep) AND should be re-triggered on a real Save Game
-- pass too - see ImmersiveWeathering.lua's FSCareerMissionInfo hook,
-- same real, confirmed-necessary pattern FS25_Hammer's saveState uses
-- (toggle-time-only writes alone didn't survive an actual Save Game).
function IWTrackedPatches:save()
    local path = getSavegamePath()
    if path == nil then
        return
    end

    local xmlFile = XMLFile.create("IWTrackedPatches", path, "iwSave")
    if xmlFile == nil then
        return
    end

    for index, patch in ipairs(self.patches) do
        local key = string.format("iwSave.trackedPatch(%d)", index - 1)
        xmlFile:setString(key .. "#name", patch.name)
        xmlFile:setFloat(key .. "#x", patch.x)
        xmlFile:setFloat(key .. "#y", patch.y)
        xmlFile:setFloat(key .. "#z", patch.z)
    end

    xmlFile:save()
    xmlFile:delete()
end

-- Public: register (name, x, y, z) as tracked, unless an existing
-- tracked entry of the SAME name already sits within DEDUPE_RADIUS -
-- called both when the sweep discovers an existing trackPatch instance
-- it doesn't know about yet (map-author-placed/"smuggled" content) and
-- when IW itself freshly places or spreads one. Returns true if a new
-- entry was actually added (false on dedupe-skip or cap-skip), in case
-- a caller ever wants to know/log that.
function IWTrackedPatches:registerIfNeeded(name, x, y, z)
    for _, patch in ipairs(self.patches) do
        if patch.name == name then
            local dx, dy, dz = patch.x - x, patch.y - y, patch.z - z

            if dx * dx + dy * dy + dz * dz <= DEDUPE_RADIUS * DEDUPE_RADIUS then
                return false
            end
        end
    end

    if #self.patches >= MAX_TRACKED_PATCHES then
        return false
    end

    table.insert(self.patches, { name = name, x = x, y = y, z = z })
    self:save()

    return true
end

-- Public: all currently tracked patches, for processTrackedPatches to
-- iterate. Returned table is the live internal list, not a copy -
-- callers must not mutate it directly, use removeByIndices instead.
function IWTrackedPatches:getAll()
    return self.patches
end

-- Public: remove patches at the given 1-based indices (into whatever
-- getAll() returned during the same pass) and persist the result once.
-- Indices are meant to be collected by the caller across one full
-- processTrackedPatches pass and removed together afterward, not one at
-- a time mid-iteration - removing from a Lua array while ipairs is
-- iterating it is unsafe. Sorted descending so earlier removals don't
-- shift the indices of ones still pending.
function IWTrackedPatches:removeByIndices(indices)
    if indices == nil or #indices == 0 then
        return
    end

    table.sort(indices, function(a, b) return a > b end)

    for _, index in ipairs(indices) do
        table.remove(self.patches, index)
    end

    self:save()
end
