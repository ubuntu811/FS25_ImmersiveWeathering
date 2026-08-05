-- Injects the 3 tune-and-forget dials (wither chance, texture bias, sweep
-- sample count) into the real ESC -> Settings -> Game Settings page,
-- instead of a custom-built overlay. Confirmed real, current pattern -
-- pulled directly from FS25_AdditionalContracts's own UIGameSettings.lua
-- (a mod actually installed and confirmed rendering real settings
-- controls), not guessed. UIHelper (scripts/UIHelper.lua, vendored
-- verbatim from that same mod, its own license permits reuse) is a
-- community utility class, NOT a base-game class - every mod that wants
-- this has to ship its own copy, which is why nothing rendered at all
-- before that file existed.
--
-- self.controls MUST be initialized before calling
-- UIHelper.createControlsDynamically - it does
-- `owningTable.controls[1] = owningTable.sectionTitle` immediately,
-- which errors on a nil table. Missed that the first time.
--
-- tyreEffectsEnabled deliberately isn't here - that one stays a quick
-- keybind + always-visible HUD toggle (Shift+T), the one thing worth
-- reaching for mid-drive. Everything else here doesn't need that.
IWSettingsUI = {}
local IWSettingsUI_mt = Class(IWSettingsUI)

function IWSettingsUI.new(config, tyreWitherLevelLabels, tyrePaintPaletteLabels, sweepSampleCounts, wheelSensitivityLabels, verboseLoggingLabels)
    local self = setmetatable({}, IWSettingsUI_mt)

    self.controls = {}
    self.config = config
    self.tyreWitherLevelLabels = tyreWitherLevelLabels
    self.tyrePaintPaletteLabels = tyrePaintPaletteLabels
    self.sweepSampleCounts = sweepSampleCounts
    self.wheelSensitivityLabels = wheelSensitivityLabels
    self.verboseLoggingLabels = verboseLoggingLabels
    self.isInitialized = false

    return self
end

function IWSettingsUI:injectUiSettings()
    if g_dedicatedServer then
        return
    end

    if self.isInitialized then
        return
    end

    self.isInitialized = true

    local settingsPage = g_gui.screenControllers[InGameMenu].pageSettings

    -- Choice controls (values = a list), not range controls (min/max/
    -- step) - a range control can only show the raw index (1, 2, 3...),
    -- not a real label, and sample count in particular isn't even evenly
    -- stepped (1000/2000/4000/6000/8000/10000), so min/max/step couldn't
    -- have represented it correctly anyway. Still bound to the same 1..N
    -- index fields on config - UIHelper's choice control stores/reads the
    -- selected index directly when values are strings/numbers (not a
    -- values-array lookup), confirmed from its own getChoiceValue/
    -- setChoiceValue (control.hasStrings branch).
    local controlProperties = {
        { name = "tyreWitherLevelIndex", values = self.tyreWitherLevelLabels, autoBind = true, nillable = false },
        { name = "tyrePaintPaletteIndex", values = self.tyrePaintPaletteLabels, autoBind = true, nillable = false },
        { name = "sweepSampleCountIndex", values = self.sweepSampleCounts, autoBind = true, nillable = false },
        { name = "wheelSensitivityIndex", values = self.wheelSensitivityLabels, autoBind = true, nillable = false },
        { name = "verboseLoggingIndex", values = self.verboseLoggingLabels, autoBind = true, nillable = false },
    }

    UIHelper.createControlsDynamically(settingsPage, "iw_setting_title", self, controlProperties, "iw_")
    UIHelper.setupAutoBindControls(self, self.config, IWSettingsUI.onSettingsChange)

    -- Apply initial values and force the layout to actually lay the new
    -- controls out - without this, controls exist but the page doesn't
    -- reflow to show them.
    self:updateUiElements()
end

function IWSettingsUI:updateUiElements(skipAutoBindControls)
    if not skipAutoBindControls then
        -- Created dynamically by UIHelper.setupAutoBindControls.
        self.populateAutoBindControls()
    end

    local isAdmin = g_currentMission:getIsServer() or g_currentMission.isMasterUser
    for _, control in ipairs(self.controls) do
        control:setDisabled(not isAdmin)
    end

    local settingsPage = g_gui.screenControllers[InGameMenu].pageSettings
    settingsPage.gameSettingsLayout:invalidateLayout()
end

-- autoBind writes straight to self.config's fields, bypassing IWConfig's
-- own cycleXIndex()/save() methods entirely - so persistence has to be
-- triggered explicitly here instead of happening for free the way it did
-- for the keybind-driven cycling.
function IWSettingsUI:onSettingsChange()
    self.config:save()
end
