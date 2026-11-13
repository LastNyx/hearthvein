"""Export the game art from the approved mockup generator (tools/mockups.py) into assets/.

Usage: python3 tools/export_art.py [out_dir]     (default: <repo>/assets)

mockups.py stays the single art source: palettes, textures, tree/boulder/crystal sprites and the b_* building
functions are imported, never copied. This file only adds what a tile game needs on top of the scene renderer:
seamless 32x32 terrain tiles, soft transition overlays (blob autotile, 46 tiles per ground), connectable road
tiles, separate shadow / light-and-smoke images, and the manifest the GDScript loader (render/art_library.gd)
reads. Every random choice uses a fixed seed, so running twice writes identical bytes.
"""
import json
import math
import random
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw

sys.path.insert(0, str(Path(__file__).resolve().parent))
import mockups as M  # noqa: E402

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
    """Mockup grass: mostly flat mid green with a faint dither (big light/dark patches come from the shade layer, so
    the 32px tile never shows as a repeat). kind: plain, tufts, flowers, clover. Detail is sparse."""
    v = 0.5 + 0.5 * (pfbm(seed, 11) - 0.5)
    gi = pquant(v, 3, bias, 0.45) + 1 + shift
    img = to_img(A(M.GRASS)[np.clip(gi, 0, 4)])
    d = ImageDraw.Draw(img)
    rng = random.Random(seed * 7 + 1)
    n_tuft = {"plain": 1, "tufts": 5, "flowers": 2, "clover": 3}[kind]
    for _ in range(n_tuft):
        x, y = rng.randrange(3, T - 3), rng.randrange(3, T - 2)
        base = img.getpixel((x, y))
        c = tuple(min(255, int(q * 1.22)) for q in base[:3]) + (255,)
        dc = tuple(int(q * 0.7) for q in base[:3]) + (255,)
        d.point([(x, y), (x - 1, y - 1), (x + 1, y - 1), (x, y - 2)], fill=c)
        d.point([(x, y + 1)], fill=dc)
    if kind == "flowers":
        for _ in range(3):
            c = rng.choice([M.hexc("f07aa8"), M.hexc("f6f0e0"), M.hexc("8ab8f8"), M.hexc("f4d050")])
            x, y = rng.randrange(3, T - 3), rng.randrange(3, T - 3)
            for _ in range(rng.randint(2, 3)):
                fx, fy = x + rng.randint(-3, 3), y + rng.randint(-2, 2)
                d.point((fx, fy + 1), fill=M.GRASS[0])
                d.point((fx, fy), fill=c)
    if kind == "clover":
        for _ in range(7):
            x, y = rng.randrange(2, T - 2), rng.randrange(2, T - 2)
            d.point((x, y), fill=M.GRASS[4])
            d.point((x + 1, y + 1), fill=M.GRASS[0])
    return img


def soil_tile(seed):
    """Fertile soil: darker, richer grass with warm loam specks and sprouts (not mud)."""
    v = 0.5 + 0.5 * (pfbm(seed, 12) - 0.5)
    gi = pquant(v, 3, 0.0, 0.45)
    rich = [mix(M.GRASS[0], M.BANK[0], 0.25), mix(M.GRASS[1], M.BANK[1], 0.18),
            mix(M.GRASS[1], M.GRASS[2], 0.4)]
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
        d.point([(x, y), (x - 1, y - 1), (x + 1, y - 1)], fill=M.GRASS[2])
    for _ in range(2):  # sprouts: this is the fertile one
        x, y = rng.randrange(3, T - 3), rng.randrange(4, T - 2)
        d.point((x, y), fill=M.LEAF["green"][3])
        d.point((x, y - 1), fill=M.LEAF["green"][4])
    return img


def forest_tile(seed, bare=False):
    """Forest floor: dark green ground with leaf litter; `bare` (felled tile) adds exposed earth and more leaves."""
    v = 0.5 + 0.6 * (pfbm(seed, 18) - 0.5)
    gi = pquant(v, 2, 0.0, 0.8)
    pal = [mix(M.GRASS[0], (20, 30, 18), 0.35), mix(M.GRASS[0], M.BANK[0], 0.15)]
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


SHADE_SIZE = 640  # shade atlas: 20x20 tiles of 32px, seamless, laid by tile position (x % 20, y % 20)


