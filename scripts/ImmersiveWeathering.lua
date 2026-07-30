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

local GRASS_MATERIAL_ONLY = { [MATERIAL.GRASS] = true }

-- Wither intensity is a player-facing dial, not a fixed constant - 0 means
-- "never", 1.0 means "paint a straight road", everything between is
-- naturalistic wear. Cycled with a debug key the same way TerraFarm's own
-- machine tools step through settings one keypress at a time.
local TYRE_WITHER_LEVELS = {0.0, 0.2, 0.4, 0.6, 0.8, 1.0}
local TYRE_WITHER_DEFAULT_INDEX = 2

-- Rolled fresh per stamp instead of one fixed material, for a mottled,
-- naturalistic look rather than a flat single-texture road - but still
-- player-directed, since "some naturalistic blend" and "I'm building a
-- dirt road, not a gravel one" are both real things to want. Toggle picks
-- which one dominates; the 10% off-material is what keeps it from looking
-- like a flat single-texture stamp either way. Same weighted-pick shape as
-- pickWeightedAction below, just a different domain, so kept as its own
-- tiny helper rather than forcing one function to serve both.
local TYRE_PAINT_PALETTES = {
    {label = "DIRT",   entries = {{weight = 0.9, name = "DIRT"},   {weight = 0.1, name = "GRAVEL"}}},
    {label = "GRAVEL", entries = {{weight = 0.9, name = "GRAVEL"}, {weight = 0.1, name = "DIRT"}}},
}
local TYRE_PAINT_PALETTE_DEFAULT_INDEX = 1

