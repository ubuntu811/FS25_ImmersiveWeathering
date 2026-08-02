-- Owns the mod's 4 real persistent settings (tyre effects enabled, wither
-- level, paint palette, sweep sample count) and saves/loads them to
-- modSettings/FS25_ImmersiveWeathering/config.xml, so they survive a
-- restart instead of resetting to defaults every load. XMLFile/XMLSchema
-- is the real, current FS25 API for this - confirmed directly from
-- Courseplay_FS25's own Courseplay.lua (an actively maintained, current
-- mod), not guessed: getUserProfileAppPath() .. "modSettings/<name>/",
-- XMLSchema.new():register(), XMLFile.create()/loadIfExists():getValue()/
-- :setValue()/:save().
--
-- Cycling helpers take the option-table length as a parameter rather than
-- this file knowing about TYRE_WITHER_LEVELS/TYRE_PAINT_PALETTES/
-- SWEEP_SAMPLE_COUNTS directly - those are ImmersiveWeathering.lua's own
-- domain data (what the indices mean), this file only owns which index is
-- currently selected and making that persist.

IWConfig = {}
local IWConfig_mt = Class(IWConfig)

local CONFIG_SCHEMA = XMLSchema.new("FS25_ImmersiveWeatheringConfig")
CONFIG_SCHEMA:register(XMLValueType.BOOL, "config#tyreEffectsEnabled")
CONFIG_SCHEMA:register(XMLValueType.INT, "config#tyreWitherLevelIndex")
CONFIG_SCHEMA:register(XMLValueType.INT, "config#tyrePaintPaletteIndex")
CONFIG_SCHEMA:register(XMLValueType.INT, "config#sweepSampleCountIndex")

function IWConfig.new(defaultTyreWitherLevelIndex, defaultTyrePaintPaletteIndex, defaultSweepSampleCountIndex)
    local self = setmetatable({}, IWConfig_mt)

    self.tyreEffectsEnabled = true
    self.tyreWitherLevelIndex = defaultTyreWitherLevelIndex
    self.tyrePaintPaletteIndex = defaultTyrePaintPaletteIndex
    self.sweepSampleCountIndex = defaultSweepSampleCountIndex

    self.baseDir = getUserProfileAppPath() .. "modSettings/FS25_ImmersiveWeathering/"
    createFolder(self.baseDir)
    self.filePath = self.baseDir .. "config.xml"

    self:load()

    return self
end

function IWConfig:load()
    local xmlFile = XMLFile.loadIfExists("IWConfig", self.filePath, CONFIG_SCHEMA)
    if xmlFile == nil then
        return
    end

    self.tyreEffectsEnabled = xmlFile:getValue("config#tyreEffectsEnabled", self.tyreEffectsEnabled)
    self.tyreWitherLevelIndex = xmlFile:getValue("config#tyreWitherLevelIndex", self.tyreWitherLevelIndex)
    self.tyrePaintPaletteIndex = xmlFile:getValue("config#tyrePaintPaletteIndex", self.tyrePaintPaletteIndex)
    self.sweepSampleCountIndex = xmlFile:getValue("config#sweepSampleCountIndex", self.sweepSampleCountIndex)

    xmlFile:delete()
end

function IWConfig:save()
    local xmlFile = XMLFile.create("IWConfig", self.filePath, "config", CONFIG_SCHEMA)
    if xmlFile == nil then
        return
    end

    xmlFile:setValue("config#tyreEffectsEnabled", self.tyreEffectsEnabled)
    xmlFile:setValue("config#tyreWitherLevelIndex", self.tyreWitherLevelIndex)
    xmlFile:setValue("config#tyrePaintPaletteIndex", self.tyrePaintPaletteIndex)
    xmlFile:setValue("config#sweepSampleCountIndex", self.sweepSampleCountIndex)
    xmlFile:save()
    xmlFile:delete()
end

function IWConfig:isTyreEffectsEnabled()
    return self.tyreEffectsEnabled
end

function IWConfig:toggleTyreEffectsEnabled()
    self.tyreEffectsEnabled = not self.tyreEffectsEnabled
    self:save()
    return self.tyreEffectsEnabled
end

function IWConfig:getTyreWitherLevelIndex()
    return self.tyreWitherLevelIndex
end

function IWConfig:cycleTyreWitherLevelIndex(optionCount)
    self.tyreWitherLevelIndex = (self.tyreWitherLevelIndex % optionCount) + 1
    self:save()
    return self.tyreWitherLevelIndex
end

function IWConfig:getTyrePaintPaletteIndex()
    return self.tyrePaintPaletteIndex
end

function IWConfig:cycleTyrePaintPaletteIndex(optionCount)
    self.tyrePaintPaletteIndex = (self.tyrePaintPaletteIndex % optionCount) + 1
    self:save()
    return self.tyrePaintPaletteIndex
end

function IWConfig:getSweepSampleCountIndex()
    return self.sweepSampleCountIndex
end

function IWConfig:cycleSweepSampleCountIndex(optionCount)
    self.sweepSampleCountIndex = (self.sweepSampleCountIndex % optionCount) + 1
    self:save()
    return self.sweepSampleCountIndex
end
