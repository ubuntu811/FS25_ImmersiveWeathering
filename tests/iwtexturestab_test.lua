-- plain Lua: the texture sets as a hub tab (IWTexturesTab): sets, the types of layers, the layers
local passed, failed = 0, 0
local function check(name, ok) if ok then passed = passed + 1 else failed = failed + 1; print("  FAIL " .. name) end end
dofile("scripts/IWPatterns.lua")
dofile("scripts/IWTextureSets.lua")
dofile("scripts/IWTexturesTab.lua")
local sets = IWTextureSets.new({
    { name = "DIRT", groundName = "DIRT", textures = { { layer = "DIRT", weight = 90 }, { layer = "GRAVEL", weight = 10 } } },
    { name = "GRAVEL", groundName = "GRAVEL", textures = { { layer = "GRAVEL", weight = 90 }, { layer = "DIRT", weight = 10 } } },
})
local active, changes, asked = 1, 0, {}
local layers = { "dirt01", "dirtMud02", "gravelBig", "stoneCobble", "grass01", "grassDry", "asphaltCracks", "sand01", "forestLeaves", "plowedField", "weirdThing" }
local tab = IWTexturesTab.new({
    sets = sets, layerNames = function() return layers end,
    getActive = function() return active end, setActive = function(i) active = i end,
    changed = function() changes = changes + 1 end,
    askName = function(default, callback) asked.default = default; asked.callback = callback end,
})
local function find(list, label) for _, b in ipairs(list) do if b.label == label then return b end end end

-- grouping by type
check("a layer is grouped by the first matching word of its name (gravel and stone are two types)", IWTextureSets.groupOf("gravelBig").key == "gravel" and IWTextureSets.groupOf("stoneCobble").key == "stone" and IWTextureSets.groupOf("dirtMud02").key == "dirt" and IWTextureSets.groupOf("asphaltCracks").key == "road" and IWTextureSets.groupOf("weirdThing").key == "other")
check("... nil and empty names are 'other'", IWTextureSets.groupOf(nil).key == "other" and IWTextureSets.groupOf("").key == "other")

