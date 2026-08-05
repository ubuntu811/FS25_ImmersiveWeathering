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
instead just drive a seeder (turned on and lowered, as you would on a field)
over the meadow. (Hand tool is supported too).
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
Also, only ground that already reads as dirt, gravel, sand, or grass is
touched at all - a fixed allowlist in the Lua
(`WEATHERABLE_MATERIALS`/`GRASS_MATERIAL_ONLY`/`TERRAIN_REGROWTH_TARGETS`
in `scripts/ImmersiveWeathering.lua`), not something `iw.xml` extends.
So e.g. concrete reads as its own separate material and is never touched,
no matter what `iw.xml` declares - `iw.xml` only customizes *what*
happens on ground IW already recognizes, it can't add new material types
to touch.
Anything underneath map objects (buildings, roads etc) will not be touched either. 

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
| Nightly sweep sample count | How many points the nightly weathering sweep samples - higher covers more ground per sweep but costs more per run | 1000/2000/4000/6000/8000/10000 |
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
in-order steps for adapting `map.xml` and writing an `iw.xml`, plus the
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
