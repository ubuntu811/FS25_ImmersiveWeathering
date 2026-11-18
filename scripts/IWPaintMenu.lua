--[[
    IWPaintMenu.lua -- the texture sets (a named, weighted mix of terrain layers: "Gravel road: GRAVEL 90, DIRT 10", with their details) as tiles in the construction screen's Painting menu.

    The menu (ConstructionScreen:buildTerrainPaintBrushes, read from the decompiled 1.25.1.0 scripts) lists the map's ground types; a tile is { terrainOverlayLayer, name, brushClass, brushParameters, price, ... } and the screen
    makes the brush with brushClass.new(nil, cursor) and brush:setParameters(unpack(brushParameters)). The stock brush (ConstructionBrushPaint) sends a LandscapingSculptEvent for one layer over the whole area; the server
    side charges for it, checks the land is the player's, clears crops, weeds, stones and decoration there and tells the AI. A set cannot be one layer, so (the tiles are in a tab of their own, "IW Textures", next to Painting in the Landscaping category: declared in modDesc.xml as <constructionCategories><tab categoryName="landscaping" name="iwTextures" .../>, which the game's mod loader reads and StoreManager:loadMapData adds):

      the set's tile uses the stock brush's own event with the set's MAIN layer (the biggest weight): cost, ownership, clearing and multiplayer all stay the game's. When the event has been answered (the brush's
      onSculptingFinished), the rest of the set is laid over that area texel by texel with IW's own painter (ImmersiveWeathering:paintCells), exactly as a roller lays a set: every texel picks its layer from the set
      (IWTextureSets.layerFor: weights, patch size, pattern), a texel that picks the main layer stays, and the set's details (cracks, missing stones, potholes) are stamped at their plain chance.

    A drag sends an event every 0.25 m, and each paints the main layer over its whole area again: the overlay of an event is decided again as well, so the stroke ends with the set's mix everywhere.
]]
IWPaintMenu = { MAX_CELLS = 600, TITLE = "", TAB_NAME = "iwTextures", CATEGORY = "landscaping" }

local function say(format, ...)
    print(string.format("[ImmersiveWeathering] " .. format, ...))
end

