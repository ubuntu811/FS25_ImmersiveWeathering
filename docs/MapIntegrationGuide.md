# Adapting a map for FS25_ImmersiveWeathering

How to make a map's `map.xml` and its optional `iw.xml` actually work with
this mod - the practical, do-this-in-order guide. For the underlying engine
mechanics ("why does meadow need two declarations", "why does state 0 read
back empty") see WAILA's
[docs/engine-api/FoliageDensityMap.md](https://github.com/ubuntu811/FS25_whatAmILookingAt/blob/main/docs/engine-api/FoliageDensityMap.md)
and
[TerrainAttributes.md](https://github.com/ubuntu811/FS25_whatAmILookingAt/blob/main/docs/engine-api/TerrainAttributes.md)/
[TerrainDeformation.md](https://github.com/ubuntu811/FS25_whatAmILookingAt/blob/main/docs/engine-api/TerrainDeformation.md) -
this guide is the "how", those are the "why".

IW works on any map with **zero** map-author effort - it falls back to a
single hardcoded `grassShort` foliage entry and a hardcoded 90/10 dirt/gravel
texture split. Everything below is for a map author who wants real, varied
foliage/ground behavior instead of that default.

## 0. Nothing to configure yet? Just install it

If you're not writing an `iw.xml`, skip straight to playing - IW already
works. The rest of this guide is for maps that want their own palette.

## 1. `map.xml` requirements (foliage)

For each foliage layer you want IW to place (e.g. `meadow`, `decoBush`),
`map.xml` needs **both**:

```xml
<decoFoliages>
    <decoFoliage layerName="meadow" startChannel="0" numChannels="4" mowable="true"/>
</decoFoliages>

<mapping name="meadow_s0" layerName="meadow" state="0" />
<mapping name="meadow_s1" layerName="meadow" state="1" />
<!-- ... one <mapping> per state you want writable, up to numChannels' real range -->
```

Missing either one breaks writes silently - no error, the write just does
nothing. Specifically:

- **`<mapping>` alone, no `<decoFoliage>` sibling**: this is what blocked
  `meadow` for an entire session - it had real I3D backing and a
  `<paintableFoliage>` declaration, but no `<decoFoliage>` one.
  `getIsDecoLayerDefined`/`applyDecoFoliage` need the `<decoFoliage>`
  registration specifically.
- **Declared `numChannels` lower than the layer's real state count**: writes
  to higher states silently clamp instead of erroring. Don't assume
  `numChannels="4"` (states 0-15) means all 16 states have real content -
  check the real per-type descriptor (see step 2).
- **State 0 is permanently unreadable** - `decodeFoliageBitsAt`'s own
  `value <= 0` check means anything written to state 0 reads back
  identical to "nothing here". Never use `stageMin="0"` in `iw.xml`.

**Verify all of this automatically** instead of hand-checking:

```bash
python3 /path/to/FS25_whatAmILookingAt/docs/engine-api/check_foliage_sync.py /path/to/YourMap/maps/map.xml
# add --game-install "/path/to/Farming Simulator 25" to also verify layers
# backed by base-game shared assets (most fruit types, decoFoliage, etc.)
```

Wire it into the map's own `build.sh` as a non-blocking check (`|| true`) -
see this map's own build.sh for the real, working example.

## 2. Finding real layer names and state counts

Don't guess. Both of these are the actual confirmed source of truth, not
`numChannels` (which only bounds the theoretical range, not real content):

- **Foliage state count**: read the real per-type descriptor XML (e.g.
  `decoFoliageUS.xml`, `decoBushEU.xml` under the game install's
  `data/foliage/...`) and count `<foliageState>` children - that's the real,
  0-indexed content count, independent of `numChannels`.
- **Terrain layer names** (for `groundMapping`, step 4): WAILA's debug menu
  (`Shift+L` → "Dump terrain layers") lists every real layer name this
  specific map declares, straight from `getTerrainLayerName` - not guessed,
  not assumed shared across maps.

## 3. `iw.xml` - foliage palette

Optional file, sibling to the map's own `map.xml`. Full field-by-field
schema is documented in the file's own header comment (kept there, not
duplicated here, so there's one source of truth) - see this map's
[maps/iw.xml](https://github.com/ubuntu811/FS25_Estancia_Lapacho_orange/blob/master/maps/iw.xml)
for a complete real example with `<foliageMapping>`, including a
specific-state override (`state="N"`) and cross-entry `mutatesTo` chains.

Quick shape:

```xml
<iwConfig>
    <foliageMapping>
        <entry name="meadow" chance="80" stageMin="1" stageMax="4"
               clusters="true" mutateChance="2" seeder="true" seederLevel="0">
            <mutatesTo name="decoBush" />
        </entry>
    </foliageMapping>
</iwConfig>
```

## 4. `iw.xml` - ground texture palette

Same file, separate `<groundMapping>` section - what ground *texture* wither
paints (not foliage), and what it can mutate into. Also fully documented in
`iw.xml`'s own header. Quick shape:

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
</groundMapping>
```

`entry name` here must be `"dirt"`/`"gravel"` specifically - those are the
two fixed options the player's Settings-page toggle offers; entries reached
only via `mutatesTo` (like `mud` above) can be named anything.

## 5. Test before trusting it

1. `check_foliage_sync.py` (step 1) - catches the three real bug categories
   it's designed for, in seconds, before you ever load the game.
2. In-game: WAILA's `Shift+L` debug menu has the tools that actually built
   this palette - "Paint layer test row" to sanity-check specific texture
   layer names paint correctly, "Dump density probe"/"Dump ground layer
   dataPlane probe" if chasing a read-side question.
3. IW's own debug menu (`Shift+Ctrl+M`) has "Fill area" for a manual foliage
   test stamp.
4. Point WAILA at the result and read `log.txt` - `Shift+J` dumps the full
   inspected target, real field names and values, not assumed ones.

## Known limits (don't design around these being fixable)

- **No way to read back which specific ground texture layer is painted at a
  position** - only the coarse `materialId` bucket (`DIRT`/`GRASS`/`GRAVEL`/
  etc, ~5 values total). Confirmed exhaustively, not just untried - see
  TerrainAttributes.md. A feature that needs "is this spot specifically X
  texture" has to track it itself; the engine won't hand it back.
- **Weather conditions** (`condition="isRaining"` in `groundMapping`) - only
  `isRaining` exists right now, the real base-game formula (see
  [Weather.md](https://github.com/ubuntu811/FS25_whatAmILookingAt/blob/main/docs/engine-api/Weather.md)).
  Unrecognized condition names always fail closed (never fire).