def shade_atlas():
    """Large dithered light/dark patches over grass-like ground, like the mockup's broad tonal patches. Seamless over
    its whole 640px so any tile position lines up with its neighbours, and far bigger than the 32px ground tile."""
    S = SHADE_SIZE
    n = 0.45 * pnoise_n(S, 160, 31) + 0.30 * pnoise_n(S, 80, 32) + 0.17 * pnoise_n(S, 40, 33) + 0.08 * pnoise_n(S, 20, 34)
    n = np.clip((n - 0.5) * 1.9 + 0.5, 0, 1)
    bay = np.tile(M.BAYER, (S // 4, S // 4))
    dark = np.clip((0.36 - n) / 0.14, 0, 1)
    light = np.clip((n - 0.58) / 0.12, 0, 1) * 0.7
    out = np.zeros((S, S, 4), dtype=np.uint8)
    dm = bay < dark
    lm = (bay < light) & ~dm
    out[dm] = (*M.GRASS[0][:3], 125)
    out[lm] = (*M.GRASS[3][:3], 85)
    return Image.fromarray(out, "RGBA")


def rock_tile(seed):
    gi = pquant(pfbm(seed, 13), 4)
    img = to_img(A([M.ROCK[0], M.ROCK[1], M.ROCK[1], M.ROCK[2]])[gi])
    d = ImageDraw.Draw(img)
    rng = random.Random(seed * 3 + 5)
    for _ in range(9):
        x, y = rng.randrange(2, T - 5), rng.randrange(2, T - 3)
        d.ellipse([x, y, x + rng.randint(2, 4), y + rng.randint(1, 2)], fill=M.ROCK[3])
        d.point((x, y + 2), fill=M.ROCK[0])
    for _ in range(6):
        d.point((rng.randrange(1, T - 1), rng.randrange(1, T - 1)), fill=M.LEAF["deep"][2])
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
    if lily:
        for _ in range(2):
            x, y = rng.randrange(7, T - 7), rng.randrange(6, T - 6)
            d.ellipse([x - 4, y - 3, x + 4, y + 3], fill=M.LEAF["green"][1])
            d.ellipse([x - 3, y - 3, x + 3, y + 2], fill=M.LEAF["green"][3])
            d.point((x + 1, y - 1), fill=M.hexc("f4a0c0"))
    return img


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


def shore_overlay(ground, mask, seed):
    """Land of `ground` pushing into a water cell: land, dark bank, then lighter shallows fading to deep water."""
    d = edge_dist(mask)
    if not mask & (BN | BE | BS | BW):
        d = d - 5.0  # lone diagonal land: bigger round corner, so river bends are not square
    wob = 0.65 * pnoise(8, 600 + seed) + 0.35 * pnoise(4, 620 + seed)
    rl = np.maximum(1.5, 3.5 + (wob - 0.5) * 7)
    out = np.array(ground_tile(ground, 3 + seed))
    alpha = np.zeros((T, T), dtype=np.uint8)
    cov = d < rl
    alpha[cov] = 255
    bank = A(M.BANK)
    for k, ci in ((0, 0), (1, 1), (2, 2)):
        band = (d >= rl + k) & (d < rl + k + 1)
        if k == 2:
            band &= BAY < 0.6
        out[band, :3] = bank[ci]
        alpha[band] = 255
    wd = d - (rl + 2.5)
    wp = A(M.WATER)
    for lo, hi, lvl in ((-1, 1, 5), (1, 3, 4), (3, 6, 3), (6, 10, 2)):
        band = (wd > lo) & (wd <= hi) & (alpha == 0)
        if lvl == 2:
            band &= BAY < 0.55
        out[band, :3] = wp[lvl]
        alpha[band] = 255
    out[..., 3] = alpha
    return Image.fromarray(out, "RGBA")


REACH = {"grass": 7, "forest": 9, "soil": 9, "rock": 6, "vein": 7, "sky": 6}
# Width in px of the dithered fade of a transition (rock and vein keep a crisp edge, ground tones blend wide).
RAMP = {"grass": 9.0, "forest": 11.0, "soil": 12.0, "rock": 3.0, "vein": 4.0, "sky": 4.0}


def export_overlays(manifest):
    uniq, index = blob_set()
    manifest["overlay_index"] = index
    manifest["overlay_cols"] = 8
    rows_per = (len(uniq) + 7) // 8
    manifest["overlay_shore_row"] = rows_per
    manifest["overlays"] = {}
    for gi, g in enumerate(GROUND_ORDER):
        if g in ("water", "sky"):
            continue
        soft = [soft_overlay(g, m, gi * 10, REACH[g]) for m in uniq]
        shore = [shore_overlay(g, m, gi * 10) for m in uniq]
        a1, _ = pack_atlas(soft, 8)
        a2, _ = pack_atlas(shore, 8)
        im = Image.new("RGBA", (8 * T, 2 * rows_per * T))
        im.paste(a1, (0, 0))
        im.paste(a2, (0, rows_per * T))
        save(im, OUT / "terrain" / f"overlay_{g}.png")
        manifest["overlays"][g] = f"terrain/overlay_{g}.png"


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
    tiles["water"] = ([[water_tile(800 + i, lily=(i == 4)) for i in range(5)]], [0, 0, 1, 1, 2, 2, 3, 3, 4])
    manifest["ground_order"] = GROUND_ORDER
    save(shade_atlas(), OUT / "terrain" / "shade.png")
    manifest["shade"] = {"file": "terrain/shade.png", "cols": SHADE_SIZE // T, "rows": SHADE_SIZE // T,
                         "grounds": ["grass", "forest", "soil"]}
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
    half = 10.0 if level == 1 else 11.5
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
        inner = rd < half - 1.5
        rgb[inner & (cob[..., 3] > 0)] = cob[..., :3][inner & (cob[..., 3] > 0)]
        curb = road & ~inner
        rgb[curb] = M.STONE[2][:3]
    alpha = np.where(road, 255, 0)
    return to_img(rgb, alpha)


def export_roads(manifest):
    manifest["roads"] = {}
    for level, name in ((1, "dirt"), (2, "paved")):
        tiles = [road_tile(level, v, m) for v in range(2) for m in range(16)]
        im, rows = pack_atlas(tiles, 16)
        save(im, OUT / "roads" / f"{name}.png")
        manifest["roads"][str(level)] = {"file": f"roads/{name}.png", "cols": 16, "rows": rows}


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
    "crystal_0": lambda: M.crystal_cluster(1061), "crystal_1": lambda: M.crystal_cluster(1062),
    "crystal_2": lambda: M.crystal_cluster(1063),
    "mushrooms_0": lambda: M.mushrooms(1071, False), "mushrooms_1": lambda: M.mushrooms(1072, True),
    "stump_0": stump,
}

# Prop scatter per terrain id (positions are hashed per tile by the loader). x/y: sprite base point inside the tile.
SCATTER = {
    "forest": {"p_first": 1.0, "p_second": 0.6, "x": [4, 28], "y": [18, 32], "choices": [
        ["pine_0", 0.1], ["pine_1", 0.1], ["pine_2", 0.1], ["oak_autumn_0", 0.075], ["oak_autumn_1", 0.075],
        ["oak_deep_0", 0.04], ["oak_lumen_0", 0.006], ["oak_green_0", 0.13], ["oak_green_1", 0.13],
        ["oak_green_2", 0.13], ["oak_green_3", 0.13]]},
    "rock": {"p_first": 1.0, "p_second": 0.5, "x": [8, 24], "y": [18, 30], "choices": [
        ["boulder_0", 1], ["boulder_1", 1], ["boulder_2", 1], ["boulder_3", 1]]},
    "lumen_vein": {"p_first": 0.7, "p_second": 0.0, "x": [12, 20], "y": [28, 31], "choices": [
        ["crystal_0", 1], ["crystal_1", 1], ["crystal_2", 1]]},
    "stump": {"p_first": 1.0, "p_second": 0.0, "x": [14, 18], "y": [24, 28], "choices": [["stump_0", 1]]},
    "grass": {"p_first": 0.012, "p_second": 0.0, "x": [6, 26], "y": [10, 30], "choices": [
        ["mushrooms_0", 1], ["mushrooms_1", 1]]},
}


def export_props(manifest):
    manifest["props"] = {}
    for name, fn in PROPS.items():
        manifest["props"][name] = export_sprite(fn(), f"props/{name}.png")
    manifest["scatter"] = SCATTER


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
}

