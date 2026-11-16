"""Export the game art from the approved mockup generator (tools/mockups.py) into assets/.

Usage: python3 tools/export_art.py [out_dir]     (default: <repo>/assets)

mockups.py stays the single art source: palettes, textures, tree/boulder/crystal sprites and the b_* building
functions are imported, never copied. This file only adds what a tile game needs on top of the scene renderer:
seamless 32x32 terrain tiles, soft transition overlays (blob autotile, 46 tiles per ground), dual-grid water
and rock edges (16 corner configurations per lower ground), connectable road tiles, separate shadow /
light-and-smoke images, and the manifest the GDScript loader (render/art_library.gd) reads. Every random choice uses a fixed seed, so running twice writes identical bytes.
"""
import json
import math
import random
import sys
import types
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw

sys.path.insert(0, str(Path(__file__).resolve().parent))
import mockups as M  # noqa: E402
import mockups_v1 as MV  # noqa: E402  (HUD icons)

T = M.T
ROOT = Path(__file__).resolve().parent.parent
OUT = Path(sys.argv[1]) if len(sys.argv) > 1 else ROOT / "assets"

SKY = M.pal("3a4a5c", "5a7a8c", "7e9eb0", "aac6d4", "d8eef4")
# Blob autotile neighbour bits: N, NE, E, SE, S, SW, W, NW.
BN, BNE, BE, BSE, BS, BSW, BW, BNW = 1, 2, 4, 8, 16, 32, 64, 128
# Rank of each ground class: a higher ground draws soft overlays onto the lower ones around it.
GROUND_ORDER = ["water", "grass", "forest", "soil", "rock", "vein", "sky"]
TERRAIN_GROUND = {"grass": "grass", "fertile_soil": "soil", "forest": "forest", "rock": "rock", "water": "water",
                  "lumen_vein": "vein", "stump": "forest", "skystone": "sky"}


# ------------------------------------------------------------------ helpers
def mix(a, b, t):
    return tuple(int(a[i] * (1 - t) + b[i] * t) for i in range(3)) + (255,)


def A(p):
    return np.array([c[:3] for c in p], dtype=np.uint8)


def pnoise(cell, seed):
    """Seamless value noise on a TxT tile (cell must divide T): neighbouring tiles join without a seam."""
    n = T // cell
    g = np.random.default_rng(seed).random((n, n)).astype(np.float32)
    pos = (np.arange(T) + 0.5) / cell - 0.5
    i0 = np.floor(pos).astype(int)
    f = pos - i0
    f = f * f * (3 - 2 * f)
    ia, ib = i0 % n, (i0 + 1) % n
    gx = g[:, ia] * (1 - f) + g[:, ib] * f
    return gx[ia] * (1 - f)[:, None] + gx[ib] * f[:, None]


def pnoise_n(size, cell, seed):
    """Seamless value noise on a size x size field (cell must divide size)."""
    n = size // cell
    g = np.random.default_rng(seed).random((n, n)).astype(np.float32)
    pos = (np.arange(size) + 0.5) / cell - 0.5
    i0 = np.floor(pos).astype(int)
    f = pos - i0
    f = f * f * (3 - 2 * f)
    ia, ib = i0 % n, (i0 + 1) % n
    gx = g[:, ia] * (1 - f) + g[:, ib] * f
    return gx[ia] * (1 - f)[:, None] + gx[ib] * f[:, None]


def pfbm(seed, shared):
    """Large octaves come from `shared` (same for every variant of a ground, so any mix of its tiles joins
    without a seam); only the finest octave (and the details) differ per variant."""
    v = 0.38 * pnoise(16, shared) + 0.37 * pnoise(8, shared + 1) + 0.25 * pnoise(4, seed)
    return np.clip((v - 0.5) * 2.4 + 0.5, 0, 1)


# Warmer, lighter meadow palette than mockups.GRASS (sampled from the village mockup: 40883 / 5aa640 / 7abc4c / 9fd05c).
PG = M.pal("2f6e36", "408837", "5aa640", "7abc4c", "9fd05c")
CONFETTI = [M.hexc("f07aa8"), M.hexc("f6f0e0"), M.hexc("8ab8f8"), M.hexc("f4d050"), M.hexc("f6f0e0"), M.hexc("e8a0f0")]