-- How many random coordinates each day-change sweep samples - was a fixed
-- local before, now a toggle so a denser sweep can be tested without
-- editing code (heavier, but the sweep is off the main thread's hot path
-- anyway - it's a once-per-day-change batch, not per-frame).
local SWEEP_SAMPLE_COUNTS = {1000, 2000, 4000, 6000, 8000, 10000}
local SWEEP_SAMPLE_COUNT_DEFAULT_INDEX = 1

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

-- Same clustering idea, one layer down: terrain texture instead of deco
-- foliage. A sampled grass-material spot has a chance to reclaim one
-- dirt/gravel neighbor back to grass - this is what lets tyre-withered
-- paths grow back in from the edges if left unused, mirroring
-- FOLIAGE_SPREAD_RULES's shape rather than its table (keyed by material,
-- not foliage name, so it doesn't fit the same table without forcing it).
local TERRAIN_REGROWTH_CHANCE = 0.5 -- temp bumped for testing, dial back down once regrowth is confirmed working
local TERRAIN_REGROWTH_TARGETS = { [MATERIAL.DIRT] = true, [MATERIAL.GRAVEL] = true }

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

    self.tyreEffectsEnabled = true
    self.tyreWitherLevelIndex = TYRE_WITHER_DEFAULT_INDEX
    self.tyrePaintPaletteIndex = TYRE_PAINT_PALETTE_DEFAULT_INDEX
    self.sweepSampleCountIndex = SWEEP_SAMPLE_COUNT_DEFAULT_INDEX

    self:refreshTyreEffectsLabel()
    self:refreshTyreWitherLabel()
    self:refreshTyrePaintBiasLabel()

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
local HUD_PANEL_WIDTH = 0.19
local HUD_PANEL_GAP = 0.010
local HUD_PANEL_HEADER_HEIGHT = 0.026
local HUD_PANEL_BODY_HEIGHT = 0.072
local HUD_PANEL_HEIGHT = HUD_PANEL_HEADER_HEIGHT + HUD_PANEL_BODY_HEIGHT
local HUD_SHADOW_OFFSET = 0.004
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
    local material = TYRE_PAINT_PALETTES[self.tyrePaintPaletteIndex].label
    local witherChance = self:getTyreWitherChance()

    return {
        title = "TYRE WITHERING",
        headerValue = self.tyreEffectsEnabled and "Enabled" or "Disabled",
        headerKeybind = getActionKeyLabel("IW_TOGGLE_TYRE_EFFECTS", "[Shift+T]"),
        headerColor = self.tyreEffectsEnabled and {0.25, 0.75, 0.25} or {0.75, 0.25, 0.25},
        cells = {
            {
                label = "Texture",
                keybind = getActionKeyLabel("IW_TOGGLE_PAINT_BIAS", "[Shift+V]"),
                value = material,
                color = material == "DIRT" and {0.55, 0.35, 0.15} or {0.55, 0.55, 0.55},
            },
            {
                label = "Chance",
                keybind = getActionKeyLabel("IW_CYCLE_WITHER_CHANCE", "[Shift+B]"),
                value = string.format("%d%%", witherChance * 100),
                color = {0.85, 0.75, 0.15},
            },
        },
    }
end

local function buildSweepPanel(self)
    return {
        title = "NIGHTLY WEATHERING LOOPS",
        headerValue = nil,
        cells = {
            {
                label = "Samples",
                keybind = getActionKeyLabel("IW_TOGGLE_SAMPLE_COUNT", "[Shift+I]"),
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

    drawFilledRect(
        left + HUD_SHADOW_OFFSET, panelBottom - HUD_SHADOW_OFFSET,
        HUD_PANEL_WIDTH, HUD_PANEL_HEIGHT,
        0, 0, 0, 0.45
    )
    drawFilledRect(left, panelBottom, HUD_PANEL_WIDTH, HUD_PANEL_HEIGHT, 0, 0, 0, 0.65)

    setTextAlignment(RenderText.ALIGN_LEFT)
    setTextColor(1, 1, 1, 1)
    setTextBold(true)
    renderText(left + 0.008, HUD_TOP - 0.017, HUD_TITLE_SIZE, panel.title)
    setTextBold(false)

    if panel.headerValue ~= nil then
        setTextAlignment(RenderText.ALIGN_RIGHT)
        setTextColor(panel.headerColor[1], panel.headerColor[2], panel.headerColor[3], 1)
        renderText(left + HUD_PANEL_WIDTH - 0.008, HUD_TOP - 0.017, HUD_LABEL_SIZE, panel.headerValue)
        setTextColor(0.65, 0.65, 0.65, 1)
        renderText(left + HUD_PANEL_WIDTH - 0.008, HUD_TOP - 0.028, HUD_KEYBIND_SIZE, panel.headerKeybind)
    end

    drawFilledRect(left, HUD_TOP - HUD_PANEL_HEADER_HEIGHT, HUD_PANEL_WIDTH, 0.001, 0, 0, 0, 0.7)

    local bodyTop = HUD_TOP - HUD_PANEL_HEADER_HEIGHT
    local cellWidth = HUD_PANEL_WIDTH / #panel.cells

    setTextAlignment(RenderText.ALIGN_LEFT)

    for index, cell in ipairs(panel.cells) do
        local cellLeft = left + (index - 1) * cellWidth
        local textLeft = cellLeft + 0.008

        setTextColor(1, 1, 1, 1)
        renderText(textLeft, bodyTop - 0.018, HUD_LABEL_SIZE, cell.label)

        setTextColor(0.65, 0.65, 0.65, 1)
        renderText(textLeft, bodyTop - 0.030, HUD_KEYBIND_SIZE, cell.keybind)

        if cell.value ~= nil then
            local swatchBottom = panelBottom + 0.014

            drawFilledRect(textLeft, swatchBottom, HUD_SWATCH_SIZE, HUD_SWATCH_SIZE, cell.color[1], cell.color[2], cell.color[3], 1)

            setTextColor(1, 1, 1, 1)
            renderText(textLeft + HUD_SWATCH_SIZE + 0.006, swatchBottom + 0.004, HUD_VALUE_SIZE, cell.value)
        end
    end
end

function ImmersiveWeathering:draw()
    if self.tyreEffectsEnabled == nil then
        return
    end

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
                InputAction.IW_TOGGLE_SAMPLE_COUNT,
                ImmersiveWeathering.onToggleSampleCountPressed,
                "toggle sample count"
            )

            ImmersiveWeathering.tyreEffectsActionEventId = registerDebugAction(
                InputAction.IW_TOGGLE_TYRE_EFFECTS,
                ImmersiveWeathering.onToggleTyreEffectsPressed,
                "toggle tyre effects"
            )
            ImmersiveWeathering:refreshTyreEffectsLabel()

            ImmersiveWeathering.tyreWitherActionEventId = registerDebugAction(
                InputAction.IW_CYCLE_WITHER_CHANCE,
                ImmersiveWeathering.onCycleWitherChancePressed,
                "cycle wither chance"
            )
            ImmersiveWeathering:refreshTyreWitherLabel()

            ImmersiveWeathering.tyrePaintBiasActionEventId = registerDebugAction(
                InputAction.IW_TOGGLE_PAINT_BIAS,
                ImmersiveWeathering.onTogglePaintBiasPressed,
                "toggle paint bias"
            )
            ImmersiveWeathering:refreshTyrePaintBiasLabel()
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

function ImmersiveWeathering:onPlaceTestRigPressed(
    actionName,
    inputValue,
    callbackState,
    isAnalog
)
    debugPrint("Immersive Weathering (FS25): place test rig key pressed")

    self:placeFoliageTestRig()
end

function ImmersiveWeathering:onWeatherCrosshairPressed(
    actionName,
    inputValue,
    callbackState,
    isAnalog
)
    debugPrint("Immersive Weathering (FS25): weather crosshair key pressed")
    self:weatherAtCrosshair()
end

function ImmersiveWeathering:onFillAreaPressed(
    actionName,
    inputValue,
    callbackState,
    isAnalog
)
    debugPrint("Immersive Weathering (FS25): fill area key pressed")
    self:placeFoliageAreaFill()
end

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
    if self.tyreEffectsActionEventId == nil or self.tyreEffectsEnabled == nil then
        return
    end
    g_inputBinding:setActionEventText(
        self.tyreEffectsActionEventId,
        string.format("Tyre dmg: %s", self.tyreEffectsEnabled and "ON" or "OFF")
    )
end

function ImmersiveWeathering:refreshTyreWitherLabel()
    if self.tyreWitherActionEventId == nil or self.tyreWitherLevelIndex == nil then
        return
    end
    g_inputBinding:setActionEventText(
        self.tyreWitherActionEventId,
        string.format("Dmg %%: %d%%", self:getTyreWitherChance() * 100)
    )
end

function ImmersiveWeathering:refreshTyrePaintBiasLabel()
    if self.tyrePaintBiasActionEventId == nil or self.tyrePaintPaletteIndex == nil then
        return
    end
    g_inputBinding:setActionEventText(
        self.tyrePaintBiasActionEventId,
        string.format("Dmg mat: %s", TYRE_PAINT_PALETTES[self.tyrePaintPaletteIndex].label)
    )
end

function ImmersiveWeathering:onToggleTyreEffectsPressed(
    actionName,
    inputValue,
    callbackState,
    isAnalog
)
    self.tyreEffectsEnabled = not self.tyreEffectsEnabled
    self:refreshTyreEffectsLabel()
    debugPrintf(
        "Immersive Weathering (FS25): tyre effects (clear/wither/displace) %s",
        self.tyreEffectsEnabled and "ENABLED" or "DISABLED"
    )
end

function ImmersiveWeathering:onCycleWitherChancePressed(
    actionName,
    inputValue,
    callbackState,
    isAnalog
)
    self.tyreWitherLevelIndex = (self.tyreWitherLevelIndex % #TYRE_WITHER_LEVELS) + 1
    self:refreshTyreWitherLabel()
    debugPrintf(
        "Immersive Weathering (FS25): tyre wither chance -> %d%%",
        self:getTyreWitherChance() * 100
    )
end

function ImmersiveWeathering:onTogglePaintBiasPressed(
    actionName,
    inputValue,
    callbackState,
    isAnalog
)
    self.tyrePaintPaletteIndex = (self.tyrePaintPaletteIndex % #TYRE_PAINT_PALETTES) + 1
    self:refreshTyrePaintBiasLabel()
    debugPrintf(
        "Immersive Weathering (FS25): tyre paint palette -> %s (90/10)",
        TYRE_PAINT_PALETTES[self.tyrePaintPaletteIndex].label
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

function ImmersiveWeathering:onToggleSampleCountPressed(
    actionName,
    inputValue,
    callbackState,
    isAnalog
)
    self.sweepSampleCountIndex = (self.sweepSampleCountIndex % #SWEEP_SAMPLE_COUNTS) + 1
    debugPrintf(
        "Immersive Weathering (FS25): sweep sample count -> %d",
        self:getSweepSampleCount()
    )
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
    self:applyTerrainRegrowth(hx, hz, stats, true)

    local after = self:getFoliageNameAt(hx, hz) or EMPTY

    debugPrintf(
        "[Weather] (%.2f %.2f) before=%s after=%s seeded=%d spread=%d weeded=%d fruited=%d regrown=%d",
        hx, hz, before, after,
        stats.seeded or 0, stats.spread or 0, stats.weeded or 0, stats.fruited or 0, stats.regrown or 0
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
            if self:paintWitherMaterial(px, pz) then
                placed = placed + 1
            end
        end
    end

    debugPrintf("[AreaFill] %dx%dm mixed-material paint around (%.2f %.2f): %d/%d stamps placed",
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

    -- spreadCandidates counts every sample that landed on ground the spread
    -- table even cares about (existing grass/bush) - this is the number to
    -- watch if "spread" stays at 0 for a while: it separates "the random
    -- sampler almost never lands back on ground we already planted" (a real
    -- probability problem, 1000 uniform samples across the whole map vs a
    -- small planted footprint) from "it lands there fine but the neighbor
    -- check keeps rejecting" (a logic problem).
    if spreadRule ~= nil then
        stats.spreadCandidates = (stats.spreadCandidates or 0) + 1

        if force or math.random() <= spreadRule.chance then
            local offset = NEIGHBOR_OFFSETS[math.random(#NEIGHBOR_OFFSETS)]
            local nx = x + offset[1] * NEIGHBOR_STEP
            local nz = z + offset[2] * NEIGHBOR_STEP
            local neighborName = self:getFoliageNameAt(nx, nz)

            local canClaimNeighbor =
                neighborName == nil
                or (spreadRule.encroachesOnGrass and neighborName == GRASS_LOW_READ)

            debugPrintf(
                "[Cluster] %s at (%.2f %.2f) -> neighbor (%.2f %.2f) reads %s, claimable=%s",
                name, x, z, nx, nz, tostring(neighborName), tostring(canClaimNeighbor)
            )

            if canClaimNeighbor
                and self:fieldIsMaterial(nx, nz, WEATHERABLE_MATERIALS)
                and self:isSpotClearForFoliage(nx, nz)
                and spreadRule.place(self, nx, nz)
            then
                stats.spread = (stats.spread or 0) + 1
                debugPrintf("[Cluster] spread %s -> (%.2f %.2f) succeeded", name, nx, nz)
            end
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

    local elapsedMs = (getTimeSec() - startTime) * 1000

    debugPrintf(
            "Immersive Weathering (FS25): FINISHED %d samples, seeded=%d spread=%d (candidates=%d) weeded=%d fruited=%d regrown=%d, %.3f ms",
            sampleCount,
            stats.seeded or 0,
            stats.spread or 0,
            stats.spreadCandidates or 0,
            stats.weeded or 0,
            stats.fruited or 0,
            stats.regrown or 0,
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
local TYRE_DISPLACE_CHANCE = 0.15

function ImmersiveWeathering:getTyreWitherChance()
    return TYRE_WITHER_LEVELS[self.tyreWitherLevelIndex]
end

function ImmersiveWeathering:getSweepSampleCount()
    return SWEEP_SAMPLE_COUNTS[self.sweepSampleCountIndex]
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

    local numLayers = getTerrainNumOfLayers(g_terrainNode)
    for i = 0, numLayers - 1 do
        local layerName = getTerrainLayerName(g_terrainNode, i)
        if layerName ~= nil and layerName:upper() == name:upper() then
            self.terrainLayerIdCache[name] = i
            debugPrintf("[TerrainPaint] resolved %s layer id=%d name=%s", name, i, layerName)
            return i
        end
    end

    debugPrintf("[TerrainPaint] no terrain layer named '%s' found on this map", name)
    self.terrainLayerIdCache[name] = false
    return nil
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

function ImmersiveWeathering:paintWitherMaterial(x, z)
    local palette = TYRE_PAINT_PALETTES[self.tyrePaintPaletteIndex]
    local materialName = pickPaintMaterial(palette.entries)
    local layerId = self:getTerrainLayerIdByName(materialName)
    if layerId == nil then
        return false
    end

    self:paintTerrainAtLayer(x, z, layerId)

    return true, materialName
end

-- Mirrors FOLIAGE_SPREAD_RULES but one layer down - terrain material
-- instead of deco foliage. Grass reclaims an adjacent dirt/gravel patch
-- over time, so tyre-withered ground (or any dirt/gravel) slowly grows
-- back in from the edges instead of staying scarred forever. Same
-- sample-then-check-a-neighbor shape as applyFoliageTransitions, kept as
-- its own function since it operates on a completely different system
-- (terrain texture paint, not the density-map foliage layer).
function ImmersiveWeathering:applyTerrainRegrowth(x, z, stats, force)
    if not self:fieldIsMaterial(x, z, GRASS_MATERIAL_ONLY) then
        return
    end

    if not (force or math.random() <= TERRAIN_REGROWTH_CHANCE) then
        return
    end

    local offset = NEIGHBOR_OFFSETS[math.random(#NEIGHBOR_OFFSETS)]
    local nx = x + offset[1] * NEIGHBOR_STEP
    local nz = z + offset[2] * NEIGHBOR_STEP

    if not self:fieldIsMaterial(nx, nz, TERRAIN_REGROWTH_TARGETS) then
        return
    end

    local layerId = self:getTerrainLayerIdByName("GRASS")
    if layerId == nil then
        return
    end

    self:paintTerrainAtLayer(nx, nz, layerId)

    stats.regrown = (stats.regrown or 0) + 1
    debugPrintf(
        "[Regrowth] grass at (%.2f %.2f) reclaimed dirt/gravel neighbor (%.2f %.2f)",
        x, z, nx, nz
    )
end

-- One pass over a wheel's contact patches, deciding independently per node
-- whether to clear foliage outright (doClear, rolled once per update by the
-- caller), wither grass texture back to dirt, or displace existing deco
-- foliage with a fresh grass patch. Displace is gated on foliage already
-- being present so it never paints a grass trail behind the vehicle across
-- bare paths - and skips ground that's already grass, since overwriting
-- grass with grass is a no-op. Both new actions respect the same field
-- exclusion as everything else in this file.
function ImmersiveWeathering:processWheelContact(wheelDestruction, doClear)
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

        if doClear and self:fieldIsMaterial(
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

        local witherChance = self:getTyreWitherChance()
        if witherChance > 0
            and math.random() <= witherChance
            and self:fieldIsMaterial(centerX, centerZ, GRASS_MATERIAL_ONLY)
        then
            local painted, materialName = self:paintWitherMaterial(centerX, centerZ)
            if painted then
                debugPrintf(
                    "[TyreWither] grass -> %s at (%.2f %.2f)",
                    materialName,
                    centerX,
                    centerZ
                )
            end
        end

        if math.random() <= TYRE_DISPLACE_CHANCE and not self:isOnField(centerX, centerZ) then
            local currentName = self:getFoliageNameAt(centerX, centerZ)

            if currentName ~= nil and currentName ~= GRASS_LOW_READ then
                if self:placeFoliage(centerX, centerZ, GRASS_LOW_WRITE) then
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

function ImmersiveWeathering:onWheelDestructionUpdate(
    wheelDestruction,
    dt,
    allowFoliageDestruction
)
    -- Density-map changes belong on the server.
    if g_server == nil then
        return
    end

    if not self.tyreEffectsEnabled then
        return
    end

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

    self:processWheelContact(wheelDestruction, math.random() <= TYRE_CLEAR_CHANCE)
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
