#!/usr/bin/env python3
"""
Damage builder: makes damaged variants of a terrain layer from the map's own textures.
  - "pothole": one small hole near the middle of the tile with a bowl and loose gravel, dry and wet (the wet twin has water in the bowl; IW swaps it in when it rains)
  - "missing": holes all over the tile, a stone or a few neighbouring stones gone each (the bed shows, sunken)
  - "cracked": stretches of the joints are widened, dark and sunken (cobblestones break between the stones, not through them)
Reads <maps>/textures/terrain/<Layer>/<Layer>_diffuse|normal|height.dds, writes the same three files per variant into <out>/<layername>/ in exactly the format of the originals (the terrain textures are packed into arrays: same format and mips for every layer; diffuse BC7 with its alpha channel, normal DXT1, height BC4)
and PNG previews. Needs numpy and ImageMagick. Everything is deterministic for a seed.
  python3 damage_builder.py --maps <maps dir> --layer cobblestone03 --out <dir> [--missing 2] [--cracked 3] [--potholes 2] [--seed 1]
"""
import argparse
import os
import subprocess
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import dds_bc4
import bc7

# ---------- small image helpers (numpy only) ----------

def read_rgb(dds_path, tmp_png):
    subprocess.run(["convert", dds_path, tmp_png], check=True)
    out = subprocess.run(["convert", tmp_png, "-depth", "8", "rgb:-"], check=True, capture_output=True).stdout
    size = subprocess.run(["identify", "-format", "%w %h", tmp_png], check=True, capture_output=True, text=True).stdout.split()
    w, h = int(size[0]), int(size[1])
    return np.frombuffer(out, dtype=np.uint8).reshape(h, w, 3).astype(np.float32)

def read_rgba(dds_path, tmp_png):
    subprocess.run(["convert", dds_path, tmp_png], check=True)
    out = subprocess.run(["convert", tmp_png, "-depth", "8", "rgba:-"], check=True, capture_output=True).stdout
    size = subprocess.run(["identify", "-format", "%w %h", tmp_png], check=True, capture_output=True, text=True).stdout.split()
    w, h = int(size[0]), int(size[1])
    return np.frombuffer(out, dtype=np.uint8).reshape(h, w, 4).astype(np.float32)

