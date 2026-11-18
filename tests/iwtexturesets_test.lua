-- plain Lua: the texture sets of the tyre painting (IWTextureSets)
local passed, failed = 0, 0
local function check(name, ok) if ok then passed = passed + 1 else failed = failed + 1; print("  FAIL " .. name) end end
dofile("scripts/IWPatterns.lua")
dofile("scripts/IWTextureSets.lua")
local function defaults()
    return IWTextureSets.new({
        { name = "DIRT", groundName = "DIRT", textures = { { layer = "DIRT", weight = 90 }, { layer = "GRAVEL", weight = 10 } } },
        { name = "GRAVEL", groundName = "GRAVEL", textures = { { layer = "GRAVEL", weight = 90 }, { layer = "DIRT", weight = 10 } } },
    })
end
local sets = defaults()
check("the built-in sets come first, in order", sets:count() == 2 and sets:get(1).name == "DIRT" and sets:get(2).name == "GRAVEL" and sets:get(2).builtin == true)
check("an index that does not exist falls back to the first set", sets:get(9).name == "DIRT")
check("the names of all sets, in order", table.concat(sets:names(), ",") == "DIRT,GRAVEL")

-- picking: weighted
local gravel = sets:get(2)
check("the roll picks by weight: low rolls the first layer, the end of the range the last", IWTextureSets.pick(gravel, function() return 0.1 end) == "GRAVEL" and IWTextureSets.pick(gravel, function() return 0.95 end) == "DIRT" and IWTextureSets.pick(gravel, function() return 0.9 end) == "GRAVEL")
math.randomseed(3)
local gravelCount, n = 0, 20000
for _ = 1, n do if IWTextureSets.pick(gravel) == "GRAVEL" then gravelCount = gravelCount + 1 end end
check("about 90% of 20000 picks are the main layer", gravelCount / n > 0.88 and gravelCount / n < 0.92)
check("an empty set picks nothing", IWTextureSets.pick({ textures = {} }, function() return 0.5 end) == nil)
local main, share = IWTextureSets.main(gravel)
check("the main texture and its share", main == "GRAVEL" and math.abs(share - 0.9) < 1e-9)
check("described biggest first", IWTextureSets.describe(gravel) == "GRAVEL 90%, DIRT 10%" and IWTextureSets.describe({ textures = {} }) == "nothing picked yet")

