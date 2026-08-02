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
- Ground already converted to dirt/gravel is kept free of regrowing
  foliage automatically, no roll needed.

Effects are scaled down per vehicle by wheel count, so a 6-wheeled
combine doesn't wear ground 6x faster than a 2-wheeled ATV at the same
dial setting. AI-driven vehicles are unconditionally excluded - player
driving only, by design.

**Manual overrides** - two crosshair-aimed tools for fixing a spot on the
spot instead of waiting on dice:
- **Swap dirt/gravel**: reads whatever material is at the crosshair and
  repaints it to the other one, over a small area.
- **Sow grass**: unconditionally repaints an area back to grass and seeds
  short grass on it, regardless of what's currently there (dirt, gravel,
  even a flat texture left behind by an unrelated map-painting tool) -
  the "undo" for an overworn patch, or for cleaning up after something
  else entirely.

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
defined field boundary) is never touched, whether that's tyre effects,
the manual tools, or a seeder sowing grass. Wither and the seeder feature
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
| `Left Shift + B` | Cycle tyre withering chance (0-100%, 20% steps) |
| `Left Shift + V` | Toggle tyre withering material bias (dirt-leaning / gravel-leaning) |
| `Left Shift + G` | Swap dirt/gravel at the crosshair |
| `Left Shift + S` | Sow grass at the crosshair (works on anything, not just dirt/gravel) |
| `Left Shift + H` | Set the nightly-sweep weather target to where you're looking |
| `Left Shift + N` | Run a weathering sweep immediately |
| `Left Shift + I` | Cycle sweep sample count (1000-10000) |

An always-visible HUD (bottom-left area) shows current settings and live
keybinds for all of the above.

## Install

Drop `FS25_ImmersiveWeathering` into your FS25 mods folder like any other
mod. WAILA is optional but recommended - without it, IW's HUD panel
loses its anchor point and falls back to a fixed screen position, and
there's no companion world inspector to pair with the effects.

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

## License

GPLv3 - see [LICENSE](LICENSE).
