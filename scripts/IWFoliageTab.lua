-- IWFoliageTab.lua -- the foliage sets (IWFoliageSets) as a tab of WAILA's debug hub: a row per set (the three ground sets IW seeds with, then the player's own, painted from the construction screen); editing a
-- set lists the foliage the map's iw-map.xml knows, one click puts a foliage in the set or takes it out, and its chance goes up and down; the player's sets can be added, renamed, duplicated and deleted.
-- Pure: the sets and the foliage names are passed in.
IWFoliageTab = {}
IWFoliageTab.ID = "immersiveweathering-foliage"
IWFoliageTab.CHANCE_CHOICES = { 1, 5, 10, 25, 50 }
IWFoliageTab.FINE_STEP = 1
IWFoliageTab.CLASS_NOTE = {
    meadow = "seeded on grass ground that is no field, road, building or forest",
    bare = "seeded on dirt, gravel or sand that is no road, building or field: trails, yards, lots",
    forest = "seeded inside a forest area",
}
local SETS, LIST, STATES = "sets", "list", "states"

-- api = {
--   sets = an IWFoliageSets,
--   names = function() -> the foliage names the map's palette can seed,
--   range = function(name) -> { min, max, sequential } of a foliage layer's states, nil when unknown   -- sequential: the states are growth stages (sunflower), else separate plants (decoBush)
--   stateName = function(name, state) -> the real name of a state ("Blueberry Short"), nil when the layer has none   -- optional
--   icon = function(name, state) -> the game's store icon file of a layer's state (state nil: of the layer), nil when it has none   -- optional
--   preview = function(name, min, max), clearPreview = function()            -- optional: stamps the states of a layer in a row in front of the player / wipes it
--   changed = function(),                                                    -- something was edited: save
--   askName = function(default, callback(text)),                             -- optional: a text input dialog
-- }
function IWFoliageTab.new(api)
    return { api = api, mode = SETS, key = nil }
end

function IWFoliageTab.chanceText(chance)
    return (string.format("%.2f", chance):gsub("0+$", ""):gsub("%.$", ""))
end

local function percentText(chance)
    return IWFoliageTab.chanceText(chance) .. "%"
end