-- adding, naming, removing
local new = sets:add()
check("a new set is empty, not built-in, and named 'Texture 1'", new == 3 and sets:get(3).name == "Texture 1" and #sets:get(3).textures == 0 and sets:get(3).builtin == false)
check("the next free name is 'Texture 2'", sets:get(sets:add()).name == "Texture 2")
check("a name that is given is kept", sets:get(sets:add("Cobblestone")).name == "Cobblestone")
check("renaming works, an empty name does not", sets:rename(3, "Stone road") and sets:get(3).name == "Stone road" and sets:rename(3, "") == false and sets:get(3).name == "Stone road")
check("built-in sets cannot be deleted", sets:remove(1) == false and sets:count() == 5)
check("a set of the player's can", sets:remove(5) == true and sets:count() == 4)

-- editing: toggle a layer in and out, change its weight
check("toggling a layer adds it with the default weight", sets:toggle(3, "STONE") == true and IWTextureSets.weightOf(sets:get(3), "STONE") == 10)
check("toggling it again takes it out", sets:toggle(3, "STONE") == false and IWTextureSets.weightOf(sets:get(3), "STONE") == nil)
sets:toggle(3, "STONE")
check("more adds a step, up to 100", sets:addWeight(3, "STONE", 10) == 20 and sets:addWeight(3, "STONE", 500) == 100)
check("less takes a step off, down to 1", sets:addWeight(3, "STONE", -500) == 1)
check("a layer that is not in the set is added by the first step", sets:addWeight(3, "GRASS", 10) == 20 and IWTextureSets.weightOf(sets:get(3), "GRASS") == 20)
check("editing a built-in set marks it edited (it stops following the map's groundMapping)", sets:get(1).edited == nil and (function() sets:toggle(1, "STONE"); return sets:get(1).edited == true end)())
local copy = sets:duplicate(3)
check("a copy has the same layers and is the player's own", copy ~= nil and sets:get(copy).builtin == false and sets:get(copy).name == "Stone road copy" and IWTextureSets.weightOf(sets:get(copy), "GRASS") == 20)

-- persistence round trip
local saved = sets:serialize()
local again = defaults()
again:restore(saved)
check("saved and restored: the same sets in the same order", again:count() == sets:count() and table.concat(again:names(), ",") == table.concat(sets:names(), ","))
check("... an edited built-in set keeps its edit", again:get(1).edited == true and IWTextureSets.weightOf(again:get(1), "STONE") == 10)
check("... the player's sets come back with their layers", IWTextureSets.weightOf(again:get(3), "GRASS") == 20 and again:get(3).builtin == false)
check("... an untouched built-in set stays what the defaults say", again:get(2).edited == nil and IWTextureSets.weightOf(again:get(2), "GRAVEL") == 90)
local fresh = defaults()
fresh:restore(nil)
check("nothing saved: the defaults stay", fresh:count() == 2)
-- patterns
local p = defaults()
local pi = p:add("Cobble")
check("a set without layers cannot get a pattern", p:setPreset(pi, "checker") == false)
p:toggle(pi, "STONE")
p:toggle(pi, "DIRT")
check("a preset needs the set's first layers (A, B) and makes a pattern", p:setPreset(pi, "checker") == true and p:get(pi).pattern ~= nil and p:get(pi).pattern.rows[1][1] == "STONE" and p:get(pi).pattern.rows[1][2] == "DIRT")
check("a set with a pattern takes the layer from it, by texel: the same texel always the same layer", IWTextureSets.layerFor(p:get(pi), 0, 0, math.random) == "STONE" and IWTextureSets.layerFor(p:get(pi), 4, 4, math.random) == "STONE" and IWTextureSets.layerFor(p:get(pi), 1, 0, math.random) == "DIRT")
check("a set without a pattern picks by weight", IWTextureSets.layerFor(p:get(1), 0, 0, function() return 0.1 end) == "DIRT")
check("it is described by its layers", IWTextureSets.describe(p:get(pi)) == "pattern: STONE, DIRT")
check("a cell of the pattern goes to the next layer of the set", p:cyclePatternCell(pi, 1, 1, 1) == "DIRT" and p:get(pi).pattern.rows[1][1] == "DIRT")
check("the pattern follows the set to a copy (its own copy), and the file", (function()
    local c = p:duplicate(pi)
    p:get(c).pattern.rows[1][1] = "STONE"
    local saved = p:serialize()
    local again = defaults()
    again:restore(saved)
    return p:get(pi).pattern.rows[1][1] == "DIRT" and again:get(pi).pattern ~= nil and again:get(pi).pattern.rows[1][2] == "DIRT" and again:get(c).pattern.rows[1][1] == "STONE"
end)())
check("clearing the pattern goes back to the mix", p:clearPattern(pi) == true and p:get(pi).pattern == nil and p:clearPattern(pi) == false)
check("a set that was never a pattern has none after a restore", defaults():get(1).pattern == nil)
-- patch size: the layer is picked per block of texels, the same block always the same layer
local b1 = defaults()
local bi = b1:add("Cobble")
for _, name in ipairs({ "A", "B", "C" }) do b1:toggle(bi, name) end
check("without a patch size every texel picks for itself (a fine mix)", (b1:get(bi).block == nil) and IWTextureSets.layerFor(b1:get(bi), 0, 0, function() return 0.1 end) ~= IWTextureSets.layerFor(b1:get(bi), 1, 0, function() return 0.9 end))
check("cycling goes through 1, 2, 4, 8, 16 and wraps", b1:cycleBlock(bi) == 2 and b1:cycleBlock(bi) == 4 and b1:cycleBlock(bi) == 8 and b1:cycleBlock(bi) == 16 and b1:cycleBlock(bi) == 1 and b1:get(bi).block == nil)
b1:cycleBlock(bi)
b1:cycleBlock(bi)
local set4 = b1:get(bi)
check("a set with patches of 4: the 16 texels of a block are one layer", (function()
    local first = IWTextureSets.layerFor(set4, 8, 4, math.random)
    for i = 8, 11 do for j = 4, 7 do if IWTextureSets.layerFor(set4, i, j, math.random) ~= first then return false end end end
    return true
end)())
check("... always the same for the same block, whatever the dice say", IWTextureSets.layerFor(set4, 8, 4, function() return 0.01 end) == IWTextureSets.layerFor(set4, 9, 5, function() return 0.99 end))
check("... and negative cells work (block -1 is texels -4 to -1)", IWTextureSets.layerFor(set4, -1, -1, math.random) == IWTextureSets.layerFor(set4, -4, -4, math.random))
check("different blocks do differ: over 400 blocks all three layers turn up, each about a third", (function()
    local counts = { A = 0, B = 0, C = 0 }
    for bx = 0, 19 do for bz = 0, 19 do local l = IWTextureSets.layerFor(set4, bx * 4, bz * 4, math.random); counts[l] = counts[l] + 1 end end
    return counts.A > 80 and counts.B > 80 and counts.C > 80
end)())
check("the patch size is described, saved, and copied", IWTextureSets.describe(set4):find("patches of 4 x 4 texels", 1, true) ~= nil and (function()
    local again = defaults()
    again:restore(b1:serialize())
    local copyIndex = b1:duplicate(bi)
    return again:get(bi).block == 4 and b1:get(copyIndex).block == 4
end)())
-- layer names compare without regard to case (the combined layer COBBLESTONE04 is the base layer cobblestone04)
do
    local c = defaults()
    local ci = c:add("Cobble")
    c:toggle(ci, "cobblestone04")
    check("a layer saved in lower case is found by its upper case name", IWTextureSets.weightOf(c:get(ci), "COBBLESTONE04") == 10 and IWTextureSets.same("cobblestone04", "COBBLESTONE04"))
    check("toggling the upper case name takes the lower case one out (no second copy)", c:toggle(ci, "COBBLESTONE04") == false and #c:get(ci).textures == 0)
    c:toggle(ci, "cobblestone04")
    c:setWeight(ci, "COBBLESTONE04", 40)
    c:addWeight(ci, "Cobblestone04", 1)
    check("weights follow the layer whatever the case", IWTextureSets.weightOf(c:get(ci), "cobblestone04") == 41 and #c:get(ci).textures == 1)
end
-- details: smudges and cracks left by driving
do
    local d = defaults()
    local di = d:add("Road")
    check("a set starts without details", d:get(di).details == nil)
    check("a detail is added with a layer and sensible defaults", d:addDetail(di, "dirt01") == 1 and d:get(di).details[1].shape == "spot" and d:get(di).details[1].chance == 0.2 and d:get(di).details[1].size == 2)
    check("shape, chance and size cycle through their lists and wrap", d:cycleDetail(di, 1, "shape") == "crack" and d:cycleDetail(di, 1, "shape") == "spot" and d:cycleDetail(di, 1, "chance") == 0.5 and d:cycleDetail(di, 1, "size") == 3)
    for _ = 1, 5 do d:cycleDetail(di, 1, "chance") end
    check("the chance wraps round after the last (10 -> 0.05)", d:get(di).details[1].chance == 0.05)
    local copy = d:duplicate(di)
    d:get(copy).details[1].layer = "X"
    check("a copy has its own details", d:get(di).details[1].layer == "dirt01")
    local again = defaults()
    again:restore(d:serialize())
    check("details survive the file", again:get(di).details ~= nil and again:get(di).details[1].layer == "dirt01" and again:get(di).details[1].size == 3 and again:get(copy).details[1].layer == "X")
    d:toggle(di, "grass01")
check("a set with details is described with their count", IWTextureSets.describe(d:get(di)):find("1 detail", 1, true) ~= nil)
    check("removing the last detail leaves none, and removing a missing one is false", d:removeDetail(di, 1) == true and d:get(di).details == nil and d:removeDetail(di, 1) == false)
    -- the stamps
    local seq = 0
    local function rnd() seq = seq + 1; return (seq * 0.37) % 1 end
    local spot = IWTextureSets.detailCells({ shape = "spot", size = 4 }, 10, 10, rnd)
    local inside = true
    for _, c in ipairs(spot) do if math.abs(c[1] - 10) > 3 or math.abs(c[2] - 10) > 3 then inside = false end end
    check("a spot of size 4 is a rough disc round its centre: the centre, a few cells, none far away", #spot >= 8 and #spot <= 25 and inside and spot[1][1] == 10 and spot[1][2] == 10)
    local one = IWTextureSets.detailCells({ shape = "spot", size = 1 }, 5, 5, rnd)
    check("a spot of size 1 is the centre cell (and at most its neighbours)", #one >= 1 and #one <= 5)
    local crack = IWTextureSets.detailCells({ shape = "crack", size = 4 }, 20, 20, function() return 0.25 end)
    check("a crack is a line of about 2 x size cells without repeats", #crack >= 6 and #crack <= 9 and (function() local seen = {}; for _, c in ipairs(crack) do local k = c[1] * 1000 + c[2]; if seen[k] then return false end seen[k] = true end return true end)())
    check("a crack is thin: a cell touches the next (no gaps wider than a step)", (function()
        for k = 2, #crack do if math.abs(crack[k][1] - crack[k - 1][1]) > 1 or math.abs(crack[k][2] - crack[k - 1][2]) > 1 then return false end end
        return true
    end)())
end
-- over stone
do
    local f = defaults()
    local fi = f:add("Cobble")
    check("a set is not over stone by default", f:get(fi).force == nil)
    check("toggling turns it on, and off again", f:toggleForce(fi) == true and f:get(fi).force == true and f:toggleForce(fi) == false and f:get(fi).force == nil)
    f:toggleForce(fi)
    f:toggle(fi, "A")
    local copy = f:duplicate(fi)
    local again = defaults()
    again:restore(f:serialize())
    check("it is copied with the set and survives the file", f:get(copy).force == true and again:get(fi).force == true and again:get(1).force == nil)
    check("a set over stone says so", IWTextureSets.describe(f:get(fi)):find("(over stone)", 1, true) ~= nil)
end
-- a pattern only knows the set's layers
do
    local f = defaults()
    local fi = f:add("Cobble")
    f:toggle(fi, "cobblestone01"); f:toggle(fi, "cobblestone02")
    f:setPreset(fi, "cobble")
    check("a pattern of two layers is a pattern", f:get(fi).pattern ~= nil)
    f:toggle(fi, "COBBLESTONE03")
    check("a new layer leaves the pattern alone", f:get(fi).pattern ~= nil and IWTextureSets.describe(f:get(fi)) == "pattern: cobblestone01, cobblestone02")
    f:toggle(fi, "cobblestone02")
    check("a layer that leaves the set leaves the pattern: its cells take the first layer, one layer left goes back to the mix", f:get(fi).pattern == nil)
    f:toggle(fi, "cobblestone01")
    check("with every old layer gone the pattern is gone and the roller picks from the set", f:get(fi).pattern == nil and IWTextureSets.layerFor(f:get(fi), 3, 4, function() return 0.5 end) == "COBBLESTONE03")
    local old = defaults()
    local oi = old:add("Cobble")
    old:toggle(oi, "COBBLESTONE03")
    local saved = old:serialize()
    for _, sv in ipairs(saved) do if sv.name == "Cobble" then sv.pattern = { "cobblestone01|cobblestone02|cobblestone01|cobblestone01" } end end
    local loaded = defaults()
    loaded:restore(saved)
    check("a saved set whose pattern names layers that are not in it loads without the pattern", loaded:get(3).name == "Cobble" and loaded:get(3).pattern == nil)
end
-- matching details
do
    local f = defaults()
    local fi = f:add("Cobble")
    f:toggle(fi, "COBBLESTONE03"); f:toggle(fi, "DIRT")
    local names = { "COBBLESTONE03", "COBBLESTONE03_CRACKED1", "COBBLESTONE03_MISSING2", "COBBLESTONE03_WORN", "COBBLESTONE04_CRACKED1", "DIRT_ROAD", "DIRT", "COBBLESTONE03_GLOSSY" }
    local m = IWTextureSets.matching(f:get(fi), names)
    check("the layers named after a layer of the set with a damage word match, other layers do not", #m == 3 and m[1].layer == "COBBLESTONE03_CRACKED1" and m[2].layer == "COBBLESTONE03_MISSING2" and m[3].layer == "COBBLESTONE03_WORN")
    check("a crack name gets the crack shape, the rest are spots, all small and rare", m[1].shape == "crack" and m[2].shape == "spot" and m[1].chance == 1 and m[1].size == 2)
    f:addDetail(fi, "COBBLESTONE03_WORN")
    check("an explicit detail is not matched twice", #IWTextureSets.matching(f:get(fi), names) == 2)
    local calls = 0
    local function namesOf() calls = calls + 1; return names end
    check("without the tick the set's own details are all there is, and nobody asks for the names", IWTextureSets.detailsOf(f:get(fi), namesOf)[1].layer == "COBBLESTONE03_WORN" and #IWTextureSets.detailsOf(f:get(fi), namesOf) == 1 and calls == 0)
    check("the tick turns on and off", f:toggleMatchDetails(fi) == true and f:get(fi).matchDetails == true)
    local all = IWTextureSets.detailsOf(f:get(fi), namesOf)
    IWTextureSets.detailsOf(f:get(fi), namesOf)
    check("with it the explicit and the matching details together, worked out once", #all == 3 and calls == 1)
    f:toggle(fi, "COBBLESTONE04")
    IWTextureSets.detailsOf(f:get(fi), namesOf)
    check("a change of the set's layers works it out again", calls == 2 and #IWTextureSets.detailsOf(f:get(fi), namesOf) == 4)
    local copy = f:duplicate(fi)
    local again = defaults()
    again:restore(f:serialize())
    check("the tick is copied and survives the file", f:get(copy).matchDetails == true and again:get(fi).matchDetails == true and again:get(1).matchDetails == nil and IWTextureSets.describe(f:get(fi)):find("matching details", 1, true) ~= nil)
    check("and goes off again", f:toggleMatchDetails(fi) == false and f:get(fi).matchDetails == nil)
end
do
    local f = defaults()
    local fi = f:add("Cobble")
    check("a set wears foliage down by default, then removes it, then leaves it, then round again", IWTextureSets.foliageMode(f:get(fi)) == "down" and f:cycleFoliage(fi) == "clear" and f:cycleFoliage(fi) == "keep" and f:get(fi).foliage == "keep" and f:cycleFoliage(fi) == "down" and f:get(fi).foliage == nil)
    f:cycleFoliage(fi)
    local copy = f:duplicate(fi)
    local again = defaults()
    again:restore(f:serialize())
    check("the foliage mode is copied and survives the file", f:get(copy).foliage == "clear" and again:get(fi).foliage == "clear" and again:get(1).foliage == nil)
end
do
    local known = {}
    for _, n in ipairs({ "cobblestone03", "cobblestone03_cracked1", "cobblestone03_worn", "dirt", "dirt_road", "stony_dirt", "dirt_damaged" }) do known[n] = true end
    check("a damage variant of a layer that exists is a variant, other layers (and names with an underscore) are not", IWTextureSets.isVariant("COBBLESTONE03_CRACKED1", known) and IWTextureSets.isVariant("COBBLESTONE03_WORN", known) and IWTextureSets.isVariant("DIRT_DAMAGED", known) and not IWTextureSets.isVariant("COBBLESTONE03", known) and not IWTextureSets.isVariant("DIRT_ROAD", known) and not IWTextureSets.isVariant("STONY_DIRT", known) and not IWTextureSets.isVariant("GHOST_CRACKED", known))
end
-- add damage: a layer's variants as details
do
    local names = { "COBBLESTONE01", "COBBLESTONE01_CRACKED1", "COBBLESTONE01_CRACKED2", "COBBLESTONE01_MISSING1", "COBBLESTONE01_WORN", "COBBLESTONE01_DAMAGED", "COBBLESTONE02", "COBBLESTONE02_CRACKED1", "cobblestone01_cracked1", "DIRT", "DIRT_ROAD" }
    local v = IWTextureSets.variantsOf("COBBLESTONE01", names)
    check("the variants of a layer: its cracked and missing ones, each once, not the mixes, not another layer's", #v == 3 and v[1] == "COBBLESTONE01_CRACKED1" and v[2] == "COBBLESTONE01_CRACKED2" and v[3] == "COBBLESTONE01_MISSING1")
    check("a layer without variants has none (DIRT_ROAD is a layer of its own)", #IWTextureSets.variantsOf("DIRT", names) == 0 and #IWTextureSets.variantsOf("cobblestone01", names) == 3)
    local f = defaults()
    local fi = f:add("Cobble")
    check("a set without details has no damage", IWTextureSets.hasDamage(f:get(fi), "COBBLESTONE01", names) == false)
    check("add damage: three details, cracks as cracks, missing stones as spots, small and rare", f:addDamage(fi, "COBBLESTONE01", names) == 3 and #f:get(fi).details == 3 and f:get(fi).details[1].shape == "crack" and f:get(fi).details[3].shape == "spot" and f:get(fi).details[1].chance == 1 and f:get(fi).details[1].size == 2)
    check("... the set has damage now, a second add adds nothing", IWTextureSets.hasDamage(f:get(fi), "COBBLESTONE01", names) and f:addDamage(fi, "COBBLESTONE01", names) == 0 and #f:get(fi).details == 3)
    f:addDetail(fi, "DIRT")
    check("the damage of another layer is not this layer's", IWTextureSets.hasDamage(f:get(fi), "COBBLESTONE02", names) == false and f:addDamage(fi, "COBBLESTONE02", names) == 1 and #f:get(fi).details == 5)
    check("remove damage: only that layer's variants go, the other details stay", f:removeDamage(fi, "COBBLESTONE01", names) == 3 and #f:get(fi).details == 2 and f:get(fi).details[1].layer == "DIRT" and IWTextureSets.hasDamage(f:get(fi), "COBBLESTONE01", names) == false)
    f:removeDamage(fi, "COBBLESTONE02", names)
    f:removeDamage(fi, "DIRT_X", names)
    check("... and a set whose last detail goes has none (nil)", #f:get(fi).details == 1 and f:removeDamage(fi, "COBBLESTONE01", names) == 0)
end
-- potholes and their wet twins
do
    local names = { "COBBLESTONE03", "COBBLESTONE03_CRACKED1", "COBBLESTONE03_POTHOLE1", "COBBLESTONE03_POTHOLE1_WET", "COBBLESTONE03_POTHOLE2", "COBBLESTONE03_POTHOLE2_WET", "COBBLESTONE03_DAMAGED" }
    check("a wet twin is recognised, a dry pothole is not", IWTextureSets.isWetTwin("COBBLESTONE03_POTHOLE1_WET") and IWTextureSets.isWetTwin("x_wet") and not IWTextureSets.isWetTwin("COBBLESTONE03_POTHOLE1") and not IWTextureSets.isWetTwin("WETLAND"))
    local pot = IWTextureSets.defaultDetail("COBBLESTONE03_POTHOLE1")
    local crack = IWTextureSets.defaultDetail("COBBLESTONE03_CRACKED1")
    check("a pothole is a rare small spot, a crack a crack, the rest spots", pot.shape == "spot" and pot.chance == 0.3 and pot.size == 2 and crack.shape == "crack" and crack.chance == 1 and IWTextureSets.defaultDetail("COBBLESTONE03_MISSING1").shape == "spot")
    local v = IWTextureSets.variantsOf("COBBLESTONE03", names)
    check("the variants of a layer leave out the wet twins (and the mix): cracked1 and the two dry potholes", #v == 3 and v[1] == "COBBLESTONE03_CRACKED1" and v[2] == "COBBLESTONE03_POTHOLE1" and v[3] == "COBBLESTONE03_POTHOLE2")
    local f = defaults()
    local fi = f:add("Cobble")
    f:toggle(fi, "COBBLESTONE03")
    local m = IWTextureSets.matching(f:get(fi), names)
    check("the matching details are the same three plus the mix, no wet twin; the potholes at 0.3 percent", #m == 4 and not (m[1].layer .. m[2].layer .. m[3].layer .. m[4].layer):find("_WET", 1, true) and m[2].chance == 0.3 and m[1].chance == 1)
    f:addDamage(fi, "COBBLESTONE03", names)
    check("add damage: the potholes come at 0.3 percent, cracks at 1", #f:get(fi).details == 3 and f:get(fi).details[2].layer == "COBBLESTONE03_POTHOLE1" and f:get(fi).details[2].chance == 0.3 and f:get(fi).details[1].chance == 1)
end
check("a chance reads without float noise", IWTextureSets.chanceText(0.20000000298023224) == "0.2" and IWTextureSets.chanceText(1) == "1" and IWTextureSets.chanceText(0.05) == "0.05" and IWTextureSets.chanceText(10) == "10")
check("a layer name in capitals is a combined layer (the map's convention), camel case is a base layer", IWTextureSets.looksCombined("COBBLESTONE04") and IWTextureSets.looksCombined("STONY_DIRT") and IWTextureSets.looksCombined("DIRT") and not IWTextureSets.looksCombined("cobblestone04") and not IWTextureSets.looksCombined("stonyDirt") and not IWTextureSets.looksCombined("") and not IWTextureSets.looksCombined("123") and not IWTextureSets.looksCombined(nil))
local r, g, b = IWTextureSets.layerColor("GRAVEL")
local dr, dg, db = IWTextureSets.layerColor("dirt01")
local rUnknown, gUnknown = IWTextureSets.layerColor("weirdThing")
check("a layer gets a colour from its name (gravel grey, dirt brown, an unknown name mid grey)", math.abs(r - 0.55 ^ 2.2) < 1e-9 and r == g and g == b and dr > dg and dg > db and rUnknown == gUnknown)
print(string.format("iwtexturesets_test: %d/%d passed", passed, passed + failed))
os.exit(failed == 0 and 0 or 1)
