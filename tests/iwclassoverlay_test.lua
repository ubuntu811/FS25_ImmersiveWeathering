-- plain Lua: the window, the runs and the counting of the class overlay (IWClassOverlay); the engine calls are not exercised
local passed, failed = 0, 0
local function check(name, ok) if ok then passed = passed + 1 else failed = failed + 1; print("  FAIL " .. name) end end
dofile("scripts/IWClassOverlay.lua")
local O = IWClassOverlay
check("every class has a value 1..7 and a colour", O.valueOf("field") == 1 and O.valueOf("other") == 7 and O.valueOf("meadow") == 5 and (function() for _, c in ipairs(O.ORDER) do if O.COLORS[c] == nil then return false end end return true end)())
local w = O.window(1000, -500, 384, 4)
check("the window is 192 cells of 4 m with its edges on the cell grid", w.cells == 192 and w.minX % 4 == 0 and w.minZ % 4 == 0 and math.abs((w.minX + 384) - 1000) <= 4 and math.abs((w.minZ + 384) + 500) <= 4)
check("a window is never larger than the cap", O.window(0, 0, 5000, 1).cells == O.MAX_CELLS and O.window(0, 0, 0.1, 4).cells == 1)
local r = O.runs({ [0] = 5, 5, 5, 6, 6, 1, 5 }, 7)
check("runs of equal values", #r == 4 and r[1][1] == 0 and r[1][2] == 3 and r[1][3] == 5 and r[2][3] == 6 and r[3][3] == 1 and r[4][1] == 6 and r[4][2] == 7)
check("an empty row has no runs", #O.runs({}, 0) == 0)
local counts, mats = {}, {}
local classify = function(x, z) return x < 10 and "meadow" or "bare" end
local material = function(x, z) return x < 5 and 2 or 1 end
local v1 = O.sampleCell(1, 0, classify, material, counts, mats)
local v2 = O.sampleCell(7, 0, classify, material, counts, mats)
local v3 = O.sampleCell(20, 0, classify, material, counts, mats)
check("a cell returns its class value and is counted per class and per material", v1 == 5 and v2 == 5 and v3 == 6 and counts.meadow == 2 and counts.bare == 1 and mats[2].meadow == 1 and mats[1].meadow == 1 and mats[1].bare == 1)
local text, lines = O.summary(counts, mats, 3)
check("the summary names classes with shares and every material with what it became", text:find("meadow 2 %(67%%%)") ~= nil and text:find("bare 1") ~= nil and #lines == 2 and lines[1]:find("material 1 %-> ") ~= nil and lines[1]:find("meadow 1, bare 1") ~= nil)
local added = {}
local waila = { addDebugAction = function(tab, entry) added[#added + 1] = { tab = tab, entry = entry }; return true end }
check("two rows go to the Terrain tab, with a label that says what the picture does", O.registerRows(waila, {}) and #added == 2 and added[1].tab == "terrain" and added[1].entry.key ~= added[2].entry.key and added[1].entry.getLabel():find("off") ~= nil and added[2].entry.getLabel():find("2 km") ~= nil)
check("a hub without addDebugAction gets nothing (and is tried again later)", O.registerRows({}, {}) == false and O.registerRows(nil, {}) == false)
check("no scan is not busy", added[1].entry.isBusy() == false)
O.job = { win = { cells = 10 }, row = 5, col = 0 }
check("a running scan says how far it is and is busy", O.status():find("scanning, 50%%") ~= nil and added[1].entry.isBusy() == true)
O.job = nil
print(string.format("iwclassoverlay_test: %d/%d passed", passed, passed + failed))
os.exit(failed == 0 and 0 or 1)
