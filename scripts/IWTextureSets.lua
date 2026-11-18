-- IWTextureSets.lua -- the texture sets of the tyre painting: a named list of the map's terrain layers with weights ("Gravel road: GRAVEL 90, DIRT 10"). The built-in two (DIRT, GRAVEL) come first and
-- can be edited; the player adds more in the WAILA tab. Pure: no engine calls, so it runs offline; the file is IWTextureStore's.
IWTextureSets = {}

-- Layer names compare without regard to case: the combined layer COBBLESTONE04 is the one the map's base layer cobblestone04 is made into, and sets saved with the old names keep working.
function IWTextureSets.same(a, b)
    return tostring(a):upper() == tostring(b):upper()
end
local IWTextureSets_mt = { __index = IWTextureSets }

IWTextureSets.DEFAULT_WEIGHT = 10
IWTextureSets.WEIGHT_STEP = 10
IWTextureSets.WEIGHT_CHOICES = { 5, 10, 25, 50, 75, 100 }      -- the weight buttons of a layer
IWTextureSets.FINE_STEP = 1                 -- the fine buttons: a 97 / 3 mix needs steps of one
IWTextureSets.MAX_WEIGHT = 100

-- defaults: { { name = "DIRT", groundName = "DIRT", textures = { { layer = "DIRT", weight = 90 }, ... } }, ... } (groundName: the iw-map.xml groundMapping entry of the same material, which adds foliage and
-- mutations while the set is not edited)
function IWTextureSets.new(defaults)
    local self = setmetatable({ sets = {} }, IWTextureSets_mt)
    for _, d in ipairs(defaults or {}) do
        local set = { name = d.name, builtin = true, groundName = d.groundName, textures = {} }
        for _, t in ipairs(d.textures) do
            set.textures[#set.textures + 1] = { layer = t.layer, weight = t.weight }
        end
        self.sets[#self.sets + 1] = set
    end
    return self
end

function IWTextureSets:count()
    return #self.sets
end

function IWTextureSets:get(index)
    return self.sets[index] or self.sets[1]
end

function IWTextureSets:names()
    local list = {}
    for i, set in ipairs(self.sets) do
        list[i] = set.name
    end
    return list
end

local function total(set)
    local sum = 0
    for _, t in ipairs(set.textures) do
        sum = sum + t.weight
    end
    return sum
end

-- The layer a paint picks for this set: weighted, random() is math.random (0..1). nil for an empty set.
function IWTextureSets.pick(set, random)
    local sum = total(set)
    if sum <= 0 then
        return nil
    end
    local roll = (random or math.random)() * sum
    local cumulative = 0
    for _, t in ipairs(set.textures) do
        cumulative = cumulative + t.weight
        if roll <= cumulative then
            return t.layer
        end
    end
    return set.textures[#set.textures].layer
end

-- The layer with the biggest weight (the set's "main texture"), and its share 0..1.
function IWTextureSets.main(set)
    local best, bestWeight = nil, -1
    for _, t in ipairs(set.textures) do
        if t.weight > bestWeight then
            best, bestWeight = t.layer, t.weight
        end
    end
    local sum = total(set)
    return best, sum > 0 and bestWeight / sum or 0
end

function IWTextureSets.weightOf(set, layer)
    for _, t in ipairs(set.textures) do
        if IWTextureSets.same(t.layer, layer) then
            return t.weight
        end
    end
    return nil
end

-- "GRAVEL 90%, DIRT 10%", biggest first.
function IWTextureSets.describe(set)
    if set.pattern ~= nil then
        local seen, names = {}, {}
        for r = 1, set.pattern.h do
            for c = 1, set.pattern.w do
                local layer = set.pattern.rows[r][c]
                if not seen[layer] then
                    seen[layer] = true
                    names[#names + 1] = layer
                end
            end
        end
        return "pattern: " .. table.concat(names, ", ")
    end
    local sum = total(set)
    if sum <= 0 then
        return "nothing picked yet"
    end
    local list = {}
    for _, t in ipairs(set.textures) do
        list[#list + 1] = t
    end
    table.sort(list, function(a, b) return a.weight > b.weight end)
    local parts = {}
    for _, t in ipairs(list) do
        parts[#parts + 1] = string.format("%s %d%%", t.layer, math.floor(t.weight / sum * 100 + 0.5))
    end
    local text = table.concat(parts, ", ")
    if set.details ~= nil then
        text = text .. string.format("  (+ %d detail%s)", #set.details, #set.details == 1 and "" or "s")
    end
    if (set.block or 1) > 1 then
        text = text .. string.format("  (patches of %d x %d texels)", set.block, set.block)
    end
    if set.matchDetails then
        text = text .. "  (+ matching details)"
    end
    if set.force then
        text = text .. "  (over stone)"
    end
    return text
end

-- A new empty set with a free name ("Texture 1", "Texture 2" ...). Returns its index.
function IWTextureSets:add(name)
    local taken = {}
    for _, set in ipairs(self.sets) do
        taken[set.name:upper()] = true
    end
    if name == nil or name == "" then
        local n = 1
        while taken[("Texture " .. n):upper()] do
            n = n + 1
        end
        name = "Texture " .. n
    end
    self.sets[#self.sets + 1] = { name = name, builtin = false, textures = {} }
    return #self.sets
end

-- A copy of a set (an edited one stops being linked to the map's groundMapping entry). Returns its index.
function IWTextureSets:duplicate(index)
    local source = self.sets[index]
    if source == nil then
        return nil
    end
    local copyIndex = self:add(source.name .. " copy")
    local copy = self.sets[copyIndex]
    for _, t in ipairs(source.textures) do
        copy.textures[#copy.textures + 1] = { layer = t.layer, weight = t.weight }
    end
    copy.pattern = source.pattern ~= nil and IWPatterns.copy(source.pattern) or nil
    copy.block = source.block
    copy.force = source.force
    copy.matchDetails = source.matchDetails
    copy.foliage = source.foliage
    copy.details = IWTextureSets.copyDetails(source.details)
    return copyIndex
end

function IWTextureSets:rename(index, name)
    local set = self.sets[index]
    if set == nil or name == nil or name == "" then
        return false
    end
    set.name = name
    return true
end

-- Built-in sets stay (they are what the settings and the saved index mean); returns false for them.
function IWTextureSets:remove(index)
    local set = self.sets[index]
    if set == nil or set.builtin then
        return false
    end
    table.remove(self.sets, index)
    return true
end

-- A pattern only knows the set's layers: a cell of a layer that left the set takes the first layer of the set, and a pattern left with one layer (or a set left with none) goes back to the weighted mix.
function IWTextureSets.prunePattern(set)
    if set.pattern == nil then
        return false
    end
    local first = set.textures[1] ~= nil and set.textures[1].layer or nil
    local distinct, seen, changed = 0, {}, false
    for r = 1, set.pattern.h do
        for c = 1, set.pattern.w do
            local layer = set.pattern.rows[r][c]
            if first ~= nil and IWTextureSets.weightOf(set, layer) == nil then
                layer = first
                set.pattern.rows[r][c] = layer
                changed = true
            end
            if not seen[layer] then
                seen[layer] = true
                distinct = distinct + 1
            end
        end
    end
    if first == nil or distinct <= 1 then
        set.pattern = nil
        return true
    end
    return changed
end

local function touch(set)
    set.edited = true                                  -- (no longer the groundMapping entry's textures)
    IWTextureSets.prunePattern(set)
end

-- In the set or not: adds the layer with DEFAULT_WEIGHT, or takes it out. Returns true when it is in the set afterwards.
function IWTextureSets:toggle(index, layer)
    local set = self.sets[index]
    if set == nil then
        return false
    end
    for i, t in ipairs(set.textures) do
        if IWTextureSets.same(t.layer, layer) then
            table.remove(set.textures, i)
            touch(set)
            return false
        end
    end
    set.textures[#set.textures + 1] = { layer = layer, weight = IWTextureSets.DEFAULT_WEIGHT }
    touch(set)
    return true
end

-- Sets the weight of a layer directly (adding the layer when it is not in the set), 1 to MAX_WEIGHT. Returns the weight.
function IWTextureSets:setWeight(index, layer, weight)
    local set = self.sets[index]
    if set == nil then
        return nil
    end
    if IWTextureSets.weightOf(set, layer) == nil then
        self:toggle(index, layer)
    end
    weight = math.max(1, math.min(IWTextureSets.MAX_WEIGHT, weight))
    for _, t in ipairs(set.textures) do
        if IWTextureSets.same(t.layer, layer) then
            t.weight = weight
        end
    end
    touch(set)
    return weight
end

-- Weight of a layer in the set by delta (steps of WEIGHT_STEP, 1 to MAX_WEIGHT); a layer that is not in the set is added first. Returns the new weight.
function IWTextureSets:addWeight(index, layer, delta)
    local set = self.sets[index]
    if set == nil then
        return nil
    end
    local weight = IWTextureSets.weightOf(set, layer)
    if weight == nil then
        self:toggle(index, layer)
        weight = IWTextureSets.DEFAULT_WEIGHT
    end
    weight = math.max(1, math.min(IWTextureSets.MAX_WEIGHT, weight + delta))
    for _, t in ipairs(set.textures) do
        if IWTextureSets.same(t.layer, layer) then
            t.weight = weight
        end
    end
    touch(set)
    return weight
end

function IWTextureSets.copyDetails(details)
    if details == nil then
        return nil
    end
    local out = {}
    for _, d in ipairs(details) do
        out[#out + 1] = { layer = d.layer, shape = d.shape, chance = d.chance, size = d.size }
    end
    return out
end

-- "Over stone": a set that may be laid over stone and sand ground too (a pattern rolled over cobbles); off, only grass, dirt and gravel are repainted, as before. Returns the new value.
function IWTextureSets:toggleForce(index)
    local set = self.sets[index]
    if set == nil then
        return nil
    end
    set.force = not set.force or nil
    return set.force == true
end

-- A combined layer by its name: the map's convention is capitals (COBBLESTONE04, STONY_DIRT) for the layers that are made of base layers (cobblestone04, stonyDirt): many combined layers wrap one base layer, so
-- the number of sublayers is no test. Names without letters are none.
function IWTextureSets.looksCombined(name)
    local text = tostring(name or "")
    return text:upper() == text and text:lower() ~= text
end

-- A number 0..1 that is always the same for the same block (bi, bj): the choice of a block must not change from one pass to the next.
function IWTextureSets.blockHash(bi, bj)
    local x = math.sin(bi * 12.9898 + bj * 78.233) * 43758.5453
    return x - math.floor(x)
end

-- The patch sizes of a set, in texels: 1 = every texel picks for itself (a fine mix), more = the layer is picked per block of that many texels a side, so a texture that has to stay continuous (cobblestones)
-- does. 4 texels are 2 m on a 0.5 m texel.
IWTextureSets.BLOCK_SIZES = { 1, 2, 4, 8, 16 }

-- The layer for texel (i, j): the set's pattern when it has one (the tile repeats over the world grid), else a weighted pick. random() is math.random.
function IWTextureSets.layerFor(set, i, j, random)
    if set.pattern ~= nil then
        return IWPatterns.layerAt(set.pattern, i, j)
    end
    local block = set.block or 1
    if block > 1 then
        local bi, bj = math.floor(i / block), math.floor(j / block)
        local hash = IWTextureSets.blockHash(bi, bj)
        return IWTextureSets.pick(set, function() return hash end)
    end
    return IWTextureSets.pick(set, random)
end

-- The patch size of a set: the next of BLOCK_SIZES (wrapping round). Returns the new size.
function IWTextureSets:cycleBlock(index)
    local set = self.sets[index]
    if set == nil then
        return nil
    end
    local current = set.block or 1
    local nextSize = IWTextureSets.BLOCK_SIZES[1]
    for i, size in ipairs(IWTextureSets.BLOCK_SIZES) do
        if size == current then
            nextSize = IWTextureSets.BLOCK_SIZES[i % #IWTextureSets.BLOCK_SIZES + 1]
        end
    end
    set.block = nextSize > 1 and nextSize or nil
    touch(set)
    return nextSize
end

-- A preset pattern (IWPatterns.KINDS) from the first two layers of the set. Returns false when the set has no layer yet.
function IWTextureSets:setPreset(index, kind)
    local set = self.sets[index]
    if set == nil or #set.textures == 0 then
        return false
    end
    local tile = IWPatterns.preset(kind, set.textures[1].layer, set.textures[2] ~= nil and set.textures[2].layer or nil)
    if tile == nil then
        return false
    end
    set.pattern = tile
    touch(set)
    return true
end

-- Back to the weighted mix.
function IWTextureSets:clearPattern(index)
    local set = self.sets[index]
    if set == nil or set.pattern == nil then
        return false
    end
    set.pattern = nil
    touch(set)
    return true
end

-- One cell of the pattern goes to the next layer of the set (the palette is the set's layers in their order). Returns the new layer.
function IWTextureSets:cyclePatternCell(index, row, col, direction)
    local set = self.sets[index]
    if set == nil or set.pattern == nil then
        return nil
    end
    local palette = {}
    for _, t in ipairs(set.textures) do
        palette[#palette + 1] = t.layer
    end
    local layer = IWPatterns.cycle(set.pattern, row, col, palette, direction)
    if layer ~= nil then
        touch(set)
    end
    return layer
end

-- ===== details: what driving leaves on a surface (a dirt smudge, a crack, a pothole) =====
-- A set may carry details: { layer, shape = "spot" | "crack", chance = percent per decided texel, size = texels }. Every texel a tyre decides has that chance to also leave the detail (a stamp of that layer round
-- it); the heavier the vehicle the likelier. Random, accumulating with traffic: a road that is driven a lot grows cracks and smudges, one nobody drives stays clean.
IWTextureSets.DETAIL_SHAPES = { "spot", "crack" }
IWTextureSets.DETAIL_CHANCES = { 0.05, 0.1, 0.2, 0.5, 1, 2, 5, 10 }
IWTextureSets.DETAIL_SIZES = { 1, 2, 3, 4, 6, 8 }

-- "Matching details": the layers named <layer of the set>_<damage word> (COBBLESTONE03_CRACKED1, COBBLESTONE03_MISSING2) are details of the set without anyone listing them. Only damage words count, so DIRT does not pull in DIRT_ROAD.
IWTextureSets.DAMAGE_WORDS = { "crack", "missing", "worn", "damage", "broken", "chip", "pothole", "hole" }

-- A wet twin (NAME_POTHOLE1_WET) is not a detail of its own: the game swaps it in for its dry sibling while it rains.
function IWTextureSets.isWetTwin(name)
    return name:lower():sub(-4) == "_wet"
end

-- What a detail of this layer is by default: cracks are cracks (1 percent, 2 texels), a pothole is a rare small hole (0.3 percent), the rest spots (1 percent).
function IWTextureSets.defaultDetail(name)
    local lower = name:lower()
    if lower:find("pothole", 1, true) then
        return { layer = name, shape = "spot", chance = 0.3, size = 2 }
    end
    return { layer = name, shape = lower:find("crack", 1, true) and "crack" or "spot", chance = 1, size = 2 }
end

-- Is the layer a damage variant of another layer of the map (COBBLESTONE03_CRACKED1 next to COBBLESTONE03)? Those are the sets' matching details, not something to look for in the type lists.
function IWTextureSets.isVariant(name, known)
    local lower = name:lower()
    local from = 1
    while true do
        local at = lower:find("_", from, true)
        if at == nil then
            return false
        end
        if known[lower:sub(1, at - 1)] then
            local rest = lower:sub(at + 1)
            for _, word in ipairs(IWTextureSets.DAMAGE_WORDS) do
                if rest:find(word, 1, true) then
                    return true
                end
            end
        end
        from = at + 1
    end
end

-- The detail entries (spot, 1%, 2 texels; "crack" names get the crack shape) for the layers among names that match a layer of the set and are not explicit details already.
function IWTextureSets.matching(set, names)
    local out, taken = {}, {}
    for _, d in ipairs(set.details or {}) do
        taken[d.layer:lower()] = true
    end
    for _, t in ipairs(set.textures) do
        local prefix = t.layer:lower() .. "_"
        for _, name in ipairs(names or {}) do
            local lower = name:lower()
            if not taken[lower] and lower:sub(1, #prefix) == prefix and not IWTextureSets.isWetTwin(name) then
                for _, word in ipairs(IWTextureSets.DAMAGE_WORDS) do
                    if lower:find(word, #prefix + 1, true) then
                        taken[lower] = true
                        out[#out + 1] = IWTextureSets.defaultDetail(name)
                        break
                    end
                end
            end
        end
    end
    return out
end

-- What the tyres leave: the set's own details, plus the matching ones when the set asks for them. namesOf() gives the layer names (called only then); the result is kept until the set changes.
function IWTextureSets.detailsOf(set, namesOf)
    if not set.matchDetails then
        return set.details
    end
    local key = {}
    for _, t in ipairs(set.textures) do
        key[#key + 1] = t.layer
    end
    for _, d in ipairs(set.details or {}) do
        key[#key + 1] = d.layer
    end
    key = table.concat(key, "|")
    if set.matchKey ~= key then
        local all = {}
        for _, d in ipairs(set.details or {}) do
            all[#all + 1] = d
        end
        for _, d in ipairs(IWTextureSets.matching(set, namesOf())) do
            all[#all + 1] = d
        end
        set.matched, set.matchKey = #all > 0 and all or nil, key
    end
    return set.matched
end

-- The damage variants of a layer among the map's layer names: <layer>_<something with a damage word>, each once, without the two mixes (_WORN, _DAMAGED: patches of a mostly intact mix are not a detail).
function IWTextureSets.variantsOf(layer, names)
    local prefix = layer:lower() .. "_"
    local seen, out = {}, {}
    for _, name in ipairs(names or {}) do
        local lower = name:lower()
        if lower:sub(1, #prefix) == prefix and not seen[lower] and lower:sub(-5) ~= "_worn" and lower:sub(-8) ~= "_damaged" and not IWTextureSets.isWetTwin(name) then
            for _, word in ipairs(IWTextureSets.DAMAGE_WORDS) do
                if lower:find(word, #prefix + 1, true) then
                    seen[lower] = true
                    out[#out + 1] = name
                    break
                end
            end
        end
    end
    return out
end

-- A detail the tick brings (see matching) becomes one of the set's own, to tune: the tick then skips it. Returns its index.
function IWTextureSets:adoptDetail(index, detail)
    local set = self.sets[index]
    if set == nil then
        return nil
    end
    set.details = set.details or {}
    set.details[#set.details + 1] = { layer = detail.layer, shape = detail.shape, chance = detail.chance, size = detail.size }
    touch(set)
    return #set.details
end

-- Is any of the layer's variants a detail of the set already?
function IWTextureSets.hasDamage(set, layer, names)
    local wanted = {}
    for _, name in ipairs(IWTextureSets.variantsOf(layer, names)) do
        wanted[name:lower()] = true
    end
    for _, d in ipairs(set.details or {}) do
        if wanted[d.layer:lower()] then
            return true
        end
    end
    return false
end

-- "Add damage": every variant of the layer becomes a detail of the set (a crack for the cracked ones, a spot for the missing stones; 1 percent, 2 texels: tune them in the Details screen). Returns how many were added.
function IWTextureSets:addDamage(index, layer, names)
    local set = self.sets[index]
    if set == nil then
        return 0
    end
    local added = 0
    for _, name in ipairs(IWTextureSets.variantsOf(layer, names)) do
        local present = false
        for _, d in ipairs(set.details or {}) do
            present = present or d.layer:lower() == name:lower()
        end
        if not present then
            set.details = set.details or {}
            set.details[#set.details + 1] = IWTextureSets.defaultDetail(name)
            added = added + 1
        end
    end
    if added > 0 then
        touch(set)
    end
    return added
end

-- "Remove damage": the layer's variants leave the details. Returns how many.
function IWTextureSets:removeDamage(index, layer, names)
    local set = self.sets[index]
    if set == nil or set.details == nil then
        return 0
    end
    local wanted = {}
    for _, name in ipairs(IWTextureSets.variantsOf(layer, names)) do
        wanted[name:lower()] = true
    end
    local kept, removed = {}, 0
    for _, d in ipairs(set.details) do
        if wanted[d.layer:lower()] then
            removed = removed + 1
        else
            kept[#kept + 1] = d
        end
    end
    set.details = #kept > 0 and kept or nil
    if removed > 0 then
        touch(set)
    end
    return removed
end

-- What a set does to the foliage on the texels it paints: "down" (the default, nil: one growth stage per pass), "clear" (gone at once) or "keep" (stays).
IWTextureSets.FOLIAGE_MODES = { "down", "clear", "keep" }

function IWTextureSets.foliageMode(set)
    return set ~= nil and set.foliage or "down"
end

-- The next of FOLIAGE_MODES. Returns the new mode.
function IWTextureSets:cycleFoliage(index)
    local set = self.sets[index]
    if set == nil then
        return nil
    end
    local current = IWTextureSets.foliageMode(set)
    local nextMode = IWTextureSets.FOLIAGE_MODES[1]
    for i, mode in ipairs(IWTextureSets.FOLIAGE_MODES) do
        if mode == current then
            nextMode = IWTextureSets.FOLIAGE_MODES[i % #IWTextureSets.FOLIAGE_MODES + 1]
        end
    end
    set.foliage = nextMode ~= "down" and nextMode or nil
    return nextMode
end

-- The tick: the set pulls in its matching details (or not). Returns the new value.
function IWTextureSets:toggleMatchDetails(index)
    local set = self.sets[index]
    if set == nil then
        return nil
    end
    set.matchDetails = not set.matchDetails or nil
    set.matchKey = nil
    return set.matchDetails == true
end

-- A chance as text without float noise: 0.2, 1, 0.05 (the file stores a float, 0.2 comes back as 0.20000000298).
function IWTextureSets.chanceText(chance)
    local text = string.format("%.2f", chance):gsub("0+$", ""):gsub("%.$", "")
    return text
end

function IWTextureSets:addDetail(index, layer)
    local set = self.sets[index]
    if set == nil then
        return nil
    end
    set.details = set.details or {}
    set.details[#set.details + 1] = { layer = layer, shape = "spot", chance = 0.2, size = 2 }
    return #set.details
end

function IWTextureSets:removeDetail(index, d)
    local set = self.sets[index]
    if set == nil or set.details == nil or set.details[d] == nil then
        return false
    end
    table.remove(set.details, d)
    if #set.details == 0 then
        set.details = nil
    end
    return true
end

-- The next shape / chance / size of the lists (wrapping round). Returns the new value.
function IWTextureSets:cycleDetail(index, d, field)
    local set = self.sets[index]
    local detail = set ~= nil and set.details ~= nil and set.details[d] or nil
    if detail == nil then
        return nil
    end
    local list = field == "shape" and IWTextureSets.DETAIL_SHAPES or field == "chance" and IWTextureSets.DETAIL_CHANCES or IWTextureSets.DETAIL_SIZES
    local nextValue = list[1]
    for i, value in ipairs(list) do
        if value == detail[field] then
            nextValue = list[i % #list + 1]
        end
    end
    detail[field] = nextValue
    return nextValue
end

-- The texels of one stamp round (ci, cj): a spot is a rough disc of size texels across, a crack a wandering line of 2 x size texels in a random direction. random() is math.random. Returns { {i, j} ... }.
function IWTextureSets.detailCells(detail, ci, cj, random)
    local cells, seen = {}, {}
    local function add(i, j)
        local key = i * 65536 + j
        if not seen[key] then
            seen[key] = true
            cells[#cells + 1] = { i, j }
        end
    end
    local size = detail.size or 2
    if detail.shape == "crack" then
        local angle = random() * math.pi
        local length = size * 2
        local x, y = ci - math.cos(angle) * length / 2, cj - math.sin(angle) * length / 2
        for _ = 0, length do
            add(math.floor(x + 0.5), math.floor(y + 0.5))
            angle = angle + (random() - 0.5) * 0.5
            x, y = x + math.cos(angle), y + math.sin(angle)
        end
    else
        local radius = size / 2
        local reach = math.ceil(radius)
        add(ci, cj)
        for di = -reach, reach do
            for dj = -reach, reach do
                if math.sqrt(di * di + dj * dj) + (random() - 0.5) * 0.8 <= radius then
                    add(ci + di, cj + dj)
                end
            end
        end
    end
    return cells
end

-- Plain tables for the file: { { name, builtin, groundName, edited, textures = { { layer, weight } } } }
function IWTextureSets:serialize()
    local out = {}
    for _, set in ipairs(self.sets) do
        local copy = { name = set.name, builtin = set.builtin, groundName = set.groundName, edited = set.edited, textures = {}, pattern = set.pattern ~= nil and IWPatterns.encode(set.pattern) or nil, block = set.block, force = set.force, matchDetails = set.matchDetails, foliage = set.foliage, details = IWTextureSets.copyDetails(set.details) }
        for _, t in ipairs(set.textures) do
            copy.textures[#copy.textures + 1] = { layer = t.layer, weight = t.weight }
        end
        out[#out + 1] = copy
    end
    return out
end

-- Restores what serialize wrote: a built-in set takes the saved textures and name (the player edited it); the others are appended. Unknown layers are kept (the map may have changed: they paint nothing).
function IWTextureSets:restore(saved)
    for _, s in ipairs(saved or {}) do
        local target = nil
        if s.builtin then
            for _, set in ipairs(self.sets) do
                if set.builtin and set.groundName == s.groundName and set.groundName ~= nil then
                    target = set
                end
            end
        end
        if target == nil then
            local index = self:add(s.name)
            target = self.sets[index]
            target.name = s.name
        end
        if s.edited or not target.builtin then
            target.textures = {}
            for _, t in ipairs(s.textures or {}) do
                target.textures[#target.textures + 1] = { layer = t.layer, weight = t.weight }
            end
            target.edited = s.edited or nil
        end
        target.pattern = IWPatterns.decode(s.pattern)
        IWTextureSets.prunePattern(target)
        target.block = (s.block ~= nil and s.block > 1) and s.block or nil
        target.force = s.force == true or nil
        target.matchDetails = s.matchDetails == true or nil
        target.foliage = (s.foliage == "clear" or s.foliage == "keep") and s.foliage or nil
        target.details = (s.details ~= nil and #s.details > 0) and IWTextureSets.copyDetails(s.details) or nil
        if target.builtin and s.name ~= nil then
            target.name = s.name
        end
    end
end

-- A colour for a layer's chip, guessed from its name (linear, as the hub wants): dirt brown, gravel and stone grey, grass green, sand tan, asphalt dark; anything else mid grey.
local COLOURS = {
    { "asphalt", { 0.25, 0.25, 0.27 } }, { "concrete", { 0.6, 0.6, 0.58 } }, { "cobble", { 0.5, 0.48, 0.45 } }, { "gravel", { 0.55, 0.55, 0.55 } }, { "stone", { 0.5, 0.5, 0.5 } },
    { "rock", { 0.45, 0.45, 0.45 } }, { "mud", { 0.35, 0.25, 0.15 } }, { "dirt", { 0.55, 0.35, 0.15 } }, { "soil", { 0.4, 0.28, 0.17 } }, { "sand", { 0.8, 0.7, 0.45 } },
    { "grass", { 0.25, 0.55, 0.2 } }, { "forest", { 0.15, 0.35, 0.15 } }, { "snow", { 0.9, 0.9, 0.95 } },
}
function IWTextureSets.layerColor(layer)
    local lower = tostring(layer or ""):lower()
    local srgb = { 0.5, 0.5, 0.5 }
    for _, entry in ipairs(COLOURS) do
        if lower:find(entry[1], 1, true) then
            srgb = entry[2]
            break
        end
    end
    return srgb[1] ^ 2.2, srgb[2] ^ 2.2, srgb[3] ^ 2.2
end

-- The type of a terrain layer, guessed from its name, for the grouped list of the editor: the first group whose word the name contains wins, in this order.
IWTextureSets.GROUPS = {
    { key = "road", title = "Asphalt and concrete", words = { "asphalt", "concrete", "tarmac", "pavement", "cement", "road" } },
    { key = "gravel", title = "Gravel", words = { "gravel", "pebble", "chipping", "grit" } },
    { key = "stone", title = "Stone", words = { "stone", "rock", "cobble", "rubble", "paver", "slate", "granite", "flag" } },
    { key = "dirt", title = "Dirt and mud", words = { "dirt", "mud", "soil", "clay", "earth", "path", "track" } },
    { key = "sand", title = "Sand", words = { "sand", "beach", "dune" } },
    { key = "grass", title = "Grass and meadow", words = { "grass", "meadow", "lawn", "moss", "clover", "weed" } },
    { key = "forest", title = "Forest floor", words = { "forest", "leaf", "leaves", "needle", "humus", "bark", "wood", "pine" } },
    { key = "field", title = "Fields and crops", words = { "field", "plow", "plough", "furrow", "crop", "stubble", "harvest", "seed", "roller", "cultivat" } },
    { key = "snow", title = "Snow and ice", words = { "snow", "ice", "frost" } },
}
IWTextureSets.OTHER_GROUP = { key = "other", title = "Other", words = {} }

function IWTextureSets.groupOf(layer)
    local lower = tostring(layer or ""):lower()
    for _, group in ipairs(IWTextureSets.GROUPS) do
        for _, word in ipairs(group.words) do
            if lower:find(word, 1, true) then
                return group
            end
        end
    end
    return IWTextureSets.OTHER_GROUP
end
