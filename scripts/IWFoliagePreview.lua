--[[
    IWFoliagePreview.lua -- looks at the models of a foliage layer in the world: the hub's "Show in the world" stamps every state of the layer (every plant of a pool, every stage of a growth ladder) in a row
    on the ground where you look, left to right, each with its number floating above it (the numbers of the states menu). "Clear preview" wipes the row again. The numbers go away after LABEL_MS, and the row with them.
    It places real foliage with IW's own stamp, so do it on bare ground: wiping the row also wipes whatever stood there.
]]
IWFoliagePreview = { SPACING = 1.6, LABEL_MS = 90000, HALF_WIDTH = 0.9 }

-- The spots of a row of states min..max centred on (cx, cz), along the direction (rx, rz) (unit): { { state, x, z } } in order.
function IWFoliagePreview.row(cx, cz, rx, rz, min, max, spacing)
    spacing = spacing or IWFoliagePreview.SPACING
    local n = max - min + 1
    local out = {}
    for i = 0, n - 1 do
        local d = (i - (n - 1) / 2) * spacing
        out[#out + 1] = { state = min + i, x = cx + rx * d, z = cz + rz * d }
    end
    return out
end

-- The parallelogram (origin, two edges) that covers a row, for the wipe: along the row from before the first to after the last spot, ±half across it.
function IWFoliagePreview.rect(spots, rx, rz, spacing, half)
    spacing = spacing or IWFoliagePreview.SPACING
    half = half or IWFoliagePreview.HALF_WIDTH
    local first, last = spots[1], spots[#spots]
    local along = spacing / 2 + 0.2
    local ox = first.x - rx * along + rz * half              -- (the across direction is (-rz, rx))
    local oz = first.z - rz * along - rx * half
    local lx, lz = (last.x - first.x) + rx * along * 2, (last.z - first.z) + rz * along * 2
    local ax, az = -rz * half * 2, rx * half * 2
    return ox, oz, ox + lx, oz + lz, ox + ax, oz + az
end

-- ---- engine side ----

local function say(format, ...)
    print(string.format("[ImmersiveWeathering] " .. format, ...))
end

-- The terrain point under the crosshair and the horizontal direction to the right of the view; nil when the terrain is not within 200 m.
function IWFoliagePreview.lookPoint(iw)
    local camera = g_cameraManager:getActiveCamera()
    local x, y, z = getWorldTranslation(camera)
    local dirX, dirY, dirZ = localDirectionToWorld(camera, 0, 0, -1)
    iw.debugFieldRaycastHit = nil
    raycastClosest(x, y, z, dirX, dirY, dirZ, 200, "onDebugFieldRaycastCallback", iw, CollisionFlag.TERRAIN)
    if iw.debugFieldRaycastHit == nil then
        return nil
    end
    local hx, _, hz = unpack(iw.debugFieldRaycastHit)
    local len = math.sqrt(dirX * dirX + dirZ * dirZ)
    if len < 1e-4 then
        return nil
    end
    local fx, fz = dirX / len, dirZ / len
    return hx, hz, -fz, fx
end

function IWFoliagePreview.clear(iw)
    local p = IWFoliagePreview.shown
    IWFoliagePreview.shown = nil
    if p == nil then
        return "no preview to clear"
    end
    iw:wipeFoliageQuad(IWFoliagePreview.rect(p.spots, p.rx, p.rz))
    return "preview cleared"
end

-- Stamps every state of the layer in a row where you look. Returns a line for the log / the hub.
function IWFoliagePreview.show(iw, name, min, max)
    local palette = iw.foliagePalette
    local entry = palette ~= nil and palette:findEntry(name) or nil
    if entry == nil then
        return "preview: the map has no foliage '" .. tostring(name) .. "'"
    end
    local cx, cz, rx, rz = IWFoliagePreview.lookPoint(iw)
    if cx == nil then
        return "preview: look at the ground first (no terrain within 200 m of the crosshair)"
    end
    IWFoliagePreview.clear(iw)
    local spots = IWFoliagePreview.row(cx, cz, rx, rz, min or entry.stageMin, max or entry.stageMax)
    local planted = 0
    for _, s in ipairs(spots) do
        if iw:placeFoliage(s.x, s.z, palette:getWriteName(entry, s.state)) then
            planted = planted + 1
        end
    end
    IWFoliagePreview.shown = { name = name, spots = spots, rx = rx, rz = rz, at = g_time or 0 }
    return string.format("preview: %d of %d state(s) of %s in a row in front of you, numbered left to right", planted, #spots, name)
end

-- The numbers above the row.
function IWFoliagePreview.draw(iw)
    local p = IWFoliagePreview.shown
    if p == nil then
        return
    end
    if (g_time or 0) - p.at > IWFoliagePreview.LABEL_MS then
        -- the numbers are gone: the row goes with them (it would stay in the savegame)
        if iw ~= nil then
            say("%s", IWFoliagePreview.clear(iw))
        end
        return
    end
    for _, s in ipairs(p.spots) do
        local y = getTerrainHeightAtWorldPos(g_terrainNode, s.x, 0, s.z) + 1.3
        Utils.renderTextAtWorldPosition(s.x, y, s.z, tostring(s.state), 0.022, 0, 1, 1, 0.3, 1)
    end
end
