-- plain Lua: a saved dial index keeps its percentage when the list gets finer (IWLevels)
local passed, failed = 0, 0
local function check(name, ok) if ok then passed = passed + 1 else failed = failed + 1; print("  FAIL " .. name) end end
dofile("scripts/IWLevels.lua")
local old = { 0, 20, 40, 60, 80, 100 }
local ok = true
for i = 1, 6 do ok = ok and (IWLevels.migrateWither(i) - 1) * 10 == old[i] end
check("each old level (0 20 40 60 80 100%) lands on the same percentage in the 10% list", ok)
check("20% (the old default, index 2) is index 3 now, 100% (index 6) is 11", IWLevels.migrateWither(2) == 3 and IWLevels.migrateWither(6) == 11)
check("a missing or out-of-range index is clamped", IWLevels.migrateWither(nil) == 1 and IWLevels.migrateWither(99) == 11 and IWLevels.migrateWither(0) == 1)
-- the 10% list (11 steps) to the finer-at-the-bottom list
local M = IWLevels.migrateWitherSparse
check("0, 10, 20, 30, 40, 50 and 100% keep their percentage", IWLevels.WITHER_PERCENT[M(1)] == 0 and IWLevels.WITHER_PERCENT[M(2)] == 10 and IWLevels.WITHER_PERCENT[M(3)] == 20 and IWLevels.WITHER_PERCENT[M(4)] == 30 and IWLevels.WITHER_PERCENT[M(5)] == 40 and IWLevels.WITHER_PERCENT[M(6)] == 50 and IWLevels.WITHER_PERCENT[M(11)] == 100)
check("60, 70, 80 and 90% go to the nearest (50 or 75, 75, 75, 100)", IWLevels.WITHER_PERCENT[M(7)] == 50 or IWLevels.WITHER_PERCENT[M(7)] == 75)
check("70 and 80% become 75, 90% becomes 100", IWLevels.WITHER_PERCENT[M(8)] == 75 and IWLevels.WITHER_PERCENT[M(9)] == 75 and IWLevels.WITHER_PERCENT[M(10)] == 100)
check("an index out of range is clamped", M(nil) == 1 and M(99) == 11)
print(string.format("iwlevels_test: %d/%d passed", passed, passed + failed))
os.exit(failed == 0 and 0 or 1)
