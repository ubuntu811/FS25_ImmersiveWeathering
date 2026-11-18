-- plain Lua: the texel cells under a wheel's contact patch and the memory of what was painted (IWPaintCells)
local passed, failed = 0, 0
local function check(name, ok) if ok then passed = passed + 1 else failed = failed + 1; print("  FAIL " .. name) end end
dofile("scripts/IWPaintCells.lua")
local C = IWPaintCells

-- a patch along x: 2 m wide (z) and 1 m long (x), corners as the wheel code builds them: x1 = (-w, -len), x0 = (+w, -len), x2 = (+w, +len); the width runs along x0 - x1
-- here: width axis = +x (2 m), length axis = +z (1 m)
local cells = C.cellsIn(2, 0, 0, 0, 2, 1, 0.5)
check("a 2 m x 1 m patch on 0.5 m cells holds 4 x 2 = 8 cell centres", #cells == 8)
local inside = true
for _, c in ipairs(cells) do inside = inside and c[3] > 0 and c[3] < 2 and c[4] > 0 and c[4] < 1 end
check("every centre lies inside the patch", inside)
check("the centres are the grid's (cell + 0.5) * size", cells[1][3] == 0.25 and cells[1][4] == 0.25 and cells[1][1] == 0 and cells[1][2] == 0)
check("a patch smaller than a cell can hold none (a thin tyre between two centres)", #C.cellsIn(0.6, 0.0, 0.0, 0.0, 0.6, 0.1, 0.5) == 0)
check("a degenerate patch (no area) holds none", #C.cellsIn(1, 1, 0, 0, 2, 2, 0.5) == 0)
check("the cap stops the list", #C.cellsIn(6, 0, 0, 0, 6, 1, 0.5, 5) == 5)
-- a patch turned by 45 degrees: about the same area, so about the same number of cells
local s = math.sqrt(0.5)
local turned = C.cellsIn(2 * s, 2 * s, 0, 0, 2 * s - s, 2 * s + s, 0.5)    -- width axis (1,1)/sqrt2 * 2 m, length axis (-1,1)/sqrt2 * 1 m
check("turned 45 degrees the patch (2 m^2) holds about 4 cells of 0.25 m^2 (2 to 10 is fine, not 0 and not a flood)", #turned >= 4 and #turned <= 10)
check("a patch in negative coordinates uses the same grid (cell index floor(x / size))", (function()
    local c = C.cellsIn(-1.5, -1.5, -2, -2, -1.5, -1, 0.5)
    return #c >= 1 and c[1][1] == -4 and c[1][3] == -1.75
end)())

-- what was painted lately
local recent = C.newRecent(1000, 100)
check("a cell nobody painted is not fresh", recent:isFresh(3, 4, 0) == false)
recent:mark(3, 4, 0)
check("a painted cell is fresh for the ttl", recent:isFresh(3, 4, 500) == true and recent:isFresh(3, 4, 999) == true)
check("... then due again", recent:isFresh(3, 4, 1000) == false)
check("another cell is unaffected, negative indices too", recent:isFresh(3, 5, 10) == false and (function() recent:mark(-7, -2, 0); return recent:isFresh(-7, -2, 10) and not recent:isFresh(-7, -3, 10) end)())
check("a clock that jumped back does not keep a cell fresh for ever", recent:isFresh(3, 4, -5000) == false)
check("another vehicle crossing the same cell decides it again at once (every pass leaves its trace)", (function() local r = C.newRecent(8000, 100); r:mark(1, 1, 0, 1, "tractor"); return r:isFresh(1, 1, 100, 1, "tractor") and not r:isFresh(1, 1, 100, 1, "combine") end)())
check("the same vehicle's next pass (after the window) decides it again, its tyres in the same rut within it do not", (function() local r = C.newRecent(8000, 100); r:mark(1, 1, 0, 1, "tractor"); return r:isFresh(1, 1, 7999, 1, "tractor") and not r:isFresh(1, 1, 8000, 1, "tractor") end)())
check("a cell decided with an older version of the set is due again at once (the player picked another texture)", recent:isFresh(3, 4, 10, 1) == false and (function() recent:mark(3, 4, 10, 1); return recent:isFresh(3, 4, 20, 1) and not recent:isFresh(3, 4, 20, 2) end)())
local small = C.newRecent(1000, 3)
for i = 1, 3 do small:mark(i, 0, 0) end
small:mark(10, 0, 5000)
check("the table is pruned when it grows past its size (old entries dropped, the new one kept)", small.count <= 2 and small:isFresh(10, 0, 5001) == true)
local full = C.newRecent(100000, 3)
for i = 1, 4 do full:mark(i, 0, 0) end
check("when everything is recent and the table is too big, it starts over", full.count == 0 and full:isFresh(1, 0, 1) == false)
-- a cell marked but not painted (the budget ran out) is due again
do
    local r = C.newRecent(8000, 100)
    r:mark(2, 3, 0, 1, "roller")
    r:unmark(2, 3)
    check("an un-marked cell is due again at once, and the count follows", r:isFresh(2, 3, 10, 1, "roller") == false and r.count == 0)
    r:unmark(9, 9)
    check("un-marking a cell that was never marked changes nothing", r.count == 0)
end
-- rollers
check("the game's roller specialization or a name with roller is a roller, others are not", C.isRoller({ spec_roller = {} }) and C.isRoller({ configFileName = "mods/FSMCR_Chopper_Roller/chopperRoller.xml" }) and not C.isRoller({ configFileName = "data/vehicles/claas/axion.xml" }) and not C.isRoller(nil))
local roller = { spec_roller = {} }
local tractor = { spec_attacherJoints = { attachedImplements = { { object = roller } } } }
check("a tractor with a roller attached carries one (its own tyres do not paint)", C.carriesRoller(tractor) == true)
check("a tractor with another implement attached does not", C.carriesRoller({ spec_attacherJoints = { attachedImplements = { { object = { configFileName = "plow.xml" } } } } }) == false)
check("a roller behind an implement behind the tractor counts (two levels)", C.carriesRoller({ spec_attacherJoints = { attachedImplements = { { object = { spec_attacherJoints = { attachedImplements = { { object = roller } } } } } } } }) == true)
check("a vehicle with nothing attached, or no joints, does not", C.carriesRoller({ spec_attacherJoints = { attachedImplements = {} } }) == false and C.carriesRoller({}) == false and C.carriesRoller(nil) == false)
print(string.format("iwpaintcells_test: %d/%d passed", passed, passed + failed))
os.exit(failed == 0 and 0 or 1)