def mips_to_4(img):
    """The chain down to 4 x 4 (the originals stop there), box filtered."""
    levels = [img]
    while levels[-1].shape[0] > 4:
        a = levels[-1]
        h, w = a.shape[:2]
        levels.append(a.reshape(h // 2, 2, w // 2, 2, -1).mean(axis=(1, 3)))
    return levels

def write_png(path, rgb):
    data = np.clip(rgb, 0, 255).astype(np.uint8)
    h, w = data.shape[:2]
    subprocess.run(["convert", "-size", f"{w}x{h}", "-depth", "8", "rgb:-", path], input=data.tobytes(), check=True)

def write_dds(path, rgb, compression, mipmaps=10):
    data = np.clip(rgb, 0, 255).astype(np.uint8)
    h, w = data.shape[:2]
    subprocess.run(["convert", "-size", f"{w}x{h}", "-depth", "8", "rgb:-", "-define", f"dds:compression={compression}", "-define", f"dds:mipmaps={mipmaps}", path],
                   input=data.tobytes(), check=True)

def box_blur(a, r):
    """Blur with wraparound (the texture tiles), radius r pixels."""
    if r <= 0:
        return a
    out = a.astype(np.float32)
    for axis in (0, 1):
        n = out.shape[axis]
        padded = np.concatenate([np.take(out, range(n - r, n), axis=axis), out, np.take(out, range(0, r), axis=axis)], axis=axis)
        c = np.cumsum(padded, axis=axis, dtype=np.float64)
        zero = np.zeros_like(np.take(c, [0], axis=axis))
        c = np.concatenate([zero, c], axis=axis)
        hi = np.take(c, range(2 * r + 1, 2 * r + 1 + n), axis=axis)
        lo = np.take(c, range(0, n), axis=axis)
        out = ((hi - lo) / (2 * r + 1)).astype(np.float32)
    return out

def upsample2(a):
    return box_blur(np.kron(a, np.ones((2, 2), dtype=np.float32)), 1)

def downsample2(a):
    h, w = a.shape
    return a.reshape(h // 2, 2, w // 2, 2).mean(axis=(1, 3))

def fbm(shape, rng, octaves=4, base=8):
    """Smooth noise 0..1 (value noise, tiling)."""
    h, w = shape
    total = np.zeros(shape, dtype=np.float32)
    amp, norm = 1.0, 0.0
    for o in range(octaves):
        cells = base * (2 ** o)
        grid = rng.random((cells, cells)).astype(np.float32)
        big = np.kron(grid, np.ones((h // cells, w // cells), dtype=np.float32))
        total += amp * box_blur(big, max(1, h // cells // 2))
        norm += amp
        amp *= 0.5
    total /= norm
    return (total - total.min()) / max(1e-6, total.max() - total.min())

def label(mask):
    """4-connected components of a boolean mask: (labels, count)."""
    h, w = mask.shape
    labels = np.zeros((h, w), dtype=np.int32)
    parent = [0]
    def find(x):
        while parent[x] != x:
            parent[x] = parent[parent[x]]
            x = parent[x]
        return x
    nxt = 1
    for y in range(h):
        row = mask[y]
        for x in range(w):
            if not row[x]:
                continue
            up = labels[y - 1, x] if y > 0 else 0
            left = labels[y, x - 1] if x > 0 else 0
            if up == 0 and left == 0:
                parent.append(nxt)
                labels[y, x] = nxt
                nxt += 1
            elif up and left and up != left:
                a, b = find(up), find(left)
                parent[max(a, b)] = min(a, b)
                labels[y, x] = min(a, b)
            else:
                labels[y, x] = up or left
    roots = np.array([find(i) for i in range(nxt)], dtype=np.int32)
    labels = roots[labels]
    uniq = np.unique(labels[labels > 0])
    remap = np.zeros(labels.max() + 1, dtype=np.int32)
    remap[uniq] = np.arange(1, len(uniq) + 1)
    return remap[labels], len(uniq)

# ---------- the layer ----------

class Layer:
    def __init__(self, maps_dir, name, tmp):
        folder = os.path.join(maps_dir, "textures", "terrain")
        match = [d for d in os.listdir(folder) if d.lower() == name.lower()]
        if not match:
            raise SystemExit(f"no texture folder for layer {name} in {folder}")
        self.folder = os.path.join(folder, match[0])
        self.base = match[0]
        self.diffuse_path = os.path.join(self.folder, f"{self.base}_diffuse.dds")
        self.normal_path = os.path.join(self.folder, f"{self.base}_normal.dds")
        self.height_path = os.path.join(self.folder, f"{self.base}_height.dds")
        rgba = read_rgba(self.diffuse_path, tmp + "_d.png")
        self.diffuse = rgba[:, :, :3]
        self.alpha = rgba[:, :, 3]                                               # the gloss / roughness the terrain shader reads: kept, and changed where the damage is
        self.normal = read_rgb(self.normal_path, tmp + "_n.png")
        height = dds_bc4.read_bc4(self.height_path)
        self.height = upsample2(height) if height.shape[0] * 2 == self.diffuse.shape[0] else height
        self.size = self.height.shape[0]
        lo, hi = np.percentile(self.height, 15), np.percentile(self.height, 85)
        self.threshold = (lo + hi) / 2
        self.stone = self.height > self.threshold
        # a texture whose joints are shallow (cobblestone02) joins its stones into one region at the middle threshold: the threshold goes up until no region is bigger than a plausible stone cluster
        for _ in range(10):
            labels, count = label(self.stone)
            largest = int(np.bincount(labels.ravel(), minlength=count + 1)[1:].max()) if count > 0 else 0
            if largest <= 0.12 * self.size * self.size:
                break
            self.threshold += (hi - lo) * 0.06
            self.stone = self.height > self.threshold
        self.low = float(np.percentile(self.height, 8))
        self.calibrate_normal()

    def gradient(self, h):
        gx = (np.roll(h, -1, axis=1) - np.roll(h, 1, axis=1)) * 0.5
        gy = (np.roll(h, -1, axis=0) - np.roll(h, 1, axis=0)) * 0.5
        return gx, gy

    def calibrate_normal(self):
        """The signs and the strength of the normal map against its height map (least squares), so a changed height can be turned into a matching normal."""
        gx, gy = self.gradient(box_blur(self.height, 1))
        nx = self.normal[:, :, 0] / 127.5 - 1
        ny = self.normal[:, :, 1] / 127.5 - 1
        self.sign = []
        self.scale = []
        for g, n in ((gx, nx), (gy, ny)):
            k = float((g * n).sum() / max(1e-6, (g * g).sum()))
            self.sign.append(1 if k >= 0 else -1)
            self.scale.append(abs(k))
        self.blue_mean = float(self.normal[:, :, 2].mean())

    def normal_from_height(self, h):
        gx, gy = self.gradient(box_blur(h, 1))
        nx = np.clip(self.sign[0] * self.scale[0] * gx, -0.95, 0.95)
        ny = np.clip(self.sign[1] * self.scale[1] * gy, -0.95, 0.95)
        nz = np.sqrt(np.clip(1 - nx * nx - ny * ny, 0.02, 1))
        return np.stack([(nx + 1) * 127.5, (ny + 1) * 127.5, (nz + 1) * 127.5], axis=2)

    def stones(self, min_area=500):
        labels, count = label(self.stone)
        areas = np.bincount(labels.ravel(), minlength=count + 1)
        keep = [i for i in range(1, count + 1) if areas[i] >= min_area]
        centres = {}
        ys, xs = np.mgrid[0:self.size, 0:self.size]
        for i in keep:
            m = labels == i
            centres[i] = (float(xs[m].mean()), float(ys[m].mean()), int(areas[i]))
        return labels, centres

    def joint_colour(self):
        joints = ~self.stone
        return self.diffuse[joints].mean(axis=0)

# ---------- the damage ----------

def feather(mask, r):
    return np.clip(box_blur(mask.astype(np.float32), r) * 1.6 - 0.1, 0, 1)

def spread_seeds(points, count, min_dist, rng):
    """count points of the list, at least min_dist apart where that is possible (a random start, then random ones that keep their distance)."""
    chosen = []
    order = list(rng.permutation(len(points)))
    for dist in (min_dist, min_dist * 0.6, 0):
        for k in order:
            if len(chosen) >= count:
                return chosen
            x, y = points[k]
            if k not in chosen and all((x - points[c][0]) ** 2 + (y - points[c][1]) ** 2 >= dist * dist for c in chosen):
                chosen.append(k)
    return chosen

def make_missing(layer, rng, holes=8, stones=2):
    """Holes all over the tile (a terrain texture is seen through a patch of a metre, so a single hole mostly misses): each is a stone or a few neighbouring stones gone, the bed shows, sunken. The bed is what the joints are made of (their colour and grain), darker towards the rim where the neighbours shade it."""
    labels, centres = layer.stones()
    size = layer.size
    margin = size * 0.06
    inside = [i for i, (x, y, a) in centres.items() if margin < x < size - margin and margin < y < size - margin]
    points = [(centres[i][0], centres[i][1]) for i in inside]
    removed = []
    for k in spread_seeds(points, holes, size * 0.2, rng):
        sx, sy = points[k]
        order = sorted(inside, key=lambda i: (centres[i][0] - sx) ** 2 + (centres[i][1] - sy) ** 2)
        count = max(1, stones + int(rng.integers(0, 2)) - 1)
        removed += [i for i in order[:count] if i not in removed]
    gone = np.isin(labels, removed)
    hole = box_blur(gone.astype(np.float32), 4) > 0.2                         # the stones and a little of the joint round them
    area = feather(hole, 3)
    shape = layer.diffuse.shape[:2]
    noise = fbm(shape, rng, 4, 8)
    # the bed: sunken below the joints, rough
    # (with fine grain: a perfectly flat bed has a flat normal, and a flat glossy patch in sunlight is a mirror: it shone white in the game)
    grain_h = fbm(shape, rng, 3, 128)
    height = layer.height * (1 - area) + (layer.low - 18 - 16 * noise + 14 * (grain_h - 0.5)) * area
    # the soil: the joints' own colour with their grain (a bright speckle of sand and a few dark grains), darker near the rim
    joint = layer.joint_colour()
    fine = fbm(shape, rng, 3, 64)
    grain = 0.78 + 0.45 * fine
    sand = (fbm(shape, rng, 2, 128) > 0.74).astype(np.float32)
    colour = joint[None, None, :] * grain[:, :, None] * np.array([0.96, 0.9, 0.8])[None, None, :]
    colour = colour * (1 - 0.35 * (fine < 0.2)[:, :, None]) + 55 * sand[:, :, None]
    inner = np.clip(1 - box_blur(area, 14) * 1.3, 0, 1)                      # 1 deep inside the hole, falling to 0 at its rim
    shade = (0.55 + 0.45 * np.clip(box_blur(area, 14) * 1.6 - 0.2, 0, 1))[:, :, None]
    colour = colour * (0.62 + 0.38 * shade)
    diffuse = layer.diffuse * (1 - area[:, :, None]) + colour * area[:, :, None]
    rim = np.clip(box_blur(area, 5) - area, 0, 1)[:, :, None]
    diffuse = diffuse * (1 - 0.22 * rim)                                     # the stones at the edge stand in the shade of the hole
    bed_alpha = min(float(layer.alpha[~layer.stone].mean()) * 0.5, 30.0)       # loose soil is matt: rougher than the stones, never a mirror
    alpha = layer.alpha * (1 - area) + bed_alpha * area
    return diffuse, height, alpha

def joint_path(cost, joints, start, rng, low=900, high=1700):
    """A continuous path along the joints (the texture tiles: wrapping): Dijkstra from the start over the joint pixels, the cheapest way following the valleys (cost: deep joint pixels are cheap, a random jitter
    makes it wander), then a random end among the pixels reached after `low` to `high` cost, the way back."""
    import heapq
    size = joints.shape[0]
    best = {start: 0.0}
    prev = {}
    heap = [(0.0, start)]
    far = []
    done = set()
    while heap:
        d, (x, y) = heapq.heappop(heap)
        if (x, y) in done:
            continue
        done.add((x, y))
        if d >= low:
            far.append((x, y))
        if d >= high:
            continue
        for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1), (1, 1), (-1, -1), (1, -1), (-1, 1)):
            nx, ny = (x + dx) % size, (y + dy) % size
            if not joints[ny, nx] or (nx, ny) in done:
                continue
            nd = d + cost[ny, nx] * (1.41 if dx and dy else 1.0)
            if nd < best.get((nx, ny), 1e18):
                best[(nx, ny)] = nd
                prev[(nx, ny)] = (x, y)
                heapq.heappush(heap, (nd, (nx, ny)))
    if not far:
        return []
    end = far[int(rng.integers(len(far)))]
    path = [end]
    while path[-1] != start:
        path.append(prev[path[-1]])
    return path

def make_cracked(layer, rng, cracks=10):
    """Stretches of the joints are widened and sunken, long and continuous: cobblestones break between the stones, not through them."""
    size = layer.size
    smooth = box_blur(layer.height, 2)
    # the joints: the low pixels of the smoothed height, only the big connected network (not the pits in the stones)
    low_mask = smooth < (np.percentile(smooth, 15) + (layer.threshold - np.percentile(smooth, 15)) * 0.55)
    labels, count = label(low_mask)
    sizes = np.bincount(labels.ravel(), minlength=count + 1)
    sizes[0] = 0
    joints = labels == int(sizes.argmax())
    if joints.mean() < 0.08:
        # shallow joints (cobblestone02): the percentile rule finds almost no network; what lies between the stones (the biggest connected piece) is the network then
        between, between_count = label(~layer.stone)
        between_sizes = np.bincount(between.ravel(), minlength=between_count + 1)
        between_sizes[0] = 0
        joints = between == int(between_sizes.argmax())
    deep = np.clip((smooth - smooth[joints].min()) / max(1.0, float(np.percentile(smooth[joints], 90) - smooth[joints].min())), 0, 1)
    cost = (1.0 + 3.0 * deep + 2.0 * rng.random((size, size))).astype(np.float32)           # valleys cheap, jitter makes it wander
    ys, xs = np.nonzero(joints)
    crack = np.zeros((size, size), dtype=np.float32)
    cells = 4                                                                    # one start per cell of a 4 x 4 grid (most of them): the cracks are all over the tile, not in one corner
    starts = []
    for gy in range(cells):
        for gx in range(cells):
            inside = np.nonzero((xs * cells // size == gx) & (ys * cells // size == gy))[0]
            if len(inside) > 0 and rng.random() < cracks / (cells * cells):
                starts.append(int(inside[int(rng.integers(len(inside)))]))
    for k in starts or [int(rng.integers(len(xs)))]:
        for x, y in joint_path(cost, joints, (int(xs[k]), int(ys[k])), rng):
            crack[y, x] = 1
    area = feather(box_blur(crack, 4) > 0.1, 2)                               # the joint's own width (about 8 px at 1024)
    wide = feather(box_blur(crack, 7) > 0.06, 3)
    shape = layer.diffuse.shape[:2]
    height = layer.height - 26 * area - 10 * wide
    soil = layer.joint_colour() * np.array([0.75, 0.68, 0.58])
    grain = (0.7 + 0.5 * fbm(shape, rng, 3, 64))[:, :, None]
    open_joint = soil[None, None, :] * grain * 0.85
    diffuse = layer.diffuse * (1 - area[:, :, None]) + open_joint * area[:, :, None]
    diffuse = diffuse * (1 - 0.15 * (wide - area)[:, :, None])
    alpha = layer.alpha * (1 - 0.25 * area)
    return diffuse, height, alpha

def make_pothole(layer, rng):
    """A pothole: one hole near the middle of the tile (the texture repeats every unitSize metres, 1.2: a pothole can only be small), the stones nearest to it gone until about 11% of the tile is, an irregular rim,
    a bowl that deepens to the middle, gravel on its floor. Returns two variants of the same hole: dry, and wet (the bowl's deeper part holds water: dark, flat, as glossy as the texture can be, for the rain)."""
    labels, centres = layer.stones()
    size = layer.size
    shape = layer.diffuse.shape[:2]
    cx = size * (0.5 + (rng.random() - 0.5) * 0.2)
    cy = size * (0.5 + (rng.random() - 0.5) * 0.2)
    order = sorted(centres, key=lambda i: (centres[i][0] - cx) ** 2 + (centres[i][1] - cy) ** 2)
    removed, gone_area = [], 0
    for i in order:
        removed.append(i)
        gone_area += centres[i][2]
        if gone_area >= 0.11 * size * size:
            break
    gone = np.isin(labels, removed)
    rim_noise = fbm(shape, rng, 4, 16)
    hole = (box_blur(gone.astype(np.float32), 16) + 0.3 * (rim_noise - 0.5)) > 0.33                 # (a wide blur: the joints between the missing stones go too, one connected hole)
    area = feather(hole, 3)
    inner = np.clip(box_blur(area, 60) * 1.9 - 0.15, 0, 1)                    # the bowl: 1 deep in the middle, falling to 0 at the rim
    grain = fbm(shape, rng, 3, 128)
    noise = fbm(shape, rng, 4, 8)
    floor_level = layer.low - 14 - 25 * inner - 10 * noise + 12 * (grain - 0.5)
    height = layer.height * (1 - area) + floor_level * area
    # the soil: the joints' colour with its grain, darker towards the middle (damp), loose gravel lying in it
    joint = layer.joint_colour()
    fine = fbm(shape, rng, 3, 64)
    soil = joint[None, None, :] * (0.78 + 0.45 * fine)[:, :, None] * np.array([0.96, 0.9, 0.8])[None, None, :]
    soil = soil * (1 - 0.33 * inner)[:, :, None]
    pebbles = (fbm(shape, rng, 3, 32) > 0.76).astype(np.float32)[:, :, None]
    soil = soil * (1 - pebbles) + pebbles * np.array([118.0, 112.0, 102.0]) * (0.8 + 0.4 * fine)[:, :, None]
    shade = (0.6 + 0.4 * np.clip(box_blur(area, 14) * 1.6 - 0.2, 0, 1))[:, :, None]
    soil = soil * (0.72 + 0.28 * shade)
    rim = np.clip(box_blur(area, 5) - area, 0, 1)[:, :, None]
    dry_diffuse = (layer.diffuse * (1 - area[:, :, None]) + soil * area[:, :, None]) * (1 - 0.22 * rim)
    dry_alpha = layer.alpha * (1 - area) + min(float(layer.alpha[~layer.stone].mean()) * 0.5, 30.0) * area
    # wet: mud darkens and shines a little round the water, the water itself is dark, flat and at full gloss
    water = np.clip((inner - 0.5) / 0.12, 0, 1) * area
    mud = np.clip((inner - 0.22) / 0.28, 0, 1) * area
    water_colour = np.array([88.0, 94.0, 96.0])[None, None, :] * (0.95 + 0.1 * fine)[:, :, None]      # (the overcast sky it would reflect: a black pool never reads as water)
    wet_diffuse = dry_diffuse * (1 - 0.3 * mud)[:, :, None]
    wet_diffuse = wet_diffuse * (1 - water[:, :, None]) + water_colour * water[:, :, None]
    wet_alpha = dry_alpha * (1 - mud) + 130.0 * mud
    wet_alpha = wet_alpha * (1 - water) + 255.0 * water
    water_height = layer.low - 14 - 25 * 0.56 - 6.0
    wet_height = height * (1 - water) + water_height * water
    return (dry_diffuse, height, dry_alpha), (wet_diffuse, wet_height, wet_alpha)

def build(layer, kind, index, rng, out_dir, name):
    if kind == "missing":
        diffuse, height, alpha = make_missing(layer, rng, holes=max(4, 10 - 3 * index), stones=1 + index)
    else:
        diffuse, height, alpha = make_cracked(layer, rng)
    return write_variant(layer, diffuse, height, alpha, out_dir, name)

def write_variant(layer, diffuse, height, alpha, out_dir, name):
    height = np.clip(height, 0, 255)
    normal = layer.normal_from_height(height)
    # keep the original normal where nothing changed (the generated one is smoother)
    changed = feather(np.abs(height - layer.height) > 2, 3)[:, :, None]
    normal = layer.normal * (1 - changed) + normal * changed
    os.makedirs(out_dir, exist_ok=True)
    base = os.path.join(out_dir, name)
    # diffuse: BC7 with alpha, the header and the mip count of the original (a chain down to 4 x 4)
    original = open(layer.diffuse_path, "rb").read()
    header = original[:148] if original[84:88] == b"DX10" else original[:128]
    rgba = np.concatenate([np.clip(diffuse, 0, 255), np.clip(alpha, 0, 255)[:, :, None]], axis=2)
    with open(base + "_diffuse.dds", "wb") as f:
        f.write(header)
        for level in mips_to_4(rgba):
            f.write(bc7.encode(level))
    # normal: DXT1 by ImageMagick (mips: 9 levels like the original), the original's header
    original_n = open(layer.normal_path, "rb").read()
    tmp_n = base + "_normal_tmp.dds"
    write_dds(tmp_n, normal, "dxt1", mipmaps=8)
    data_n = open(tmp_n, "rb").read()[128:]
    os.remove(tmp_n)
    with open(base + "_normal.dds", "wb") as f:
        f.write(original_n[:128] + data_n)
    # height: BC4 with the original's header
    original_h = open(layer.height_path, "rb").read()
    header_h = original_h[:148] if original_h[84:88] == b"DX10" else original_h[:128]
    dds_bc4.write_bc4(base + "_height.dds", downsample2(height) if height.shape[0] == layer.diffuse.shape[0] else height, header=header_h)
    # the same size as the originals or the format is not the same
    for kind_name, source in (("diffuse", layer.diffuse_path), ("normal", layer.normal_path), ("height", layer.height_path)):
        a, b = os.path.getsize(base + f"_{kind_name}.dds"), os.path.getsize(source)
        if a != b:
            raise SystemExit(f"{name}_{kind_name}.dds is {a} bytes, the original {b}: the format or the mips differ")
    write_png(base + "_preview.png", diffuse)
    return base

def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--maps", required=True)
    ap.add_argument("--layer", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--missing", type=int, default=2)
    ap.add_argument("--cracked", type=int, default=3)
    ap.add_argument("--potholes", type=int, default=0, help="potholes: each also gets a wet twin (NAME_potholeN_wet) the game swaps in for rain")
    ap.add_argument("--seed", type=int, default=1)
    args = ap.parse_args()
    tmp = os.path.join(args.out, "_tmp")
    os.makedirs(args.out, exist_ok=True)
    layer = Layer(args.maps, args.layer, tmp)
    print(f"{layer.base}: {layer.size}x{layer.size}, stone threshold {layer.threshold:.0f}, normal signs {layer.sign}, scale {layer.scale[0]:.2f}/{layer.scale[1]:.2f}")
    written = []
    for kind, count in (("missing", args.missing), ("cracked", args.cracked)):
        for i in range(1, count + 1):
            rng = np.random.default_rng(args.seed * 1000 + (1 if kind == "missing" else 2) * 100 + i)
            name = f"{args.layer.lower()}_{kind}{i}"
            written.append(build(layer, kind, i, rng, os.path.join(args.out, args.layer.lower()), name))
            print("wrote", name)
    for i in range(1, args.potholes + 1):
        rng = np.random.default_rng(args.seed * 1000 + 3 * 100 + i)
        dry, wet = make_pothole(layer, rng)
        for suffix, (diffuse, height, alpha) in (("", dry), ("_wet", wet)):
            name = f"{args.layer.lower()}_pothole{i}{suffix}"
            written.append(write_variant(layer, diffuse, height, alpha, os.path.join(args.out, args.layer.lower()), name))
            print("wrote", name)
    return written

if __name__ == "__main__":
    main()
