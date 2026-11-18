--[[
    Immersive Weathering (FS25)

    Current MVP:
      * run a weathering sweep once per in-game day
      * sample random map coordinates
      * place grassShort on gravel
      * provide debug keys for terrain/foliage inspection and manual testing
]]

ImmersiveWeathering = {}
local MOD_DIRECTORY = g_currentModDirectory

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

local GRASS_MATERIAL_ONLY = { [MATERIAL.GRASS] = true }

-- Wither intensity is a player-facing dial, not a fixed constant - 0 means
-- "never", 1.0 means "paint a straight road", everything between is
-- naturalistic wear. Cycled with a debug key the same way TerraFarm's own
-- machine tools step through settings one keypress at a time.
local TYRE_WITHER_LEVELS = {0.0, 0.01, 0.02, 0.05, 0.1, 0.2, 0.3, 0.4, 0.5, 0.75, 1.0}      -- the share of texels a pass paints (fine at the bottom: 10% is a lot)
local TYRE_WITHER_DEFAULT_INDEX = 9                 -- 50%
-- i18n keys, one per TYRE_WITHER_LEVELS entry, in the same order - for the
-- settings-page choice control, which needs real text/keys, not just a
-- raw index range.
local TYRE_WITHER_LEVEL_LABELS = {
    "iw_wither_pct_0", "iw_wither_pct_1", "iw_wither_pct_2", "iw_wither_pct_5", "iw_wither_pct_10", "iw_wither_pct_20",
    "iw_wither_pct_30", "iw_wither_pct_40", "iw_wither_pct_50", "iw_wither_pct_75", "iw_wither_pct_100",
}
-- the wheel sensitivity keeps its six levels (0, 20 ... 100%)
local WHEEL_SENSITIVITY_LABELS = {
    "iw_wither_pct_0", "iw_wither_pct_20", "iw_wither_pct_40", "iw_wither_pct_60", "iw_wither_pct_80", "iw_wither_pct_100",
}

-- Rolled fresh per stamp instead of one fixed material, for a mottled,
-- naturalistic look rather than a flat single-texture road - but still
-- player-directed, since "some naturalistic blend" and "I'm building a
-- dirt road, not a gravel one" are both real things to want. Toggle picks
-- which one dominates; the 10% off-material is what keeps it from looking
-- like a flat single-texture stamp either way. Same weighted-pick shape as
-- IWFoliagePalette:pickFreshEntry, just a different domain (terrain
-- material, not foliage), so kept as its own tiny helper rather than
-- forcing one function to serve both.
local TYRE_PAINT_PALETTES = {
    {label = "DIRT",   entries = {{weight = 0.9, name = "DIRT"},   {weight = 0.1, name = "GRAVEL"}}},
    {label = "GRAVEL", entries = {{weight = 0.9, name = "GRAVEL"}, {weight = 0.1, name = "DIRT"}}},
}
local TYRE_PAINT_PALETTE_DEFAULT_INDEX = 1
-- i18n keys, one per TYRE_PAINT_PALETTES entry, in the same order.
local TYRE_PAINT_PALETTE_LABELS = {"iw_material_dirt", "iw_material_gravel"}
-- iw-map.xml <groundMapping> entry names, same order/index as
-- TYRE_PAINT_PALETTES/TYRE_PAINT_PALETTE_LABELS above - the Settings-page
-- toggle itself stays fixed at these two options; iw-map.xml supplies their
-- content (which real texture layers, what weights, foliage chance), not
-- the toggle's own option count.
local TYRE_PAINT_PALETTE_NAMES = {"dirt", "gravel"}

-- Tyre painting per terrain texel (paintTyreContact): a texel is decided once per pass of a vehicle (the TTL), every later pass decides it again; a contact paints at most this many cells, and at most this many deformations a frame.
local TYRE_CELL_TTL_MS = 8000                       -- one pass of a vehicle: its tyres in the same rut (and its frames) decide a texel once within this
local PAINT_HARDNESS, PAINT_STRENGTH = 0.9, 1.0
local PAINT_MAX_CELLS_PER_CONTACT = 64
local PAINT_APPLIES_PER_FRAME = 16
local TRAMPLE_CELLS_PER_FRAME = 24

-- How much wheelCount actually discounts chance - 0% means every wheel
-- rolls its own full, unscaled chance independently (more wheels = more
-- rolls, no per-wheel discount at all); 100% is today's original behavior
-- (full linear division, so a 6-wheeled combine doesn't wear ground 6x
-- faster than a 2-wheeled ATV at the same dial setting). Values between
-- are a partial blend. Reuses TYRE_WITHER_LEVELS' own 0/20/40/60/80/100%
-- shape and l10n keys (iw_wither_pct_*) - identical percentage meaning,
-- no reason for a second set of duplicate labels.
local WHEEL_SENSITIVITY_LEVELS = {0.0, 0.2, 0.4, 0.6, 0.8, 1.0}
local WHEEL_SENSITIVITY_DEFAULT_INDEX = 6

-- Real cost found live: a big multi-axle vehicle+trailer combo can fire a
-- dozen+ of the tyre debugPrintf calls below within the same tick (every
-- wheel independently rolling clear/drift/wither/displace), each one both
-- a string-format+print AND (for drift/wither/displace) a real
-- TerrainDeformation paint operation - confirmed as an actual lag spike,
-- not a hypothetical one. Defaults ON (today's behavior, and these tags
-- are genuinely how the whole palette/ground system got debugged
-- tonight) - this is for turning it off once you're not actively
-- debugging, not a permanent recommendation to disable it.
local VERBOSE_LOGGING_LEVELS = {false, true}
local VERBOSE_LOGGING_DEFAULT_INDEX = 2
local VERBOSE_LOGGING_LABELS = {"iw_off", "iw_on"}

