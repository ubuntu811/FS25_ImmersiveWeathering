-- plain Lua: what a place looks like (IWClass): the order of the checks, WAILA's layers, the grass share around a spot
local passed, failed = 0, 0
local function check(name, ok) if ok then passed = passed + 1 else failed = failed + 1; print("  FAIL " .. name) end end
dofile("scripts/IWClass.lua")
local C = IWClass
local GRASS, DIRT, GRAVEL, STONE = 2, 1, 6, 7
local reads = { wailaField = 0 }
local function deps(overrides)
    local d = {
        material = function() return GRASS end,
        gameField = function() return false end,
        wailaField = function() reads.wailaField = reads.wailaField + 1; return false end,
        tracer = nil,
        grassMaterial = GRASS,
        bareMaterials = { [DIRT] = true, [GRAVEL] = true },
    }
    for k, v in pairs(overrides or {}) do d[k] = v end
    return d
end
local tracer = function(t) return { sampleBuilding = t.building or function() return false end, sampleDrivable = t.drivable or function() return 0 end, sampleForest = t.forest or function() return false end } end

check("grass with nothing above it is a meadow", C.classify(0, 0, deps()) == C.MEADOW)
check("dirt or gravel is bare ground", C.classify(0, 0, deps({ material = function() return DIRT end })) == C.BARE and C.classify(0, 0, deps({ material = function() return GRAVEL end })) == C.BARE)
check("stone (concrete, a material the map names differently) is other: never touched", C.classify(0, 0, deps({ material = function() return STONE end })) == C.OTHER)
check("the game's own field wins over grass ground", C.classify(0, 0, deps({ gameField = function() return true end })) == C.FIELD)
check("a field WAILA found (a field dug in with TerraFarm is no game field) is a field too", C.classify(0, 0, deps({ wailaField = function() return true end })) == C.FIELD)
check("a building layer cell is a building, before anything else", C.classify(0, 0, deps({ tracer = tracer({ building = function() return true end, drivable = function() return 2 end }) })) == C.BUILDING)
check("a road cell (drivable 2) is a road, even on grass-coloured ground", C.classify(0, 0, deps({ tracer = tracer({ drivable = function() return 2 end }) })) == C.ROAD)
-- the verge of a road: WAILA's ribbon is narrower than the asphalt
check("ground 1.5 m beside a road cell is road (the verge of the asphalt)", C.classify(1.5, 0, deps({ tracer = tracer({ drivable = function(x, z) return (x >= 3.4 and x <= 3.6) and 2 or 0 end }) })) == C.ROAD)
check("ground 5 m from the road is still meadow", C.classify(0, 0, deps({ tracer = tracer({ drivable = function(x, z) return (x >= 6.9 and x <= 7.1) and 2 or 0 end }) })) == C.MEADOW)
check("the verge of a road beats forest (a forest edge along the asphalt)", C.classify(0, 0, deps({ tracer = tracer({ forest = function() return true end, drivable = function(x, z) return x > 1.9 and x < 2.1 and 2 or 0 end }) })) == C.ROAD)
check("a worn trail (drivable 1) beside a meadow does not make a verge", C.classify(0, 0, deps({ tracer = tracer({ drivable = function(x, z) return x > 1.9 and x < 2.1 and 1 or 0 end }) })) == C.MEADOW)
check("a forest cell is forest", C.classify(0, 0, deps({ tracer = tracer({ forest = function() return true end }) })) == C.FOREST)
check("a worn trail (drivable 1) is bare ground whatever its material says", C.classify(0, 0, deps({ tracer = tracer({ drivable = function() return 1 end }) })) == C.BARE)
check("without WAILA (no tracer) the material and the field tests decide", C.classify(0, 0, deps({ tracer = nil })) == C.MEADOW)

-- cost: the dear read (WAILA's field index) only for ground that could be meadow or bare
reads.wailaField = 0
C.classify(0, 0, deps({ material = function() return STONE end }))
check("ground that cannot be meadow or bare never asks WAILA's field index", reads.wailaField == 0)
C.classify(0, 0, deps({ tracer = tracer({ building = function() return true end }) }))
check("... nor does a building or a road (the cheap layer reads decide first)", reads.wailaField == 0)
C.classify(0, 0, deps())
check("... a meadow candidate asks it once", reads.wailaField == 1)

-- the grass share around a spot
local function ring(grassFn) return deps({ material = grassFn }) end
check("a rut in a meadow (grass all round) reads 1", math.abs(C.grassShare(0, 0, ring(function() return GRASS end)) - 1) < 1e-9)
check("the middle of a bare field reads 0", C.grassShare(0, 0, ring(function() return DIRT end)) == 0)
local half = C.grassShare(0, 0, ring(function(x, z) return x > 0 and GRASS or DIRT end))
check("the edge of a parking lot (grass on one side) reads about a half", half > 0.35 and half < 0.65)
check("the inner ring counts twice: grass at 3 m only is 16 of 24 weights", math.abs(C.grassShare(0, 0, ring(function(x, z) return math.sqrt(x * x + z * z) < 4.5 and GRASS or DIRT end)) - 16 / 24) < 1e-9)

print(string.format("iwclass_test: %d/%d passed", passed, passed + failed))
os.exit(failed == 0 and 0 or 1)
