-- IWPatterns.lua -- a texture pattern: a small tile of texels (cells hold layer names) that repeats over the world's texel grid, so the same texel always gets the same layer (cobblestones, bricks, stripes), against
-- the weighted mix of a set (which picks at random). Pure: no engine calls.
IWPatterns = {}
IWPatterns.SIZE = 4                  -- a tile is 4 x 4 texels: 2 m x 2 m on a 0.5 m texel
IWPatterns.KINDS = { "checker", "stripes", "bricks", "cobble" }

-- letters of the presets (A = the first layer of the set, B = the second): rows of a 4 x 4 tile
local PRESETS = {
    checker = { "ABAB", "BABA", "ABAB", "BABA" },
    stripes = { "ABAB", "ABAB", "ABAB", "ABAB" },
    bricks = { "AAAB", "AAAB", "ABAA", "ABAA" },                  -- stones three texels long, the joints of one row against the next
    cobble = { "AABA", "BAAA", "AAAB", "ABAA" },                  -- scattered joints
}

-- A tile of the preset with layerA and layerB (layerB defaults to layerA): { w, h, rows = { { layer, ... }, ... } }. nil for an unknown kind.
function IWPatterns.preset(kind, layerA, layerB)
    local rows = PRESETS[kind]
    if rows == nil or layerA == nil then
        return nil
    end
    layerB = layerB or layerA
    local tile = { w = IWPatterns.SIZE, h = IWPatterns.SIZE, rows = {} }
    for r = 1, tile.h do
        tile.rows[r] = {}
        for c = 1, tile.w do
            tile.rows[r][c] = rows[r]:sub(c, c) == "A" and layerA or layerB
        end
    end
    return tile
end

-- The layer of texel (i, j) (the integer cell indices of the world grid, negative too): the tile repeats in both directions.
function IWPatterns.layerAt(tile, i, j)
    local c = i % tile.w + 1
    local r = j % tile.h + 1
    return tile.rows[r][c]
end

-- The next layer of the palette (a list of layer names) after the one in a cell, wrapping round; a cell whose layer is not in the palette gets the first. Returns the new layer.
function IWPatterns.cycle(tile, row, col, palette, direction)
    if #palette == 0 then
        return nil
    end
    local current = tile.rows[row][col]
    local index = 0
    for i, name in ipairs(palette) do
        if tostring(name):upper() == tostring(current):upper() then
            index = i
        end
    end
    index = ((index - 1 + (direction or 1)) % #palette) + 1
    tile.rows[row][col] = palette[index]
    return palette[index]
end

-- The letters of a tile against a palette: A for its first layer, B for the second ... ("?" for a layer that is no longer in it), one string per row, and the key.
function IWPatterns.letters(tile, palette)
    local letter = {}
    for i, name in ipairs(palette) do
        letter[tostring(name):upper()] = string.char(64 + math.min(i, 26))
    end
    local rows = {}
    for r = 1, tile.h do
        local cells = {}
        for c = 1, tile.w do
            cells[c] = letter[tostring(tile.rows[r][c]):upper()] or "?"
        end
        rows[r] = table.concat(cells, " ")
    end
    local key = {}
    for i, name in ipairs(palette) do
        key[#key + 1] = string.format("%s = %s", string.char(64 + math.min(i, 26)), name)
    end
    return rows, table.concat(key, ", ")
end

function IWPatterns.copy(tile)
    local out = { w = tile.w, h = tile.h, rows = {} }
    for r = 1, tile.h do
        out.rows[r] = {}
        for c = 1, tile.w do
            out.rows[r][c] = tile.rows[r][c]
        end
    end
    return out
end

-- For the file: one string per row, the layer names joined with "|".
function IWPatterns.encode(tile)
    local rows = {}
    for r = 1, tile.h do
        rows[r] = table.concat(tile.rows[r], "|")
    end
    return rows
end

function IWPatterns.decode(rows)
    if rows == nil or #rows == 0 then
        return nil
    end
    local tile = { w = 0, h = #rows, rows = {} }
    for r, line in ipairs(rows) do
        tile.rows[r] = {}
        for name in tostring(line):gmatch("[^|]+") do
            tile.rows[r][#tile.rows[r] + 1] = name
        end
        tile.w = math.max(tile.w, #tile.rows[r])
    end
    for r = 1, tile.h do
        if #tile.rows[r] ~= tile.w then
            return nil                                                   -- (a ragged tile: the file was edited by hand)
        end
    end
    return tile.w > 0 and tile or nil
end