-- the sets level
local items = IWTexturesTab.items(tab)
check("the sets level lists the sets", #items == 2 and items[1].kind == "set")
local primary, secondary = IWTexturesTab.describeItem(tab, items[1])
check("a set shows its name, 'in use' and its mix", primary == "DIRT  (in use)" and secondary == "DIRT 90%, GRAVEL 10%")
local share = IWTexturesTab.meter(tab, items[2])
check("the meter is the share of the main layer and the chip its colour", math.abs(share - 0.9) < 1e-9 and select(1, IWTexturesTab.color(tab, items[2])) == IWTextureSets.layerColor("GRAVEL"))
local buttons = IWTexturesTab.buttons(tab, items[1])
check("a built-in set has Use, Edit, Mix, Replaces, Foliage, Details, Pattern, Add, Rename, Duplicate and no Delete", #buttons == 10 and find(buttons, "Foliage: wears down") and find(buttons, "Use") and find(buttons, "Edit") and find(buttons, "Replaces: grass, dirt, gravel") and find(buttons, "Mix: per texel") and find(buttons, "Details  (0)") and find(buttons, "Pattern") and find(buttons, "Add") and find(buttons, "Rename") and find(buttons, "Duplicate") and not find(buttons, "Delete"))
find(buttons, "Use").callback()
check("Use makes the set the one the tyres paint with", active == 1)
find(IWTexturesTab.buttons(tab, items[2]), "Use").callback()
check("... any set", active == 2)
find(buttons, "Duplicate").callback()
check("Duplicate adds a copy and saves", sets:count() == 3 and changes == 1)
check("the copy is the player's and has Delete", find(IWTexturesTab.buttons(tab, IWTexturesTab.items(tab)[3]), "Delete") ~= nil)
find(buttons, "Rename").callback()
asked.callback("Dirt road")
check("Rename asks for a name with the old one as default, and saves the new one", asked.default == "DIRT" and sets:get(1).name == "Dirt road" and changes == 2)
asked.callback("")
check("an empty name changes nothing", sets:get(1).name == "Dirt road" and changes == 2)

-- Add: a new empty set, straight into the editor
find(buttons, "Add").callback()
check("Add makes an empty set and opens it in the editor (the types level)", sets:count() == 4 and #sets:get(4).textures == 0 and tab.mode == "groups" and tab.setIndex == 4)

-- the types level
local groups = IWTexturesTab.items(tab)
local titles = {}
for _, g in ipairs(groups) do titles[#titles + 1] = g.entry.group.title end
check("layers are listed by type, empty types left out, in the fixed order, no 'In this set' while the set is empty", table.concat(titles, "|") == "Asphalt and concrete|Gravel|Stone|Dirt and mud|Sand|Grass and meadow|Forest floor|Fields and crops|Other")
local gravelRow = groups[4]
check("a type row says how many layers it has and how many are in the set", select(2, IWTexturesTab.describeItem(tab, gravelRow)) == "2 layer(s), 0 in 'Texture 1' (0% of it)")
-- the layers of the selected type are buttons: one click puts a layer in the set or takes it out
local typeButtons = IWTexturesTab.buttons(tab, gravelRow)
check("the type row lists its layers as buttons, then Weights and Done (no page button for two layers)", #typeButtons == 4 and typeButtons[1].label == "dirt01" and typeButtons[2].label == "dirtMud02" and find(typeButtons, "Weights") and find(typeButtons, "Done") and not find(typeButtons, "More layers  (page 1 of 1)"))
changes = 0
typeButtons[1].callback()
check("one click on a layer button puts it in the set (default weight) and saves", IWTextureSets.weightOf(sets:get(4), "dirt01") == 10 and changes == 1)
check("... and the button is marked now", IWTexturesTab.buttons(tab, gravelRow)[1].label == "> dirt01" and IWTexturesTab.buttons(tab, gravelRow)[2].label == "dirtMud02")
IWTexturesTab.buttons(tab, gravelRow)[1].callback()
check("a click on a marked one takes it out again", IWTextureSets.weightOf(sets:get(4), "dirt01") == nil)
typeButtons[1].callback()
typeButtons[2].callback()
-- paging: a type with more layers than a page
do
    local manyLayers = {}
    for i = 1, 20 do manyLayers[i] = string.format("gravel%02d", i) end
    local pagedSets = IWTextureSets.new({ { name = "DIRT", groundName = "DIRT", textures = { { layer = "DIRT", weight = 90 } } } })
    local paged = IWTexturesTab.new({ sets = pagedSets, layerNames = function() return manyLayers end, getActive = function() return 1 end, setActive = function() end, changed = function() end })
    paged.setIndex, paged.mode = 1, "groups"
    local row = IWTexturesTab.items(paged)[2]
    local first = IWTexturesTab.buttons(paged, row)
    check("20 layers: 8 on a page, the page button, Weights, Done (11 slots, none over)", #first == 11 and first[1].label == "gravel01" and first[8].label == "gravel08" and first[9].label == "More layers  (page 1 of 3)")
    first[9].callback()
    local second = IWTexturesTab.buttons(paged, row)
    check("the page button goes to the next page", second[1].label == "gravel09" and second[9].label == "More layers  (page 2 of 3)")
    IWTexturesTab.buttons(paged, row)[9].callback()
    local third = IWTexturesTab.buttons(paged, row)
    check("the last page has the rest (4 layers) and the page button", #third == 7 and third[1].label == "gravel17" and third[4].label == "gravel20")
    IWTexturesTab.buttons(paged, row)[5].callback()
    check("... and wraps to the first page", IWTexturesTab.buttons(paged, row)[1].label == "gravel01")
    second = IWTexturesTab.buttons(paged, row)
    second[9].callback()
    local other = IWTexturesTab.items(paged)[1]
    check("a click on a layer of page two adds that layer", (function() IWTexturesTab.buttons(paged, row)[2].callback(); return IWTextureSets.weightOf(pagedSets:get(1), "gravel10") == 10 end)())
    check("another type starts on its first page again", (function() paged.pageGroup = "dirt"; return IWTexturesTab.buttons(paged, row)[1].label == "gravel01" end)())
end
find(typeButtons, "Weights").callback()
check("Weights goes to the layers of that type", tab.mode == "layers" and tab.group == "dirt")
local layerItems = IWTexturesTab.items(tab)
check("the layers of the type are listed", #layerItems == 2 and layerItems[1].layer == "dirt01" and layerItems[2].layer == "dirtMud02")
check("a layer in the set shows its weight and share, with a lit meter", select(2, IWTexturesTab.describeItem(tab, layerItems[1])) == "in 'Texture 1': weight 10 (50%)" and math.abs(IWTexturesTab.meter(tab, layerItems[1]) - 0.5) < 1e-9)
local layerButtons = IWTexturesTab.buttons(tab, layerItems[1])
check("a layer has Add / remove, six weight buttons (5 10 25 50 75 100), the fine pair, Back and Done: 11", #layerButtons == 11 and find(layerButtons, "Add / remove") and find(layerButtons, "> Weight 10") and find(layerButtons, "Weight 5") and find(layerButtons, "Weight 100") and find(layerButtons, "More  (+1)") and find(layerButtons, "Less  (-1)") and find(layerButtons, "Back to the types") and find(layerButtons, "Done"))
changes = 0
find(layerButtons, "Weight 75").callback()
check("a weight button sets the weight directly and saves, the marker follows", IWTextureSets.weightOf(sets:get(4), "dirt01") == 75 and changes == 1 and find(IWTexturesTab.buttons(tab, layerItems[1]), "> Weight 75") ~= nil)
check("a weight on a layer that is not in the set adds it", (function() find(IWTexturesTab.buttons(tab, layerItems[1]), "Add / remove").callback(); find(IWTexturesTab.buttons(tab, layerItems[1]), "Weight 25").callback(); return IWTextureSets.weightOf(sets:get(4), "dirt01") == 25 end)())
find(layerButtons, "More  (+1)").callback()
check("the fine button adds one (a 97 / 3 mix is possible)", IWTextureSets.weightOf(sets:get(4), "dirt01") == 26)
find(layerButtons, "Less  (-1)").callback()
find(IWTexturesTab.buttons(tab, layerItems[1]), "Weight 5").callback()
find(IWTexturesTab.buttons(tab, layerItems[1]), "Back to the types").callback()
groups = IWTexturesTab.items(tab)
check("Back goes to the types; the set's own layers are the first row now", tab.mode == "groups" and groups[1].entry.group.key == "set" and #groups[1].entry.layers == 2 and select(2, IWTexturesTab.describeItem(tab, groups[1])) == "2 layer(s) of 'Texture 1'")
local gravelAgain
for _, g in ipairs(groups) do if g.entry.group.key == "dirt" then gravelAgain = g end end
check("a type shows its share of the set (both layers are dirt: 100%)", select(2, IWTexturesTab.describeItem(tab, gravelAgain)):find("2 in 'Texture 1' (100% of it)", 1, true) ~= nil and IWTexturesTab.meter(tab, gravelAgain) == 1)
find(IWTexturesTab.buttons(tab, gravelAgain), "Done").callback()
check("Done goes back to the sets", tab.mode == "sets")

-- the pattern assembler: a tile of texels (cobblestones, bricks, stripes), a cell at a time
do
    local pSets = IWTextureSets.new({ { name = "DIRT", groundName = "DIRT", textures = { { layer = "DIRT", weight = 90 }, { layer = "GRAVEL", weight = 10 } } } })
    local patternChanges = 0
    local pTab = IWTexturesTab.new({ sets = pSets, layerNames = function() return layers end, getActive = function() return 1 end, setActive = function() end, changed = function() patternChanges = patternChanges + 1 end })
    local mine = pSets:add("Cobble")
    pSets:toggle(mine, "dirtMud02")
    pSets:toggle(mine, "dirt01")
    local setItems = IWTexturesTab.items(pTab)
    find(IWTexturesTab.buttons(pTab, setItems[mine]), "Pattern").callback()
    check("Pattern on a set with layers opens the pattern editor with a checker to start from", pTab.mode == "pattern" and pTab.setIndex == mine and pSets:get(mine).pattern ~= nil and patternChanges == 1)
    local rows = IWTexturesTab.items(pTab)
    check("the editor lists the rows of the tile and a key", #rows == 5 and rows[1].kind == "prow" and rows[5].kind == "pkey")
    local primary, secondary = IWTexturesTab.describeItem(pTab, rows[1])
    check("a row shows its letters (A first layer, B second)", primary == "Row 1 of 4" and secondary == "A B A B")
    check("the key says what the letters are", select(2, IWTexturesTab.describeItem(pTab, rows[5])) == "A = dirtMud02, B = dirt01")
    check("a row has a chip, a key row and the meter none", IWTexturesTab.color(pTab, rows[1]) ~= nil and IWTexturesTab.color(pTab, rows[5]) == nil and IWTexturesTab.meter(pTab, rows[1]) == nil)
    local rowButtons = IWTexturesTab.buttons(pTab, rows[1])
    check("a row has one button per cell (showing its letter), the four presets, Back to the mix and Done", #rowButtons == 10 and find(rowButtons, "Cell 1  (A)") and find(rowButtons, "Cell 2  (B)") and find(rowButtons, "Checker") and find(rowButtons, "Stripes") and find(rowButtons, "Bricks") and find(rowButtons, "Cobble") and find(rowButtons, "Back to the mix") and find(rowButtons, "Done"))
    patternChanges = 0
    find(rowButtons, "Cell 1  (A)").callback()
    check("a cell button sends that cell to the next layer and saves", pSets:get(mine).pattern.rows[1][1] == "dirt01" and patternChanges == 1)
    check("the button shows the new letter", find(IWTexturesTab.buttons(pTab, IWTexturesTab.items(pTab)[1]), "Cell 1  (B)") ~= nil and select(2, IWTexturesTab.describeItem(pTab, IWTexturesTab.items(pTab)[1])) == "B B A B")
    find(IWTexturesTab.buttons(pTab, IWTexturesTab.items(pTab)[2]), "Bricks").callback()
    check("a preset replaces the pattern", pSets:get(mine).pattern.rows[1][4] == "dirt01" and pSets:get(mine).pattern.rows[1][1] == "dirtMud02")
    check("the key row has the presets and no cell buttons", #IWTexturesTab.buttons(pTab, IWTexturesTab.items(pTab)[5]) == 6)
    find(IWTexturesTab.buttons(pTab, IWTexturesTab.items(pTab)[1]), "Done").callback()
    check("Done goes back to the sets, the pattern stays", pTab.mode == "sets" and pSets:get(mine).pattern ~= nil)
    check("a set with a pattern is described by it in the list", select(2, IWTexturesTab.describeItem(pTab, IWTexturesTab.items(pTab)[mine])):find("pattern: dirtMud02, dirt01", 1, true) ~= nil)
    find(IWTexturesTab.buttons(pTab, IWTexturesTab.items(pTab)[mine]), "Pattern").callback()
    find(IWTexturesTab.buttons(pTab, IWTexturesTab.items(pTab)[1]), "Back to the mix").callback()
    check("Back to the mix takes the pattern off and leaves the editor", pSets:get(mine).pattern == nil and pTab.mode == "sets")
    -- a set with no layers yet: the editor says what is missing
    local blank = pSets:add("Blank")
    find(IWTexturesTab.buttons(pTab, IWTexturesTab.items(pTab)[blank]), "Pattern").callback()
    local hint = IWTexturesTab.items(pTab)
    check("a set with no layers has no pattern to start from: the editor says so", pSets:get(blank).pattern == nil and #hint == 1 and hint[1].kind == "empty" and select(1, IWTexturesTab.describeItem(pTab, hint[1])) == "No pattern yet")
    check("... and its presets do nothing until the set has a layer", (function() find(IWTexturesTab.buttons(pTab, hint[1]), "Checker").callback(); return pSets:get(blank).pattern == nil end)())
end

-- the over stone button
do
    local oSets = IWTextureSets.new({ { name = "DIRT", groundName = "DIRT", textures = { { layer = "dirt01", weight = 50 } } } })
    local oTab = IWTexturesTab.new({ sets = oSets, layerNames = function() return layers end, getActive = function() return 1 end, setActive = function() end, changed = function() end })
    local row = IWTexturesTab.items(oTab)[1]
    find(IWTexturesTab.buttons(oTab, row), "Replaces: grass, dirt, gravel").callback()
    check("the Replaces button turns stone and sand on and says so", oSets:get(1).force == true and find(IWTexturesTab.buttons(oTab, row), "Replaces: grass, dirt, gravel, stone, sand") ~= nil)
end

-- the patch size button: per texel, 1 m, 2 m ... patches (the texel is 0.5 m unless the tab is told)
do
    local bSets = IWTextureSets.new({ { name = "DIRT", groundName = "DIRT", textures = { { layer = "DIRT", weight = 90 } } } })
    local texel = 0.5
    local bTab = IWTexturesTab.new({ sets = bSets, layerNames = function() return layers end, getActive = function() return 1 end, setActive = function() end, changed = function() end, texelSize = function() return texel end })
    local item = IWTexturesTab.items(bTab)[1]
    local patch = find(IWTexturesTab.buttons(bTab, item), "Mix: per texel")
    patch.callback()
    check("the patch button cycles the patch size of the set and says it in metres", bSets:get(1).block == 2 and find(IWTexturesTab.buttons(bTab, item), "Mix: 1 m patches") ~= nil)
    find(IWTexturesTab.buttons(bTab, item), "Mix: 1 m patches").callback()
    check("... 2 m next (4 texels of 0.5 m)", find(IWTexturesTab.buttons(bTab, item), "Mix: 2 m patches") ~= nil)
    texel = 0.25
    check("... and it follows the map's texel size", find(IWTexturesTab.buttons(bTab, item), "Mix: 1 m patches") ~= nil)
end

-- the picture of a row: the terrain layer id of its layer
do
    local ids = { DIRT = 11, dirt01 = 12, grass01 = 13 }
    local pSets = IWTextureSets.new({ { name = "DIRT", groundName = "DIRT", textures = { { layer = "DIRT", weight = 90 } } } })
    local pTab = IWTexturesTab.new({ sets = pSets, layerNames = function() return layers end, getActive = function() return 1 end, setActive = function() end, changed = function() end, layerId = function(name) return ids[name] end })
    check("a set row shows the texture of its main layer", IWTexturesTab.layerId(pTab, IWTexturesTab.items(pTab)[1]) == 11)
    pTab.setIndex, pTab.mode = 1, "groups"
    local groupRows = IWTexturesTab.items(pTab)
    check("a type row shows its first layer, a layer row its own", IWTexturesTab.layerId(pTab, groupRows[1]) == 11 and (function() pTab.mode, pTab.group = "layers", "grass"; return IWTexturesTab.layerId(pTab, IWTexturesTab.items(pTab)[1]) == 13 end)())
    check("a layer the map does not know has no picture (the colour chip stays)", (function() pTab.group = "dirt"; local it = IWTexturesTab.items(pTab); return IWTexturesTab.layerId(pTab, it[2]) == nil end)())
    local noApi = IWTexturesTab.new({ sets = pSets, layerNames = function() return layers end, getActive = function() return 1 end, setActive = function() end, changed = function() end })
    check("without a layerId lookup there is no picture", IWTexturesTab.layerId(noApi, IWTexturesTab.items(noApi)[1]) == nil)
    check("the descriptor hands the hub the picture lookup", type(IWTexturesTab.descriptor(pTab, "T", "i").getItemLayer) == "function")
    pTab.mode, pTab.setIndex = "groups", 1
    local typeRow = nil
    for _, it in ipairs(IWTexturesTab.items(pTab)) do if it.kind == "group" and it.entry.group.key == "dirt" then typeRow = it end end
    local layerButtons = IWTexturesTab.buttons(pTab, typeRow)
    check("the layer buttons of a type carry the layer's id (the hub shows its picture left of the button)", layerButtons[1].layerId == 12 and layerButtons[1].label:find("dirt01", 1, true) ~= nil)
    check("a button that is no layer (Weights, Done) carries none", layerButtons[#layerButtons].layerId == nil and layerButtons[#layerButtons - 1].layerId == nil)
    check("a layer the map does not know has no id (no picture)", layerButtons[2].layerId == nil)
end

-- the last layer of "In this set" taken out while looking at it: the list must not be empty (no row, no buttons, no way back)
do
    local eSets = IWTextureSets.new({ { name = "DIRT", groundName = "DIRT", textures = { { layer = "dirt01", weight = 50 } } } })
    local eTab = IWTexturesTab.new({ sets = eSets, layerNames = function() return layers end, getActive = function() return 1 end, setActive = function() end, changed = function() end })
    eTab.setIndex, eTab.mode, eTab.group = 1, "layers", "set"
    local only = IWTexturesTab.items(eTab)
    check("(the set's own layers: one row)", #only == 1 and only[1].layer == "dirt01")
    find(IWTexturesTab.buttons(eTab, only[1]), "Add / remove").callback()
    local after = IWTexturesTab.items(eTab)
    check("the last layer taken out: the list falls back to the types instead of going empty", eTab.mode == "groups" and #after >= 1 and after[1].kind == "group" and #IWTexturesTab.buttons(eTab, after[1]) > 0)
    -- nothing at all to show (no layers on the map either): a row with a way back
    local bare = IWTexturesTab.new({ sets = eSets, layerNames = function() return {} end, getActive = function() return 1 end, setActive = function() end, changed = function() end })
    bare.setIndex, bare.mode = 1, "groups"
    local none = IWTexturesTab.items(bare)
    check("a map with no layers and a set with none: one row that says so, with Done", #none == 1 and none[1].kind == "none" and select(1, IWTexturesTab.describeItem(bare, none[1])) == "No layers to show" and IWTexturesTab.buttons(bare, none[1])[1].label == "Done" and IWTexturesTab.color(bare, none[1]) == nil and IWTexturesTab.meter(bare, none[1]) == nil)
    IWTexturesTab.buttons(bare, none[1])[1].callback()
    check("Done takes it back to the sets", bare.mode == "sets")
end

-- the preview of a whole assembly: 8 x 8 cells of layer pictures
do
    local ids = { A = 1, B = 2, C = 3 }
    local vSets = IWTextureSets.new({})
    local mix = vSets:add("Mix")
    vSets:toggle(mix, "A")
    vSets:toggle(mix, "B")
    local vTab = IWTexturesTab.new({ sets = vSets, layerNames = function() return { "A", "B" } end, getActive = function() return 1 end, setActive = function() end, changed = function() end, layerId = function(name) return ids[name] end })
    local row = IWTexturesTab.items(vTab)[mix]
    local pv = IWTexturesTab.preview(vTab, row)
    check("a set row in the sets list has a 8 x 8 preview of layer ids", pv ~= nil and pv.cols == 8 and pv.rows == 8 and #pv.layers == 64)
    local counts = { 0, 0, 0 }
    for _, id in ipairs(pv.layers) do counts[id] = (counts[id] or 0) + 1 end
    check("a mix shows both its layers, each in about half of the cells (equal weights)", counts[1] > 16 and counts[2] > 16 and counts[1] + counts[2] == 64)
    check("the same set always shows the same mosaic (no new roll every frame)", (function() local again = IWTexturesTab.preview(vTab, row); for k = 1, 64 do if again.layers[k] ~= pv.layers[k] then return false end end return true end)())
    vSets:setPreset(mix, "stripes")
    vTab.mode, vTab.setIndex = "pattern", mix
    local stripes = IWTexturesTab.preview(vTab, IWTexturesTab.items(vTab)[1])
    check("a pattern shows its tile twice in each direction (stripes: columns alternate, the tile repeats at 4)", stripes.layers[1] == 1 and stripes.layers[2] == 2 and stripes.layers[5] == 1 and stripes.layers[9] == 1)
    check("in the pattern editor the preview is the set being edited, whichever row", IWTexturesTab.preview(vTab, IWTexturesTab.items(vTab)[3]).layers[2] == 2)
    vSets:clearPattern(mix)
    vSets:cycleBlock(mix)
    vSets:cycleBlock(mix)
    vTab.mode = "sets"
    local patches = IWTexturesTab.preview(vTab, IWTexturesTab.items(vTab)[mix])
    check("a set with patches of 4 shows one cell per patch (it differs from a per-texel mix)", patches ~= nil and #patches.layers == 64)
    check("a layer the map does not know is an empty cell (false)", (function() ids.A = nil; local p2 = IWTexturesTab.preview(vTab, IWTexturesTab.items(vTab)[mix]); for _, v in ipairs(p2.layers) do if v == false then return true end end return false end)())
    vTab.mode, vTab.group, vTab.setIndex = "layers", "dirt", mix
    check("no assembly preview for types and layers (they get the big picture of their own layer)", IWTexturesTab.preview(vTab, { kind = "layer", layer = "A" }) == nil)
    check("the descriptor hands the hub the preview lookup", type(IWTexturesTab.descriptor(vTab, "T", "i").getItemPreview) == "function")
end

-- a double click on a row: its default action
do
    local dSets = IWTextureSets.new({ { name = "DIRT", groundName = "DIRT", textures = { { layer = "DIRT", weight = 90 } } }, { name = "GRAVEL", groundName = "GRAVEL", textures = { { layer = "GRAVEL", weight = 90 } } } })
    local dActive = 1
    local dTab = IWTexturesTab.new({ sets = dSets, layerNames = function() return layers end, getActive = function() return dActive end, setActive = function(i) dActive = i end, changed = function() end })
    local d = IWTexturesTab.descriptor(dTab, "Textures", "i")
    d.onDoubleClick(d.getItems()[2])
    check("a double click on a set opens its editor (Use is a button)", dActive == 1 and dTab.mode == "groups" and dTab.setIndex == 2)
    dTab.mode = "sets"
    dTab.setIndex, dTab.mode = 2, "groups"
    d.onDoubleClick(d.getItems()[2])
    check("a double click on a type opens its weights", dTab.mode == "layers" and dTab.group == "road")
    local first = d.getItems()[1]
    d.onDoubleClick(first)
    check("a double click on a layer puts it in the set (and again takes it out)", IWTextureSets.weightOf(dSets:get(2), first.layer) == 10 and (function() d.onDoubleClick(first); return IWTextureSets.weightOf(dSets:get(2), first.layer) == nil end)())
    dTab.mode = "pattern"
    check("pattern rows have no double click action (nothing breaks)", pcall(d.onDoubleClick, { kind = "empty" }))
end

-- Back goes up one level, the top returns false (the hub closes then)
do
    local bSets = IWTextureSets.new({ { name = "DIRT", groundName = "DIRT", textures = { { layer = "dirt01", weight = 50 } } } })
    local bTab = IWTexturesTab.new({ sets = bSets, layerNames = function() return layers end, getActive = function() return 1 end, setActive = function() end, changed = function() end })
    local desc = IWTexturesTab.descriptor(bTab, "T", "i")
    check("at the top (the sets) Back is not handled: the hub closes", desc.onBack() == false and bTab.mode == "sets")
    bTab.mode, bTab.setIndex, bTab.group = "layers", 1, "dirt"
    check("from the layers Back goes to the types, then the sets, then it is the hub's", desc.onBack() == true and bTab.mode == "groups" and desc.onBack() == true and bTab.mode == "sets" and desc.onBack() == false)
    bTab.mode = "pattern"
    check("from the pattern editor Back goes to the sets", desc.onBack() == true and bTab.mode == "sets")
end

-- details: what driving leaves on the surface
do
    local xSets = IWTextureSets.new({ { name = "DIRT", groundName = "DIRT", textures = { { layer = "dirt01", weight = 50 } } } })
    local xTab = IWTexturesTab.new({ sets = xSets, layerNames = function() return layers end, getActive = function() return 1 end, setActive = function() end, changed = function() end })
    local setRow = IWTexturesTab.items(xTab)[1]
    find(IWTexturesTab.buttons(xTab, setRow), "Details  (0)").callback()
    local none = IWTexturesTab.items(xTab)
    check("Details opens the list of details: empty at first, one row that says how to add one", xTab.mode == "details" and #none == 1 and none[1].kind == "nodetail" and select(1, IWTexturesTab.describeItem(xTab, none[1])) == "No details yet")
    check("the empty row has Add detail, Matching details and Done", #IWTexturesTab.buttons(xTab, none[1]) == 3 and find(IWTexturesTab.buttons(xTab, none[1]), "Matching details: off  (0 found)") and find(IWTexturesTab.buttons(xTab, none[1]), "Add detail") ~= nil)
    find(IWTexturesTab.buttons(xTab, none[1]), "Add detail").callback()
    check("Add detail goes to the types to pick the layer", xTab.mode == "groups" and xTab.pickDetail == true)
    local typeRows = IWTexturesTab.items(xTab)
    local pickButtons = IWTexturesTab.buttons(xTab, typeRows[2])
    check("picking a detail layer: the layers are buttons, no Weights, Done", #pickButtons >= 2 and not find(pickButtons, "Weights") and find(pickButtons, "Done") ~= nil)
    pickButtons[1].callback()
    local details = IWTexturesTab.items(xTab)
    check("a click on a layer adds it as a detail (spot, 0.2%, size 2) and returns to the list", xSets:get(1).details ~= nil and #xSets:get(1).details == 1 and xTab.mode == "details" and xTab.pickDetail == false and details[1].kind == "detail")
    check("a detail row says its layer and what it does", select(2, IWTexturesTab.describeItem(xTab, details[1])) == "spot, 0.2% per texel a tyre wears, size 2" and IWTexturesTab.layerId(xTab, details[1]) == nil)
    local detailButtons = IWTexturesTab.buttons(xTab, details[1])
    check("a detail has Shape, Chance, Size, Remove, Add detail, Matching details and Done", #detailButtons == 7 and find(detailButtons, "Shape: spot") and find(detailButtons, "Chance: 0.2%") and find(detailButtons, "Size: 2") and find(detailButtons, "Remove"))
    find(detailButtons, "Shape: spot").callback()
    find(detailButtons, "Chance: 0.2%").callback()
    find(detailButtons, "Size: 2").callback()
    local d = xSets:get(1).details[1]
    check("the buttons cycle shape, chance and size", d.shape == "crack" and d.chance == 0.5 and d.size == 3)
    find(IWTexturesTab.buttons(xTab, details[1]), "Remove").callback()
    check("Remove takes the detail out, the list is empty again", xSets:get(1).details == nil and IWTexturesTab.items(xTab)[1].kind == "nodetail")
    -- Back from picking goes to the list of details, then to the sets
    find(IWTexturesTab.buttons(xTab, IWTexturesTab.items(xTab)[1]), "Add detail").callback()
    local back = IWTexturesTab.descriptor(xTab, "T", "i").onBack
    check("Back while picking a detail layer returns to the details, then to the sets", back() == true and xTab.mode == "details" and xTab.pickDetail == false and back() == true and xTab.mode == "sets")
    check("a double click on the empty details row opens the picker", (function() xTab.mode, xTab.setIndex = "details", 1; IWTexturesTab.descriptor(xTab, "T", "i").onDoubleClick(IWTexturesTab.items(xTab)[1]); return xTab.mode == "groups" and xTab.pickDetail == true end)())
end

-- Delete: the active set index follows
active = 4
local last = IWTexturesTab.items(tab)[4]
find(IWTexturesTab.buttons(tab, last), "Delete").callback()
check("deleting the active set makes the first one active", sets:count() == 3 and active == 1)
active = 3
find(IWTexturesTab.buttons(tab, IWTexturesTab.items(tab)[3]), "Delete").callback()
check("deleting a set that is not the active one: nothing else changes", sets:count() == 2 and active == 1)
sets:add()
sets:add()
active = 4
find(IWTexturesTab.buttons(tab, IWTexturesTab.items(tab)[3]), "Delete").callback()
check("deleting a set before the active one moves the active index with it", active == 3 and sets:count() == 3)

-- registration
local registered, removed = {}, {}
local waila = { registerDebugTab = function(d) registered[#registered + 1] = d end, unregisterDebugTab = function(id) removed[#removed + 1] = id end }
check("registered with its own id, the old one removed first; no WAILA: false", IWTexturesTab.register(waila, tab, "Textures", "icon.dds") and removed[1] == IWTexturesTab.ID and #registered == 1 and IWTexturesTab.register(nil, tab, "Textures", "i") == false)
local d = registered[1]
check("the descriptor has rows, texts, chip, meter and the row's buttons", #d.getItems() == 3 and type(d.describeItem) == "function" and type(d.getItemColor) == "function" and type(d.getItemMeter) == "function" and #d.getButtons(d.getItems()[1]) >= 5)
-- the damage variants stay out of the type lists
do
    local vSets = IWTextureSets.new({ { name = "DIRT", groundName = "DIRT", textures = { { layer = "DIRT", weight = 100 } } } })
    local vLayers = { "COBBLESTONE03", "COBBLESTONE03_CRACKED1", "COBBLESTONE03_MISSING1", "COBBLESTONE03_WORN", "COBBLESTONE04", "DIRT" }
    local vTab = IWTexturesTab.new({ sets = vSets, layerNames = function() return vLayers end, getActive = function() return 1 end, setActive = function() end, changed = function() end })
    vTab.setIndex = 1
    vTab.mode = "groups"
    local function count()
        local n = 0
        for _, entry in ipairs(IWTexturesTab.groups(vTab)) do
            if entry.group.key ~= "set" then n = n + #entry.layers end
        end
        return n
    end
    check("the type lists show COBBLESTONE03, COBBLESTONE04 and DIRT but not the three variants", count() == 3)
    vTab.pickDetail = true
    check("picking a detail lists them all", count() == 6)
end
-- Add damage on a layer that has variants
do
    local dSets = IWTextureSets.new({ { name = "DIRT", groundName = "DIRT", textures = { { layer = "DIRT", weight = 100 } } } })
    local dLayers = { "COBBLESTONE01", "COBBLESTONE01_CRACKED1", "COBBLESTONE01_MISSING1", "COBBLESTONE01_WORN", "COBBLESTONE01_DAMAGED", "DIRT" }
    local dChanges = 0
    local dTab = IWTexturesTab.new({ sets = dSets, layerNames = function() return dLayers end, getActive = function() return 1 end, setActive = function() end, changed = function() dChanges = dChanges + 1 end })
    dTab.setIndex = 1
    dTab.mode = "layers"
    local cobble = IWTexturesTab.buttons(dTab, { kind = "layer", layer = "COBBLESTONE01" })
    check("a layer with variants offers Add damage (2), the Weight 75 slot is taken, still 11 buttons", #cobble == 11 and find(cobble, "Add damage  (2)") ~= nil and find(cobble, "Weight 75") == nil and find(cobble, "Weight 100") ~= nil and find(cobble, "Weight 50") ~= nil and find(cobble, "Done") ~= nil)
    check("... right below Add / remove", cobble[1].label == "Add / remove" and cobble[2].label == "Add damage  (2)")
    find(cobble, "Add damage  (2)").callback()
    check("pressing it adds the variants as details of the set", #dSets:get(1).details == 2 and dChanges == 1)
    cobble = IWTexturesTab.buttons(dTab, { kind = "layer", layer = "COBBLESTONE01" })
    check("then it says Remove damage", find(cobble, "Remove damage") ~= nil and find(cobble, "Add damage  (2)") == nil)
    find(cobble, "Remove damage").callback()
    check("... which takes them out again", dSets:get(1).details == nil and dChanges == 2)
    local plain = IWTexturesTab.buttons(dTab, { kind = "layer", layer = "DIRT" })
    check("a layer without variants keeps its six weights and has no damage button", #plain == 11 and find(plain, "Weight 75") ~= nil and find(plain, "Add damage") == nil and find(plain, "Remove damage") == nil)
end
-- Matching details on: the Details screen lists what the tick brings
do
    local mSets = IWTextureSets.new({ { name = "DIRT", groundName = "DIRT", textures = { { layer = "COBBLESTONE01", weight = 100 } } } })
    local mLayers = { "COBBLESTONE01", "COBBLESTONE01_CRACKED1", "COBBLESTONE01_MISSING1", "COBBLESTONE01_DAMAGED", "DIRT" }
    local mChanges = 0
    local mTab = IWTexturesTab.new({ sets = mSets, layerNames = function() return mLayers end, getActive = function() return 1 end, setActive = function() end, changed = function() mChanges = mChanges + 1 end, layerId = function(name) return name == "COBBLESTONE01_CRACKED1" and 42 or nil end })
    mTab.setIndex = 1
    mTab.mode = "details"
    local items = IWTexturesTab.items(mTab)
    check("tick off: the empty row, as before", #items == 1 and items[1].kind == "nodetail" and select(1, IWTexturesTab.describeItem(mTab, items[1])) == "No details yet")
    mSets:toggleMatchDetails(1)
    items = IWTexturesTab.items(mTab)
    check("tick on: one row per matching detail (cracked1, missing1, and the _DAMAGED mix), no empty row", #items == 3 and items[1].kind == "matched" and items[1].detail.layer == "COBBLESTONE01_CRACKED1" and items[2].detail.layer == "COBBLESTONE01_MISSING1")
    local title, text = IWTexturesTab.describeItem(mTab, items[1])
    check("a row says it comes from the tick, with its shape, chance and size", title == "COBBLESTONE01_CRACKED1" and text == "from Matching details: crack, 1% per texel, size 2")
    check("... has the layer's colour and picture, no meter", IWTexturesTab.color(mTab, items[1]) ~= nil and IWTexturesTab.layerId(mTab, items[1]) == 42 and IWTexturesTab.meter(mTab, items[1]) == nil)
    local buttons = IWTexturesTab.buttons(mTab, items[1])
    check("its buttons: tune it, Add detail, Matching details, Done", #buttons == 4 and buttons[1].label == "Tune it (make it a detail)" and find(buttons, "Add detail") ~= nil and find(buttons, "Matching details: on  (3 found)") ~= nil and find(buttons, "Done") ~= nil)
    buttons[1].callback()
    check("tuning it makes it a detail of the set's own (the same shape, chance, size) and the tick skips it", #mSets:get(1).details == 1 and mSets:get(1).details[1].layer == "COBBLESTONE01_CRACKED1" and mSets:get(1).details[1].shape == "crack" and mSets:get(1).details[1].chance == 1 and mChanges == 1)
    items = IWTexturesTab.items(mTab)
    check("the list is then one own detail and two matching ones", #items == 3 and items[1].kind == "detail" and items[2].kind == "matched" and items[3].kind == "matched")
    local bare = IWTextureSets.new({ { name = "DIRT", groundName = "DIRT", textures = { { layer = "DIRT", weight = 100 } } } })
    bare:toggleMatchDetails(1)
    local bTab = IWTexturesTab.new({ sets = bare, layerNames = function() return mLayers end, getActive = function() return 1 end, setActive = function() end, changed = function() end })
    bTab.setIndex = 1; bTab.mode = "details"
    local bItems = IWTexturesTab.items(bTab)
    check("tick on but no layer of the set has variants: the empty row says so", #bItems == 1 and bItems[1].kind == "nodetail" and select(2, IWTexturesTab.describeItem(bTab, bItems[1])):find("no layer of this set has damage variants", 1, true) ~= nil)
end
print(string.format("iwtexturestab_test: %d/%d passed", passed, passed + failed))
os.exit(failed == 0 and 0 or 1)