-- The texel cells (i, j, centre x, centre z) of a brush area: a square of side 2 * radius or a circle of that radius at (x, z), on the texel grid that starts at the world origin. At most maxCells, the nearest to the middle.
function IWPaintMenu.cellsIn(x, z, radius, isCircle, size, maxCells)
    local list = {}
    local i0, i1 = math.floor((x - radius) / size), math.floor((x + radius) / size)
    local j0, j1 = math.floor((z - radius) / size), math.floor((z + radius) / size)
    for i = i0, i1 do
        for j = j0, j1 do
            local cx, cz = (i + 0.5) * size, (j + 0.5) * size
            local dx, dz = cx - x, cz - z
            local inside = math.abs(dx) <= radius and math.abs(dz) <= radius
            if inside and isCircle then
                inside = dx * dx + dz * dz <= radius * radius
            end
            if inside then
                list[#list + 1] = { i, j, cx, cz, d = dx * dx + dz * dz }
            end
        end
    end
    if maxCells ~= nil and #list > maxCells then
        table.sort(list, function(a, b) return a.d < b.d end)
        for k = #list, maxCells + 1, -1 do
            list[k] = nil
        end
    end
    return list
end

-- Which texels go into which layer, besides the main layer that the stock event has painted already. pickId(i, j) -> the layer id the set picks for that texel (nil: none); stamps(i, j) -> a list of
-- { id = layer id, cells = { { i, j }, ... } } (the set's details, decided at their chance). Returns byLayer (id -> texel list for paintCells) and the order of the ids.
function IWPaintMenu.plan(cells, size, mainId, pickId, stamps)
    local byLayer, order = {}, {}
    local function add(id, cell)
        if byLayer[id] == nil then
            byLayer[id] = {}
            order[#order + 1] = id
        end
        table.insert(byLayer[id], cell)
    end
    for _, c in ipairs(cells) do
        local id = pickId(c[1], c[2])
        if id ~= nil and id ~= mainId then
            add(id, c)
        end
        if stamps ~= nil then
            for _, stamp in ipairs(stamps(c[1], c[2]) or {}) do
                for _, cell in ipairs(stamp.cells) do
                    add(stamp.id, { cell[1], cell[2], (cell[1] + 0.5) * size, (cell[2] + 0.5) * size })
                end
            end
        end
    end
    return byLayer, order
end

-- The overlay of one answered event: req = { x, z, radius, shape } (the brush's own numbers). Returns how many texels were painted.
function IWPaintMenu.overlay(set, req)
    local iw = ImmersiveWeathering
    if iw == nil or set == nil then
        return 0
    end
    local size = iw:getTexelSize()
    local mainName = IWTextureSets.main(set)
    local mainId = mainName ~= nil and iw:getTerrainLayerIdByName(mainName) or nil
    local isCircle = Landscaping ~= nil and req.shape == Landscaping.BRUSH_SHAPE.CIRCLE
    local cells = IWPaintMenu.cellsIn(req.x, req.z, req.radius, isCircle, size, IWPaintMenu.MAX_CELLS)
    local details = IWTextureSets.detailsOf(set, function() return iw:listTerrainLayers() end)
    local raining = IWFoliagePalette ~= nil and IWFoliagePalette.isRaining() or false
    local function pickId(i, j)
        local name = IWTextureSets.layerFor(set, i, j, math.random)
        return name ~= nil and iw:getTerrainLayerIdByName(name) or nil
    end
    local stamps = nil
    if details ~= nil and #details > 0 then
        stamps = function(i, j)
            local out = nil
            for _, detail in ipairs(details) do
                if math.random() * 100 < detail.chance then
                    -- while it rains (and half an hour after) a pothole holds water: its wet twin, when the map has one
                    local id = (raining and iw:getTerrainLayerIdByName(detail.layer .. "_WET")) or iw:getTerrainLayerIdByName(detail.layer)
                    if id ~= nil then
                        out = out or {}
                        out[#out + 1] = { id = id, cells = IWTextureSets.detailCells(detail, i, j, math.random) }
                    end
                end
            end
            return out
        end
    end
    local byLayer, order = IWPaintMenu.plan(cells, size, mainId, pickId, stamps)
    local painted = 0
    for _, id in ipairs(order) do
        iw:paintCells(byLayer[id], size, id)
        painted = painted + #byLayer[id]
    end
    return painted
end

-- The brush: the stock paint brush with the set's main layer, and the overlay once an event is answered. Made when the screen first needs it (ConstructionBrushPaint is there by then).
function IWPaintMenu.brushClass()
    if IWBrushPaintSet ~= nil then
        return IWBrushPaintSet
    end
    IWBrushPaintSet = {}
    local mt = Class(IWBrushPaintSet, ConstructionBrushPaint)
    function IWBrushPaintSet.new(subclass_mt, cursor)
        local self = IWBrushPaintSet:superClass().new(subclass_mt or mt, cursor)
        self.pending = {}
        return self
    end
    function IWBrushPaintSet:setParameters(setIndex)
        self.setIndex = setIndex
        local iw = ImmersiveWeathering
        local set = iw ~= nil and iw.textureSets ~= nil and iw.textureSets:get(setIndex) or nil
        local mainName = set ~= nil and IWTextureSets.main(set) or nil
        self.terrainLayer = mainName ~= nil and iw:getTerrainLayerIdByName(mainName) or 0
    end
    function IWBrushPaintSet:onButtonPrimary(isDown, isDrag, isUp)
        local lastX, lastZ = self.lastX, self.lastZ
        IWBrushPaintSet:superClass().onButtonPrimary(self, isDown, isDrag, isUp)
        -- the stock brush sent an event when it moved its last position: that one is answered later, in order
        if self.lastX ~= nil and (self.lastX ~= lastX or self.lastZ ~= lastZ) then
            self.pending[#self.pending + 1] = { x = self.lastX, z = self.lastZ, radius = self.brushRadius, shape = self.brushShape }
        end
    end
    function IWBrushPaintSet:onSculptingFinished(isValidation, errorCode, displacedVolumeOrArea)
        if isValidation then
            return
        end
        local request = table.remove(self.pending, 1)
        if request == nil or errorCode ~= TerrainDeformation.STATE_SUCCESS then
            return
        end
        local iw = ImmersiveWeathering
        local set = iw ~= nil and iw.textureSets ~= nil and iw.textureSets:get(self.setIndex) or nil
        local ok, err = pcall(IWPaintMenu.overlay, set, request)
        if not ok then
            say("paint menu: the set could not be laid over the area (%s)", tostring(err))
        end
    end
    return IWBrushPaintSet
end

-- The tiles, one per set, the set's main layer as its picture: in the tab of their own; if that tab could not be made, at the top of the Painting tab (before the game's ~100 ground types).
function IWPaintMenu.addTiles(screen, numItems)
    local iw = ImmersiveWeathering
    if iw == nil or iw.textureSets == nil then
        return numItems
    end
    local landscapingIndex = g_storeManager:getConstructionCategoryByName(IWPaintMenu.CATEGORY).index
    local ownTab = g_storeManager:getConstructionTabByName(IWPaintMenu.TAB_NAME, IWPaintMenu.CATEGORY)         -- (the modDesc.xml declaration made it)
    local tab, at = nil, nil
    if ownTab ~= nil and screen.items[landscapingIndex][ownTab.index] ~= nil then
        tab = screen.items[landscapingIndex][ownTab.index]
        at = #tab + 1
    else
        tab = screen.items[landscapingIndex][g_storeManager:getConstructionTabByName("painting", IWPaintMenu.CATEGORY).index]
        at = 1
    end
    local first = at
    for index = 1, iw.textureSets:count() do
        local set = iw.textureSets:get(index)
        local mainName = IWTextureSets.main(set)
        local layerId = mainName ~= nil and iw:getTerrainLayerIdByName(mainName) or nil
        if layerId ~= nil then
            numItems = numItems + 1
            table.insert(tab, at, { terrainOverlayLayer = layerId, name = IWPaintMenu.TITLE .. set.name, brushClass = IWPaintMenu.brushClass(), brushParameters = { index }, price = 2, imageFilename = nil, brandFilename = nil, modDlc = "", uniqueIndex = numItems })
            at = at + 1
        end
    end
    say("paint menu: %d texture set tile(s) in the %s", at - first, ownTab ~= nil and '"IW Textures" tab' or "Painting tab (the own tab is missing)")
    return numItems
end

if ConstructionScreen ~= nil and Utils ~= nil and not IWPaintMenu.hooked then
    IWPaintMenu.hooked = true
    -- overwritten, not appended: the screen reads the number the function returns (numItems = self:buildTerrainPaintBrushes(numItems))
    ConstructionScreen.buildTerrainPaintBrushes = Utils.overwrittenFunction(ConstructionScreen.buildTerrainPaintBrushes, function(self, superFunc, numItems, ...)
        numItems = superFunc(self, numItems, ...)
        local ok, result = pcall(IWPaintMenu.addTiles, self, numItems)
        if not ok then
            say("paint menu: the texture sets could not be added (%s)", tostring(result))
            return numItems
        end
        return result
    end)
end
