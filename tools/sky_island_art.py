"""Island art of ticket 72 (sky art pass 2): whole-island skystone slab sheets and the island "kit" (tapered rocky
underside, side undersides, rim lumps, roots, crystals). Imported by export_art.py.

Every island is 16x12 tiles. Instead of a 32 px flagstone per tile, the skystone is baked as one 512x384 image per
variant (irregular slab seams from a warped Voronoi, tone per slab, cracks, moss and grass tufts in the seams, a few
faint Lumen veins) and sliced into 32 px cells; the renderer picks the variant per island and puts cell (x, y) of the
island at cell (x, y) of the slice, so no seam lines up with a tile edge. The kit is baked the same way on a canvas with
KIT_MARGIN tiles round the island and KIT_BELOW tiles under it, clipped to leave the island body alone.
"""
import random

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

import mockups as M

T = M.T
IW, IH = 16, 12                 # island size in tiles
W, H = IW * T, IH * T
KIT_L, KIT_T, KIT_R, KIT_B = 2, 2, 2, 5   # kit margin in tiles: left, top, right, below
KW, KH = (IW + KIT_L + KIT_R) * T, (IH + KIT_T + KIT_B) * T
VARIANTS = 4

SKYSTONE = M.pal("8c8068", "b4a68a", "cfc2a4", "e4d9bc", "f4edd6")
MOSS = [(78, 100, 56), (104, 132, 70), (132, 160, 84)]
GRASS = [(64, 136, 55), (90, 166, 64), (122, 188, 76), (159, 208, 92)]
CLIFF = [(34, 30, 28), (62, 57, 52), (92, 86, 78), (126, 118, 106), (160, 150, 134)]
ROOT = [(70, 48, 30), (98, 70, 44), (126, 92, 56)]
BAYER = M.BAYER


