--[[
    IWClassOverlay.lua -- a debug picture of what IW thinks the ground is (IWClass: field, building, road, forest, meadow, bare, other) on the in-game map.

    iwClass [here | off | half <m> | cell <m>]   scans a square around the camera (default 384 m each side, 4 m cells; at most 256 cells a side) and draws it on the full-screen map; the log says
    how many cells came out as each class and which terrain materials fed the meadow / bare / other decision (a map whose grass or dirt has another material id than IW expects shows up there at once).
    The scan is on demand and sliced: SLICE_SEC of classification per frame, then the picture is generated once. The picture is a density-map overlay of its own (3 bits per cell, one value per class), drawn
    like WAILA's map layers; the minimap (when another mod patches it) may not show it, the full-screen map does.
]]
IWClassOverlay = { HALF = 384, CELL = 4, MAX_CELLS = 256, SLICE_SEC = 0.004, SIZE = 2048 }
IWClassOverlay.ORDER = { "field", "building", "road", "forest", "meadow", "bare", "other" }          -- the value of a class in the map is its place here
IWClassOverlay.COLORS = {
    field = { 1.0, 0.9, 0.1 }, building = { 0.8, 0.8, 0.8 }, road = { 1.0, 0.35, 0.0 }, forest = { 0.0, 0.5, 0.2 },
    meadow = { 0.45, 1.0, 0.3 }, bare = { 0.6, 0.35, 0.15 }, other = { 0.7, 0.2, 1.0 },
}
IWClassOverlay.ALPHA = 0.65

function IWClassOverlay.valueOf(class)
    for i, c in ipairs(IWClassOverlay.ORDER) do
        if c == class then
            return i
        end
    end
    return #IWClassOverlay.ORDER
end

-- The square of cells around (cx, cz): { minX, minZ, cells, cell } with the edges on the cell grid.
function IWClassOverlay.window(cx, cz, half, cell)
    cell = math.max(1, cell)
    local cells = math.min(IWClassOverlay.MAX_CELLS, math.max(1, math.floor(half * 2 / cell + 0.5)))
    return { minX = math.floor((cx - cells * cell / 2) / cell) * cell, minZ = math.floor((cz - cells * cell / 2) / cell) * cell, cells = cells, cell = cell }
end

