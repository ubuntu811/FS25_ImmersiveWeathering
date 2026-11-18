-- IWWailaTab.lua -- IW's settings as a tab of WAILA's debug hub (g_currentMission.waila.registerDebugTab): one row per setting, previous / next buttons or the mouse wheel change it.
-- Pure: the config, the option lists and the text lookup are passed in, so it runs offline.
IWWailaTab = {}
IWWailaTab.ID = "immersiveweathering"

-- options = {
--   { key = "tyreWitherLevelIndex", label = "Tyre withering chance", texts = { "20%", ... } },     -- texts: the display text of each index
--   { key = "tyreEffectsEnabled", label = "Tyre effects", boolean = true },                           -- a plain on/off
-- }
-- an option may also carry color = function(index) -> r, g, b (linear): the little colour field of its row (the texture row shows the main texture).
function IWWailaTab.new(config, options)
    return { config = config, options = options }
end

-- the display texts of an option: a fixed list, or getTexts() when the list changes (the texture sets)
local function textsOf(option)
    return option.getTexts ~= nil and option.getTexts() or option.texts
end

local function count(option)
    return option.boolean and 2 or #textsOf(option)
end

-- 1-based index of the option's current value (a boolean is 1 = off, 2 = on).
function IWWailaTab.indexOf(tab, option)
    if option.boolean then
        return tab.config[option.key] and 2 or 1
    end
    return tab.config[option.key] or 1
end

function IWWailaTab.valueText(tab, option)
    local index = IWWailaTab.indexOf(tab, option)
    if option.boolean then
        return index == 2 and (option.onText or "On") or (option.offText or "Off")
    end
    return tostring(textsOf(option)[index] or index)
end

-- Sets a setting to an index (1-based; a boolean: 1 = off, 2 = on), saves. Returns the index.
function IWWailaTab.setIndex(tab, option, index)
    local n = count(option)
    index = math.max(1, math.min(n, index))
    if option.boolean then
        tab.config[option.key] = index == 2
    else
        tab.config[option.key] = index
    end
    if tab.config.save ~= nil then
        tab.config:save()
    end
    if option.onChange ~= nil then
        option.onChange(index)
    end
    return index
end

-- Steps a setting by delta (+1 next, -1 previous), wrapping round; saves. Returns the new index.
function IWWailaTab.step(tab, option, delta)
    local n = count(option)
    return IWWailaTab.setIndex(tab, option, ((IWWailaTab.indexOf(tab, option) - 1 + delta) % n) + 1)
end

function IWWailaTab.items(tab)
    local items = {}
    for i, option in ipairs(tab.options) do
        items[i] = { option = option, index = i }
    end
    return items
end

function IWWailaTab.describeItem(tab, item)
    local option = item.option
    return option.label, IWWailaTab.valueText(tab, option)
end

-- The terrain layer picture of a row: only for options that have one (option.layerId(index) -> a terrain layer id).
function IWWailaTab.layerId(tab, option)
    if option.layerId == nil then
        return nil
    end
    return option.layerId(IWWailaTab.indexOf(tab, option))
end

-- The ten-segment meter of a row: where its value sits in its list (the first is empty, the last full; an off switch is dim and empty).
function IWWailaTab.meter(tab, option)
    local n = count(option)
    local index = IWWailaTab.indexOf(tab, option)
    if option.boolean then
        return index == 2 and 1 or 0, index ~= 2
    end
    return n > 1 and (index - 1) / (n - 1) or 1, false
end

-- The colour field of a row: only for options that have one.
function IWWailaTab.color(tab, option)
    if option.color == nil then
        return nil
    end
    return option.color(IWWailaTab.indexOf(tab, option))
end

-- The right column of the hub for the selected row: one button per value, the current one marked, one click sets it. The hub has IWWailaTab.MAX_BUTTONS slots: a longer list shows the window round the
-- current value.
IWWailaTab.MAX_BUTTONS = 11
function IWWailaTab.buttons(tab, option)
    local n = count(option)
    local current = IWWailaTab.indexOf(tab, option)
    local first = 1
    if n > IWWailaTab.MAX_BUTTONS then
        first = math.max(1, math.min(n - IWWailaTab.MAX_BUTTONS + 1, current - 2))
    end
    local list = {}
    for index = first, math.min(n, first + IWWailaTab.MAX_BUTTONS - 1) do
        local text = option.boolean and (index == 2 and (option.onText or "On") or (option.offText or "Off")) or tostring(textsOf(option)[index] or index)
        list[#list + 1] = {
            label = (index == current and "> " or "") .. text,
            instant = true,
            callback = function() IWWailaTab.setIndex(tab, option, index) end,
        }
    end
    return list
end

-- The descriptor for Waila.registerDebugTab.
function IWWailaTab.descriptor(tab, label, icon)
    return {
        id = IWWailaTab.ID,
        label = label,
        icon = icon,
        getItems = function() return IWWailaTab.items(tab) end,
        describeItem = function(item) return IWWailaTab.describeItem(tab, item) end,
        getItemMeter = function(item) return IWWailaTab.meter(tab, item.option) end,
        getItemLayer = function(item) return IWWailaTab.layerId(tab, item.option) end,
        getItemColor = function(item) return IWWailaTab.color(tab, item.option) end,
        onScroll = function(item, delta) IWWailaTab.step(tab, item.option, delta > 0 and 1 or -1) end,
        getButtons = function(item) return IWWailaTab.buttons(tab, item.option) end,
        onDoubleClick = function(item) IWWailaTab.step(tab, item.option, 1) end,
    }
end

-- Registers (again) with WAILA when it is there; true once done. Unregisters its own id first: the tab list outlives a mission.
function IWWailaTab.register(waila, tab, label, icon)
    if waila == nil or waila.registerDebugTab == nil then
        return false
    end
    if waila.unregisterDebugTab ~= nil then
        waila.unregisterDebugTab(IWWailaTab.ID)
    end
    waila.registerDebugTab(IWWailaTab.descriptor(tab, label, icon))
    return true
end
