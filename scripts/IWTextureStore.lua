-- IWTextureStore.lua -- the texture sets of a map on disk: modSettings/FS25_ImmersiveWeathering/textures_<map>.xml (layer names belong to a map, so the file does too). The sets themselves are IWTextureSets'.
IWTextureStore = {}

local SCHEMA = XMLSchema.new("FS25_ImmersiveWeatheringTextures")
SCHEMA:register(XMLValueType.STRING, "textures.set(?)#name")
SCHEMA:register(XMLValueType.BOOL, "textures.set(?)#builtin")
SCHEMA:register(XMLValueType.STRING, "textures.set(?)#groundName")
SCHEMA:register(XMLValueType.BOOL, "textures.set(?)#edited")
SCHEMA:register(XMLValueType.INT, "textures.set(?)#block")
SCHEMA:register(XMLValueType.BOOL, "textures.set(?)#force")
SCHEMA:register(XMLValueType.BOOL, "textures.set(?)#matchDetails")
SCHEMA:register(XMLValueType.STRING, "textures.set(?)#foliage")
SCHEMA:register(XMLValueType.STRING, "textures.set(?).texture(?)#layer")
SCHEMA:register(XMLValueType.INT, "textures.set(?).texture(?)#weight")
SCHEMA:register(XMLValueType.STRING, "textures.set(?).pattern.row(?)#cells")
SCHEMA:register(XMLValueType.STRING, "textures.set(?).detail(?)#layer")
SCHEMA:register(XMLValueType.STRING, "textures.set(?).detail(?)#shape")
SCHEMA:register(XMLValueType.FLOAT, "textures.set(?).detail(?)#chance")
SCHEMA:register(XMLValueType.INT, "textures.set(?).detail(?)#size")

function IWTextureStore.path(mapId)
    local name = tostring(mapId or "map"):gsub("[^%w_]", "_")
    local folder = getUserProfileAppPath() .. "modSettings/FS25_ImmersiveWeathering/"
    createFolder(folder)
    return folder .. "textures_" .. name .. ".xml"
end

-- The saved sets (what IWTextureSets:serialize wrote), or nil when there is no file.
function IWTextureStore.load(path)
    local xmlFile = XMLFile.loadIfExists("IWTextures", path, SCHEMA)
    if xmlFile == nil then
        return nil
    end
    local saved = {}
    xmlFile:iterate("textures.set", function(_, key)
        local set = {
            name = xmlFile:getValue(key .. "#name"),
            builtin = xmlFile:getValue(key .. "#builtin", false),
            groundName = xmlFile:getValue(key .. "#groundName"),
            edited = xmlFile:getValue(key .. "#edited", false) or nil,
            block = xmlFile:getValue(key .. "#block", 1),
            force = xmlFile:getValue(key .. "#force", false) or nil,
            matchDetails = xmlFile:getValue(key .. "#matchDetails", false) or nil,
            foliage = xmlFile:getValue(key .. "#foliage"),
            textures = {},
        }
        xmlFile:iterate(key .. ".texture", function(_, textureKey)
            set.textures[#set.textures + 1] = { layer = xmlFile:getValue(textureKey .. "#layer"), weight = xmlFile:getValue(textureKey .. "#weight", 10) }
        end)
        local rows = {}
        xmlFile:iterate(key .. ".pattern.row", function(_, rowKey)
            rows[#rows + 1] = xmlFile:getValue(rowKey .. "#cells", "")
        end)
        set.pattern = #rows > 0 and rows or nil
        local details = {}
        xmlFile:iterate(key .. ".detail", function(_, detailKey)
            details[#details + 1] = { layer = xmlFile:getValue(detailKey .. "#layer"), shape = xmlFile:getValue(detailKey .. "#shape", "spot"), chance = xmlFile:getValue(detailKey .. "#chance", 0.2), size = xmlFile:getValue(detailKey .. "#size", 2) }
        end)
        set.details = #details > 0 and details or nil
        saved[#saved + 1] = set
    end)
    xmlFile:delete()
    return saved
end

function IWTextureStore.save(path, saved)
    local xmlFile = XMLFile.create("IWTextures", path, "textures", SCHEMA)
    if xmlFile == nil then
        return false
    end
    for i, set in ipairs(saved) do
        local key = string.format("textures.set(%d)", i - 1)
        xmlFile:setValue(key .. "#name", set.name)
        xmlFile:setValue(key .. "#builtin", set.builtin == true)
        if set.groundName ~= nil then
            xmlFile:setValue(key .. "#groundName", set.groundName)
        end
        xmlFile:setValue(key .. "#edited", set.edited == true)
        xmlFile:setValue(key .. "#block", set.block or 1)
        xmlFile:setValue(key .. "#force", set.force == true)
        xmlFile:setValue(key .. "#matchDetails", set.matchDetails == true)
        xmlFile:setValue(key .. "#foliage", set.foliage or "down")
        for j, texture in ipairs(set.textures) do
            local textureKey = string.format("%s.texture(%d)", key, j - 1)
            xmlFile:setValue(textureKey .. "#layer", texture.layer)
            xmlFile:setValue(textureKey .. "#weight", texture.weight)
        end
        for k, detail in ipairs(set.details or {}) do
            local detailKey = string.format("%s.detail(%d)", key, k - 1)
            xmlFile:setValue(detailKey .. "#layer", detail.layer)
            xmlFile:setValue(detailKey .. "#shape", detail.shape)
            xmlFile:setValue(detailKey .. "#chance", detail.chance)
            xmlFile:setValue(detailKey .. "#size", detail.size)
        end
        for r, line in ipairs(set.pattern or {}) do
            xmlFile:setValue(string.format("%s.pattern.row(%d)#cells", key, r - 1), line)
        end
    end
    xmlFile:save()
    xmlFile:delete()
    return true
end
