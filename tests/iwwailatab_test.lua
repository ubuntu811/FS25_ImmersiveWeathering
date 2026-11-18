-- plain Lua: IW's settings as a WAILA hub tab (IWWailaTab)
local passed, failed = 0, 0
local function check(name, ok) if ok then passed = passed + 1 else failed = failed + 1; print("  FAIL " .. name) end end
dofile("scripts/IWWailaTab.lua")
local saves = 0
local config = { tyreWitherLevelIndex = 2, tyreEffectsEnabled = true, sweepIntervalIndex = 3, save = function() saves = saves + 1 end }
local changed = {}
local options = {
    { key = "tyreEffectsEnabled", label = "Tyre effects", boolean = true },
    { key = "tyreWitherLevelIndex", label = "Tyre withering chance", texts = { "0%", "20%", "40%", "60%", "80%", "100%" }, onChange = function(i) changed[#changed + 1] = i end },
    { key = "sweepIntervalIndex", label = "Weathering pace", texts = { "Once per game day", "Every 10 minutes", "Every 5 minutes", "Every 2 minutes" } },
}
local tab = IWWailaTab.new(config, options)
local items = IWWailaTab.items(tab)
check("one row per setting, in order", #items == 3 and items[2].option.key == "tyreWitherLevelIndex")
local primary, secondary = IWWailaTab.describeItem(tab, items[2])
check("a row shows the label and the current value, nothing more (the buttons and the meter show where it sits)", primary == "Tyre withering chance" and secondary == "20%")
check("a boolean reads On / Off", select(2, IWWailaTab.describeItem(tab, items[1])):find("On", 1, true) ~= nil)
check("next steps the index, saves, and tells the setting", IWWailaTab.step(tab, options[2], 1) == 3 and config.tyreWitherLevelIndex == 3 and saves == 1 and changed[1] == 3)
check("previous steps back", IWWailaTab.step(tab, options[2], -1) == 2 and config.tyreWitherLevelIndex == 2)
config.tyreWitherLevelIndex = 6
IWWailaTab.step(tab, options[2], 1)
check("next at the end wraps to the first", config.tyreWitherLevelIndex == 1)
IWWailaTab.step(tab, options[2], -1)
check("previous at the start wraps to the last", config.tyreWitherLevelIndex == 6)
IWWailaTab.step(tab, options[1], 1)
check("a boolean flips", config.tyreEffectsEnabled == false)
IWWailaTab.step(tab, options[1], -1)
check("... and back", config.tyreEffectsEnabled == true)

-- the meter: where the value sits in its list; the colour field: only where an option has one
options[3].color = function(i) return i == 1 and 0.1 or 0.5, 0.2, 0.3 end
config.tyreWitherLevelIndex, config.sweepIntervalIndex, config.tyreEffectsEnabled = 1, 4, true
local m1 = IWWailaTab.meter(tab, options[2])
check("the first value of a list is an empty meter, the last a full one", m1 == 0 and IWWailaTab.meter(tab, options[3]) == 1)
config.tyreWitherLevelIndex = 4
check("a value in between sits in between (4 of 6 is 3/5)", math.abs(IWWailaTab.meter(tab, options[2]) - 0.6) < 1e-9)
local full, dimOn = IWWailaTab.meter(tab, options[1])
config.tyreEffectsEnabled = false
local empty, dimOff = IWWailaTab.meter(tab, options[1])
check("a switch is a full meter when on and a dim empty one when off", full == 1 and dimOn == false and empty == 0 and dimOff == true)
config.tyreEffectsEnabled = true
check("an option without a colour has no colour field", IWWailaTab.color(tab, options[2]) == nil)
config.sweepIntervalIndex = 1
local r, g, b = IWWailaTab.color(tab, options[3])
check("an option with one gives it for its current value", r == 0.1 and g == 0.2 and b == 0.3)
config.sweepIntervalIndex = 3

-- the descriptor and its registration with WAILA
local registered, removed = {}, {}
local waila = { registerDebugTab = function(d) registered[#registered + 1] = d end, unregisterDebugTab = function(id) removed[#removed + 1] = id end }
check("no WAILA: nothing registered, false", IWWailaTab.register(nil, tab, "Weathering", "icon.dds") == false)
check("WAILA there: registered once, its own id removed first (the tab list outlives a mission)", IWWailaTab.register(waila, tab, "Weathering", "icon.dds") == true and #registered == 1 and removed[1] == IWWailaTab.ID)
local d = registered[1]
check("the descriptor has what the hub needs: id, label, icon, rows, texts, scroll, meter, colour, the row's own buttons", type(d.getItemMeter) == "function" and type(d.getItemColor) == "function" and type(d.getButtons) == "function" and d.id == IWWailaTab.ID and d.label == "Weathering" and d.icon == "icon.dds" and #d.getItems() == 3 and d.describeItem(d.getItems()[1]) == "Tyre effects")
local row = d.getItems()[3]
local list = d.getButtons(row)
check("a row lists all its values as buttons, the current one marked", #list == 4 and list[3].label == "> Every 5 minutes" and list[1].label == "Once per game day" and list[4].instant == true)
list[4].callback(row)
check("clicking a value sets it at once", config.sweepIntervalIndex == 4)
check("... and the marker moves with it", d.getButtons(row)[4].label == "> Every 2 minutes" and d.getButtons(row)[3].label == "Every 5 minutes")
local switchList = d.getButtons(d.getItems()[1])
check("a switch lists Off and On", #switchList == 2 and switchList[1].label == "Off" and switchList[2].label == "> On")
switchList[1].callback(d.getItems()[1])
check("clicking Off turns it off", config.tyreEffectsEnabled == false)
config.tyreEffectsEnabled = true
d.onScroll(row, -1)
check("the wheel (down) still steps back", config.sweepIntervalIndex == 3)
-- more values than slots: a window round the current one (twelve values, eleven slots)
local long = { key = "k", label = "Long", texts = {} }
for i = 1, 14 do long.texts[i] = "v" .. i end
local longConfig = { k = 1 }
local longTab = IWWailaTab.new(longConfig, { long })
check("fourteen values, eleven slots: the window starts at the first when the first is current", #IWWailaTab.buttons(longTab, long) == 11 and IWWailaTab.buttons(longTab, long)[1].label == "> v1")
longConfig.k = 8
local windowed = IWWailaTab.buttons(longTab, long)
check("... and follows the current value (eleven round 8: v4 to v14)", windowed[1].label == "v4" and windowed[11].label == "v14" and windowed[5].label == "> v8")
longConfig.k = 14
check("... the last window ends at the last value", IWWailaTab.buttons(longTab, long)[11].label == "> v14" and IWWailaTab.buttons(longTab, long)[1].label == "v4")
windowed[1].callback()
check("a windowed button sets its own value (v4)", longConfig.k == 4)
-- eleven values fit exactly (the 10% steps)
local steps = { key = "s", label = "Steps", texts = { "0%", "10%", "20%", "30%", "40%", "50%", "60%", "70%", "80%", "90%", "100%" } }
local stepsTab = IWWailaTab.new({ s = 6 }, { steps })
local stepButtons = IWWailaTab.buttons(stepsTab, steps)
check("the 11 steps of 10% are all there, none cut off, the current one marked", #stepButtons == 11 and stepButtons[1].label == "0%" and stepButtons[6].label == "> 50%" and stepButtons[11].label == "100%")
-- the texture picture of a row
options[3].layerId = function(i) return 100 + i end
config.sweepIntervalIndex = 2
check("an option with a layer lookup gives the picture of its current value, one without gives none", IWWailaTab.layerId(tab, options[3]) == 102 and IWWailaTab.layerId(tab, options[2]) == nil and type(d.getItemLayer) == "function")
options[3].layerId = nil
-- a double click steps the setting to the next value
check("a double click on a row steps it to the next value (and wraps)", (function() config.sweepIntervalIndex = 3; d.onDoubleClick(d.getItems()[3]); local a = config.sweepIntervalIndex == 4; d.onDoubleClick(d.getItems()[3]); return a and config.sweepIntervalIndex == 1 end)())
print(string.format("iwwailatab_test: %d/%d passed", passed, passed + failed))
os.exit(failed == 0 and 0 or 1)
