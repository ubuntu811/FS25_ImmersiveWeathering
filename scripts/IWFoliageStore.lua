-- IWFoliageStore.lua -- the edited foliage sets of a map on disk: modSettings/FS25_ImmersiveWeathering/foliage_<map>.xml (foliage names belong to a map, so the file does too). The sets are IWFoliageSets'.
IWFoliageStore = {}

local SCHEMA = XMLSchema.new("FS25_ImmersiveWeatheringFoliage")
SCHEMA:register(XMLValueType.STRING, "foliage.list(?)#class")        -- (the first version of the file: a built-in set was named by its class)
SCHEMA:register(XMLValueType.STRING, "foliage.list(?)#key")
SCHEMA:register(XMLValueType.STRING, "foliage.list(?)#name")
SCHEMA:register(XMLValueType.BOOL, "foliage.list(?)#builtin")
SCHEMA:register(XMLValueType.STRING, "foliage.list(?).entry(?)#name")
SCHEMA:register(XMLValueType.INT, "foliage.list(?).entry(?)#state")
SCHEMA:register(XMLValueType.FLOAT, "foliage.list(?).entry(?)#chance")

function IWFoliageStore.path(mapId)
    local name = tostring(mapId or "map"):gsub("[^%w_]", "_")
    local folder = getUserProfileAppPath() .. "modSettings/FS25_ImmersiveWeathering/"
    createFolder(folder)
    return folder .. "foliage_" .. name .. ".xml"
end

-- The saved lists (what IWFoliageSets:serialize wrote), or nil when there is no file.
function IWFoliageStore.load(path)
    local xmlFile = XMLFile.loadIfExists("IWFoliage", path, SCHEMA)
    if xmlFile == nil then
        return nil
    end
    local saved = {}
    xmlFile:iterate("foliage.list", function(_, key)
        local list = { key = xmlFile:getValue(key .. "#key") or xmlFile:getValue(key .. "#class"), name = xmlFile:getValue(key .. "#name"), builtin = xmlFile:getValue(key .. "#builtin", true), edited = true, entries = {} }
        xmlFile:iterate(key .. ".entry", function(_, entryKey)
            list.entries[#list.entries + 1] = { name = xmlFile:getValue(entryKey .. "#name"), state = xmlFile:getValue(entryKey .. "#state"), chance = xmlFile:getValue(entryKey .. "#chance", 0) }
        end)
        saved[#saved + 1] = list
    end)
    xmlFile:delete()
    return saved
end

function IWFoliageStore.save(path, saved)
    local xmlFile = XMLFile.create("IWFoliage", path, "foliage", SCHEMA)
    if xmlFile == nil then
        return false
    end
    for i, list in ipairs(saved) do
        local key = string.format("foliage.list(%d)", i - 1)
        xmlFile:setValue(key .. "#key", list.key)
        xmlFile:setValue(key .. "#name", list.name)
        xmlFile:setValue(key .. "#builtin", list.builtin == true)
        for j, e in ipairs(list.entries) do
            local entryKey = string.format("%s.entry(%d)", key, j - 1)
            xmlFile:setValue(entryKey .. "#name", e.name)
            if e.state ~= nil then
                xmlFile:setValue(entryKey .. "#state", e.state)
            end
            xmlFile:setValue(entryKey .. "#chance", e.chance)
        end
    end
    xmlFile:save()
    xmlFile:delete()
    return true
end
