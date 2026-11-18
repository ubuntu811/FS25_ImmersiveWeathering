-- plain Lua: where a layer's foliage type file is looked for, and the cleaning of the names (IWFoliageNames); the file reading is the engine's
local passed, failed = 0, 0
local function check(name, ok) if ok then passed = passed + 1 else failed = failed + 1; print("  FAIL " .. name) end end
dofile("scripts/IWFoliageNames.lua")
local c = IWFoliageNames.candidates("decoBush", "C:/map/")
local function has(list, path) for _, p in ipairs(list) do if p == path then return true end end return false end
check("a base layer: its own folder in the game data, then the map's folders", c[1] == "$data/foliage/decoBush/decoBush.xml" and has(c, "C:/map/foliage/decoBush/decoBush.xml"))
c = IWFoliageNames.candidates("decoBushEU", "C:/map/")
check("a regional variant lives in a folder of its own under the base layer's, or flat beside it", has(c, "$data/foliage/decoBush/decoBushEU/decoBushEU.xml") and has(c, "$data/foliage/decoBush/decoBushEU.xml") and has(c, "C:/map/foliage/decoBush/decoBushEU.xml"))
check("decoFoliageEU is flat in decoFoliage's folder", has(IWFoliageNames.candidates("decoFoliageEU", nil), "$data/foliage/decoFoliage/decoFoliageEU.xml"))
check("groundFoliage is under forestPlants and decoStones is the game's stone", has(IWFoliageNames.candidates("groundFoliage", nil), "$data/foliage/forestPlants/groundFoliage.xml") and has(IWFoliageNames.candidates("decoStones", nil), "$data/foliage/stone/stone.xml"))
c = IWFoliageNames.candidates("decoFoliageUS", "C:/map/")
check("the map's own foliage folder is searched (decoFoliageUS of the map)", has(c, "C:/map/foliage/decoFoliage/decoFoliageUS.xml"))
check("without a map folder only the game data is searched", (function() for _, p in ipairs(IWFoliageNames.candidates("stone", nil)) do if p:sub(1, 6) ~= "$data/" then return false end end return true end)())
check("names lose stray blanks and empty ones are none", IWFoliageNames.clean("  Blueberry Short ") == "Blueberry Short" and IWFoliageNames.clean("   ") == nil and IWFoliageNames.clean(nil) == nil)
-- the store icons
check("an icon key is the file name without the store_ prefix, extension and punctuation", IWFoliageNames.iconKey("$data/foliage/decoBush/decoBushEU/store_boxWoodSmall.dds") == "boxwoodsmall" and IWFoliageNames.iconKey("Boxwood Small") == "boxwoodsmall")
check("the base of a regional layer", IWFoliageNames.baseOf("decoBushEU") == "decoBush" and IWFoliageNames.baseOf("decoBush") == "decoBush" and IWFoliageNames.baseOf("EU") == "EU")
local index = IWFoliageNames.indexIcons({
    { type = "foliage", parameters = { "decoBush", "1" }, image = "$data/foliage/decoBush/store_decoBush_small.dds" },
    { type = "foliage", parameters = { "decoBush", "1" }, image = "$data/foliage/decoBush/decoBushEU/store_boxWoodSmall.dds" },
    { type = "foliage", parameters = { "decoBush", "2" }, image = "$data/foliage/decoBush/store_decoBush_medium.dds" },
    { type = "placeable", parameters = { "decoBush", "3" }, image = "x.dds" },
    { type = "foliage", parameters = { "decoBush" }, image = "y.dds" },
    { type = "foliage", parameters = { "decoBush", "5" } },
})
check("only foliage items with a layer, a state and an icon are indexed", index.decoBush[1] ~= nil and #index.decoBush[1] == 2 and index.decoBush[2] ~= nil and index.decoBush[3] == nil and index.decoBush[5] == nil)
check("one icon for a state: that one", IWFoliageNames.iconOf(index, "decoBush", 2, nil) == "$data/foliage/decoBush/store_decoBush_medium.dds")
check("two regions: the base layer takes the one in no region's folder, the EU layer the one in its folder", IWFoliageNames.iconOf(index, "decoBush", 1, nil):find("decoBush_small", 1, true) ~= nil and IWFoliageNames.iconOf(index, "decoBush", 1, { [1] = "boxWoodSmall" }, "decoBushEU"):find("boxWoodSmall", 1, true) ~= nil)
check("flat files: the region on the end of the file name, else the state's name picks", IWFoliageNames.iconOf(IWFoliageNames.indexIcons({ { type = "foliage", parameters = { "decoFoliage", "9" }, image = "$data/foliage/decoFoliage/store_decoGrassShortAS.dds" }, { type = "foliage", parameters = { "decoFoliage", "9" }, image = "$data/foliage/decoFoliage/store_decoGrassShortEU.dds" } }), "decoFoliage", 9, nil, "decoFoliageEU"):find("ShortEU", 1, true) ~= nil and IWFoliageNames.iconOf(index, "decoBush", 1, { [1] = "Small" }):find("decoBush_small", 1, true) ~= nil)
check("two regions and no name: the first", IWFoliageNames.iconOf(index, "decoBush", 1, nil):find("decoBush_small", 1, true) ~= nil)
check("a layer without a state: its lowest state with an icon; unknown layers none", IWFoliageNames.iconOf(index, "decoBush", nil, nil):find("decoBush_small", 1, true) ~= nil and IWFoliageNames.iconOf(index, "wheat", nil, nil) == nil and IWFoliageNames.iconOf(index, "decoBush", 9, nil) == nil)
print(string.format("iwfoliagenames_test: %d/%d passed", passed, passed + failed))
os.exit(failed == 0 and 0 or 1)
