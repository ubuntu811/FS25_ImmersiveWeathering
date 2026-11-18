-- plain Lua: the foliage tab of the hub (IWFoliageTab)
local passed, failed = 0, 0
local function check(name, ok) if ok then passed = passed + 1 else failed = failed + 1; print("  FAIL " .. name) end end
dofile("scripts/IWFoliageSets.lua")
dofile("scripts/IWFoliageTab.lua")
local changes, asked = 0, nil
local sets = IWFoliageSets.new({ meadow = { { name = "decoBush", chance = 1 }, { name = "grassShort", chance = 99 } } })
local tab = IWFoliageTab.new({ sets = sets, names = function() return { "wheat_s1", "decoBush", "grassShort", "aster", "sunflower" } end, range = function(name) if name == "decoBush" then return { min = 1, max = 14, sequential = false } elseif name == "sunflower" then return { min = 1, max = 6, sequential = true } end end, changed = function() changes = changes + 1 end, askName = function(default, cb) asked = { default = default, cb = cb } end })
local function button(item, label)
    for _, b in ipairs(IWFoliageTab.buttons(tab, item)) do if b.label == label then return b end end
end

local items = IWFoliageTab.items(tab)
check("the first level lists the three ground sets", #items == 3 and items[1].key == "meadow" and items[2].key == "bare" and items[3].key == "forest")
local title, text = IWFoliageTab.describeItem(tab, items[1])
check("the meadow says what it plants and that it is the map's list", title == "Meadow" and text:find("2 foliage") and text:find("100%%") and text:find("the map's list"))
title, text = IWFoliageTab.describeItem(tab, items[2])
check("an empty set says it plants nothing", text:find("plants nothing") ~= nil)
check("a ground set has no reset, rename or delete button to begin with", button(items[1], "Back to the map's list") == nil and button(items[1], "Rename") == nil and button(items[1], "Delete") == nil)

button(items[2], "Edit").callback()
items = IWFoliageTab.items(tab)
check("editing opens the foliage list, the map's names alphabetically", #items == 5 and items[1].name == "aster" and items[5].name == "wheat_s1")
check("not in the set: the row says so, the meter is dimmed", select(2, IWFoliageTab.describeItem(tab, items[1])):find("not in 'Bare ground'") ~= nil and select(2, IWFoliageTab.meter(tab, items[1])) == true)
button(items[1], "Put in (any plant)").callback()
check("Put in adds it with the default chance and saves", sets:chanceOf("bare", "aster") == 10 and changes == 1)
items = IWFoliageTab.items(tab)
check("what is in the set comes first", items[1].name == "aster")
check("the chance is in the row's text and meter", select(2, IWFoliageTab.describeItem(tab, items[1])):find("at 10%%") ~= nil and IWFoliageTab.meter(tab, items[1]) == 0.1)
button(items[1], "Chance 25%").callback()
button(items[1], "More  (+1)").callback()
button(items[1], "Less  (-1)").callback()
button(items[1], "Less  (-1)").callback()
check("a chance button sets it, More and Less step by one", sets:chanceOf("bare", "aster") == 24)
button(items[2], "Chance 5%").callback()
check("a chance button on a foliage that is not in the set puts it in", sets:chanceOf("bare", "decoBush") == 5)
button(items[1], "Take out").callback()
check("Take out removes it", sets:chanceOf("bare", "aster") == nil)
button({ kind = "foliage", name = "aster" }, "Put in (any plant)").callback()
check("and Put in adds it again", sets:chanceOf("bare", "aster") == 10)
check("Back goes up one level, then closes the hub", IWFoliageTab.back(tab) == true and tab.mode == "sets" and IWFoliageTab.back(tab) == false)

local rows = IWFoliageTab.items(tab)
check("an edited ground set offers the way back to the map's list", button(rows[2], "Back to the map's list") ~= nil)
button(rows[2], "Back to the map's list").callback()
check("which empties the bare set again", #sets:entries("bare") == 0 and not sets:isEdited("bare"))

button(rows[1], "Add").callback()
local mine = tab.key
check("Add makes the player's set and opens it", sets:get(mine) ~= nil and not sets:get(mine).builtin and tab.mode == "list" and #IWFoliageTab.items(tab) == 5)
IWFoliageTab.back(tab)
rows = IWFoliageTab.items(tab)
check("it is a row after the ground sets, with Rename and Delete", #rows == 4 and rows[4].key == mine and button(rows[4], "Rename") ~= nil and button(rows[4], "Delete") ~= nil)
local before = sets:get(mine).name
button(rows[4], "Rename").callback()
asked.cb("Hedge mix")
check("Rename asks for a name and takes it", asked.default == before and sets:get(mine).name == "Hedge mix")
check("the row shows the set's own name and that it paints anywhere", select(1, IWFoliageTab.describeItem(tab, rows[4])) == "Hedge mix" and select(2, IWFoliageTab.describeItem(tab, rows[4])):find("any ground") ~= nil)
button(rows[4], "Duplicate").callback()
check("Duplicate adds a copy", sets:count() == 5)
button(rows[4], "Delete").callback()
check("Delete takes the set out", sets:get(mine) == nil and sets:count() == 4)
check("the chance text has no float noise", IWFoliageTab.chanceText(0.20000000298) == "0.2" and IWFoliageTab.chanceText(5) == "5")
local registered
check("it registers with the hub", IWFoliageTab.register({ registerDebugTab = function(d) registered = d end }, tab, "Seeding", nil) and registered.id == IWFoliageTab.ID and registered.label == "Seeding")
check("and says no when the hub is not there", IWFoliageTab.register(nil, tab, "x", nil) == false)
-- the sub menu: the states of a layer
tab.mode, tab.key = "list", "bare"
local layers = IWFoliageTab.items(tab)
local function layer(name) for _, it in ipairs(layers) do if it.name == name then return it end end end
check("a pool of plants offers to pick plants, a growth ladder to pick a stage", button(layer("decoBush"), "Pick plants") ~= nil and button(layer("sunflower"), "Pick a stage") ~= nil and button(layer("decoBush"), "Pick a stage") == nil)
IWFoliageTab.doubleClick(tab, layer("decoBush"))
local states = IWFoliageTab.items(tab)
check("a double click on a layer opens its states: 14 plants", tab.mode == "states" and tab.layer == "decoBush" and #states == 14 and states[1].state == 1 and states[14].state == 14)
check("a plant is described as one of 14, not in the set yet", select(1, IWFoliageTab.describeItem(tab, states[3])) == "plant 3 of 14" and select(2, IWFoliageTab.describeItem(tab, states[3])):find("not in") ~= nil)
button(states[3], "Put in").callback()
button(states[7], "Put in").callback()
check("Put in adds that plant alone, at the default chance, next to the layer's own entry", sets:chanceOf("bare", "decoBush", 3) == 10 and sets:chanceOf("bare", "decoBush", 7) == 10 and sets:chanceOf("bare", "decoBush") == nil and sets:stateCount("bare", "decoBush") == 2)
button(states[3], "Chance 25%").callback()
button(states[3], "More  (+1)").callback()
check("the chance of a plant is its own", sets:chanceOf("bare", "decoBush", 3) == 26 and sets:chanceOf("bare", "decoBush", 7) == 10)
check("its meter and row text show the chance", IWFoliageTab.meter(tab, states[3]) == 0.26 and select(2, IWFoliageTab.describeItem(tab, states[3])):find("chance 26%%") ~= nil)
button(states[7], "Take out").callback()
check("Take out removes just that plant", sets:chanceOf("bare", "decoBush", 7) == nil and sets:chanceOf("bare", "decoBush", 3) == 26)
check("Back goes from the states to the layers, then to the sets", IWFoliageTab.back(tab) == true and tab.mode == "list" and IWFoliageTab.back(tab) == true and tab.mode == "sets")
tab.mode, tab.key = "list", "bare"
check("the layer row says how many plants are picked", select(2, IWFoliageTab.describeItem(tab, { kind = "foliage", name = "decoBush" })):find("1 particular plant picked") ~= nil)
tab.mode, tab.layer = "states", "sunflower"
local stages = IWFoliageTab.items(tab)
check("a ladder lists its stages, the first is the start and the last is full grown", #stages == 6 and select(1, IWFoliageTab.describeItem(tab, stages[1])):find("the start") ~= nil and select(1, IWFoliageTab.describeItem(tab, stages[6])) == "stage 6 of 6  (full grown)")
button(stages[6], "Put in").callback()
check("one stage can be the set's sunflower", sets:chanceOf("bare", "sunflower", 6) == 10)
local name, state = sets:pick("bare", function() return 0.01 end)
check("a pick hands the state over", name == "decoBush" and state == nil or state ~= nil)
local shown, cleared = nil, false
tab.api.preview = function(name, min, max) shown = { name, min, max } end
tab.api.clearPreview = function() cleared = true end
tab.mode, tab.key = "list", "bare"
button({ kind = "foliage", name = "decoBush" }, "Show all 14 in the world").callback()
check("a layer row can show all its states in the world", shown ~= nil and shown[1] == "decoBush" and shown[2] == 1 and shown[3] == 14)
tab.mode, tab.layer = "states", "decoBush"
button({ kind = "state", state = 2 }, "Clear the preview").callback()
check("and clear them", cleared)
tab.api.stateName = function(name, state) return name == "decoBush" and state == 3 and "Big" or nil end
tab.mode, tab.layer = "states", "decoBush"
local named = IWFoliageTab.items(tab)
check("a state with a real name shows it, the others keep plant N of M", select(1, IWFoliageTab.describeItem(tab, named[3])) == "Big  (plant 3 of 14)" and select(1, IWFoliageTab.describeItem(tab, named[4])) == "plant 4 of 14")
shown = nil
button(named[3], "Show this one in the world").callback()
check("a state row can show just that state", shown ~= nil and shown[1] == "decoBush" and shown[2] == 3 and shown[3] == 3)
button(named[3], "Show all 14 in the world").callback()
check("or all of them", shown[2] == 1 and shown[3] == 14)
tab.api.icon = function(name, state) return name == "decoBush" and (state or 1) == 3 and "$data/x/store_big.dds" or (name == "decoBush" and state == nil and "$data/x/store_first.dds" or nil) end
check("a layer row's picture is the layer's icon, a state row's its own, sets have none", IWFoliageTab.image(tab, { kind = "foliage", name = "decoBush" }) == "$data/x/store_first.dds" and IWFoliageTab.image(tab, { kind = "state", state = 3 }) == "$data/x/store_big.dds" and IWFoliageTab.image(tab, { kind = "state", state = 4 }) == nil and IWFoliageTab.image(tab, { kind = "set", key = "meadow" }) == nil)
check("the tab descriptor hands it to the hub", IWFoliageTab.descriptor(tab, "Foliage sets", "i").getItemImage({ kind = "state", state = 3 }) == "$data/x/store_big.dds")
-- a set with several particular plants of one layer: one row for the layer, not one per entry
local many = IWFoliageSets.new({})
for state = 1, 6 do many:toggle("bare", "decoBush", state) end
local manyTab = IWFoliageTab.new({ sets = many, names = function() return { "decoBush", "aster" } end, range = function() return { min = 1, max = 14, sequential = false } end, changed = function() end })
manyTab.mode, manyTab.key = "list", "bare"
local rows = IWFoliageTab.items(manyTab)
check("six particular plants of one layer are one row, not six", #rows == 2 and rows[1].name == "decoBush" and rows[2].name == "aster")
check("...and that row counts the six", select(2, IWFoliageTab.describeItem(manyTab, rows[1])):find("6 particular plants") ~= nil)
print(string.format("iwfoliagetab_test: %d/%d passed", passed, passed + failed))
os.exit(failed == 0 and 0 or 1)
