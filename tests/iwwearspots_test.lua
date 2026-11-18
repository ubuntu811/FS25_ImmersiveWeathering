-- plain Lua: the worn spots IW heals (IWWearSpots): one per cell, the list cap, snapshots, removal
local passed, failed = 0, 0
local function check(name, ok) if ok then passed = passed + 1 else failed = failed + 1; print("  FAIL " .. name) end end
dofile("scripts/IWWearSpots.lua")
local W = IWWearSpots
local w = W.new()
check("a worn spot is remembered", w:add(10.2, 5.7) == true and #w.spots == 1 and w.dirty == true)
check("another spot in the same metre cell is the same spot", w:add(10.9, 5.1) == false and #w.spots == 1)
check("the next cell is a new spot", w:add(11.1, 5.7) == true and #w.spots == 2)
check("negative coordinates get their own cells (floor, not truncation)", w:add(-0.5, -0.5) == true and w:add(0.5, 0.5) == true and #w.spots == 4)
local snap = w:snapshot()
check("a snapshot is a copy of the list", #snap == 4 and snap ~= w.spots)
w:add(50, 50)
check("a spot added during a pass is not in the pass's snapshot", #snap == 4 and #w.spots == 5)
check("removing a spot takes it out of the list and frees its cell", w:remove(snap[1]) == true and #w.spots == 4 and w:add(10.2, 5.7) == true)
check("removing the old spot again does nothing, and the newer spot of that cell stays", w:remove(snap[1]) == false and #w.spots == 5 and w.byCell[snap[1].key] ~= nil)
-- the cap: the oldest goes
W.MAX = 3
local small = W.new()
for i = 1, 5 do small:add(i * 10, 0) end
check("a full list drops the oldest spots and keeps the newest", #small.spots == 3 and small.spots[1].x == 30 and small.spots[3].x == 50 and small.byCell[W.cellKey(10, 0)] == nil)
check("a dropped spot's cell is free again", small:add(10, 0) == true)
print(string.format("iwwearspots_test: %d/%d passed", passed, passed + failed))
os.exit(failed == 0 and 0 or 1)