-- The foliage of the map: the ones in the set first (in set order), then the rest alphabetically.
function IWFoliageTab.foliageNames(tab)
    local out, seen = {}, {}
    for _, e in ipairs(tab.api.sets:entries(tab.key)) do
        if not seen[e.name] then                                     -- (a set with six particular plants of one layer has six entries, one row)
            out[#out + 1], seen[e.name] = e.name, true
        end
    end
    local rest = {}
    for _, name in ipairs(tab.api.names()) do
        if not seen[name] then
            seen[name] = true
            rest[#rest + 1] = name
        end
    end
    table.sort(rest)
    for _, name in ipairs(rest) do
        out[#out + 1] = name
    end
    return out
end

-- The states of a layer: { min, max, sequential }; a layer the tab cannot look up has the one state 1 (and is no ladder).
function IWFoliageTab.rangeOf(tab, name)
    local range = tab.api.range ~= nil and tab.api.range(name) or nil
    if range == nil or range.min == nil or range.max == nil or range.max < range.min then
        return { min = 1, max = 1, sequential = false }
    end
    return range
end

-- "plants" for a layer that is a pool of separate plants, "stages" for one whose states are growth stages.
local function noun(range)
    return range.sequential and "stage" or "plant"
end

function IWFoliageTab.items(tab)
    local items = {}
    if tab.mode == SETS then
        for i = 1, tab.api.sets:count() do
            items[i] = { kind = "set", key = tab.api.sets:keyAt(i) }
        end
    elseif tab.mode == STATES then
        local range = IWFoliageTab.rangeOf(tab, tab.layer)
        for state = range.min, range.max do
            items[#items + 1] = { kind = "state", state = state }
        end
    else
        for _, name in ipairs(IWFoliageTab.foliageNames(tab)) do
            items[#items + 1] = { kind = "foliage", name = name }
        end
        if #items == 0 then
            items[1] = { kind = "none" }
        end
    end
    return items
end

function IWFoliageTab.describeItem(tab, item)
    local sets = tab.api.sets
    if item.kind == "set" then
        local set = sets:get(item.key)
        local count = #set.entries
        local what = count == 0 and "plants nothing" or string.format("%d foliage, %s of the rolls plant one", count, percentText(math.min(100, IWFoliageSets.chanceSum(set))))
        local state = set.builtin and (set.edited and "yours" or "the map's list") or "yours"
        local note = IWFoliageTab.CLASS_NOTE[item.key] or "painted from the construction screen, on any ground"
        return set.name, what .. "  -  " .. state .. "  (" .. note .. ")"
    elseif item.kind == "none" then
        return "No foliage to pick from", "the map's iw-map.xml declares no foliage entries"
    end
    local set = sets:get(tab.key)
    if item.kind == "state" then
        local range = IWFoliageTab.rangeOf(tab, tab.layer)
        local title = string.format("%s %d of %d", noun(range), item.state, range.max - range.min + 1)
        local real = tab.api.stateName ~= nil and tab.api.stateName(tab.layer, item.state) or nil
        if real ~= nil then
            title = string.format("%s  (%s %d of %d)", real, noun(range), item.state, range.max - range.min + 1)
        end
        if range.sequential then
            title = title .. (item.state == range.max and "  (full grown)" or (item.state == range.min and "  (the start)" or ""))
        end
        local chance = sets:chanceOf(tab.key, tab.layer, item.state)
        return title, chance == nil and ("not in '" .. set.name .. "'") or string.format("in '%s': chance %s", set.name, percentText(chance))
    end
    local range = IWFoliageTab.rangeOf(tab, item.name)
    local chance = sets:chanceOf(tab.key, item.name)
    local states = sets:stateCount(tab.key, item.name)
    local kind = range.sequential and "growth stages" or "separate plants"
    local parts = {}
    if chance ~= nil then
        parts[#parts + 1] = string.format("any %s at %s", range.sequential and "start" or "plant", percentText(chance))
    end
    if states > 0 then
        parts[#parts + 1] = string.format("%d particular %s%s picked", states, noun(range), states == 1 and "" or "s")
    end
    if #parts == 0 then
        return item.name, string.format("not in '%s'  (%d %s)", set.name, range.max - range.min + 1, kind)
    end
    return item.name, string.format("in '%s': %s  (%d %s)", set.name, table.concat(parts, ", "), range.max - range.min + 1, kind)
end

function IWFoliageTab.meter(tab, item)
    if item.kind == "set" then
        return math.min(1, IWFoliageSets.chanceSum(tab.api.sets:get(item.key)) / 100), false
    elseif item.kind == "foliage" then
        local chance = tab.api.sets:chanceOf(tab.key, item.name)
        local sum = chance or 0
        for _, e in ipairs(tab.api.sets:entries(tab.key)) do
            if e.name == item.name and e.state ~= nil then
                sum = sum + e.chance
            end
        end
        return math.min(1, sum / 100), sum == 0
    elseif item.kind == "state" then
        local chance = tab.api.sets:chanceOf(tab.key, tab.layer, item.state)
        return (chance or 0) / 100, chance == nil
    end
    return nil
end

function IWFoliageTab.buttons(tab, item)
    local api = tab.api
    local list = {}
    local group = nil                                                    -- (the hub leaves a gap where it changes)
    local function add(label, callback)
        list[#list + 1] = { label = label, instant = true, callback = callback, group = group }
    end
    if item.kind == "set" then
        local sets, key = api.sets, item.key
        local set = sets:get(key)
        group = 1
        add("Edit", function() tab.key = key; tab.mode = LIST end)
        group = 2
        add("Add", function() tab.key = sets:add(); api.changed(); tab.mode = LIST end)
        if not set.builtin and api.askName ~= nil then
            add("Rename", function()
                api.askName(set.name, function(text)
                    if sets:rename(key, text) then
                        api.changed()
                    end
                end)
            end)
        end
        add("Duplicate", function() sets:duplicate(key); api.changed() end)
        if set.builtin and set.edited then
            add("Back to the map's list", function() sets:reset(key); api.changed() end)
        end
        if not set.builtin then
            add("Delete", function() sets:remove(key); api.changed() end)
        end
    elseif item.kind == "none" then
        add("Done", function() tab.mode = SETS end)
    else
        local sets, key = api.sets, tab.key
        local name = item.kind == "state" and tab.layer or item.name
        local state = item.kind == "state" and item.state or nil
        local current = sets:chanceOf(key, name, state)
        if item.kind == "foliage" then
            local range = IWFoliageTab.rangeOf(tab, name)
            group = 1
            add(range.sequential and "Pick a stage" or "Pick plants", function() tab.layer = name; tab.mode = STATES end)
        end
        if api.preview ~= nil and state == nil then
            local range = IWFoliageTab.rangeOf(tab, name)
            add(string.format("Show all %d in the world", range.max - range.min + 1), function() api.preview(name, range.min, range.max) end)
        end
        if item.kind == "state" and api.preview ~= nil then
            local range = IWFoliageTab.rangeOf(tab, name)
            add("Show this one in the world", function() api.preview(name, item.state, item.state) end)
            add(string.format("Show all %d in the world", range.max - range.min + 1), function() api.preview(name, range.min, range.max) end)
        end
        group = 2
        local whole = item.kind == "foliage" and (IWFoliageTab.rangeOf(tab, name).sequential and "Put in (the start)" or "Put in (any plant)") or "Put in"
        add(current ~= nil and "Take out" or whole, function() sets:toggle(key, name, state); api.changed() end)
        group = 3
        for _, chance in ipairs(IWFoliageTab.CHANCE_CHOICES) do
            add((current == chance and "> " or "") .. "Chance " .. chance .. "%", function()
                if sets:chanceOf(key, name, state) == nil then
                    sets:toggle(key, name, state)
                end
                sets:setChance(key, name, chance, state)
                api.changed()
            end)
        end
        add("More  (+" .. IWFoliageTab.FINE_STEP .. ")", function() sets:addChance(key, name, IWFoliageTab.FINE_STEP, state); api.changed() end)
        add("Less  (-" .. IWFoliageTab.FINE_STEP .. ")", function() sets:addChance(key, name, -IWFoliageTab.FINE_STEP, state); api.changed() end)
        group = 4
        if api.clearPreview ~= nil then
            add("Clear the preview", function() api.clearPreview() end)
        end
        add("Done", function() tab.mode = item.kind == "state" and LIST or SETS end)
    end
    return list
end

-- The picture of a foliage row (a layer: its first state with an icon; a state: its own): the game's store icon. Sets and rows without an icon show none.
function IWFoliageTab.image(tab, item)
    if tab.api.icon == nil then
        return nil
    end
    if item.kind == "foliage" then
        return tab.api.icon(item.name, nil)
    elseif item.kind == "state" then
        return tab.api.icon(tab.layer, item.state)
    end
    return nil
end

function IWFoliageTab.doubleClick(tab, item)
    local wanted = nil
    if item.kind == "set" then
        wanted = "Edit"
    elseif item.kind == "foliage" then
        wanted = IWFoliageTab.rangeOf(tab, item.name).sequential and "Pick a stage" or "Pick plants"
    elseif item.kind == "state" then
        wanted = tab.api.sets:chanceOf(tab.key, tab.layer, item.state) ~= nil and "Take out" or "Put in"
    end
    for _, button in ipairs(wanted ~= nil and IWFoliageTab.buttons(tab, item) or {}) do
        if button.label == wanted then
            button.callback()
            return
        end
    end
end

-- The hub's Back (and ESC): from a set's foliage to the sets; false at the top (the hub closes then).
function IWFoliageTab.back(tab)
    if tab.mode == STATES then
        tab.mode = LIST
        return true
    elseif tab.mode == LIST then
        tab.mode = SETS
        return true
    end
    return false
end

function IWFoliageTab.descriptor(tab, label, icon)
    return {
        id = IWFoliageTab.ID,
        label = label,
        icon = icon,
        getItems = function() return IWFoliageTab.items(tab) end,
        describeItem = function(item) return IWFoliageTab.describeItem(tab, item) end,
        getItemMeter = function(item) return IWFoliageTab.meter(tab, item) end,
        getButtons = function(item) return IWFoliageTab.buttons(tab, item) end,
        getItemImage = function(item) return IWFoliageTab.image(tab, item) end,
        onDoubleClick = function(item) IWFoliageTab.doubleClick(tab, item) end,
        onBack = function() return IWFoliageTab.back(tab) end,
    }
end

function IWFoliageTab.register(waila, tab, label, icon)
    if waila == nil or waila.registerDebugTab == nil then
        return false
    end
    if waila.unregisterDebugTab ~= nil then
        waila.unregisterDebugTab(IWFoliageTab.ID)
    end
    waila.registerDebugTab(IWFoliageTab.descriptor(tab, label, icon))
    return true
end
