--[[
    IWFoliageNames.lua -- the real names of a foliage layer's states ("Small", "Blueberry Short", "Boxwood Medium"), read from the layer's own foliage type file the way the game reads it: the file lists its
    <foliageState name="..."> in the order of the density values, so state N is the Nth. The file is found by the layer's name: $data/foliage/<name>/<name>.xml, a regional variant (decoBushEU, decoBushUS,
    decoFoliageAS) in a folder of its own under the base layer's, and the map's own foliage folder next to its map.xml. A layer with no such file (crops, whose states are growth stages) has no names and
    the menu says "plant 3" / "stage 3" as before.
]]
IWFoliageNames = { cache = {} }

local REGION = { "EU", "US", "AS" }
IWFoliageNames.ALIAS = { decoStones = "stone/stone.xml" }

-- decoBushEU -> decoBush (the regions: EU, US, AS). Pure.
function IWFoliageNames.baseOf(name)
    for _, region in ipairs(REGION) do
        if #name > #region and name:sub(-#region) == region then
            return name:sub(1, #name - #region)
        end
    end
    return name
end

-- The places a layer's file may be, in order: { path } (a $data path or a path under the map's folder); mapDir ends with a separator or is nil. Pure. (Found by reading mapEU.i3d's own references.)
function IWFoliageNames.candidates(name, mapDir)
    local out = {}
    local base = name
    for _, region in ipairs(REGION) do
        if #name > #region and name:sub(-#region) == region then
            base = name:sub(1, #name - #region)
        end
    end
    out[#out + 1] = string.format("$data/foliage/%s/%s.xml", name, name)
    if base ~= name then
        out[#out + 1] = string.format("$data/foliage/%s/%s/%s.xml", base, name, name)      -- (decoBushEU: a folder of its own under decoBush)
        out[#out + 1] = string.format("$data/foliage/%s/%s.xml", base, name)               -- (decoFoliageEU: next to decoFoliage's other files)
    end
    out[#out + 1] = string.format("$data/foliage/forestPlants/%s.xml", name)               -- (groundFoliage, smallGroundPlants ...)
    out[#out + 1] = string.format("$data/foliage/%s", IWFoliageNames.ALIAS[name] or "none.xml")  -- (the game's stones layer is called stone)
    if mapDir ~= nil then
        out[#out + 1] = string.format("%sfoliage/%s/%s.xml", mapDir, base, name)
        out[#out + 1] = string.format("%sfoliage/%s/%s.xml", mapDir, name, name)
    end
    return out
end

-- "  Blueberry Short" -> "Blueberry Short" (the files carry stray blanks now and then). Pure.
function IWFoliageNames.clean(text)
    if text == nil then
        return nil
    end
    local trimmed = text:gsub("^%s+", ""):gsub("%s+$", "")
    return trimmed ~= "" and trimmed or nil
end

-- engine side: the names of a layer, { [state] = name }, or an empty table; read once per layer.
function IWFoliageNames.namesOf(name)
    local cached = IWFoliageNames.cache[name]
    if cached ~= nil then
        return cached
    end
    local names = {}
    local mission = g_currentMission
    local mapDir = nil
    if mission ~= nil and mission.baseDirectory ~= nil and mission.missionInfo ~= nil and mission.missionInfo.mapXMLFilename ~= nil then
        local base = mission.baseDirectory
        if base:sub(-1) ~= "/" and base:sub(-1) ~= "\\" then
            base = base .. "/"
        end
        mapDir = base .. Utils.getDirectory(mission.missionInfo.mapXMLFilename)
    end
    for _, candidate in ipairs(IWFoliageNames.candidates(name, mapDir)) do
        local path = Utils.getFilename(candidate, g_currentModDirectory)
        if path ~= nil and fileExists(path) then
            local xmlFile = XMLFile.load("IWFoliageNames", path)
            if xmlFile ~= nil then
                xmlFile:iterate("foliageType.foliageLayer.foliageState", function(index, key)
                    names[index] = IWFoliageNames.clean(xmlFile:getString(key .. "#name"))
                end)
                xmlFile:delete()
            end
            if next(names) ~= nil then
                break
            end
        end
    end
    IWFoliageNames.cache[name] = names
    return names
end

function IWFoliageNames.stateName(name, state)
    return IWFoliageNames.namesOf(name)[state]
end

-- The store icons of the plants: the game's Plants tab is made of store items (data/foliage/**/paintable_*.xml) that carry brush type "foliage", the parameters { layer name, state } and a finished icon (store_*.dds),
-- so the picture of a layer's state is the icon of the item that paints it. The regions (decoBush of EU, base ...) reuse the same layer name and state numbers: the state's real name picks among them.

-- "$data/foliage/decoBush/decoBushEU/store_boxWoodSmall.dds" -> "boxwoodsmall". Pure.
function IWFoliageNames.iconKey(path)
    local file = tostring(path or ""):match("([^/\\]+)$") or ""
    file = file:gsub("%.%w+$", ""):gsub("^store_", "")
    return (file:lower():gsub("[^%a%d]", ""))
end

-- items: { { type = "foliage", parameters = { layer, state }, image = path } } -> { [layer] = { [state] = { path, ... } } }. Pure.
function IWFoliageNames.indexIcons(items)
    local index = {}
    for _, item in ipairs(items) do
        local p = item.parameters
        local state = p ~= nil and tonumber(p[2]) or nil
        if item.type == "foliage" and item.image ~= nil and p ~= nil and p[1] ~= nil and state ~= nil then
            index[p[1]] = index[p[1]] or {}
            index[p[1]][state] = index[p[1]][state] or {}
            table.insert(index[p[1]][state], item.image)
        end
    end
    return index
end

-- Which of the icons of one state: the one whose file name is the state's name ("Blueberry Small" -> store_decoBushBlueberry_small), else the first. Pure.
function IWFoliageNames.pickIcon(paths, stateName)
    if paths == nil or #paths == 0 then
        return nil
    end
    local wanted = stateName ~= nil and IWFoliageNames.iconKey(stateName) or ""
    if #paths > 1 and wanted ~= "" then
        for _, path in ipairs(paths) do
            if IWFoliageNames.iconKey(path) == wanted then
                return path
            end
        end
        for _, path in ipairs(paths) do
            local key = IWFoliageNames.iconKey(path)
            if key:sub(-#wanted) == wanted or wanted:sub(-#key) == key then
                return path
            end
        end
    end
    return paths[1]
end

-- Of the icons of one state, the ones of the layer's own region: a file in a folder named after the layer (decoBush/decoBushEU/ for decoBushEU), or a name ending in its region (decoGrassShortEU); a base layer
-- takes the ones in no region's folder. owner is the map's layer name. Pure.
function IWFoliageNames.ofRegion(paths, owner)
    local base = IWFoliageNames.baseOf(owner)
    local region = owner:sub(#base + 1)
    local picked = {}
    for _, path in ipairs(paths) do
        local inRegionFolder = false
        for _, r in ipairs(REGION) do
            if path:find("/" .. base .. r .. "/", 1, true) ~= nil then
                inRegionFolder = true
            end
        end
        local own = region ~= "" and (path:find("/" .. owner .. "/", 1, true) ~= nil or IWFoliageNames.iconKey(path):sub(-#region) == region:lower())
        if (region ~= "" and own) or (region == "" and not inRegionFolder) then
            picked[#picked + 1] = path
        end
    end
    return #picked > 0 and picked or paths
end

-- The icon of a state of a layer (the icons are filed under layer, owner is the map's own name for it: decoBushEU's icons are decoBush's), or (state nil) of the lowest state that has one; nil when there is none.
-- names: { [state] = name }. Pure.
function IWFoliageNames.iconOf(index, layer, state, names, owner)
    local states = index[layer]
    if states == nil then
        return nil
    end
    if state == nil then
        for s in pairs(states) do
            if state == nil or s < state then
                state = s
            end
        end
    end
    local paths = states[state]
    if paths == nil then
        return nil
    end
    return IWFoliageNames.pickIcon(IWFoliageNames.ofRegion(paths, owner or layer), names ~= nil and names[state] or nil)
end

-- engine side: the index of the game's store items (made once), and the lookup the hub uses.
function IWFoliageNames.icons()
    if IWFoliageNames.iconIndex == nil then
        local items = {}
        if g_storeManager ~= nil then
            for _, storeItem in ipairs(g_storeManager:getItems()) do
                if storeItem.brush ~= nil then
                    items[#items + 1] = { type = storeItem.brush.type, parameters = storeItem.brush.parameters, image = storeItem.imageFilename }
                end
            end
        end
        IWFoliageNames.iconIndex = IWFoliageNames.indexIcons(items)
    end
    return IWFoliageNames.iconIndex
end

-- The layer's own name first, then its base (decoBushEU: the icons are filed under decoBush, the state's real name tells the region's).
function IWFoliageNames.iconFor(layer, state)
    local names = IWFoliageNames.namesOf(layer)
    return IWFoliageNames.iconOf(IWFoliageNames.icons(), layer, state, names, layer) or IWFoliageNames.iconOf(IWFoliageNames.icons(), IWFoliageNames.baseOf(layer), state, names, layer)
end