-- How many random coordinates each day-change sweep samples - was a fixed
-- local before, now a toggle so a denser sweep can be tested without
-- editing code (heavier, but the sweep is off the main thread's hot path
-- anyway - it's a once-per-day-change batch, not per-frame).
local SWEEP_SAMPLE_COUNTS = {1000, 2000, 4000, 6000, 8000, 10000}
local SWEEP_SAMPLE_COUNT_DEFAULT_INDEX = 3       -- 4000 (a new install: the background pass spreads them over many frames)
local SWEEP_INTERVAL_LABELS = { "iw_sweep_calendar", "iw_sweep_10min", "iw_sweep_5min", "iw_sweep_2min" }
-- i18n keys, not the raw numbers - UIHelper's choice control returns the
-- raw *value* for numeric entries but the *index* for string entries
-- (its hasStrings flag), and sweepSampleCountIndex needs to stay an
-- index (1..6) to match SWEEP_SAMPLE_COUNTS[index] lookups elsewhere in
-- this file. Passing the numbers directly would have silently stored
-- 1000/2000/etc. into the index field instead.
local SWEEP_SAMPLE_COUNT_LABELS = {
    "iw_samples_1000", "iw_samples_2000", "iw_samples_4000",
    "iw_samples_6000", "iw_samples_8000", "iw_samples_10000",
}

local function pickPaintMaterial(entries)
    local roll = math.random()
    local cumulative = 0

    for _, entry in ipairs(entries) do
        cumulative = cumulative + entry.weight
        if roll <= cumulative then
            return entry.name
        end
    end

    return entries[#entries].name
end

-- Reads the REAL current binding for an action instead of assuming it
-- matches whatever modDesc.xml ships as the default - confirmed necessary
-- the hard way tonight, since a player's manual rebind via the settings
-- screen silently overrides the shipped default from then on, and our own
-- hardcoded HUD labels had no way to know that happened. Same native the
-- base game's own InputGlyphElement uses for on-screen key prompts
-- (g_inputDisplayManager), not in scriptBinding.xml, so wrapped in pcall
-- and falls back to the given default if it errors or returns nothing.
local function getActionKeyLabel(actionName, fallback)
    if g_inputDisplayManager == nil then
        return fallback
    end

    local success, helpElement = pcall(
        g_inputDisplayManager.getControllerSymbolOverlays,
        g_inputDisplayManager, actionName, nil, "", true
    )

    if not success or helpElement == nil or helpElement.keys == nil or #helpElement.keys == 0 then
        return fallback
    end

    return "[" .. table.concat(helpElement.keys, "+") .. "]"
end

-- VEHICLE deliberately excluded, unlike when this was sweep-only: this
-- same raycast (isSpotClearForFoliage) is now also called from the tyre
-- wither/seeder checks, which run at the exact spot a wheel is touching
-- right now - the vehicle triggering the check would always see its own
-- body directly above that point and permanently block itself. Confirmed
-- as the actual cause of wither doing nothing at all regardless of
-- chance: zero TyreWither log entries while TyreMaterialDrift/TyreClear
-- (neither of which got this check) kept firing normally. The sweep
-- samples random distant coordinates, so losing vehicle-exclusion there
-- is a rare cosmetic edge case, not a real regression.
local WEATHERING_COLLISION_FLAG_NAMES = {
    "TERRAIN", "TREE", "VEHICLE_FORK",
    "STATIC_OBJECT", "DYNAMIC_OBJECT", "BUILDING", "ROAD", "ANIMAL"
}

-- TEST_RIG_GRID_LAYERS/MAX_STATE/STATES/SPACING and placeFoliageTestRig
-- itself moved to WAILA (WailaDebugTools) - pure world/map investigation,
-- never read or wrote iw-map.xml/the foliage palette.
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
local ROAD_WIPE_HALF_M = 1.0                 -- (half side of the square wiped around a sample that stands on a road: a stamp is up to 0.7 m round)
local GRASS_LOW_READ = "decoFoliage"
-- "decoBush" (Layer 1, type 3) is confirmed in decoFoliages - real,
-- writable in principle, used for the pre-existing map bush displace
-- target - but flaky this session (rejected every attempt on this
-- specific use). Left wired up as a harmless no-op rather than ripped
-- out, same reasoning as fruit was kept in the old system: costs nothing
-- to leave in case a future session behaves differently.
local BUSH = "decoBush"

local NEIGHBOR_STEP = 1.0
local NEIGHBOR_OFFSETS = {
    {-1, -1}, {0, -1}, {1, -1},
    {-1,  0},          {1,  0},
    {-1,  1}, {0,  1}, {1,  1},
}

-- Detection kernel for getFoliageNameNearby - deliberately much tighter
-- than NEIGHBOR_STEP/NEIGHBOR_OFFSETS above, which are sized for
-- claiming a *new* neighboring spot 1m away during spread, not for
-- reliably re-finding a stamp that's already there. placeFoliage's own
-- quad (halfSize 0.35-0.7, so ~0.7-1.4m across) is small enough that a
-- single exact-point density read can land in the gap between painted
-- pixels inside it (confirmed via WAILA) - so a sweep sample reading
-- "empty" isn't trustworthy on its own until a small ring around it is
-- also checked.
local FOLIAGE_DETECT_RADIUS = 0.4
local FOLIAGE_DETECT_OFFSETS = {
    {-1, -1}, {0, -1}, {1, -1},
    {-1,  0},          {1,  0},
    {-1,  1}, {0,  1}, {1,  1},
}

-- Terrain texture's own regrowth (one layer down from foliage) - a
-- sampled grass-material spot has a chance to reclaim one dirt/gravel
-- neighbor back to grass. Not folded into the foliage palette - it's
-- keyed by terrain material, not foliage name, a genuinely different
-- domain from what IWFoliagePalette governs.
local TERRAIN_REGROWTH_TARGETS = { [MATERIAL.DIRT] = true, [MATERIAL.GRAVEL] = true }
-- A texture set with "Over stone" on may be laid over stone and sand ground too (tyres and rollers alike), so a stone pattern can be rolled over another one; not over roads and buildings (WAILA's layers), not a game field.
local FORCE_MATERIALS = { [MATERIAL.STONE] = true, [MATERIAL.SAND] = true }
-- Grass growing back from the sides (applyTerrainRegrowth): the share of grass around a bare spot that is needed at all, the chance at a share of 1 (it falls with the square of the share), the most spots one pass paints
local TERRAIN_REGROWTH_MIN_SHARE = 0.3
local TERRAIN_REGROWTH_BASE_CHANCE = 0.5
local TERRAIN_REGROWTH_MAX_PER_PASS = 80
-- The spots IW wore itself (IWWearSpots) are visited by every pass: grass is painted back with a chance of WEAR_HEAL_BASE_CHANCE x share^2 per visit (a rut in a meadow: about 0.15 a pass, half of them healed after
-- about 4 passes), if at least WEAR_HEAL_MIN_SHARE of the ground around is grass; at most WEAR_HEAL_MAX_PER_PASS a pass.
local WEAR_HEAL_BASE_CHANCE = 0.15
local WEAR_HEAL_MIN_SHARE = 0.2
local WEAR_HEAL_MAX_PER_PASS = 120

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
        local success = superFunc(mission, filename, ...)

        -- iw-save.xml load is deferred to CURRENT_MISSION_START, same
        -- proven-safe pattern FS25_Hammer's own sandboxtools.xml load
        -- uses (a physics/density-map query fired directly inside
        -- loadMap hung there once, confirmed the hard way in that mod -
        -- this particular load has no physics query of its own, but
        -- consistency with the pattern that's actually confirmed safe
        -- costs nothing). self.trackedPatches itself is constructed
        -- earlier in ImmersiveWeathering:loadMap (the mod's own
        -- addModEventListener callback, unrelated to this
        -- BaseMission.loadMap override) - only the disk read is deferred.
        g_messageCenter:subscribeOneshot(MessageType.CURRENT_MISSION_START, function()
            if ImmersiveWeathering.trackedPatches ~= nil then
                ImmersiveWeathering.trackedPatches:load()
            end
            if ImmersiveWeathering.wearSpots ~= nil then
                ImmersiveWeathering.wearSpots:load()
            end
        end)

        -- FSCareerMissionInfo.saveToXMLFile hook - same real, confirmed-
        -- necessary pattern FS25_Hammer uses for sandboxtools.xml
        -- (registration-time writes alone didn't survive an actual Save
        -- Game pass). Installed here, not at file-scope, for the same
        -- reason Hammer's own comment gives: FSCareerMissionInfo isn't a
        -- boot-time global. Guarded so a second loadMap (loading a
        -- different save without restarting) doesn't stack wrappers.
        if not ImmersiveWeathering.saveHookInstalled then
            FSCareerMissionInfo.saveToXMLFile = Utils.appendedFunction(FSCareerMissionInfo.saveToXMLFile, function()
                if ImmersiveWeathering.trackedPatches ~= nil then
                    ImmersiveWeathering.trackedPatches:save()
                end
                if ImmersiveWeathering.wearSpots ~= nil then
                    ImmersiveWeathering.wearSpots:save()
                end
            end)
            ImmersiveWeathering.saveHookInstalled = true
        end

        return success
    end
)

-- ============================================================
-- Entry point
-- ============================================================

function ImmersiveWeathering:loadMap(_)
    debugPrint("----------------------------------------------------------------------")
    debugPrint("Immersive Weathering (FS25): loadMap() called - initializing...")

    self.wailaTabDone = false

    self.config = IWConfig.new(
        TYRE_WITHER_DEFAULT_INDEX,
        TYRE_PAINT_PALETTE_DEFAULT_INDEX,
        SWEEP_SAMPLE_COUNT_DEFAULT_INDEX,
        WHEEL_SENSITIVITY_DEFAULT_INDEX,
        VERBOSE_LOGGING_DEFAULT_INDEX,
        IWSweep.INTERVAL_DEFAULT_INDEX
    )

    self.settingsUI = IWSettingsUI.new(
        self.config,
        TYRE_WITHER_LEVEL_LABELS,
        TYRE_PAINT_PALETTE_LABELS,
        SWEEP_SAMPLE_COUNT_LABELS,
        WHEEL_SENSITIVITY_LABELS,
        VERBOSE_LOGGING_LABELS,
        SWEEP_INTERVAL_LABELS
    )

    -- Loads the current map's own iw-map.xml if present (sibling to map.xml),
    -- falls back to the built-in single-grassShort palette otherwise.
    self.foliagePalette = IWFoliagePalette.new()

    -- the texture sets of this map (the built-in two, then the player's), what a tyre paints with; the tyre painting remembers which texels it decided
    self.paintRecent = IWPaintCells.newRecent(TYRE_CELL_TTL_MS, 20000)
    self.paintVersion = 1
    self.textureSets = self:buildTextureSets()
    local mapId = g_currentMission.missionInfo ~= nil and g_currentMission.missionInfo.mapId or nil
    self.textureStorePath = IWTextureStore.path(mapId)
    self.textureSets:restore(IWTextureStore.load(self.textureStorePath))
    self.foliageSets = self:buildFoliageSets()
    self.foliageStorePath = IWFoliageStore.path(mapId)
    self.foliageSets:restore(IWFoliageStore.load(self.foliageStorePath))
    -- other mods (Daisychain) read the sets through this table: a mod's own globals are invisible to the others, g_currentMission is shared
    g_currentMission.immersiveWeatheringFoliage = IWFoliageSets.api(function() return self.foliageSets end, function() return self.foliagePalette end, math.random)
    if self.config:getTyrePaintPaletteIndex() > self.textureSets:count() then
        self.config.tyrePaintPaletteIndex = 1
    end

    -- Constructed here (so self.trackedPatches exists and is safe to
    -- reference immediately), but its own disk read is deferred - see
    -- the BaseMission.loadMap override above for why.
    self.trackedPatches = IWTrackedPatches.new()
    self.wearSpots = IWWearSpots.new()                                   -- (the spots IW wore: healed by every pass; loaded with the tracked patches below)

    self:refreshTyreEffectsLabel()

    addConsoleCommand("iwClass", "iwClass [here | off | half <m> | cell <m>]: draws what IW thinks the ground is (field, building, road, forest, meadow, bare, other) on the full-screen map and logs the counts and the terrain materials behind them", "consoleClassOverlay", self)
    addConsoleCommand("iwPaintDebug", "iwPaintDebug: draws where the tyre painting lands (the contact patch in yellow, the texels it decided: green painted, grey not); the same command turns it off", "togglePaintDebug", self)
    addConsoleCommand("iwProbe", "iwProbe: what IW reads at the crosshair (material, field, WAILA, the ground around) and what it would do there", "probeAtCrosshair", self)

    g_messageCenter:subscribe(
        MessageType.DAY_CHANGED,
        ImmersiveWeathering.onDayChanged,
        self
    )

    debugPrint("Immersive Weathering (FS25): ready.")
    debugPrint("----------------------------------------------------------------------")
end

function ImmersiveWeathering:deleteMap()
    removeConsoleCommand("iwProbe")
    removeConsoleCommand("iwClass")
    g_inputBinding:removeActionEventsByTarget(self)
    g_messageCenter:unsubscribeAll(self)
end

-- ============================================================
-- HUD
-- ============================================================

-- A whole night of chasing a third-party keybind overlay's opaque display
-- logic (confirmed accurate, just external to us) for something this
-- small isn't worth it - draw our own current-state readout directly from
-- our own fields, no g_inputBinding round-trip, no dependency on any
-- other mod's UI. Always on rather than a toggle key.
-- Tried top-left flush against the edge - collided with the power-tools
-- quickbar, which also claims that corner. Rather than push the panel far
-- down the screen to dodge the quickbar's height (which varies a lot,
-- 3-10+ rows depending on context, and isn't ours to query), shift
-- rightward past its width instead - that stays fairly constant (~0.19)
-- regardless of row count, so this is robust to the quickbar getting
-- taller in some other context in a way a vertical offset guess wasn't.
-- Stays comfortably short of the top-right date/money bar (~0.70) too.
-- Top-anchored the same way WailaHud does it (self.top, panel grows
-- downward) - HUD_TOP here is this panel's own top edge, not the screen's.
-- HUD_LEFT_FALLBACK is only used if WAILA's own mini panel isn't present
-- (see getHudLeft) - normally we dock to its right, since it's the
-- leftmost/anchor panel in this row now. Panel width trimmed from 0.20 to
-- 0.19 to keep the full 3-panel row (WAILA mini + 2 of ours) inside the
-- ~0.51 band between the quickbar and the date/money bar.
local HUD_LEFT_FALLBACK = 0.20
local HUD_TOP = 0.98
-- Narrowed from 0.19: at 0.19x2 + WAILA's mini panel + gaps, the combined
-- row reached to x=0.685, which collides with the base game's own
-- top-right cluster (calendar/compass/money) on at least one confirmed
-- resolution. 0.17 buys real margin.
local HUD_PANEL_WIDTH = 0.17
local HUD_PANEL_GAP = 0.010
-- Matches WailaHud's miniHeight (0.036 header + 0.062 body = 0.098) exactly
-- so both panels share the same total height and therefore the same
-- bottom Y, given they both anchor to the same HUD_TOP. Previously
-- 0.040/0.072 (0.112 total) - WAILA's summary line and IW's swatch/value
-- row sat at genuinely different heights despite looking like one row.
local HUD_PANEL_HEADER_HEIGHT = 0.036
local HUD_PANEL_BODY_HEIGHT = 0.062
local HUD_PANEL_HEIGHT = HUD_PANEL_HEADER_HEIGHT + HUD_PANEL_BODY_HEIGHT
local HUD_TITLE_SIZE = 0.016
local HUD_LABEL_SIZE = 0.0135
local HUD_KEYBIND_SIZE = 0.0135
local HUD_VALUE_SIZE = 0.0145
local HUD_SWATCH_SIZE = 0.016

-- Two distinct panels instead of one 4-cell strip - tyre wear and the
-- ambient nightly sweep are two different systems (one driven by the
-- player driving, one by day-change), and mashing them into one
-- undifferentiated row made that harder to read at a glance than it
-- needed to be. Small fixed-size swatches instead of proportional fill
-- bars too - a bar wide enough to read as "a bar" was wider than this
-- panel should be; a small color chip communicates the same category/
-- state info without the width.
local function buildTyrePanel(self)
    local material = self.textureSets ~= nil and self.textureSets:get(self.config:getTyrePaintPaletteIndex()).name:upper() or TYRE_PAINT_PALETTES[self.config:getTyrePaintPaletteIndex()].label
    local witherChance = self:getTyreWitherChance()

    return {
        title = "TYRE WITHERING",
        headerKeybind = getActionKeyLabel("IW_TOGGLE_TYRE_EFFECTS", "[Shift+T]"),
        headerColor = self.config:isTyreEffectsEnabled() and {0.25, 0.75, 0.25} or {0.75, 0.25, 0.25},
        -- Texture/Chance are now Settings-page controls (the keybinds
        -- that used to cycle these are retired below) - keybind left nil
        -- since there's genuinely no key to press anymore, but the label
        -- stays: dropping it too left a bare swatch+number with no way to
        -- tell what it was measuring. Swap D/G and Sow Grass are gone
        -- entirely, not just re-labeled - both fully superseded by
        -- automatic mechanics (material drift, the seeder feature) that
        -- do the same thing without a manual key.
        cells = {
            {
                label = "Texture",
                keybind = nil,
                value = material,
                color = material == "DIRT" and {0.55, 0.35, 0.15} or {0.55, 0.55, 0.55},
            },
            {
                label = "Chance",
                keybind = nil,
                value = string.format("%d%%", witherChance * 100),
                color = {0.85, 0.75, 0.15},
            },
        },
    }
end

local function buildSweepPanel(self)
    return {
        title = "NIGHTLY WEATHERING LOOPS",
        headerKeybind = nil,
        -- Samples is now a Settings-page control too - same read-only
        -- treatment as Texture/Chance above (label stays, keybind doesn't).
        cells = {
            {
                label = "Samples",
                keybind = nil,
                value = tostring(self:getSweepSampleCount()),
                color = {0.85, 0.75, 0.15},
            },
            {
                label = "Run Now",
                keybind = getActionKeyLabel("IW_RUN_SWEEP", "[Shift+N]"),
                value = nil,
                color = nil,
            },
            {
                label = "Weather Target",
                keybind = getActionKeyLabel("IW_WEATHER_CROSSHAIR", "[Shift+H]"),
                value = nil,
                color = nil,
            },
        },
    }
end

local function drawHudPanel(left, panel)
    local panelBottom = HUD_TOP - HUD_PANEL_HEIGHT

    drawFilledRect(left, panelBottom, HUD_PANEL_WIDTH, HUD_PANEL_HEIGHT, 0, 0, 0, 0.65)

    setTextAlignment(RenderText.ALIGN_LEFT)
    setTextColor(1, 1, 1, 1)
    setTextBold(true)
    renderText(left + 0.008, HUD_TOP - 0.017, HUD_TITLE_SIZE, panel.title)
    setTextBold(false)

    if panel.headerKeybind ~= nil then
        -- No separate "Enabled"/"Disabled" label needed - the keybind
        -- itself in the on/off color already says which it is, and reads
        -- as one clean line under the title instead of two labels
        -- competing for space.
        setTextAlignment(RenderText.ALIGN_LEFT)
        setTextColor(panel.headerColor[1], panel.headerColor[2], panel.headerColor[3], 1)
        renderText(left + 0.008, HUD_TOP - 0.034, HUD_KEYBIND_SIZE, panel.headerKeybind)
    end

    drawFilledRect(left, HUD_TOP - HUD_PANEL_HEADER_HEIGHT, HUD_PANEL_WIDTH, 0.001, 0, 0, 0, 0.7)

    local bodyTop = HUD_TOP - HUD_PANEL_HEADER_HEIGHT
    local cellWidth = HUD_PANEL_WIDTH / #panel.cells

    setTextAlignment(RenderText.ALIGN_LEFT)

    for index, cell in ipairs(panel.cells) do
        local cellLeft = left + (index - 1) * cellWidth
        local textLeft = cellLeft + 0.008

        -- label nil means "read-only status, adjust it in Settings"
        -- (Texture/Chance/Samples) rather than "press this key" - skip the
        -- label line and let the swatch+value sit roughly centered instead
        -- of pinned to the bottom under empty space.
        if cell.label ~= nil then
            setTextColor(1, 1, 1, 1)
            renderText(textLeft, bodyTop - 0.018, HUD_LABEL_SIZE, cell.label)
        end

        -- Value and keybind both render on this same bottom content row
        -- (panelBottom + 0.018) rather than keybind getting its own line
        -- under the label - matches WAILA's mini-panel summary line at the
        -- identical Y (see WailaHud:drawMini), so the whole HUD row reads
        -- as one consistent baseline instead of some cells' content
        -- sitting at a different height than others'. No cell currently
        -- sets both value and keybind, so this never has to choose between
        -- them.
        if cell.value ~= nil then
            local swatchBottom = panelBottom + 0.014
            if cell.label == nil and cell.keybind == nil then
                swatchBottom = panelBottom + (HUD_PANEL_BODY_HEIGHT - HUD_SWATCH_SIZE) * 0.5
            end

            drawFilledRect(textLeft, swatchBottom, HUD_SWATCH_SIZE, HUD_SWATCH_SIZE, cell.color[1], cell.color[2], cell.color[3], 1)

            setTextColor(1, 1, 1, 1)
            renderText(textLeft + HUD_SWATCH_SIZE + 0.006, swatchBottom + 0.004, HUD_VALUE_SIZE, cell.value)
        elseif cell.keybind ~= nil then
            setTextColor(0.65, 0.65, 0.65, 1)
            renderText(textLeft, panelBottom + 0.018, HUD_KEYBIND_SIZE, cell.keybind)
        end
    end
end

function ImmersiveWeathering:draw()
    if self.config == nil then
        return
    end
    self:drawPaintDebug()
    IWFoliagePreview.draw(self)

    local tyrePanel = buildTyrePanel(self)
    local sweepPanel = buildSweepPanel(self)
    local totalWidth = HUD_PANEL_WIDTH * 2 + HUD_PANEL_GAP

    -- WAILA's mini panel is the real anchor for this whole row now - dock
    -- to its right if it's present. Read via g_currentMission, not a bare
    -- WailaHud global - confirmed via direct logging that separately
    -- loaded mods don't actually see a new global table another mod
    -- declares (WailaHud read as nil from here every single frame for
    -- over 30 seconds straight), even though both mods already read/write
    -- g_currentMission constantly elsewhere. Falls back to our own fixed
    -- corner if WAILA isn't loaded at all, so this still works standalone.
    local hudLeft = HUD_LEFT_FALLBACK
    if g_currentMission ~= nil and g_currentMission.wailaHudMiniRight ~= nil then
        hudLeft = g_currentMission.wailaHudMiniRight + HUD_PANEL_GAP
    end

    -- Published the same way, for anything that might want to dock under
    -- IW specifically. Not a formal API, just plain fields on shared
    -- engine state.
    if g_currentMission ~= nil then
        g_currentMission.immersiveWeatheringHudLeft = hudLeft
        g_currentMission.immersiveWeatheringHudWidth = totalWidth
        g_currentMission.immersiveWeatheringHudBottom = HUD_TOP - HUD_PANEL_HEIGHT
    end

    if drawFilledRect == nil then
        return
    end

    drawHudPanel(hudLeft, tyrePanel)
    drawHudPanel(hudLeft + HUD_PANEL_WIDTH + HUD_PANEL_GAP, sweepPanel)

    setTextAlignment(RenderText.ALIGN_LEFT)
end

addModEventListener(ImmersiveWeathering)

-- ============================================================
-- Settings page injection
-- ============================================================

-- InGameMenu.onMenuOpened, not BaseMission.loadMapFinished - switched
-- after confirming against FS25_AdditionalContracts (an actually working,
-- installed mod doing the same thing): loadMapFinished fires once the map
-- is done loading, but that's apparently too early for the settings
-- page's own GUI elements (gameSettingsLayout etc.) to exist yet.
-- onMenuOpened only fires once the player actually opens the ESC menu, by
-- which point everything's guaranteed built. injectUiSettings() is
-- already idempotent (self.isInitialized guard) so appending this
-- unconditionally on every menu open is safe - it only actually builds
-- controls the first time.
InGameMenu.onMenuOpened = Utils.appendedFunction(
    InGameMenu.onMenuOpened,
    function(...)
        if ImmersiveWeathering.settingsUI ~= nil then
            ImmersiveWeathering.settingsUI:injectUiSettings()
        end
    end
)

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
                    -- False, not true: all three actions still using this
                    -- helper (H, N, I) are now shown in our own HUD, so
                    -- hide them from whatever text-visibility-respecting
                    -- overlay(s) exist rather than duplicate the info -
                    -- confirmed the real settings/remap menu lists actions
                    -- regardless of this flag, so this shouldn't make them
                    -- any harder to find/rebind there.
                    g_inputBinding:setActionEventTextVisibility(
                        actionEventId,
                        false
                    )
                else
                    debugPrintf(
                            "Immersive Weathering (FS25): FAILED to register %s",
                            label
                        )
                end

                return actionEventId
            end

            registerDebugAction(
                InputAction.IW_WEATHER_CROSSHAIR,
                ImmersiveWeathering.onWeatherCrosshairPressed,
                "weather crosshair"
            )

            registerDebugAction(
                InputAction.IW_RUN_SWEEP,
                ImmersiveWeathering.onRunSweepPressed,
                "run sweep"
            )

            registerDebugAction(
                InputAction.IW_DEBUG_MENU,
                ImmersiveWeathering.onDebugMenuPressed,
                "debug menu"
            )

            -- IW_TOGGLE_SAMPLE_COUNT, IW_CYCLE_WITHER_CHANCE and
            -- IW_TOGGLE_PAINT_BIAS are retired - no action, no binding, no
            -- l10n in modDesc.xml. Sample count/wither chance/paint bias
            -- now live on the Settings page instead of a cycle key, via
            -- IWSettingsUI's autoBind controls writing straight to
            -- self.config. IW_SWAP_DIRT_GRAVEL/IW_SOW_GRASS and their
            -- handlers were removed outright (not just unwired) - fully
            -- superseded by automatic mechanics (material drift, the
            -- seeder feature) that do the same job without a manual key.
            ImmersiveWeathering.tyreEffectsActionEventId = registerDebugAction(
                InputAction.IW_TOGGLE_TYRE_EFFECTS,
                ImmersiveWeathering.onToggleTyreEffectsPressed,
                "toggle tyre effects"
            )
            ImmersiveWeathering:refreshTyreEffectsLabel()
        end
    )

-- ============================================================
-- Callbacks
-- ============================================================

-- Tried vehicle-scoped registration (Vehicle:onRegisterActionEvents +
-- self:addActionEvent, the pattern real vehicle specializations like
-- TerraFarm's Machine use) for the tyre keys, on the theory that they're
-- vehicle-context actions the same way TerraFarm's own machine toggle is.
-- Reverted: TerraFarm's toggle only makes sense for the one specific
-- machine you're driving, but tyre withering/weight/material are global
-- mod settings that just happen to matter while driving - and once the
-- HUD started showing their state persistently (on foot too, not just
-- in-vehicle), being unable to toggle them from on foot became a real,
-- confirmed inconsistency, not just a theoretical one. Vehicle-scoped
-- registration also turned out to be genuinely flaky in practice -
-- isActiveForInput flipped back to false within seconds of a vehicle
-- becoming active on at least one observed occasion, silently wiping the
-- bindings. Back to the same global on-foot hook H/N/I already use
-- reliably everywhere, on foot and in any vehicle, confirmed all night.

function ImmersiveWeathering:onWeatherCrosshairPressed(
    actionName,
    inputValue,
    callbackState,
    isAnalog
)
    debugPrint("Immersive Weathering (FS25): weather crosshair key pressed")
    self:weatherAtCrosshair()
end

-- placeTerrainLayerTestRow, dumpDensityProbe, and dumpTerrainLayers moved
-- to WAILA (WailaDebugTools) - none of them read or wrote iw-map.xml/the
-- foliage palette, pure world/engine investigation.

-- The power-tools overlay has no room to show current values, only static
-- descriptions of what a key does - so instead of fighting that, these
-- three rewrite their own bound key's label text live via
-- setActionEventText, turning the existing row into the status readout
-- instead of adding a separate HUD. Guarded on both the action id and the
-- relevant self field being set, since registration (this closure) and
-- loadMap (where the self fields get initialized) are two independent
-- lifecycle events with no guaranteed order - whichever finishes second
-- is the one that actually paints the initial label.
function ImmersiveWeathering:refreshTyreEffectsLabel()
    if self.tyreEffectsActionEventId == nil or self.config == nil then
        return
    end
    g_inputBinding:setActionEventText(
        self.tyreEffectsActionEventId,
        string.format("Tyre dmg: %s", self.config:isTyreEffectsEnabled() and "ON" or "OFF")
    )
end

function ImmersiveWeathering:onToggleTyreEffectsPressed(
    actionName,
    inputValue,
    callbackState,
    isAnalog
)
    self.config:toggleTyreEffectsEnabled()
    self:refreshTyreEffectsLabel()
    debugPrintf(
        "Immersive Weathering (FS25): tyre effects (clear/wither/displace) %s",
        self.config:isTyreEffectsEnabled() and "ENABLED" or "DISABLED"
    )
end

function ImmersiveWeathering:onRunSweepPressed(
    actionName,
    inputValue,
    callbackState,
    isAnalog
)
    debugPrint("Immersive Weathering (FS25): run sweep key pressed")
    self:runWeatheringSweep()
end

function ImmersiveWeathering:onDebugMenuPressed(
    actionName,
    inputValue,
    callbackState,
    isAnalog
)
    debugPrint("Immersive Weathering (FS25): debug menu key pressed")
    self:showDebugMenu()
end

-- IW's own minimal port of the OptionDialog pattern seen working in
-- FS25_PowerTools's DialogHelper.showOptionDialog - OptionDialog/
-- OptionDialog.createFromExistingGui are real base-game GUI classes
-- (dataS/gui/dialogs/, same family as YesNoDialog/TextInputDialog), not a
-- PowerTools-exclusive trick or a dependency on that mod. Replaces what
-- used to be five separate debug/test keybinds (place test rig, fill
-- area, dump terrain layers, paint layer test row, density probe) with
-- one menu - the keybind list was growing by one every time a new
-- throwaway investigation tool showed up. Core gameplay actions (weather
-- crosshair, run sweep, toggle tyre effects) deliberately stay on direct
-- keys, not folded into this menu - those get pressed constantly during
-- normal testing, a menu round-trip would be the wrong tradeoff for them.
function ImmersiveWeathering:showDebugMenu()
    -- Place foliage test rig / dump terrain layers / paint layer test row
    -- / density probe all moved to WAILA (WailaDebugTools) - none of them
    -- ever read or wrote iw-map.xml/the foliage palette, pure world/engine
    -- investigation that only lived here because the raycast/paint
    -- helpers were already at hand. Fill area is the one exception kept
    -- here for now - unclear yet whether its gravel-not-grassShort
    -- behavior is a real bug worth tracing before deciding where it
    -- belongs. Dump config validity is the opposite of the tools that
    -- left - it's about iw-map.xml's own content, not the world, so it
    -- belongs here permanently.
    local actions = {
        { "Fill area (debug)", self.placeFoliageAreaFill },
        { "Dump iw-map.xml config validity", self.dumpConfigValidity },
    }

    local options = {}
    for index, action in ipairs(actions) do
        options[#options + 1] = index .. ") " .. action[1]
    end

    local target = self
    local function onDebugMenuSelected(callbackTarget, selectedOption, args)
        debugPrintf("[DebugMenu] callback fired, selectedOption=%s", tostring(selectedOption))

        if type(selectedOption) ~= "number" or selectedOption == 0 then
            return
        end

        local action = actions[selectedOption]

        if action ~= nil and action[2] ~= nil then
            debugPrintf("[DebugMenu] running action %d: %s", selectedOption, action[1])
            action[2](target)
        end
    end

    OptionDialog.createFromExistingGui({
        options = options,
        optionText = "Choose a debug action",
        optionTitle = "IW Debug Tools",
        callbackFunc = onDebugMenuSelected,
    }, "IWDebugMenuOptionDialog")

    local optionDialog = OptionDialog.INSTANCE
    optionDialog.optionElement:setState(1)
    optionDialog:setCallback(onDebugMenuSelected, target, {})
end

function ImmersiveWeathering:onDayChanged()
    -- only for the "once per game day" pace: the others run in the background (update)
    if IWSweep.intervalMs(self.config ~= nil and self.config.sweepIntervalIndex or IWSweep.INTERVAL_DEFAULT_INDEX) == nil then
        self:runWeatheringSweep()
    end
end

-- The background pass: every few real minutes (the weathering pace setting) a pass of getSweepSampleCount() samples starts, and each frame does a few of them within IWSweep.BUDGET_MS, spread evenly over the whole map.
-- The samples are the same as the batch sweep's (foliage transitions, terrain regrowth); the tracked patches are processed once at the end of a pass.
-- IW's settings as a tab of WAILA's debug hub (IWWailaTab); WAILA may load after IW, so it is tried every frame until it is there.
function ImmersiveWeathering:registerWailaTab()
    local waila = g_currentMission ~= nil and g_currentMission.waila or nil
    if waila == nil or waila.registerDebugTab == nil then
        return
    end
    local function texts(keys)
        local list = {}
        for i, key in ipairs(keys) do
            list[i] = g_i18n:getText(key)
        end
        return list
    end
    -- the colour field of the texture row: the palette's main material (sRGB as the HUD swatch has it, made linear for the hub)
    local function paletteColor(index)
        local main = IWTextureSets.main(self.textureSets:get(index))
        return IWTextureSets.layerColor(main)
    end
    local options = {
        { key = "tyreEffectsEnabled", label = "Tyre effects (Shift+T)", boolean = true },
        { key = "tyreWitherLevelIndex", label = "Tyre withering chance", texts = texts(TYRE_WITHER_LEVEL_LABELS) },
        { key = "tyrePaintPaletteIndex", label = "Tyre withering texture", getTexts = function() return self.textureSets:names() end, color = paletteColor, layerId = function(index) return self:getTerrainLayerIdByName((IWTextureSets.main(self.textureSets:get(index)))) end, onChange = function() self:touchTextureSets(false) end },
        { key = "sweepSampleCountIndex", label = "Samples per sweep", texts = texts(SWEEP_SAMPLE_COUNT_LABELS) },
        { key = "sweepIntervalIndex", label = "Weathering pace", texts = texts(SWEEP_INTERVAL_LABELS) },
        { key = "wheelSensitivityIndex", label = "Wheel count discount (grass clearing, bushes)", texts = texts(WHEEL_SENSITIVITY_LABELS) },
        { key = "verboseLoggingIndex", label = "Verbose debug logging", texts = texts(VERBOSE_LOGGING_LABELS) },
    }
    local icon = Utils.getFilename("icon_tab_weathering.dds", MOD_DIRECTORY)
    self.wailaTabDone = IWWailaTab.register(waila, IWWailaTab.new(self.config, options), "Weathering", icon)

    -- the texture sets: the map's sets, then yours, edited by type
    local function refresh()
        if waila.refreshDebugHub ~= nil then
            waila.refreshDebugHub()
        end
    end
    local api = {
        sets = self.textureSets,
        layerNames = function() return self:listTerrainLayers() end,
        layerId = function(name) return self:getTerrainLayerIdByName(name) end,
        texelSize = function() return self:getTexelSize() end,
        getActive = function() return self.config:getTyrePaintPaletteIndex() end,
        setActive = function(index)
            self.config.tyrePaintPaletteIndex = index
            self.config:save()
            self:touchTextureSets(false)
        end,
        changed = function() self:touchTextureSets(true) end,
        askName = function(default, callback)
            if TextInputDialog == nil or TextInputDialog.show == nil then
                return
            end
            TextInputDialog.show(function(_, text, clickOk)
                if clickOk and text ~= nil and text ~= "" then
                    callback(text)
                end
                refresh()
            end, self, default, "Name of the texture", "Name", 24, g_i18n:getText("button_ok"))
        end,
    }
    IWTexturesTab.register(waila, IWTexturesTab.new(api), "Textures", icon)

    -- the foliage lists: what IW may seed on meadow, bare ground and forest floor
    IWFoliageTab.register(waila, IWFoliageTab.new({
        sets = self.foliageSets,
        names = function()
            local names = {}
            for _, entry in ipairs(self.foliagePalette.entries) do
                names[#names + 1] = entry.name
            end
            return names
        end,
        range = function(name)
            local entry = self.foliagePalette:findEntry(name)
            return entry ~= nil and { min = entry.stageMin, max = entry.stageMax, sequential = entry.sequential } or nil
        end,
        stateName = function(name, state) return IWFoliageNames.stateName(name, state) end,
        icon = function(name, state) return IWFoliageNames.iconFor(name, state) end,
        preview = function(name, min, max)
            local text = IWFoliagePreview.show(self, name, min, max)
            print("[ImmersiveWeathering] " .. text)
        end,
        clearPreview = function() print("[ImmersiveWeathering] " .. IWFoliagePreview.clear(self)) end,
        changed = function() self:touchFoliageSets() end,
        askName = api.askName,
    }), "Foliage sets", icon)

    -- the debug picture of the ground classes: two rows of WAILA's Terrain tab
    IWClassOverlay.registerRows(waila, self)
end

function ImmersiveWeathering:consoleClassOverlay(arg1, arg2)
    return IWClassOverlay.console(self, arg1, arg2)
end

function ImmersiveWeathering:togglePaintDebug()
    self.paintDebugOn = not self.paintDebugOn
    self.paintDebugList = {}
    return "iwPaintDebug " .. (self.paintDebugOn and "on: drive over grass or a path" or "off")
end

-- The debug overlay of the tyre painting: the contact patch of each wheel (yellow), the texels decided (green: painted, grey: not), for the last 3 seconds.
local function drawQuad(x0, z0, x1, z1, x2, z2, r, g, b)
    local function y(x, z) return getTerrainHeightAtWorldPos(g_terrainNode, x, 0, z) + 0.08 end
    local x3, z3 = x2 + (x1 - x0), z2 + (z1 - z0)
    local points = { { x1, z1 }, { x0, z0 }, { x2, z2 }, { x3, z3 } }
    for i = 1, 4 do
        local a, c = points[i], points[i % 4 + 1]
        drawDebugLine(a[1], y(a[1], a[2]), a[2], r, g, b, c[1], y(c[1], c[2]), c[2], r, g, b)
    end
end

function ImmersiveWeathering:drawPaintDebug()
    local list = self.paintDebugList
    if not self.paintDebugOn or list == nil then
        return
    end
    local now = g_time or 0
    local kept = {}
    local half = self:getTexelSize() * 0.5
    for _, record in ipairs(list) do
        if now - record.at < 3000 then
            kept[#kept + 1] = record
            local q = record.quad
            drawQuad(q[1], q[2], q[3], q[4], q[5], q[6], 1, 1, 0)
            for _, cell in ipairs(record.cells) do
                local r, g, b = 0.5, 0.5, 0.5
                if cell.painted then
                    r, g, b = 0, 1, 0
                end
                drawQuad(cell[1] + half, cell[2] - half, cell[1] - half, cell[2] - half, cell[1] + half, cell[2] + half, r, g, b)
            end
        end
    end
    self.paintDebugList = kept
end

-- How much a vehicle wears what it drives on: its mass against 8 t (a tractor with a load is about 1), between a quarter and four times.
function ImmersiveWeathering:damageFactor(vehicle)
    local mass = 4
    if vehicle ~= nil and vehicle.getTotalMass ~= nil then
        local ok, total = pcall(vehicle.getTotalMass, vehicle, true)
        if ok and total ~= nil and total > 0 then
            mass = total
        end
    end
    return math.max(0.25, math.min(4, mass / 8))
end

-- A road or a building according to WAILA's layers (a stone ground that is the asphalt of a road is not for a roller to repaint). Without WAILA nothing is excluded.
ImmersiveWeathering.ROADS_EXCLUDED = false            -- roads are ruttable (a dirt track is a road to WAILA); only buildings are kept out. true: asphalt is not for a roller or a tyre set to repaint
function ImmersiveWeathering:isRoadOrBuilding(x, z)
    local tracer = g_currentMission ~= nil and g_currentMission.wailaTrailTracer or nil
    if tracer == nil then
        return false
    end
    if tracer.sampleBuilding ~= nil and tracer.sampleBuilding(x, z) then
        return true
    end
    return ImmersiveWeathering.ROADS_EXCLUDED and tracer.sampleDrivable ~= nil and tracer.sampleDrivable(x, z) == 2
end

-- The names of the map's terrain layers worth picking, sorted (cached): the combined layers (the map's <CombinedLayer>: a base layer, or several, with the engine's own variety noise; their names are in capitals, and a
-- combined layer may wrap just one base layer), not the base layers they are made of. A map without combined layers lists all of them.
function ImmersiveWeathering:listTerrainLayers()
    if self.terrainLayerNames == nil then
        local combined, all = {}, {}
        for i = 0, getTerrainNumOfLayers(g_terrainNode) - 1 do
            local name = getTerrainLayerName(g_terrainNode, i)
            if name ~= nil and name ~= "" then
                all[#all + 1] = name
                if IWTextureSets.looksCombined(name) or getTerrainLayerNumOfSubLayers(g_terrainNode, i) > 1 then
                    combined[#combined + 1] = name
                end
            end
        end
        local names = #combined > 0 and combined or all
        table.sort(names, function(a, b) return a:lower() < b:lower() end)
        self.terrainLayerNames = names
    end
    return self.terrainLayerNames
end

function ImmersiveWeathering:update(dt)
    if self.config == nil or g_currentMission == nil or self.foliagePalette == nil then
        return
    end
    IWClassOverlay.tick()
    if not self.wailaTabDone then
        self:registerWailaTab()
    end
    local interval = IWSweep.intervalMs(self.config.sweepIntervalIndex)
    if interval == nil then
        self.sweepPass = nil
        return
    end
    if self.sweepPass == nil then
        self.sweepWaitMs = (self.sweepWaitMs or 0) + (dt or 0)
        if self.sweepWaitMs < interval then
            return
        end
        self.sweepWaitMs = 0
        local samples = self:getSweepSampleCount()
        local spots = self.wearSpots ~= nil and self.wearSpots:snapshot() or {}
        self.sweepPass = IWSweep.new(samples + #spots)           -- (the samples first, then the worn spots one by one: the same time slicing)
        self.sweepPass.samples, self.sweepPass.spots = samples, spots
        self.sweepPass.startedAt = getTimeSec()
        self.sweepPass.workMs = 0
    end
    local pass = self.sweepPass
    local began = getTimeSec()
    local finished = IWSweep.advance(pass, IWSweep.BUDGET_MS, getTimeSec, function(p)
        local done = p.total - p.remaining
        if done < p.samples then
            local x, z = IWSweep.pickPoint(math.random, g_currentMission.terrainSize, done, p.samples)
            self:applyFoliageTransitions(x, z, p.stats)
            self:applyTerrainRegrowth(x, z, p.stats)
        else
            local spot = p.spots[done - p.samples + 1]
            if spot ~= nil then
                self:processWearSpot(spot, p.stats)
            end
        end
    end)
    pass.workMs = pass.workMs + (getTimeSec() - began) * 1000
    if finished then
        self:processTrackedPatches(pass.stats)
        local s = pass.stats
        debugPrintf("[Sweep] background pass finished: %d samples and %d worn spots in %.0f ms of work over %.0f s, seeded=%d spread=%d grown=%d mutated=%d regrown=%d healed=%d (forgotten %d, left %d)",
            pass.samples, #pass.spots, pass.workMs, getTimeSec() - pass.startedAt, s.seeded or 0, s.spread or 0, s.grown or 0, s.mutated or 0, s.regrown or 0, s.healed or 0, s.wearForgotten or 0,
            self.wearSpots ~= nil and #self.wearSpots.spots or 0)
        if self.wearSpots ~= nil then
            self.wearSpots:saveIfDirty()
        end
        self.sweepPass = nil
    end
end

-- ============================================================
-- Debug helpers
-- ============================================================




-- Runs the exact same per-sample logic the daily sweep uses, but on a
-- small deterministic grid around one targeted spot instead of 1000
-- random ones across the whole map - point at a specific patch and see
-- what it is, what got rolled, and what it became, instead of waiting on
-- blind resampling luck to ever land there again. Matches WAILA's own
-- "AREA 5x5m / step 0.50m" HUD stat block exactly, so before/after is
-- directly comparable, and processing the whole visible patch instead of
-- one exact coordinate sidesteps whether this raycast and WAILA's own
-- independent raycast landed on the same sub-tile point.
local WEATHER_CROSSHAIR_AREA_SIZE = 5
local WEATHER_CROSSHAIR_AREA_STEP = 0.5
-- Debug toggle: false makes weatherAtCrosshair only evolve foliage that's
-- already there, never seed new growth on empty ground - isolates "does
-- an established patch actually change" from "does new nearby growth just
-- look like it did". Flip back to true for normal use once that's settled.
local WEATHER_CROSSHAIR_ALLOW_FRESH_PLACEMENT = false

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
    local half = WEATHER_CROSSHAIR_AREA_SIZE * 0.5
    local stats = {}
    local sampled = 0

    -- Direct world x/z density-map reads/writes per grid point, no
    -- per-point raycast - same cheap pattern placeFoliageAreaFill and the
    -- nightly sweep already use, just a dense deterministic grid instead
    -- of a random scatter.
    local dz = -half
    while dz <= half do
        local dx = -half
        while dx <= half do
            self:applyFoliageTransitions(hx + dx, hz + dz, stats, true, WEATHER_CROSSHAIR_ALLOW_FRESH_PLACEMENT)
            self:applyTerrainRegrowth(hx + dx, hz + dz, stats, true)
            sampled = sampled + 1
            dx = dx + WEATHER_CROSSHAIR_AREA_STEP
        end
        dz = dz + WEATHER_CROSSHAIR_AREA_STEP
    end

    debugPrintf(
        "[Weather] (%.2f %.2f) %gx%gm sampled=%d seeded=%d spread=%d grown=%d mutated=%d regrown=%d",
        hx, hz, WEATHER_CROSSHAIR_AREA_SIZE, WEATHER_CROSSHAIR_AREA_SIZE, sampled,
        stats.seeded or 0, stats.spread or 0, stats.grown or 0, stats.mutated or 0, stats.regrown or 0
    )
end

-- iwProbe: what IW thinks the ground at the crosshair is, and why it would (or would not) seed, grow or regrow there. The material ids are numbers the code hardwires (MATERIAL), the field test is the
-- game's own field list: both can be wrong on a map (a field dug in with TerraFarm is no game field, a parking lot is "dirt" or "gravel"), so this prints the raw reads next to the verdicts, plus what the
-- ground around reads as (the share of grass in a ring at 3 m and at 6 m: what a grass-from-the-sides rule would see) and what WAILA knows about the spot (field blobs, declared areas).
local MATERIAL_NAMES = {}
for name, id in pairs(MATERIAL) do
    MATERIAL_NAMES[id] = name
end

local function materialName(id)
    return id ~= nil and (MATERIAL_NAMES[id] or "?") .. " (" .. tostring(id) .. ")" or "none"
end

function ImmersiveWeathering:probeAt(hx, hz)
    local a1, a2, a3, a4, material = getTerrainAttributesAtWorldPos(g_terrainNode, hx, 0, hz, true, true, true, true, false)
    local isField = FSDensityMapUtil.getFieldDataAtWorldPosition(hx, 0, hz)
    local lines = { string.format("iwProbe at %.1f / %.1f", hx, hz) }
    lines[#lines + 1] = string.format("terrain reads: %s %s %s %s | material %s", tostring(a1), tostring(a2), tostring(a3), tostring(a4), materialName(material))
    lines[#lines + 1] = string.format("a game field here: %s | on grass only: %s | weatherable (dirt, sand, grass, gravel): %s", tostring(isField == true), tostring(material ~= nil and GRASS_MATERIAL_ONLY[material] == true), tostring(material ~= nil and WEATHERABLE_MATERIALS[material] == true))
    local wailaTypes = {}
    local waila = g_currentMission ~= nil and g_currentMission.waila or nil
    if waila ~= nil and waila.getTypes ~= nil then
        local ok, types = pcall(waila.getTypes, hx, hz)
        wailaTypes = ok and types or {}
        lines[#lines + 1] = "WAILA knows here: " .. (#wailaTypes > 0 and table.concat(wailaTypes, ", ") or "no field, no declared area")
    else
        lines[#lines + 1] = "WAILA is not there"
    end
    local deps = self:classDeps()
    local class = IWClass.classify(hx, hz, deps)
    local share = IWClass.grassShare(hx, hz, deps)
    lines[#lines + 1] = string.format("IW class: %s | grass share around %.2f | flowers may be placed here: %s | grass may grow back here: %s (needs bare ground and a share of at least %.1f)",
        class, share, tostring(class == IWClass.MEADOW), tostring(class == IWClass.BARE and share >= TERRAIN_REGROWTH_MIN_SHARE), TERRAIN_REGROWTH_MIN_SHARE)
    local name, stage = self:getFoliageNameAt(hx, hz)
    lines[#lines + 1] = string.format("foliage here: %s %s | clear spot for foliage: %s", tostring(name), tostring(stage), tostring(self:isSpotClearForFoliage(hx, hz)))
    for _, radius in ipairs({ 3, 6 }) do
        local counts, total = {}, 0
        for k = 0, 7 do
            local angle = k * math.pi / 4
            local _, _, _, _, m = getTerrainAttributesAtWorldPos(g_terrainNode, hx + math.cos(angle) * radius, 0, hz + math.sin(angle) * radius, true, true, true, true, false)
            local key = materialName(m)
            counts[key] = (counts[key] or 0) + 1
            total = total + 1
        end
        local parts = {}
        for key, n in pairs(counts) do
            parts[#parts + 1] = string.format("%s x%d", key, n)
        end
        table.sort(parts)
        lines[#lines + 1] = string.format("ring at %d m (8 points): %s", radius, table.concat(parts, ", "))
    end
    return table.concat(lines, "\n")
end

function ImmersiveWeathering:probeAtCrosshair()
    local camera = g_cameraManager:getActiveCamera()
    local x, y, z = getWorldTranslation(camera)
    local dirX, dirY, dirZ = localDirectionToWorld(camera, 0, 0, -1)
    self.debugFieldRaycastHit = nil
    raycastClosest(x, y, z, dirX, dirY, dirZ, 200, "onDebugFieldRaycastCallback", self, CollisionFlag.TERRAIN)
    if self.debugFieldRaycastHit == nil then
        return "iwProbe: no terrain within 200 m of where you look"
    end
    local hx, _, hz = unpack(self.debugFieldRaycastHit)
    local text = self:probeAt(hx, hz)
    print("[ImmersiveWeathering] " .. text)
    return text
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
            if self:paintWitherMaterial(px, pz) then
                placed = placed + 1
            end
        end
    end

    debugPrintf("[AreaFill] %dx%dm mixed-material paint around (%.2f %.2f): %d/%d stamps placed",
        AREA_FILL_SIZE, AREA_FILL_SIZE, hx, hz, placed, ((AREA_FILL_SIZE / AREA_FILL_STEP) + 1) ^ 2)
end

-- Dumps the loaded iw-map.xml palette's own validity against the real engine -
-- one line per entry, every reference it makes (a texture layer name, a
-- foliage layer/state, a cross-entry mutatesTo target) marked OK/MISSING.
-- Squarely IW's own domain (validating iw-map.xml's own content, not world/
-- terrain reverse engineering), unlike the tools that moved to WAILA -
-- this is why IW keeps its own debug menu instead of folding entirely
-- into WAILA's. Complements check_foliage_sync.py (map.xml vs real I3D/
-- descriptors, no game load needed) with the other half: iw-map.xml vs what's
-- actually loaded and resolvable right now, in this running game.
function ImmersiveWeathering:dumpConfigValidity()
    local palette = self.foliagePalette
    local foliageSystem = g_currentMission.foliageSystem

    debugPrintf("[ConfigDump] === foliageMapping (%d entries) ===", #palette.entries)
    for _, entry in ipairs(palette.entries) do
        local stageParts = {}
        for stage = entry.stageMin, entry.stageMax do
            local writeName = palette:getWriteName(entry, stage)
            local ok = foliageSystem:getIsDecoLayerDefined(writeName)
            table.insert(stageParts, string.format("%s=%s", writeName, ok and "OK" or "MISSING"))
        end

        local mutateParts = {}
        for _, mutate in ipairs(entry.mutatesTo) do
            local targetOk = palette.entriesByName[mutate.name] ~= nil
            table.insert(mutateParts, string.format("%s=%s", mutate.name, targetOk and "OK" or "MISSING"))
        end

        debugPrintf(
            "[ConfigDump]   %s chance=%d sequential=%s stages[%s]%s",
            entry.name,
            entry.chance,
            tostring(entry.sequential),
            table.concat(stageParts, " "),
            #mutateParts > 0 and (" mutatesTo[" .. table.concat(mutateParts, " ") .. "]") or ""
        )
    end

    local allowedFruitTypeParts = {}
    for fruitTypeIndex in pairs(self:getAllowedSeederFruitTypeIndices()) do
        local fruitTypeDesc = g_fruitTypeManager:getFruitTypeByIndex(fruitTypeIndex)
        table.insert(allowedFruitTypeParts, fruitTypeDesc ~= nil and fruitTypeDesc.name or tostring(fruitTypeIndex))
    end
    debugPrintf(
        "[ConfigDump] === seederFruitTypes: %s (%s) ===",
        table.concat(allowedFruitTypeParts, " "),
        palette.seederFruitTypeNames ~= nil and "declared in iw-map.xml" or "built-in default"
    )

    local groundEntryCount = 0
    for _ in pairs(palette.groundEntriesByName) do
        groundEntryCount = groundEntryCount + 1
    end

    if groundEntryCount == 0 then
        debugPrintf("[ConfigDump] === groundMapping: none declared, using built-in dirt/gravel split ===")
        return
    end

    debugPrintf("[ConfigDump] === groundMapping (%d entries) ===", groundEntryCount)
    for name, groundEntry in pairs(palette.groundEntriesByName) do
        local textureParts = {}
        for _, texture in ipairs(groundEntry.textures) do
            local ok = self:getTerrainLayerIdByName(texture.name) ~= nil
            table.insert(textureParts, string.format("%s(%d%%)=%s", texture.name, texture.chance, ok and "OK" or "MISSING"))
        end

        local foliageParts = {}
        for _, foliage in ipairs(groundEntry.foliages) do
            local ok = palette.entriesByName[foliage.name] ~= nil
            table.insert(foliageParts, string.format("%s(%d%%)=%s", foliage.name, foliage.chance, ok and "OK" or "MISSING"))
        end

        local mutateParts = {}
        for _, mutate in ipairs(groundEntry.mutatesTo) do
            local ok = palette.groundEntriesByName[mutate.name] ~= nil
            table.insert(mutateParts, string.format("%s(%d%%,%s)=%s", mutate.name, mutate.chance, tostring(mutate.condition), ok and "OK" or "MISSING"))
        end

        debugPrintf(
            "[ConfigDump]   %s%s: textures[%s]%s%s",
            name,
            groundEntry.seeder and " (seeder)" or "",
            table.concat(textureParts, " "),
            #foliageParts > 0 and (" foliage[" .. table.concat(foliageParts, " ") .. "]") or "",
            #mutateParts > 0 and (" mutatesTo[" .. table.concat(mutateParts, " ") .. "]") or ""
        )
    end
end

-- placeFoliageTestRig moved to WAILA (WailaDebugTools) - pure world/map
-- investigation, never read or wrote iw-map.xml/the foliage palette.

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

    return true
end

-- Same write as placeFoliage, but into an exact caller-supplied
-- parallelogram instead of placeFoliage's own randomized stamp. Exists
-- for trampleCells' normalize-then-clear step: writing a randomly
-- sized/rotated stamp there and then clearing a *different* area (the
-- tyre's own narrow contact quad) right after could leave part of the
-- write outside what got cleared - confirmed as the actual cause of a
-- "grass fountain" trailing behind a truck on a plain gravel road, not
-- the normalize idea itself. Writing into the identical quad the clear
-- call uses next means there's nothing left over by construction.
function ImmersiveWeathering:placeFoliageInQuad(decoName, x0, z0, x1, z1, x2, z2)
    decoName = decoName or "grassShort"

    local foliageSystem = g_currentMission.foliageSystem
    if not foliageSystem:getIsDecoLayerDefined(decoName) then
        return false
    end

    foliageSystem:applyDecoFoliage(decoName, x0, z0, x1, z1, x2, z2)
    return true
end

-- Wipes foliage in a square: normalize, then clear (clearDecoArea alone misses ambient meadow).
function ImmersiveWeathering:wipeFoliageSquare(x, z, half)
    local x0, z0, x1, z1, x2, z2 = x - half, z - half, x + half, z - half, x - half, z + half
    self:placeFoliageInQuad(GRASS_LOW_WRITE, x0, z0, x1, z1, x2, z2)
    FSDensityMapUtil.clearDecoArea(x0, z0, x1, z1, x2, z2)
    if self:isVerboseLoggingEnabled() then
        debugPrintf("[RoadWipe] foliage wiped at (%.2f %.2f)", x, z)
    end
end

-- The whole contact area at once (the parallelogram of IWPaintCells.cellsIn: x1 z1 its origin): what the lawnmower does to a square, for a set that removes foliage. One pair of calls, however many cells the roller covers.
-- The paintable foliage layers that are plants (the construction screen's foliage brush paints them; state 0 erases): the dead stalks of decoFoliage stood through the pair of calls below. decoStones is not a plant.
local PLANT_PAINTABLES = { "decoFoliage", "decoFoliageUS", "decoBush", "decoBushUS", "meadow", "grass" }

function ImmersiveWeathering:wipeFoliageQuad(x0, z0, x1, z1, x2, z2)
    self:placeFoliageInQuad(GRASS_LOW_WRITE, x0, z0, x1, z1, x2, z2)
    FSDensityMapUtil.clearDecoArea(x0, z0, x1, z1, x2, z2)
    local foliageSystem = g_currentMission.foliageSystem
    for _, name in ipairs(PLANT_PAINTABLES) do
        local paint = foliageSystem:getFoliagePaintByName(name)
        if paint ~= nil then
            foliageSystem:apply(paint, x0, z0, x1, z1, x2, z2, 0)                   -- (the same call the construction brush makes with state 0)
        end
    end
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

    return layerData.types[typeIndex], value
end

-- Second return (growth-state value) is new - existing callers that only
-- capture the name are unaffected, Lua just discards the extra value.
-- Needed for palette growth tracking (bump-toward-stageMax on repeat
-- hits), which requires knowing not just what's there but what stage.
function ImmersiveWeathering:getFoliageNameAt(x, z)
    local data = self:loadFoliageDebugData()

    if data == nil then
        return nil
    end

    self:resolveFoliagePlaneIds(data)

    for _, layerData in ipairs(data.multilayers) do
        local name, value = decodeFoliageBitsAt(layerData, x, z)

        if name ~= nil then
            return name, value
        end
    end

    return nil
end

-- Only called when the direct exact-point read already came back nil -
-- the common case (genuinely clear ground, or a read that landed dead
-- center on a stamp) needs no extra density-map reads at all. This only
-- pays for itself on the specific "might have missed a small existing
-- stamp" case, which is exactly when it's worth a handful of extra
-- cheap reads. Returns whichever nearby point matched first, same
-- (name, stage) shape as getFoliageNameAt.
function ImmersiveWeathering:getFoliageNameNearby(x, z)
    for _, offset in ipairs(FOLIAGE_DETECT_OFFSETS) do
        local name, value = self:getFoliageNameAt(x + offset[1] * FOLIAGE_DETECT_RADIUS, z + offset[2] * FOLIAGE_DETECT_RADIUS)

        if name ~= nil then
            return name, value
        end
    end

    return nil
end

-- Shared by every call site that might be creating or discovering a
-- trackPatch=true instance (entry-resolution discovery, fresh
-- placement, cluster spread - see applyFoliageTransitions) - one place
-- owning "should this coordinate be tracked" instead of three copies of
-- the same entry.trackPatch/nil-guard/height-lookup logic.
-- registerIfNeeded's own dedupe means this is safe to call every time
-- the sweep touches a trackPatch entry, not just the first time.
function ImmersiveWeathering:registerTrackedPatchIfNeeded(entry, x, z)
    if entry == nil or not entry.trackPatch or self.trackedPatches == nil then
        return
    end

    local y = getTerrainHeightAtWorldPos(g_terrainNode, x, 0, z)
    self.trackedPatches:registerIfNeeded(entry.name, x, y, z)
end


-- force=true skips every dice roll and tries everything possible for the
-- sampled spot instead of one weighted pick - used by weatherAtCrosshair
-- so a manual debug press always shows something instead of "nothing,
-- try again" ~95% of the time on empty ground. The real sweep always
-- calls this with force=false (or omitted) so ambient weathering stays
-- genuinely rare - only the deliberate single-point tool is deterministic.
-- Palette-driven replacement for the old hardcoded FOLIAGE_STATE_OPTIONS/
-- FOLIAGE_SPREAD_RULES tables - see IWFoliagePalette.lua and the map's own
-- iw-map.xml (or the built-in single-grassShort default on a map with none).
-- Two rates the palette design itself doesn't cover are still module
-- constants here rather than new config surface invented unprompted -
-- flagged for retuning if the new balance doesn't feel right:
--   - FOLIAGE_FRESH_PLACEMENT_CHANCE: matches the old EMPTY->seed 5%
--     weight exactly, for genuinely empty ground.
--   - FOLIAGE_SPREAD_CHANCE: matches the old grassShort spread rate (10%),
--     applied uniformly to any entry flagged clusters=true, rather than
--     trying to derive it from chance (already doing double duty for
--     fresh-pick weight and growth rate - a third meaning would overload
--     it further).
-- Dropped from the old system: BUSH's "encroachesOnGrass" (could invade a
-- neighbor that already had plain grass, not just empty ground) - the new
-- schema has no dominance/hierarchy field, so spread now only claims
-- genuinely empty neighbors for every entry uniformly. Flagging as a
-- deliberate simplification, not an oversight.
local FOLIAGE_FRESH_PLACEMENT_CHANCE = 0.05
-- A background pass samples mostly near the player now, so what a pass may add is capped: new foliage seeds and spread steps per pass (the crosshair test forces and is not capped)
local FOLIAGE_MAX_SEEDS_PER_PASS = 12
local FOLIAGE_MAX_SPREAD_PER_PASS = 24
-- Was bumped 0.10 -> 0.90 for testing (spread wasn't observed working at
-- 0.10 across the nightly sweep's own dilution) and confirmed working -
-- almost too well. weatherAtCrosshair's grid reads/writes the same live
-- density map as it scans, not a snapshot, so an existing clusters=true
-- cell near the start of the raster can spread onto a not-yet-visited
-- neighbor, which the scan then reaches moments later in the SAME press
-- and spreads again, chaining across the whole grid in one press - at 90%
-- per cell per visit that chain reaction was close to guaranteed. Back to
-- its original 0.10 now that spread is unambiguously confirmed working -
-- makes a multi-step chain within one pass exponentially, not just
-- somewhat, less likely (0.1^n per n-step chain instead of 0.9^n).
local FOLIAGE_SPREAD_CHANCE = 0.10

-- Would a stamp here overwrite same-kind foliage that is further grown? Reads the four corners.
local FOOTPRINT_OFFSET_M = 0.5
function ImmersiveWeathering:footprintHasHigher(x, z, name, stage)
    for _, sx in ipairs({ -FOOTPRINT_OFFSET_M, FOOTPRINT_OFFSET_M }) do
        for _, sz in ipairs({ -FOOTPRINT_OFFSET_M, FOOTPRINT_OFFSET_M }) do
            local there, thereStage = self:getFoliageNameAt(x + sx, z + sz)
            if there == name and thereStage ~= nil and thereStage > stage then
                return true
            end
        end
    end
    return false
end

function ImmersiveWeathering:applyFoliageTransitions(x, z, stats, force, allowFreshPlacement)
    local name, stage = self:getFoliageNameAt(x, z)

    -- Direct exact-point read missed - before treating this as genuinely
    -- empty ground, check a small ring around it (see
    -- getFoliageNameNearby's own comment for why the exact point alone
    -- isn't trustworthy against a small existing stamp). Growth/mutation/
    -- spread below still write to the ORIGINAL x,z either way, not the
    -- nearby point that matched - re-stamping at the sweep's own sample
    -- point, which also helps thicken/fill the gaps in the existing
    -- patch's footprint over repeated sweeps.
    if name == nil then
        name, stage = self:getFoliageNameNearby(x, z)

        if name ~= nil then
            stats.foundNearby = (stats.foundNearby or 0) + 1
        end
    end

    -- Nothing stands on a road: wipe it (tyres never clear road ground). Manual weathering (force) is left alone.
    if name ~= nil and not force and self:classAt(x, z) == IWClass.ROAD then
        self:wipeFoliageSquare(x, z, ROAD_WIPE_HALF_M)
        stats.roadWiped = (stats.roadWiped or 0) + 1
        return
    end

    local entry = self.foliagePalette:findEntry(name, stage)

    -- Discovery: whenever the sweep recognizes an EXISTING trackPatch
    -- instance, make sure it's registered - covers both "IW placed this
    -- itself a while ago and is only now re-sampling it" and "this was
    -- always here, map-author-placed content IW never planted" (the
    -- actual motivating case - see IWFoliagePalette's trackPatch field
    -- comment). registerIfNeeded's own dedupe makes this a cheap no-op
    -- once something's already tracked.
    self:registerTrackedPatchIfNeeded(entry, x, z)

    if entry == nil then
        -- Nothing here the palette recognizes - either truly empty, or
        -- real content outside the configured palette (ambient map
        -- decoration). Either way, only a fresh-placement roll applies,
        -- same as EMPTY->seed used to be the only thing that fired here.
        -- allowFreshPlacement defaults true (unchanged real behavior) -
        -- explicitly false lets a caller isolate "only evolve what's
        -- already there" from "also seed new growth on empty ground", for
        -- telling apart an established patch actually mutating from new
        -- growth nearby just looking like it did.
        if allowFreshPlacement ~= false and name == nil and (force or ((stats.seeded or 0) < FOLIAGE_MAX_SEEDS_PER_PASS and math.random() <= FOLIAGE_FRESH_PLACEMENT_CHANCE)) then
            -- the ground's own list decides what may be seeded here (the map's default, or the player's edit): none for a class without one
            local freshName, freshState = self.foliageSets:pick(self:classAt(x, z), math.random)
            local freshEntry = freshName ~= nil and self.foliagePalette:findEntry(freshName) or nil
            local freshStage = freshEntry ~= nil and (freshState or self.foliagePalette:pickInitialStage(freshEntry)) or nil
            local writeName = freshEntry ~= nil and self.foliagePalette:getWriteName(freshEntry, freshStage) or nil

            if writeName ~= nil
                and self:isSpotClearForFoliage(x, z)
                and self:placeFoliage(x, z, writeName)
            then
                stats.seeded = (stats.seeded or 0) + 1
                debugPrintf("[Palette] seeded %s at (%.2f %.2f)", writeName, x, z)
                self:registerTrackedPatchIfNeeded(freshEntry, x, z)
            end
        end

        return
    end

    -- Fields are never touched, full stop - matches the same principle
    -- everywhere else in this file, even though something here physically
    -- reads back as a recognized palette entry (a real farmed field can
    -- read exactly like "meadow", same ambiguity noted elsewhere).
    if self:isOnField(x, z) then
        return
    end

    -- Growth: reuses this entry's own chance value as "how readily this
    -- established patch progresses on a visit" - meadow (80%) grows far
    -- more often than a 5%-weight accent species, which reads as a
    -- reasonable "how dominant is this in the succession" analogy without
    -- inventing a separate rate.
    if force or math.random() * 100 <= entry.chance then
        local nextStage = self.foliagePalette:growStage(entry, stage)
        local writeName = self.foliagePalette:getWriteName(entry, nextStage)

        if nextStage ~= stage and not self:footprintHasHigher(x, z, name, nextStage) and self:placeFoliage(x, z, writeName) then
            stats.grown = (stats.grown or 0) + 1
            debugPrintf("[Palette] grew %s -> %s at (%.2f %.2f)", name, writeName, x, z)
        end
    end

    -- Succession: independent of growth above - an established patch can
    -- grow AND mutate on the same visit, same "orthogonal rolls" shape the
    -- old spread-vs-state-options split already used.
    local mutateTarget = self.foliagePalette:rollMutation(entry)

    if mutateTarget ~= nil then
        local mutateStage = self.foliagePalette:pickInitialStage(mutateTarget)
        local writeName = self.foliagePalette:getWriteName(mutateTarget, mutateStage)

        if self:placeFoliage(x, z, writeName) then
            stats.mutated = (stats.mutated or 0) + 1
            debugPrintf("[Palette] %s mutated -> %s at (%.2f %.2f)", name, writeName, x, z)
        end
    end

    -- spreadCandidates counts every sample that landed on a clusters=true
    -- entry - the number to watch if "spread" stays at 0 for a while: it
    -- separates "the random sampler almost never lands back on ground we
    -- already planted" (a real probability problem, 1000 uniform samples
    -- across the whole map vs a small planted footprint) from "it lands
    -- there fine but the neighbor check keeps rejecting" (a logic
    -- problem).
    if entry.clusters then
        stats.spreadCandidates = (stats.spreadCandidates or 0) + 1

        if force or ((stats.spread or 0) < FOLIAGE_MAX_SPREAD_PER_PASS and math.random() <= FOLIAGE_SPREAD_CHANCE) then
            local offset = NEIGHBOR_OFFSETS[math.random(#NEIGHBOR_OFFSETS)]
            local nx = x + offset[1] * NEIGHBOR_STEP
            local nz = z + offset[2] * NEIGHBOR_STEP
            local neighborName = self:getFoliageNameAt(nx, nz)

            debugPrintf(
                "[Cluster] %s at (%.2f %.2f) -> neighbor (%.2f %.2f) reads %s, claimable=%s",
                name, x, z, nx, nz, tostring(neighborName), tostring(neighborName == nil)
            )

            if neighborName == nil
                and self:classAt(nx, nz) == IWClass.MEADOW
                and self:isSpotClearForFoliage(nx, nz)
                and not self:footprintHasHigher(nx, nz, name, self.foliagePalette:pickSpreadStage(entry, stage))
            then
                -- Sequential entries (meadow) spread as a fresh young
                -- instance, starting at stageMin and growing up on its own
                -- subsequent visits. Non-sequential entries (unrelated
                -- species/model variants) instead clone the SOURCE's own
                -- current species - spreading shouldn't turn a poppy patch
                -- into a random different flower at the edges, any more
                -- than growth should.
                local spreadStage = self.foliagePalette:pickSpreadStage(entry, stage)
                local spreadWriteName = self.foliagePalette:getWriteName(entry, spreadStage)

                if self:placeFoliage(nx, nz, spreadWriteName) then
                    stats.spread = (stats.spread or 0) + 1
                    debugPrintf("[Cluster] spread %s -> (%.2f %.2f) succeeded", spreadWriteName, nx, nz)
                    self:registerTrackedPatchIfNeeded(entry, nx, nz)
                end
            end
        end
    end
end

-- Deterministic pass over every tracked patch (see IWTrackedPatches and
-- IWFoliagePalette's trackPatch/trackedSpreadChance/
-- trackedRejuvenateChance fields) - called once per sweep, NOT sampled,
-- so a tracked patch gets checked every single sweep instead of relying
-- on the random sampler ever landing near it again.
--
-- "Past stageMax" is the trigger, not "at stageMax": for a
-- sequential=false entry (e.g. decoFoliage, a pool of unrelated
-- species/variants with no real progression) states within
-- stageMin..stageMax are all equally normal variety, never a "fully
-- grown" signal - only a raw value beyond what iw-map.xml actually
-- curates means "landed in genuinely undefined/degenerate territory"
-- (the exact same failure mode decoBush's own states 13-15 comment
-- describes - a real, previously-observed bug class, not a hypothetical
-- one). For a sequential entry, growStage never takes a patch past stageMax (and never lowers one) on
-- IW's own growth, so "past max" there specifically means something
-- OTHER than IW's own growth pushed it there (an external/map-author
-- placement, or base-game growth outside IW's control) - "rotten and
-- stuck" either way.
function ImmersiveWeathering:processTrackedPatches(stats)
    if self.trackedPatches == nil then
        return
    end

    local patches = self.trackedPatches:getAll()
    local toRemove = {}

    for index, patch in ipairs(patches) do
        local entry = self.foliagePalette:findEntry(patch.name)

        if entry == nil or not entry.trackPatch then
            -- Config changed out from under a saved entry (map author
            -- removed/retagged it) - nothing sensible left to do with
            -- this coordinate.
            table.insert(toRemove, index)
        else
            local name, stage = self:getFoliageNameAt(patch.x, patch.z)

            if name == nil then
                name, stage = self:getFoliageNameNearby(patch.x, patch.z)
            end

            if name ~= entry.name then
                -- Gone (player mowed/plowed/built over it) or mutated
                -- into something else entirely - nothing left here for
                -- this entry to manage, stop tracking it. Matches the
                -- original ask exactly: "if flower is still there...
                -- if not, delete entry."
                table.insert(toRemove, index)
                debugPrintf("[Tracked] %s at (%.2f %.2f) no longer found - untracked", patch.name, patch.x, patch.z)
            elseif stage ~= nil and stage > entry.stageMax then
                stats.trackedRotten = (stats.trackedRotten or 0) + 1

                -- Spread first, using the SOURCE's still-rotten stage
                -- (pickSpreadStage clones the source's current species
                -- for non-sequential entries, same as normal cluster
                -- spread) - separate, low-by-default chance so a
                -- guaranteed-every-sweep check doesn't mean guaranteed
                -- map takeover.
                if math.random() * 100 <= entry.trackedSpreadChance then
                    local offset = NEIGHBOR_OFFSETS[math.random(#NEIGHBOR_OFFSETS)]
                    local nx = patch.x + offset[1] * NEIGHBOR_STEP
                    local nz = patch.z + offset[2] * NEIGHBOR_STEP
                    local neighborName = self:getFoliageNameAt(nx, nz)

                    if neighborName == nil
                        and self:classAt(nx, nz) == IWClass.MEADOW
                        and self:isSpotClearForFoliage(nx, nz)
                        and not self:footprintHasHigher(nx, nz, entry.name, self.foliagePalette:pickSpreadStage(entry, stage))
                    then
                        local spreadStage = self.foliagePalette:pickSpreadStage(entry, stage)
                        local spreadWriteName = self.foliagePalette:getWriteName(entry, spreadStage)

                        if self:placeFoliage(nx, nz, spreadWriteName) then
                            stats.trackedSpread = (stats.trackedSpread or 0) + 1
                            debugPrintf("[Tracked] %s spread (%.2f %.2f) -> (%.2f %.2f)", patch.name, patch.x, patch.z, nx, nz)
                            self:registerTrackedPatchIfNeeded(entry, nx, nz)
                        end
                    end
                end

                -- Rejuvenate the source back to a fresh young instance -
                -- high-by-default chance (the actual bug being fixed:
                -- "even the 10k sweep has a low chance to fix a rotten
                -- sunflower we placed"). Stays tracked either way, so it
                -- cycles through this same life stage again later.
                if math.random() * 100 <= entry.trackedRejuvenateChance then
                    local rejuvenateWriteName = self.foliagePalette:getWriteName(entry, entry.stageMin)

                    if self:placeFoliage(patch.x, patch.z, rejuvenateWriteName) then
                        stats.trackedRejuvenated = (stats.trackedRejuvenated or 0) + 1
                        debugPrintf("[Tracked] %s at (%.2f %.2f) rejuvenated -> %s", patch.name, patch.x, patch.z, rejuvenateWriteName)
                    end
                end
            end
        end
    end

    if #toRemove > 0 then
        self.trackedPatches:removeByIndices(toRemove)
    end
end

-- What a place looks like (IWClass): the dependencies of the classification, made once. The bare ground that counts is dirt, gravel and sand.
local BARE_MATERIALS = { [MATERIAL.DIRT] = true, [MATERIAL.GRAVEL] = true, [MATERIAL.SAND] = true }
function ImmersiveWeathering:classDeps()
    if self.classDepsTable == nil then
        self.classDepsTable = {
            material = function(x, z)
                local _, _, _, _, material = getTerrainAttributesAtWorldPos(g_terrainNode, x, 0, z, true, true, true, true, false)
                return material
            end,
            gameField = function(x, z)
                return FSDensityMapUtil.getFieldDataAtWorldPosition(x, 0, z) == true
            end,
            wailaField = function(x, z)
                local waila = g_currentMission ~= nil and g_currentMission.waila or nil
                return waila ~= nil and waila.get ~= nil and waila.get("field", x, z) ~= nil
            end,
            grassMaterial = MATERIAL.GRASS,
            bareMaterials = BARE_MATERIALS,
        }
    end
    self.classDepsTable.tracer = g_currentMission ~= nil and g_currentMission.wailaTrailTracer or nil          -- (WAILA may load after IW: asked every time)
    return self.classDepsTable
end

function ImmersiveWeathering:classAt(x, z)
    return IWClass.classify(x, z, self:classDeps())
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

    local sampleCount = self:getSweepSampleCount()
    local stats = {}
    local startTime = getTimeSec()

    for i = 1, sampleCount do
        if i % 100 == 0 then
            debugPrintf( "Weathering sweep done %d%%", i / sampleCount * 100 )
        end

        local x, z = self:randomCoordinate()
        self:applyFoliageTransitions(x, z, stats)
        self:applyTerrainRegrowth(x, z, stats)
    end

    -- Deterministic, not sampled - processes every tracked patch exactly
    -- once per sweep regardless of sampleCount, see
    -- processTrackedPatches's own comment for why.
    self:processTrackedPatches(stats)

    local elapsedMs = (getTimeSec() - startTime) * 1000

    debugPrintf(
            "Immersive Weathering (FS25): FINISHED %d samples, seeded=%d spread=%d (candidates=%d) grown=%d mutated=%d regrown=%d foundNearby=%d trackedRotten=%d trackedSpread=%d trackedRejuvenated=%d roadWiped=%d, %.3f ms",
            sampleCount,
            stats.seeded or 0,
            stats.spread or 0,
            stats.spreadCandidates or 0,
            stats.grown or 0,
            stats.mutated or 0,
            stats.regrown or 0,
            stats.foundNearby or 0,
            stats.trackedRotten or 0,
            stats.trackedSpread or 0,
            stats.trackedRejuvenated or 0,
            stats.roadWiped or 0,
            elapsedMs
        )
    debugPrint("----------------------------------------------------------------------")
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


-- ============================================================
-- Tyre foliage destruction
-- ============================================================

local TYRE_CLEAR_DISTANCE = 0.35
local TYRE_DISPLACE_CHANCE = 0.15

function ImmersiveWeathering:getTyreWitherChance()
    return TYRE_WITHER_LEVELS[self.config:getTyreWitherLevelIndex()]
end

function ImmersiveWeathering:getSweepSampleCount()
    return SWEEP_SAMPLE_COUNTS[self.config:getSweepSampleCountIndex()]
end

-- Shared by every terrain-paint target (dirt, gravel, ...) - resolves and
-- caches a map's terrain layer id by name the first time it's asked for.
-- "DIRT"/"GRAVEL" are the two names TerraFarm itself falls back to as
-- defaults across maps, not something we invented.
function ImmersiveWeathering:getTerrainLayerIdByName(name)
    self.terrainLayerIdCache = self.terrainLayerIdCache or {}
    local cached = self.terrainLayerIdCache[name]
    if cached ~= nil then
        if cached == false then
            return nil
        end
        return cached
    end

    -- the combined layer (more than one sublayer: COBBLESTONE04, with the engine's own variety) wins over the base layer of the same name (cobblestone04); a map without combined layers has the base ones
    local numLayers = getTerrainNumOfLayers(g_terrainNode)
    local base = nil
    for i = 0, numLayers - 1 do
        local layerName = getTerrainLayerName(g_terrainNode, i)
        if layerName ~= nil and layerName:upper() == name:upper() then
            if IWTextureSets.looksCombined(layerName) or getTerrainLayerNumOfSubLayers(g_terrainNode, i) > 1 then
                self.terrainLayerIdCache[name] = i
                debugPrintf("[TerrainPaint] resolved %s layer id=%d name=%s (combined)", name, i, layerName)
                return i
            end
            base = base or i
        end
    end
    if base ~= nil then
        self.terrainLayerIdCache[name] = base
        debugPrintf("[TerrainPaint] resolved %s layer id=%d (base layer)", name, base)
        return base
    end

    debugPrintf("[TerrainPaint] no terrain layer named '%s' found on this map", name)
    self.terrainLayerIdCache[name] = false
    return nil
end

-- Public: the terrain layer id the real-seeder path should paint. Reuses
-- the exact same groundMapping mechanism wither already uses for dirt/
-- gravel (a weighted pick among real texture layer names, e.g. a mosaic
-- of grass01/grassDry01/... instead of one flat texture) - via
-- getSeederGroundEntry's seeder="true" flag, not a fixed reserved entry
-- name. No hardcoded assumption that a seeder paints grass specifically -
-- a map author could just as easily flag their "sand" entry instead, this
-- doesn't care which. Falls back to the single hardcoded "GRASS" layer if
-- no groundMapping entry is flagged seeder="true" (today's behavior,
-- works on any map with zero author effort).
function ImmersiveWeathering:getSeederTerrainLayerId()
    local groundEntry = self.foliagePalette:getSeederGroundEntry()
    local textureName = groundEntry ~= nil and self.foliagePalette:pickGroundTexture(groundEntry)
    return self:getTerrainLayerIdByName(textureName or "GRASS")
end

-- Public: the set of real fruit type indices a sowing machine must have
-- loaded to count as "sowing grass" here at all - a map author's own
-- <seederFruitTypes> list in iw-map.xml if declared, or the hardcoded
-- MEADOW/GRASS default otherwise (today's behavior, confirmed real via
-- Roller.lua's own grassFruitTypes = {FruitType.GRASS, FruitType.MEADOW},
-- the same two fruit types the base game itself treats as "grass" for
-- its own roller mechanic - unchanged for every map that doesn't declare
-- its own list, so this can never silently break an existing iw-map.xml).
-- Resolved and cached once, not per-call - fruit type registration
-- doesn't change mid-session. An unresolvable declared name is logged
-- and skipped, not a hard error - one typo shouldn't take the whole list
-- down.
function ImmersiveWeathering:getAllowedSeederFruitTypeIndices()
    if self.allowedSeederFruitTypeIndices ~= nil then
        return self.allowedSeederFruitTypeIndices
    end

    local names = self.foliagePalette.seederFruitTypeNames or { "MEADOW", "GRASS" }
    local indices = {}

    for _, name in ipairs(names) do
        local fruitTypeDesc = g_fruitTypeManager:getFruitTypeByName(name)
        if fruitTypeDesc ~= nil then
            indices[fruitTypeDesc.index] = true
        else
            debugPrintf("[Seeder] iw-map.xml declared unknown fruit type '%s' - ignored", name)
        end
    end

    self.allowedSeederFruitTypeIndices = indices
    return indices
end

-- Public: whether a real sowing machine currently has one of the
-- allowed seeder fruit types loaded (see
-- getAllowedSeederFruitTypeIndices), not some other crop.
-- spec.seeds[spec.currentSeed] is the real internal field (confirmed via
-- SowingMachine.lua's own getSowingMachineSeedFillTypeIndex, which reads
-- the exact same path) - fails closed (false) if anything's missing,
-- same reasoning as isConditionTrue for weather conditions.
function ImmersiveWeathering:isSeederLoadedWithAllowedFruitType(vehicle)
    local spec = vehicle.spec_sowingMachine
    if spec == nil or spec.seeds == nil or spec.currentSeed == nil then
        return false
    end

    local fruitTypeIndex = spec.seeds[spec.currentSeed]
    return self:getAllowedSeederFruitTypeIndices()[fruitTypeIndex] == true
end

-- Ground-texture paint, a different system entirely from the deco density
-- maps everything else here writes to - none of these natives show up in
-- scriptBinding.xml, confirmed instead against TerraFarm's actual working
-- LandscapingOutput:createPaintDeformation and base-game PlaceableLeveling.lua.
-- Each call gets its own throwaway callback target rather than reusing self,
-- since multiple wheels can have an apply() in flight at once and a shared
-- field would race between them.
-- Shared by every terrain-paint caller (tyre wither, ambient regrowth,
-- ...) - the TerrainDeformation lifecycle itself, decoupled from which
-- layer or why. Each call gets its own throwaway callback target rather
-- than reusing self, since multiple paints can have an apply() in flight
-- at once and a shared field would race.
function ImmersiveWeathering:paintTerrainAtLayer(x, z, layerId)
    local paint = TerrainDeformation.new(g_terrainNode)
    paint:enablePaintingMode()
    paint:addSoftCircleBrush(x, z, 0.4, 0.3, 0.6, layerId)

    local callbackTarget = { deformation = paint }
    function callbackTarget:onPaintApplied(code, volume)
        self.deformation:delete()
    end

    paint:apply(false, "onPaintApplied", callbackTarget)
end

-- The built-in sets: dirt and gravel, from the map's iw-map.xml groundMapping when it declares them, else the 90/10 split built in above.
function ImmersiveWeathering:buildTextureSets()
    local defaults = {}
    for i, palette in ipairs(TYRE_PAINT_PALETTES) do
        local groundName = TYRE_PAINT_PALETTE_NAMES[i]
        local textures = {}
        local groundEntry = self.foliagePalette:findGroundEntry(groundName)
        if groundEntry ~= nil and #groundEntry.textures > 0 then
            for _, texture in ipairs(groundEntry.textures) do
                textures[#textures + 1] = { layer = texture.name, weight = math.max(1, math.floor(texture.chance + 0.5)) }
            end
        else
            for _, entry in ipairs(palette.entries) do
                textures[#textures + 1] = { layer = entry.name, weight = math.floor(entry.weight * 100 + 0.5) }
            end
        end
        defaults[i] = { name = palette.label, groundName = groundName, textures = textures }
    end
    return IWTextureSets.new(defaults)
end

-- The active texture set (the "Tyre withering texture" setting is its index) and, while it is a built-in one nobody edited, the map's own groundMapping entry (its foliage chances and mutations).
function ImmersiveWeathering:activeTextureSet()
    if self.textureSets == nil then
        return nil
    end
    local set = self.textureSets:get(self.config:getTyrePaintPaletteIndex())
    local groundEntry = nil
    if set.groundName ~= nil and not set.edited then
        groundEntry = self.foliagePalette:findGroundEntry(set.groundName)
    end
    return set, groundEntry
end

-- The map's default foliage lists: the meadow seeds the <foliageMapping> palette (what is left of the 100 % roll is the fallback grass, as the palette's own pick does), the other classes seed nothing.
function ImmersiveWeathering:buildFoliageSets()
    local palette = self.foliagePalette
    local meadow, sum, fallbackAt = {}, 0, nil
    for _, entry in ipairs(palette.entries) do
        if entry.chance > 0 then
            meadow[#meadow + 1] = { name = entry.name, chance = entry.chance }
            sum = sum + entry.chance
            if entry == palette.fallbackEntry then
                fallbackAt = #meadow
            end
        end
    end
    if sum < 100 then
        if fallbackAt ~= nil then
            meadow[fallbackAt].chance = meadow[fallbackAt].chance + (100 - sum)
        else
            meadow[#meadow + 1] = { name = palette.fallbackEntry.name, chance = 100 - sum }
        end
    end
    return IWFoliageSets.new({ meadow = meadow })
end

-- The edited foliage lists go to the map's file.
function ImmersiveWeathering:touchFoliageSets()
    if self.foliageSets ~= nil and self.foliageStorePath ~= nil then
        IWFoliageStore.save(self.foliageStorePath, self.foliageSets:serialize())
    end
end

-- Every texel decided with an older version of the set is decided again: called when the player picks or edits a set.
function ImmersiveWeathering:touchTextureSets(save)
    self.paintVersion = (self.paintVersion or 1) + 1
    if save and self.textureSets ~= nil and self.textureStorePath ~= nil then
        IWTextureStore.save(self.textureStorePath, self.textureSets:serialize())
    end
end

-- One terrain texel in metres (the map's terrain size over its detail map size: 0.5 m on a 4 km map with an 8192 detail map).
function ImmersiveWeathering:getTexelSize()
    local size = g_currentMission ~= nil and g_currentMission.terrainSize or 4096
    local detail = g_currentMission ~= nil and g_currentMission.terrainDetailMapSize or 8192
    return size / detail
end

-- Squares of one texel painted in one layer, one deformation.
function ImmersiveWeathering:paintCells(cells, size, layerId)
    local paint = TerrainDeformation.new(g_terrainNode)
    paint:enablePaintingMode()
    for _, c in ipairs(cells) do
        paint:addSoftSquareBrush(c[3], c[4], size, PAINT_HARDNESS, PAINT_STRENGTH, layerId)
    end
    local callbackTarget = { deformation = paint }
    function callbackTarget:onPaintApplied(code, volume)
        self.deformation:delete()
    end
    paint:apply(false, "onPaintApplied", callbackTarget)
end

-- The tyre's paint: every texel under the contact patch (the tyre's width, up to a metre of its length) is decided once: with the dial's chance it gets a layer of its own, picked from the active set by weight,
-- so the mix is the set's mix at the grain of the terrain. gate (optional) is asked once, and only when there are new texels: the raycast that keeps the paint from going under objects. Returns how many
-- texels were painted.
function ImmersiveWeathering:paintTyreContact(x0, z0, x1, z1, x2, z2, centerX, centerZ, gate, owner, rolling, wheelCount)
    local set, groundEntry = self:activeTextureSet()
    if set == nil or self.paintRecent == nil or (#set.textures == 0 and set.pattern == nil) then
        return 0, {}                                                         -- (a set with no layer at all paints nothing, and wears nothing)
    end
    if g_time ~= self.paintFrame then
        self.paintFrame, self.paintApplies = g_time, 0
    end
    if self.paintApplies >= PAINT_APPLIES_PER_FRAME then
        return 0, {}
    end
    local size = self:getTexelSize()
    local now, version = g_time or 0, self.paintVersion
    local fresh = {}
    for _, c in ipairs(IWPaintCells.cellsIn(x0, z0, x1, z1, x2, z2, size, PAINT_MAX_CELLS_PER_CONTACT)) do
        if not self.paintRecent:isFresh(c[1], c[2], now, version, owner) then
            fresh[#fresh + 1] = c
        end
    end
    if #fresh == 0 or (gate ~= nil and not gate()) then
        return 0, {}
    end
    -- the map's own mutation (dirt becomes mud while it rains) swaps the textures for this contact
    local pickFrom = set
    if groundEntry ~= nil then
        local mutatedName = self.foliagePalette:rollGroundMutation(groundEntry)
        local mutatedEntry = mutatedName ~= nil and self.foliagePalette:findGroundEntry(mutatedName) or nil
        if mutatedEntry ~= nil and #mutatedEntry.textures > 0 then
            pickFrom = { textures = {} }
            for _, texture in ipairs(mutatedEntry.textures) do
                pickFrom.textures[#pickFrom.textures + 1] = { layer = texture.name, weight = texture.chance }
            end
            groundEntry = mutatedEntry
        end
    end
    -- a roller lays its set completely (no dice: it is paving on purpose), its details at the plain chance; a tyre wears the ground at the dial's chance, its details by weight
    local chance = rolling and 1 or self:getTyreWitherChance()
    local byLayer, layers, hits = {}, {}, {}
    local details = IWTextureSets.detailsOf(set, function() return self:listTerrainLayers() end)
    local raining = false
    if details ~= nil then
        if g_time ~= self.rainFrame then
            self.rainFrame, self.rainNow = g_time, IWFoliagePalette.isRaining()          -- (asked once a frame)
        end
        raining = self.rainNow
    end
    local damage = details ~= nil and (rolling and 1 or self:damageFactor(owner)) or 0
    for _, c in ipairs(fresh) do
        self.paintRecent:mark(c[1], c[2], now, version, owner)
        if math.random() <= chance then
            hits[#hits + 1] = c
            -- what driving leaves on the surface: a smudge, a crack (the set's details), the likelier the heavier the vehicle
            for _, detail in ipairs(details or {}) do
                if math.random() * 100 < detail.chance * damage then
                    -- while it rains (and half an hour after) a pothole holds water: its wet twin, when the map has one
                    local detailId = (raining and self:getTerrainLayerIdByName(detail.layer .. "_WET")) or self:getTerrainLayerIdByName(detail.layer)
                    if detailId ~= nil then
                        for _, cell in ipairs(IWTextureSets.detailCells(detail, c[1], c[2], math.random)) do
                            if byLayer[detailId] == nil then
                                byLayer[detailId] = {}
                                layers[#layers + 1] = detailId
                            end
                            table.insert(byLayer[detailId], { cell[1], cell[2], (cell[1] + 0.5) * size, (cell[2] + 0.5) * size })
                        end
                    end
                end
            end
            local name = IWTextureSets.layerFor(pickFrom, c[1], c[2], math.random)
            local layerId = name ~= nil and self:getTerrainLayerIdByName(name) or nil
            if layerId ~= nil then
                if byLayer[layerId] == nil then
                    byLayer[layerId] = {}
                    layers[#layers + 1] = layerId
                end
                table.insert(byLayer[layerId], c)
            end
        end
    end
    if self.paintDebugOn then
        local record = { quad = { x0, z0, x1, z1, x2, z2 }, cells = {}, at = now }
        for _, c in ipairs(fresh) do
            record.cells[#record.cells + 1] = { c[3], c[4], painted = false }
        end
        for _, layerId in ipairs(layers) do
            for _, c in ipairs(byLayer[layerId]) do
                for _, entry in ipairs(record.cells) do
                    if entry[1] == c[3] and entry[2] == c[4] then
                        entry.painted = true
                    end
                end
            end
        end
        self.paintDebugList = self.paintDebugList or {}
        self.paintDebugList[#self.paintDebugList + 1] = record
    end
    -- every contact gets its share of the frame's paint calls (a roller has many contacts, a set many layers: the contacts processed last used to find the budget spent and their cells were lost); the
    -- cells of a layer that is not painted this frame are un-marked and decided again next frame
    local share = math.max(1, math.floor(PAINT_APPLIES_PER_FRAME / math.max(1, wheelCount or 1)))
    local painted, used = 0, 0
    for _, layerId in ipairs(layers) do
        if used < share and self.paintApplies < PAINT_APPLIES_PER_FRAME then
            used = used + 1
            self.paintApplies = self.paintApplies + 1
            self:paintCells(byLayer[layerId], size, layerId)
            painted = painted + #byLayer[layerId]
        else
            for _, c in ipairs(byLayer[layerId]) do
                self.paintRecent:unmark(c[1], c[2])
            end
        end
    end
    if painted > 0 then
        if self.wearSpots ~= nil then
            self.wearSpots:add(centerX, centerZ)
        end
        local foliageEntryName = groundEntry ~= nil and self.foliagePalette:rollGroundFoliage(groundEntry) or nil
        local foliageEntry = foliageEntryName ~= nil and self.foliagePalette:findEntry(foliageEntryName) or nil
        if foliageEntry ~= nil then
            self:placeFoliage(centerX, centerZ, self.foliagePalette:getWriteName(foliageEntry, self.foliagePalette:pickInitialStage(foliageEntry)))
        end
    end
    return painted, hits
end

-- What the tyre does to the foliage on the texels it wore (the hits of paintTyreContact): the grass comes one growth stage down per pass (IWFoliagePalette.trampleStage), the last stage and anything without
-- stages is removed (written as grassShort first, then cleared: clearDecoArea alone does not reliably remove ambient meadow). At most TRAMPLE_CELLS_PER_FRAME cells a frame.
function ImmersiveWeathering:trampleCells(hits)
    if hits == nil or #hits == 0 then
        return
    end
    local mode = IWTextureSets.foliageMode(self:activeTextureSet())      -- "down": a stage a pass, "clear": gone at once (paintContactOnGround wipes the whole area), "keep": untouched
    if mode ~= "down" then
        return
    end
    local half = self:getTexelSize() * 0.5
    local budget = TRAMPLE_CELLS_PER_FRAME
    for _, c in ipairs(hits) do
        if budget <= 0 then
            break
        end
        local name, stage = self:getFoliageNameAt(c[3], c[4])
        if name ~= nil then
            budget = budget - 1
            local x0, z0, x1, z1, x2, z2 = c[3] + half, c[4] - half, c[3] - half, c[4] - half, c[3] + half, c[4] + half
            local entry = self.foliagePalette:findEntry(name, stage)
            local lower = IWFoliagePalette.trampleStage(entry, stage)
            if lower ~= nil then
                self:placeFoliageInQuad(self.foliagePalette:getWriteName(entry, lower), x0, z0, x1, z1, x2, z2)
            else
                self:placeFoliageInQuad(GRASS_LOW_WRITE, x0, z0, x1, z1, x2, z2)
                FSDensityMapUtil.clearDecoArea(x0, z0, x1, z1, x2, z2)
            end
        end
    end
end

-- iw-map.xml <groundMapping> drives this when present (real texture layer
-- weights + optional "also plant this foliage" chance), falling back to
-- the hardcoded TYRE_PAINT_PALETTES 90/10 split with no foliage chance
-- when absent - same backward-compat shape the foliage palette already
-- uses. The Settings-page toggle itself is unchanged either way, only
-- which source supplies the toggle's two options' actual content.
function ImmersiveWeathering:paintWitherMaterial(x, z)
    local index = self.config:getTyrePaintPaletteIndex()
    local set, groundEntry = self:activeTextureSet()
    if set == nil then
        groundEntry = self.foliagePalette:findGroundEntry(TYRE_PAINT_PALETTE_NAMES[index])
    end

    local materialName
    if groundEntry ~= nil then
        -- Mutation check first, same as foliage's own mutatesTo switching
        -- identity entirely rather than just picking a different texture
        -- within the same entry - a successful mutation (e.g. dirt->mud
        -- while raining) means the REST of this function operates on the
        -- target entry's own textures, not the original's.
        local mutatedName = self.foliagePalette:rollGroundMutation(groundEntry)

        if mutatedName ~= nil then
            local mutatedEntry = self.foliagePalette:findGroundEntry(mutatedName)

            if mutatedEntry ~= nil then
                groundEntry = mutatedEntry
            end
        end

        materialName = self.foliagePalette:pickGroundTexture(groundEntry)
    else
        if set ~= nil then
            materialName = IWTextureSets.pick(set, math.random)
        else
            materialName = pickPaintMaterial(TYRE_PAINT_PALETTES[index].entries)
        end
    end

    if materialName == nil then
        return false
    end

    local layerId = self:getTerrainLayerIdByName(materialName)
    if layerId == nil then
        return false
    end

    self:paintTerrainAtLayer(x, z, layerId)
    if self.wearSpots ~= nil then
        self.wearSpots:add(x, z)                       -- (remembered: every weathering pass visits it and may grow grass back)
    end

    if groundEntry ~= nil then
        local foliageEntryName = self.foliagePalette:rollGroundFoliage(groundEntry)

        if foliageEntryName ~= nil then
            local foliageEntry = self.foliagePalette:findEntry(foliageEntryName)

            if foliageEntry ~= nil then
                local stage = self.foliagePalette:pickInitialStage(foliageEntry)
                local writeName = self.foliagePalette:getWriteName(foliageEntry, stage)
                self:placeFoliage(x, z, writeName)
            end
        end
    end

    return true, materialName
end

-- Paints GRASS across a seeder's actual working swath instead of just
-- the wheel's own narrow contact point - reads the vehicle's own
-- <workAreas><workArea><area startNode=.../></workArea></workAreas>
-- geometry (confirmed real tonight against two vehicle XMLs: amazone/
-- precea4500 and FS25_HandPushableToolsPack's handSeeder_PL), the same
-- three named nodes every ground-effect implement uses to define its
-- work rectangle - start, plus a width-direction node and a height/
-- length-direction node. Read-only: just getWorldTranslation on nodes
-- that already exist, nothing hooked or wrapped, so a wrong field name
-- just returns nil harmlessly (falls back to the caller's own single-
-- point paint) instead of corrupting anything the way guessing at
-- processSowingMachineArea's return contract did earlier tonight.
-- Field names (spec_workArea.workAreas[i].start/.width/.height) are
-- still unverified convention, not confirmed from source - pcall-wrapped
-- at the call site for exactly that reason.
--
-- Confirmed wrong in practice: a combined disc/seeder implement has a
-- cultivator work area AND a sowing work area, both using the same
-- <area startNode=.../> schema - matching on start/width/height alone
-- grabbed whichever came first (the disc section), painting the wrong
-- swath entirely. Now requires workArea.type to positively match
-- WorkAreaType.SOWINGMACHINE - if that global/member name turns out to
-- be wrong, type just never matches anything, and this safely falls
-- through to the caller's single-point fallback rather than guessing at
-- "probably the first one".
-- Terrain-only wasn't quite the final word - texture alone reads as bare
-- dirt with a green tint until real foliage grows in on its own, which
-- takes a nightly sweep or more. Placing short grass makes it read as
-- sown immediately, same as the real effect. Scoped to genuinely empty
-- spots only (getFoliageNameAt == nil) - not a blanket placeFoliage call,
-- so it still never overwrites/replaces whatever's already growing there
-- (a bush, existing deco, ...), matching "just want to replace dirt with
-- grass" from earlier, extended to "and grass where there's nothing yet".
-- Palette-driven: places whatever entry is flagged seeder="true" in the
-- current map's iw-map.xml (or the built-in grassShort default), at its
-- configured seederLevel, instead of hardcoding grassShort.
function ImmersiveWeathering:sowGrassFoliageIfEmpty(x, z)
    if self:getFoliageNameAt(x, z) == nil then
        local entry = self.foliagePalette:getSeederEntry()
        local writeName = self.foliagePalette:getWriteName(entry, entry.seederLevel)
        self:placeFoliage(x, z, writeName)
    end
end

function ImmersiveWeathering:sowGrassAcrossWorkArea(vehicle, layerId)
    local spec = vehicle.spec_workArea
    if spec == nil or spec.workAreas == nil then
        return false
    end

    if WorkAreaType == nil or WorkAreaType.SOWINGMACHINE == nil then
        return false
    end

    for _, workArea in ipairs(spec.workAreas) do
        local startNode = workArea.start
        local widthNode = workArea.width
        local heightNode = workArea.height

        if workArea.type == WorkAreaType.SOWINGMACHINE
            and startNode ~= nil and widthNode ~= nil and heightNode ~= nil
        then
            local sx, _, sz = getWorldTranslation(startNode)
            local wx, _, wz = getWorldTranslation(widthNode)
            local hx, _, hz = getWorldTranslation(heightNode)

            local widthVecX, widthVecZ = wx - sx, wz - sz
            local heightVecX, heightVecZ = hx - sx, hz - sz

            local widthLen = math.sqrt(widthVecX * widthVecX + widthVecZ * widthVecZ)
            local heightLen = math.sqrt(heightVecX * heightVecX + heightVecZ * heightVecZ)

            -- A ridgemarker/other non-area workArea could in principle
            -- still have odd leftover fields - a sane swath is at most a
            -- few metres each way, anything wildly larger is a sign this
            -- isn't the geometry we think it is, so skip rather than
            -- paint half the map.
            if widthLen > 0.05 and widthLen < 20 and heightLen > 0.05 and heightLen < 20 then
                local widthSteps = math.max(1, math.floor(widthLen / AREA_FILL_STEP))
                local heightSteps = math.max(1, math.floor(heightLen / AREA_FILL_STEP))

                for i = 0, widthSteps do
                    local tWidth = i / widthSteps
                    for j = 0, heightSteps do
                        local tHeight = j / heightSteps
                        local px = sx + widthVecX * tWidth + heightVecX * tHeight
                        local pz = sz + widthVecZ * tWidth + heightVecZ * tHeight

                        if not self:isOnField(px, pz) and self:isSpotClearForFoliage(px, pz) then
                            self:paintTerrainAtLayer(px, pz, layerId)
                            self:sowGrassFoliageIfEmpty(px, pz)
                        end
                    end
                end

                return true
            end
        end
    end

    return false
end

-- Mirrors the clusters spread mechanic in applyFoliageTransitions but one
-- layer down - terrain material instead of deco foliage. Grass reclaims
-- an adjacent dirt/gravel patch over time, so tyre-withered ground (or
-- any dirt/gravel) slowly grows
-- back in from the edges instead of staying scarred forever. Same
-- sample-then-check-a-neighbor shape as applyFoliageTransitions, kept as
-- its own function since it operates on a completely different system
-- (terrain texture paint, not the density-map foliage layer).
-- One worn spot of a pass: healed (grass painted back) with a chance that rises with the grass around it, forgotten when it is no longer bare ground of ours to heal (grass again, or a road, a field...).
function ImmersiveWeathering:processWearSpot(spot, stats)
    local deps = self:classDeps()
    local material = deps.material(spot.x, spot.z)
    if not BARE_MATERIALS[material] then
        self.wearSpots:remove(spot)                              -- (grass already, or ground that is not dirt, gravel or sand any more)
        stats.wearForgotten = (stats.wearForgotten or 0) + 1
        return
    end
    local class = IWClass.classify(spot.x, spot.z, deps)
    if class ~= IWClass.BARE then
        self.wearSpots:remove(spot)                              -- (it turned into a road, a field, a yard under a roof: not ours)
        stats.wearForgotten = (stats.wearForgotten or 0) + 1
        return
    end
    if (stats.healed or 0) >= WEAR_HEAL_MAX_PER_PASS then
        return
    end
    local share = IWClass.grassShare(spot.x, spot.z, deps)
    if share < WEAR_HEAL_MIN_SHARE or math.random() > WEAR_HEAL_BASE_CHANCE * share * share then
        return
    end
    local layerId = self:getTerrainLayerIdByName("GRASS")
    if layerId == nil then
        return
    end
    self:paintTerrainAtLayer(spot.x, spot.z, layerId)
    self.wearSpots:remove(spot)
    stats.healed = (stats.healed or 0) + 1
end

-- Grass grows back IN from the sides: a sampled spot of bare ground (dirt, gravel or sand that is no road, building, field or forest: a rut, a trail, a yard) is painted grass with a chance that rises with
-- how grassy the ground around it is (IWClass.grassShare). A rut in a meadow reads near 1 and heals quickly; the border of a parking lot half that; the middle of a yard or a dirt field 0 and never. At most
-- TERRAIN_REGROWTH_MAX_SHARE_MIN of the ring is needed at all, and a pass paints at most TERRAIN_REGROWTH_MAX_PER_PASS spots (each is a terrain deformation).
function ImmersiveWeathering:applyTerrainRegrowth(x, z, stats, force)
    if not force and (stats.regrown or 0) >= TERRAIN_REGROWTH_MAX_PER_PASS then
        return
    end
    local deps = self:classDeps()
    local material = deps.material(x, z)
    if not BARE_MATERIALS[material] then
        return                                              -- (the common case, one read: not bare ground)
    end
    if IWClass.classify(x, z, deps) ~= IWClass.BARE then
        return
    end
    local share = IWClass.grassShare(x, z, deps)
    if share < TERRAIN_REGROWTH_MIN_SHARE then
        return
    end
    if not (force or math.random() <= TERRAIN_REGROWTH_BASE_CHANCE * share * share) then
        return
    end
    local layerId = self:getTerrainLayerIdByName("GRASS")
    if layerId == nil then
        return
    end
    self:paintTerrainAtLayer(x, z, layerId)
    stats.regrown = (stats.regrown or 0) + 1
    debugPrintf("[Regrowth] grass back at (%.2f %.2f), grass share around it %.2f", x, z, share)
end

-- One pass over a wheel's contact patches, deciding independently per node
-- whether to clear foliage outright (doClear, rolled once per update by the
-- caller), wither grass texture back to dirt, or displace existing deco
-- foliage with a fresh grass patch. Displace is gated on foliage already
-- being present so it never paints a grass trail behind the vehicle across
-- bare paths - and skips ground that's already grass, since overwriting
-- grass with grass is a no-op. Both new actions respect the same field
-- exclusion as everything else in this file.
-- WheelDestruction.update fires once per wheel, independently - a 4-wheel
-- tractor rolls every chance below 4 times per contact tick, an 8-wheel
-- articulated truck 8 times. Without this, the dial's percentage was a
-- lie: "20%" behaved like a much higher aggregate chance once you account
-- for every wheel getting its own independent roll, which is exactly why
-- driving anywhere looked like carpet-bombing dirt patches regardless of
-- what the dial said. Dividing by wheel count keeps the dial's number
-- roughly honest as "chance this happens somewhere on this pass",
-- independent of how many wheels are doing the rolling.
function ImmersiveWeathering:getVehicleWheelCount(vehicle)
    local wheels = vehicle.spec_wheels ~= nil and vehicle.spec_wheels.wheels or nil
    if wheels == nil or #wheels == 0 then
        return 1
    end
    return #wheels
end

-- Player-facing strength for how much wheelCount discounts chance - see
-- WHEEL_SENSITIVITY_LEVELS' own comment. Linear blend between "no
-- discount at all" (1) and "today's full linear division" (wheelCount)
-- rather than an exponent, so the dial's percentage reads the same
-- intuitive way the wither-chance dial already does.
function ImmersiveWeathering:getEffectiveWheelCount(wheelCount)
    local sensitivity = WHEEL_SENSITIVITY_LEVELS[self.config:getWheelSensitivityIndex()] or 1.0
    return 1 + (wheelCount - 1) * sensitivity
end

function ImmersiveWeathering:isVerboseLoggingEnabled()
    local enabled = VERBOSE_LOGGING_LEVELS[self.config:getVerboseLoggingIndex()]
    if enabled == nil then
        return true
    end
    return enabled
end

-- What a tyre or a roller drum leaves on the ground under the parallelogram (x1, z1 is its origin, see IWPaintCells.cellsIn): a path is repainted with the active set, stone and sand when the set may, grass is worn.
function ImmersiveWeathering:paintContactOnGround(x0, z0, x1, z1, x2, z2, centerX, centerZ, owner, rolling, wheelCount)
    local activeSet = self:activeTextureSet()
    -- what the set does to the foliage of the texels it painted: a growth stage a pass, gone at once (the whole area in one go: the per-cell budget cannot keep up with a wide roller), or nothing
    local function foliage(painted, hits)
        local mode = IWTextureSets.foliageMode(activeSet)
        if mode == "clear" then
            if painted > 0 then
                self:wipeFoliageQuad(x0, z0, x1, z1, x2, z2)
            end
        else
            self:trampleCells(hits)
        end
    end

    -- Repaints a path with the active set once per texel (and again when the set changes): the roller's job, and every tyre's.
    if self:fieldIsMaterial(centerX, centerZ, TERRAIN_REGROWTH_TARGETS) then
        local painted, hits = self:paintTyreContact(x0, z0, x1, z1, x2, z2, centerX, centerZ, nil, owner, rolling, wheelCount)
        foliage(painted, hits)
        if painted > 0 and self:isVerboseLoggingEnabled() then
            debugPrintf("[TyrePaint] %d texel(s) repainted on a path at (%.2f %.2f)", painted, centerX, centerZ)
        end
    end

    -- A set that may go over stone or sand: the gate (road / building, a few bitmap reads) is only asked when the contact has new texels. (It used to leave the foliage standing: nothing here dealt with it.)
    if activeSet ~= nil and activeSet.force and self:fieldIsMaterial(centerX, centerZ, FORCE_MATERIALS) then
        local painted, hits = self:paintTyreContact(x0, z0, x1, z1, x2, z2, centerX, centerZ, function() return not self:isRoadOrBuilding(centerX, centerZ) end, owner, rolling, wheelCount)
        foliage(painted, hits)
    end

    -- Grass under a tyre becomes path: every texel under the contact patch, once.
    if self:fieldIsMaterial(centerX, centerZ, GRASS_MATERIAL_ONLY) then
        -- the gate (a raycast) is only asked when the contact has new texels to paint
        local painted, hits = self:paintTyreContact(x0, z0, x1, z1, x2, z2, centerX, centerZ, function() return self:isSpotClearForFoliage(centerX, centerZ) end, owner, rolling, wheelCount)
        foliage(painted, hits)
        if painted > 0 and self:isVerboseLoggingEnabled() then
            debugPrintf("[TyreWither] %d texel(s) painted over grass at (%.2f %.2f)", painted, centerX, centerZ)
        end
    end
end

-- Clear, wither, and displace used to be three independent rolls against
-- the same spot - meaning even at "20%" each, the real chance that
-- SOMETHING happened to a given contact patch was close to
-- 1-(0.8*0.8*0.8) ~= 49%, not 20%. One roll now decides at most one
-- outcome per contact node, same mutually-exclusive weighted-pick shape
-- as the palette's own growth roll elsewhere in this file - the dial's percentage
-- now actually means "chance this specific thing happens on this pass",
-- not "chance this thing happens, ignoring whatever else might also fire
-- on the same roll".
function ImmersiveWeathering:processWheelContact(wheelDestruction, wheelCount)
    local wheel = wheelDestruction.wheel

    if wheel.physics.contact ~= WheelContactType.GROUND then
        return
    end

    -- a roller lays the texture itself; the tyres of what pulls it do not paint (their wear on the grass is the roller's job too)
    local rolling = IWPaintCells.isRoller(wheelDestruction.vehicle)
    local carriesRoller = not rolling and IWPaintCells.carriesRoller(wheelDestruction.vehicle)

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

        -- A seeder's wheels "sow" grass instead of running the normal
        -- wither/clear/displace tyre logic - reuses this same wheel-
        -- contact hook that's been safe all night, rather than the real
        -- SowingMachine.processSowingMachineArea (tried, broke real
        -- seeders: its return value mattered to the engine's own
        -- WorkArea loop, and nothing here calls into or wraps anything
        -- the engine depends on, so there's nothing to get wrong that
        -- way). Off-field only - a real seeder actually sowing a real
        -- crop on a real field shouldn't also get grass painted
        -- underneath it. Terrain material only, no placeFoliage call -
        -- this replaces bare dirt with grass, it doesn't touch whatever
        -- deco (bushes, clutter, ...) might already be standing there.
        if wheelDestruction.vehicle.spec_sowingMachine ~= nil then
            local seederVehicle = wheelDestruction.vehicle

            -- isWorking (spec_sowingMachine), confirmed via a live field
            -- dump, is the real signal on an actual working seeder
            -- (Amazone Citan 15001-C) - not the tractor's engine (nearly
            -- always on while driving, meaningless as a gate), not the
            -- implement's own generic getIsTurnedOn, getIsLowered, or
            -- getIsUnfolded (all confirmed uncorrelated with whether it's
            -- actually sowing).
            --
            -- But confirmed via two more dumps spanning both fold states
            -- that isWorking never goes true on FS25_HandPushableToolsPack's
            -- hand-pushed implements at all - not a timing fluke, it's
            -- categorically false for this vehicle type regardless of
            -- what you do with it. Those declare a real, dedicated
            -- <specialization name="pushHandTool"/> (confirmed straight
            -- from that pack's own modDesc.xml) - simplest correct
            -- answer is to treat "it's a hand tool" as its own always-on
            -- case, since there's no meaningful activation state to gate
            -- on at all: you're either pushing it (wheels grounded,
            -- already required above) or you're not.
            --
            -- isWorking alone isn't enough for a real sowing machine
            -- though - it fires for ANY loaded seed, so a wheat drill
            -- driven over bare ground for testing got the exact same
            -- grass treatment as an actual pasture seeder. Real hand
            -- tools skip this check entirely - they're dedicated grass
            -- tools with no crop selection to get wrong.
            local seederIsOn = seederVehicle.spec_pushHandTool ~= nil
                or (seederVehicle.spec_sowingMachine.isWorking == true
                    and self:isSeederLoadedWithAllowedFruitType(seederVehicle))

            local layerId = nil
            if seederIsOn then
                layerId = self:getSeederTerrainLayerId()
            end

            if layerId ~= nil then
                local success, coveredWorkArea = pcall(self.sowGrassAcrossWorkArea, self, seederVehicle, layerId)
                if not success or not coveredWorkArea then
                    if not self:isOnField(centerX, centerZ) and self:isSpotClearForFoliage(centerX, centerZ) then
                        self:paintTerrainAtLayer(centerX, centerZ, layerId)
                        self:sowGrassFoliageIfEmpty(centerX, centerZ)
                    end
                end
            end
        else

        -- Lawnmower: a tyre on a road wipes what grows there. Not behind the Shift+T toggle.
        if self:getFoliageNameAt(centerX, centerZ) ~= nil and self:classAt(centerX, centerZ) == IWClass.ROAD then
            self:wipeFoliageSquare(centerX, centerZ, ROAD_WIPE_HALF_M)
        end

        -- Everything below this point is the wither/material-drift/
        -- displace/clear side of tyre effects, gated by the player's own
        -- Shift+T toggle - unlike the seeder branch above, which is
        -- deliberately independent of it (see onWheelDestructionUpdate's
        -- own comment on why).
        if not self.config:isTyreEffectsEnabled() then
            return
        end

        if not carriesRoller then
            self:paintContactOnGround(x0, z0, x1, z1, x2, z2, centerX, centerZ, wheelDestruction.vehicle, rolling, wheelCount)
        end

        if not self:isOnField(centerX, centerZ)
            and not self:fieldIsMaterial(centerX, centerZ, TERRAIN_REGROWTH_TARGETS)
            and math.random() <= TYRE_DISPLACE_CHANCE / self:getEffectiveWheelCount(wheelCount)
        then
            local currentName = self:getFoliageNameAt(centerX, centerZ)

            -- Only an actual bush counts as "something to displace" -
            -- currentName ~= GRASS_LOW_READ used to be the whole guard,
            -- which also matched plain "meadow"/"forestGrass" ambient
            -- ground cover (basically everywhere off-field), scattering
            -- redundant grass on top of paths instead of only clearing
            -- real deco bushes. Still wasn't enough on its own - an
            -- established dirt/gravel road with roadside bush deco is
            -- also "off-field", so a truck driving straight down one hit
            -- displace on every bush along the way, sprouting a steady
            -- row of fresh grass down the middle of what's supposed to
            -- read as a worn road. Excluding TERRAIN_REGROWTH_TARGETS
            -- here means displace only touches bushes standing on
            -- untouched ground, not ground already part of a path.
            if currentName == BUSH then
                if self:placeFoliage(centerX, centerZ, GRASS_LOW_WRITE) and self:isVerboseLoggingEnabled() then
                    debugPrintf(
                        "[TyreDisplace] %s -> grass at (%.2f %.2f)",
                        currentName,
                        centerX,
                        centerZ
                    )
                end
            end
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

    -- Deliberately NOT gated on isTyreEffectsEnabled() here - that toggle
    -- only covers the wither/material-drift/displace/clear branch
    -- (processWheelContact's own else branch below), not the real-seeder
    -- branch. A player wanting to fill in bare ground with a seeder
    -- shouldn't have it constantly re-destroyed by their own tractor's
    -- front wheels just because tyre effects happen to be off - the
    -- seeder already has its own real on/off (isWorking/pushHandTool),
    -- no separate enable needed on our end.
    local vehicle = wheelDestruction.vehicle

    -- WheelDestruction.update fires for every vehicle's wheels, hired AI
    -- workers included, since it has no notion of who's driving. Not a
    -- player-facing toggle - AI pathing is erratic enough (snake lines
    -- from a tractor "practicing driving straight") that letting it touch
    -- terrain/foliage was never going to look intentional. Player-only
    -- for now, full stop.
    if vehicle.getIsAIActive ~= nil and vehicle:getIsAIActive() then
        return
    end

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
        -- chatty (a line per wheel contact flip): only while WAILA's shared
        -- debug-log switch is on (WAILA hub, General tab). Without WAILA, silent.
        local waila = g_currentMission ~= nil and g_currentMission.waila or nil
        if waila ~= nil and waila.isDebugLogEnabled ~= nil and waila.isDebugLogEnabled() then
            debugPrintf("[TyreDebug] wheel contact -> %s at (%.2f %.2f)", tostring(isGrounded), x, z)
        end
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

    local wheelCount = self:getVehicleWheelCount(vehicle)
    self:processWheelContact(wheelDestruction, wheelCount)
end

-- A roller rolls its work areas (start / width / height nodes), and a drum may have no physics wheel at all (the middle of a wide roller): the area lays the set just like a wheel's contact does, in pieces of
-- at most ROLLER_SLICE_M across so that what lies under each piece decides for it.
local ROLLER_SLICE_M = 2
function ImmersiveWeathering:onRollerArea(vehicle, workArea)
    local sx, _, sz = getWorldTranslation(workArea.start)
    local wx, _, wz = getWorldTranslation(workArea.width)
    local hx, _, hz = getWorldTranslation(workArea.height)
    local ax, az, bx, bz = wx - sx, wz - sz, hx - sx, hz - sz
    local slices = math.max(1, math.ceil(math.sqrt(ax * ax + az * az) / ROLLER_SLICE_M))
    for k = 0, slices - 1 do
        local u0, u1 = k / slices, (k + 1) / slices
        local x1, z1 = sx + ax * u0, sz + az * u0                       -- the piece: origin, along the width by 1 / slices, along the height
        local x0, z0 = sx + ax * u1, sz + az * u1
        local x2, z2 = x0 + bx, z0 + bz
        self:paintContactOnGround(x0, z0, x1, z1, x2, z2, (x1 + x2) * 0.5, (z1 + z2) * 0.5, vehicle, true, 1)
    end
end

-- Roller.onEndWorkAreaProcessing is an event listener (nothing of its result is read), unlike processRollerArea, whose result the engine uses and which only runs on land the farm owns: the roads are not.
function ImmersiveWeathering:onRollerEndProcessing(vehicle)
    if g_server == nil or self.config == nil or not self.config:isTyreEffectsEnabled() then
        return
    end
    local areas = vehicle.spec_workArea ~= nil and vehicle.spec_workArea.workAreas or nil
    if areas == nil or vehicle:getLastSpeed() < 0.5 or (vehicle.getIsAIActive ~= nil and vehicle:getIsAIActive()) then
        return
    end
    for _, workArea in ipairs(areas) do
        if workArea.type == WorkAreaType.ROLLER and workArea.start ~= nil and workArea.width ~= nil and workArea.height ~= nil and vehicle:getIsWorkAreaActive(workArea) then
            self:onRollerArea(vehicle, workArea)
        end
    end
end

if Roller ~= nil and Roller.onEndWorkAreaProcessing ~= nil then
    Roller.onEndWorkAreaProcessing = Utils.appendedFunction(Roller.onEndWorkAreaProcessing, function(vehicle)
        ImmersiveWeathering:onRollerEndProcessing(vehicle)
    end)
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

-- ============================================================
-- Seeder-on-meadow - reverted
-- ============================================================

-- Tried hooking SowingMachine.processSowingMachineArea via
-- Utils.appendedFunction (real function name, confirmed against two
-- real vehicle XMLs - amazone/precea4500 and FS25_HandPushableToolsPack's
-- handSeeder_PL, both declaring <workArea type="sowingMachine"
-- functionName="processSowingMachineArea">). Broke real seeders on
-- first test: "WorkArea.lua:278: attempt to compare number < nil",
-- spamming every frame. Root cause: this function's return value
-- (changedArea/totalArea, same shape sowFruit already returns) is read
-- by the engine's own WorkArea update loop right after the call -
-- appendedFunction runs both the original and our function for their
-- side effects but returns neither's result, so every call started
-- returning nil where the engine expected a number. Our own pcall only
-- protected our side of the hook, not the engine's subsequent use of
-- the now-missing return value, so it corrupted that workArea's state
-- for the rest of the session regardless.
--
-- The real fix would be Utils.overwrittenFunction instead - call the
-- original via superFunc, capture and explicitly return its real
-- result, and do our own thing as a side effect in between. Not
-- attempting that live tonight after breaking a real vehicle once
-- already; needs verifying the actual return contract first (ideally
-- with real source access, not another guess) before trying again.
