-- plain Lua: the row of states of the foliage preview (IWFoliagePreview); the engine calls are not exercised
local passed, failed = 0, 0
local function check(name, ok) if ok then passed = passed + 1 else failed = failed + 1; print("  FAIL " .. name) end end
dofile("scripts/IWFoliagePreview.lua")
local P = IWFoliagePreview
local row = P.row(100, 200, 1, 0, 1, 5, 2)
check("five states in a row, centred on the point, in order", #row == 5 and row[1].state == 1 and row[5].state == 5 and row[3].x == 100 and row[1].x == 96 and row[5].x == 104 and row[1].z == 200)
local diag = P.row(0, 0, 0, 1, 3, 4, 2)
check("along another direction, two states straddle the point", #diag == 2 and diag[1].state == 3 and diag[1].z == -1 and diag[2].z == 1 and diag[1].x == 0)
check("one state sits on the point", #P.row(5, 5, 1, 0, 7, 7) == 1 and P.row(5, 5, 1, 0, 7, 7)[1].x == 5)
local ox, oz, ex, ez, ax, az = P.rect(P.row(0, 0, 1, 0, 1, 3, 2), 1, 0, 2, 1)
check("the wipe rectangle covers the row with a margin along and across", ox < -3 and ex > ox and ez == oz and math.abs((ex - ox) - (4 + 2 * (1 + 0.2))) < 1e-9 and math.abs(math.abs(az - oz) - 2) < 1e-9)
print(string.format("iwfoliagepreview_test: %d/%d passed", passed, passed + failed))
os.exit(failed == 0 and 0 or 1)
