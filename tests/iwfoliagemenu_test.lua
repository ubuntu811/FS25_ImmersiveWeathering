-- plain Lua: the cells and picks of the foliage brush (IWFoliageMenu.plan); the engine calls are not exercised
local passed, failed = 0, 0
local function check(name, ok) if ok then passed = passed + 1 else failed = failed + 1; print("  FAIL " .. name) end end
g_currentModDirectory = "mod/"
dofile("scripts/IWFoliageMenu.lua")
math.randomseed(5)
local function always(name) return function() return name end end

check("a brush of 0.5 m has cells of half a metre, a big one of one metre", IWFoliageMenu.spacingFor(0.25) == 0.5 and IWFoliageMenu.spacingFor(0.5) == 0.75 and IWFoliageMenu.spacingFor(4) == 1.0)
local done = {}
local pts = IWFoliageMenu.plan(10, 10, 2, false, 1, done, always("a"), math.random)
check("a 4 m square plants one foliage per cell, 16 cells (the cells the square touches may add a few)", #pts >= 12 and #pts <= 25)
local inside = true
for _, p in ipairs(pts) do if math.abs(p.x - 10) > 2 or math.abs(p.z - 10) > 2 then inside = false end end
check("every spot lies inside the square", inside)
check("the cells it used are remembered", next(done) ~= nil)
check("a second event on the same place plants nothing: the cells already rolled", #IWFoliageMenu.plan(10, 10, 2, false, 1, done, always("a"), math.random) == 0)
check("a step along the stroke only adds the new cells", #IWFoliageMenu.plan(11, 10, 2, false, 1, done, always("a"), math.random) < #pts)
local circle = IWFoliageMenu.plan(50, 50, 3, true, 1, {}, always("a"), math.random)
local ok = true
for _, p in ipairs(circle) do if (p.x - 50) ^ 2 + (p.z - 50) ^ 2 > 9 + 1e-9 then ok = false end end
check("a circle keeps its spots within the radius", ok and #circle > 5)
local mixed, n = {}, 0
local picks = IWFoliageMenu.plan(0, 0, 8, false, 1, mixed, function() n = n + 1; return n % 3 == 0 and "b" or nil end, math.random)
check("a pick of nil plants nothing in that cell but the cell is used up", #picks > 0 and #picks < n)
check("the cap stops one event, and the cells not reached are left for the next", (function()
    local d = {}
    local first = IWFoliageMenu.plan(0, 0, 8, false, 1, d, always("a"), math.random, 20)
    local second = IWFoliageMenu.plan(0, 0, 8, false, 1, d, always("a"), math.random, 20)
    return #first == 20 and #second > 0 and #second <= 20
end)())
check("a pick that returns the names is planted as given", pts[1].name == "a")
-- the tile's picture: the first foliage of the set that has an icon, else the mod's
local icons = { decoBush = "bush.dds", ["decoFoliage:3"] = "flower3.dds" }
local function iconFor(name, state) return icons[name] or icons[name .. ":" .. tostring(state)] end
check("the first foliage's icon is the tile's", IWFoliageMenu.tileIcon({ { name = "decoBush" }, { name = "decoFoliage", state = 3 } }, iconFor, "mod.dds") == "bush.dds")
check("a first foliage with no icon is skipped", IWFoliageMenu.tileIcon({ { name = "stones" }, { name = "decoFoliage", state = 3 } }, iconFor, "mod.dds") == "flower3.dds")
check("a state's icon is asked with its state", IWFoliageMenu.tileIcon({ { name = "decoFoliage", state = 3 } }, iconFor, "mod.dds") == "flower3.dds")
check("an empty set, or none with an icon: the mod's icon", IWFoliageMenu.tileIcon({}, iconFor, "mod.dds") == "mod.dds" and IWFoliageMenu.tileIcon({ { name = "stones" } }, iconFor, "mod.dds") == "mod.dds")
print(string.format("iwfoliagemenu_test: %d/%d passed", passed, passed + failed))
os.exit(failed == 0 and 0 or 1)
