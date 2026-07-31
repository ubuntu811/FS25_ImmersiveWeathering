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
- **Displace**: off-field deco bushes have a separate chance to get
  flattened into short grass.
- Ground already converted to dirt/gravel is kept free of regrowing
  foliage automatically, no roll needed.

Effects are scaled down per vehicle by wheel count, so a 6-wheeled
combine doesn't wear ground 6x faster than a 2-wheeled ATV at the same
dial setting. AI-driven vehicles are unconditionally excluded - player
driving only, by design.

**Nightly weathering loops** - a periodic sweep samples random points
across gravel/dirt areas and lets weeds/grass creep back in over time,
independent of whether anyone's driven there.

## Controls

All defaults below - Shift+letter combos can be rebound like any other
action via the in-game controls menu; the HUD always shows your actual
current binding, not the default.

| Key | Action |
|---|---|
| `Left Shift + T` | Toggle tyre weathering on/off |
| `Left Shift + B` | Cycle tyre withering chance (0-100%, 20% steps) |
| `Left Shift + V` | Toggle tyre withering material bias (dirt-leaning / gravel-leaning) |
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

## License

GPLv3 - see [LICENSE](LICENSE).
