"""BC7 encoder, mode 6 only (one subset, RGBA endpoints of 7 bits + a p-bit, 4-bit indices), numpy only. Endpoints on the principal axis of each block. Good enough for terrain diffuse maps."""
import numpy as np

_WEIGHTS = np.array([0, 4, 9, 13, 17, 21, 26, 30, 34, 38, 43, 47, 51, 55, 60, 64], dtype=np.int32)

def _blocks(img):
    h, w, c = img.shape
    bw, bh = w // 4, h // 4
    return img.reshape(bh, 4, bw, 4, c).transpose(0, 2, 1, 3, 4).reshape(bh * bw, 16, c).astype(np.float32)

def _encode_chunk(px):
    n = px.shape[0]
    mean = px.mean(axis=1, keepdims=True)
    centred = px - mean
    cov = np.einsum("npc,npd->ncd", centred, centred)
    axis = np.ones((n, 4), dtype=np.float32)
    for _ in range(8):
        axis = np.einsum("ncd,nd->nc", cov, axis)
        norm = np.linalg.norm(axis, axis=1, keepdims=True)
        axis = np.where(norm > 1e-6, axis / np.maximum(norm, 1e-6), np.array([0.5, 0.5, 0.5, 0.5], dtype=np.float32))
    t = np.einsum("npc,nc->np", centred, axis)
    lo = mean[:, 0, :] + axis * t.min(axis=1, keepdims=True)
    hi = mean[:, 0, :] + axis * t.max(axis=1, keepdims=True)
    # 7 bit endpoints (p-bit 0: the decoded value is 2 * v7)
    e0 = np.clip(np.rint(lo / 2), 0, 127).astype(np.int32)
    e1 = np.clip(np.rint(hi / 2), 0, 127).astype(np.int32)
    d0 = (e0 * 2).astype(np.float32)
    d1 = (e1 * 2).astype(np.float32)
    # the 16 colours of the ramp and the nearest index per pixel (RGB and alpha)
    ramp = ((64 - _WEIGHTS)[None, :, None] * d0[:, None, :] + _WEIGHTS[None, :, None] * d1[:, None, :] + 32) // 64      # n x 16 x 4
    err = ((px[:, :, None, :] - ramp[:, None, :, :]) ** 2).sum(axis=3)                                                    # n x 16 px x 16 idx
    idx = err.argmin(axis=2).astype(np.int64)
    # the anchor (pixel 0) has 3 index bits: its index must be below 8, else swap the endpoints and flip the indices
    flip = idx[:, 0] >= 8
    idx = np.where(flip[:, None], 15 - idx, idx)
    e0, e1 = np.where(flip[:, None], e1, e0), np.where(flip[:, None], e0, e1)
    return e0.astype(np.int64), e1.astype(np.int64), idx

def encode(img):
    """img: h x w x 4 array (0..255). Returns the bytes of the BC7 blocks, row of blocks by row of blocks."""
    px = _blocks(img)
    out = np.zeros((px.shape[0], 2), dtype=np.uint64)
    for start in range(0, px.shape[0], 4096):
        e0, e1, idx = _encode_chunk(px[start:start + 4096])
        lo = np.zeros(e0.shape[0], dtype=np.uint64)
        hi = np.zeros(e0.shape[0], dtype=np.uint64)
        lo |= np.uint64(1 << 6)                                                  # mode 6
        offset = 7
        fields = []
        for c in range(4):
            fields.append(e0[:, c])
            fields.append(e1[:, c])
        for f in fields:
            lo |= (f.astype(np.uint64) & np.uint64(127)) << np.uint64(offset)
            offset += 7
        # offset is 63 now: the p-bits are bits 63 and 64 (0 here), the indices start at bit 65
        pos = 65
        bits = idx
        for p in range(16):
            width = 3 if p == 0 else 4
            v = bits[:, p].astype(np.uint64)
            for b in range(width):
                bit = (v >> np.uint64(b)) & np.uint64(1)
                if pos < 64:
                    lo |= bit << np.uint64(pos)
                else:
                    hi |= bit << np.uint64(pos - 64)
                pos += 1
        out[start:start + e0.shape[0], 0] = lo
        out[start:start + e0.shape[0], 1] = hi
    return out.astype("<u8").tobytes()