def fnoise(h, w, cell, seed):
    """Smooth value noise (0..1) on an h x w field with the given feature size, not periodic."""
    g = np.random.default_rng(seed).random((h // cell + 3, w // cell + 3)).astype(np.float32)
    im = Image.fromarray(g, "F").resize((g.shape[1] * cell, g.shape[0] * cell), Image.BICUBIC)
    return np.clip(np.asarray(im)[cell // 2:cell // 2 + h, cell // 2:cell // 2 + w], 0, 1)


def _bayer(h, w):
    return np.tile(BAYER, (h // 4 + 1, w // 4 + 1))[:h, :w]


# ------------------------------------------------------------------ skystone slabs
def slab_image(seed):
    """512x384 RGBA of skystone slabs: irregular seams, slab tones, cracks, moss and grass in the seams, cyan veins."""
    rng = random.Random(seed)
    nrng = np.random.default_rng(seed)
    ys, xs = np.mgrid[0:H, 0:W].astype(np.float32)
    wx = xs + 14 * (fnoise(H, W, 40, seed + 1) - 0.5) * 2 + 4 * (fnoise(H, W, 12, seed + 2) - 0.5) * 2
    wy = ys + 14 * (fnoise(H, W, 40, seed + 3) - 0.5) * 2 + 4 * (fnoise(H, W, 12, seed + 4) - 0.5) * 2
    # Slab centres: a jittered grid of big cells (about 2-3 tiles across), stretched a little so slabs are not square.
    cw, ch = 88.0, 72.0
    pts = []
    for j in range(-1, int(H / ch) + 2):
        for i in range(-1, int(W / cw) + 2):
            off = cw * 0.5 if j % 2 else 0.0   # brick-like stagger so seams never form a straight lattice
            pts.append(((i + 0.5) * cw + off + nrng.uniform(-0.3, 0.3) * cw,
                        (j + 0.5) * ch + nrng.uniform(-0.3, 0.3) * ch))
    d = np.stack([0.5 * np.hypot((wx - px) * 0.92, (wy - py) * 1.1) + 0.5 * np.maximum(np.abs(wx - px) * 0.92, np.abs(wy - py) * 1.1)
                  for px, py in pts]).astype(np.float32)
    part = np.partition(d, 1, axis=0)
    gap = part[1] - part[0]
    cid = np.argmin(d, axis=0)
    seam = gap < 1.25
    # tone per slab plus a soft gradient inside it, dithered into the palette
    cell_tone = nrng.uniform(0.0, 1.0, len(pts)).astype(np.float32)
    cell_tone = np.round(cell_tone * 3) / 3 * 1.5
    tone = 1.9 + cell_tone[cid] + (fnoise(H, W, 24, seed + 5) - 0.5) * 0.9 + (fnoise(H, W, 6, seed + 6) - 0.5) * 0.35
    lvl = np.clip(np.floor(tone + (_bayer(H, W) - 0.5) * 0.7), 1, 4).astype(int)
    rgb = np.array([c[:3] for c in SKYSTONE], np.uint8)[lvl]
    # light from the top-left: lit pixels just right of / below a seam, shaded ones just left of / above it
    s = seam
    lit = np.zeros_like(s)
    lit[:, 1:] |= s[:, :-1]
    lit[1:, :] |= s[:-1, :]
    shade = np.zeros_like(s)
    shade[:, :-1] |= s[:, 1:]
    shade[:-1, :] |= s[1:, :]
    rgb[lit & ~s] = SKYSTONE[4][:3]
    sh = shade & ~s & ~lit
    rgb[sh] = np.array([c[:3] for c in SKYSTONE], np.uint8)[np.clip(lvl[sh] - 1, 1, 4)]
    rgb[s] = SKYSTONE[0][:3]
    im = Image.fromarray(rgb, "RGB").convert("RGBA")
    px = im.load()
    dr = ImageDraw.Draw(im)
    seam_pts = np.argwhere(seam)
    # hairline cracks inside slabs, with a lit lower lip
    for _ in range(26):
        x, y = rng.randrange(10, W - 10), rng.randrange(10, H - 10)
        if seam[y, x]:
            continue
        pts2 = [(x, y)]
        for _ in range(rng.randint(3, 6)):
            x = max(2, min(W - 3, x + rng.randint(3, 9) * rng.choice([-1, 1])))
            y = max(2, min(H - 3, y + rng.randint(-5, 6)))
            pts2.append((x, y))
        dr.line(pts2, fill=SKYSTONE[1] if rng.random() < 0.5 else SKYSTONE[0])
        dr.line([(px_ + 1, py_ + 1) for px_, py_ in pts2], fill=SKYSTONE[4])
    # faint Lumen-cyan veins wandering over slabs and seams
    ov = Image.new("RGBA", (W, H))
    od = ImageDraw.Draw(ov)
    for _ in range(7):
        x, y = rng.randrange(20, W - 20), rng.randrange(20, H - 20)
        ang = rng.uniform(0, 6.28)
        pts2 = [(x, y)]
        for _ in range(rng.randint(8, 16)):
            ang += rng.uniform(-0.7, 0.7)
            x += int(np.cos(ang) * rng.randint(6, 12))
            y += int(np.sin(ang) * rng.randint(5, 10))
            pts2.append((max(0, min(W - 1, x)), max(0, min(H - 1, y))))
        od.line(pts2, fill=(92, 206, 224, 110), width=1)
        for p in pts2[1::3]:
            od.point(p, fill=(178, 244, 250, 190))
    im = Image.alpha_composite(im, ov)
    px = im.load()
    dr = ImageDraw.Draw(im)
    # specks and pebbles
    for _ in range(420):
        x, y = rng.randrange(1, W - 1), rng.randrange(1, H - 1)
        if not seam[y, x]:
            px[x, y] = SKYSTONE[rng.choice([1, 2, 4])] if rng.random() < 0.6 else SKYSTONE[0]
    # moss creeping off the seams and grass tufts rooted in them
    for _ in range(130):
        y, x = seam_pts[rng.randrange(len(seam_pts))]
        for _ in range(rng.randint(3, 9)):
            mx, my = x + rng.randint(-3, 3), y + rng.randint(-2, 2)
            if 0 <= mx < W and 0 <= my < H and not seam[my, mx] or rng.random() < 0.3:
                if 0 <= mx < W and 0 <= my < H:
                    px[mx, my] = MOSS[rng.choice([0, 0, 1, 1, 2])] + (255,)
    for _ in range(70):
        y, x = seam_pts[rng.randrange(len(seam_pts))]
        if not (2 <= x < W - 2 and 4 <= y < H - 2):
            continue
        for k, (dx, dy) in enumerate([(0, 0), (0, -1), (-1, -1), (1, -2), (0, -2), (-1, -3), (0, -3)][:rng.randint(4, 7)]):
            px[x + dx, y + dy] = GRASS[1 + (k + rng.randint(0, 1)) % 3] + (255,)
        px[x, y + 1] = GRASS[0] + (255,)
    return im


# ------------------------------------------------------------------ kit: underside, side masses, lumps
def body_mask(cap_sd):
    """Boolean (H, W) of the island body on its own canvas: the rectangle without the four rounded corner bites."""
    m = np.ones((H, W), bool)
    for corner in range(4):
        sd = cap_sd(corner)[16:48, 16:48] > 0.0   # True where the bite is cut away
        x0 = W - T if corner in (1, 2) else 0
        y0 = H - T if corner in (2, 3) else 0
        m[y0:y0 + T, x0:x0 + T] &= ~sd
    return m


def _smooth(x):
    x = np.clip(x, 0.0, 1.0)
    return x * x * (3 - 2 * x)


def kit_image(seed, cap_sd):
    """RGBA KW x KH kit of one island variant: the island sits at (KIT_L, KIT_T) tiles. The underside is a tapered
    rocky mass, deepest under the middle of the south edge, with ragged bottom, strata, hanging roots and crystals;
    thinner tapered masses hang down the lower east and west sides; a few rock lumps stick out past the rim."""
    rng = random.Random(seed)
    nrng = np.random.default_rng(seed)
    ox, oy = KIT_L * T, KIT_T * T
    x0, y0, x1, y1 = ox, oy, ox + W, oy + H
    ys, xs = np.mgrid[0:KH, 0:KW].astype(np.float32) + 0.5
    # --- bottom contour: deep (about 3 tiles) in the middle, shallow to the corners, ragged
    u = (xs[0] - x0) / W
    tri = 1.0 - np.abs(2 * u - 1.0)                       # 0 at the sides, 1 in the middle
    deep = 20 + 84 * _smooth(tri * 1.1) ** 1.7
    c = rng.uniform(0.42, 0.58)                           # the deepest point is not exactly centred
    deep = deep * (0.88 + 0.12 * np.exp(-((u - c) / 0.2) ** 2))
    n1 = np.random.default_rng(seed + 1).random(KW // 24 + 4)
    n2 = np.random.default_rng(seed + 2).random(KW // 8 + 4)
    xi = np.arange(KW)
    r1 = np.interp(xi, np.arange(len(n1)) * 24, n1) - 0.5
    r2 = np.interp(xi, np.arange(len(n2)) * 8, n2) - 0.5
    deep = deep + 22 * r1 * (0.3 + tri) + 9 * r2 * (0.4 + tri)
    for _ in range(rng.randint(3, 5)):                    # a few chunky stalactite lumps on the bottom
        cx = rng.uniform(0.2, 0.8) * W + x0
        wd = rng.uniform(14, 26)
        deep = deep + rng.uniform(10, 24) * np.exp(-((xi + 0.5 - cx) / wd) ** 2) * (0.4 + tri)
    deep = np.where((xi >= x0 - 18) & (xi < x1 + 18), deep, 0.0)
    # side thickness: tapered masses, thin at the top and fattest at the bottom
    side_h = 4.2 * T
    st = _smooth((ys - (y1 - side_h)) / side_h)
    side = 15.0 * st * (0.75 + 0.5 * fnoise(KH, KW, 30, seed + 3))
    below = ys - y1
    bottom = (y1 + deep)[None, :].repeat(KH, 0)
    inside_x = (xs > x0 - side) & (xs < x1 + side)
    mass = inside_x & (ys > y1 - side_h) & (ys < bottom)
    # side masses end above the bottom contour at x outside the rect: pinch them toward the bottom corner
    out_l, out_r = xs < x0, xs >= x1
    corner_cut = (out_l | out_r) & (below > 0) & (below > deep[np.clip(xs.astype(int), 0, KW - 1)] * 1.0)
    mass &= ~corner_cut
    mass &= (ys > y1 - side_h)
    # keep only what lies outside the island body
    bm = np.zeros((KH, KW), bool)
    bm[y0:y1, x0:x1] = body_mask(cap_sd)
    mass &= ~bm
    # --- lumps on the rim: blobs sticking out past the rect edge, away from the corners
    lump_q = np.full((KH, KW), 9.0, np.float32)
    specs = []
    for edge, n in (("N", rng.randint(2, 3)), ("E", rng.randint(1, 2)), ("W", rng.randint(1, 2))):
        slots = np.linspace(0.16, 0.84, 6)
        for p in rng.sample(range(6), n):
            specs.append((edge, slots[p] + rng.uniform(-0.03, 0.03)))
    for edge, f in specs:
        w_ = rng.uniform(38, 74)
        h_ = rng.uniform(15, 27)
        horiz = edge == "N"
        if horiz:
            cx, cy, ax, ay = x0 + f * W, y0 + h_ * 0.1, w_, h_
        else:
            cx, cy, ax, ay = (x0 if edge == "W" else x1) + (h_ * 0.1 if edge == "E" else -h_ * 0.1), y0 + f * H, h_, w_ * 0.9
        lump_q = np.minimum(lump_q, np.sqrt(((xs - cx) / ax) ** 2 + ((ys - cy) / ay) ** 2))
        k = rng.uniform(0.4, 0.8)   # a second, smaller bump on the lump for a lumpy outline
        if horiz:
            cx2, cy2 = cx + rng.uniform(-0.5, 0.5) * w_, cy - h_ * 0.35
            rx, ry = rng.uniform(10, 18), rng.uniform(9, 14)
        else:
            cx2, cy2 = cx + (-1 if edge == "W" else 1) * h_ * 0.35, cy + rng.uniform(-0.5, 0.5) * w_
            rx, ry = rng.uniform(9, 14), rng.uniform(10, 18)
        lump_q = np.minimum(lump_q, np.sqrt(((xs - cx2) / rx) ** 2 + ((ys - cy2) / ry) ** 2) * 1.1)
    edge_n = fnoise(KH, KW, 7, seed + 7)
    lump = lump_q < 1.0 + 0.55 * (edge_n - 0.5)
    lump &= ~bm
    both = mass | lump
    # --- colour: pale rock near the island, darker toward the bottom
    depth = np.where(mass, np.clip((ys - (y1 - 6)) / np.maximum(1.0, deep[np.clip(xs.astype(int), 0, KW - 1)] + 4), 0, 1.4),
                     0.0)
    nz = fnoise(KH, KW, 10, seed + 8) - 0.5
    nz2 = fnoise(KH, KW, 4, seed + 9) - 0.5
    # face tone: 0 (dark) .. 3 (light)
    streak = np.interp(xs[0], np.arange(KW // 9 + 3) * 9, np.random.default_rng(seed + 11).random(KW // 9 + 3)) - 0.5
    tone = np.where(lump & ~mass, 2.3 + nz * 1.6, 3.5 - 2.5 * depth + nz * 1.5 + nz2 * 0.6 + streak[None, :] * 0.9
                    + 0.45 * (1.0 - (xs - x0) / W * 2.0) - 0.9 * np.exp(-np.maximum(ys - y1, 0) / 7.0))
    tone = tone + (_bayer(KH, KW) - 0.5) * 0.8
    lvl = np.clip(np.floor(tone), 0, 3).astype(int)
    pal = np.array([c for c in CLIFF[1:5]], np.uint8)
    rgb = pal[lvl]
    # dark cracks running down the underside, with a lit lip on their right
    cr = np.zeros((KH, KW), bool)
    crl = np.zeros((KH, KW), bool)
    for _ in range(rng.randint(9, 13)):
        x = rng.uniform(x0 + 10, x1 - 10)
        y = y1 + rng.randint(2, 30)
        for _ in range(rng.randint(14, 40)):
            xi_, yi_ = int(x), int(y)
            if 0 <= xi_ < KW - 2 and 0 <= yi_ < KH:
                cr[yi_, xi_] = True
                crl[yi_, xi_ + 1] = True
            y += 1
            x += rng.choice([-1, 0, 0, 0, 1]) * 1.0
            if rng.random() < 0.15:
                x += rng.choice([-1, 1])
    crl &= ~cr
    rgb[cr & mass] = CLIFF[0]
    rgb[crl & mass] = CLIFF[3]
    # silhouette outline: darkest outline all round, lit top-left edges
    up = np.zeros_like(both)
    up[1:] = both[:-1]
    lf = np.zeros_like(both)
    lf[:, 1:] = both[:, :-1]
    dn = np.zeros_like(both)
    dn[:-1] = both[1:]
    rt = np.zeros_like(both)
    rt[:, :-1] = both[:, 1:]
    edge_any = both & ~(up & lf & dn & rt)
    rgb[edge_any] = CLIFF[0]
    # inner highlight one pixel inside the outline on top-left facing edges (lumps and side masses)
    inner_hi = both & ~edge_any & (~np.roll(both, 2, 0) | ~np.roll(both, 2, 1)) & (lump | (ys < y1))
    rgb[inner_hi & ~edge_any] = CLIFF[4]
    rgb[lump & ~mass & ~edge_any & (ys < y0 + 60.0) & inner_hi] = SKYSTONE[3][:3]
    a = (both * 255).astype(np.uint8)
    im = Image.fromarray(np.dstack([rgb, a]), "RGBA").copy()
    px = im.load()
    # moss on top of the lumps
    for _ in range(40):
        yy, xx = rng.randrange(KH), rng.randrange(KW)
        if lump[yy, xx] and not mass[yy, xx] and not edge_any[yy, xx]:
            for k in range(rng.randint(2, 5)):
                mx = min(KW - 1, xx + k)
                if lump[yy, mx]:
                    px[mx, yy] = MOSS[rng.choice([0, 1, 1, 2])] + (255,)
    # --- hanging roots from the bottom contour and the side masses
    bot_pts = [x for x in range(x0 + 30, x1 - 30) if both[int(y1 + deep[x]) - 2, x]]
    for _ in range(rng.randint(7, 10)):
        x = rng.choice(bot_pts)
        y = int(y1 + deep[x]) - 2
        length = rng.randint(18, 54)
        for k in range(length):
            if not (0 <= y < KH and 0 <= x < KW):
                break
            px[x, y] = ROOT[2 if k % 5 == 0 else (1 if k % 2 else 0)] + (255,)
            if k > 6 and k % 9 == 0 and 0 <= x + 1 < KW:  # side tendril
                px[x + 1, y] = ROOT[1] + (255,)
                if 0 <= x + 2 < KW:
                    px[x + 2, y + 1] = ROOT[0] + (255,)
            y += 1
            x = max(0, min(KW - 1, x + rng.choice([0, 0, 0, 1, -1])))
    # --- glowing crystals: a few clusters poking down / out of the mass, with a soft cyan halo
    halo = Image.new("RGBA", (KW, KH))
    n_cr = rng.randint(3, 4)
    spots = []
    for i in range(n_cr):
        x = rng.randint(x0 + 40, x1 - 40)
        spots.append((x, int(y1 + deep[x]) - 3, "down"))
    spots[0] = (x0 - 6, int(y1 - 30 - rng.randint(0, 40)), "left") if rng.random() < 0.5 else spots[0]
    for (cx, cy, kind) in spots:
        hd = ImageDraw.Draw(halo)
        hd.ellipse([cx - 20, cy - 12, cx + 20, cy + 30], fill=(110, 230, 250, 95))
    halo = halo.filter(ImageFilter.GaussianBlur(6))
    ha = np.array(halo)
    ha[..., 3] = np.where(bm, 0, ha[..., 3])   # the glow never tints the island body
    halo = Image.fromarray(ha, "RGBA")
    # halo only over transparent surroundings and the mass edge (kept soft); composite under the rock
    out = Image.alpha_composite(halo, im)
    px = out.load()
    for (cx, cy, kind) in spots:
        for ox_, ln, wd in ((0, rng.randint(14, 20), 3), (-5, rng.randint(7, 11), 1), (5, rng.randint(8, 12), 1)):
            for k in range(ln):
                half = (wd - (1 if k > ln * 0.55 else 0) - (1 if k > ln * 0.85 else 0)) if wd > 1 else 0
                for dx in range(-half, half + 1):
                    xx = cx + ox_ + dx
                    yy = cy + k
                    if 0 <= xx < KW and 0 <= yy < KH:
                        col = M.CRYSTAL[3 if dx == 0 and k > 1 else (2 if dx >= 0 else 1)]
                        if k == ln - 1:
                            col = M.CRYSTAL[4]
                        px[xx, yy] = tuple(col[:3]) + (255,)
    return out


# ------------------------------------------------------------------ atlases and a flat preview
def corner_cells(slab, cap_sd):
    """Row of the four corner tiles of a slab variant with the bite cut out (NW, NE, SE, SW)."""
    fill = Image.new("RGBA", (4 * T, T))
    origins = [(0, 0), (W - T, 0), (W - T, H - T), (0, H - T)]
    for c, (cx, cy) in enumerate(origins):
        tile = np.array(slab.crop((cx, cy, cx + T, cy + T)))
        tile[..., 3] = np.where(cap_sd(c)[16:48, 16:48] <= 0.0, 255, 0)
        fill.paste(Image.fromarray(tile, "RGBA"), (c * T, 0))
    return fill


def kit_cells(kit):
    """Non-empty 32 px cells of a kit, as a list of [col, row]."""
    a = np.array(kit)[..., 3]
    out = []
    for r in range(KH // T):
        for c in range(KW // T):
            if a[r * T:(r + 1) * T, c * T:(c + 1) * T].any():
                out.append([c, r])
    return out
