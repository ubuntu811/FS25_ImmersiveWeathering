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

Effects are scaled down per vehicle by wheel count, so a 6-wheeled
combine doesn't wear ground 6x faster than a 2-wheeled ATV at the same
dial setting. AI-driven vehicles are unconditionally excluded - player
driving only, by design.

**Seeders sow grass too** - any vehicle with the sowing-machine
specialization (a real crop seeder, or a hand-pushed one) repaints bare
dirt/gravel to grass and seeds short grass on genuinely empty ground
while it's actually working (confirmed via the seeder's own real
activation state, not just "engine on" or "implement lowered" - neither
turned out to correlate with whether it's actually sowing). Never
touches ground where something's already growing - this only fills in
bare ground, it doesn't overwrite existing bushes or deco.

**Nightly weathering loops** - a periodic sweep samples random points
across gravel/dirt areas and lets weeds/grass creep back in over time,
independent of whether anyone's driven there.

## Where this operates

Every mechanic here is off-field only - real farmland (anything inside a
defined field boundary) is never touched, whether that's tyre effects or
a seeder sowing grass. Wither and the seeder feature
additionally raycast straight down before painting or placing anything,
so ground that happens to still read as grass/dirt/gravel underneath a
road, rail line, or building isn't touched either - only open ground
under open sky.

## Controls

All defaults below - Shift+letter combos can be rebound like any other
action via the in-game controls menu; the HUD always shows your actual
current binding, not the default.

| Key | Action |
|---|---|
| `Left Shift + T` | Toggle tyre weathering on/off |
| `Left Shift + H` | Weather what you're looking at - a 5x5m area around the crosshair, immediately |
| `Left Shift + N` | Run a full weathering sweep immediately |
| `Left Shift + Ctrl + M` | Debug tools menu (test rig, area fill - not needed for normal play) |

Tyre withering chance, material bias, and nightly-sweep sample count are
set on the Settings page (Options > Mod Settings), not a keybind.

An always-visible HUD (bottom-left area) shows current settings and live
keybinds for the actions above.

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