-- A row of values (index 0 .. n-1) as runs of equal values: { { from, to (exclusive), value } }.
function IWClassOverlay.runs(row, n)
    local out, start, current = {}, nil, nil
    for i = 0, n do
        local v = i < n and row[i] or nil
        if v ~= current then
            if current ~= nil then
                out[#out + 1] = { start, i, current }
            end
            start, current = i, v
        end
    end
    return out
end

-- The one line the log gets: the classes with their cell counts and shares, and the materials behind meadow / bare / other.
function IWClassOverlay.summary(counts, byMaterial, total)
    local parts = {}
    for _, class in ipairs(IWClassOverlay.ORDER) do
        local n = counts[class] or 0
        if n > 0 then
            parts[#parts + 1] = string.format("%s %d (%d%%)", class, n, math.floor(n * 100 / math.max(1, total) + 0.5))
        end
    end
    local mats = {}
    for material, byClass in pairs(byMaterial) do
        local inner = {}
        for _, class in ipairs(IWClassOverlay.ORDER) do
            if byClass[class] ~= nil then
                inner[#inner + 1] = class .. " " .. byClass[class]
            end
        end
        mats[#mats + 1] = { material = material, text = string.format("material %s -> %s", tostring(material), table.concat(inner, ", ")) }
    end
    table.sort(mats, function(a, b) return tostring(a.material) < tostring(b.material) end)
    local lines = {}
    for _, m in ipairs(mats) do
        lines[#lines + 1] = m.text
    end
    return table.concat(parts, ", "), lines
end

-- One cell: counts it and returns its map value. classify(x, z) -> class, material(x, z) -> terrain material id (only for the table of materials).
function IWClassOverlay.sampleCell(x, z, classify, material, counts, byMaterial)
    local class = classify(x, z)
    counts[class] = (counts[class] or 0) + 1
    local m = material(x, z)
    local byClass = byMaterial[m]
    if byClass == nil then
        byClass = {}
        byMaterial[m] = byClass
    end
    byClass[class] = (byClass[class] or 0) + 1
    return IWClassOverlay.valueOf(class)
end

local function say(format, ...)
    print(string.format("[ImmersiveWeathering] " .. format, ...))
end

-- ---- engine side ----

function IWClassOverlay.start(iw, cx, cz, half, cell)
    local win = IWClassOverlay.window(cx, cz, half or IWClassOverlay.HALF, cell or IWClassOverlay.CELL)
    IWClassOverlay.job = { win = win, row = 0, col = 0, grid = {}, counts = {}, byMaterial = {}, startedAt = getTimeSec(), iw = iw }
    IWClassOverlay.visible = true
    return win
end

function IWClassOverlay.ensureOverlay()
    if IWClassOverlay.map == nil then
        IWClassOverlay.map = createBitVectorMap("iwClassOverlayMap")
        loadBitVectorMapNew(IWClassOverlay.map, IWClassOverlay.SIZE, IWClassOverlay.SIZE, 3, false)
        IWClassOverlay.overlay = createDensityMapVisualizationOverlay("iwClassOverlay", IWClassOverlay.SIZE, IWClassOverlay.SIZE)
    end
end

function IWClassOverlay.finish(job)
    IWClassOverlay.ensureOverlay()
    local win = job.win
    local modifier = DensityMapModifier.new(IWClassOverlay.map, 0, 3, g_terrainNode)
    if IWClassOverlay.lastWindow ~= nil then
        local w = IWClassOverlay.lastWindow
        local size = w.cells * w.cell
        modifier:clearPolygonPoints()
        modifier:addPolygonPointWorldCoords(w.minX, w.minZ)
        modifier:addPolygonPointWorldCoords(w.minX + size, w.minZ)
        modifier:addPolygonPointWorldCoords(w.minX + size, w.minZ + size)
        modifier:addPolygonPointWorldCoords(w.minX, w.minZ + size)
        modifier:executeSet(0)
    end
    local rects = 0
    for r = 0, win.cells - 1 do
        local z0 = win.minZ + r * win.cell
        for _, run in ipairs(IWClassOverlay.runs(job.grid[r], win.cells)) do
            modifier:clearPolygonPoints()
            modifier:addPolygonPointWorldCoords(win.minX + run[1] * win.cell, z0)
            modifier:addPolygonPointWorldCoords(win.minX + run[2] * win.cell, z0)
            modifier:addPolygonPointWorldCoords(win.minX + run[2] * win.cell, z0 + win.cell)
            modifier:addPolygonPointWorldCoords(win.minX + run[1] * win.cell, z0 + win.cell)
            modifier:executeSet(run[3])
            rects = rects + 1
        end
    end
    resetDensityMapVisualizationOverlay(IWClassOverlay.overlay)
    for i, class in ipairs(IWClassOverlay.ORDER) do
        local c = IWClassOverlay.COLORS[class]
        setDensityMapVisualizationOverlayStateColor(IWClassOverlay.overlay, IWClassOverlay.map, 0, 0, 0, 3, i, c[1], c[2], c[3])
    end
    generateDensityMapVisualizationOverlay(IWClassOverlay.overlay)
    IWClassOverlay.lastWindow = win
    local text, lines = IWClassOverlay.summary(job.counts, job.byMaterial, win.cells * win.cells)
    say("iwClass: %dx%d cells of %d m from %.0f/%.0f, %d rectangle(s), %.1f s: %s", win.cells, win.cells, win.cell, win.minX, win.minZ, rects, getTimeSec() - job.startedAt, text)
    for _, line in ipairs(lines) do
        say("iwClass:   %s", line)
    end
end

-- Called every frame: classifies cells until the frame's slice is used up.
function IWClassOverlay.tick()
    local job = IWClassOverlay.job
    if job == nil then
        return
    end
    local iw, win = job.iw, job.win
    local classify = function(x, z) return iw:classAt(x, z) end
    local material = iw:classDeps().material
    local began = getTimeSec()
    local n = 0
    while job.row < win.cells do
        local row = job.grid[job.row]
        if row == nil then
            row = {}
            job.grid[job.row] = row
        end
        local x = win.minX + (job.col + 0.5) * win.cell
        local z = win.minZ + (job.row + 0.5) * win.cell
        row[job.col] = IWClassOverlay.sampleCell(x, z, classify, material, job.counts, job.byMaterial)
        job.col = job.col + 1
        if job.col >= win.cells then
            job.col, job.row = 0, job.row + 1
        end
        n = n + 1
        if n % 32 == 0 and getTimeSec() - began > IWClassOverlay.SLICE_SEC then
            return
        end
    end
    IWClassOverlay.job = nil
    local ok, err = pcall(IWClassOverlay.finish, job)
    if not ok then
        say("iwClass: the picture could not be made (%s)", tostring(err))
    end
end

-- Drawn like WAILA's map layers (TaskMap's renderMapOverlay): the map's position, pivot, rotation and the minimap clip.
function IWClassOverlay.draw(map)
    if not IWClassOverlay.visible or IWClassOverlay.overlay == nil or IWClassOverlay.lastWindow == nil then
        return
    end
    if not getIsDensityMapVisualizationOverlayReady(IWClassOverlay.overlay) then
        return
    end
    local overlay = IWClassOverlay.overlay
    local width, height = map.layout:getMapSize()
    local x, y = map.layout:getMapPosition()
    local px, py = map.layout:getMapPivot()
    px, py = px + x, py + y
    x = x + width * map.mapExtensionOffsetX
    y = y + height * map.mapExtensionOffsetZ
    px, py = px - x, py - y
    local posX, posY = x, y
    local sizeX, sizeY = width * map.mapExtensionScaleFactor, height * map.mapExtensionScaleFactor
    if map.clipX1 ~= nil then
        local u1, v1, u2, v2, u3, v3, u4, v4
        posX, posY, sizeX, sizeY, u1, v1, u2, v2, u3, v3, u4, v4 = Overlay.getClippingUVs(Overlay.DEFAULT_UVS, posX, posY, sizeX, sizeY, map.clipX1, map.clipY1, map.clipX2, map.clipY2)
        if u1 == nil then
            return
        end
        setOverlayUVs(overlay, u1, v1, u2, v2, u3, v3, u4, v4)
    end
    setOverlayRotation(overlay, map.layout:getMapRotation(), px, py)
    setOverlayColor(overlay, 1, 1, 1, IWClassOverlay.ALPHA)
    renderOverlay(overlay, posX, posY, sizeX, sizeY)
    if map.clipX1 ~= nil then
        setOverlayUVs(overlay, unpack(Overlay.DEFAULT_UVS))
    end
end

-- The hub rows: what the overlay is doing, and the click that starts a scan around the camera (a click while it is shown hides it).
function IWClassOverlay.status()
    if IWClassOverlay.job ~= nil then
        local win = IWClassOverlay.job.win
        return string.format("scanning, %d%%", math.floor(((IWClassOverlay.job.row * win.cells + IWClassOverlay.job.col) * 100) / (win.cells * win.cells)))
    end
    return IWClassOverlay.visible and IWClassOverlay.lastWindow ~= nil and "shown on the full-screen map" or "off"
end

function IWClassOverlay.isBusy()
    return IWClassOverlay.job ~= nil
end

function IWClassOverlay.toggle(iw, half, cell)
    if IWClassOverlay.visible and IWClassOverlay.lastWindow ~= nil and IWClassOverlay.job == nil then
        IWClassOverlay.visible = false
        return "iwClass: off"
    end
    return IWClassOverlay.console(iw, "half", half, cell)
end

-- Adds the two rows to WAILA's Terrain tab (WAILA may load after IW: tried every frame until it is there). Returns true when they are in.
function IWClassOverlay.registerRows(waila, iw)
    if waila == nil or waila.addDebugAction == nil then
        return false
    end
    local function row(key, title, half, cell)
        return waila.addDebugAction("terrain", {
            key = key,
            getLabel = function() return "IW ground classes on the map: " .. title .. " (" .. IWClassOverlay.status() .. ")" end,
            instant = true,
            isBusy = function() return IWClassOverlay.isBusy() end,
            run = function()
                print("[ImmersiveWeathering] " .. IWClassOverlay.toggle(iw, half, cell))
                if waila.refreshDebugHubKeepSelection ~= nil then
                    waila.refreshDebugHubKeepSelection()
                end
            end,
        })
    end
    return row("iw.classOverlay", "around me, 768 m in 4 m cells", 384, 4) and row("iw.classOverlayWide", "wide, 2 km in 8 m cells", 1024, 8)
end

-- iwClass [here | off | half <m> | cell <m>]
function IWClassOverlay.console(iw, arg1, arg2, arg3)
    local half, cell = IWClassOverlay.HALF, IWClassOverlay.CELL
    if arg1 == "off" then
        IWClassOverlay.visible = false
        IWClassOverlay.job = nil
        return "iwClass: off"
    elseif arg1 == "half" and tonumber(arg2) ~= nil then
        half = tonumber(arg2)
        cell = tonumber(arg3) or cell
    elseif arg1 == "cell" and tonumber(arg2) ~= nil then
        cell = tonumber(arg2)
    elseif arg1 ~= nil and arg1 ~= "here" and arg1 ~= "on" then
        return "usage: iwClass [here | off | half <m> | cell <m>]"
    end
    if IWClassOverlay.job ~= nil then
        return "iwClass: still scanning"
    end
    local camera = g_cameraManager:getActiveCamera()
    local cx, _, cz = getWorldTranslation(camera)
    local win = IWClassOverlay.start(iw, cx, cz, half, cell)
    return string.format("iwClass: scanning %dx%d cells of %d m around you, open the full-screen map; the log gets the counts when it is done", win.cells, win.cells, win.cell)
end

if IngameMap ~= nil and Utils ~= nil and not IWClassOverlay.hooked then
    IWClassOverlay.hooked = true
    IngameMap.drawFields = Utils.appendedFunction(IngameMap.drawFields, IWClassOverlay.draw)
end
