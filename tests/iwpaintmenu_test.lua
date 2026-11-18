-- plain Lua with fakes: the set tiles of the Painting menu, the brush that queues an answered event per request, and the overlay that lays the set over the area
local passed, failed = 0, 0
local function check(name, ok) if ok then passed = passed + 1 else failed = failed + 1; print("  FAIL " .. name) end end

Utils = { overwrittenFunction = function(old, new) return function(self, ...) return new(self, old, ...) end end }
function Class(members, base)
    local mt = { __index = members }
    members.superClass = function() return base end
    setmetatable(members, { __index = base })
    return mt
end
Landscaping = { BRUSH_SHAPE = { CIRCLE = 1, SQUARE = 2 } }
TerrainDeformation = { STATE_SUCCESS = 0 }
g_terrainNode = 1
local function newStore(allowTabs)
    local store = { category = { index = 1, tabs = { { name = "SCULPTING", index = 1 }, { name = "PAINTING", index = 2 } } } }
    function store:getConstructionCategoryByName(name) return name == "landscaping" and self.category or nil end
    function store:getConstructionTabByName(name, categoryName)
        local category = self:getConstructionCategoryByName(categoryName)
        for _, tab in ipairs(category and category.tabs or {}) do if tab.name == string.upper(name) then return tab end end
        return nil
    end
    function store:addConstructionTab(categoryName, name, title, icon, uvs, baseDir, slice)
        local category = self:getConstructionCategoryByName(categoryName)
        if category == nil or not allowTabs then return end
        table.insert(category.tabs, { title = title, name = string.upper(name), index = #category.tabs + 1 })
    end
    return store
end
g_storeManager = newStore(true)
local cursorPos = { 0, 0 }
ConstructionBrushPaint = {}
function ConstructionBrushPaint.new(subclass_mt, cursor)
    return setmetatable({ brushRadius = 1, brushShape = Landscaping.BRUSH_SHAPE.SQUARE }, subclass_mt or { __index = ConstructionBrushPaint })
end
function ConstructionBrushPaint:superClass() return nil end
function ConstructionBrushPaint:onButtonPrimary(isDown, isDrag, isUp)
    if isUp then self.lastX = nil; return end
    local x, z = cursorPos[1], cursorPos[2]
    if self.lastX ~= nil and math.sqrt((x - self.lastX) ^ 2 + (z - self.lastZ) ^ 2) < 0.25 then return end
    self.lastX, self.lastZ = x, z
end
ConstructionScreen = { buildTerrainPaintBrushes = function(self, numItems) return numItems + 3 end }

-- IW and its texture sets (fakes with the same names)
local sets = { { name = "Gravel road", textures = { { layer = "GRAVEL", weight = 90 }, { layer = "DIRT", weight = 10 } } },
               { name = "Worn cobble", textures = { { layer = "COBBLE", weight = 80 }, { layer = "DIRT", weight = 20 } }, details = { { layer = "POTHOLE", chance = 100, size = 2, shape = "spot" } } } }
IWTextureSets = {
    main = function(set) local best, w = nil, -1 for _, t in ipairs(set.textures) do if t.weight > w then best, w = t.layer, t.weight end end return best end,
    layerFor = function(set, i, j) return ((i + j) % 10 == 0) and set.textures[2].layer or set.textures[1].layer end,
    detailsOf = function(set) return set.details end,
    detailCells = function(detail, i, j) return { { i, j }, { i + 1, j } } end,
}
local ids = { GRAVEL = 3, DIRT = 4, COBBLE = 5, POTHOLE = 7, POTHOLE_WET = 8 }
local painted = {}
ImmersiveWeathering = {
    textureSets = { count = function() return #sets end, get = function(_, i) return sets[i] end },
    getTerrainLayerIdByName = function(_, name) return ids[name] end,
    getTexelSize = function() return 0.5 end,
    listTerrainLayers = function() return {} end,
    paintCells = function(_, cells, size, id) painted[#painted + 1] = { id = id, cells = cells, size = size } end,
}
local raining = false
IWFoliagePalette = { isRaining = function() return raining end }
dofile("scripts/IWPaintMenu.lua")

-- the cells of a brush area
local square = IWPaintMenu.cellsIn(0, 0, 2, false, 0.5)
local circle = IWPaintMenu.cellsIn(0, 0, 2, true, 0.5)
check("a square of side 4 m on 0.5 m texels: 8 x 8", #square == 64)
check("the circle of the same radius has fewer, all of them inside", #circle < #square and #circle > 40 and (function() for _, c in ipairs(circle) do if c[3] ^ 2 + c[4] ^ 2 > 4 + 1e-9 then return false end end return true end)())
local capped = IWPaintMenu.cellsIn(0, 0, 4, false, 0.5, 100)
check("at most maxCells, the nearest to the middle", #capped == 100 and (function() for _, c in ipairs(capped) do if c[3] ^ 2 + c[4] ^ 2 > 2.9 ^ 2 then return false end end return true end)())

-- the plan: the main layer stays, the others and the stamps are laid
local cells = {}
for i = 0, 9 do cells[#cells + 1] = { i, 0, (i + 0.5) * 0.5, 0.25 } end
local byLayer, order = IWPaintMenu.plan(cells, 0.5, 3, function(i) return i == 0 and 4 or 3 end, function(i) if i == 5 then return { { id = 7, cells = { { 5, 0 }, { 6, 0 } } } } end end)
check("the texel that picks the main layer is not painted again", byLayer[3] == nil)
check("the other layer and the stamp are", #byLayer[4] == 1 and #byLayer[7] == 2 and #order == 2)
check("a stamp's texels carry their centres", byLayer[7][1][3] == 2.75 and byLayer[7][2][3] == 3.25)

-- the tab comes from the official <constructionCategories> block of modDesc.xml (the game's mod loader reads it, the store manager adds it): here the fake store has it added
g_storeManager:addConstructionTab("landscaping", "iwTextures", "IW Textures")
local ownTab = g_storeManager:getConstructionTabByName("iwTextures", "landscaping")
check("the modDesc.xml tab is the third of the Landscaping category", ownTab ~= nil and ownTab.index == 3)

-- the tiles go into that tab, the game's own tabs are left as they are
local screen = { items = { [1] = { [1] = {}, [2] = { { name = "vanilla 1" }, { name = "vanilla 2" } }, [3] = {} } } }
local n = ConstructionScreen.buildTerrainPaintBrushes(screen, 10)
local tab = screen.items[1][3]
check("the screen's own number plus a tile per set", n == 15)
check("two tiles in the own tab, the Painting tab untouched", #tab == 2 and #screen.items[1][2] == 2 and screen.items[1][2][1].name == "vanilla 1")
check("a tile: named, the set's main layer as its picture, the set's index as parameter", tab[1].name == "Gravel road" and tab[1].terrainOverlayLayer == 3 and tab[1].brushParameters[1] == 1 and tab[2].terrainOverlayLayer == 5 and tab[2].uniqueIndex == 15 and tab[1].uniqueIndex == 14)
check("the brush class is the set brush", tab[1].brushClass == IWBrushPaintSet and tab[1].brushClass == tab[2].brushClass)

-- no own tab (the category was not there in time): the tiles are at the top of the Painting tab
g_storeManager = newStore(false)
local screenB = { items = { [1] = { [1] = {}, [2] = { { name = "vanilla 1" } } } } }
ConstructionScreen.buildTerrainPaintBrushes(screenB, 10)
check("without the own tab the tiles are at the top of the Painting tab", #screenB.items[1][2] == 3 and screenB.items[1][2][1].name == "Gravel road" and screenB.items[1][2][3].name == "vanilla 1")
g_storeManager = newStore(true)
g_storeManager:addConstructionTab("landscaping", "iwTextures", "IW Textures")

ImmersiveWeathering.textureSets, sets[1].dummy = nil, nil
local screen2 = { items = { [1] = { [1] = {}, [2] = {}, [3] = {} } } }
check("without the sets the menu is the game's own", ConstructionScreen.buildTerrainPaintBrushes(screen2, 10) == 13 and #screen2.items[1][3] == 0 and #screen2.items[1][2] == 0)
ImmersiveWeathering.textureSets = { count = function() return #sets end, get = function(_, i) return sets[i] end }

-- the brush: one request per event it sent, answered in order
local brush = tab[2].brushClass.new(nil, {})
brush:setParameters(2)
check("the brush paints the set's main layer through the stock event", brush.terrainLayer == 5)
local overlays = {}
local realOverlay = IWPaintMenu.overlay
IWPaintMenu.overlay = function(set, req) overlays[#overlays + 1] = { set = set, req = req } end
cursorPos = { 10, 10 }
brush:onButtonPrimary(true, false, false)
brush:onButtonPrimary(false, true, false)                          -- (the same spot: the stock brush sent nothing)
cursorPos = { 10.5, 10 }
brush:onButtonPrimary(false, true, false)
check("an event per position the stock brush sent, not per call", #brush.pending == 2 and brush.pending[1].x == 10 and brush.pending[2].x == 10.5)
brush:onButtonPrimary(false, false, true)
check("button up sends nothing", #brush.pending == 2)
brush:onSculptingFinished(true, 0, 5)
check("a validation answer is ignored", #overlays == 0 and #brush.pending == 2)
brush:onSculptingFinished(false, 0, 100)
check("the first answer lays the set over the first request", #overlays == 1 and overlays[1].req.x == 10 and overlays[1].set == sets[2])
brush:onSculptingFinished(false, 7, 0)
check("a failed answer (not the player's land ...) lays nothing, but the request is used up", #overlays == 1 and #brush.pending == 0)
IWPaintMenu.overlay = realOverlay

-- the overlay itself
painted = {}
local count = IWPaintMenu.overlay(sets[2], { x = 5, z = 5, radius = 1, shape = Landscaping.BRUSH_SHAPE.SQUARE })
local byId = {}
for _, call in ipairs(painted) do byId[call.id] = #call.cells end
check("the set's other layer (DIRT, 1 texel in 10) and the pothole stamps are laid, the main layer (COBBLE) is not", byId[4] ~= nil and byId[7] ~= nil and byId[5] == nil and count > 0)
check("the texel size is the map's", painted[1].size == 0.5)
painted, raining = {}, true
IWPaintMenu.overlay(sets[2], { x = 5, z = 5, radius = 1, shape = Landscaping.BRUSH_SHAPE.SQUARE })
local wet = false
for _, call in ipairs(painted) do if call.id == 8 then wet = true end end
check("while it rains the pothole stamps are the wet twin", wet)
print(string.format("iwpaintmenu_test: %d/%d passed", passed, passed + failed))
os.exit(failed == 0 and 0 or 1)