BAY = np.tile(M.BAYER, (T // 4, T // 4))
YS, XS = np.mgrid[0:T, 0:T].astype(np.float32) + 0.5


def pquant(v, n, bias=0.0, amt=0.7):
    return np.clip(((v + bias) * n + (BAY - 0.5) * amt).astype(int), 0, n - 1)


def to_img(rgb, alpha=None):
    out = np.zeros((T, T, 4), dtype=np.uint8)
    out[..., :3] = rgb
    out[..., 3] = 255 if alpha is None else alpha
    return Image.fromarray(out, "RGBA")


def pack_atlas(tiles, cols):
    rows = (len(tiles) + cols - 1) // cols
    im = Image.new("RGBA", (cols * T, rows * T))
    for i, t in enumerate(tiles):
        im.paste(t, ((i % cols) * T, (i // cols) * T))
    return im, rows


def save(im, path):
    path.parent.mkdir(parents=True, exist_ok=True)
    im.save(path, optimize=False)


# ------------------------------------------------------------------ ground textures
def grass_tile(seed, bias=0.0, shift=0, kind="plain"):
    """Mockup meadow grass: light warm green with a faint dither and plenty of small flower / pebble confetti (the big
    light/dark meadow areas come from the shade layer, so the 32px tile never shows as a repeat).
    kind: plain, tufts, flowers, clover; every kind carries some confetti, flowers the most."""
    v = 0.5 + 0.5 * (pfbm(seed, 11) - 0.5)
    # Per-pixel random threshold, not the 4x4 Bayer matrix: Bayer makes a regular diagonal weave at zoom 2.
    nz = np.random.default_rng(seed * 31 + 7).random((T, T)).astype(np.float32)
    gi = np.clip(((v + bias) * 3 + (nz - 0.5) * 0.5).astype(int), 0, 2) + 1 + shift
    img = to_img(A(PG)[np.clip(gi, 0, 4)])
    d = ImageDraw.Draw(img)
    rng = random.Random(seed * 7 + 1)
    n_tuft = {"plain": 2, "tufts": 6, "flowers": 3, "clover": 4}[kind]
    for _ in range(n_tuft):
        x, y = rng.randrange(3, T - 3), rng.randrange(3, T - 2)
        base = img.getpixel((x, y))
        c = tuple(min(255, int(q * 1.22)) for q in base[:3]) + (255,)
        dc = tuple(int(q * 0.7) for q in base[:3]) + (255,)
        d.point([(x, y), (x - 1, y - 1), (x + 1, y - 1), (x, y - 2)], fill=c)
        d.point([(x, y + 1)], fill=dc)
    n_conf = {"plain": 12, "tufts": 13, "flowers": 20, "clover": 13}[kind]
    for _ in range(n_conf):  # tiny clusters of 1-3 coloured specks
        c = rng.choice(CONFETTI)
        x, y = rng.randrange(2, T - 2), rng.randrange(2, T - 2)
        for _ in range(rng.randint(1, 3)):
            d.point((x + rng.randint(-2, 2), y + rng.randint(-1, 1)), fill=c)
    if kind == "flowers":
        for _ in range(2):
            c = rng.choice(CONFETTI)
            x, y = rng.randrange(3, T - 3), rng.randrange(3, T - 3)
            d.point((x, y + 1), fill=PG[0])
            d.point((x, y), fill=c)
    if kind == "clover":
        for _ in range(7):
            x, y = rng.randrange(2, T - 2), rng.randrange(2, T - 2)
            d.point((x, y), fill=PG[4])
            d.point((x + 1, y + 1), fill=PG[0])
    return img


def soil_tile(seed):
    """Fertile soil: darker, richer grass with warm loam specks and sprouts (not mud)."""
    v = 0.5 + 0.5 * (pfbm(seed, 12) - 0.5)
    gi = pquant(v, 3, 0.0, 0.45)
    rich = [mix(PG[1], M.BANK[0], 0.2), mix(PG[2], M.BANK[1], 0.12),
            mix(PG[2], PG[3], 0.4)]
    img = to_img(A(rich)[gi])
    d = ImageDraw.Draw(img)
    rng = random.Random(seed * 5 + 2)
    for _ in range(11):  # loam crumbs
        x, y = rng.randrange(1, T - 3), rng.randrange(1, T - 2)
        d.line([(x, y), (x + rng.randint(0, 2), y)], fill=M.BANK[rng.randint(0, 1)])
    for _ in range(3):
        d.point((rng.randrange(1, T - 1), rng.randrange(1, T - 1)), fill=M.DIRT[1])
    for _ in range(3):  # tufts, a touch lighter than the ground
        x, y = rng.randrange(3, T - 3), rng.randrange(3, T - 2)
        d.point([(x, y), (x - 1, y - 1), (x + 1, y - 1)], fill=PG[2])
    for _ in range(2):  # sprouts: this is the fertile one
        x, y = rng.randrange(3, T - 3), rng.randrange(4, T - 2)
        d.point((x, y), fill=M.LEAF["green"][3])
        d.point((x, y - 1), fill=M.LEAF["green"][4])
    return img


def forest_tile(seed, bare=False):
    """Forest floor: dark green ground with leaf litter; `bare` (felled tile) adds exposed earth and more leaves."""
    v = 0.5 + 0.6 * (pfbm(seed, 18) - 0.5)
    gi = pquant(v, 2, 0.0, 0.8)
    pal = [mix(M.GRASS[0], (20, 30, 18), 0.2), mix(M.GRASS[0], M.BANK[0], 0.15)]
    img = to_img(A(pal)[gi])
    d = ImageDraw.Draw(img)
    rng = random.Random(seed * 9 + 4)
    if bare:
        for _ in range(3):
            x, y = rng.randrange(2, T - 7), rng.randrange(2, T - 4)
            d.ellipse([x, y, x + rng.randint(3, 6), y + rng.randint(2, 3)], fill=M.BANK[0])
            d.ellipse([x + 1, y, x + 3, y + 1], fill=M.BANK[1])
    leaves = [M.LEAF["autumn"][1], M.LEAF["autumn"][2], M.LEAF["deep"][2], M.LEAF["deep"][1]]
    for _ in range(9 if bare else 5):
        x, y = rng.randrange(1, T - 2), rng.randrange(1, T - 2)
        d.point((x, y), fill=rng.choice(leaves))
        if rng.random() < 0.4:
            d.point((x + 1, y), fill=rng.choice(leaves))
    for _ in range(4):
        d.point((rng.randrange(1, T - 1), rng.randrange(1, T - 1)), fill=M.GRASS[1])
    return img


# Broad meadow shading is computed per tile in world space at map build time (ArtLibrary.shade_image): low-frequency
# value noise from the map seed, no atlas and no period. The manifest carries the look so the loader holds no art data.
def rock_tile(seed):
    """Rock ground (ticket 56): stony grass, a darker grey-green gravel with bare soil patches and pebbles. The
    boulder props on top carry the rock look; the ground only has to read as 'not meadow' for placement."""
    v = 0.5 + 0.6 * (pfbm(seed, 14) - 0.5)
    gi = pquant(v, 3, 0.0, 0.8)
    stone = [mix(PG[0], M.ROCK[1], 0.62), mix(PG[1], M.ROCK[1], 0.66), mix(PG[1], M.ROCK[2], 0.62)]
    img = to_img(A(stone)[gi])
    d = ImageDraw.Draw(img)
    rng = random.Random(seed * 3 + 5)
    for _ in range(3):  # bare dark soil under and between the boulders
        x, y = rng.randrange(1, T - 8), rng.randrange(2, T - 5)
        d.ellipse([x, y, x + rng.randint(4, 7), y + rng.randint(2, 4)], fill=mix(M.BANK[0], M.ROCK[0], 0.35))
    for _ in range(11):  # pebbles
        x, y = rng.randrange(2, T - 4), rng.randrange(2, T - 3)
        d.ellipse([x, y, x + rng.randint(1, 2), y + 1], fill=mix(M.ROCK[2], M.ROCK[3], rng.random()))
        d.point((x, y + 2), fill=M.ROCK[0])
    for _ in range(4):  # a few grass tufts still poking through
        x, y = rng.randrange(3, T - 3), rng.randrange(3, T - 2)
        d.point([(x, y), (x - 1, y - 1)], fill=PG[1])
    return img


def vein_tile(seed):
    img = to_img(A(M.VEIN)[pquant(pfbm(seed, 14), 4)])
    d = ImageDraw.Draw(img)
    rng = random.Random(seed * 11 + 3)
    for _ in range(2):  # glowing cracks, as in the mockup ground
        x, y = rng.randrange(6, 26), rng.randrange(6, 26)
        pts = [(x, y)]
        for _ in range(3):
            x = max(3, min(T - 4, x + rng.randint(-6, 6)))
            y = max(3, min(T - 4, y + rng.randint(-4, 4)))
            pts.append((x, y))
        d.line(pts, fill=M.CRYSTAL[1], width=2)
        d.line(pts, fill=M.CRYSTAL[3])
    return img


def sky_tile(seed):
    img = to_img(A(SKY)[pquant(pfbm(seed, 15), 3) + 1])
    d = ImageDraw.Draw(img)
    rng = random.Random(seed * 13 + 7)
    for _ in range(3):
        x, y = rng.randrange(2, T - 9), rng.randrange(3, T - 3)
        d.line([(x, y), (x + 6, y + 2)], fill=SKY[0])
    for _ in range(8):
        d.point((rng.randrange(1, T - 1), rng.randrange(1, T - 1)), fill=SKY[4])
    for _ in range(3):
        x, y = rng.randrange(4, T - 4), rng.randrange(4, T - 4)
        d.point([(x, y), (x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)], fill=M.CRYSTAL[2])
        d.point((x, y), fill=M.CRYSTAL[4])
    return img


def water_tile(seed, lily=False):
    v = pfbm(seed, 16)
    lvl = 1 + pquant(v, 2)
    rip = pnoise(4, seed + 40) > 0.80
    lvl = np.where(rip, np.minimum(lvl + 1, 3), lvl)
    img = to_img(A(M.WATER)[lvl])
    d = ImageDraw.Draw(img)
    rng = random.Random(seed * 17 + 9)
    for _ in range(3):
        x, y = rng.randrange(2, T - 6), rng.randrange(2, T - 2)
        d.line([(x, y), (x + rng.randint(2, 4), y)], fill=M.WATER[4])
    return img


def lily_pad(seed, flower):
    """A lily pad prop (separate sprite so pads are scattered by hash, not baked into a repeating tile)."""
    rng = random.Random(seed)
    w, h = rng.choice([(10, 6), (12, 7), (9, 6)])
    im = Image.new("RGBA", (w + 4, h + 4))
    d = ImageDraw.Draw(im)
    d.ellipse([1, 1, 1 + w, 1 + h], fill=M.LEAF["green"][1])
    d.ellipse([2, 1, 1 + w - 1, h], fill=M.LEAF["green"][3])
    d.point((1 + w // 2 + rng.randint(1, 2), 1 + h // 2), fill=M.LEAF["green"][1])  # notch
    if flower:
        d.point((w // 2 + 1, h // 2), fill=M.hexc("f4a0c0"))
        d.point((w // 2 + 2, h // 2), fill=M.hexc("f6f0e0"))
    return types.SimpleNamespace(img=im, fw=1, fh=1, glows=[], smoke=[], shadow=None)


def ground_tile(ground, seed):
    """One representative tile of a ground class (used inside transition overlays)."""
    return {"grass": lambda: grass_tile(seed), "forest": lambda: forest_tile(seed),
            "soil": lambda: soil_tile(seed), "rock": lambda: rock_tile(seed), "vein": lambda: vein_tile(seed),
            "sky": lambda: sky_tile(seed), "water": lambda: water_tile(seed)}[ground]()


# ------------------------------------------------------------------ transitions (blob autotile overlays)
def reduce_mask(m):
    """Corner bits only matter when neither adjacent side is set."""
    for corner, a, b in ((BNE, BN, BE), (BSE, BE, BS), (BSW, BS, BW), (BNW, BW, BN)):
        if m & (a | b):
            m &= ~corner
    return m


def blob_set():
    uniq = sorted({reduce_mask(m) for m in range(256)} - {0})
    index = [-1] * 256
    pos = {m: i for i, m in enumerate(uniq)}
    for m in range(256):
        r = reduce_mask(m)
        index[m] = pos[r] if r else -1
    return uniq, index


def edge_dist(m):
    """Distance to the neighbouring ground. Sides are combined with a soft minimum so two touching sides give a
    rounded fillet instead of a square inner corner (no stair steps); lone corners are round (hypot)."""
    k = 0.16
    acc = np.zeros((T, T), dtype=np.float32)
    for bit, dist in ((BN, YS), (BE, T - XS), (BS, T - YS), (BW, XS)):
        if m & bit:
            acc += np.exp(-k * dist)
    for bit, dx, dy in ((BNE, T - XS, YS), (BSE, T - XS, T - YS), (BSW, XS, T - YS), (BNW, XS, YS)):
        if m & bit:
            acc += np.exp(-k * np.hypot(dx, dy))
    if not acc.any():
        return np.full((T, T), 1e9, dtype=np.float32)
    return (-np.log(np.maximum(acc, 1e-30)) / k).astype(np.float32)


def soft_overlay(ground, mask, seed, reach):
    """Ground `ground` bleeding into a lower neighbour: wobbly, ordered-dither edge of ~`reach` px."""
    d = edge_dist(mask)
    wob = 0.65 * pnoise(8, 500 + seed) + 0.35 * pnoise(4, 520 + seed)
    r = reach + (wob - 0.5) * 2 * (reach * 0.85)
    cov = (r - d) + (BAY - 0.5) * RAMP.get(ground, 5.0) > 0
    src = np.array(ground_tile(ground, 3 + seed))
    src[..., 3] = np.where(cov, 255, 0)
    return Image.fromarray(src, "RGBA")


REACH = {"grass": 7, "forest": 7, "soil": 9, "rock": 8, "vein": 9, "sky": 6}
# Width in px of the dithered fade of a transition (rock and vein keep a crisp edge, ground tones blend wide).
RAMP = {"grass": 9.0, "forest": 11.0, "soil": 12.0, "rock": 10.0, "vein": 11.0, "sky": 4.0}


OVERLAY_VARIANTS = 3


def export_overlays(manifest):
    uniq, index = blob_set()
    manifest["overlay_index"] = index
    manifest["overlay_cols"] = 8
    rows_per = (len(uniq) + 7) // 8
    manifest["overlay_rows"] = rows_per
    manifest["overlay_variants"] = OVERLAY_VARIANTS
    manifest["overlays"] = {}
    for gi, g in enumerate(GROUND_ORDER):
        if g in ("water", "grass", "rock", "sky"):  # water shores and rock edges are dual-grid autotiles (ticket 54)
            continue
        im = Image.new("RGBA", (8 * T, OVERLAY_VARIANTS * rows_per * T))
        for v in range(OVERLAY_VARIANTS):  # variants differ in edge wobble so a long border is not one repeated tile
            soft = [soft_overlay(g, m, gi * 10 + v * 100, REACH[g]) for m in uniq]
            a1, _ = pack_atlas(soft, 8)
            im.paste(a1, (0, v * rows_per * T))
        save(im, OUT / "terrain" / f"overlay_{g}.png")
        manifest["overlays"][g] = f"terrain/overlay_{g}.png"


# ---------------------------------------------------------------- dual-grid autotiles (ticket 54)
# A dual cell sits on a map corner and covers a quarter of the four map tiles around it. Its 16 corner
# configurations are indexed by a bit per tile (TL=1, TR=2, BR=4, BL=8) flagging the upper ground (water or
# rock). Lone upper corners are a quarter disc of radius half a tile around the map tile's centre, straight
# borders are a line through the corner, and the two diagonal cases draw the two *lower* corners as rounded
# lobes so the upper ground runs between them: a diagonal shore is a smooth band, never a stair-step. The lobes
# meet the cell's edge midpoints, which is exactly where the neighbouring cell's border crosses, so tiles join
# without a seam. The layers are drawn half a tile up-left in the map view.
AUTOTILE_PAIRS = {
    # pair -> lower grounds that get their own atlas (the upper ground edges onto each of them)
    "water": ["grass", "forest", "soil", "rock", "vein", "sky"],
    "rock": ["grass", "forest", "soil"],
}
AT_UP = {"water": "water", "rock": "rock"}
AT_R = T / 2.0


def at_dist(mask):
    """Signed distance in px to the autotile edge, positive inside the upper ground."""
    corners = [(1, 0.0, 0.0), (2, float(T), 0.0), (4, float(T), float(T)), (8, 0.0, float(T))]
    ups = [(x, y) for b, x, y in corners if mask & b]
    lows = [(x, y) for b, x, y in corners if not mask & b]
    if not ups or not lows:  # all land / all water: the map view never draws these cells
        return np.full((T, T), -1e9 if not ups else 1e9, np.float32)
    if len(ups) == 1:  # lone upper corner: round lobe around that map tile's centre
        x, y = ups[0]
        return AT_R - np.hypot(XS - x, YS - y)
    if len(ups) == 3:  # lone lower corner: the upper ground wraps a round notch around it
        x, y = lows[0]
        return np.hypot(XS - x, YS - y) - AT_R
    (ax, ay), (bx, by) = ups
    if ax == bx:  # left or right half
        return (T / 2.0 - XS) if ax == 0.0 else (XS - T / 2.0)
    if ay == by:  # top or bottom half
        return (T / 2.0 - YS) if ay == 0.0 else (YS - T / 2.0)
    # diagonal: both lower corners are rounded lobes and the upper ground flows between them
    return np.minimum(np.hypot(XS - lows[0][0], YS - lows[0][1]),
                      np.hypot(XS - lows[1][0], YS - lows[1][1])) - AT_R


def at_cover(t):
    """Ordered-dither coverage: 255 where the fraction t of pixels should be kept (BAY is seamless across tiles)."""
    return np.where(BAY < np.clip(t, 0.0, 1.0), 255, 0).astype(np.uint8)


WATER_BANDS = [(9.5, 13.0, M.WATER[2]), (6.5, 9.5, M.WATER[3]), (4.5, 6.5, M.WATER[4]),
               (3.0, 4.5, M.WATER[5]), (2.0, 3.0, M.BANK[2]), (1.0, 2.0, M.BANK[1]),
               (0.0, 1.0, M.BANK[0])]


def _quadrants(mask):
    """Boolean per pixel: does the atlas quadrant around this pixel belong to a tile flagged in `mask`?
    Atlas quadrants are TL=1, TR=2, BR=4, BL=8, matching the map tiles around the corner."""
    out = np.zeros((T, T), bool)
    for b, sx, sy in ((1, 0, 0), (2, T // 2, 0), (4, T // 2, T // 2), (8, 0, T // 2)):
        if mask & b:
            out[sy:sy + T // 2, sx:sx + T // 2] = True
    return out


def at_tile(mask, pair, ground, seed):
    """One dual-cell tile: the upper ground on its side of the smooth edge, `ground` on the other, with a soft
    bank/edge band. The water side fades into the base water tile between the bands; the water tile's own land
    side (its rounded-off quarters) is filled with `ground`, and land tiles are left to their base ground."""
    d = at_dist(mask)
    wob = (pnoise(8, 410 + seed) - 0.5) * 3.0  # same seamless field in every tile: bands wobble, edges join
    db = d + wob * np.clip(1.0 - np.abs(d) / 22.0, 0.0, 1.0)
    rgb = np.zeros((T, T, 3), np.uint8)
    alpha = np.zeros((T, T), np.uint8)
    up = np.array(ground_tile(AT_UP[pair], 3 + seed))
    low = np.array(ground_tile(ground, 5 + seed))
    land = db <= 0.0
    # The low ground only fills the pair tiles' own quarters (their rounded-off corners). Every other quarter
    # belongs to a neighbour tile whose base ground is already right, and one atlas ground stamped over mixed
    # corners (water + rock + soil) drew a square of the wrong ground there.
    fill = land & _quadrants(mask)
    rgb[fill] = low[fill, :3]
    land_a = np.where(db > -7.0, 255, at_cover((db + 11.0) / 4.0))  # bank band, gone ~11 px from the edge
    alpha[fill] = land_a[fill]
    upper = db > 0.0
    if pair == "water":
        rgb[upper] = up[upper, :3]
        alpha[upper] = at_cover((12.5 - db) / 3.0)[upper]
        for lo, hi, c in WATER_BANDS:
            band = (db > lo) & (db <= hi) & upper
            rgb[band] = c[:3]
            alpha[band] = at_cover((12.5 - db) / 3.0)[band] if lo >= 9.0 else 255
        rim = (db > -1.3) & fill  # dark waterline on the land side
        rgb[rim] = (rgb[rim].astype(np.float32) * 0.78).astype(np.uint8)
    else:  # rock: opaque rock, dithered soft edge creeping onto the lower ground as the old per-tile overlay did
        rgb[upper] = up[upper, :3]
        alpha[upper] = at_cover((11.0 - db) / 3.0)[upper]
        creep = land & (db > -8.0)
        a = at_cover(1.0 + db / 8.0)  # dense at the edge, thinning outward
        rgb[creep] = np.where((a[creep] == 255)[:, None], up[creep, :3], rgb[creep])
        alpha[creep] = np.maximum(alpha[creep], a[creep])
    out = np.dstack([rgb, alpha])
    return Image.fromarray(out, "RGBA")


def export_autotiles(manifest):
    manifest["autotiles"] = {}
    for pair, grounds in AUTOTILE_PAIRS.items():
        files = {}
        for gi, g in enumerate(grounds):
            tiles = [at_tile(m, pair, g, gi * 13 + 120) for m in range(16)]
            im, _ = pack_atlas(tiles, 4)
            rel = f"terrain/{'shore' if pair == 'water' else 'rockedge'}_{g}.png"
            save(im, OUT / rel)
            files[g] = rel
        manifest["autotiles"][pair] = {"grounds": grounds, "files": files, "cols": 4, "rows": 4}


# ------------------------------------------------------------------ blight and fouling (soft tile states)
BLIGHT = [(48, 36, 70), (80, 58, 112), (108, 80, 146), (150, 120, 190)]  # saturated violet, as the village mockup
FOUL = [(70, 66, 30), (96, 86, 36), (118, 104, 46), (140, 122, 58)]  # murky olive-brown, tints the water tile
STATE_ALPHA = {"blight": 232, "fouled": 104}  # fouled stays translucent so water ripples and lily pads read through


def state_tile(seed, pal, base_alpha):
    """Fill tile of a tile state (blighted ground, fouled water): saturated tint with darker pits and speckle.
    Opaque enough to read as a purple blob; the soft edge comes from state_edge on the neighbours."""
    v = pfbm(seed, 14)
    nz = np.random.default_rng(seed * 5 + 1).random((T, T)).astype(np.float32)
    gi = np.clip(((v * 0.9 + 0.05) * 3 + (nz - 0.5) * 0.6).astype(int), 0, 2)
    rgb = A(pal)[gi]
    alpha = np.full((T, T), base_alpha, dtype=np.uint8)
    img = to_img(rgb, alpha)
    d = ImageDraw.Draw(img)
    rng = random.Random(seed * 13 + 5)
    for _ in range(4):  # darker pits, as in the mockup
        x, y = rng.randrange(2, T - 7), rng.randrange(2, T - 6)
        d.ellipse([x, y, x + rng.randint(2, 4), y + rng.randint(2, 3)], fill=pal[0] + (base_alpha,))
    for _ in range(16):
        d.point((rng.randrange(1, T - 1), rng.randrange(1, T - 1)),
                fill=rng.choice([pal[0], pal[0], pal[3]]) + (base_alpha,))
    return img


def state_edge(pal, base_alpha, mask, seed):
    """Tint bleeding from the 8 neighbours flagged in `mask` into this clear tile: wobbly dithered fade, the same
    texture as the fill tile so the blob has no seam at the tile border."""
    d = edge_dist(mask)
    wob = 0.65 * pnoise(8, 700 + seed) + 0.35 * pnoise(4, 720 + seed)
    r = 9 + (wob - 0.5) * 12
    nz = np.random.default_rng(seed * 3 + 11).random((T, T)).astype(np.float32)
    cov = (r - d) + (nz - 0.5) * 9.0 > 0
    src = np.array(state_tile(900 + seed % 4, pal, base_alpha))
    src[..., 3] = np.where(cov, src[..., 3], 0)
    return Image.fromarray(src, "RGBA")


def export_states(manifest):
    uniq, index = blob_set()
    manifest["states"] = {}
    for name, pal, seed0 in (("blight", BLIGHT, 900), ("fouled", FOUL, 950)):
        al = STATE_ALPHA[name]
        im, rows = pack_atlas([state_tile(seed0 + i, pal, al) for i in range(4)], 4)
        save(im, OUT / "terrain" / f"{name}.png")
        edges = [state_edge(pal, al, m, seed0 + k) for k, m in enumerate(uniq)]
        eim, erows = pack_atlas(edges, 8)
        save(eim, OUT / "terrain" / f"{name}_edge.png")
        manifest["states"][name] = {"file": f"terrain/{name}.png", "cols": 4, "rows": 1,
                                    "edge_file": f"terrain/{name}_edge.png", "edge_cols": 8, "edge_rows": erows}


def sparkle(seed, big):
    """Lumen sparkle prop for blighted ground: a small cyan cross with a pale core (static, sits in the Fx layer)."""
    im = Image.new("RGBA", (9, 9) if big else (5, 5))
    d = ImageDraw.Draw(im)
    c = 4 if big else 2
    arm = 3 if big else 1
    cy = M.CRYSTAL[2][:3] + (170,)
    d.line([(c - arm, c), (c + arm, c)], fill=cy)
    d.line([(c, c - arm), (c, c + arm)], fill=cy)
    d.point((c, c), fill=M.CRYSTAL[4])
    return types.SimpleNamespace(img=im, fw=1, fh=1, glows=[(c, c, 5 if big else 3, M.CRYSTAL[3])], smoke=[], shadow=None)


# ------------------------------------------------------------------ construction site art
SCAFFOLD_TIERS = [40, 64, 88]  # pole heights in px; PlacementView picks the smallest that covers the building sprite


def scaffold_image(fw, fh, tier):
    """Wooden scaffold for a fw x fh footprint: front poles on the footprint's lower edge, shorter back poles, plank
    decks, cross braces, a rope and a plank stack. Bottom edge of the image = bottom edge of the footprint."""
    W = fw * T
    H = tier + 10
    im = Image.new("RGBA", (W, H))
    d = ImageDraw.Draw(im)
    wd = [M.WOOD[1], M.WOOD[2], M.WOOD[3], M.WOOD[4]]
    back = H - 1 - fh * T // 2  # back poles stand further up the image (the plot's depth)
    def pole(x, y1, y0, lit):
        d.line([(x, y1), (x, y0)], fill=wd[0], width=3)
        d.line([(x, y1), (x, y0)], fill=wd[2 if lit else 1], width=1)
    bt = max(8, back - (tier - 6))
    for x in (6, W - 7):
        pole(x, back, bt, False)
    d.line([(6, bt + 5), (W - 7, bt + 5)], fill=wd[1], width=2)
    xs = (2, W - 3)
    for x in xs:
        pole(x, H - 2, 2, True)
    levels = [H - 2 - int((tier - 2) * k / 3.0) for k in (1, 2, 3)]
    for i, y in enumerate(levels):  # cross planks (decks) between the front poles, with plank lines
        M.R(d, xs[0] - 1, y, xs[1] + 1, y + 2, wd[2])
        d.line([(xs[0] - 1, y), (xs[1] + 1, y)], fill=wd[3])
        d.line([(xs[0] - 1, y + 2), (xs[1] + 1, y + 2)], fill=wd[0])
    d.line([(xs[0], H - 2), (xs[1], levels[1])], fill=wd[2], width=1)  # diagonal braces
    d.line([(xs[1], H - 2), (xs[0], levels[1])], fill=wd[1], width=1)
    d.line([(xs[0] + 4, levels[2]), (xs[0] + 4, levels[2] + 6)], fill=M.hexc("c8b890"))  # rope
    d.point((xs[0] + 4, levels[2] + 7), fill=wd[0])
    return im


def site_plot(fw, fh):
    """Trodden dirt plot with a plank stack and a few stones, drawn under the rising building."""
    W, H = fw * T, fh * T
    rng = np.random.default_rng(fw * 10 + fh)
    base = np.array([(110, 84, 52), (128, 98, 60), (92, 68, 42)], dtype=np.uint8)
    n = rng.random((H, W))
    idx = np.where(n < 0.15, 2, np.where(n > 0.78, 1, 0))
    out = np.zeros((H, W, 4), dtype=np.uint8)
    out[..., :3] = base[idx]
    out[..., 3] = 255
    yy, xx = np.mgrid[0:H, 0:W]
    edge = np.minimum(np.minimum(xx, W - 1 - xx), np.minimum(yy, H - 1 - yy)).astype(np.float32)
    keep = edge + (rng.random((H, W)) - 0.5) * 7 > 1.5  # ragged outline
    out[..., 3] = np.where(keep, 235, 0)
    im = Image.fromarray(out, "RGBA")
    d = ImageDraw.Draw(im)
    for k in range(3):  # stacked planks in a corner
        x, y = W - 12, H - 6 - k * 2
        M.R(d, x, y, x + 9, y + 1, M.WOOD[3 - k % 2])
        d.line([(x, y + 1), (x + 9, y + 1)], fill=M.WOOD[1])
    for _ in range(max(2, fw * fh)):
        x, y = int(rng.integers(3, W - 5)), int(rng.integers(3, H - 4))
        d.ellipse([x, y, x + 2, y + 1], fill=(150, 142, 130, 255))
    return im


def export_sites(manifest):
    manifest["site"] = {"tiers": SCAFFOLD_TIERS, "scaffold": {}, "plot": {}}
    for fw in (1, 2, 3):
        for fh in (1, 2, 3):
            rel = f"sites/plot_{fw}x{fh}.png"
            save(site_plot(fw, fh), OUT / rel)
            manifest["site"]["plot"][f"{fw}x{fh}"] = rel
            for tier in SCAFFOLD_TIERS:
                rel = f"sites/scaffold_{fw}x{fh}_{tier}.png"
                save(scaffold_image(fw, fh, tier), OUT / rel)
                manifest["site"]["scaffold"][f"{fw}x{fh}_{tier}"] = rel


# ------------------------------------------------------------------ terrain tiles
def export_terrain(manifest):
    tiles = {}
    kinds = ["plain", "plain", "tufts", "flowers", "clover"]
    tiles["grass"] = ([[grass_tile(100 + i, kind=k) for i, k in enumerate(kinds)]], [0, 0, 1, 1, 2, 2, 2, 3, 4])
    tiles["forest"] = ([[forest_tile(200 + i) for i in range(4)]], [0, 1, 2, 3])
    tiles["stump"] = ([[forest_tile(300 + i, bare=True) for i in range(4)]], [0, 1, 2, 3])
    tiles["fertile_soil"] = ([[soil_tile(400 + i) for i in range(4)]], [0, 1, 2, 3])
    tiles["rock"] = ([[rock_tile(500 + i) for i in range(4)]], [0, 1, 2, 3])
    tiles["lumen_vein"] = ([[vein_tile(600 + i) for i in range(4)]], [0, 1, 2, 3])
    tiles["skystone"] = ([[sky_tile(700 + i) for i in range(3)]], [0, 1, 2])
    tiles["water"] = ([[water_tile(800 + i) for i in range(5)]], [0, 0, 1, 1, 2, 2, 3, 3, 4])
    manifest["ground_order"] = GROUND_ORDER
    manifest["shade"] = {"grounds": ["grass", "soil"], "cells": [14.0, 7.0, 3.5],
                         "weights": [0.5, 0.33, 0.17], "dark": list(PG[0][:3]) + [105],
                         "light": [190, 228, 108, 130], "dark_below": 0.46, "light_above": 0.56, "ramp": 0.2}
    manifest["terrain"] = {}
    for tid, (families, pick) in tiles.items():
        cols = len(families[0])
        flat = [t for row in families for t in row]
        im, rows = pack_atlas(flat, cols)
        save(im, OUT / "terrain" / f"{tid}.png")
        manifest["terrain"][tid] = {"file": f"terrain/{tid}.png", "cols": cols, "rows": rows,
                                    "ground": TERRAIN_GROUND[tid], "pick": pick}


# ------------------------------------------------------------------ roads
ROAD_SEGS = {1: ((16, 16), (16, -24)), 2: ((16, 16), (56, 16)), 4: ((16, 16), (16, 56)), 8: ((16, 16), (-24, 16))}


def road_tile(level, variant, mask):
    """Dirt / paved road tile for a connection mask (N=1, E=2, S=4, W=8), mockup width and cobble flecks."""
    wx = XS + (pnoise(16, 801) - 0.5) * 6
    wy = YS + (pnoise(16, 802) - 0.5) * 6
    rd = np.full((T, T), 99.0, dtype=np.float32)
    for bit, (a, b) in ROAD_SEGS.items():
        if mask & bit:
            rd = np.minimum(rd, M.seg_dist(wx, wy, a, b))
    if mask == 0:
        rd = np.hypot(wx - 16, wy - 16) + 2.5
    half = 10.0
    road = rd < half + (BAY - 0.5) * 1.6
    rng = random.Random(900 + variant * 31 + level * 7)
    if level == 1:
        v = pfbm(910 + variant, 17)
        rgb = A(M.DIRT)[pquant(v, 3) + 1]
        layer = Image.new("RGBA", (3 * T, 3 * T))
        d = ImageDraw.Draw(layer)
        geo = random.Random(77)  # fixed cobble layout shared by all variants so neighbours line up
        for k in range(6):
            y0 = round(k * T / 6 + 2)
            for j in range(5):
                x0 = round(j * T / 5 + (k % 2) * T / 10)
                jx, jy = x0 + geo.randint(-1, 1), y0 + geo.randint(-1, 1)
                c = rng.choice(M.COBBLE[1:])
                for ox in (0, T, 2 * T):
                    for oy in (0, T, 2 * T):
                        X, Y = jx + ox, jy + oy
                        d.ellipse([X - 2, Y - 1, X + 2, Y + 2], fill=M.COBBLE[0])
                        d.ellipse([X - 2, Y - 2, X + 1, Y + 1], fill=c)
        cob = np.array(layer.crop((T, T, 2 * T, 2 * T)))
        use = (cob[..., 3] > 0) & (rd < 8.5)
        rgb = rgb.copy()
        rgb[use] = cob[..., :3][use]
    else:
        rgb = np.zeros((T, T, 3), dtype=np.uint8)
        rgb[:] = M.COBBLE[0][:3]
        layer = Image.new("RGBA", (3 * T, 3 * T))
        d = ImageDraw.Draw(layer)
        for k in range(8):
            y0 = k * 4 + 1
            for j in range(4):
                x0 = j * 8 + (k % 2) * 4
                c = rng.choice(M.COBBLE[1:])
                for ox in (0, T, 2 * T):
                    for oy in (0, T, 2 * T):
                        X, Y = x0 + ox, y0 + oy
                        d.rectangle([X, Y, X + 5, Y + 2], fill=c)
                        d.line([(X, Y), (X + 5, Y)], fill=M.COBBLE[3])
        cob = np.array(layer.crop((T, T, 2 * T, 2 * T)))
        inner = rd < half - 2.0
        rgb[inner & (cob[..., 3] > 0)] = cob[..., :3][inner & (cob[..., 3] > 0)]
        # stone variation: a few darker and lighter slabs, plus a shaded mortar band next to the kerb
        vary = pfbm(950 + variant, 17)
        slab = inner & (vary < 0.35)
        rgb[slab] = (rgb[slab].astype(np.int32) * 0.86).astype(np.uint8)
        lite = inner & (vary > 0.72)
        rgb[lite] = np.minimum(rgb[lite].astype(np.int32) * 1.06 + 6, 255).astype(np.uint8)
        shade = inner & (rd >= half - 3.5)
        rgb[shade] = (rgb[shade].astype(np.int32) * 0.88).astype(np.uint8)
        curb = road & ~inner
        rgb[curb] = M.STONE[1][:3]
        rgb[curb & (rd < half - 0.8)] = M.STONE[2][:3]  # lighter kerb top, darker outer lip
    alpha = np.where(road, 255, 0)
    return to_img(rgb, alpha)


def export_roads(manifest):
    manifest["roads"] = {}
    for level, name in ((1, "dirt"), (2, "paved")):
        tiles = [road_tile(level, v, m) for v in range(2) for m in range(16)]
        im, rows = pack_atlas(tiles, 16)
        save(im, OUT / "roads" / f"{name}.png")
        manifest["roads"][str(level)] = {"file": f"roads/{name}.png", "cols": 16, "rows": rows}


# ------------------------------------------------------------------ irrigation channels
def channel_tile(flowing, mask):
    """Narrow dug ditch for a connection mask (N=1, E=2, S=4, W=8): earth banks, and a water bed with a bright
    centre line when the channel flows (it reaches the river), a dry dark earth bed when it does not."""
    rd = np.full((T, T), 99.0, dtype=np.float32)
    for bit, (a, b) in ROAD_SEGS.items():
        if mask & bit:
            rd = np.minimum(rd, M.seg_dist(XS, YS, a, b))
    if mask == 0:
        rd = np.hypot(XS - 16, YS - 16) + 1.5
    outer = rd < 6.5 + (BAY - 0.5) * 1.0
    bed = rd < 4.0
    mid = rd < 1.6
    rgb = np.zeros((T, T, 3), dtype=np.uint8)
    rgb[:] = M.DIRT[1][:3]
    rim = outer & ~bed
    rgb[rim] = (M.DIRT[3] if flowing else M.DIRT[2])[:3]
    if flowing:
        rgb[bed] = M.WATER[2][:3]
        rgb[mid] = M.WATER[4][:3]
        rgb[bed & (BAY > 0.6) & ~mid] = M.WATER[3][:3]
    else:
        rgb[bed] = M.DIRT[0][:3]
        rgb[mid] = M.DIRT[1][:3]
    return to_img(rgb, np.where(outer, 255, 0))


def export_channels(manifest):
    manifest["channels"] = {}
    for key, flowing in (("dry", False), ("flowing", True)):
        tiles = [channel_tile(flowing, m) for m in range(16)]
        im, rows = pack_atlas(tiles, 16)
        save(im, OUT / "channels" / f"{key}.png")
        manifest["channels"][key] = {"file": f"channels/{key}.png", "cols": 16, "rows": rows}


# ------------------------------------------------------------------ rail track and trains (ticket 37c)
ARMS = {1: (0, -1), 2: (1, 0), 4: (0, 1), 8: (-1, 0)}  # N, E, S, W as (dx, dy); same bits as roads


def track_tile(mask, crossing=False):
    """Rails on wooden sleepers over gravel ballast, for a connection mask (N=1, E=2, S=4, W=8). A tile with one or
    no neighbour is drawn as a straight piece along its axis (the depot or the open end sits there). Corners are
    mitered rails; a T is two corners; a cross lets both lines run through. Roads and channels never share a tile
    with track in the plain tile. crossing=True (ticket 67) draws only what lies over a road: plank infill between and
    just outside the rails plus the two rails, on transparent pixels, for the track layer to sit over the road tile."""
    if mask in (0, 2, 8):
        mask = 2 | 8
    elif mask in (1, 4):
        mask = 1 | 4
    px = XS - T / 2.0
    py = YS - T / 2.0
    ix = np.floor(XS).astype(int)
    iy = np.floor(YS).astype(int)
    rd = np.full((T, T), 99.0, dtype=np.float32)
    for bit, (a, b) in ROAD_SEGS.items():
        if mask & bit:
            rd = np.minimum(rd, M.seg_dist(XS, YS, a, b))
    ballast = rd < 9.5 + (BAY - 0.5) * 1.6
    v = pfbm(1300, 17)
    gravel = np.array([M.hexc("4a4238"), M.hexc("5e5548"), M.hexc("756b5c"), M.hexc("8a806e")], dtype=np.uint8)[:, :3]
    rgb = gravel[pquant(v, 4, 0.0, 0.9)]
    sleeper = np.zeros((T, T), dtype=bool)
    plank = np.zeros((T, T), dtype=bool)
    rail = np.zeros((T, T), dtype=np.int8)  # 1 outer rail pixel, 2 inner (lit) rail pixel
    for bit, (ax, ay) in ARMS.items():
        if not mask & bit:
            continue
        lx, ly = -ay, ax
        u = px * ax + py * ay
        w = px * lx + py * ly
        axis = iy if ax == 0 else ix
        sleeper |= (u > 0) & (np.abs(w) < 7.5) & ((axis % 8 == 2) | (axis % 8 == 3) | (axis % 8 == 4))
        plank |= (u > -5.0) & (np.abs(w) < 7.5)
        for side in (-1, 1):
            perp = ARMS_BIT(side * lx, side * ly)
            lo = 3.0 if (mask != 15 and mask & perp) else -5.0
            on = (u >= lo) & (np.abs(w - side * 3.9) < 1.3)
            lit = on & (np.abs(w) < 4.0)
            rail[on] = np.maximum(rail[on], 1)
            rail[lit] = 2
    rgb = rgb.copy()
    if crossing:
        # Planks laid along the road between and beside the rails; the plain sleepers' bands are skipped.
        seam = np.zeros((T, T), dtype=bool)
        for bit, (ax, ay) in ARMS.items():
            if mask & bit:
                seam |= ((ix if ax == 0 else iy) % 4 == 0)
        rgb[plank] = M.WOOD[2][:3]
        rgb[plank & seam] = M.WOOD[1][:3]
        rgb[plank & (BAY > 0.5) & ~seam] = M.WOOD[3][:3]
        sleeper = plank
        ballast = np.zeros((T, T), dtype=bool)
    else:
        rgb[sleeper] = M.WOOD[2][:3]
        rgb[sleeper & (BAY > 0.5)] = M.WOOD[3][:3]
        rgb[sleeper & (np.abs(iy % 8 - 4) == 0) & (np.abs(ix % 8 - 4) == 0)] = M.WOOD[1][:3]
    rgb[rail == 1] = M.IRON[1][:3]
    rgb[rail == 2] = M.IRON[4][:3]
    return to_img(rgb, np.where(ballast | sleeper | (rail > 0), 255, 0))


def ARMS_BIT(dx, dy):
    for bit, v in ARMS.items():
        if v == (int(round(dx)), int(round(dy))):
            return bit
    return 0


TRAIN_CELL = (32, 32)
TRAIN_FOOT = (16, 20)  # the point of a cell that sits on the track-tile centre
TRAIN_DIRS = ["e", "w", "s", "n"]
TRAIN_CAR_GAP = 0.95  # tiles between car centres


def _wheel(d, x, y):
    M.R(d, x, y, x + 3, y + 3, M.IRON[0])
    M.R(d, x + 1, y + 1, x + 2, y + 2, M.IRON[3])


def train_car(kind, facing):
    """32x32 cell. 'e'/'w' are profile views (w is the mirror of e), 's'/'n' the front/back of the loco and the top of
    a wagon. kind: loco | wagon."""
    im = Image.new("RGBA", TRAIN_CELL)
    d = ImageDraw.Draw(im)
    R = M.R
    if facing in ("e", "w"):
        if kind == "loco":
            R(d, 3, 19, 28, 21, M.IRON[1])
            R(d, 11, 11, 28, 19, M.TEAL[1])
            R(d, 11, 11, 28, 12, M.TEAL[3])
            R(d, 11, 18, 28, 19, M.TEAL[0])
            R(d, 14, 14, 15, 16, M.BRASS[2])
            R(d, 22, 14, 23, 16, M.BRASS[2])
            R(d, 26, 11, 29, 19, M.IRON[1])
            R(d, 29, 14, 30, 16, M.WARM)
            R(d, 25, 5, 27, 11, M.IRON[1])
            R(d, 24, 4, 28, 5, M.BRASS[3])
            R(d, 17, 8, 20, 11, M.BRASS[2])
            R(d, 18, 8, 19, 8, M.BRASS[3])
            R(d, 3, 7, 11, 19, M.hexc("8a3a2e"))
            R(d, 3, 7, 11, 8, M.hexc("b0503e"))
            R(d, 2, 5, 12, 6, M.IRON[2])
            R(d, 5, 10, 8, 14, M.WARM)
            R(d, 5, 10, 8, 10, M.BRASS[1])
            for x in (4, 12, 21):
                _wheel(d, x, 21)
        else:
            R(d, 2, 19, 29, 21, M.IRON[1])
            R(d, 2, 11, 29, 19, M.WOOD[2])
            for x in range(6, 29, 6):
                R(d, x, 12, x, 19, M.WOOD[1])
            R(d, 2, 11, 29, 12, M.WOOD[4])
            R(d, 2, 18, 29, 19, M.WOOD[1])
            R(d, 4, 8, 12, 11, M.BRASS[1])  # load: sacks and crates
            R(d, 4, 8, 12, 8, M.BRASS[3])
            R(d, 15, 7, 24, 11, M.WOOD[3])
            R(d, 15, 7, 24, 7, M.WOOD[4])
            R(d, 19, 7, 19, 11, M.WOOD[1])
            for x in (5, 22):
                _wheel(d, x, 21)
        if facing == "w":
            im = im.transpose(Image.FLIP_LEFT_RIGHT)
    else:
        down = facing == "s"
        if kind == "loco":
            R(d, 10, 9, 21, 22, M.TEAL[1] if down else M.hexc("8a3a2e"))
            R(d, 10, 9, 21, 11, M.TEAL[3] if down else M.hexc("b0503e"))
            R(d, 9, 7, 22, 8, M.IRON[2])
            if down:
                d.ellipse([12, 13, 19, 20], fill=M.IRON[1])
                R(d, 15, 15, 16, 18, M.IRON[3])
                R(d, 15, 11, 16, 12, M.WARM)
                R(d, 14, 3, 17, 7, M.IRON[1])
                R(d, 13, 2, 18, 3, M.BRASS[3])
            else:
                R(d, 13, 13, 18, 18, M.WARM)
                R(d, 13, 13, 18, 13, M.BRASS[1])
            for x in (7, 22):
                R(d, x, 17, x + 2, 24, M.IRON[0])
                R(d, x + 1, 18, x + 1, 23, M.IRON[3])
        else:
            R(d, 9, 3, 22, 28, M.WOOD[1])
            R(d, 10, 4, 21, 27, M.WOOD[2])
            for y in range(7, 27, 5):
                R(d, 10, y, 21, y, M.WOOD[1])
            R(d, 10, 4, 21, 4, M.WOOD[4])
            R(d, 10, 27, 21, 27, M.WOOD[1])
            R(d, 11, 8, 17, 13, M.BRASS[1])
            R(d, 11, 8, 17, 8, M.BRASS[3])
            R(d, 14, 17, 20, 22, M.WOOD[3])
            R(d, 14, 17, 20, 17, M.WOOD[4])
    return M.sel_outline(im)


def export_rail(manifest):
    tiles = [track_tile(m) for m in range(16)]
    im, rows = pack_atlas(tiles, 16)
    save(im, OUT / "rail" / "track.png")
    tiles = [track_tile(m, True) for m in range(16)]
    im, rows = pack_atlas(tiles, 16)
    save(im, OUT / "rail" / "crossing.png")
    cw, ch = TRAIN_CELL
    atlas = Image.new("RGBA", (cw * len(TRAIN_DIRS), ch * 2))
    for r, kind in enumerate(("loco", "wagon")):
        for c, facing in enumerate(TRAIN_DIRS):
            atlas.alpha_composite(train_car(kind, facing), (c * cw, r * ch))
    save(atlas, OUT / "rail" / "train.png")
    manifest["rail"] = {
        "track": {"file": "rail/track.png", "cols": 16, "rows": rows},
        "crossing": {"file": "rail/crossing.png", "cols": 16, "rows": rows},
        "train": {"file": "rail/train.png", "cell": list(TRAIN_CELL), "foot": list(TRAIN_FOOT),
                  "dirs": TRAIN_DIRS, "kinds": ["loco", "wagon"], "gap": TRAIN_CAR_GAP, "cars": ["loco", "wagon", "wagon"]},
    }


def export_airship(manifest):
    """Airship sprite plus its soft ground shadow (ticket 68); east-facing, the view mirrors it for west."""
    sp = M.airship_sprite()
    save(sp, OUT / "airship" / "airship.png")
    w, h = sp.size
    sh = Image.new("RGBA", (w, 12))
    ImageDraw.Draw(sh).ellipse([6, 2, w - 6, 9], fill=(8, 10, 24, 90))
    ImageDraw.Draw(sh).ellipse([12, 4, w - 12, 8], fill=(8, 10, 24, 50))
    save(sh, OUT / "airship" / "shadow.png")
    manifest["airship"] = {"file": "airship/airship.png", "shadow": "airship/shadow.png", "cell": [w, h],
                           "shadow_cell": [w, 12], "foot": [w // 2, 14]}


# ------------------------------------------------------------------ sprites (props and buildings)
def shadow_image(sp, bx, by):
    W, H = sp.img.size
    wf, hh = sp.shadow
    w = W * wf
    cx = W / 2 + w * 0.12
    box = [cx - w / 2, H - 1 - hh * 0.6, cx + w / 2 + hh * 0.6, H - 1 + hh * 0.4]
    x0, y0 = math.floor(box[0]), math.floor(box[1])
    x1, y1 = math.ceil(box[2]), math.ceil(box[3])
    im = Image.new("RGBA", (x1 - x0 + 2, y1 - y0 + 2))
    ImageDraw.Draw(im).ellipse([box[0] - x0, box[1] - y0, box[2] - x0, box[3] - y0], fill=(4, 6, 18, 84))
    return im, (x0 - bx, y0 - by)


def fx_image(sp, bx, by):
    """Lantern/crystal glows and chimney smoke exactly as the scene renderer composites them."""
    W, H = sp.img.size
    if not sp.glows and not sp.smoke:
        return None, None
    mg = max([r for _, _, r, _ in sp.glows] + [0]) + 34
    size = (W + 2 * mg, H + 2 * mg)
    smoke = Image.new("RGBA", size)
    sd = ImageDraw.Draw(smoke)
    for x, y in sp.smoke:
        for k in range(4):
            r = 2 + k
            cx, cy = mg + x + int(math.sin(k * 1.3) * 3) + k, mg + y - k * 6
            sd.ellipse([cx - r, cy - r, cx + r, cy + r], fill=(235, 235, 240, 150 - k * 32))
    glow = Image.new("RGBA", size)
    for gx, gy, r, c in sp.glows:
        glow.alpha_composite(M.glow_img(r, c), (mg + gx - r, mg + gy - r))
    smoke.alpha_composite(glow)
    box = smoke.getbbox()
    if box is None:
        return None, None
    return smoke.crop(box), (box[0] - mg - bx, box[1] - mg - by)


def export_sprite(sp, rel, extra=None):
    W, H = sp.img.size
    bx, by = W // 2, H - 1
    save(sp.img, OUT / rel)
    e = {"file": rel, "w": W, "h": H, "base": [bx, by], "footprint": [sp.fw, sp.fh]}
    if sp.shadow:
        sh, off = shadow_image(sp, bx, by)
        srel = rel.replace(".png", "_shadow.png")
        save(sh, OUT / srel)
        e["shadow"] = {"file": srel, "offset": list(off)}
    fx, foff = fx_image(sp, bx, by)
    if fx is not None:
        frel = rel.replace(".png", "_fx.png")
        save(fx, OUT / frel)
        e["fx"] = {"file": frel, "offset": list(foff)}
    if extra:
        e.update(extra)
    return e


def stump():
    im = Image.new("RGBA", (18, 14))
    d = ImageDraw.Draw(im)
    d.ellipse([1, 8, 16, 13], fill=M.BARK[1])
    M.R(d, 3, 4, 14, 10, M.BARK[2])
    M.R(d, 3, 4, 5, 10, M.BARK[3])
    M.R(d, 12, 4, 14, 10, M.BARK[1])
    d.ellipse([3, 1, 14, 7], fill=M.BARK[1])
    d.ellipse([4, 2, 13, 6], fill=M.hexc("d8b07a"))
    d.ellipse([6, 3, 11, 5], fill=M.hexc("a87a4a"))
    d.point((8, 4), fill=M.BARK[1])
    return M.Sprite(im, shadow=(0.9, 4))


PROPS = {
    "oak_green_0": lambda: M.oak(1011, 0.9), "oak_green_1": lambda: M.oak(1012, 1.0),
    "oak_green_2": lambda: M.oak(1013, 1.1), "oak_green_3": lambda: M.oak(1014, 1.0),
    "oak_autumn_0": lambda: M.oak(1021, 0.95, "autumn"), "oak_autumn_1": lambda: M.oak(1022, 1.1, "autumn"),
    "oak_deep_0": lambda: M.oak(1031, 1.0, "deep"), "oak_lumen_0": lambda: M.oak(99, 1.35, "lumen"),
    "pine_0": lambda: M.pine(1041, 0.9), "pine_1": lambda: M.pine(1042, 1.0), "pine_2": lambda: M.pine(1043, 1.1),
    "boulder_0": lambda: M.boulder(1051, 0.8), "boulder_1": lambda: M.boulder(1052, 1.0),
    "boulder_2": lambda: M.boulder(1053, 1.15), "boulder_3": lambda: M.boulder(1054, 1.3),
    "boulder_4": lambda: M.boulder(1055, 0.5), "boulder_5": lambda: M.boulder(1056, 0.6),
    "boulder_6": lambda: M.boulder(1057, 1.5), "boulder_7": lambda: M.boulder(1058, 0.7),
    "crystal_0": lambda: M.crystal_cluster(1061), "crystal_1": lambda: M.crystal_cluster(1062),
    "crystal_2": lambda: M.crystal_cluster(1063),
    "mushrooms_0": lambda: M.mushrooms(1071, False), "mushrooms_1": lambda: M.mushrooms(1072, True),
    "stump_0": stump,
    "lily_0": lambda: lily_pad(1, False), "lily_1": lambda: lily_pad(2, False), "lily_2": lambda: lily_pad(3, True),
    "lily_3": lambda: lily_pad(4, False), "lily_4": lambda: lily_pad(5, True),
    "sparkle_0": lambda: sparkle(1, False), "sparkle_1": lambda: sparkle(2, True),
}

# Prop scatter per terrain id (positions are hashed per tile by the loader). x/y: sprite base point inside the tile.
SCATTER = {
    "forest": {"p_first": 1.0, "p_second": 0.6, "edge_jitter": 12, "x": [4, 28], "y": [18, 32], "choices": [
        ["pine_0", 0.1], ["pine_1", 0.1], ["pine_2", 0.1], ["oak_autumn_0", 0.075], ["oak_autumn_1", 0.075],
        ["oak_deep_0", 0.04], ["oak_lumen_0", 0.006], ["oak_green_0", 0.13], ["oak_green_1", 0.13],
        ["oak_green_2", 0.13], ["oak_green_3", 0.13]]},
    "rock": {"p_first": 1.0, "p_second": 0.75, "x": [6, 26], "y": [14, 31], "choices": [
        ["boulder_0", 1], ["boulder_1", 1], ["boulder_2", 1], ["boulder_3", 0.8], ["boulder_4", 1.2],
        ["boulder_5", 1.2], ["boulder_6", 0.5], ["boulder_7", 1.2]]},
    "lumen_vein": {"p_first": 0.7, "p_second": 0.0, "x": [12, 20], "y": [28, 31], "choices": [
        ["crystal_0", 1], ["crystal_1", 1], ["crystal_2", 1]]},
    "stump": {"p_first": 1.0, "p_second": 0.0, "x": [14, 18], "y": [24, 28], "choices": [["stump_0", 1]]},
    "water": {"p_first": 0.2, "p_second": 0.4, "interior_only": True, "x": [9, 23], "y": [14, 24], "choices": [
        ["lily_0", 1], ["lily_1", 1], ["lily_2", 0.5], ["lily_3", 1], ["lily_4", 0.5]]},
    "grass": {"p_first": 0.012, "p_second": 0.0, "x": [6, 26], "y": [10, 30], "choices": [
        ["mushrooms_0", 1], ["mushrooms_1", 1]]},
}


def export_props(manifest):
    manifest["props"] = {}
    for name, fn in PROPS.items():
        manifest["props"][name] = export_sprite(fn(), f"props/{name}.png")
    manifest["scatter"] = SCATTER
    manifest["blight_sparkle"] = {"props": ["sparkle_0", "sparkle_1"], "chance_pct": 30}


# Buildings that appear on the approved sheets (docs/mockups/buildings_*.png) use exactly those b_* functions.
SHEET = {
    "hearth": lambda: M.b_hearth(), "tent": lambda: M.b_tent(0), "woodcutter": lambda: M.b_woodcutter(1),
    "lumen_tap": lambda: M.b_lumen_mill(), "meeting_hall": lambda: M.b_meeting_hall(),
    "cottage": lambda: M.b_cottage(3, "thatch"), "cottage_shingle": lambda: M.b_cottage(4, "shingle"),
    "farm": lambda: M.b_farm(1), "market": lambda: M.b_market(), "shrine": lambda: M.b_shrine(),
    "bell_tower": lambda: M.b_bell_tower(),
    "rowhouse": lambda: M.b_rowhouse(2), "greenhouse": lambda: M.b_greenhouse(3), "lumen_pump": lambda: M.b_lumen_pump(),
    "cleanser": lambda: M.b_cleanser(4), "lumen_spire": lambda: M.b_lumen_spire(),
    "apartment_block": lambda: M.b_apartment(5), "lumen_reactor": lambda: M.b_reactor(), "park": lambda: M.b_park(6),
    "skyheart": lambda: M.b_skyheart(),
    # ticket 64: City row additions (same drawing helpers and palette as the sheet)
    "purifier_tower": lambda: M.b_purifier(), "toolsmith": lambda: M.b_toolsmith(7),
    "grand_bazaar": lambda: M.b_bazaar(8), "lumen_nexus": lambda: M.b_nexus(),
    "lumen_pylon": lambda: M.b_pylon(), "grid_battery": lambda: M.b_battery(),
    "rail_depot": lambda: M.b_rail_depot(),  # ticket 37c
    "airship_dock": lambda: M.b_airship_dock(),  # ticket 38
    "sky_foundry": lambda: M.b_sky_foundry(),  # ticket 39d
    "conduit_terraces": lambda: M.b_conduit_terraces(), "water_tower": lambda: M.b_water_tower(),  # ticket 39
    "vein_bore": lambda: M.b_vein_bore(), "hydroponic_hall": lambda: M.b_hydroponic_hall(),  # ticket 39b, 39c
    # tier art (TierDef.art_id): Tent II = Hut, Tent III = Lodge
    "hut": lambda: M.b_hut(9), "lodge": lambda: M.b_lodge(10),
}
# Flat footprints (lawn, plaza): drawn on the ground layer under every y-sorted object, never occluded by neighbours.
FLAT = {"park"}

# Not on a sheet: generic gable house (same generator as the cottage), tinted by category. id: (category, fw, fh).
GENERIC = {
    "forager": ("food", 1, 1), "storehouse": ("logistics", 2, 1),
    "fishing_dock": ("food", 1, 1), "quarry": ("materials", 1, 1), "sawmill": ("materials", 2, 1),
    "forester": ("materials", 1, 1), "builders_yard": ("logistics", 2, 1),
    "workshop": ("refining", 2, 1), "tax_office": ("civic", 1, 1), "well": ("water", 1, 1),
    "mason": ("refining", 2, 1), "refinery": ("refining", 2, 2), "kitchen": ("food", 1, 1),
    "handcart_shed": ("logistics", 2, 1),
    "conduit_terraces": ("housing", 3, 2), "lumen_pylon": ("lumen", 1, 1), "grid_battery": ("lumen", 2, 1),
    "rail_depot": ("logistics", 3, 1), "airship_dock": ("sky", 3, 3), "vein_bore": ("lumen", 2, 2),
    "hydroponic_hall": ("food", 3, 2), "water_tower": ("water", 1, 1), "sky_foundry": ("landmark", 3, 3),
    "lift_anchor": ("sky", 3, 3), "sky_lift": ("sky", 1, 1), "skyspire": ("housing", 2, 2),
    "cloud_cistern": ("water", 2, 1), "sky_garden": ("food", 3, 2), "aether_collector": ("lumen", 2, 2),
    "skyforge": ("refining", 2, 2), "observatory": ("civic", 2, 2), "dawn_beacon": ("landmark", 2, 2),
    "lumen_arcology": ("housing", 3, 3), "heartroot_tap": ("lumen", 2, 2), "verdant_spring": ("water", 2, 2),
    "vein_mender": ("lumen", 1, 1), "rewilding_grove": ("food", 2, 2), "clearwater_works": ("water", 2, 1),
    "bloom_orchard": ("food", 3, 3), "hall_of_seasons": ("civic", 3, 2),
}
# category -> (roof, wall, shutter colour, window light)
TINT = {
    "housing": ("thatch", "plaster", M.TEAL[2], M.WARM), "food": ("thatch", "plaster", M.LEAF["green"][2], M.WARM),
    "materials": ("thatch", "planks", None, M.WARM), "lumen": ("slate", "stone", M.CRYSTAL[2], M.GLOW),
    "refining": ("shingle", "stone", None, M.WARM), "water": ("teal", "plaster", M.hexc("3a6a9a"), M.WARM),
    "logistics": ("thatch", "planks", M.hexc("a83a3a"), M.WARM), "civic": ("slate", "plaster", M.hexc("a83a3a"), M.WARM),
    "sky": ("teal", "plaster", M.hexc("9ab0d0"), M.GLOW), "landmark": ("slate", "stone", None, M.WARM),
}


def generic_house(cat, fw, fh, seed):
    roof, wall, shut, light = TINT[cat]
    w = fw * 30 - 8 if fw > 1 else 22
    wall_h = 13 + 4 * (fh - 1)
    apex = max(8, min(20, int(w * 0.42)))
    depth = 8 + 3 * (fh - 1)
    wins = 2 if w < 30 else 4
    door = (7, 11) if fw == 1 else (9, 13)
    im, glows, smoke = M.gable_house(w, wall_h, apex, depth, roof, wall, wins, seed, shutters=shut, door=door,
                                     win_glow=light)
    return M.pack(im, glows, smoke, fw, fh, (1.0, 8 + 2 * fh))


def export_buildings(manifest):
    manifest["buildings"] = {}
    for bid, fn in SHEET.items():
        manifest["buildings"][bid] = export_sprite(fn(), f"buildings/{bid}.png",
                                                   {"generic": False, "flat": bid in FLAT})
    for i, (bid, (cat, fw, fh)) in enumerate(sorted(GENERIC.items())):
        if bid in SHEET:  # drawn on the sheet (pylon, battery); kept in GENERIC so the other seeds stay put
            continue
        manifest["buildings"][bid] = export_sprite(generic_house(cat, fw, fh, 200 + i), f"buildings/{bid}.png",
                                                   {"generic": True, "category": cat})


# ---------------------------------------------------------------- walkers (ticket 50)
# Atlas: one row per (variant, direction), one column per frame (0 step A, 1 step B, 2 standing). Directions
# 0 down, 1 up, 2 left, 3 right. Left is the mirrored right sprite, so the game never flips anything.
WALK_KINDS = ["villager", "farmer", "weaver"]
WALK_CLOTH = ["", "a8483c", "3e6aa0", "7a5aa0", "c8923a", "3e8a78", "8a8a94", "b0587a"]
WALK_HAIR = ["", "2a1c14", "a8783a", "c8b878", "7a3a22", "4a3a30"]
WALK_SKIN = ["", "d89c74", "b07a56", "f0c4a0"]
WALK_DIRS = ["down", "up", "side"]
WALK_CELL = (16, 20)
WALK_FOOT = (8, 18)  # foot point inside a cell
WALK_FRAMES = 3


def walker_looks():
    """Deterministic list of (kind, cloth, hair, skin); look 0 of each kind is the mockup original."""
    rng = random.Random(5050)
    looks = [(k, None, None, None) for k in WALK_KINDS]
    while len(looks) < 24:
        k = WALK_KINDS[len(looks) % 3]
        c = WALK_CLOTH[rng.randrange(len(WALK_CLOTH))]
        h = WALK_HAIR[rng.randrange(len(WALK_HAIR))]
        sk = WALK_SKIN[rng.randrange(len(WALK_SKIN))]
        look = (k, M.hexc(c) if c else None,
                M.hexc(h) if h else None, M.hexc(sk) if sk else None)
        if look not in looks:
            looks.append(look)
    return looks


def export_walkers(manifest):
    looks = walker_looks()
    cw, ch = WALK_CELL
    atlas = Image.new("RGBA", (cw * WALK_FRAMES, ch * len(looks) * 4))
    for v, (kind, cloth, hair, skin) in enumerate(looks):
        for di, facing in enumerate(WALK_DIRS):
            for f in range(WALK_FRAMES):
                im, _ = M.citizen(kind, facing, f, cloth, hair, skin)
                cells = [(di, im)] if facing != "side" else [(3, im), (2, im.transpose(Image.FLIP_LEFT_RIGHT))]
                for row, img in cells:
                    # foot centre of the 11x17 sprite is (5, 16); put it on WALK_FOOT
                    atlas.alpha_composite(img, (f * cw + WALK_FOOT[0] - 5, (v * 4 + row) * ch + WALK_FOOT[1] - 15))
    save(atlas, OUT / "walkers/walkers.png")
    sh = Image.new("RGBA", (14, 7))
    ImageDraw.Draw(sh).ellipse([0, 0, 13, 6], fill=(4, 6, 18, 62))
    save(sh, OUT / "walkers/shadow.png")
    # carried bundle: a small crate with rope, drawn per direction (down/up/side) as 7x7
    bd = {}
    for name in ("front", "back", "side"):
        im = Image.new("RGBA", (8, 8))
        d = ImageDraw.Draw(im)
        M.R(d, 1, 1, 6, 6, M.WOOD[2])
        M.R(d, 1, 1, 6, 2, M.WOOD[3])
        M.R(d, 1, 6, 6, 6, M.WOOD[0])
        M.R(d, 3, 1, 4, 6, M.THATCH[2])
        d.point([(1, 4), (6, 4)], fill=M.WOOD[1])
        im = M.sel_outline(im)
        save(im, OUT / f"walkers/bundle_{name}.png")
        bd[name] = f"walkers/bundle_{name}.png"
    manifest["walkers"] = {
        "file": "walkers/walkers.png", "cell": [cw, ch], "foot": list(WALK_FOOT), "frames": WALK_FRAMES,
        "variants": len(looks), "directions": ["down", "up", "left", "right"],
        "shadow": "walkers/shadow.png", "shadow_offset": [-7, -3],
        "bundle": bd, "bundle_size": [10, 10],
        "bundle_offset": {"front": [-5, -11], "back": [-5, -15], "side": [-4, -11]},
    }


def export_icons(manifest):
    """12x12 HUD icons (outlined, drawn at 3x by the UI with nearest filtering) into assets/ui/."""
    names = ["food", "materials", "lumen", "gold", "pop", "spirit", "moon"]
    for k in names:
        save(MV.icon(k), OUT / "ui" / f"icon_{k}.png")
    im = Image.new("RGBA", (12, 12))
    d = ImageDraw.Draw(im)
    d.ellipse([1, 1, 10, 10], fill=MV.hexc("3f86c8"))
    d.polygon([(3, 3), (6, 2), (7, 5), (4, 7), (2, 6)], fill=MV.hexc("5fae4a"))
    d.polygon([(7, 7), (10, 6), (9, 9), (7, 10)], fill=MV.hexc("5fae4a"))
    save(MV.outline(im), OUT / "ui" / "icon_planet.png")
    names.append("planet")
    manifest["icons"] = {k: f"ui/icon_{k}.png" for k in names}


def main():
    manifest = {"tile": T}
    export_icons(manifest)
    export_terrain(manifest)
    export_overlays(manifest)
    export_autotiles(manifest)
    export_states(manifest)
    export_roads(manifest)
    export_channels(manifest)
    export_rail(manifest)
    export_airship(manifest)
    export_sites(manifest)
    export_props(manifest)
    export_buildings(manifest)
    export_walkers(manifest)
    OUT.mkdir(parents=True, exist_ok=True)
    (OUT / "art_manifest.json").write_text(json.dumps(manifest, indent=1, sort_keys=True) + "\n")
    print("wrote", OUT)


if __name__ == "__main__":
    main()
