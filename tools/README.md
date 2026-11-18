# Damage builder

Makes damaged variants of a terrain layer from the map's own textures (offline, on your PC; the game cannot make layers at runtime).

```
python3 damage_builder.py --maps "<map mod>/maps" --layer cobblestone03 --out <output dir> [--missing 2] [--cracked 3] [--seed 1]
```

Needs `python3` with `numpy`, and ImageMagick (`convert`). Reads `textures/terrain/<Layer>/<Layer>_diffuse|normal|height.dds` of the map, writes per variant a diffuse (DXT5), a normal (DXT1) and a height (BC4), all with mips,
and a PNG preview, to `<out>/<layer>/`:

* `missing`: holes all over the tile, a stone or a few neighbouring stones gone each, the bed (the joints' own colour and grain) shows, sunken. A terrain texture is seen through a patch of a metre or so, so one hole per tile mostly missed it.
* `cracked`: long, continuous stretches of the joints are widened, dark and sunken: cobblestones break between the stones, not through them.

How: the stones are found in the height map (threshold between its low and high values), removed stones are labelled regions; cracks are Dijkstra paths over the joint network that prefer the valleys and wander; the normal
map is rebuilt from the changed height with the signs and strength fitted against the original (least squares), and kept where nothing changed. Deterministic for a seed. The texture tiles: damage stays away from the
edges (holes) or wraps (cracks).

`dds_bc4.py` reads and writes the one channel BC4 height maps (ImageMagick cannot).

## Adding the variants to the map: `add_layers.py`

```
python3 add_layers.py --maps "<map mod>/maps" --i3d mapEU.i3d --layer cobblestone03 --variants <damage_builder output dir>            # dry run: writes <variants>/mapEU.i3d.patched, changes nothing
python3 add_layers.py ... --apply                                                                                                       # copies the textures, blank weight maps, patches the i3d (backup first)
python3 add_layers.py --maps "<map mod>/maps" --i3d mapEU.i3d --restore                                                                 # undoes it
```

Text insertions only into the i3d: a `<File>` per texture and a blank 4096 x 4096 weight map per variant, a `<Layer>` per variant (the base layer's settings), a `<CombinedLayer>` per variant (so each shows in IW's
picker, as COBBLESTONE03_MISSING1 ...) and two mixes of the intact layer with the variants like the engine's own `layers="dirt01;dirt02"`: `_WORN` (three parts intact, one cracked: UNVERIFIED that a repeated name counts as a
bigger share) and `_DAMAGED`. The new layers go after the last `<Layer>` / `<CombinedLayer>`. The map's `*.cache` files are derived data and were left alone: if the game complains, delete them and let it rebuild.
Existing saves: try a copy of the save first. Examples of the result are in `examples/`.

## Several textures at once, and more later

`add_layers.py --layer cobblestone01,cobblestone02,cobblestone04,cobblestone05 --variants <dir>` adds several base layers in one run (the variants of each in `<dir>/<layer>/`, as damage_builder writes them), and also
adds to a map that is already patched: a layer whose variants are already in is skipped, the first backup stays the way back to the original. Run damage_builder once per layer, each into its own output folder (they
share a temp file) and gather the `<layer>` folders under one directory.

damage_builder checks its own work for textures that differ from cobblestone03: if the stones of a texture join into one region at the middle height threshold (cobblestone02, shallow joints) the threshold goes
up until none does, and if the joint network the crack generator finds is tiny (under 8% of the tile) the space between the stones is the network. Textures that worked before are not changed by either.

## Potholes, and their wet twins

`damage_builder.py --potholes 2` makes, besides the cracks and the missing stones, potholes: one hole near the middle of the tile (the textures repeat every unitSize metres, 1.2 in this map, so a pothole can only
be small), the stones nearest to it gone until about 11% of the tile is, an irregular rim, a bowl that deepens to the middle with loose gravel on its floor. Each pothole also gets a **wet twin**
(`NAME_potholeN_wet`): the same hole with water in the bowl (dark, flat, as glossy as the texture can be) and wet mud round it. In the game Immersive Weathering stamps the wet twin instead of the dry
pothole while it rains and for half an hour after (the same rule as its dirt-to-mud mutation); the wet twins are no details of their own and stay out of the mixes and the pickers.
`add_layers.py` on a layer that is already patched adds the new layers and takes the new dry variants into its `_DAMAGED` mix.

### Rain without the twins: the layer's own wetness

The engine has a weather-driven wetness of its own: a global wetness that rain raises, and per layer `porosityAtZeroRoughness` / `porosityAtFullRoughness` (how much rain soaks in; the map's layers all say
0.9 / 1, only the concrete ones 0.9 / 0.25) and `firmnessWet` / `viscosity` (how soft the ground gets for tyre tracks). The pothole layers made by add_layers.py now get `porosity 0.1 / 0.1`, `firmnessWet 0.6`, `viscosity 0.9`
(POTHOLE_ATTRS): they do not soak the rain up, so the engine's own wetness should show them as wet while it rains, whenever they were painted; `add_layers.py --maps ... --i3d mapEU.i3d --wetness` puts the same
attributes on pothole layers that are in the map already. Not seen in the game yet: whether the shine is strong enough, or whether the wet twins (which IW stamps for rain) are still needed.


### The engine reads at most four entries of a combined layer

`NAME_DAMAGED` was first made of the intact layer and every variant: eight entries. In the game only the first four showed (the intact layer and the cracked variants; never the missing stones or the potholes). The map's own combined layers have one or two entries and ROADGRAVEL four, so `add_layers.py` now makes the mix of four: the intact layer and the first cracked, missing-stone and pothole variant (`NAME_DAMAGED`), and rebuilds a mix that is already in the map that way. (An older map file is brought up to date by running add_layers on it again, or by editing the five `layers=` lists by hand.)


### Rain reaction of the variants: one value for all

The engine's rain wetness reads a layer's porosity (how much rain soaks in) and, for tyre tracks, `firmnessWet` / `viscosity`. The potholes were once non-porous (`0.1`), then the missing stones and the cracks got values in between (`0.3`, `0.5`): painted in one mix during rain, some patches looked wet and the neighbours did not. Now every damage variant (cracked, missing stone, pothole and the wet twins) has ONE value, the intact layer's own (`VARIANT_WETNESS`: porosity `0.9 / 1`, firmness 1, viscosity 1, firmnessWet 1), so nothing in a mix reacts differently from what is next to it. The water of a pothole comes from its wet twin, which IW stamps while it rains. `add_layers.py --wetness` puts the value on the variants that are in a map already (only `<layer>_cracked1 / _missing1 / _pothole1(_wet)` names; a base layer like `mudCracked` is not touched). To make the whole mix shinier, change `VARIANT_WETNESS` (and the intact layers if they should match).
