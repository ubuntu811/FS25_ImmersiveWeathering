-- IWFoliageSets.lua -- named foliage sets: a list of foliage names with a chance in percent each (a roll that lands past the sum plants nothing). Three built-in sets belong to a ground class (meadow, bare, forest) and
-- are what IW seeds on that ground: the map's iw-map.xml gives the default (the meadow gets its <foliageMapping> palette, the others nothing) and the player's edit replaces it. The player's own sets are not bound to any
-- ground: the construction screen paints them (a mix of bushes, flowers and grass anywhere), the hub adds, renames, duplicates and deletes them. Saved per map (IWFoliageStore). Pure: no engine calls, so it runs offline.
IWFoliageSets = {}
local IWFoliageSets_mt = { __index = IWFoliageSets }

-- The classes IW may seed on (a field, a road and a building are never seeded); a built-in set's key is its class.
IWFoliageSets.CLASSES = { "meadow", "bare", "forest" }
IWFoliageSets.CLASS_TITLE = { meadow = "Meadow", bare = "Bare ground", forest = "Forest floor" }
IWFoliageSets.DEFAULT_CHANCE = 10

local function copyEntries(entries)
    local out = {}
    for _, e in ipairs(entries or {}) do
        out[#out + 1] = { name = e.name, state = e.state, chance = e.chance }
    end
    return out
end

-- defaults: { meadow = { { name = "decoBush", chance = 1 }, ... }, bare = { ... } }
function IWFoliageSets.new(defaults)
    local self = setmetatable({ byKey = {}, order = {}, nextId = 1 }, IWFoliageSets_mt)
    for _, class in ipairs(IWFoliageSets.CLASSES) do
        local entries = defaults ~= nil and defaults[class] or nil
        self.byKey[class] = { key = class, name = IWFoliageSets.CLASS_TITLE[class], builtin = true, entries = copyEntries(entries), default = copyEntries(entries), edited = false }
        self.order[#self.order + 1] = class
    end
    return self
end

function IWFoliageSets:count()
    return #self.order
end

function IWFoliageSets:keyAt(index)
    return self.order[index]
end

function IWFoliageSets:indexOf(key)
    for i, k in ipairs(self.order) do
        if k == key then
            return i
        end
    end
    return nil
end

function IWFoliageSets:get(key)
    return self.byKey[key]
end

function IWFoliageSets:entries(key)
    local set = self.byKey[key]
    return set ~= nil and set.entries or {}
end

function IWFoliageSets:isEdited(key)
    local set = self.byKey[key]
    return set ~= nil and set.edited
end

-- An entry is a foliage layer (state nil: the layer's own pick, a random plant for a pool of plants, the first stage for a growth ladder) or one state of it (a particular plant, a particular stage).
local function matches(e, name, state)
    return e.name == name and e.state == state
end

function IWFoliageSets:chanceOf(key, name, state)
    for _, e in ipairs(self:entries(key)) do
        if matches(e, name, state) then
            return e.chance
        end
    end
    return nil
end

-- How many particular states of a layer the set lists.
function IWFoliageSets:stateCount(key, name)
    local n = 0
    for _, e in ipairs(self:entries(key)) do
        if e.name == name and e.state ~= nil then
            n = n + 1
        end
    end
    return n
end

function IWFoliageSets.chanceSum(set)
    local sum = 0
    for _, e in ipairs(set.entries) do
        sum = sum + e.chance
    end
    return sum
end

-- The weighted pick: the chances are percent of a roll, what is left over plants nothing. random() is math.random. Returns a foliage name and its state (nil: the layer's own pick), or nil.
function IWFoliageSets:pick(key, random)
    local roll = random() * 100
    local cumulative = 0
    for _, e in ipairs(self:entries(key)) do
        cumulative = cumulative + e.chance
        if roll <= cumulative then
            return e.name, e.state
        end
    end
    return nil
end

local function touch(set)
    set.edited = true
end

-- Puts a foliage in the set (at DEFAULT_CHANCE) or takes it out. Returns true when it is in the set now.
function IWFoliageSets:toggle(key, name, state)
    local set = self.byKey[key]
    if set == nil then
        return false
    end
    for i, e in ipairs(set.entries) do
        if matches(e, name, state) then
            table.remove(set.entries, i)
            touch(set)
            return false
        end
    end
    set.entries[#set.entries + 1] = { name = name, state = state, chance = IWFoliageSets.DEFAULT_CHANCE }
    touch(set)
    return true
end

-- Sets the chance (0..100) of a foliage that is in the set. Returns the new chance.
function IWFoliageSets:setChance(key, name, chance, state)
    local set = self.byKey[key]
    if set == nil then
        return nil
    end
    chance = math.max(0, math.min(100, chance))
    for _, e in ipairs(set.entries) do
        if matches(e, name, state) then
            e.chance = chance
            touch(set)
            return chance
        end
    end
    return nil
end

function IWFoliageSets:addChance(key, name, delta, state)
    local current = self:chanceOf(key, name, state)
    return current ~= nil and self:setChance(key, name, current + delta, state) or nil
end

-- A built-in set goes back to the map's list.
function IWFoliageSets:reset(key)
    local set = self.byKey[key]
    if set ~= nil and set.builtin then
        set.entries = copyEntries(set.default)
        set.edited = false
    end
end

local function freshKey(self)
    while self.byKey["set" .. self.nextId] ~= nil do
        self.nextId = self.nextId + 1
    end
    return "set" .. self.nextId
end

-- A new empty set of the player's. Returns its key.
function IWFoliageSets:add(name)
    local key = freshKey(self)
    self.byKey[key] = { key = key, name = name or ("Foliage set " .. self.nextId), builtin = false, entries = {}, edited = true }
    self.order[#self.order + 1] = key
    return key
end

function IWFoliageSets:duplicate(key)
    local set = self.byKey[key]
    if set == nil then
        return nil
    end
    local copyKey = self:add(set.name .. " copy")
    self.byKey[copyKey].entries = copyEntries(set.entries)
    return copyKey
end

-- The player's sets can be renamed (the built-in ones are named after their ground). Returns true when it did.
function IWFoliageSets:rename(key, name)
    local set = self.byKey[key]
    if set == nil or set.builtin or name == nil or name == "" then
        return false
    end
    set.name = name
    return true
end

function IWFoliageSets:remove(key)
    local set = self.byKey[key]
    if set == nil or set.builtin then
        return false
    end
    self.byKey[key] = nil
    table.remove(self.order, self:indexOf(key))
    return true
end

-- Plain tables for the file, in order: the edited built-in sets (the others follow the map) and all the player's sets.
function IWFoliageSets:serialize()
    local out = {}
    for _, key in ipairs(self.order) do
        local set = self.byKey[key]
        if set.edited or not set.builtin then
            out[#out + 1] = { key = key, name = set.name, builtin = set.builtin, edited = true, entries = copyEntries(set.entries) }
        end
    end
    return out
end

function IWFoliageSets:restore(saved)
    for _, s in ipairs(saved or {}) do
        local set = self.byKey[s.key]
        if set ~= nil and set.builtin then
            if s.edited then
                set.entries = copyEntries(s.entries)
                set.edited = true
            end
        elseif set == nil and not s.builtin and s.key ~= nil then
            self.byKey[s.key] = { key = s.key, name = s.name or s.key, builtin = false, entries = copyEntries(s.entries), edited = true }
            self.order[#self.order + 1] = s.key
        end
    end
end

-- What other mods get (published as g_currentMission.immersiveWeatheringFoliage): the sets by key, resolved to what can be written. palette needs findEntry(name), pickInitialStage(entry), getWriteName(entry, stage).
--   api.list()      -> { { key, name, builtin } } in order
--   api.entries(k)  -> { { name, state (nil: the layer's own pick), chance } } (a copy)
--   api.pick(k)     -> { name, writeName, stage, sequential } or nil (an entry with a state plants exactly that plant / stage) (the set's weighted pick, ready for applyDecoFoliage; nil: the roll planted nothing, or the set / foliage is unknown)
function IWFoliageSets.api(getSets, getPalette, random)
    local api = {}
    function api.list()
        local sets, out = getSets(), {}
        for i = 1, sets:count() do
            local set = sets:get(sets:keyAt(i))
            out[i] = { key = set.key, name = set.name, builtin = set.builtin }
        end
        return out
    end
    function api.entries(key)
        return copyEntries(getSets():entries(key))
    end
    function api.pick(key)
        local name, state = getSets():pick(key, random or math.random)
        local palette = getPalette()
        local entry = name ~= nil and palette ~= nil and palette:findEntry(name) or nil
        if entry == nil then
            return nil
        end
        local stage = state or palette:pickInitialStage(entry)
        return { name = name, writeName = palette:getWriteName(entry, stage), stage = stage, sequential = entry.sequential == true }
    end
    return api
end
