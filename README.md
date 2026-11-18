# FS25_ImmersiveWeathering

Ambient vegetation and tyre-weathering mod for Farming Simulator 25. Grass
gradually reclaims neglected gravel/dirt patches overnight, and driving
wears grass down into dirt tracks that stay clear of regrowing foliage -
so paths you actually drive look driven, and ground you leave alone
slowly goes wild.

Pairs with [FS25_whatAmILookingAt](https://github.com/ubuntu811/FS25_whatAmILookingAt)
(soft dependency, not required - see below).

## What it does

**Tyre weathering** - while driving, wheels in contact with the ground can:
- **Wither**: grass-textured ground has a chance to convert to dirt or
  gravel, clearing any standing foliage on it in the same action.
- **Material drift**: ground already dirt/gravel has a chance to re-roll
  toward the currently selected texture bias, so a road doesn't stay
  stuck as whatever it first landed on if you change the bias later.
- **Displace**: off-field deco bushes (not ordinary ground cover) have a
  separate chance to get flattened into short grass.
- Driving back over ground you've already converted to dirt/gravel keeps
  sweeping any regrowth off it automatically - unlike wither/material
  drift/displace above, this isn't a dice roll, it happens on every pass
  over already-converted ground, so paths you actually drive stay looking
  driven.

Effects can be scaled down per vehicle by wheel count, via the "Wheel
count sensitivity" Settings-page dial - at 100%, a 6-wheeled combine
doesn't wear ground 6x faster than a 2-wheeled ATV at the same dial
setting; at 0%, every wheel rolls independently (today's default is
100%, unchanged from before this was configurable). AI-driven vehicles
are unconditionally excluded - player driving only, by design.

**Seeders sow grass on meadows** - this mod is trying to give you the 
most immersive way possible to manage the changes we're doing. So, I'm trying
to avoid forcing you to use the construction menu to undo damaged meadows, 
instead just drive a seeder loaded with grass/pasture seed (turned on and
lowered, as you would on a field) over the meadow - a seeder loaded with
any other crop (wheat, barley, ...) is left alone, it's not treated as
"sow grass" just because it's active. (Hand tool is supported too).
It will repaint dirt/gravel to grass and seed short grass (or what you 
configure in the maps integration xml, see below).
It never touches ground where something's already growing - this only fills
in bare ground, it doesn't overwrite existing bushes or deco.
Works independently of the tyre weathering toggle (`Left Shift + T`) - so
turning that off to protect a patch you just seeded from your own
tractor's front wheels doesn't also disable the seeder. The seeder has
its own on/off already (whether it's actually turned on and lowered).

**Nightly weathering loops** - a periodic sweep samples random points
across gravel/dirt areas and lets weeds/grass creep back in over time,
independent of whether anyone's driven there.
For testing, feel free to call the same function via the hotkey Left Shift + N, see below. 

## Where this operates

Every mechanic here is off-field only - real farmland (anything inside a
defined field boundary) is never touched, whether that's tyre effects or
a seeder sowing grass. Tyre effects or crop destruction there is completely
managed by the in game config, we're not touching that. 
IW acts on what a place LOOKS LIKE (`IWClass`, from WAILA's layers when WAILA is installed: buildings, roads, forest, trails, and field blobs, also the ones dug in with TerraFarm): fresh foliage and its spread go only onto **meadow** (grass ground with none of those above it), and grass grows back **from the sides**: a spot of bare ground (a rut, a trail, a yard) is painted grass with a chance that rises with the share of grass around it, so a rut in a meadow heals and the middle of a parking lot or a dirt field does not. `iwProbe` (console) says what IW reads at the crosshair.
Also, only ground that already reads as dirt, gravel, sand, or grass is
touched at all - a fixed allowlist in the Lua
(`WEATHERABLE_MATERIALS`/`GRASS_MATERIAL_ONLY`/`TERRAIN_REGROWTH_TARGETS`
in `scripts/ImmersiveWeathering.lua`), not something `iw-map.xml` extends.
So e.g. concrete reads as its own separate material and is never touched,
no matter what `iw-map.xml` declares - `iw-map.xml` only customizes *what*
happens on ground IW already recognizes, it can't add new material types
to touch.
Anything underneath buildings will not be touched either. Roads can be rutted: a stone or sand texture set ("Over stone") may paint over WAILA's road ground too (`ImmersiveWeathering.ROADS_EXCLUDED = true` brings the old rule back); a tyre on a road still wipes the foliage standing on it. 

## Controls

All defaults below - Shift+letter combos can be rebound like any other
action via the in-game controls menu; the HUD always shows your actual
current binding, not the default.

| Key | Action |
|---|---|
| `Left Shift + T` | Toggle tyre weathering on/off |
| `Left Shift + H` | Weather what you're looking at - a 5x5m area around the crosshair, immediately |
| `Left Shift + N` | Run a full weathering sweep immediately |
| `Left Shift + Ctrl + M` | Debug tools menu (area fill - not needed for normal play) |

Tyre withering chance, material bias, nightly-sweep sample count, wheel
count sensitivity, and verbose debug logging are all set on the Settings
page (Options > Mod Settings), not a keybind.

An always-visible HUD (bottom-left area) shows current settings and live
keybinds for the actions above.

## Settings

All on the Settings page (Options > Mod Settings), admin-only in
multiplayer:

| Setting | What it does | Options |
|---|---|---|
| Tyre withering chance | How often grass converts to dirt/gravel under tyre contact | 0/20/40/60/80/100% |
| Tyre withering material bias | Which material fresh conversions lean toward | Dirt-leaning / Gravel-leaning |
| Weathering pace | How often a weathering pass runs: once per game day (the old way, which almost never happens when a game day lasts a month or runs at half speed) or in real time every 10 / 5 / 2 minutes, spread over many frames within 0.4 ms each and spread evenly over the whole map (a place you were not at for a while grows in just the same) | Once per game day / 10 / 5 / 2 minutes |
| Nightly sweep sample count | How many points a weathering pass samples - higher covers more ground per sweep but costs more per run | 1000/2000/4000/6000/8000/10000 |
| Wheel count sensitivity | How much extra wheels discount chance per wheel - 0% = every wheel rolls independently (more wheels = more effect overall), 100% = a many-wheeled vehicle wears ground at the same overall rate as a 2-wheeled one | 0/20/40/60/80/100% |
| Verbose debug logging | Logs every tyre material drift/wither/clear event. Off by default - many-wheeled vehicles can fire dozens of these per tick, which costs performance | Off / On |

## Install

Drop `FS25_ImmersiveWeathering` into your FS25 mods folder like any other
mod. WAILA is optional but recommended - without it, IW's HUD panel
loses its anchor point and falls back to a fixed screen position, and
there's no companion world inspector to pair with the effects.

## Map authors: custom foliage/ground palette

IW works with zero setup on any map (a hardcoded fallback). For a map
author who wants real, varied foliage and ground-texture behavior instead
of the default, see
[docs/MapIntegrationGuide.md](docs/MapIntegrationGuide.md) - practical,
in-order steps for adapting `map.xml` and writing an `iw-map.xml`, plus the
real bugs/gotchas hit building this feature.

## Engine API notes

Shared with WAILA - see
[docs/engine-api/](https://github.com/ubuntu811/FS25_whatAmILookingAt/tree/main/docs/engine-api)
in that repo for reverse-engineered notes on FS25 natives used by both
mods (foliage density maps, terrain paint, tree planting, collision
flags, etc.).

## Dev environment / build tooling

Shared with WAILA - see
[docs/AI_DEV_GUIDE.md](https://github.com/ubuntu811/FS25_whatAmILookingAt/blob/main/docs/AI_DEV_GUIDE.md)
in that repo for Windows+Steam+WSL+Claude Code setup, the
`build.sh`/`deploy.sh` pattern, and a running list of real engine gotchas
hit building this mod pair.

## Credits

TerraFarm, FS25_LumberJack, FS25_PowerTools, and FS25_allTheFoliage all
contributed real, working source that answered engine-API questions
`scriptBinding.xml` alone couldn't - see WAILA's
[README credits section](https://github.com/ubuntu811/FS25_whatAmILookingAt#credits)
for the specifics of what came from where.

## License

GPLv3 - see [LICENSE](LICENSE).

## Texture sets and patterns (the Textures tab of WAILA's debug hub)

Tyres (and a roller) repaint the ground under them texel by texel (0.5 m on a 4 km map) with the **active set**. A set is a **weighted mix** of the map's terrain layers (gravel 95, dirt 5: each texel gets its own pick, so the mix is the mix), or a **pattern**: a 4 x 4 tile of texels that repeats over the ground (stripes, bricks, a checker, scattered joints: cobblestones), so the same texel always gets the same layer. Sets are made in the **Textures** tab: Add, then Edit (the map's layers grouped by type: tick the layers of the set, more or less weight in steps of 10 or of 1) and Pattern (a preset to start from, then a cell at a time). Saved per map in `modSettings/FS25_ImmersiveWeathering/textures_<map>.xml`. "Tyre withering chance" is the share of texels a pass paints (0 to 100%, fine at the bottom), the grass on them comes one growth stage down per pass.

The set's **Mix** button sets how coarse that mix is: "per texel" lets every 0.5 m texel pick its layer on its own (a fine speckle); "2 m patches" and the other sizes (1, 2, 4, 8, 16 texels a side) let a block of texels pick together, so the same weights come out as bigger blotches, which a texture that has to stay continuous (cobblestones) needs. A pattern ignores it. The buttons of the Textures and Foliage sets tabs come in groups (the hub leaves a gap between them). `tests/iwtexturestab_test.lua` passes on plain Lua 5.4 now: the patch size text used `tostring` of a float (`1.0 m` outside the game, `1 m` in it), it uses `%g`.

## Add damage, from the layer itself

In the Textures tab a layer that has damage variants in the map (COBBLESTONE01 with its _CRACKED and _MISSING ones, made by the tools) has an **Add damage (N)** button right under Add / remove: its variants become details
of the set (the cracked ones as cracks, the missing stones as spots, 1 percent, 2 texels; tune them in the set's Details screen). It then says **Remove damage**. It takes the slot of the Weight 75 button, which More /
Less cover. The two mixes (_WORN, _DAMAGED) are not details. The set's "Matching details" tick still does the same for every layer of the set at once.


## Debug: what IW thinks the ground is (`iwClass`)

`iwClass` (console; `here` is the default) scans a square around the camera, 384 m each side in 4 m cells (`half <m>` and `cell <m>` change that, at most 256 cells a side), puts every cell through `IWClass.classify` (field, building, road, forest, meadow, bare, other) and draws the result on the **full-screen map** (yellow field, grey building, orange road, dark green forest, light green meadow, brown bare, purple other); `iwClass off` hides it. The same is two rows of WAILA's **Terrain** tab in the debug hub ("IW ground classes on the map": around me, 768 m in 4 m cells; wide, 2 km in 8 m cells; a click while it is shown hides it, the row's text says off / scanning N % / shown). Nothing runs until you ask: the scan classifies for 4 ms a frame and generates the picture once at the end (`scripts/IWClassOverlay.lua`; a density-map overlay of its own, drawn the way WAILA's map layers are; a minimap that another mod patched may not show it). The log gets one line with the class counts and one line per terrain material that fed the decision (`material 2 -> meadow 5100, bare 3`): IW decides meadow / bare / other from the terrain material alone (grass = 2, dirt = 1, sand = 3, gravel = 6, stone = 7 are fixed numbers in `ImmersiveWeathering.lua`), so a map whose grass has another material id shows up there at once. WAILA's layers (roads, forest, buildings, fields) must be scanned for the road / forest / building / field cells to show. Test: `tests/iwclassoverlay_test.lua`.

## Foliage sets: what IW seeds where, and what you paint with

A foliage set is a named list of foliage with a chance in percent each (`scripts/IWFoliageSets.lua`; a roll that lands past the sum plants nothing). Three built-in sets belong to a ground class IW can tell apart (meadow, bare ground, forest floor) and are what fresh seeding draws from on that ground: the map's `iw-map.xml` supplies the default exactly as it does for the texture sets (the meadow set is the `<foliageMapping>` palette, what is left of the 100 % roll is the fallback grass, as before; bare and forest are empty, so a fresh install behaves like the version before), a set the player edits replaces the default, "Back to the map's list" restores it. Fields, roads and buildings are never seeded; spreading of an existing patch is still meadow-only. Your own sets belong to no ground: add, rename, duplicate and delete them in the **Foliage sets** tab of WAILA's debug hub (`scripts/IWFoliageTab.lua`): the sets, then the map's foliage with Put in / Take out, chance presets (1, 5, 10, 25, 50 %) and More / Less (1 %). Only foliage the map's `<foliageMapping>` declares can be listed (the entry carries the growth stages and the write names). Everything is saved per map in `modSettings/FS25_ImmersiveWeathering/foliage_<map>.xml` (`scripts/IWFoliageStore.lua`; a ground set that is not edited stays out of the file and keeps following the map).

### For other mods (Daisychain)

The sets are published as `g_currentMission.immersiveWeatheringFoliage` (a mod's own globals are invisible to the other mods; `g_currentMission` is shared): `list()` gives `{ key, name, builtin }` for every set, `entries(key)` a copy of `{ name, chance }`, `pick(key)` the set's weighted pick resolved through the map's palette to `{ name, writeName, stage, sequential }` (ready for `applyDecoFoliage`; nil when the roll planted nothing). `nil` for the table itself means IW is not loaded. The player's own sets are in it, so a mod that offers "pick a foliage set" shows what the player made in the hub. Test: `tests/iwfoliagesets_test.lua`.

### Plants and stages: the states menu

A foliage layer of the map is one of two things (`sequential` in `iw-map.xml`): a **pool of separate plants** (`decoBush`, `decoFoliageUS`, `decoStones`, `forestPlants` ...: each state is another plant, IW never grows them) or a **growth ladder** (`sunflower`, `carrot`, `wheat` ...: each state is a later stage). In the Foliage sets tab a layer row therefore opens a sub menu (double click, or "Pick plants" / "Pick a stage"): one row per state, each with Put in / Take out and its own chance, so a set can hold "decoBush plants 3, 7 and 12" or "sunflower, stage 6 (full grown)". An entry without a state ("Put in (any plant)" / "(the start)") is the layer's own pick as before: a random plant of the pool, the first stage of a ladder. Entries with a state are saved with it (`state="6"` in `foliage_<map>.xml`), seeding, the construction brush and the published API plant exactly that state.

**Real names:** the states menu shows the names the game's own foliage file gives ("Big  (plant 3 of 14)", "Blueberry Short", "chantarelle mushroom", a crop's "greenSmall"): `scripts/IWFoliageNames.lua` reads the layer's file (`$data/foliage/<layer>/<layer>.xml`, a regional variant under or beside its base layer, `forestPlants/groundFoliage.xml`, the stones layer's `stone/stone.xml`, the map's own `foliage/` folder; the paths are the ones `mapEU.i3d` references) once per layer and takes its `<foliageState name>` entries in order: state N is the Nth. That order is checked against the file's own comment table for `decoBush` only, the others are assumed to follow it; a layer whose file is not found shows "plant N of M" as before. Test: `tests/iwfoliagenames_test.lua`.

**Pictures:** the hub shows the game's own store icon of the selected layer or state (bottom right, in the frame the textures use). The game's Plants tab is made of store items (`data/foliage/**/paintable_*.xml`) that carry brush type `foliage`, the parameters `{ layer, state }` and a finished icon (`store_*.dds`): `IWFoliageNames` reads those from `g_storeManager` once and looks the icon up by layer and state (a layer row shows its lowest state's icon). The regions reuse the same layer and state numbers (decoBush of the base game and of EU): the state's real name picks the icon whose file name matches ("Boxwood Small" -> `store_boxWoodSmall`), else the first. Layers with no store item (stones, forest plants, ground foliage, water plants, crops) show no picture. Needs the hub's `getItemImage(item)` (WAILA). Test: `tests/iwfoliagenames_test.lua`.

**Looking at the models:** "Show all N in the world" (layer row; a state row also has "Show this one in the world") stamps every state of the layer in a row on the ground where you look, left to right, with its number floating above it for 90 s (then the numbers and the plants are wiped by themselves); "Clear the preview" wipes the row (and whatever else stood there: do it on bare ground). `scripts/IWFoliagePreview.lua`, test `tests/iwfoliagepreview_test.lua`.

**Does a placed plant grow?** In IW's hands: a ladder layer (sequential, `grow` not false) that IW finds off a field grows one stage on a sweep visit with the layer's `chance` until its last stage, and a layer with `clusters="true"` also spreads young plants (first stage) next to it. A pool of plants never grows. So a sunflower painted at its last stage stays that stage but can still seed first-stage neighbours that grow up; a freeze per set entry is not built (the map-wide switch is `grow="false"` / `clusters="false"` on the entry in `iw-map.xml`). Whether the base game also advances such layers by itself is not checked.

### Foliage sets in the construction screen: the "IW Foliage" tab

Every set (the three ground ones too) is a tile of the **IW Foliage** tab in the Landscaping category, next to IW Textures (declared in `modDesc.xml` like that one; if the tab is missing the tiles go to the end of the Painting tab). The brush (`scripts/IWFoliageMenu.lua`) derives from the game's foliage brush (cursor, sizes 0.5 to 16 m, circle / square, sound, the land-ownership check) but plants a random mix on any ground: the area is cut into cells of about 1 m (half a metre for the smallest brush), every cell rolls once per stroke (dragging does not thicken what it already crossed), the set's chances decide which foliage lands in the cell, at a jittered spot, or nothing. Primary plants (IW's own stamp, the one seeding uses; free and local, no landscaping event), secondary removes the plants in the brush square. At most 120 stamps per event, the rest of the stroke follows with the next one. Not seen in the game yet. Tests: `tests/iwfoliagesets_test.lua`, `tests/iwfoliagetab_test.lua`, `tests/iwfoliagemenu_test.lua`. (`tests/iwtexturestab_test.lua` already failed at line 175 before the foliage sets.)

## Texture sets in the construction screen: the "IW Textures" tab

The texture sets (a named mix of terrain layers with weights, and their details) are tiles of a tab of their own, **IW Textures**, in the Landscaping category next to Sculpting and Painting, each named after its set and showing the set's main layer. The tab is declared the official way, in `modDesc.xml`: `<constructionCategories><tab categoryName="landscaping" name="iwTextures" title="$l10n_iw_constructionTab_textures"/></constructionCategories>` (read by the game's mod loader in `mods.lua`, added by `StoreManager:loadMapData` after the game's own tabs; no timing tricks, no iconFilename: the store manager resolves it without the mod folder). If the tab is not there the tiles go to the top of the Painting tab instead (a log line says which). The stock paint brush paints one layer over its whole area and the server charges for it, checks the land is yours, clears crops, weeds, stones and decoration and tells the AI; so a tile uses that very event with the set's MAIN layer (cost, ownership, clearing and multiplayer stay the game's), and when the event has been answered the rest of the set is laid over the area texel by texel with IW's own painter, the way a roller lays a set: every texel picks its layer from the set (weights, patch size, pattern), a texel that picks the main layer stays, and the set's details (cracks, missing stones, potholes, their wet twins while it rains) are stamped at their plain chance. Brush size and shape (circle / square) are the stock brush's. At most 600 texels per event (the nearest to the middle). The code is `scripts/IWPaintMenu.lua`; the menu's and the brush's code was read from the decompiled 1.25.1.0 scripts (`~/fs25_resources/dataS_decompiled/1.25.1.0`). Not seen in the game yet.
