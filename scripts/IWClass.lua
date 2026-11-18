-- IWClass.lua -- what a place LOOKS LIKE, so that IW acts on "meadow" and not on "terrain material 2". The answer comes from WAILA's layers (published through g_currentMission.wailaTrailTracer: buildings,
-- roads, forest, trails, read from the saved layer bitmaps), WAILA's field blobs (a field dug in with TerraFarm is no game field) and the game's own field test, and from the terrain material for what is left:
--   field     a field (the game's, or a blob WAILA found): never touched
--   building  under a roof outline          road      on a road or on its verge (ROAD_MARGIN_M)          forest   in a forest area
--   meadow    grass ground, nothing above applies (flowers and the like may be placed here)
--   bare      dirt, gravel or sand ground that is not a road, a building, a field or forest: a trail, a rut, a yard, a parking lot (grass may grow back IN from the side, nothing is seeded)
--   other     anything else (stone, concrete, water, a material this map names differently)
-- Every dependency is passed in (deps), so it runs offline: deps.material(x, z) -> terrain material id, deps.gameField(x, z), deps.wailaField(x, z), deps.tracer (the WAILA table or nil),
-- deps.grassMaterial, deps.bareMaterials (a set). The cheap reads come first; the dearest one (WAILA's field index walks its polygons) only for ground that could be meadow or bare.
IWClass = {}
IWClass.FIELD, IWClass.BUILDING, IWClass.ROAD, IWClass.FOREST, IWClass.MEADOW, IWClass.BARE, IWClass.OTHER = "field", "building", "road", "forest", "meadow", "bare", "other"

-- WAILA's road layer is narrower than the asphalt, so ground within ROAD_MARGIN_M of a road cell counts as road too.
IWClass.ROAD_MARGIN_M = 2.0

local function nearRoad(tracer, x, z)
    local m = IWClass.ROAD_MARGIN_M
    return tracer.sampleDrivable(x + m, z) == 2 or tracer.sampleDrivable(x - m, z) == 2
        or tracer.sampleDrivable(x, z + m) == 2 or tracer.sampleDrivable(x, z - m) == 2
end

function IWClass.classify(x, z, deps)
    local material = deps.material(x, z)
    if material ~= deps.grassMaterial and not deps.bareMaterials[material] then
        return IWClass.OTHER
    end
    local tracer = deps.tracer
    local drivable = 0
    if tracer ~= nil then
        if tracer.sampleBuilding ~= nil and tracer.sampleBuilding(x, z) then
            return IWClass.BUILDING
        end
        drivable = tracer.sampleDrivable ~= nil and tracer.sampleDrivable(x, z) or 0
        if drivable == 2 then
            return IWClass.ROAD
        end
        if tracer.sampleDrivable ~= nil and nearRoad(tracer, x, z) then
            return IWClass.ROAD
        end
        if tracer.sampleForest ~= nil and tracer.sampleForest(x, z) then
            return IWClass.FOREST
        end
    end
    if deps.gameField(x, z) or deps.wailaField(x, z) then
        return IWClass.FIELD
    end
    if drivable == 1 or material ~= deps.grassMaterial then
        return IWClass.BARE                                  -- (a worn trail is bare ground whatever the material says)
    end
    return IWClass.MEADOW
end

-- How grassy the ground around a point is, 0 to 1: the ring at 3 m counts twice, the ring at 6 m once, 8 points each. A rut in a meadow reads near 1, the middle of a yard or a field of dirt near 0, the border
-- of a parking lot about half.
IWClass.RINGS = { { 3, 2 }, { 6, 1 } }
function IWClass.grassShare(x, z, deps)
    local grass, total = 0, 0
    for _, ring in ipairs(IWClass.RINGS) do
        local radius, weight = ring[1], ring[2]
        for k = 0, 7 do
            local angle = k * math.pi / 4
            if deps.material(x + math.cos(angle) * radius, z + math.sin(angle) * radius) == deps.grassMaterial then
                grass = grass + weight
            end
            total = total + weight
        end
    end
    return total > 0 and grass / total or 0
end
