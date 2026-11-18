-- IWWearSpots.lua -- where IW itself wore the ground (the tyre paths: grass painted to dirt or gravel). Healing used to rely on a random sample landing within a few decimetres of a 0.4 m spot: with one sample per
-- 100 m2 near the player that is hundreds of passes. Every wear spot is remembered here (one per metre cell, newest kept when the list is full) and visited by every pass: the ruts the player drives into a
-- meadow are exactly the spots that heal. Per savegame (iw-wear.xml next to iw-save.xml), written when the game saves and at the end of a pass that changed it.
IWWearSpots = {}
local IWWearSpots_mt = Class and Class(IWWearSpots) or { __index = IWWearSpots }
IWWearSpots.CELL_M = 1.0
IWWearSpots.MAX = 4000

function IWWearSpots.new()
    return setmetatable({ spots = {}, byCell = {}, dirty = false }, IWWearSpots_mt)
end

-- a number, not a string: add() runs for every wheel contact that wears the ground (no garbage per call)
local function cellKey(x, z)
    return (math.floor(x / IWWearSpots.CELL_M) + 20000) * 40000 + (math.floor(z / IWWearSpots.CELL_M) + 20000)
end
IWWearSpots.cellKey = cellKey

-- Remembers a worn spot, one per cell. When the list is full the oldest goes. Returns true when it was new.
function IWWearSpots:add(x, z)
    local key = cellKey(x, z)
    if self.byCell[key] ~= nil then
        return false
    end
    if #self.spots >= IWWearSpots.MAX then
        local oldest = table.remove(self.spots, 1)
        self.byCell[oldest.key] = nil
    end
    local spot = { x = x, z = z, key = key }
    self.spots[#self.spots + 1] = spot
    self.byCell[key] = spot
    self.dirty = true
    return true
end

-- A snapshot of the list, for a pass: spots added or dropped meanwhile do not shift it.
function IWWearSpots:snapshot()
    local copy = {}
    for i, spot in ipairs(self.spots) do
        copy[i] = spot
    end
    return copy
end

function IWWearSpots:remove(spot)
    if self.byCell[spot.key] ~= spot then
        return false                                          -- (gone already, or the cell holds a newer spot)
    end
    self.byCell[spot.key] = nil
    for i, other in ipairs(self.spots) do
        if other == spot then
            table.remove(self.spots, i)
            break
        end
    end
    self.dirty = true
    return true
end

local function savePath()
    local info = g_currentMission ~= nil and g_currentMission.missionInfo or nil
    return info ~= nil and info.savegameDirectory ~= nil and (info.savegameDirectory .. "/iw-wear.xml") or nil
end

function IWWearSpots:load()
    self.spots, self.byCell, self.dirty = {}, {}, false
    local path = savePath()
    local xmlFile = path ~= nil and XMLFile.load("IWWearSpots", path) or nil
    if xmlFile == nil then
        return
    end
    local index = 0
    while xmlFile:hasProperty(string.format("iwWear.spot(%d)", index)) do
        local key = string.format("iwWear.spot(%d)", index)
        local x, z = xmlFile:getFloat(key .. "#x"), xmlFile:getFloat(key .. "#z")
        if x ~= nil and z ~= nil then
            self:add(x, z)
        end
        index = index + 1
    end
    xmlFile:delete()
    self.dirty = false
    print(string.format("[IWWearSpots] loaded %d worn spot(s)", #self.spots))
end

function IWWearSpots:save()
    local path = savePath()
    if path == nil then
        return
    end
    local xmlFile = XMLFile.create("IWWearSpots", path, "iwWear")
    if xmlFile == nil then
        return
    end
    for index, spot in ipairs(self.spots) do
        local key = string.format("iwWear.spot(%d)", index - 1)
        xmlFile:setFloat(key .. "#x", spot.x)
        xmlFile:setFloat(key .. "#z", spot.z)
    end
    xmlFile:save()
    xmlFile:delete()
    self.dirty = false
end

function IWWearSpots:saveIfDirty()
    if self.dirty then
        self:save()
    end
end
