#!/usr/bin/env python3
"""
Adds the damaged variants made by damage_builder.py to the map as terrain layers.
  python3 add_layers.py --maps "<map mod>/maps" --i3d mapEU.i3d --layer cobblestone03[,cobblestone01 ...] --variants <damage_builder output dir>          (dry run: writes <variants>/<i3d>.patched, changes nothing)
  python3 add_layers.py ... --apply                                                                                                    (copies the textures, makes the weight maps, patches the i3d; a backup first)
  python3 add_layers.py --maps ... --i3d mapEU.i3d --layer cobblestone03 --variants <dir> --update                                      (after a damage_builder run: replaces the textures of an already patched map, the i3d is not touched)
  python3 add_layers.py --maps ... --i3d mapEU.i3d --restore                                                                           (puts the i3d back, removes what was added)
What is added to the i3d (text insertions only, the rest of the file is left byte for byte):
  <File> entries (diffuse, normal, height, an empty weight map per variant), a <Layer> per variant (a copy of the base layer's settings), and <CombinedLayer> entries: one per variant (so each shows in the picker) and
  two mixes of the intact layer with the variants, like the engine's own "dirt01;dirt02": NAME_WORN (three parts intact, one cracked) and NAME_DAMAGED (the intact layer and the first cracked, missing-stone and pothole variant: the engine reads at most four entries; one part each).
The new layers go right after the last <Layer> (new combined layers after the last <CombinedLayer>), the order the file already has. Several layers can be given at once, and more can be added to a map that is\nalready patched (a layer whose variants are in is skipped); the first backup stays the way back. Existing saves: test on a copy of the save first.
"""
import argparse
import json
import os
import re
import shutil
import subprocess
import sys

MANIFEST = ".damage_builder_manifest.json"
# What the engine's rain wetness reads of a layer (porosity: how much rain soaks in; firmnessWet / viscosity: how soft it gets, for tyre tracks). ONE value for every damage variant (cracked, missing stone,
# pothole), the intact layer's own (the map's cobblestones all say 0.9 / 1, firmness 1): painted in one mix, nothing reacts to the rain differently from what is next to it. (Potholes were once non-porous
# and the missing stones and cracks in between: a mess, wet in one spot and dry next to it. The water of a pothole is its wet twin, stamped while it rains.)
VARIANT_WETNESS = {"porosityAtZeroRoughness": "0.9", "porosityAtFullRoughness": "1", "firmnessWet": "1", "viscosity": "1"}

def wetness_for(name):
    """The rain-wetness attributes of a damage variant by its name (None: an intact layer)."""
    lower = name.lower()
    if "pothole" in lower or "missing" in lower or "cracked" in lower:
        return VARIANT_WETNESS
    return None

def pothole_wetness(text):
    """The damage variants that are in the i3d already (potholes, missing stones, cracks) get their rain-wetness attributes (replaced or added). Returns (text, how many layers)."""
    count = 0
    def fix(m):
        nonlocal count
        tag = m.group(0)
        attrs_for = wetness_for(m.group(1))
        if attrs_for is None:
            return tag
        for key, value in attrs_for.items():
            if re.search(r'\b%s="' % key, tag):
                tag = re.sub(r'(\b%s=")[^"]*(")' % key, r'\g<1>%s\g<2>' % value, tag)
            else:
                tag = tag[:-2] + f' {key}="{value}"/>'
        count += 1
        return tag
    # (only the variants: <layer>_cracked1, _missing2, _pothole1_wet ...; a base layer such as mudCracked is not one)
    text = re.sub(r'<Layer name="([A-Za-z0-9]+_(?:pothole|missing|cracked)[^"]*)"[^>]*/>', fix, text, flags=re.I)
    return text, count

def read(path):
    return open(path, "rb").read().decode("latin-1")

def write(path, text):
    open(path, "wb").write(text.encode("latin-1"))

def attrs(tag):
    return dict(re.findall(r'([A-Za-z]+)="([^"]*)"', tag))

def restore(maps, i3d):
    manifest_path = os.path.join(maps, MANIFEST)
    if not os.path.exists(manifest_path):
        sys.exit("nothing to restore: no manifest")
    manifest = json.load(open(manifest_path))
    shutil.copyfile(os.path.join(maps, manifest["backup"]), os.path.join(maps, i3d))
    for f in manifest["files"]:
        if os.path.exists(os.path.join(maps, f)):
            os.remove(os.path.join(maps, f))
    os.remove(manifest_path)
    os.remove(os.path.join(maps, manifest["backup"]))
    print(f"restored {i3d}, removed {len(manifest['files'])} files")

