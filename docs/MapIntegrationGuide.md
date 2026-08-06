# Adapting a map for FS25_ImmersiveWeathering

IW works on any map with **zero** map-author effort - it falls back to a
single hardcoded `grassShort` foliage entry and a hardcoded 90/10 dirt/gravel
texture split. This guide is for a map author who wants real, varied
foliage/ground behavior instead of that default.

It's two files:

- **`map.xml`** (your map already has this) - declares which foliage layers
  exist and which of their states are writable at all. IW can only ever
  touch what's declared here.
- **`iw.xml`** (optional, sibling file you add) - tells IW *what to do* with
  what `map.xml` made available: which layers/states to pick from, how
  likely, whether they grow/spread/mutate, and what ground texture to paint
  underneath.

If you just want the engine-internals "why" behind any rule below (density
map bit-packing, terrain layer natives, etc.), that all lives in WAILA's
[docs/engine-api/](https://github.com/ubuntu811/FS25_whatAmILookingAt/tree/main/docs/engine-api) -
this guide only states the rule and what to do about it.

## 0. Nothing to configure yet? Just install it

If you're not writing an `iw.xml`, skip straight to playing - IW already
works. The rest of this guide is for maps that want their own palette.

## 1. `map.xml`: declare what's writable

For each foliage layer you want IW to place (e.g. `meadow`, `decoBush`),
`map.xml` needs both a `<decoFoliage>` and one `<mapping>` per usable state,
**nested inside `<decoFoliages>`**:

```xml
<decoFoliages>
    <decoFoliage layerName="meadow" startChannel="0" numChannels="4" mowable="true"/>

    <mapping name="meadow_s0" layerName="meadow" state="0" />
    <mapping name="meadow_s1" layerName="meadow" state="1" />
    <!-- ... one <mapping> per state you want writable -->
</decoFoliages>
```

Two rules, both real bugs hit building this. Don't hand-check either one -
run the script we built for exactly this:

```bash
python3 /path/to/FS25_whatAmILookingAt/docs/engine-api/check_foliage_sync.py /path/to/YourMap/maps/map.xml --game-install "/path/to/Farming Simulator 25"
```

| Rule | If you skip it |
|---|---|
| Both `<decoFoliage>` **and** `<mapping>` per state are required | `<mapping>` alone silently does nothing - no error, write just fails |
| Declared `numChannels` must match the layer's real state count | Writes past the real count silently clamp instead of erroring |

The script checks both and tells you plainly (`[NO DECOFOLIAGE SIBLING]`,
`[NUMCHANNELS MISMATCH]`, `[OK]`) - you don't need to know *why* those
values matter, just fix what it flags.

Wire it into the map's own `build.sh` as a non-blocking check (`|| true`) -
see this map's own `build.sh` for the real, working example.

**Finding real terrain layer names** (for `groundMapping`, step 3): WAILA's
debug menu (`Shift+L` → "Dump terrain layers") prints every real layer name
this map declares - to `log.txt`, not on screen - don't guess or assume
shared across maps.

## 2. `iw.xml`: foliage palette

Sibling file to `map.xml`. `<foliageMapping>` picks which declared layer/
state gets placed, how often, and what it does over time.

`grassShort` is IW's own built-in universal fallback - it's what runs with
zero `iw.xml` at all (step 0), and it's still there once you add one: your
entries never have to add up to 100, whatever's left over just falls back
to it. Nothing to declare for it yourself.

```xml
<iwConfig>
    <foliageMapping>
        <!-- meadow: chance=80 (weighted pick on bare ground), grows
             through states 1-4, can spread to a neighbor (clusters), and
             on 2% of repeat hits converts entirely to decoBush instead of
             growing. Real seeder implements sow this at state 0. -->
        <entry name="meadow" chance="80" stageMin="1" stageMax="4"
               clusters="true" mutateChance="2" seeder="true" seederLevel="0">
            <mutatesTo name="decoBush" />
        </entry>
    </foliageMapping>
</iwConfig>
```

For a complete real example (including a specific-state override and
cross-entry `mutatesTo` chains), see `maps/iw.xml` in the
`FS25_Estancia_Lapacho_orange` map repo this palette was built against
(local dev repo, not published anywhere yet).

Field-by-field:

| Field | Meaning |
|---|---|
| `name` | Must match a `<decoFoliage layerName="X">` from `map.xml` (step 1) - IW appends `_s<stage>` itself to reach each `<mapping name="X_s<stage>">` |
| `chance` | Relative weight for fresh placement on bare ground (weights don't need to sum to 100 - the remainder falls back to `grassShort`, see above) |
| `stageMin` / `stageMax` | Confirmed-real valid state range. **Never `0`** - state 0 writes are indistinguishable from empty on read-back, so IW would re-seed the same spot forever |
| `sequential` | `true`/absent: ordered growth progression - a sweep hitting `meadow_s0` grows it to `meadow_s1`, `s2`, up to `stageMax`. `false`: states are unrelated variants with no logical order (e.g. `decoFoliage_s7` is just one flower species/model among many) - picked randomly once on fresh placement, then **never changes again** on repeat hits (a poppy patch stays a poppy forever; the only way it changes at all is a deliberate `mutateChance` hit) |
| `clusters` | `true`: a hit can also spread to a neighboring position |
| `grow` | Only meaningful when `sequential` is `true`/absent - dead, silently ignored on a `sequential="false"` entry, which already never advances regardless. `false`: an established sequential patch never advances on repeat hits. Default `true` |
| `mutateChance` | Separate roll for an established patch to convert to a `<mutatesTo>` target instead of growing. Absent/0 = never mutates |
| `seeder` | `true`: real seeder vehicles sow this entry instead of the hardcoded `grassShort` default. At most one entry should set this |
| `seederLevel` | Starting stage when sown by a seeder (default `0`) |

`<mutatesTo name="X" />` - child element, only checked when `mutateChance`
rolls a hit: `name` is another `<foliageMapping>` entry to switch this whole
patch to (species, not just stage). This is what puts the occasional
flower or bush into an otherwise plain field of meadow - `meadow`'s own
`mutateChance="2"` gives 2% of its repeat hits a chance to convert wholesale
into `decoBush`/`decoFoliage`/`forestGrass` instead of just growing, so a
uniform meadow patch doesn't stay uniform forever.

Don't take any of the above on faith - confirm live with IW's own debug
menu (`Shift+Ctrl+M` → "Fill area") plus WAILA (`Shift+M` full panel,
`Shift+J` to dump the exact target). Two reasons that's worth doing every
time, not just once:

1. **Proves the `map.xml` wiring is actually correct.** Fill an area and
   look - nothing showing up for a layer you just declared means something
   upstream (step 1) is broken, before you waste time debugging `iw.xml`
   itself.
2. **Tells you what's actually planted where**, right now, on the real map
   - useful any time you want to find "that one specific flower" for a
   `<mutatesTo>` target or a `groundMapping` `<foliage>` reference, instead
   of guessing a name and hoping it's right.

## 3. `iw.xml`: ground texture palette

Same file, separate `<groundMapping>` section - what ground *texture*
wither paints (not foliage), and what it can mutate into (e.g. mud when
raining). `entry name` must be `"dirt"` or `"gravel"` to be reachable from
the player's Dirt-leaning/Gravel-leaning Settings toggle - those are the
only two names that toggle resolves. Any other name is only ever reached
via another entry's `mutatesTo`, or via its own `seeder="true"` flag (not
a reserved name - mirrors `foliageMapping`'s own `seeder` flag exactly):
a real seeder vehicle paints whichever entry is flagged that way
underneath whatever it sows, instead of the hardcoded `"GRASS"` fallback.
Doesn't have to be grass - flagging a `"sand"` entry instead is equally
valid, IW doesn't assume what a seeder paints.

```xml
<groundMapping>
    <entry name="dirt">
        <texture name="DIRT" chance="90" />
        <texture name="GRAVEL" chance="10" />
        <foliage name="meadow" chance="15" />
        <mutatesTo name="mud" chance="20" condition="isRaining" />
    </entry>
    <entry name="mud">
        <texture name="mud01" chance="50" />
        <texture name="mud02" chance="50" />
    </entry>
    <entry name="grass" seeder="true">
        <texture name="grass01" chance="25" />
        <texture name="grass02" chance="25" />
        <texture name="grassDry01" chance="25" />
        <texture name="grassDry02" chance="25" />
    </entry>
</groundMapping>
```

If no entry is flagged `seeder="true"`, the seeder falls back to the
single hardcoded `"GRASS"` layer (today's behavior, zero author effort).

Field-by-field:

| Element | Field | Meaning |
|---|---|---|
| `<entry>` | `seeder` | `true`: a real seeder vehicle paints this entry's textures underneath whatever it sows. At most one entry should set this |
| `<texture>` | `name` | Real terrain layer name (WAILA's `Shift+L` → "Dump terrain layers") |
| `<texture>` | `chance` | Relative weight, weighted pick among this entry's textures |
| `<foliage>` | `name` | An existing `<foliageMapping>` entry - reuses its own stage rules |
| `<foliage>` | `chance` | Independent 0-100 roll, "also seed this" on top of the texture pick |
| `<mutatesTo>` | `name` | Another `groundMapping` entry to switch to entirely, evaluated before the texture pick |
| `<mutatesTo>` | `chance` | Independent 0-100 roll, only reachable if `condition` passes |
| `<mutatesTo>` | `condition` | Optional. Only `"isRaining"` exists today (see [Weather.md](https://github.com/ubuntu811/FS25_whatAmILookingAt/blob/main/docs/engine-api/Weather.md)). Absent = unconditional. Unrecognized names always fail closed |

## 4. `iw.xml`: which crops count as "sowing grass"

Same file, top-level `<seederFruitTypes>` - which real fruit types a real
sowing machine must have loaded for its seeder pass to count at all (paint
the `groundMapping` `seeder="true"` entry, plant the `foliageMapping`
`seeder="true"` entry). A wheat drill loaded with wheat is never treated
as "sowing grass" just because it's active - only a genuine match counts.

```xml
<seederFruitTypes>
    <fruitType name="MEADOW" />
    <fruitType name="GRASS" />
</seederFruitTypes>
```

**Absent entirely** (no `<seederFruitTypes>` element at all) falls back to
the hardcoded `MEADOW`/`GRASS` default - today's behavior, unchanged for
every existing `iw.xml` that predates this. **Present but empty**
(`<seederFruitTypes></seederFruitTypes>`) means no seeder pass ever
counts, a genuine map-author choice, not the same as "not declared."
`name` must be a real fruit type name the game recognizes (`WHEAT`,
`SUNFLOWER`, ... same names used in vehicle/crop XMLs) - an unresolvable
name is logged and skipped, not a hard error.

## 5. Test before trusting it

1. `check_foliage_sync.py` (step 1) - catches the three real bug categories
   it's designed for, in seconds, before you ever load the game.
2. In-game: IW's own debug menu (`Shift+Ctrl+M`) → "Dump iw.xml config
   validity" - one line per `iw.xml` entry, every reference it makes (a
   texture layer name, a foliage layer/state, a cross-entry `mutatesTo`
   target) marked `OK`/`MISSING` against what's actually loaded right now.
   Catches a typo'd layer name or a `mutatesTo` pointing at a name that
   doesn't exist, without hunting for it live. Output goes to `log.txt`,
   same as everything else here.
3. WAILA's `Shift+L` debug menu has the tools that actually built this
   palette - "Paint layer test row" to sanity-check specific texture layer
   names paint correctly, "Dump density probe"/"Dump ground layer dataPlane
   probe" if chasing a read-side question.
4. IW's own debug menu also has "Fill area" for a manual foliage test stamp.
5. Point WAILA at the result and read `log.txt` - `Shift+J` dumps the full
   inspected target, real field names and values, not assumed ones.

## Known limits (don't design around these being fixable)

- **No way to read back which specific ground texture layer is painted at a
  position** - only the coarse `materialId` bucket (`DIRT`/`GRASS`/`GRAVEL`/
  etc, ~5 values total). A feature that needs "is this spot specifically X
  texture" has to track it itself; the engine won't hand it back. Details:
  [TerrainAttributes.md](https://github.com/ubuntu811/FS25_whatAmILookingAt/blob/main/docs/engine-api/TerrainAttributes.md).
- **Weather conditions** - only `isRaining` exists right now. Details:
  [Weather.md](https://github.com/ubuntu811/FS25_whatAmILookingAt/blob/main/docs/engine-api/Weather.md).
