-- IWPaintCells.lua -- tyre painting per terrain texel: which texel cells lie under a wheel's contact patch, and which of them were painted lately (a cell is painted once per pass, not re-rolled every frame).
-- Pure: no engine calls, so it runs offline.
IWPaintCells = {}

-- The texel cells whose centre lies inside the parallelogram (x1, z1) + u * (x0 - x1, z0 - z1) + v * (x2 - x0, z2 - z0), u and v in 0..1 (the corners the wheel code builds: x1 the (-w, -len) corner, x0 the (+w, -len)
-- one, x2 the (+w, +len) one). cell: the texel size in metres, the grid starts at the world origin. Returns a list of { i, j, cx, cz }, at most maxCells (the nearest to the middle are not preferred: the list is in grid order).
function IWPaintCells.cellsIn(x0, z0, x1, z1, x2, z2, cell, maxCells)
    local ax, az = x0 - x1, z0 - z1
    local bx, bz = x2 - x0, z2 - z0
    local det = ax * bz - az * bx
    local cells = {}
    if math.abs(det) < 1e-9 then
        return cells
    end
    local minX = math.min(x0, x1, x2, x2 + (x1 - x0))
    local maxX = math.max(x0, x1, x2, x2 + (x1 - x0))
    local minZ = math.min(z0, z1, z2, z2 + (z1 - z0))
    local maxZ = math.max(z0, z1, z2, z2 + (z1 - z0))
    local i0, i1 = math.floor(minX / cell), math.floor(maxX / cell)
    local j0, j1 = math.floor(minZ / cell), math.floor(maxZ / cell)
    for i = i0, i1 do
        for j = j0, j1 do
            local cx, cz = (i + 0.5) * cell, (j + 0.5) * cell
            local px, pz = cx - x1, cz - z1
            local u = (px * bz - pz * bx) / det
            local v = (ax * pz - az * px) / det
            if u >= 0 and u <= 1 and v >= 0 and v <= 1 then
                cells[#cells + 1] = { i, j, cx, cz }
                if maxCells ~= nil and #cells >= maxCells then
                    return cells
                end
            end
        end
    end
    return cells
end

-- Which cells were decided lately, by whom, and with which version of the texture set. A pass is one vehicle crossing a cell: its tyres in the same rut, and its frames, find the cell decided already for ttl
-- milliseconds; the next pass of that vehicle, or another vehicle, decides it again (every pass leaves its trace). A new version (the player picked another texture) makes everything due at once.
-- Entries older than the ttl are dropped when the table gets bigger than maxEntries.
IWPaintCells.Recent = {}
local Recent_mt = { __index = IWPaintCells.Recent }

function IWPaintCells.newRecent(ttlMs, maxEntries)
    return setmetatable({ ttl = ttlMs, max = maxEntries or 20000, at = {}, count = 0 }, Recent_mt)
end

local function key(i, j)
    return i * 4194304 + j                          -- (cell indices are within +-4096 at the smallest cell size; the key is unique then)
end

function IWPaintCells.Recent:isFresh(i, j, now, version, owner)
    local entry = self.at[key(i, j)]
    return entry ~= nil and entry[2] == (version or 0) and entry[3] == owner and now - entry[1] < self.ttl and now >= entry[1]
end

function IWPaintCells.Recent:mark(i, j, now, version, owner)
    local k = key(i, j)
    if self.at[k] == nil then
        self.count = self.count + 1
    end
    self.at[k] = { now, version or 0, owner }
    if self.count > self.max then
        self:prune(now)
    end
end

-- A cell that was marked but not painted after all (the frame's paint budget ran out) is due again at once.
function IWPaintCells.Recent:unmark(i, j)
    local k = key(i, j)
    if self.at[k] ~= nil then
        self.at[k] = nil
        self.count = self.count - 1
    end
end

-- Drops the cells that are due again; when that is not enough (everything is recent) all of them.
function IWPaintCells.Recent:prune(now)
    local kept = 0
    for k, entry in pairs(self.at) do
        if now - entry[1] >= self.ttl or now < entry[1] then
            self.at[k] = nil
        else
            kept = kept + 1
        end
    end
    if kept > self.max then
        self.at, kept = {}, 0
    end
    self.count = kept
end

-- A roller: the game's roller specialization, or a vehicle called roller (the mods' own are not always one). Pure.
function IWPaintCells.isRoller(vehicle)
    if vehicle == nil then
        return false
    end
    if vehicle.spec_roller ~= nil then
        return true
    end
    return tostring(vehicle.configFileName or ""):lower():find("roller", 1, true) ~= nil
end

-- Does this vehicle carry a roller (attached to it, or to what is attached to it, two levels)? Its own tyres then do not paint: the roller lays the texture.
function IWPaintCells.carriesRoller(vehicle, depth)
    local joints = vehicle ~= nil and vehicle.spec_attacherJoints or nil
    if joints == nil or joints.attachedImplements == nil or (depth or 0) >= 2 then
        return false
    end
    for _, implement in ipairs(joints.attachedImplements) do
        local object = implement.object
        if object ~= nil and (IWPaintCells.isRoller(object) or IWPaintCells.carriesRoller(object, (depth or 0) + 1)) then
            return true
        end
    end
    return false
end
