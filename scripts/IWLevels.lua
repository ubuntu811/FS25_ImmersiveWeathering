-- IWLevels.lua -- saved dial indices that changed meaning when a list got finer steps. Pure.
IWLevels = {}

-- The tyre withering chance had 6 levels (0, 20 ... 100%), now 11 (0, 10 ... 100%): the same percentage keeps its place.
function IWLevels.migrateWither(oldIndex)
    local index = math.max(1, math.min(6, oldIndex or 1))
    return (index - 1) * 2 + 1
end

-- The withering chance list changed again, to 0, 1, 2, 5, 10, 20, 30, 40, 50, 75, 100% (fine at the low end): an index of the 10% list (version 2) goes to the nearest percentage.
IWLevels.WITHER_PERCENT = { 0, 1, 2, 5, 10, 20, 30, 40, 50, 75, 100 }
function IWLevels.migrateWitherSparse(oldIndex)
    local percent = (math.max(1, math.min(11, oldIndex or 1)) - 1) * 10
    local best, bestDistance = 1, math.huge
    for i, value in ipairs(IWLevels.WITHER_PERCENT) do
        local distance = math.abs(value - percent)
        if distance < bestDistance then
            best, bestDistance = i, distance
        end
    end
    return best
end
