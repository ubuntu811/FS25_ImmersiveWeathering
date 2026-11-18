"""BC4 (one 8-bit channel, the height maps) reader and writer for DDS files, with a mip chain. numpy only."""
import struct
import numpy as np

def _header(path):
    data = open(path, "rb").read()
    if data[:4] != b"DDS ":
        raise ValueError("not a DDS file")
    height, width = struct.unpack_from("<II", data, 12)
    fourcc = data[84:88]
    offset = 128
    if fourcc == b"DX10":
        offset += 20
    return data, width, height, offset

def read_bc4(path):
    """Returns the first mip level as a float array 0..255 (height x width)."""
    data, w, h, offset = _header(path)
    bw, bh = (w + 3) // 4, (h + 3) // 4
    blocks = np.frombuffer(data, dtype=np.uint8, count=bw * bh * 8, offset=offset).reshape(bh, bw, 8)
    r0 = blocks[:, :, 0].astype(np.float32)
    r1 = blocks[:, :, 1].astype(np.float32)
    bits = np.zeros((bh, bw), dtype=np.uint64)
    for i in range(6):
        bits |= blocks[:, :, 2 + i].astype(np.uint64) << np.uint64(8 * i)
    out = np.zeros((h, w), dtype=np.float32)
    palette = np.zeros((bh, bw, 8), dtype=np.float32)
    palette[:, :, 0], palette[:, :, 1] = r0, r1
    gt = r0 > r1
    for k in range(1, 7):
        palette[:, :, k + 1] = ((7 - k) * r0 + k * r1) / 7.0                     # r0 > r1: six interpolated values
    for k in range(1, 5):
        palette[:, :, k + 1] = np.where(gt, palette[:, :, k + 1], ((5 - k) * r0 + k * r1) / 5.0)     # r0 <= r1: four interpolated, then 0 and 255
    palette[:, :, 6] = np.where(gt, palette[:, :, 6], 0.0)
    palette[:, :, 7] = np.where(gt, palette[:, :, 7], 255.0)
    for py in range(4):
        for px in range(4):
            idx = ((bits >> np.uint64(3 * (py * 4 + px))) & np.uint64(7)).astype(np.int64)
            val = np.take_along_axis(palette, idx[:, :, None], axis=2)[:, :, 0]
            out[py::4, px::4] = val[: (h - py + 3) // 4, : (w - px + 3) // 4]
    return out

def _encode_level(img):
    h, w = img.shape
    bw, bh = w // 4, h // 4
    blocks = img.reshape(bh, 4, bw, 4).transpose(0, 2, 1, 3).reshape(bh, bw, 16)
    lo = blocks.min(axis=2)
    hi = blocks.max(axis=2)
    out = bytearray()
    for by in range(bh):
        for bx in range(bw):
            a, b = int(round(hi[by, bx])), int(round(lo[by, bx]))      # r0 > r1: 8-value mode
            if a == b:
                out += bytes([a, b]) + bytes(6)
                continue
            palette = np.array([a, b] + [((7 - k) * a + k * b) / 7.0 for k in range(1, 7)], dtype=np.float32)
            idx = np.abs(blocks[by, bx][:, None] - palette[None, :]).argmin(axis=1)
            bits = 0
            for i, v in enumerate(idx):
                bits |= int(v) << (3 * i)
            out += bytes([a, b]) + bits.to_bytes(6, "little")
    return bytes(out)

def write_bc4(path, img, header=None):
    """img: float array 0..255, sizes a power of two >= 4. Writes the whole mip chain (box filter)."""
    h, w = img.shape
    levels = []
    level = np.clip(img, 0, 255)
    while True:
        levels.append(level)
        if level.shape[0] <= 4 or level.shape[1] <= 4:
            break
        level = level.reshape(level.shape[0] // 2, 2, level.shape[1] // 2, 2).mean(axis=(1, 3))
    if header is not None:
        with open(path, "wb") as f:
            f.write(header)
            for lvl in levels:
                f.write(_encode_level(lvl))
        return
    header = bytearray(128)
    header[0:4] = b"DDS "
    struct.pack_into("<I", header, 4, 124)
    struct.pack_into("<I", header, 8, 0x1 | 0x2 | 0x4 | 0x1000 | 0x20000 | 0x80000)
    struct.pack_into("<II", header, 12, h, w)
    struct.pack_into("<I", header, 20, ((w + 3) // 4) * 8)
    struct.pack_into("<I", header, 28, len(levels))
    struct.pack_into("<I", header, 76, 32)
    struct.pack_into("<I", header, 80, 0x4)
    header[84:88] = b"BC4U"
    struct.pack_into("<I", header, 108, 0x1000 | 0x400000 | 0x8)
    with open(path, "wb") as f:
        f.write(bytes(header))
        for lvl in levels:
            f.write(_encode_level(lvl))
