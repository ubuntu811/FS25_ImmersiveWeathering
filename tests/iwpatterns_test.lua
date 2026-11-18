-- plain Lua: texture patterns, a tile of texels that repeats over the world grid (IWPatterns)
local passed, failed = 0, 0
local function check(name, ok) if ok then passed = passed + 1 else failed = failed + 1; print("  FAIL " .. name) end end
dofile("scripts/IWPatterns.lua")
local P = IWPatterns

local checker = P.preset("checker", "STONE", "DIRT")
check("a preset is a 4 x 4 tile of layer names", checker.w == 4 and checker.h == 4 and checker.rows[1][1] == "STONE" and checker.rows[1][2] == "DIRT" and checker.rows[2][1] == "DIRT")
check("an unknown kind or no layer is no tile", P.preset("zigzag", "A", "B") == nil and P.preset("checker", nil, "B") == nil)
check("with one layer only, the tile is that layer everywhere", (function() local t = P.preset("cobble", "STONE"); for r = 1, 4 do for c = 1, 4 do if t.rows[r][c] ~= "STONE" then return false end end end return true end)())
local all = true
for _, kind in ipairs(P.KINDS) do all = all and P.preset(kind, "A", "B") ~= nil end
check("every kind in the list makes a tile", all)

-- the tile repeats over the world grid, negative cells too
check("texel (0,0) is the tile's first cell, (1,0) the second", P.layerAt(checker, 0, 0) == "STONE" and P.layerAt(checker, 1, 0) == "DIRT")
check("the tile repeats every four texels in both directions", P.layerAt(checker, 4, 0) == P.layerAt(checker, 0, 0) and P.layerAt(checker, 0, 4) == P.layerAt(checker, 0, 0) and P.layerAt(checker, 7, 9) == P.layerAt(checker, 3, 1))
check("negative cells wrap round the same way (-1 is the last column)", P.layerAt(checker, -1, 0) == P.layerAt(checker, 3, 0) and P.layerAt(checker, 0, -1) == P.layerAt(checker, 0, 3) and P.layerAt(checker, -5, -5) == P.layerAt(checker, 3, 3))
local stripes = P.preset("stripes", "STONE", "DIRT")
check("stripes: a column is one layer, neighbouring columns differ", P.layerAt(stripes, 0, 0) == P.layerAt(stripes, 0, 3) and P.layerAt(stripes, 0, 0) ~= P.layerAt(stripes, 1, 0))
local bricks = P.preset("bricks", "STONE", "DIRT")
check("bricks: the joints of the second pair of rows are not under the first (offset)", bricks.rows[1][4] == "DIRT" and bricks.rows[3][4] == "STONE" and bricks.rows[3][2] == "DIRT")

-- editing a cell: cycles through the palette
local palette = { "STONE", "DIRT", "GRAVEL" }
check("a cell goes to the next layer of the palette", P.cycle(checker, 1, 1, palette, 1) == "DIRT" and checker.rows[1][1] == "DIRT")
check("... and wraps round at the end", P.cycle(checker, 1, 1, palette, 1) == "GRAVEL" and P.cycle(checker, 1, 1, palette, 1) == "STONE")
check("backwards too", P.cycle(checker, 1, 1, palette, -1) == "GRAVEL")
check("a cell whose layer left the palette gets the first", (function() checker.rows[2][2] = "GONE"; return P.cycle(checker, 2, 2, palette, 1) == "STONE" end)())
check("an empty palette changes nothing", P.cycle(checker, 1, 1, {}, 1) == nil)

-- letters, a copy, the file
local rows, key = P.letters(P.preset("checker", "STONE", "DIRT"), { "STONE", "DIRT" })
check("rows as letters (A first layer, B second) and the key", rows[1] == "A B A B" and rows[2] == "B A B A" and key == "A = STONE, B = DIRT")
local tile = P.preset("checker", "STONE", "GONE")
check("a layer that is no longer in the palette shows as ?", P.letters(tile, { "STONE" })[1] == "A ? A ?")
local copy = P.copy(tile)
copy.rows[1][1] = "X"
check("a copy is its own", tile.rows[1][1] == "STONE")
local decoded = P.decode(P.encode(P.preset("bricks", "STONE", "DIRT")))
check("a tile survives the file (rows joined with |)", decoded ~= nil and decoded.w == 4 and decoded.h == 4 and P.layerAt(decoded, 3, 0) == "DIRT" and P.layerAt(decoded, 0, 0) == "STONE")
check("a ragged or empty file is no tile", P.decode({ "A|B", "A" }) == nil and P.decode({}) == nil and P.decode(nil) == nil)
-- names without regard to case
local mixed = P.preset("checker", "cobblestone04", "dirt01")
check("letters match the palette whatever the case", P.letters(mixed, { "COBBLESTONE04", "DIRT01" })[1] == "A B A B")
check("a cell cycles from a lower case name to the next layer of an upper case palette", P.cycle(mixed, 1, 1, { "COBBLESTONE04", "DIRT01" }, 1) == "DIRT01")
print(string.format("iwpatterns_test: %d/%d passed", passed, passed + failed))
os.exit(failed == 0 and 0 or 1)
