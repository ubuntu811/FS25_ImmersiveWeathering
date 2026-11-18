-- plain Lua: the sweep as background work (IWSweep): the interval setting, where samples land, the time slicing
local passed, failed = 0, 0
local function check(name, ok) if ok then passed = passed + 1 else failed = failed + 1; print("  FAIL " .. name) end end
dofile("scripts/IWSweep.lua")

check("setting 1 is the calendar (no real-time interval), the others are minutes", IWSweep.intervalMs(1) == nil and IWSweep.intervalMs(2) == 10 * 60000 and IWSweep.intervalMs(3) == 5 * 60000 and IWSweep.intervalMs(4) == 2 * 60000 and IWSweep.intervalMs(99) == nil)

-- where the samples land: evenly over the whole map, one in each cell of a grid
local total, size = 10000, 4096
local seen, cells = {}, 0
for i = 0, total - 1 do
    local x, z = IWSweep.pickPoint(math.random, size, i, total)
    if x < -2048 or x >= 2048 or z < -2048 or z >= 2048 then check("a point inside the map", false) end
    local key = math.floor((x + 2048) / 40.96) * 1000 + math.floor((z + 2048) / 40.96)
    if not seen[key] then seen[key] = true; cells = cells + 1 end
end
check("10000 samples fall into 10000 different 41 m cells: one in each", cells == 10000)
-- a pass cut short is still spread: the first 100 samples cover all four quarters of the map and many different rows
local quarters, rows = {}, {}
for i = 0, 99 do
    local x, z = IWSweep.pickPoint(math.random, size, i, total)
    quarters[(x < 0 and 1 or 2) + (z < 0 and 2 or 0)] = true
    rows[math.floor((z + 2048) / 409.6)] = true
end
check("the first 100 samples already reach all four quarters of the map", quarters[1] and quarters[2] and quarters[3] and quarters[4])
local rowCount = 0
for _ in pairs(rows) do rowCount = rowCount + 1 end
check("... and most of the ten bands of the map", rowCount >= 8)
-- a count that is no square, a small one: every sample still has a cell of its own
local odd, oddCells = {}, 0
for i = 0, 1999 do
    local x, z = IWSweep.pickPoint(function() return 0.5 end, size, i, 2000)
    local key = x * 10000 + z
    if not odd[key] then odd[key] = true; oddCells = oddCells + 1 end
end
check("2000 samples (no square) are 2000 different cells", oddCells == 2000)
local x, z = IWSweep.pickPoint(function() return 0.5 end, 4096, 0, 1)
check("a single sample is the middle of the map", x == 0 and z == 0)

-- the time slicing
local clock = 0
local function now() return clock end
local pass = IWSweep.new(100)
local done = IWSweep.advance(pass, 0.4, now, function() clock = clock + 0.00011 end)      -- 0.11 ms a sample, 0.4 ms a frame: 4 samples
check("a frame does samples until its budget is used (4 of 100 at 0.11 ms each against 0.4 ms), not the whole pass", done == false and pass.remaining == 96)
local frames = 1
repeat frames = frames + 1 until IWSweep.advance(pass, 0.4, now, function() clock = clock + 0.00011 end)
check("the pass finishes after 25 frames and says so", frames == 25 and pass.remaining == 0)
local count = 0
local quick = IWSweep.new(3)
check("a pass that is smaller than the budget finishes in one frame", IWSweep.advance(quick, 10, now, function() count = count + 1 end) == true and count == 3)

print(string.format("iwsweep_test: %d/%d passed", passed, passed + failed))
os.exit(failed == 0 and 0 or 1)