def add_one(out, layer, variants, maps):
    """The insertions for one base layer into the i3d text `out`. Returns (out, files, names, folder, weight_size, vdir, combined_names) or None when this layer's variants are already in."""
    m = re.search(r'^( *)<Layer name="%s"[^\n]*?/>[ \t]*\r?$' % re.escape(layer), out, re.M | re.I)
    if not m:
        sys.exit(f"no <Layer name=\"{layer}\"> in the i3d")
    indent, base_line = m.group(1), m.group(0)
    base = attrs(base_line)
    detail_file = re.search(r'<File fileId="%s" filename="([^"]*)"' % base["detailMapId"], out).group(1)
    folder = os.path.dirname(detail_file)                                  # textures/terrain/Cobblestone03
    weight_file = re.search(r'<File fileId="%s" filename="([^"]*)"' % base["weightMapId"], out).group(1)
    weight_size = subprocess.run(["identify", "-format", "%wx%h", os.path.join(maps, weight_file)], check=True, capture_output=True, text=True).stdout

    vdir = os.path.join(variants, layer.lower())
    names = sorted({f.rsplit("_", 1)[0] for f in os.listdir(vdir) if f.endswith("_diffuse.dds")})
    if not names:
        sys.exit(f"no variants in {vdir}")
    if re.search(r'<Layer name="%s"' % re.escape(names[0]), out, re.I):
        print(f"{layer}: its variants are already in the map, skipped")
        return None
    nxt = max(int(i) for i in re.findall(r'fileId="(\d+)"', out)) + 1
    file_lines, layer_lines, files, ids = [], [], [], {}
    for name in names:
        ids[name] = {}
        for kind in ("diffuse", "normal", "height"):
            rel = f"{folder}/{name}_{kind}.dds"
            file_lines.append(f'    <File fileId="{nxt}" filename="{rel}"/>')
            files.append(rel)
            ids[name][kind] = nxt
            nxt += 1
        rel = f"data/{name}_weight.png"
        file_lines.append(f'    <File fileId="{nxt}" filename="{rel}"/>')
        files.append(rel)
        ids[name]["weight"] = nxt
        nxt += 1
        new = dict(base)
        new.update({"name": name, "detailMapId": ids[name]["diffuse"], "normalMapId": ids[name]["normal"], "heightMapId": ids[name]["height"], "weightMapId": ids[name]["weight"]})
        if wetness_for(name) is not None:
            new.update(wetness_for(name))
        layer_lines.append(indent + "<Layer " + " ".join(f'{k}="{v}"' for k, v in new.items()) + "/>")

    upper = layer.upper()
    combined = [f'{indent}<CombinedLayer name="{n.upper()}" layers="{n}" noiseFrequency="2"/>' for n in names]
    cracked = [n for n in names if "cracked" in n]
    mixes = []
    if cracked:
        mixes.append(("WORN", [layer] * 3 + [cracked[0]]))
    # the engine reads at most FOUR entries of a combined layer (the map's own have 1 or 2, ROADGRAVEL 4; an 8-entry mix showed only the first four: intact and the cracked ones, never the missing stones or
    # the potholes): the intact layer and the first variant of each kind, in the order cracked, missing, pothole (the wet twins are for the rain, not for the mix)
    damaged = [layer]
    for kind in ("cracked", "missing", "pothole"):
        first = next((n for n in names if kind in n and not n.endswith("_wet")), None)
        if first is not None:
            damaged.append(first)
    mixes.append(("DAMAGED", damaged[:4]))
    for suffix, members in mixes:
        existing = re.search(r'(<CombinedLayer name="%s_%s" layers=")([^"]*)(")' % (re.escape(upper), suffix), out, re.I)
        if existing is None:
            combined.append(f'{indent}<CombinedLayer name="{upper}_{suffix}" layers="{";".join(members)}" noiseFrequency="2"/>')
        elif suffix == "DAMAGED":
            # a second batch for a layer (potholes after the cracks): the mix that is there takes the new dry variants in
            # (the mix is rebuilt to the same four: a longer one is cut back, one with a variant kind missing gets it)
            out = out[:existing.start(2)] + ";".join(members) + out[existing.end(2):]

    # the insertions (text only)
    end_files = out.index("  </Files>")
    out = out[:end_files] + "\n".join(file_lines) + "\n" + out[end_files:]
    last_layer = [x for x in re.finditer(r'^ *<Layer name="[^\n]*?/>[ \t]*\r?\n', out, re.M)][-1]
    out = out[:last_layer.end()] + "\n".join(layer_lines) + "\n" + out[last_layer.end():]
    last_combined = [x for x in re.finditer(r'^ *<CombinedLayer [^\n]*?/>[ \t]*\r?\n', out, re.M)][-1]
    out = out[:last_combined.end()] + "\n".join(combined) + "\n" + out[last_combined.end():]
    print(f"{layer}: {len(names)} variant layers ({', '.join(names)}), combined: {', '.join(re.findall(r'name=\"([^\"]*)\"', chr(10).join(combined)))}")
    return out, files, names, folder, weight_size, vdir

