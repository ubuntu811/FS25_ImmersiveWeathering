-- IWTexturesTab.lua -- the texture sets as a tab of WAILA's debug hub: a list of sets (use, edit, add, rename, duplicate, delete); editing a set goes one level down to the map's terrain layers grouped by type
-- (gravel, stone, dirt and mud, grass ...) and one more to the layers of a group (add or remove it, more or less weight). "Pattern" turns a set from a weighted mix into a tile of texels that repeats over
-- the ground (cobblestones, bricks, stripes): the rows of the tile, a cell at a time. Pure: the sets, the layer names and the actions are passed in.
IWTexturesTab = {}
IWTexturesTab.ID = "immersiveweathering-textures"
IWTexturesTab.PAGE_SIZE = 8              -- layers listed as buttons for a type: 8 + the page button + Weights + Done = the hub's 11 slots
local SETS, GROUPS, LAYERS, PATTERN, DETAILS = "sets", "groups", "layers", "pattern", "details"
local IN_SET = { key = "set", title = "In this set" }
IWTexturesTab.FOLIAGE_TEXT = { down = "wears down", clear = "removed", keep = "stays" }
IWTexturesTab.SHAPE_TEXT = { spot = "spot (a smudge, a pothole)", crack = "crack (a thin line)" }

-- api = {
--   sets = an IWTextureSets, layerNames = function() -> the map's terrain layer names,
--   getActive = function() -> index, setActive = function(index),            -- the set the tyres paint with
--   changed = function(),                                                    -- something was edited: save, repaint
--   askName = function(default, callback(text)),                             -- optional: a text input dialog
--   layerId = function(name) -> the terrain layer id of a layer name (for the row's texture picture), nil when unknown
-- }
function IWTexturesTab.new(api)
    return { api = api, mode = SETS, setIndex = nil, group = nil }
end

local function currentSet(tab)
    return tab.api.sets:get(tab.setIndex or 1)
end

-- "per texel" or "2 m patches": the patch size of a set in words (api.texelSize() is the texel in metres, 0.5 when the tab is not told).
function IWTexturesTab.blockText(tab, block)
    if block <= 1 then
        return "per texel"
    end
    local texel = tab.api.texelSize ~= nil and tab.api.texelSize() or 0.5
    return string.format("%g m patches", math.floor(block * texel * 10 + 0.5) / 10)
end

-- Layers of the map grouped by type: { { group, layers = { names } } }, in the order of IWTextureSets.GROUPS (then Other); the first row is the set's own layers when it has any.
function IWTexturesTab.groups(tab)
    local set = currentSet(tab)
    local byKey, list = {}, {}
    if #set.textures > 0 then
        local own = { group = IN_SET, layers = {} }
        for _, t in ipairs(set.textures) do
            own.layers[#own.layers + 1] = t.layer
        end
        list[1] = own
    end
    local order = {}
    for _, group in ipairs(IWTextureSets.GROUPS) do
        order[#order + 1] = group
    end
    order[#order + 1] = IWTextureSets.OTHER_GROUP
    for _, group in ipairs(order) do
        byKey[group.key] = { group = group, layers = {} }
    end
    local names = tab.api.layerNames()
    local known = {}
    for _, name in ipairs(names) do
        known[name:lower()] = true
    end
    for _, name in ipairs(names) do
        if tab.pickDetail or not IWTextureSets.isVariant(name, known) then      -- (the damage variants are the matching details' business; picking a detail lists them)
            table.insert(byKey[IWTextureSets.groupOf(name).key].layers, name)
        end
    end
    for _, group in ipairs(order) do
        if #byKey[group.key].layers > 0 then
            list[#list + 1] = byKey[group.key]
        end
    end
    return list
end

local function weightShare(set, layer)
    local sum = 0
    for _, t in ipairs(set.textures) do
        sum = sum + t.weight
    end
    local weight = IWTextureSets.weightOf(set, layer)
    return weight ~= nil and sum > 0 and weight / sum or 0, weight
end

function IWTexturesTab.items(tab)
    local items = {}
    if tab.mode == SETS then
        for i = 1, tab.api.sets:count() do
            items[i] = { kind = "set", index = i }
        end
    elseif tab.mode == GROUPS then
        for _, entry in ipairs(IWTexturesTab.groups(tab)) do
            items[#items + 1] = { kind = "group", entry = entry }
        end
        if #items == 0 then
            items[1] = { kind = "none" }                                 -- (a row, so that the buttons have something to belong to)
        end
    elseif tab.mode == DETAILS then
        local set = currentSet(tab)
        for d = 1, #(set.details or {}) do
            items[d] = { kind = "detail", index = d }
        end
        if set.matchDetails then
            for _, detail in ipairs(IWTextureSets.matching(set, tab.api.layerNames())) do
                items[#items + 1] = { kind = "matched", detail = detail }          -- (what the tick brings: listed, so the screen says what is on)
            end
        end
        if #items == 0 then
            items[1] = { kind = "nodetail" }
        end
    elseif tab.mode == PATTERN then
        local set = currentSet(tab)
        if set.pattern == nil then
            items[1] = { kind = "empty" }
        else
            for r = 1, set.pattern.h do
                items[r] = { kind = "prow", row = r }
            end
            items[#items + 1] = { kind = "pkey" }
        end
    else
        for _, entry in ipairs(IWTexturesTab.groups(tab)) do
            if entry.group.key == tab.group then
                for _, name in ipairs(entry.layers) do
                    items[#items + 1] = { kind = "layer", layer = name }
                end
            end
        end
        if #items == 0 then
            -- the last layer of "In this set" was taken out (or the type has none): an empty list has no buttons and no way back, so it falls back to the types
            tab.mode = GROUPS
            return IWTexturesTab.items(tab)
        end
    end
    return items
end

function IWTexturesTab.describeItem(tab, item)
    local sets = tab.api.sets
    if item.kind == "set" then
        local set = sets:get(item.index)
        local used = tab.api.getActive() == item.index
        return set.name .. (used and "  (in use)" or ""), IWTextureSets.describe(set) .. (set.builtin and "" or "  -  yours")
    elseif item.kind == "group" then
        local set = currentSet(tab)
        local inSet, shareSum = 0, 0
        for _, name in ipairs(item.entry.layers) do
            local share, weight = weightShare(set, name)
            if weight ~= nil then
                inSet, shareSum = inSet + 1, shareSum + share
            end
        end
        if item.entry.group.key == "set" then
            return item.entry.group.title, string.format("%d layer(s) of '%s'", #item.entry.layers, set.name)
        end
        return item.entry.group.title, string.format("%d layer(s), %d in '%s' (%d%% of it)", #item.entry.layers, inSet, set.name, math.floor(shareSum * 100 + 0.5))
    end
    if item.kind == "nodetail" then
        if currentSet(tab).matchDetails then
            return "No details", "Matching details are on, but no layer of this set has damage variants in the map"
        end
        return "No details yet", "Add detail: a layer that driving leaves on the surface (a dirt smudge, a crack, a pothole)"
    elseif item.kind == "matched" then
        local detail = item.detail
        return detail.layer, string.format("from Matching details: %s, %s%% per texel, size %d", detail.shape, IWTextureSets.chanceText(detail.chance), detail.size)
    elseif item.kind == "detail" then
        local detail = currentSet(tab).details[item.index]
        return detail.layer, string.format("%s, %s%% per texel a tyre wears, size %d", detail.shape, IWTextureSets.chanceText(detail.chance), detail.size)
    elseif item.kind == "none" then
        return "No layers to show", "this map has no terrain layers, and the set has none: nothing to pick from"
    elseif item.kind == "empty" then
        return "No pattern yet", "pick a preset on the right (it needs the set's layers: Edit adds them)"
    elseif item.kind == "prow" or item.kind == "pkey" then
        local set = currentSet(tab)
        local palette = {}
        for _, t in ipairs(set.textures) do
            palette[#palette + 1] = t.layer
        end
        local rows, key = IWPatterns.letters(set.pattern, palette)
        if item.kind == "pkey" then
            return "Key", key
        end
        return "Row " .. item.row .. " of " .. set.pattern.h, rows[item.row]
    end
    local set = currentSet(tab)
    local share, weight = weightShare(set, item.layer)
    if weight == nil then
        return item.layer, string.format("not in '%s'", set.name)
    end
    return item.layer, string.format("in '%s': weight %d (%d%%)", set.name, weight, math.floor(share * 100 + 0.5))
end

-- the chip: a set's main layer, a group's colour (its first layer), a layer's own
function IWTexturesTab.color(tab, item)
    if item.kind == "prow" then
        return IWTextureSets.layerColor(currentSet(tab).pattern.rows[item.row][1])
    elseif item.kind == "detail" then
        return IWTextureSets.layerColor(currentSet(tab).details[item.index].layer)
    elseif item.kind == "matched" then
        return IWTextureSets.layerColor(item.detail.layer)
    elseif item.kind == "pkey" or item.kind == "empty" or item.kind == "none" or item.kind == "nodetail" then
        return nil
    end
    if item.kind == "set" then
        local main = IWTextureSets.main(tab.api.sets:get(item.index))
        return IWTextureSets.layerColor(main)
    elseif item.kind == "group" then
        return IWTextureSets.layerColor(item.entry.layers[1])
    end
    return IWTextureSets.layerColor(item.layer)
end

-- the picture of a row: the terrain layer id of a set's main layer, a type's first layer, a layer, a pattern row's first cell (the hub draws that layer's own texture), nil for rows with no layer
function IWTexturesTab.layerId(tab, item)
    if tab.api.layerId == nil then
        return nil
    end
    local name = nil
    if item.kind == "set" then
        name = IWTextureSets.main(tab.api.sets:get(item.index))
    elseif item.kind == "group" then
        name = item.entry.layers[1]
    elseif item.kind == "layer" then
        name = item.layer
    elseif item.kind == "prow" then
        name = currentSet(tab).pattern.rows[item.row][1]
    elseif item.kind == "detail" then
        name = currentSet(tab).details[item.index].layer
    elseif item.kind == "matched" then
        name = item.detail.layer
    end
    return name ~= nil and tab.api.layerId(name) or nil
end

-- The preview of a whole assembly: 8 x 8 cells of terrain layer pictures for the set under the mouse in the sets list, and for the set being edited in the pattern editor (it redraws with every click).
-- A pattern shows its tile twice in each direction, a set with a patch size one cell per patch, a weighted mix a cell per texel (each cell a stable pick, not a new roll every frame). nil elsewhere.
IWTexturesTab.PREVIEW_SIZE = 8
function IWTexturesTab.preview(tab, item)
    if tab.api.layerId == nil then
        return nil
    end
    local set = nil
    if tab.mode == SETS and item.kind == "set" then
        set = tab.api.sets:get(item.index)
    elseif tab.mode == PATTERN then
        set = currentSet(tab)
    else
        return nil
    end
    local n = IWTexturesTab.PREVIEW_SIZE
    local block = set.pattern == nil and set.block or 1
    local layers = {}
    for row = 0, n - 1 do
        for col = 0, n - 1 do
            local i, j = col * block, row * block
            local name = IWTextureSets.layerFor(set, i, j, function() return IWTextureSets.blockHash(i + 7, j + 3) end)
            layers[#layers + 1] = name ~= nil and tab.api.layerId(name) or false
        end
    end
    return { cols = n, rows = n, layers = layers }
end

-- the meter: a set's main share, the share of a group in the set being edited, the share of a layer
function IWTexturesTab.meter(tab, item)
    if item.kind == "prow" or item.kind == "pkey" or item.kind == "empty" or item.kind == "none" or item.kind == "nodetail" or item.kind == "detail" or item.kind == "matched" then
        return nil
    end
    if item.kind == "set" then
        local _, share = IWTextureSets.main(tab.api.sets:get(item.index))
        return share, false
    elseif item.kind == "group" then
        local set = currentSet(tab)
        local sum = 0
        for _, name in ipairs(item.entry.layers) do
            sum = sum + (weightShare(set, name))
        end
        return math.min(1, sum), false
    end
    local share, weight = weightShare(currentSet(tab), item.layer)
    return share, weight == nil
end

local function go(tab, mode)
    tab.mode = mode
end

local function afterDelete(tab, index)
    local api = tab.api
    local active = api.getActive()
    if index < active then
        api.setActive(active - 1)
    elseif index == active then
        api.setActive(1)
    end
end

function IWTexturesTab.buttons(tab, item)
    local api = tab.api
    local list = {}
    local group = nil                                                    -- (the hub leaves a gap where it changes: related buttons stay together)
    local function add(label, callback, layerName)
        list[#list + 1] = { label = label, instant = true, callback = callback, group = group, layerId = layerName ~= nil and api.layerId ~= nil and api.layerId(layerName) or nil }
    end
    if item.kind == "none" then
        add("Done", function() go(tab, SETS) end)
        return list
    end
    if tab.mode == DETAILS then
        local function pick() tab.pickDetail = true; go(tab, GROUPS) end
        if item.kind == "detail" then
            local detail = currentSet(tab).details[item.index]
            add("Shape: " .. detail.shape, function() api.sets:cycleDetail(tab.setIndex, item.index, "shape"); api.changed() end)
            add("Chance: " .. IWTextureSets.chanceText(detail.chance) .. "%", function() api.sets:cycleDetail(tab.setIndex, item.index, "chance"); api.changed() end)
            add("Size: " .. detail.size, function() api.sets:cycleDetail(tab.setIndex, item.index, "size"); api.changed() end)
            add("Remove", function() api.sets:removeDetail(tab.setIndex, item.index); api.changed() end)
        end
        if item.kind == "matched" then
            add("Tune it (make it a detail)", function() api.sets:adoptDetail(tab.setIndex, item.detail); api.changed() end)
        end
        add("Add detail", pick)
        local set = currentSet(tab)
        local found = #IWTextureSets.matching(set, api.layerNames())
        add(string.format("Matching details: %s  (%d found)", set.matchDetails and "on" or "off", found), function() api.sets:toggleMatchDetails(tab.setIndex); api.changed() end)
        add("Done", function() go(tab, SETS) end)
        return list
    end
    if tab.mode == SETS then
        local index = item.index
        local set = api.sets:get(index)
        group = 1
        add("Use", function() api.setActive(index) end)
        add("Edit", function() tab.setIndex = index; go(tab, GROUPS) end)
        group = 2
        add(string.format("Mix: %s", IWTexturesTab.blockText(tab, set.block or 1)), function() api.sets:cycleBlock(index); api.changed() end)
        add("Replaces: " .. (set.force and "grass, dirt, gravel, stone, sand" or "grass, dirt, gravel"), function() api.sets:toggleForce(index); api.changed() end)
        add("Foliage: " .. IWTexturesTab.FOLIAGE_TEXT[IWTextureSets.foliageMode(set)], function() api.sets:cycleFoliage(index); api.changed() end)
        add(string.format("Details  (%d%s)", #(set.details or {}), set.matchDetails and " + matching" or ""), function() tab.setIndex = index; go(tab, DETAILS) end)
        add("Pattern", function()
            tab.setIndex = index
            if set.pattern == nil and #set.textures > 0 then
                api.sets:setPreset(index, "checker")                  -- (a first pattern to start from: "Back to the mix" undoes it)
                api.changed()
            end
            go(tab, PATTERN)
        end)
        group = 3
        add("Add", function() tab.setIndex = api.sets:add(); api.changed(); go(tab, GROUPS) end)
        if api.askName ~= nil then
            add("Rename", function()
                api.askName(set.name, function(text)
                    if api.sets:rename(index, text) then
                        api.changed()
                    end
                end)
            end)
        end
        add("Duplicate", function() api.sets:duplicate(index); api.changed() end)
        if not set.builtin then
            add("Delete", function()
                if api.sets:remove(index) then
                    afterDelete(tab, index)
                    api.changed()
                end
            end)
        end
    elseif tab.mode == GROUPS then
        -- the layers of the selected type are buttons (IWTexturesTab.PAGE_SIZE a page): one click adds a layer to the set or takes it out, the ones in the set are marked
        local set = currentSet(tab)
        local key = item.entry.group.key
        if tab.pageGroup ~= key then
            tab.pageGroup, tab.page = key, 1
        end
        local count = #item.entry.layers
        local pages = math.max(1, math.ceil(count / IWTexturesTab.PAGE_SIZE))
        tab.page = math.max(1, math.min(pages, tab.page or 1))
        for n = (tab.page - 1) * IWTexturesTab.PAGE_SIZE + 1, math.min(count, tab.page * IWTexturesTab.PAGE_SIZE) do
            local layer = item.entry.layers[n]
            if tab.pickDetail then
                add(layer, function() api.sets:addDetail(tab.setIndex, layer); tab.pickDetail = false; api.changed(); go(tab, DETAILS) end, layer)
            else
                add((IWTextureSets.weightOf(set, layer) ~= nil and "> " or "") .. layer, function() api.sets:toggle(tab.setIndex, layer); api.changed() end, layer)
            end
        end
        if pages > 1 then
            add(string.format("More layers  (page %d of %d)", tab.page, pages), function() tab.page = tab.page % pages + 1 end)
        end
        if not tab.pickDetail then
            add("Weights", function() tab.group = key; go(tab, LAYERS) end)
        end
        local picking = tab.pickDetail
        add("Done", function() tab.pickDetail = false; go(tab, picking and DETAILS or SETS) end)
    elseif tab.mode == PATTERN then
        local set = currentSet(tab)
        if item.kind == "prow" then
            local palette = {}
            for _, t in ipairs(set.textures) do
                palette[#palette + 1] = t.layer
            end
            local letters = IWPatterns.letters(set.pattern, palette)
            for col = 1, set.pattern.w do
                local letter = letters[item.row]:sub(col * 2 - 1, col * 2 - 1)
                add(string.format("Cell %d  (%s)", col, letter), function() api.sets:cyclePatternCell(tab.setIndex, item.row, col, 1); api.changed() end)
            end
        end
        for _, kind in ipairs(IWPatterns.KINDS) do
            add(kind:sub(1, 1):upper() .. kind:sub(2), function() api.sets:setPreset(tab.setIndex, kind); api.changed() end)
        end
        add("Back to the mix", function() api.sets:clearPattern(tab.setIndex); api.changed(); go(tab, SETS) end)
        add("Done", function() go(tab, SETS) end)
    else
        local layer = item.layer
        group = 1
        add("Add / remove", function() api.sets:toggle(tab.setIndex, layer); api.changed() end)
        -- a layer with damage variants offers them as details (the slot of "Weight 75": the hub has 11 buttons and More / Less cover the weights in between)
        local names = api.layerNames()
        local variants = IWTextureSets.variantsOf(layer, names)
        if #variants > 0 then
            if IWTextureSets.hasDamage(currentSet(tab), layer, names) then
                add("Remove damage", function() api.sets:removeDamage(tab.setIndex, layer, names); api.changed() end)
            else
                add(string.format("Add damage  (%d)", #variants), function() api.sets:addDamage(tab.setIndex, layer, names); api.changed() end)
            end
        end
        local current = IWTextureSets.weightOf(currentSet(tab), layer)
        group = 2
        for _, weight in ipairs(IWTextureSets.WEIGHT_CHOICES) do
            if not (weight == 75 and #variants > 0) then
                add((current == weight and "> " or "") .. "Weight " .. weight, function() api.sets:setWeight(tab.setIndex, layer, weight); api.changed() end)
            end
        end
        add("More  (+" .. IWTextureSets.FINE_STEP .. ")", function() api.sets:addWeight(tab.setIndex, layer, IWTextureSets.FINE_STEP); api.changed() end)
        add("Less  (-" .. IWTextureSets.FINE_STEP .. ")", function() api.sets:addWeight(tab.setIndex, layer, -IWTextureSets.FINE_STEP); api.changed() end)
        group = 3
        add("Back to the types", function() go(tab, GROUPS) end)
        add("Done", function() go(tab, SETS) end)
    end
    return list
end

-- A double click on a row opens what the row opens: a set its editor, a type its weights, a layer goes in the set or out; the pattern rows have none.
function IWTexturesTab.doubleClick(tab, item)
    local wanted = nil
    if tab.mode == GROUPS then
        wanted = "Weights"
    elseif tab.mode == SETS then
        wanted = "Edit"                                                  -- (a set opens its editor: Use is a button)
    elseif tab.mode == LAYERS then
        wanted = "Add / remove"
    elseif tab.mode == DETAILS and item.kind == "nodetail" then
        wanted = "Add detail"
    end
    for _, button in ipairs(wanted ~= nil and IWTexturesTab.buttons(tab, item) or {}) do
        if button.label == wanted then
            button.callback()
            return
        end
    end
end

-- The hub's Back (and ESC): one level up instead of closing the hub. Returns true when it went up, false at the top (the hub closes then).
function IWTexturesTab.back(tab)
    if tab.mode == LAYERS then
        tab.mode = GROUPS
        return true
    elseif tab.mode == GROUPS and tab.pickDetail then
        tab.pickDetail = false
        tab.mode = DETAILS
        return true
    elseif tab.mode == GROUPS or tab.mode == PATTERN or tab.mode == DETAILS then
        tab.mode = SETS
        return true
    end
    return false
end

-- The descriptor for Waila.registerDebugTab.
function IWTexturesTab.descriptor(tab, label, icon)
    return {
        id = IWTexturesTab.ID,
        label = label,
        icon = icon,
        getItems = function() return IWTexturesTab.items(tab) end,
        describeItem = function(item) return IWTexturesTab.describeItem(tab, item) end,
        getItemColor = function(item) return IWTexturesTab.color(tab, item) end,
        getItemMeter = function(item) return IWTexturesTab.meter(tab, item) end,
        getItemLayer = function(item) return IWTexturesTab.layerId(tab, item) end,
        getItemPreview = function(item) return IWTexturesTab.preview(tab, item) end,
        getButtons = function(item) return IWTexturesTab.buttons(tab, item) end,
        onDoubleClick = function(item) IWTexturesTab.doubleClick(tab, item) end,
        onBack = function() return IWTexturesTab.back(tab) end,
    }
end

function IWTexturesTab.register(waila, tab, label, icon)
    if waila == nil or waila.registerDebugTab == nil then
        return false
    end
    if waila.unregisterDebugTab ~= nil then
        waila.unregisterDebugTab(IWTexturesTab.ID)
    end
    waila.registerDebugTab(IWTexturesTab.descriptor(tab, label, icon))
    return true
end
