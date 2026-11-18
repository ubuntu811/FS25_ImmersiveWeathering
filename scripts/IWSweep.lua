-- IWSweep.lua -- the weathering sweep as background work. The nightly batch (10000 samples at once: 450 to 1000 ms in a single frame) ran once per game day change, and a game that runs one day a month at half
-- speed gets one a couple of real days: two sweeps in the whole log, 2 to 5 seedlings each. So the sweep is time-sliced instead: a few samples a frame within a millisecond budget, a new pass every few real
-- minutes (a setting, or the old once per game day), and the samples are spread EVENLY over the whole map: a place nobody has been to for a while grows in just the same as the one next to the player.
IWSweep = {}
IWSweep.INTERVAL_MIN = { 0, 10, 5, 2 }       -- by setting index: 0 = the old way (once per game day), else a pass every this many real minutes
IWSweep.INTERVAL_DEFAULT_INDEX = 3
IWSweep.BUDGET_MS = 0.4                      -- a frame's work at most (a sample takes 45 to 100 microseconds: 4 to 9 of them)

-- The real-time interval of a setting index in milliseconds, nil for the calendar.
function IWSweep.intervalMs(index)
    local minutes = IWSweep.INTERVAL_MIN[index] or 0
    return minutes > 0 and minutes * 60000 or nil
end

-- Grid side and cell stride for `total` samples (cached).
local gridCache = {}
function IWSweep.gridOf(total)
    local grid = gridCache[total]
    if grid == nil then
        local side = math.max(1, math.ceil(math.sqrt(total)))
        local cells = side * side
        local stride = math.max(1, math.floor(cells * 0.6180339887))
        local function gcd(a, b) while b ~= 0 do a, b = b, a % b end return a end
        while gcd(stride, cells) ~= 1 do
            stride = stride + 1
        end
        grid = { side, stride }
        gridCache[total] = grid
    end
    return grid[1], grid[2]
end

-- Sample `index` (0-based) of `total`: one grid cell each, visited in scattered order, random spot in the cell. Even coverage.
function IWSweep.pickPoint(random, terrainSize, index, total)
    local side, stride = IWSweep.gridOf(total)
    local cells = side * side
    local cell = (index * stride) % cells
    local size = terrainSize / side
    local half = terrainSize * 0.5
    return -half + ((cell % side) + random()) * size, -half + (math.floor(cell / side) + random()) * size
end

-- One pass: `total` samples to do.
function IWSweep.new(total)
    return { total = total, remaining = total, stats = {} }
end

-- Does samples until the budget (ms, by clock() in seconds) is used up or the pass is done: work(pass) is called once per sample. Returns true when the pass is finished.
function IWSweep.advance(pass, budgetMs, clock, work)
    local start = clock()
    while pass.remaining > 0 do
        work(pass)
        pass.remaining = pass.remaining - 1
        if (clock() - start) * 1000 >= budgetMs then
            break
        end
    end
    return pass.remaining <= 0
end