# Not on a sheet: generic gable house (same generator as the cottage), tinted by category. id: (category, fw, fh).
GENERIC = {
    "forager": ("food", 1, 1), "storehouse": ("logistics", 2, 1),
    "fishing_dock": ("food", 1, 1), "quarry": ("materials", 1, 1), "sawmill": ("materials", 2, 1),
    "forester": ("materials", 1, 1), "builders_yard": ("logistics", 2, 1),
    "workshop": ("refining", 2, 1), "tax_office": ("civic", 1, 1), "well": ("water", 1, 1),
    "mason": ("refining", 2, 1), "refinery": ("refining", 2, 2), "kitchen": ("food", 1, 1),
    "handcart_shed": ("logistics", 2, 1), "purifier_tower": ("water", 1, 1), "grand_bazaar": ("civic", 3, 2),
    "toolsmith": ("refining", 2, 1), "lumen_nexus": ("lumen", 3, 3),
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
        manifest["buildings"][bid] = export_sprite(fn(), f"buildings/{bid}.png", {"generic": False})
    for i, (bid, (cat, fw, fh)) in enumerate(sorted(GENERIC.items())):
        manifest["buildings"][bid] = export_sprite(generic_house(cat, fw, fh, 200 + i), f"buildings/{bid}.png",
                                                   {"generic": True, "category": cat})


def main():
    manifest = {"tile": T}
    export_terrain(manifest)
    export_overlays(manifest)
    export_roads(manifest)
    export_props(manifest)
    export_buildings(manifest)
    OUT.mkdir(parents=True, exist_ok=True)
    (OUT / "art_manifest.json").write_text(json.dumps(manifest, indent=1, sort_keys=True) + "\n")
    print("wrote", OUT)


if __name__ == "__main__":
    main()
