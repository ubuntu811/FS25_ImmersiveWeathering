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

-- The universal last-resort fallback - grassShort is the one pre-existing,
-- singular <mapping> alias (grassShort -> decoFoliage@9) confirmed to work
-- on every map tested tonight with zero exceptions. literalName=true -
-- it's not part of the "_s<stage>" numbered convention every other entry
-- follows, getWriteName must use the bare name here, not "grassShort_s0"
-- (confirmed real bug: "foliage layer 'grassShort_s0' is not defined").
--
-- No mutateChance/mutatesTo here - a mutation escape hatch on THIS entry
-- would be dead code. grassShort never reads back as literally
-- "grassShort" (it reads back as "decoFoliage", the real underlying type
-- name, the same write/read split confirmed all night) - so findEntry is
-- only ever called with "decoFoliage", never "grassShort" itself. This
-- entry is only ever used as *what to write* (pickFreshEntry's remainder,
-- getSeederEntry's fallback), never looked up again afterward. The real
-- "stuck" entry to fix is decoFoliage's own entry in iw.xml, not this one.
local GRASS_SHORT_FALLBACK_ENTRY = {
    name = "grassShort",
    literalName = true,
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

-- No auto-detected "smarter" fallback (a meadow-if-available variant was
-- tried and reverted) - if iw.xml is present, everything that happens on
-- the map should come from what it declares, no guessing layered on top
-- by our own code, even for the remainder slot. grassShort is the one
-- fallback used everywhere, uniformly, whether there's no iw.xml at all
-- or a loaded palette's weights just don't sum to 100%.
function IWFoliagePalette.new()
    local self = setmetatable({}, IWFoliagePalette_mt)
    self.fallbackEntry = GRASS_SHORT_FALLBACK_ENTRY
    self.entries = { self.fallbackEntry }
    self.entriesByName = { [self.fallbackEntry.name] = self.fallbackEntry }
    -- Specific per-state overrides (<entry name="X" state="N">) - kept
    -- entirely separate from entries/entriesByName. Never participate in
    -- pickFreshEntry's weighted pool or getSeederEntry - they only matter
    -- for "something already sitting at this exact state", not for
    -- picking what to place fresh. A general entry landing on this same
    -- state via its own normal random/growth roll is unaffected and
    -- unchanged - this only adds a second, more specific lookup findEntry
    -- checks first.
    self.specificEntriesByNameAndState = {}
    self:load()
    return self
end

function IWFoliagePalette:load()
    local mapXMLFilename = g_currentMission ~= nil
        and g_currentMission.missionInfo ~= nil
        and g_currentMission.missionInfo.mapXMLFilename
        or nil

    if mapXMLFilename == nil then
        debugPrintf("mapXMLFilename unavailable, using default (%s only)", self.fallbackEntry.name)
        return
    end

    -- Utils.getDirectory - real, confirmed via TerraFarm's own
    -- ModUtils.getMapDirectoryFilename and FS25_allTheFoliage's main.lua,
    -- both of which resolve a file next to map.xml the same way. Real bug
    -- caught in testing: Utils.getDirectory alone returns a bare relative
    -- path ("maps/") - g_currentMission.baseDirectory must be prepended to
    -- get an actually-resolvable absolute path, confirmed by TerraFarm's
    -- own getMapDirectoryFilename doing exactly this. Without it, every
    -- fresh placement silently fell back to the built-in grassShort-only
    -- default, palette never actually loaded despite iw.xml existing.
    local iwXMLFilename = g_currentMission.baseDirectory .. Utils.getDirectory(mapXMLFilename) .. "iw.xml"
    local xmlFile = XMLFile.load("IWFoliagePalette", iwXMLFilename)

    if xmlFile == nil then
        debugPrintf("no iw.xml at %s - using default (%s only)", iwXMLFilename, self.fallbackEntry.name)
        return
    end

    local entries = {}
    local entriesByName = {}
    local specificEntriesByNameAndState = {}
    local specificCount = 0
    local index = 0

    while true do
        local key = string.format("iwConfig.foliageMapping.entry(%d)", index)

        if not xmlFile:hasProperty(key) then
            break
        end

        local name = xmlFile:getString(key .. "#name")

        if name ~= nil then
            -- state present (sentinel -1 = absent, real states are always
            -- >=1 given the stageMin=0-is-unreadable fix) marks this as a
            -- specific single-state override - it's never picked for fresh
            -- placement, only found via a matching (name, state) lookup
            -- once something's already sitting at that exact state.
            -- stageMin/stageMax default to just that one state (today's
            -- narrow behavior), but aren't forced to it - a specific entry
            -- can explicitly declare its own wider range + randomStage to
            -- diversify via growth/spread exactly like a general entry
            -- would, while still carrying whatever extra behavior (e.g.
            -- mutateChance) makes it worth being a specific override in
            -- the first place. Confirmed live: forcing stageMin=stageMax
            -- unconditionally meant a specific entry could only ever
            -- reinforce itself on growth/spread, with mutateChance as the
            -- only way out - not what "should behave like everything else,
            -- plus an escape hatch" means.
            local state = xmlFile:getInt(key .. "#state", -1)
            local isSpecific = state >= 0

            local entry = {
                name = name,
                chance = xmlFile:getInt(key .. "#chance", 0),
                stageMin = xmlFile:getInt(key .. "#stageMin", isSpecific and state or 0),
                stageMax = xmlFile:getInt(key .. "#stageMax", isSpecific and state or 0),
                randomStage = xmlFile:getString(key .. "#randomStage", "false") == "true",
                clusters = xmlFile:getString(key .. "#clusters", "false") == "true",
                grow = xmlFile:getString(key .. "#grow", "true") == "true",
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

            if isSpecific then
                specificEntriesByNameAndState[name] = specificEntriesByNameAndState[name] or {}
                specificEntriesByNameAndState[name][state] = entry
                specificCount = specificCount + 1
            else
                table.insert(entries, entry)
                entriesByName[entry.name] = entry
            end
        end

        index = index + 1
    end

    xmlFile:delete()

    if #entries > 0 or specificCount > 0 then
        if #entries > 0 then
            self.entries = entries
            self.entriesByName = entriesByName
        end

        self.specificEntriesByNameAndState = specificEntriesByNameAndState
        debugPrintf("loaded %d general + %d specific entries from %s", #entries, specificCount, iwXMLFilename)
    end
end

-- Public: find the palette entry matching a raw foliage name (and,
-- optionally, the exact state currently there), as read back by
-- ImmersiveWeathering:getFoliageNameAt - nil if nothing is there yet, or
-- if what's there doesn't correspond to any entry this palette knows
-- about (e.g. ambient map content outside the configured palette). A
-- specific (name, state) override, if one is declared, always wins over
-- the general name-only entry - e.g. decoFoliage state 9 specifically can
-- have its own mutateChance without affecting the other 14 states that
-- fall under the general decoFoliage entry.
function IWFoliagePalette:findEntry(name, state)
    if name == nil then
        return nil
    end

    if state ~= nil then
        local specificByState = self.specificEntriesByNameAndState[name]

        if specificByState ~= nil and specificByState[state] ~= nil then
            return specificByState[state]
        end
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

    return self.fallbackEntry
end

-- Public: the stage a fresh placement of this entry should start at.
function IWFoliagePalette:pickInitialStage(entry)
    if entry.randomStage then
        return math.random(entry.stageMin, entry.stageMax)
    end

    return entry.stageMin
end

-- Public: the stage an existing patch should move to on a repeat hit.
-- randomStage entries (unrelated species/model variants, e.g. decoBush/
-- decoFoliage) structurally never grow, full stop - not "unless grow is
-- also explicitly set false". A pool of unrelated flowers/bushes has no
-- meaningful order to advance through, so "growth" on one of these was
-- never anything but a full reroll to a random different species -
-- exactly the churn that made an established poppy patch turn into
-- lavender on a later hit. The only legitimate way a randomStage entry's
-- identity changes at all is a deliberate mutateChance roll (a real
-- succession event, not incidental reroll noise). Checked first and
-- unconditionally, so no entry needs to separately remember grow="false"
-- to get this - it was too easy to add randomStage without it (or add it
-- to one entry and forget the next).
--
-- grow=false only still matters for ordered (non-randomStage) entries -
-- a real growth-stage progression an author wants frozen for some other
-- reason. Spread is unaffected either way - it uses pickSpreadStage, not
-- this function.
function IWFoliagePalette:growStage(entry, currentStage)
    if entry.randomStage then
        return currentStage or entry.stageMin
    end

    if entry.grow == false then
        return currentStage or entry.stageMin
    end

    local nextStage = (currentStage or entry.stageMin) + 1

    if nextStage > entry.stageMax then
        nextStage = entry.stageMax
    end

    return nextStage
end

-- Public: the stage a NEW cluster node (a spread neighbor) should start
-- at - distinct from pickInitialStage, which answers "what should a
-- brand-new instance on empty ground be." Ordered entries (a real
-- growth-stage progression, e.g. meadow) are the same either way: a
-- spread node is genuinely a young new plant, starting at stageMin and
-- growing up on its own subsequent visits. randomStage entries (unrelated
-- species/model variants, e.g. decoBush/decoFoliage) are not - they're a
-- pool of distinct flowers/bushes, not a sequence, so spreading a poppy
-- patch should clone more poppies next to it, not reroll into a random
-- different flower (the same reasoning growStage's grow=false already
-- applies to growth, just for spread instead).
function IWFoliagePalette:pickSpreadStage(entry, currentStage)
    if entry.randomStage then
        return currentStage or self:pickInitialStage(entry)
    end

    return entry.stageMin
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
-- literalName entries (currently only the built-in grassShort fallback)
-- use the bare name regardless of stage - not part of the "_s<stage>"
-- numbered convention at all.
function IWFoliagePalette:getWriteName(entry, stage)
    if entry.literalName then
        return entry.name
    end

    return entry.name .. "_s" .. stage
end

-- Public: the entry a real seeder vehicle should sow, or grassShort (the
-- universal fallback) if the loaded palette flagged nothing.
function IWFoliagePalette:getSeederEntry()
    for _, entry in ipairs(self.entries) do
        if entry.seeder then
            return entry
        end
    end

    return self.fallbackEntry
end
