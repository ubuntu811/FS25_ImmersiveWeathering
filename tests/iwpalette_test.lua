-- plain Lua: grass grows, it never shrinks (IWFoliagePalette:growStage)
local passed, failed = 0, 0
local function check(name, ok) if ok then passed = passed + 1 else failed = failed + 1; print("  FAIL " .. name) end end
Class = function() return {} end
dofile("scripts/IWFoliagePalette.lua")
local P = IWFoliagePalette
local meadow = { sequential = true, stageMin = 1, stageMax = 4 }
check("a young meadow grows one stage", P.growStage(nil, meadow, 2) == 3)
check("... up to its curated maximum", P.growStage(nil, meadow, 3) == 4)
check("at the maximum it stays", P.growStage(nil, meadow, 4) == 4)
check("meadow beyond the curated maximum (the map's own tall meadow, state 7) is NOT cut back to 4", P.growStage(nil, meadow, 7) == 7)
check("no stage read: starts at the minimum plus one", P.growStage(nil, meadow, nil) == 2)
check("a frozen entry (grow=false) stays", P.growStage(nil, { sequential = true, grow = false, stageMin = 1, stageMax = 4 }, 2) == 2)
check("a pool of species (not sequential) never changes", P.growStage(nil, { sequential = false, stageMin = 1, stageMax = 14 }, 5) == 5)
-- what a tyre does to the foliage on a texel it wears: one stage down, the last one removed
local T = P.trampleStage
check("a meadow stage goes one down per pass (4 to 3, 3 to 2, 2 to 1)", T(meadow, 4) == 3 and T(meadow, 3) == 2 and T(meadow, 2) == 1)
check("the lowest stage is removed (nil)", T(meadow, 1) == nil)
check("the map's tall meadow (state 7, stageMax 4) comes down to 3 at once", T(meadow, 7) == 3)
check("something without stages (a bush, a pool of species) is removed, and so is something unknown", T({ sequential = false, stageMin = 1, stageMax = 14 }, 5) == nil and T(nil, 3) == nil and T(meadow, nil) == nil)
print(string.format("iwpalette_test: %d/%d passed", passed, passed + failed))
os.exit(failed == 0 and 0 or 1)
