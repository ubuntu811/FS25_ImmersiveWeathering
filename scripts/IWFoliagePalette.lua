-- Loads an optional per-map foliage palette (iw.xml, sibling to the
-- current map's own map.xml) - see the comment block at the top of
-- FS25_Estancia_Lapacho_orange's maps/iw.xml for the real, worked schema.
--
-- Deliberately schema-less XMLFile.load (not XMLFile.create/loadIfExists +
-- XMLSchema like IWConfig.lua) - this file is read-only, map-author-
-- supplied content, not something we ourselves create/save, so it matches
-- WailaFoliageInspector's I3D-parsing pattern (confirmed real all night)
-- rather than IWConfig's own persisted-settings pattern. Only getString/
-- getInt/hasProperty are used - getBool/getFloat/getValue+schema were
-- never confirmed real for a schema-less load, so boolean flags are read
-- as "true"/"false" strings instead of risking an unconfirmed method.
IWFoliagePalette = {}
local IWFoliagePalette_mt = Class(IWFoliagePalette)

-- debugPrint/debugPrintf in ImmersiveWeathering.lua are file-local, not
-- reachable from here despite load order (<extraSourceFiles> loads this
-- file before ImmersiveWeathering.lua anyway) - IWConfig.lua/
-- IWSettingsUI.lua don't log at all currently, this is the first separate
-- module that needs to, so it gets its own trivial copy of the same
-- pattern rather than a new logging abstraction.
local function debugPrint(message)
    print("[IWFoliagePalette] " .. tostring(message))
end

local function debugPrintf(formatString, ...)
    debugPrint(string.format(formatString, ...))
end

-- Falls back to this - today's exact existing behavior - when no iw.xml
-- exists next to the current map, so a map with zero IW-specific setup
-- keeps working unchanged.
local DEFAULT_ENTRY = {
    name = "grassShort",
    chance = 100,
    stageMin = 0,
    stageMax = 0,
    randomStage = false,
    clusters = false,
    mutateChance = 0,
    mutatesTo = {},
    seeder = true,
    seederLevel = 0,
}

function IWFoliagePalette.new()
    local self = setmetatable({}, IWFoliagePalette_mt)
    self.entries = { DEFAULT_ENTRY }
    self.entriesByName = { [DEFAULT_ENTRY.name] = DEFAULT_ENTRY }
    self:load()
    return self
end

function IWFoliagePalette:load()
    local mapXMLFilename = g_currentMission ~= nil
        and g_currentMission.missionInfo ~= nil
        and g_currentMission.missionInfo.mapXMLFilename
        or nil

    if mapXMLFilename == nil then
        debugPrint("mapXMLFilename unavailable, using default (grassShort only)")
        return
    end

    -- Utils.getDirectory - real, confirmed via TerraFarm's own
    -- ModUtils.getMapDirectoryFilename and FS25_allTheFoliage's main.lua,
    -- both of which resolve a file next to map.xml the same way.
    local iwXMLFilename = Utils.getDirectory(mapXMLFilename) .. "iw.xml"
    local xmlFile = XMLFile.load("IWFoliagePalette", iwXMLFilename)

    if xmlFile == nil then
        debugPrintf("no iw.xml at %s - using default (grassShort only)", iwXMLFilename)
        return
    end

    local entries = {}
    local entriesByName = {}
    local index = 0

    while true do
        local key = string.format("iwConfig.foliageMapping.entry(%d)", index)

        if not xmlFile:hasProperty(key) then
            break
        end

        local name = xmlFile:getString(key .. "#name")

        if name ~= nil then
            local entry = {
                name = name,
                chance = xmlFile:getInt(key .. "#chance", 0),
                stageMin = xmlFile:getInt(key .. "#stageMin", 0),
                stageMax = xmlFile:getInt(key .. "#stageMax", 0),
                randomStage = xmlFile:getString(key .. "#randomStage", "false") == "true",
                clusters = xmlFile:getString(key .. "#clusters", "false") == "true",
                mutateChance = xmlFile:getInt(key .. "#mutateChance", 0),
                seeder = xmlFile:getString(key .. "#seeder", "false") == "true",
                seederLevel = xmlFile:getInt(key .. "#seederLevel", 0),
                mutatesTo = {},
            }

            local mutateIndex = 0
            while true do
                local mutateKey = string.format("%s.mutatesTo(%d)", key, mutateIndex)

                if not xmlFile:hasProperty(mutateKey) then
                    break
                end

                local targetName = xmlFile:getString(mutateKey .. "#name")

                if targetName ~= nil then
                    table.insert(entry.mutatesTo, targetName)
                end

                mutateIndex = mutateIndex + 1
            end

            table.insert(entries, entry)
            entriesByName[entry.name] = entry
        end

        index = index + 1
    end

    xmlFile:delete()

    if #entries > 0 then
        self.entries = entries
        self.entriesByName = entriesByName
        debugPrintf("loaded %d entries from %s", #entries, iwXMLFilename)
    end
end

-- Public: find the palette entry matching a raw foliage name, as read
-- back by ImmersiveWeathering:getFoliageNameAt - nil if nothing is there
-- yet, or if what's there doesn't correspond to any entry this palette
-- knows about (e.g. ambient map content outside the configured palette).
function IWFoliagePalette:findEntry(name)
    if name == nil then
        return nil
    end

    return self.entriesByName[name]
end

-- Public: weighted pick among all entries for fresh placement on bare
-- ground. Weights don't need to sum to 100 - the remainder falls back to
-- grassShort (the historical universal default), not "nothing happens" -
-- the existing outer gates (wither chance, sweep sample count) already
-- control how often a fresh-placement roll happens at all.
function IWFoliagePalette:pickFreshEntry()
    local roll = math.random() * 100
    local cumulative = 0

    for _, entry in ipairs(self.entries) do
        cumulative = cumulative + entry.chance

        if roll <= cumulative then
            return entry
        end
    end

    return self.entriesByName["grassShort"] or DEFAULT_ENTRY
end

-- Public: the stage a fresh placement of this entry should start at.
function IWFoliagePalette:pickInitialStage(entry)
    if entry.randomStage then
        return math.random(entry.stageMin, entry.stageMax)
    end

    return entry.stageMin
end

-- Public: the stage an existing patch should move to on a repeat hit.
-- randomStage entries (unrelated species/models, no meaningful order)
-- re-roll fresh every time - no memory, no progression. Ordered entries
-- (a real growth-stage progression) bump toward stageMax by one.
function IWFoliagePalette:growStage(entry, currentStage)
    if entry.randomStage then
        return math.random(entry.stageMin, entry.stageMax)
    end

    local nextStage = (currentStage or entry.stageMin) + 1

    if nextStage > entry.stageMax then
        nextStage = entry.stageMax
    end

    return nextStage
end

-- Public: independent succession roll - nil if nothing mutates (no
-- mutateChance/mutatesTo configured, or the roll simply missed),
-- otherwise the target entry to switch to.
function IWFoliagePalette:rollMutation(entry)
    if entry.mutateChance == nil or entry.mutateChance <= 0 or #entry.mutatesTo == 0 then
        return nil
    end

    if math.random() * 100 > entry.mutateChance then
        return nil
    end

    local targetName = entry.mutatesTo[math.random(#entry.mutatesTo)]

    return self.entriesByName[targetName]
end

-- Public: the real writable mapping name for applyDecoFoliage - base
-- layerName + "_s" + stage, matching the map.xml naming convention every
-- entry in this palette is expected to declare (e.g. decoBush -> decoBush_s7).
function IWFoliagePalette:getWriteName(entry, stage)
    return entry.name .. "_s" .. stage
end

-- Public: the entry a real seeder vehicle should sow, or the default
-- grassShort fallback if the loaded palette flagged nothing.
function IWFoliagePalette:getSeederEntry()
    for _, entry in ipairs(self.entries) do
        if entry.seeder then
            return entry
        end
    end

    return self.entriesByName["grassShort"] or DEFAULT_ENTRY
end