def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--maps", required=True)
    ap.add_argument("--i3d", required=True)
    ap.add_argument("--layer", help="one base layer or several, separated by commas")
    ap.add_argument("--variants")
    ap.add_argument("--apply", action="store_true")
    ap.add_argument("--restore", action="store_true")
    ap.add_argument("--update", action="store_true")
    ap.add_argument("--wetness", action="store_true", help="give the damage variants that are in the i3d already (potholes, missing stones, cracks) their rain-wetness attributes (no textures, no --layer needed)")
    args = ap.parse_args()
    if args.wetness:
        path = os.path.join(args.maps, args.i3d)
        text, count = pothole_wetness(read(path))
        write(path, text)
        print(f"{count} damage variant layers: {VARIANT_WETNESS}")
        return
    if args.restore:
        return restore(args.maps, args.i3d)
    if not args.layer or not args.variants:
        sys.exit("--layer and --variants are needed")
    layers = [x.strip() for x in args.layer.split(",") if x.strip()]
    manifest_path = os.path.join(args.maps, MANIFEST)
    if args.update:
        if not os.path.exists(manifest_path):
            sys.exit("nothing to update: this map was not patched (no manifest)")
        wanted = {os.path.basename(rel): None for rel in json.load(open(manifest_path))["files"]}
        copied = 0
        for rel in json.load(open(manifest_path))["files"]:
            name = os.path.basename(rel)
            for layer in layers:
                source = os.path.join(args.variants, layer.lower(), name)
                if rel.endswith(".dds") and os.path.exists(source):
                    shutil.copyfile(source, os.path.join(args.maps, rel))
                    copied += 1
        print(f"updated {copied} textures")
        return
    i3d_path = os.path.join(args.maps, args.i3d)
    text = read(i3d_path)
    out, added = text, []
    for layer in layers:
        result = add_one(out, layer, args.variants, args.maps)
        if result is not None:
            out = result[0]
            added.append(result[1:])
    patched = os.path.join(args.variants, args.i3d + ".patched")
    write(patched, out)
    print(f"patched i3d (not applied): {patched}   (+{len(out) - len(text)} bytes)")
    if not added:
        print("nothing to add.")
        return
    if not args.apply:
        print("dry run: nothing changed in the map. Add --apply to apply.")
        return
    if os.path.exists(manifest_path):
        manifest = json.load(open(manifest_path))                     # (an already patched map: the first backup stays the way back to the original)
    else:
        backup = args.i3d + ".before-damage-builder"
        shutil.copyfile(i3d_path, os.path.join(args.maps, backup))
        manifest = {"backup": backup, "files": []}
    for files, names, folder, weight_size, vdir in added:
        for name in names:
            for kind in ("diffuse", "normal", "height"):
                shutil.copyfile(os.path.join(vdir, f"{name}_{kind}.dds"), os.path.join(args.maps, folder, f"{name}_{kind}.dds"))
            subprocess.run(["convert", "-size", weight_size, "xc:black", "-colorspace", "Gray", "-depth", "8", os.path.join(args.maps, f"data/{name}_weight.png")], check=True)
        manifest["files"] += [f for f in files if f not in manifest["files"]]
    write(i3d_path, out)
    json.dump(manifest, open(manifest_path, "w"), indent=1)
    print("applied. Back up: " + manifest["backup"] + ". --restore undoes all of it.")

if __name__ == "__main__":
    main()
