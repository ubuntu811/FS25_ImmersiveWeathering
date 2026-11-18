--[[
    IWFoliageMenu.lua -- the foliage sets (IWFoliageSets) as tiles in the construction screen's "IW Foliage" tab (Landscaping, next to IW Textures): a brush that plants a random mix of the set's foliage, on any ground.

    The stock foliage brush (ConstructionBrushFoliage, read from the decompiled 1.25.1.0 scripts) paints ONE foliage type and state over its whole area with a LandscapingSculptEvent. A set is a mix, so the tile's brush
    derives from it (cursor, sizes 0.5 .. 16 m, circle / square, sound, land ownership check) and plants by itself with IW's own placement (ImmersiveWeathering:placeFoliage, the stamp seeding uses):
      the area is cut into a grid (cell about 1 m, smaller for the smallest brushes); every cell rolls once per stroke (a drag does not thicken what it already crossed): the set's chances decide which foliage
      lands in the cell at a jittered spot, or nothing (what the chances leave out of 100 %). Primary button plants, secondary removes all plants in the brush square (IW's wipe).
    Planting is free and local (IW places foliage the way weathering does, no landscaping event); at most MAX_POINTS foliage stamps per event, the rest of the stroke follows with the next one.
]]
IWFoliageMenu = { TAB_NAME = "iwFoliage", CATEGORY = "landscaping", MAX_POINTS = 120, MAX_SPACING = 1.0 }
local MOD_DIRECTORY = g_currentModDirectory

local function say(format, ...)
    print(string.format("[ImmersiveWeathering] " .. format, ...))
end

-- The cell size of a brush: 1 m, down to half a metre for the smallest brush (a 0.5 m brush would hit a 1 m grid rarely).
function IWFoliageMenu.spacingFor(radius)
    return math.max(0.5, math.min(IWFoliageMenu.MAX_SPACING, radius + 0.25))
end

-- The foliage one event plants: { { x, z, name } }. `done` is the stroke's memory (cell key -> true); a cell that is in it is not rolled again. pick() is the set's weighted pick (nil: nothing for this
-- cell), random() math.random. At most maxPoints; the cells not reached stay out of `done`.
function IWFoliageMenu.plan(x, z, radius, isCircle, spacing, done, pick, random, maxPoints)
    local out = {}
    local i0, i1 = math.floor((x - radius) / spacing), math.floor((x + radius) / spacing)
    local j0, j1 = math.floor((z - radius) / spacing), math.floor((z + radius) / spacing)
    for i = i0, i1 do
        for j = j0, j1 do
            local key = i .. ":" .. j
            if not done[key] then
                local px, pz = (i + random()) * spacing, (j + random()) * spacing
                local dx, dz = px - x, pz - z
                local inside = math.abs(dx) <= radius and math.abs(dz) <= radius
                if inside and isCircle then
                    inside = dx * dx + dz * dz <= radius * radius
                end
                if inside then
                    if maxPoints ~= nil and #out >= maxPoints then
                        return out
                    end
                    done[key] = true
                    local name, state = pick()
                    if name ~= nil then
                        out[#out + 1] = { x = px, z = pz, name = name, state = state }
                    end
                end
            end
        end
    end
    return out
end

-- Plants the planned foliage; returns how many stamps were written.
function IWFoliageMenu.plant(points)
    local iw = ImmersiveWeathering
    local palette = iw ~= nil and iw.foliagePalette or nil
    if palette == nil then
        return 0
    end
    local planted = 0
    for _, p in ipairs(points) do
        local entry = palette:findEntry(p.name)
        if entry ~= nil then
            local writeName = palette:getWriteName(entry, p.state or palette:pickInitialStage(entry))
            if iw:placeFoliage(p.x, p.z, writeName) then
                planted = planted + 1
                iw:registerTrackedPatchIfNeeded(entry, p.x, p.z)
            end
        end
    end
    return planted
end

-- One primary / secondary press, drag or release of the brush.
function IWFoliageMenu.brushPerform(self, isDown, isDrag, isUp, direction)
    self:setActiveSound(ConstructionSound.ID.NONE)
    if isDown then
        self.done = {}
    end
    if isUp then
        self.lastX = nil
        self.done = {}
        return
    end
    local iw = ImmersiveWeathering
    local sets = iw ~= nil and iw.foliageSets or nil
    local x, y, z = self.cursor:getHitTerrainPosition()
    if sets == nil or sets:get(self.setKey) == nil or x == nil or self:verifyAccess(x, y, z) ~= nil then
        return
    end
    if self.lastX ~= nil and (x - self.lastX) ^ 2 + (z - self.lastZ) ^ 2 < 0.0625 then
        return
    end
    self.lastX, self.lastZ = x, z
    self:setActiveSound(ConstructionSound.ID.FOLIAGE, 1 - self.brushRadius / self.maxBrushRadius)
    local r = self.brushRadius
    if direction > 0 then
        local key = self.setKey
        local points = IWFoliageMenu.plan(x, z, r, self.brushShape == Landscaping.BRUSH_SHAPE.CIRCLE, IWFoliageMenu.spacingFor(r), self.done, function() return sets:pick(key, math.random) end, math.random, IWFoliageMenu.MAX_POINTS)
        IWFoliageMenu.plant(points)
    else
        iw:wipeFoliageQuad(x - r, z - r, x + r, z - r, x - r, z + r)
    end
end
-- The brush: the stock foliage brush with a set instead of a foliage type. Made when the screen first needs it (ConstructionBrushFoliage is there by then).
function IWFoliageMenu.brushClass()
    if IWBrushFoliageSet ~= nil then
        return IWBrushFoliageSet
    end
    IWBrushFoliageSet = {}
    local mt = Class(IWBrushFoliageSet, ConstructionBrushFoliage)
    function IWBrushFoliageSet.new(subclass_mt, cursor)
        local self = IWBrushFoliageSet:superClass().new(subclass_mt or mt, cursor)
        self.done = {}
        return self
    end
    function IWBrushFoliageSet:setParameters(key)
        self.setKey = key
    end
    function IWBrushFoliageSet:getPrice()
        return 0
    end
    function IWBrushFoliageSet:update(dt)
        ConstructionBrushFoliage:superClass().update(self, dt)               -- (not the stock foliage update: it complains that there is no foliage paint)
        local x, y, z = self.cursor:getHitTerrainPosition()
        if x == nil then
            return
        end
        local err = self:verifyAccess(x, y, z)
        if err ~= nil then
            self.cursor:setErrorMessage(g_i18n:getText(ConstructionBrush.ERROR_MESSAGES[err]))
        end
    end
    function IWBrushFoliageSet:onButtonPrimary(isDown, isDrag, isUp)
        IWFoliageMenu.brushPerform(self, isDown, isDrag, isUp, 1)
    end
    function IWBrushFoliageSet:onButtonSecondary(isDown, isDrag, isUp)
        IWFoliageMenu.brushPerform(self, isDown, isDrag, isUp, -1)
    end
    return IWBrushFoliageSet
end

-- The picture of a set's tile: the store icon of the first foliage in the set that has one (iconFor(name, state): a file or nil), else the mod's own icon.
function IWFoliageMenu.tileIcon(entries, iconFor, fallback)
    for _, e in ipairs(entries or {}) do
        local file = iconFor(e.name, e.state)
        if file ~= nil then
            return file
        end
    end
    return fallback
end

-- The tiles, one per set, in the tab of their own ("IW Foliage", declared in modDesc.xml); if that tab could not be made, at the end of the Painting tab.
function IWFoliageMenu.addTiles(screen, numItems)
    local iw = ImmersiveWeathering
    if iw == nil or iw.foliageSets == nil then
        return numItems
    end
    local landscapingIndex = g_storeManager:getConstructionCategoryByName(IWFoliageMenu.CATEGORY).index
    local ownTab = g_storeManager:getConstructionTabByName(IWFoliageMenu.TAB_NAME, IWFoliageMenu.CATEGORY)
    local tab
    if ownTab ~= nil and screen.items[landscapingIndex][ownTab.index] ~= nil then
        tab = screen.items[landscapingIndex][ownTab.index]
    else
        tab = screen.items[landscapingIndex][g_storeManager:getConstructionTabByName("painting", IWFoliageMenu.CATEGORY).index]
    end
    local icon = Utils.getFilename("icon_immersive_weathering.dds", MOD_DIRECTORY)
    local count = 0
    for index = 1, iw.foliageSets:count() do
        local set = iw.foliageSets:get(iw.foliageSets:keyAt(index))
        numItems = numItems + 1
        count = count + 1
        local setIcon = IWFoliageMenu.tileIcon(set.entries, function(name, state)
            local ok, file = pcall(IWFoliageNames.iconFor, name, state)
            return ok and file or nil
        end, icon)
        table.insert(tab, { name = set.name, brushClass = IWFoliageMenu.brushClass(), brushParameters = { set.key }, price = 0, imageFilename = setIcon, brandFilename = nil, modDlc = "", uniqueIndex = numItems })
    end
    say("foliage menu: %d foliage set tile(s) in the %s", count, ownTab ~= nil and '"IW Foliage" tab' or "Painting tab (the own tab is missing)")
    return numItems
end

if ConstructionScreen ~= nil and Utils ~= nil and not IWFoliageMenu.hooked then
    IWFoliageMenu.hooked = true
    ConstructionScreen.buildTerrainPaintBrushes = Utils.overwrittenFunction(ConstructionScreen.buildTerrainPaintBrushes, function(self, superFunc, numItems, ...)
        numItems = superFunc(self, numItems, ...)
        local ok, result = pcall(IWFoliageMenu.addTiles, self, numItems)
        if not ok then
            say("foliage menu: the foliage sets could not be added (%s)", tostring(result))
            return numItems
        end
        return result
    end)
end
