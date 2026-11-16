"""Hearthvein design mockups v2: lush 3/4 pixel art with depth and fantasy touches.

Usage: python3 tools/mockups.py [out_dir]
Writes scene_village.png, scene_dimming.png, scene_closeup.png, buildings_camp_village.png,
buildings_town_city.png, citizens.png.
Procedural mockup art to settle look, scale and palette; not final assets.
"""
import math
import random
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageChops, ImageDraw, ImageFont

T = 32
FONT_B = "/usr/share/fonts/noto/NotoSans-Bold.ttf"


def hexc(h, a=255):
    h = h.lstrip("#")
    return (int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16), a)


def pal(*hs):
    return [hexc(h) for h in hs]


def font(size):
    try:
        return ImageFont.truetype(FONT_B, size)
    except OSError:
        return ImageFont.load_default(size)


def mul(c, f):
    return tuple(max(0, min(255, int(v * f))) for v in c[:3]) + (c[3] if len(c) > 3 else 255,)


# ------------------------------------------------------------------ palettes
GRASS = pal("2c6a34", "3f8a3a", "5aaa44", "7cc452", "a2da64")
VEIN = pal("262f30", "323e3e", "414f4d", "56685f")
BLIGHT = pal("3a2f4a", "4e4262", "65587a", "7d6f92", "978aaa")
WATER = pal("23508c", "2f66a8", "3f80c2", "5fa6d8", "9cd6ec", "d4f2f8")
BANK = pal("4a3626", "6a4f36", "8a6c4a")
DIRT = pal("6e4c30", "8a6440", "a47e52", "c09a6a")
COBBLE = pal("8e7a5a", "c4b28a", "d8c9a3", "ebdfc0")
BARK = pal("2e2016", "4a3424", "6a4c32", "8a6a46")
LEAF = {
    "green": pal("1c4426", "2a6232", "3f8a3a", "62b048", "96d460"),
    "deep": pal("163a2a", "1f5232", "2e703a", "4a9444", "74b85a"),
    "autumn": pal("4e2416", "7e3e1e", "b0662a", "dc9a3a", "f4c862"),
    "lumen": pal("10343e", "17525e", "238a96", "4cc6cc", "aaf2f2"),
}
ROCK = pal("3e3e48", "5a5a66", "7c7c88", "a2a2ae", "c8c8d2")
THATCH = pal("6a4620", "93682e", "bb8c3e", "dcb460", "f0d488")
SHINGLE = pal("4e2018", "7a3424", "a44a30", "c8663e", "e08a5a")
SLATE = pal("1e2a36", "2e4050", "425a6c", "5a7a8c", "7e9eb0")
STONE = pal("4e4a44", "6e685e", "8e877a", "aca594", "c8c2b0")
PLASTER = pal("b8a888", "d6c8a6", "eadcbc", "f6ecd2")
WOOD = pal("2e1e14", "4e3220", "6e4a2e", "906640", "b08656")
CANVAS = pal("8a7a5a", "c8b48a", "e6d6b0", "f6ecd0")
TEAL = pal("124848", "1f6e6a", "2e948a", "52bcae")
CRYSTAL = pal("12586c", "2a92aa", "58c8dc", "a8eef8", "eaffff")
BRASS = pal("6a4a18", "a87a2a", "d4a440", "f0d070")
GLOW = hexc("7fe8f8")
WARM = hexc("ffd27a")


def R(d, x0, y0, x1, y1, c):
    d.rectangle([x0, y0, x1, y1], fill=c)


# ------------------------------------------------------------------ outline / sprites
def sel_outline(img, f=0.42):
    """Selective outline: transparent pixels next to solid ones take a darkened neighbour colour."""
    a = np.array(img, dtype=np.int32)
    a = np.pad(a, ((1, 1), (1, 1), (0, 0)))
    solid = a[..., 3] > 180
    out = a.copy()
    done = solid.copy()
    for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
        nb = np.roll(np.roll(a, dy, 0), dx, 1)
        nbs = np.roll(np.roll(solid, dy, 0), dx, 1)
        cond = (~done) & nbs
        out[cond, :3] = (nb[cond, :3] * f).astype(np.int32)
        out[cond, 3] = 255
        done |= cond
    return Image.fromarray(out.astype(np.uint8), "RGBA")


class Sprite:
    def __init__(self, img, fw=1, fh=1, glows=(), smoke=(), shadow=None):
        self.img = sel_outline(img)
        self.fw, self.fh = fw, fh
        self.glows = [(x + 1, y + 1, r, c) for x, y, r, c in glows]
        self.smoke = [(x + 1, y + 1) for x, y in smoke]
        self.shadow = shadow  # (width_frac, height_px)


def glow_img(r, col, strength=1.0):
    s = 2 * r + 1
    im = Image.new("RGBA", (s, s))
    d = ImageDraw.Draw(im)
    for i in range(r, 0, -1):
        a = int(strength * (70 * (1 - i / r) ** 1.6 + 5))
        d.ellipse([r - i, r - i, r + i, r + i], fill=col[:3] + (min(255, a),))
    return im


# ------------------------------------------------------------------ textures
def tex_thatch(w, h, seed, p=THATCH):
    rng = random.Random(seed)
    im = Image.new("RGBA", (w, h))
    px = im.load()
    jit = [rng.randint(0, 2) for _ in range(w)]
    for x in range(w):
        for y in range(h):
            yy = y + jit[x]
            ly = yy % 6
            n = rng.random()
            if ly == 5:
                c = p[0] if n < 0.8 else p[1]
            elif ly == 4:
                c = p[1]
            elif ly == 0:
                c = p[4] if n < 0.35 else p[3]
            else:
                c = p[3] if (x + yy // 6) % 3 == 0 and n < 0.7 else p[2]
                if n > 0.93:
                    c = p[1]
            px[x, y] = c
    return im


def tex_shingle(w, h, p):
    im = Image.new("RGBA", (w, h))
    px = im.load()
    for y in range(h):
        row, ry = divmod(y, 5)
        off = 3 if row % 2 else 0
        for x in range(w):
            rx = (x + off) % 6
            if ry == 4 or (rx == 0 and ry > 0):
                c = p[0]
            elif ry == 3 and rx in (1, 5):
                c = p[0]
            elif ry == 0:
                c = p[3]
            elif rx == 1:
                c = p[3]
            elif ry == 3:
                c = p[1]
            else:
                c = p[2]
            px[x, y] = c
    return im


def tex_stone(w, h, seed, p=STONE):
    rng = random.Random(seed)
    im = Image.new("RGBA", (w, h), p[0])
    d = ImageDraw.Draw(im)
    y = 0
    while y < h:
        x = -rng.randint(0, 5)
        while x < w:
            bw = rng.randint(5, 9)
            c = rng.choice(p[2:5])
            R(d, x, y, x + bw - 2, y + 3, c)
            d.line([(x, y), (x + bw - 3, y)], fill=mul(c, 1.12))
            d.point((x + bw - 2, y + 3), fill=p[1])
            x += bw
        y += 5
    return im


def tex_plaster(w, h, seed, p=PLASTER):
    rng = random.Random(seed)
    im = Image.new("RGBA", (w, h), p[2])
    px = im.load()
    for _ in range(w * h // 9):
        px[rng.randrange(w), rng.randrange(h)] = rng.choice([p[1], p[3]])
    return im


def tex_planks(w, h, seed, p=WOOD, vertical=True):
    rng = random.Random(seed)
    im = Image.new("RGBA", (w, h))
    d = ImageDraw.Draw(im)
    n = w if vertical else h
    i = 0
    while i < n:
        c = rng.choice(p[2:5])
        if vertical:
            R(d, i, 0, i + 2, h - 1, c)
            d.line([(i + 3, 0), (i + 3, h - 1)], fill=p[1])
            d.line([(i, 0), (i, h - 1)], fill=mul(c, 1.1))
        else:
            R(d, 0, i, w - 1, i + 2, c)
            d.line([(0, i + 3), (w - 1, i + 3)], fill=p[1])
        i += 4
    for _ in range(w * h // 60):
        d.point((rng.randrange(w), rng.randrange(h)), fill=p[1])
    return im


def roof_tex(kind, w, h, seed):
    if kind == "thatch":
        return tex_thatch(w, h, seed)
    if kind == "shingle":
        return tex_shingle(w, h, SHINGLE)
    if kind == "slate":
        return tex_shingle(w, h, SLATE)
    if kind == "teal":
        return tex_shingle(w, h, TEAL)
    raise ValueError(kind)


def wall_tex(kind, w, h, seed):
    return {"plaster": tex_plaster, "stone": tex_stone, "planks": tex_planks}[kind](w, h, seed)


def shade(im, f):
    a = np.array(im, dtype=np.float32)
    a[..., :3] *= f
    return Image.fromarray(np.clip(a, 0, 255).astype(np.uint8), "RGBA")


def fill_poly(dst, pts, tex):
    m = Image.new("L", dst.size)
    ImageDraw.Draw(m).polygon(pts, fill=255)
    dst.paste(tex, (0, 0), m)
    return m


# ------------------------------------------------------------------ small props
def window(d, x, y, glow=WARM, shutters=None, box=True, w=7, h=8):
    R(d, x, y, x + w - 1, y + h - 1, WOOD[1])
    R(d, x + 1, y + 1, x + w - 2, y + h - 2, glow)
    R(d, x + 1, y + 1, x + 2, y + 2, mul(glow, 1.25))
    d.line([(x + w // 2, y + 1), (x + w // 2, y + h - 2)], fill=WOOD[1])
    d.line([(x + 1, y + h // 2), (x + w - 2, y + h // 2)], fill=WOOD[1])
    if shutters:
        R(d, x - 2, y, x - 1, y + h - 1, shutters)
        R(d, x + w, y, x + w + 1, y + h - 1, shutters)
    if box:
        R(d, x - 1, y + h, x + w, y + h + 2, WOOD[2])
        for k, c in enumerate([hexc("e8506a"), hexc("f4f0e0"), hexc("f4c040"), hexc("e8506a")]):
            d.point((x + k * 2, y + h - 1), fill=c)
            d.point((x + k * 2 + 1, y + h), fill=LEAF["green"][3])


def arch_door(d, cx, yb, w=7, h=11):
    x0 = cx - w // 2
    R(d, x0, yb - h + w // 2, x0 + w - 1, yb, WOOD[1])
    d.ellipse([x0, yb - h, x0 + w - 1, yb - h + w], fill=WOOD[1])
    R(d, x0 + 1, yb - h + w // 2, x0 + w - 2, yb - 1, WOOD[3])
    d.ellipse([x0 + 1, yb - h + 1, x0 + w - 2, yb - h + w - 1], fill=WOOD[3])
    for x in range(x0 + 2, x0 + w - 1, 2):
        d.line([(x, yb - h + 3), (x, yb - 1)], fill=WOOD[2])
    d.point((x0 + w - 2, yb - h // 2 + 1), fill=BRASS[3])


def crystal(d, x, yb, h, w=6, p=CRYSTAL):
    cx = x + w // 2
    d.polygon([(x, yb), (x, yb - h * 2 // 3), (cx, yb - h), (cx, yb)], fill=p[3])
    d.polygon([(cx, yb), (cx, yb - h), (x + w, yb - h * 2 // 3), (x + w, yb)], fill=p[2])
    d.line([(cx, yb - h + 1), (cx, yb)], fill=p[4])
    d.point((x + 1, yb - h * 2 // 3), fill=p[4])


def lantern_post():
    im = Image.new("RGBA", (7, 20))
    d = ImageDraw.Draw(im)
    R(d, 3, 6, 3, 19, WOOD[1])
    R(d, 2, 18, 4, 19, WOOD[0])
    R(d, 1, 1, 5, 6, BRASS[1])
    R(d, 2, 2, 4, 5, CRYSTAL[3])
    d.point((3, 3), fill=CRYSTAL[4])
    R(d, 2, 0, 4, 0, BRASS[0])
    return Sprite(im, glows=[(3, 3, 14, GLOW)], shadow=(0.5, 3))


# ------------------------------------------------------------------ trees / nature
def oak(seed, s=1.0, kind="green"):
    rng = random.Random(seed)
    p = LEAF[kind]
    W, H = int(46 * s), int(60 * s)
    im = Image.new("RGBA", (W, H))
    d = ImageDraw.Draw(im)
    cx, cy, Rr = W // 2, int(H * 0.36), 16 * s
    # trunk + roots
    tw = max(4, int(6 * s))
    tb = H - 2
    d.polygon([(cx - tw // 2 - 3, tb), (cx - tw // 2, tb - 4), (cx - tw // 2, cy), (cx + tw // 2, cy),
               (cx + tw // 2, tb - 4), (cx + tw // 2 + 4, tb), (cx + 1, tb - 2)], fill=BARK[2])
    R(d, cx - tw // 2, cy, cx - tw // 2 + 1, tb - 4, BARK[3])
    R(d, cx + tw // 2 - 1, cy, cx + tw // 2, tb - 3, BARK[1])
    for _ in range(3):
        y = rng.randint(cy + 4, tb - 6)
        d.line([(cx - 1, y), (cx, y + 2)], fill=BARK[1])
    d.line([(cx, cy + 8), (cx + int(9 * s), cy + 2)], fill=BARK[2], width=2)
    # canopy blobs
    blobs = [(cx, cy, Rr * 0.72)]
    for k in range(7):
        ang = k / 7 * 2 * math.pi + rng.uniform(-0.3, 0.3)
        dist = Rr * rng.uniform(0.45, 0.62)
        blobs.append((cx + math.cos(ang) * dist * 1.15, cy + math.sin(ang) * dist * 0.8, Rr * rng.uniform(0.42, 0.56)))
    blobs.sort(key=lambda b: b[1])
    for bx, by, br in blobs:
        d.ellipse([bx - br, by - br + 2, bx + br, by + br + 2], fill=p[0])
    for bx, by, br in blobs:
        d.ellipse([bx - br, by - br, bx + br, by + br - 1], fill=p[1])
    for bx, by, br in blobs:
        d.ellipse([bx - br + 1, by - br, bx + br - 2, by + br * 0.55], fill=p[2])
    for bx, by, br in blobs:
        r2 = br * 0.55
        d.ellipse([bx - br * 0.55 - r2, by - br * 0.5 - r2 * 0.8, bx - br * 0.55 + r2 * 1.2, by - br * 0.5 + r2],
                  fill=p[3])
    for bx, by, br in blobs:
        for _ in range(int(br)):
            x = int(bx - br * 0.7 + rng.random() * br * 0.9)
            y = int(by - br * 0.8 + rng.random() * br * 0.6)
            if 0 <= x < W - 1 and 0 <= y < H and im.getpixel((x, y))[3]:
                d.point([(x, y), (x + 1, y)], fill=p[4])
        for _ in range(int(br * 1.2)):
            x = int(bx - br + rng.random() * br * 2)
            y = int(by + rng.random() * br * 0.8)
            if 0 <= x < W and 0 <= y < H and im.getpixel((x, y))[3]:
                d.point((x, y), fill=p[1])
    glows = []
    if kind == "lumen":
        for _ in range(9):
            x, y = int(cx + rng.uniform(-Rr, Rr) * 0.8), int(cy + rng.uniform(-Rr, Rr) * 0.6)
            if im.getpixel((x, y))[3]:
                d.point([(x, y), (x + 1, y), (x, y + 1)], fill=CRYSTAL[4])
                glows.append((x, y, 7, GLOW))
        glows.append((cx, cy, int(Rr * 1.6), GLOW))
    return Sprite(im, glows=glows, shadow=(0.85, 10))


def pine(seed, s=1.0):
    rng = random.Random(seed)
    p = LEAF["deep"]
    W, H = int(30 * s), int(56 * s)
    im = Image.new("RGBA", (W, H))
    d = ImageDraw.Draw(im)
    cx = W // 2
    R(d, cx - 2, H - 10, cx + 1, H - 1, BARK[2])
    R(d, cx + 1, H - 10, cx + 1, H - 1, BARK[1])
    tiers = 5
    for t in range(tiers):
        yb = H - 8 - t * int(9 * s)
        hw = int((13 - t * 2.2) * s)
        th = int(14 * s)
        d.polygon([(cx - hw, yb), (cx, yb - th), (cx + hw, yb)], fill=p[1])
        d.polygon([(cx - hw, yb), (cx, yb - th), (cx, yb)], fill=p[2])
        d.polygon([(cx - hw + 2, yb - 2), (cx - 1, yb - th + 3), (cx - 1, yb - 2)], fill=p[3])
        for k in range(cx - hw + 1, cx + hw, 3):
            d.point((k, yb), fill=p[0])
            if rng.random() < 0.4 and k < cx:
                d.point((k + 1, yb - 3), fill=p[4])
    return Sprite(im, shadow=(0.7, 7))


def boulder(seed, s=1.0):
    rng = random.Random(seed)
    W, H = int(20 * s), int(15 * s)
    im = Image.new("RGBA", (W, H))
    d = ImageDraw.Draw(im)
    d.ellipse([0, 1, W - 1, H - 1], fill=ROCK[1])
    d.ellipse([0, 0, W - 3, H - 4], fill=ROCK[2])
    d.ellipse([2, 1, W // 2 + 1, H // 2], fill=ROCK[3])
    d.ellipse([3, 2, W // 3 + 1, H // 3], fill=ROCK[4])
    for _ in range(int(6 * s)):
        x = rng.randint(2, W - 4)
        d.point([(x, 1), (x + 1, 1), (x, 2)], fill=LEAF["green"][3])
    d.line([(W // 2, 3), (W // 2 + 2, H // 2)], fill=ROCK[1])
    return Sprite(im, shadow=(0.9, 5))


def crystal_cluster(seed):
    rng = random.Random(seed)
    im = Image.new("RGBA", (30, 34))
    d = ImageDraw.Draw(im)
    d.ellipse([2, 26, 28, 33], fill=VEIN[1])
    for x, h, w in sorted([(3, rng.randint(12, 16), 7), (11, rng.randint(22, 28), 9), (20, rng.randint(14, 19), 7)],
                          key=lambda c: -c[1]):
        crystal(d, x, 31, h, w)
    return Sprite(im, glows=[(15, 18, 22, GLOW)], shadow=(0.7, 5))


def mushrooms(seed, glowing):
    rng = random.Random(seed)
    im = Image.new("RGBA", (14, 10))
    d = ImageDraw.Draw(im)
    glows = []
    for k in range(3):
        x = 1 + k * 4 + rng.randint(0, 1)
        h = rng.randint(3, 5)
        R(d, x + 1, 9 - h, x + 2, 9, PLASTER[3])
        cap = CRYSTAL[2] if glowing else hexc("c83a32")
        d.ellipse([x - 1, 9 - h - 2, x + 4, 9 - h + 1], fill=cap)
        d.point((x, 9 - h - 1), fill=CRYSTAL[4] if glowing else PLASTER[3])
        if glowing:
            glows.append((x + 1, 9 - h, 6, GLOW))
    return Sprite(im, glows=glows)


# ------------------------------------------------------------------ buildings
def gable_house(w=21, wall_h=14, apex_h=10, depth=10, roof="thatch", wall="plaster", windows=2, seed=0,
                chimney=True, lantern=True, shutters=None, door=(7, 11), gable_window=True, timber=True,
                win_glow=WARM):
    """Front-gabled house seen 3/4 from above: two receding roof planes, gable face in front."""
    ov, tm = 4, 14
    W = w + 2 * ov
    H = tm + depth + apex_h + wall_h + 2
    im = Image.new("RGBA", (W, H))
    d = ImageDraw.Draw(im)
    x0, x1 = ov, ov + w - 1
    cx = (x0 + x1) // 2
    yb = H - 1
    ye = yb - wall_h
    ya = ye - apex_h
    rt = roof_tex(roof, W, H, seed)
    lp = [(0, ye + 3), (cx, ya - 1), (cx, ya - 1 - depth), (0, ye + 3 - depth)]
    rp = [(W - 1, ye + 3), (cx, ya - 1), (cx, ya - 1 - depth), (W - 1, ye + 3 - depth)]
    fill_poly(im, lp, shade(rt, 1.05))
    fill_poly(im, rp, shade(rt, 0.7))
    rp_ = roof_tex(roof, 4, 4, 0).getpixel((1, 1))
    d.line([(0, ye + 3 - depth), (cx, ya - 1 - depth), (W - 1, ye + 3 - depth)], fill=mul(rp_, 1.3))
    d.line([(cx, ya - 1), (cx, ya - 1 - depth)], fill=mul(rp_, 1.35))
    d.line([(cx + 1, ya - 1), (cx + 1, ya - 1 - depth)], fill=mul(rp_, 0.55))
    smoke = []
    if chimney:
        chx, chy = cx + w // 4, ya - depth + 2
        st = tex_stone(6, 13, seed + 3)
        im.paste(st, (chx, chy - 6))
        R(d, chx - 1, chy - 7, chx + 6, chy - 6, STONE[1])
        R(d, chx + 4, chy - 5, chx + 5, chy + 6, STONE[1])
        smoke.append((chx + 3, chy - 10))
    # gable face
    face = Image.new("L", im.size)
    fd = ImageDraw.Draw(face)
    fd.polygon([(x0, ye), (cx, ya + 1), (x1, ye)], fill=255)
    fd.rectangle([x0, ye, x1, yb], fill=255)
    im.paste(wall_tex(wall, W, H, seed + 1), (0, 0), face)
    if timber and wall == "plaster":
        for x in (x0, x1 - 1):
            R(d, x, ye, x + 1, yb - 4, WOOD[2])
        R(d, cx, ya + 3, cx, yb - 4, WOOD[2])
        R(d, x0, ye, x1, ye + 1, WOOD[2])
        R(d, x0, ye + wall_h // 2, x1, ye + wall_h // 2, WOOD[2])
        d.line([(x0 + 2, ye - 1), (cx - 3, ya + 6)], fill=WOOD[2])
        d.line([(x1 - 2, ye - 1), (cx + 3, ya + 6)], fill=WOOD[2])
    # shadow under the bargeboards (masked to the face)
    sh = Image.new("L", im.size)
    sd = ImageDraw.Draw(sh)
    sd.line([(x0 - 2, ye + 4), (cx, ya + 2), (x1 + 2, ye + 4)], fill=110, width=4)
    sh = ImageChops.multiply(sh, face)
    im.paste(Image.new("RGBA", im.size, (20, 14, 10, 255)), (0, 0), sh)
    # right edge shade
    shade_strip = Image.new("L", im.size)
    ImageDraw.Draw(shade_strip).rectangle([x1 - 1, ye, x1, yb], fill=70)
    im.paste(Image.new("RGBA", im.size, (10, 8, 6, 255)), (0, 0), ImageChops.multiply(shade_strip, face))
    # bargeboards
    d.line([(0, ye + 3), (cx, ya - 1), (W - 1, ye + 3)], fill=WOOD[1], width=3)
    d.line([(0, ye + 2), (cx, ya - 2), (W - 1, ye + 2)], fill=WOOD[3])
    # foundation
    im.paste(tex_stone(w, 4, seed + 2), (x0, yb - 3))
    R(d, x0, yb - 4, x1, yb - 4, STONE[1])
    # door, windows
    dw, dh = door
    arch_door(d, cx, yb - 1, dw, dh)
    if windows:
        slots = [x0 + (cx - x0) // 2 - 3, cx + (x1 - cx) // 2 - 3] if windows == 2 else \
            [x0 + 2, x0 + (cx - x0) // 2, cx + 4, x1 - 8]
        for sx in slots:
            window(d, sx, ye + 3, win_glow, shutters)
    glows = []
    if gable_window and apex_h >= 9:
        gy = ya + apex_h // 2 + 1
        d.ellipse([cx - 3, gy - 2, cx + 3, gy + 3], fill=WOOD[1])
        d.ellipse([cx - 2, gy - 1, cx + 2, gy + 2], fill=win_glow)
    if lantern:
        lx, ly = cx + dw // 2 + 2, yb - dh + 1
        d.line([(lx, ly), (lx + 2, ly)], fill=WOOD[0])
        R(d, lx + 2, ly + 1, lx + 4, ly + 4, CRYSTAL[3])
        glows.append((lx + 3, ly + 2, 12, GLOW))
    return im, glows, smoke


def pack(im, glows, smoke, fw=1, fh=1, shadow=(1.0, 8)):
    return Sprite(im, fw, fh, glows, smoke, shadow)


def b_cottage(seed=0, roof="thatch"):
    sh = random.Random(seed).choice([TEAL[2], hexc("a83a3a"), hexc("3a6a9a"), LEAF["green"][2]])
    return pack(*gable_house(23, 14, 11, 9, roof, "plaster", 2, seed, shutters=sh), shadow=(0.9, 9))


def b_hearth():
    W, H = 80, 96
    im = Image.new("RGBA", (W, H))
    for side, x in ((0, 0), (1, 52)):
        wing, _, _ = gable_house(21, 16, 9, 10, "slate", "plaster", 0, 40 + side, chimney=False,
                                 lantern=False, door=(5, 8), gable_window=True)
        im.alpha_composite(wing, (x, H - wing.height - 4))
    main, glows, smoke = gable_house(35, 26, 20, 14, "slate", "stone", 4, 7, door=(11, 17),
                                     gable_window=True, win_glow=WARM)
    mx = (W - main.width) // 2
    im.alpha_composite(main, (mx, H - main.height))
    d = ImageDraw.Draw(im)
    glows = [(x + mx, y + H - main.height, r, c) for x, y, r, c in glows]
    smoke = [(x + mx, y + H - main.height) for x, y in smoke]
    # banners
    for bx in (mx + 6, mx + main.width - 10):
        R(d, bx, H - 32, bx + 4, H - 20, hexc("9a2e2e"))
        d.polygon([(bx, H - 20), (bx + 2, H - 17), (bx + 4, H - 20)], fill=hexc("9a2e2e"))
        R(d, bx + 1, H - 28, bx + 3, H - 25, BRASS[3])
    return Sprite(im, 2, 2, glows, smoke, (1.0, 12))


def b_brazier():
    im = Image.new("RGBA", (16, 22))
    d = ImageDraw.Draw(im)
    R(d, 6, 12, 9, 20, STONE[2])
    R(d, 4, 19, 11, 21, STONE[1])
    d.ellipse([1, 8, 14, 14], fill=STONE[3])
    d.ellipse([3, 9, 12, 12], fill=STONE[0])
    d.polygon([(4, 11), (6, 3), (8, 7), (9, 0), (12, 11)], fill=CRYSTAL[2])
    d.polygon([(6, 11), (8, 4), (10, 11)], fill=CRYSTAL[4])
    return Sprite(im, glows=[(8, 6, 26, GLOW), (8, 6, 10, CRYSTAL[4])], shadow=(0.8, 4))


def b_tent(seed=0):
    rng = random.Random(seed)
    stripe = rng.choice([TEAL[2], hexc("a83a3a"), hexc("3a5a9a")])
    W, H = 36, 42
    im = Image.new("RGBA", (W, H))
    d = ImageDraw.Draw(im)
    ax, ay, cy, rx, ry = 18, 8, 35, 15, 4
    n = 10
    pts = []
    for i in range(n + 1):
        t = i / n
        x = ax - rx + t * 2 * rx
        y = cy + ry * math.sqrt(max(0, 1 - ((x - ax) / rx) ** 2))
        pts.append((x, y))
    for i in range(n):
        c = CANVAS[2] if i % 2 == 0 else stripe
        if pts[i][0] > ax:
            c = mul(c, 0.75)
        d.polygon([(ax, ay), pts[i], pts[i + 1]], fill=c)
    d.polygon([(ax, 15), (ax - 5, cy + ry), (ax + 5, cy + ry)], fill=WOOD[0])
    d.polygon([(ax, 17), (ax - 5, cy + ry), (ax - 3, cy + ry)], fill=CANVAS[3])
    for i in range(0, n, 1):
        x, y = pts[i]
        d.point((int(x) + 1, int(y) + 1), fill=BRASS[2])
    d.line([(ax, 2), (ax, ay)], fill=WOOD[1])
    d.polygon([(ax, 2), (ax + 7, 4), (ax, 6)], fill=hexc("c83a3a"))
    d.point((ax + 2, 3), fill=BRASS[3])
    return Sprite(im, glows=[], shadow=(0.9, 7))


def log_pile(d, x, y):
    for k, (lx, ly) in enumerate([(0, 6), (6, 6), (12, 6), (3, 1), (9, 1), (6, -4)]):
        cx, cy = x + lx, y + ly
        d.ellipse([cx, cy, cx + 6, cy + 6], fill=BARK[1])
        d.ellipse([cx + 1, cy + 1, cx + 5, cy + 5], fill=hexc("d8b07a"))
        d.point((cx + 3, cy + 3), fill=hexc("a87a4a"))


def b_woodcutter(seed=0):
    house, glows, smoke = gable_house(17, 12, 8, 8, "thatch", "planks", 0, seed, chimney=False, lantern=False,
                                      gable_window=False, door=(6, 9))
    W, H = house.width + 18, house.height
    im = Image.new("RGBA", (W, H))
    im.alpha_composite(house, (0, 0))
    d = ImageDraw.Draw(im)
    log_pile(d, house.width - 4, H - 16)
    d.ellipse([W - 10, H - 6, W - 2, H - 2], fill=BARK[2])
    d.ellipse([W - 9, H - 7, W - 3, H - 4], fill=hexc("d8b07a"))
    d.line([(W - 6, H - 7), (W - 3, H - 13)], fill=WOOD[3])
    R(d, W - 4, H - 15, W - 1, H - 13, ROCK[3])
    return Sprite(im, 1, 1, glows, smoke, (1.0, 8))


def b_lumen_mill():
    """Lumen Tap: timber tower over a crystal vein, crystal-paned sails turning as Lumen is drawn."""
    W, H = 56, 92
    im = Image.new("RGBA", (W, H))
    d = ImageDraw.Draw(im)
    cx = W // 2
    tb, tt = H - 3, 38
    wb, wt = 12, 8
    tower = [(cx - wb, tb), (cx - wt, tt), (cx + wt, tt), (cx + wb, tb)]
    fill_poly(im, tower, tex_planks(W, H, 5))
    fill_poly(im, [(cx + 1, tb), (cx + 1, tt), (cx + wt, tt), (cx + wb, tb)], shade(tex_planks(W, H, 6), 0.7))
    for y in (52, 68):
        d.line([(cx - wb + (tb - y) // 9, y), (cx + wb - (tb - y) // 9, y)], fill=WOOD[1], width=2)
    im.paste(tex_stone(28, 6, 9), (cx - 14, tb - 5))
    # crystal glowing through an arch
    d.ellipse([cx - 5, tb - 20, cx + 5, tb - 10], fill=WOOD[0])
    R(d, cx - 5, tb - 15, cx + 5, tb - 5, WOOD[0])
    crystal(d, cx - 4, tb - 5, 13, 8)
    window(d, cx - 3, 46, CRYSTAL[3], box=False, w=6, h=7)
    # cone roof
    rt = tex_shingle(W, H, SLATE)
    fill_poly(im, [(cx - 13, tt + 2), (cx, 14), (cx + 13, tt + 2)], rt)
    fill_poly(im, [(cx, tt + 2), (cx, 14), (cx + 13, tt + 2)], shade(rt, 0.68))
    d.line([(cx - 13, tt + 2), (cx + 13, tt + 2)], fill=WOOD[1], width=2)
    crystal(d, cx - 2, 15, 9, 4)
    # sails (crystal panes) around hub
    hx, hy = cx, tt - 6
    for k in range(4):
        a = math.pi / 4 + k * math.pi / 2 + 0.2
        ux, uy = math.cos(a), math.sin(a)
        vx, vy = -uy, ux
        p0 = (hx + ux * 4, hy + uy * 4)
        p1 = (hx + ux * 24, hy + uy * 24)
        quad = [(p0[0], p0[1]), (p1[0], p1[1]), (p1[0] + vx * 7, p1[1] + vy * 7), (p0[0] + vx * 5, p0[1] + vy * 5)]
        d.polygon(quad, fill=CRYSTAL[3] if k % 2 == 0 else CRYSTAL[2])
        d.line([p0, p1], fill=WOOD[3], width=2)
        for t in (0.4, 0.7):
            q = (p0[0] + (p1[0] - p0[0]) * t, p0[1] + (p1[1] - p0[1]) * t)
            d.line([q, (q[0] + vx * 6, q[1] + vy * 6)], fill=WOOD[2])
        d.line([quad[1], quad[2], quad[3]], fill=WOOD[2])
    d.ellipse([hx - 3, hy - 3, hx + 3, hy + 3], fill=BRASS[2])
    d.point((hx - 1, hy - 1), fill=BRASS[3])
    # barrel + pipe
    R(d, W - 12, tb - 10, W - 5, tb, WOOD[2])
    R(d, W - 12, tb - 7, W - 5, tb - 7, BRASS[1])
    d.ellipse([W - 12, tb - 12, W - 5, tb - 9], fill=CRYSTAL[3])
    d.line([(cx + wb - 2, tb - 12), (W - 9, tb - 12)], fill=BRASS[1], width=2)
    return Sprite(im, 1, 1, [(cx, tb - 10, 22, GLOW), (hx, hy, 18, GLOW), (cx, 14, 10, GLOW)], [], (1.2, 9))


def b_shrine():
    W, H = 48, 50
    im = Image.new("RGBA", (W, H))
    d = ImageDraw.Draw(im)
    d.ellipse([2, H - 16, W - 3, H - 2], fill=STONE[1])
    d.ellipse([2, H - 17, W - 3, H - 4], fill=STONE[3])
    d.ellipse([7, H - 15, W - 8, H - 6], fill=STONE[2])

    def standing(x, yb, h):
        d.rounded_rectangle([x, yb - h, x + 7, yb], 3, fill=ROCK[2])
        R(d, x + 5, yb - h + 2, x + 7, yb, ROCK[1])
        R(d, x + 1, yb - h + 1, x + 2, yb - h + 4, ROCK[3])
        for k in range(3):
            d.point((x + 3, yb - h + 5 + k * 4), fill=CRYSTAL[3])
            d.point((x + 4, yb - h + 6 + k * 4), fill=CRYSTAL[2])
        d.point([(x + 1, yb - h), (x + 2, yb - h)], fill=LEAF["green"][3])

    standing(6, H - 10, 20)
    standing(W - 14, H - 10, 22)
    R(d, W // 2 - 5, H - 14, W // 2 + 4, H - 8, STONE[3])
    R(d, W // 2 - 4, H - 12, W // 2 + 3, H - 8, STONE[2])
    cx, cy = W // 2, 14
    d.polygon([(cx, cy - 9), (cx + 6, cy), (cx, cy + 10), (cx - 6, cy)], fill=CRYSTAL[2])
    d.polygon([(cx, cy - 9), (cx, cy + 10), (cx - 6, cy)], fill=CRYSTAL[3])
    d.line([(cx - 3, cy - 2), (cx, cy - 7)], fill=CRYSTAL[4])
    for k, c in enumerate([hexc("e8506a"), hexc("f4f0e0"), hexc("7ab0f0"), hexc("f4c040")]):
        d.point((4 + k * 11, H - 3), fill=c)
    return Sprite(im, 1, 1, [(cx, cy, 24, GLOW), (cx, cy, 8, CRYSTAL[4])], [], (1.1, 6))


def b_bell_tower():
    W, H = 38, 116
    im = Image.new("RGBA", (W, H))
    d = ImageDraw.Draw(im)
    x0, x1 = 6, 31
    im.paste(tex_stone(x1 - x0 + 1, 44, 21), (x0, H - 45))
    sh = Image.new("L", im.size)
    ImageDraw.Draw(sh).rectangle([x1 - 5, H - 45, x1, H - 1], fill=80)
    im.paste(Image.new("RGBA", im.size, (10, 8, 6, 255)), (0, 0), sh)
    arch_door(d, (x0 + x1) // 2, H - 2, 9, 14)
    # timber upper with open belfry
    up = tex_plaster(x1 - x0 - 1, 30, 4)
    im.paste(up, (x0 + 1, H - 75))
    R(d, x0 + 1, H - 75, x0 + 2, H - 46, WOOD[2])
    R(d, x1 - 2, H - 75, x1 - 1, H - 46, WOOD[2])
    R(d, x0 + 1, H - 47, x1 - 1, H - 46, WOOD[2])
    d.ellipse([x0 + 6, H - 73, x1 - 6, H - 60], fill=WOOD[0])
    R(d, x0 + 6, H - 67, x1 - 6, H - 52, WOOD[0])
    bx = (x0 + x1) // 2
    d.polygon([(bx - 5, H - 54), (bx - 3, H - 65), (bx + 3, H - 65), (bx + 5, H - 54)], fill=BRASS[2])
    d.line([(bx - 2, H - 64), (bx - 3, H - 56)], fill=BRASS[3])
    R(d, x0 - 1, H - 78, x1 + 1, H - 75, WOOD[1])
    # witch-hat roof, slightly crooked
    rt = tex_shingle(W, H, SLATE)
    tipx, tipy = bx + 4, 6
    left = [(x0 - 4, H - 76)] + [(x0 - 4 + (tipx - x0 + 4) * t + 3 * math.sin(t * math.pi), H - 76 - (H - 76 - tipy) * t)
                                for t in (0.3, 0.6, 0.85)] + [(tipx, tipy)]
    right = [(tipx, tipy)] + [(x1 + 4 - (x1 + 4 - tipx) * t - 2 * math.sin(t * math.pi), H - 76 - (H - 76 - tipy) * t)
                              for t in (0.85, 0.6, 0.3)] + [(x1 + 4, H - 76)]
    fill_poly(im, left + right, rt)
    fill_poly(im, [(bx + 1, H - 76), (tipx, tipy)] + right[1:], shade(rt, 0.68))
    d.line([(x0 - 4, H - 76), (x1 + 4, H - 76)], fill=SLATE[0], width=2)
    crystal(d, tipx - 2, tipy + 2, 9, 5)
    d.line([(tipx + 2, tipy + 8), (tipx + 9, tipy + 12)], fill=WOOD[1])
    d.polygon([(tipx + 9, tipy + 9), (tipx + 16, tipy + 12), (tipx + 9, tipy + 15)], fill=hexc("c83a3a"))
    return Sprite(im, 1, 1, [(tipx, tipy - 3, 14, GLOW)], [], (1.4, 10))


def b_meeting_hall():
    main, glows, smoke = gable_house(45, 20, 18, 16, "thatch", "planks", 4, 11, door=(11, 15), lantern=True)
    W, H = main.width + 8, main.height
    im = Image.new("RGBA", (W, H))
    im.alpha_composite(main, (4, 0))
    d = ImageDraw.Draw(im)
    glows = [(x + 4, y, r, c) for x, y, r, c in glows]
    smoke = [(x + 4, y) for x, y in smoke]
    for x in (1, W - 6):
        R(d, x, H - 30, x + 4, H - 1, WOOD[2])
        R(d, x, H - 30, x + 1, H - 1, WOOD[3])
        for y in range(H - 26, H - 2, 6):
            d.line([(x, y), (x + 4, y + 2)], fill=WOOD[1])
        crystal(d, x, H - 30, 8, 5)
        glows.append((x + 2, H - 35, 9, GLOW))
    return Sprite(im, 2, 2, glows, smoke, (1.0, 12))


def b_market():
    W, H = 70, 50
    im = Image.new("RGBA", (W, H))
    d = ImageDraw.Draw(im)

    def stall(x, y, col):
        # counter
        im.paste(tex_planks(28, 9, x, vertical=True), (x, y + 18))
        R(d, x - 1, y + 16, x + 28, y + 18, WOOD[3])
        for k, c in enumerate([hexc("d84a3a"), hexc("f4c040"), LEAF["green"][3], CRYSTAL[3], hexc("e88a3a")]):
            d.ellipse([x + 1 + k * 5, y + 12, x + 5 + k * 5, y + 16], fill=c)
            d.point((x + 2 + k * 5, y + 13), fill=mul(c, 1.3))
        for px_ in (x, x + 26):
            R(d, px_, y + 2, px_ + 1, y + 26, WOOD[1])
        # awning: receding top plane + scalloped valance
        for s in range(0, 32, 4):
            c = col if (s // 4) % 2 == 0 else CANVAS[3]
            d.polygon([(x - 2 + s, y + 4), (x + 1 + s, y - 4), (x + 5 + s, y - 4), (x + 2 + s, y + 4)], fill=c)
            d.polygon([(x - 2 + s, y + 4), (x + 2 + s, y + 4), (x + 2 + s, y + 7), (x - 2 + s, y + 7)],
                      fill=mul(c, 0.85))
            d.ellipse([x - 2 + s, y + 5, x + 2 + s, y + 9], fill=mul(c, 0.85))

    stall(3, 14, hexc("b83a32"))
    stall(37, 14, TEAL[2])
    # crates + barrel
    for cx_, cy_ in ((4, 40), (12, 42)):
        R(d, cx_, cy_, cx_ + 7, cy_ + 7, WOOD[3])
        d.line([(cx_, cy_), (cx_ + 7, cy_ + 7)], fill=WOOD[1])
        R(d, cx_, cy_, cx_ + 7, cy_, WOOD[4])
    R(d, 58, 38, 66, 48, WOOD[2])
    R(d, 58, 41, 66, 41, BRASS[1])
    R(d, 58, 45, 66, 45, BRASS[1])
    d.ellipse([58, 36, 66, 40], fill=WOOD[3])
    return Sprite(im, 2, 2, [(33, 30, 12, WARM)], [], (1.0, 8))


def b_farm(seed=0):
    rng = random.Random(seed)
    W, H = 64, 72
    im = Image.new("RGBA", (W, H))
    d = ImageDraw.Draw(im)
    y0 = 8
    R(d, 0, y0, W - 1, H - 1, DIRT[1])
    for y in range(y0 + 2, H - 2, 6):
        R(d, 1, y, W - 2, y + 2, DIRT[2])
        R(d, 1, y + 3, W - 2, y + 3, DIRT[0])
        d.line([(1, y), (W - 2, y)], fill=DIRT[3])
    glows = []
    rows = list(range(y0 + 4, H - 4, 6))
    for ri, y in enumerate(rows):
        crop = ["glow", "cabbage", "wheat", "cabbage", "glow", "wheat", "cabbage", "wheat", "glow", "cabbage"][ri % 10]
        for x in range(4, W - 4, 7):
            if crop == "cabbage":
                d.ellipse([x - 3, y - 3, x + 3, y + 2], fill=LEAF["green"][1])
                d.ellipse([x - 2, y - 3, x + 2, y + 1], fill=LEAF["green"][3])
                d.point((x - 1, y - 2), fill=LEAF["green"][4])
            elif crop == "wheat":
                for k in (-2, 0, 2):
                    d.line([(x + k, y + 1), (x + k, y - 5)], fill=THATCH[3])
                    d.point((x + k, y - 6), fill=THATCH[4])
            else:
                d.line([(x, y + 1), (x, y - 3)], fill=LEAF["green"][2])
                d.ellipse([x - 2, y - 7, x + 2, y - 3], fill=hexc("4a6ad8"))
                d.point((x - 1, y - 6), fill=CRYSTAL[4])
                if rng.random() < 0.5:
                    glows.append((x, y - 5, 6, GLOW))
    # fence top
    for x in range(0, W, 7):
        R(d, x, 0, x + 1, y0 + 2, WOOD[2])
        d.point((x, 0), fill=WOOD[3])
    d.line([(0, 3), (W - 1, 3)], fill=WOOD[3])
    d.line([(0, 6), (W - 1, 6)], fill=WOOD[2])
    return Sprite(im, 2, 2, glows, [], None)


def b_bridge(length_px):
    W, H = length_px, 26
    im = Image.new("RGBA", (W, H))
    d = ImageDraw.Draw(im)
    im.paste(tex_planks(W, 14, 3), (0, 6))
    for x in range(0, W, 10):
        R(d, x, 0, x + 2, 8, WOOD[2])
        R(d, x, 18, x + 2, 25, WOOD[1])
    d.line([(0, 2), (W - 1, 2)], fill=WOOD[3], width=2)
    R(d, 0, 20, W - 1, 21, WOOD[1])
    return sel_outline(im)


# ------------------------------------------------------------------ town / city buildings
IRON = pal("1c2026", "2e343c", "48505a", "68727e", "909aa6")
PLASTER_OCHRE = pal("b08e5e", "ccac7a", "e0c290", "f0d8aa")


def pipe(d, pts, w=3, p=BRASS):
    d.line(pts, fill=p[1], width=w)
    d.line([(x, y - w // 2) for x, y in pts], fill=p[3])


def cylinder(d, x0, x1, y0, y1, p, light=0.3):
    """Vertical cylinder body: columns shaded from a highlight at `light` (0..1 across)."""
    n = len(p)
    for x in range(x0, x1 + 1):
        t = (x - x0) / max(1, x1 - x0)
        v = 1 - abs(t - light) * 1.5
        d.line([(x, y0), (x, y1)], fill=p[max(0, min(n - 1, int(round(v * (n - 1)))))])


def paste_box(dst, src, x0, y0, x1, y1):
    dst.paste(src.crop((x0, y0, x1 + 1, y1 + 1)), (x0, y0))


def glow_arch(d, cx, yb, w, h, glows):
    """Arched opening with Lumen light inside."""
    x0 = cx - w // 2
    R(d, x0, yb - h + w // 2, x0 + w - 1, yb, IRON[0])
    d.ellipse([x0, yb - h, x0 + w - 1, yb - h + w], fill=IRON[0])
    R(d, x0 + 1, yb - h + w // 2, x0 + w - 2, yb, CRYSTAL[2])
    d.ellipse([x0 + 1, yb - h + 1, x0 + w - 2, yb - h + w - 1], fill=CRYSTAL[2])
    R(d, x0 + 2, yb - h + w // 2, x0 + 3, yb, CRYSTAL[4])
    glows.append((cx, yb - h // 2, max(8, w + 4), GLOW))


def b_rowhouse(seed=0):
    """Three attached two-storey houses sharing walls; brass drainpipes between them."""
    specs = [("slate", "plaster"), ("shingle", "stone"), ("slate", "plaster")]
    parts = [gable_house(17, 26, 9, 9, r, w, 2, seed + i * 5, chimney=i != 1, door=(6, 10))
             for i, (r, w) in enumerate(specs)]
    pw, ph = parts[0][0].size
    step = pw - 5
    W, H = step * 2 + pw, ph
    im = Image.new("RGBA", (W, H))
    d = ImageDraw.Draw(im)
    ye = H - 1 - 26
    for k in (1, 2):
        im.paste(tex_stone(6, H - ye, seed + k), (k * step, ye))
    glows, smoke = [], []
    for i, (p, g, s) in enumerate(parts):
        x = i * step
        im.alpha_composite(p, (x, 0))
        glows += [(gx + x, gy, r, c) for gx, gy, r, c in g]
        smoke += [(sx + x, sy) for sx, sy in s]
    for k in (1, 2):
        x = k * step + 2
        R(d, x, ye + 4, x, H - 5, BRASS[1])
        R(d, x - 1, H - 5, x + 1, H - 4, BRASS[1])
        d.point((x, ye + 4), fill=BRASS[3])
    return Sprite(im, 2, 1, glows, smoke, (1.0, 9))


def b_greenhouse(seed=0):
    """Long glass house on a stone footing, iron frame, glowing Lumen flora visible inside."""
    rng = random.Random(seed)
    W, H = 64, 56
    x0, x1, yb = 3, 60, H - 1
    wy = yb - 18
    ry = wy - 24
    glows = []
    inner = Image.new("RGBA", (W, H), hexc("1f4a3a"))
    idr = ImageDraw.Draw(inner)
    for _ in range(90):
        x, y, r = rng.randint(x0, x1), rng.randint(ry + 2, yb - 4), rng.randint(2, 4)
        idr.ellipse([x - r, y - r, x + r, y + r], fill=rng.choice(LEAF["green"][1:4] + LEAF["deep"][2:4]))
    for _ in range(16):
        x, y = rng.randint(x0 + 3, x1 - 3), rng.randint(ry + 4, yb - 7)
        col = rng.choice([CRYSTAL[3], CRYSTAL[4], hexc("f4c040"), hexc("e8506a")])
        idr.point([(x, y), (x + 1, y), (x, y + 1)], fill=col)
        if col in (CRYSTAL[3], CRYSTAL[4]):
            glows.append((x, y, 6, GLOW))
    glint = Image.new("RGBA", (W, H))
    gd = ImageDraw.Draw(glint)
    for k in range(-H, W, 15):
        gd.line([(k, H), (k + H, 0)], fill=(255, 255, 255, 70), width=2)
    roof, wall = inner.copy(), inner.copy()
    roof.alpha_composite(Image.new("RGBA", (W, H), CRYSTAL[3][:3] + (125,)))
    roof.alpha_composite(glint)
    wall.alpha_composite(Image.new("RGBA", (W, H), CRYSTAL[2][:3] + (60,)))
    wall.alpha_composite(glint)
    im = Image.new("RGBA", (W, H))
    d = ImageDraw.Draw(im)
    paste_box(im, shade(roof, 0.62), x0, ry - 4, x1, ry - 1)
    paste_box(im, roof, x0 - 2, ry, x1 + 2, wy)
    paste_box(im, wall, x0, wy + 1, x1, yb - 5)
    im.paste(tex_stone(x1 - x0 + 1, 5, seed), (x0, yb - 4))
    R(d, x0, yb - 5, x1, yb - 5, STONE[4])
    # iron frame
    for x in range(x0, x1 + 1, 7):
        d.line([(x, ry), (x, wy)], fill=IRON[2])
        d.line([(x, wy + 1), (x, yb - 5)], fill=IRON[1])
    for y in (ry + 8, ry + 16):
        d.line([(x0 - 2, y), (x1 + 2, y)], fill=IRON[2])
    d.line([(x0, wy + 8), (x1, wy + 8)], fill=IRON[1])
    R(d, x0 - 2, wy, x1 + 2, wy + 1, IRON[1])
    d.line([(x0 - 2, wy), (x1 + 2, wy)], fill=IRON[3])
    d.line([(x0 - 1, ry), (x1 + 1, ry)], fill=IRON[3])
    d.line([(x0, ry - 4), (x1, ry - 4)], fill=IRON[1])
    for x in (x0, x1):
        R(d, x - 1, ry - 9, x, ry, BRASS[1])
        d.point((x - 1, ry - 10), fill=BRASS[3])
    cx = (x0 + x1) // 2
    crystal(d, cx - 2, ry - 2, 8, 4)
    glows.append((cx, ry - 6, 10, GLOW))
    # glass door + planters
    R(d, cx - 4, yb - 16, cx + 4, yb - 1, BRASS[1])
    R(d, cx - 3, yb - 15, cx + 3, yb - 1, mul(CRYSTAL[2], 0.8))
    d.line([(cx, yb - 15), (cx, yb - 1)], fill=BRASS[1])
    d.point((cx - 2, yb - 13), fill=CRYSTAL[4])
    for x in (x0 + 5, x1 - 10, x0 + 16):
        R(d, x, yb - 4, x + 4, yb, hexc("b0603a"))
        R(d, x, yb - 4, x + 4, yb - 4, hexc("d07a4a"))
        d.ellipse([x - 1, yb - 9, x + 5, yb - 3], fill=LEAF["green"][3])
        d.point((x + 1, yb - 8), fill=hexc("e8506a"))
    return Sprite(im, 2, 1, glows, [], (1.0, 9))


def b_lumen_pump():
    """Iron derrick sunk into a Lumen vein; the pad is already stained with blight."""
    W, H = 50, 88
    im = Image.new("RGBA", (W, H))
    d = ImageDraw.Draw(im)
    cx, yb = 22, H - 1
    glows = []
    d.ellipse([0, yb - 13, W - 1, yb], fill=BLIGHT[1])
    d.ellipse([3, yb - 12, W - 6, yb - 2], fill=BLIGHT[2])
    m = Image.new("L", im.size)
    ImageDraw.Draw(m).ellipse([5, yb - 11, W - 9, yb - 2], fill=255)
    im.paste(tex_stone(W, H, 3), (0, 0), m)
    d.line([(cx - 14, yb - 5), (cx - 8, yb - 7), (cx - 3, yb - 4)], fill=CRYSTAL[2])
    d.line([(cx + 6, yb - 3), (cx + 12, yb - 6)], fill=CRYSTAL[2])
    rng = random.Random(4)
    for _ in range(14):
        a = rng.uniform(0, 2 * math.pi)
        d.point((int(cx + 2 + math.cos(a) * 23), int(yb - 6 + math.sin(a) * 6)), fill=BLIGHT[4])
    # derrick
    top = 16
    span = yb - 6 - top
    for xa, xb in ((cx - 13, cx - 3), (cx + 13, cx + 3)):
        d.line([(xa, yb - 6), (xb, top)], fill=IRON[3], width=2)
    for y in range(top + 6, yb - 14, 10):
        h0 = 3 + 10 * (y - top) / span
        h1 = 3 + 10 * (y + 10 - top) / span
        d.line([(cx - h0, y), (cx + h1, y + 10)], fill=IRON[1])
        d.line([(cx + h0, y), (cx - h1, y + 10)], fill=IRON[1])
        d.line([(cx - h0, y), (cx + h0, y)], fill=IRON[2])
    # glowing core pipe
    R(d, cx - 2, top + 3, cx + 2, yb - 8, IRON[1])
    R(d, cx - 1, top + 3, cx + 1, yb - 8, CRYSTAL[2])
    d.line([(cx, top + 3), (cx, yb - 8)], fill=CRYSTAL[4])
    for y in range(top + 8, yb - 24, 12):
        glows.append((cx, y, 8, GLOW))
    # crown block, wheel, vent
    R(d, cx + 4, top - 14, cx + 6, top - 3, IRON[2])
    R(d, cx + 3, top - 15, cx + 7, top - 14, IRON[3])
    d.ellipse([cx - 5, top - 11, cx + 3, top - 3], fill=BRASS[1])
    d.ellipse([cx - 3, top - 9, cx + 1, top - 5], fill=BRASS[3])
    d.point((cx - 1, top - 7), fill=BRASS[0])
    R(d, cx - 7, top - 3, cx + 7, top + 2, IRON[3])
    R(d, cx - 7, top + 1, cx + 7, top + 2, IRON[1])
    # pump housing
    hx0, hx1, hy0 = cx - 9, cx + 9, yb - 24
    R(d, cx - 1, hy0 - 7, cx + 1, hy0, BRASS[2])
    R(d, hx0, hy0, hx1, yb - 6, IRON[2])
    R(d, hx0, hy0, hx1, hy0 + 1, IRON[4])
    R(d, hx1 - 3, hy0 + 2, hx1, yb - 6, IRON[1])
    for px_, py_ in ((hx0 + 1, hy0 + 3), (hx1 - 4, hy0 + 3), (hx0 + 1, yb - 8), (hx1 - 4, yb - 8)):
        d.point((px_, py_), fill=IRON[4])
    R(d, cx - 4, hy0 + 4, cx + 3, hy0 + 11, IRON[0])
    R(d, cx - 3, hy0 + 5, cx + 2, hy0 + 10, CRYSTAL[3])
    d.point((cx - 2, hy0 + 6), fill=CRYSTAL[4])
    glows.append((cx, hy0 + 7, 11, GLOW))
    # storage tank
    tx0, tx1 = W - 14, W - 3
    pipe(d, [(hx1, yb - 14), (tx0, yb - 14)])
    cylinder(d, tx0, tx1, yb - 30, yb - 6, BRASS)
    d.ellipse([tx0, yb - 33, tx1, yb - 27], fill=BRASS[3])
    d.ellipse([tx0 + 2, yb - 32, tx1 - 2, yb - 28], fill=BRASS[2])
    for y in (yb - 24, yb - 12):
        R(d, tx0, y, tx1, y, BRASS[0])
    R(d, tx0 + 4, yb - 23, tx0 + 6, yb - 13, CRYSTAL[3])
    glows.append((tx0 + 5, yb - 18, 9, GLOW))
    return Sprite(im, 1, 1, glows, [(cx + 5, top - 18)], (1.0, 8))


def b_cleanser(seed=0):
    """Stone works that scrubs blight: teal roof, tall vapour stack, clear settling basin."""
    house, glows, _ = gable_house(27, 16, 10, 9, "teal", "stone", 2, seed, chimney=False, door=(5, 10))
    W, H = house.width + 20, house.height + 16
    im = Image.new("RGBA", (W, H))
    d = ImageDraw.Draw(im)
    hy = H - house.height
    sx = house.width + 4
    cylinder(d, sx, sx + 6, 6, H - 12, IRON)
    for y in (12, 26, 40):
        R(d, sx - 1, y, sx + 7, y + 1, BRASS[2])
    R(d, sx - 2, 3, sx + 8, 6, IRON[3])
    R(d, sx - 2, 3, sx + 8, 3, IRON[4])
    im.alpha_composite(house, (0, hy))
    glows = [(x, y + hy, r, c) for x, y, r, c in glows]
    # leaf sigil on the stack
    gx, gy = sx + 3, 33
    d.ellipse([gx - 4, gy - 4, gx + 4, gy + 4], fill=BRASS[1])
    d.polygon([(gx - 2, gy + 2), (gx, gy - 3), (gx + 3, gy - 2), (gx + 1, gy + 2)], fill=LEAF["green"][4])
    d.line([(gx - 2, gy + 2), (gx + 2, gy - 2)], fill=LEAF["green"][1])
    # settling basin
    tx0, tx1 = house.width - 8, W - 2
    pipe(d, [(house.width - 6, H - 22), (house.width - 2, H - 22), (house.width - 2, H - 16)])
    cylinder(d, tx0, tx1, H - 15, H - 2, STONE)
    d.ellipse([tx0, H - 19, tx1, H - 11], fill=STONE[3])
    d.ellipse([tx0 + 2, H - 18, tx1 - 2, H - 12], fill=WATER[4])
    d.arc([tx0 + 4, H - 17, tx1 - 6, H - 13], 180, 300, fill=WATER[5])
    d.point(((tx0 + tx1) // 2 + 2, H - 15), fill=WATER[5])
    glows.append(((tx0 + tx1) // 2, H - 15, 12, GLOW))
    for x in (2, 8):
        d.ellipse([x, H - 6, x + 5, H - 1], fill=LEAF["green"][3])
        d.point((x + 2, H - 5), fill=hexc("f4f0e0"))
    return Sprite(im, 2, 1, glows, [(sx + 3, 0)], (1.0, 9))


def b_lumen_spire():
    """Town landmark: buttressed stone spire wrapped in a glowing conduit, crowned by a great crystal."""
    W, H = 56, 156
    im = Image.new("RGBA", (W, H))
    d = ImageDraw.Draw(im)
    cx, yb = W // 2, H - 1
    glows = []
    st = tex_stone(W, H, 31)
    im.paste(tex_stone(W - 6, 8, 32), (3, yb - 7))
    R(d, 3, yb - 8, W - 4, yb - 8, STONE[4])
    im.paste(tex_stone(W - 16, 8, 33), (8, yb - 15))
    R(d, 8, yb - 16, W - 9, yb - 16, STONE[4])
    base, ty = yb - 16, 44
    for sgn in (-1, 1):
        poly = [(cx + sgn * 22, base), (cx + sgn * 10, base), (cx + sgn * 8, base - 56), (cx + sgn * 11, base - 52)]
        fill_poly(im, poly, shade(st, 0.88 if sgn < 0 else 0.6))
        d.line([(cx + sgn * 22, base), (cx + sgn * 11, base - 52)], fill=STONE[4] if sgn < 0 else STONE[1])
    top_hw, base_hw = 5, 11

    def hw(y):
        return top_hw + (base_hw - top_hw) * (y - ty) / (base - ty)

    fill_poly(im, [(cx - base_hw, base), (cx - top_hw, ty), (cx + top_hw, ty), (cx + base_hw, base)], st)
    fill_poly(im, [(cx + 3, base), (cx + 1, ty), (cx + top_hw, ty), (cx + base_hw, base)], shade(st, 0.68))
    for y in (ty + 8, ty + 44, base - 22):
        R(d, cx - hw(y) - 1, y, cx + hw(y) + 1, y + 2, BRASS[1])
        d.line([(cx - hw(y) - 1, y), (cx + hw(y) + 1, y)], fill=BRASS[3])
    n = 900
    for i in range(n):
        t = i / n
        y = base - 4 - t * (base - ty - 8)
        a = t * 4.5 * 2 * math.pi
        if math.cos(a) > -0.15:
            x = cx + math.sin(a) * hw(y) * 0.9
            d.point((int(x), int(y)), fill=CRYSTAL[4] if math.cos(a) > 0.5 else CRYSTAL[2])
            d.point((int(x), int(y) + 1), fill=CRYSTAL[1])
            if i % 60 == 0 and math.cos(a) > 0.5:
                glows.append((int(x), int(y), 7, GLOW))
    glow_arch(d, cx, base, 9, 13, glows)
    R(d, cx - top_hw - 2, ty - 2, cx + top_hw + 2, ty + 2, BRASS[1])
    d.line([(cx - top_hw - 2, ty - 2), (cx + top_hw + 2, ty - 2)], fill=BRASS[3])
    crystal(d, cx - 8, ty - 2, 34, 16)
    for sgn in (-1, 1):
        d.line([(cx + sgn * 6, ty - 1), (cx + sgn * 10, ty - 10), (cx + sgn * 8, ty - 19)], fill=BRASS[2], width=2)
        d.point((cx + sgn * 8, ty - 20), fill=BRASS[3])
    crystal(d, cx - 18, ty - 18, 8, 4)
    crystal(d, cx + 14, ty - 26, 7, 3)
    glows += [(cx, ty - 18, 34, GLOW), (cx, ty - 18, 12, CRYSTAL[4]), (cx - 16, ty - 22, 7, GLOW),
              (cx + 15, ty - 30, 7, GLOW)]
    return Sprite(im, 2, 2, glows, [], (0.9, 12))


def b_apartment(seed=0):
    """City housing: four storeys, mansard slate roof with dormers, shopfronts on the ground floor."""
    rng = random.Random(seed)
    W, H = 64, 118
    im = Image.new("RGBA", (W, H))
    d = ImageDraw.Draw(im)
    x0, x1, yb = 4, 59, H - 1
    cx = (x0 + x1) // 2
    glows, smoke = [], []
    cy = 34
    R(d, x0 + 4, 9, x1 - 4, 14, SLATE[1])
    R(d, x0 + 4, 9, x1 - 4, 9, SLATE[3])
    for chx in (x0 + 8, x1 - 14):
        im.paste(tex_stone(7, 12, seed + chx), (chx, 1))
        R(d, chx - 1, 0, chx + 7, 1, STONE[1])
        R(d, chx + 5, 2, chx + 6, 12, STONE[1])
        smoke.append((chx + 3, -2))
    fill_poly(im, [(x0 + 4, 14), (x1 - 4, 14), (x1 + 2, cy), (x0 - 2, cy)], tex_shingle(W, H, SLATE))
    fill_poly(im, [(cx + 14, 14), (x1 - 4, 14), (x1 + 2, cy), (cx + 16, cy)], shade(tex_shingle(W, H, SLATE), 0.75))
    for dx in (x0 + 5, cx - 4, x1 - 13):
        R(d, dx, 19, dx + 8, 30, PLASTER[2])
        R(d, dx + 7, 20, dx + 8, 30, PLASTER[0])
        window(d, dx + 1, 21, WARM if rng.random() < 0.7 else hexc("34445a"), box=False, w=7, h=8)
        d.polygon([(dx - 1, 20), (dx + 4, 14), (dx + 9, 20)], fill=SLATE[2])
        d.line([(dx - 1, 20), (dx + 4, 14), (dx + 9, 20)], fill=SLATE[4])
    R(d, x0 - 2, cy, x1 + 2, cy + 2, STONE[4])
    R(d, x0 - 2, cy + 3, x1 + 2, cy + 3, STONE[1])
    fy0, fy1 = cy + 4, yb - 20
    walls = rng.choice([PLASTER, PLASTER_OCHRE])
    im.paste(tex_plaster(x1 - x0 + 1, fy1 - fy0 + 1, seed, walls), (x0, fy0))
    for k in range(3):
        yf = fy0 + k * 18
        for i in range(4):
            wx = x0 + 5 + i * 13
            lit = rng.random() < 0.6
            window(d, wx, yf + 4, WARM if lit else hexc("34445a"), box=False, w=7, h=9)
            R(d, wx - 1, yf + 3, wx + 7, yf + 3, walls[0])
            R(d, wx - 1, yf + 13, wx + 7, yf + 13, STONE[3])
        if k == 1:
            for bx in (x0 + 17, x0 + 30):
                R(d, bx - 1, yf + 11, bx + 9, yf + 14, STONE[2])
                R(d, bx - 1, yf + 8, bx + 9, yf + 8, IRON[2])
                for px_ in range(bx - 1, bx + 10, 2):
                    d.line([(px_, yf + 8), (px_, yf + 11)], fill=IRON[1])
                for px_ in range(bx, bx + 9, 3):
                    d.point((px_, yf + 7), fill=rng.choice([hexc("e8506a"), hexc("f4c040"), hexc("f4f0e0")]))
                    d.point((px_ + 1, yf + 7), fill=LEAF["green"][3])
        R(d, x0, yf + 17, x1, yf + 17, STONE[2])
    im.paste(tex_stone(x1 - x0 + 1, 20, seed + 9), (x0, yb - 19))
    R(d, x0, yb - 20, x1, yb - 20, STONE[4])
    arch_door(d, cx, yb - 1, 9, 15)
    awn = rng.choice([hexc("b83a32"), TEAL[2], hexc("3a5a9a")])
    for sx in (x0 + 3, x1 - 17):
        window(d, sx, yb - 14, WARM, box=False, w=14, h=10)
        for s in range(0, 16, 2):
            R(d, sx - 1 + s, yb - 19, sx + s, yb - 16, awn if s % 4 == 0 else CANVAS[3])
        R(d, sx - 1, yb - 15, sx + 15, yb - 15, mul(awn, 0.7))
        glows.append((sx + 7, yb - 9, 12, WARM))
    lx, ly = cx + 7, yb - 14
    R(d, lx, ly, lx + 2, ly, WOOD[0])
    R(d, lx + 2, ly + 1, lx + 4, ly + 4, CRYSTAL[3])
    glows.append((lx + 3, ly + 2, 12, GLOW))
    paste_box(im, shade(im, 0.72), x1 - 2, fy0, x1, yb)
    return Sprite(im, 2, 2, glows, smoke, (1.0, 14))


def b_reactor():
    """Brass-and-iron drum under a glass dome caging a huge Lumen crystal; cooling stacks steam."""
    W, H = 70, 96
    im = Image.new("RGBA", (W, H))
    d = ImageDraw.Draw(im)
    cx, yb = W // 2, H - 1
    glows, smoke = [], []
    for sx in (4, W - 12):
        cylinder(d, sx, sx + 7, 18, yb - 14, IRON)
        for y in (30, 50):
            R(d, sx, y, sx + 7, y + 1, BRASS[1])
        R(d, sx - 1, 16, sx + 8, 19, BRASS[2])
        d.ellipse([sx, 14, sx + 7, 18], fill=IRON[0])
        smoke.append((sx + 4, 10))
    im.paste(tex_stone(W - 4, 10, 41), (2, yb - 9))
    R(d, 2, yb - 10, W - 3, yb - 10, STONE[4])
    dx0, dx1, dt = 12, W - 13, 52
    cylinder(d, dx0, dx1, dt, yb - 10, IRON)
    for y in (dt + 3, yb - 16):
        R(d, dx0, y, dx1, y + 1, BRASS[2])
        d.line([(dx0, y), (dx1, y)], fill=BRASS[3])
    for x in range(dx0 + 3, dx1, 5):
        d.point((x, dt + 7), fill=IRON[4])
        d.point((x, yb - 19), fill=IRON[4])
    for px_ in (cx - 15, cx + 15):
        d.ellipse([px_ - 4, dt + 10, px_ + 4, dt + 18], fill=BRASS[1])
        d.ellipse([px_ - 3, dt + 11, px_ + 3, dt + 17], fill=CRYSTAL[3])
        d.point((px_ - 1, dt + 12), fill=CRYSTAL[4])
        glows.append((px_, dt + 14, 10, GLOW))
    R(d, cx - 6, dt + 10, cx + 6, yb - 10, BRASS[1])
    R(d, cx - 5, dt + 11, cx + 5, yb - 10, IRON[1])
    R(d, cx - 5, dt + 20, cx + 5, dt + 20, IRON[3])
    d.ellipse([cx - 2, dt + 14, cx + 2, dt + 18], fill=BRASS[3])
    for sgn in (-1, 1):
        xa = cx + sgn * 7
        pts = [(xa, yb - 5), (cx + sgn * 32, yb - 5)]
        d.line(pts, fill=CRYSTAL[1], width=3)
        d.line(pts, fill=CRYSTAL[4])
        glows += [(cx + sgn * k, yb - 5, 6, GLOW) for k in (12, 22, 31)]
    # dome: glass over the core crystal, brass ribs on top
    d.chord([dx0, dt - 26, dx1, dt + 26], 180, 360, fill=CRYSTAL[1])
    d.chord([dx0 + 3, dt - 23, dx1 - 3, dt + 23], 180, 360, fill=mul(CRYSTAL[1], 0.8))
    crystal(d, cx - 7, dt, 24, 14)
    crystal(d, cx - 15, dt, 11, 6)
    crystal(d, cx + 9, dt, 13, 6)
    rx, ry_ = (dx1 - dx0) / 2, 26
    for u in (-0.9, -0.5, 0, 0.5, 0.9):
        pts = [(cx + u * rx * math.cos(t), dt - ry_ * math.sin(t)) for t in [k / 10 * math.pi / 2 for k in range(11)]]
        d.line(pts, fill=BRASS[2])
    d.arc([dx0 + 5, dt - 22, dx1 - 18, dt + 10], 200, 250, fill=CRYSTAL[4])
    R(d, dx0 - 1, dt - 1, dx1 + 1, dt + 1, BRASS[2])
    d.line([(dx0 - 1, dt - 1), (dx1 + 1, dt - 1)], fill=BRASS[3])
    d.ellipse([cx - 3, dt - 29, cx + 3, dt - 24], fill=BRASS[2])
    d.line([(cx, dt - 34), (cx, dt - 29)], fill=BRASS[3])
    glows += [(cx, dt - 10, 32, GLOW), (cx, dt - 10, 12, CRYSTAL[4])]
    return Sprite(im, 2, 2, glows, smoke, (1.0, 12))


def b_park(seed=0):
    """Hedged lawn with paths, a Lumen fountain, benches, flower beds and two trees."""
    rng = random.Random(seed)
    W, H = 64, 82
    im = Image.new("RGBA", (W, H))
    d = ImageDraw.Draw(im)
    top = H - 64
    glows = []
    d.rounded_rectangle([0, top, W - 1, H - 1], 6, fill=LEAF["deep"][1])
    d.rounded_rectangle([0, top, W - 1, H - 3], 6, fill=LEAF["deep"][3])
    for x in range(3, W - 3, 4):
        d.point([(x, top + 1), (x + 1, top + 1)], fill=LEAF["deep"][4])
    d.rounded_rectangle([3, top + 3, W - 4, H - 5], 4, fill=GRASS[3])
    for _ in range(160):
        d.point((rng.randint(4, W - 5), rng.randint(top + 4, H - 6)), fill=rng.choice([GRASS[2], GRASS[4]]))
    cx, cy = W // 2, top + 34
    for box in ((cx - 4, top + 3, cx + 3, H - 1), (3, cy - 3, W - 4, cy + 3)):
        R(d, *box, COBBLE[1])
        for _ in range(40):
            x, y = rng.randint(box[0], box[2] - 1), rng.randint(box[1], box[3])
            d.point([(x, y), (x + 1, y)], fill=rng.choice(COBBLE[2:]))
    for fx, fy in ((13, top + 50), (W - 15, top + 50)):
        d.ellipse([fx - 7, fy - 4, fx + 7, fy + 4], fill=DIRT[1])
        for _ in range(14):
            x, y = fx + rng.randint(-5, 5), fy + rng.randint(-2, 2)
            d.point((x, y - 1), fill=LEAF["green"][3])
            d.point((x, y - 2), fill=rng.choice([hexc("e8506a"), hexc("f4c040"), hexc("f4f0e0"), CRYSTAL[3]]))
    # trees (back quadrants)
    for i, (tx, kind) in enumerate(((14, "green"), (W - 14, "lumen"))):
        ty_ = top + 26
        d.ellipse([tx - 9, ty_ - 3, tx + 10, ty_ + 2], fill=GRASS[1])
        t = oak(seed * 10 + i, 0.62, kind)
        ox, oy = tx - t.img.width // 2, ty_ - t.img.height
        im.alpha_composite(t.img, (ox, oy))
        glows += [(gx + ox, gy + oy, r, c) for gx, gy, r, c in t.glows]
    # fountain
    d.ellipse([cx - 13, cy - 7, cx + 13, cy + 8], fill=STONE[1])
    d.ellipse([cx - 13, cy - 8, cx + 13, cy + 6], fill=STONE[3])
    d.ellipse([cx - 10, cy - 6, cx + 10, cy + 4], fill=WATER[3])
    d.ellipse([cx - 8, cy - 5, cx + 3, cy + 1], fill=WATER[4])
    d.arc([cx - 7, cy - 4, cx + 7, cy + 3], 20, 160, fill=WATER[5])
    R(d, cx - 1, cy - 12, cx + 1, cy - 1, STONE[3])
    d.ellipse([cx - 5, cy - 14, cx + 5, cy - 10], fill=STONE[3])
    d.ellipse([cx - 4, cy - 13, cx + 4, cy - 11], fill=WATER[4])
    crystal(d, cx - 2, cy - 12, 8, 4)
    for sgn in (-1, 1):
        for k in range(4):
            d.point((cx + sgn * (4 + k * 2), cy - 13 + k * k), fill=CRYSTAL[4])
    glows += [(cx, cy - 8, 18, GLOW), (cx, cy - 16, 7, CRYSTAL[4])]
    for bx in (cx - 24, cx + 16):
        R(d, bx, cy + 7, bx + 7, cy + 7, WOOD[2])
        R(d, bx, cy + 9, bx + 7, cy + 10, WOOD[3])
        d.point([(bx, cy + 11), (bx + 7, cy + 11)], fill=WOOD[1])
    for lx in (5, W - 12):
        lp = lantern_post()
        ox, oy = lx, H - 6 - lp.img.height
        im.alpha_composite(lp.img, (ox, oy))
        glows += [(gx + ox, gy + oy, r, c) for gx, gy, r, c in lp.glows]
    return Sprite(im, 2, 2, glows, [], None)


def b_skyheart():
    """Final landmark: a stepped stone tower holding a huge crystal heart that floats above it, ringed in brass."""
    W, H = 112, 236
    im = Image.new("RGBA", (W, H))
    d = ImageDraw.Draw(im)
    cx, yb = W // 2, H - 1
    glows = []
    st = tex_stone(W, H, 77)
    im.paste(tex_stone(W - 8, 12, 78), (4, yb - 11))
    R(d, 4, yb - 12, W - 5, yb - 12, STONE[4])
    im.paste(tex_stone(W - 28, 12, 79), (14, yb - 23))
    R(d, 14, yb - 24, W - 15, yb - 24, STONE[4])
    for ax in (16, 32, W - 33, W - 17):
        glow_arch(d, ax, yb - 1, 7, 9, glows)
    base, ty = yb - 24, 100
    for sgn in (-1, 1):
        px_ = cx + sgn * 38
        ptop = 116
        d.polygon([(px_ - 4, base), (px_ - 1, ptop), (px_ + 1, ptop), (px_ + 4, base)], fill=BRASS[1])
        d.polygon([(px_ - 4, base), (px_ - 1, ptop), (px_, ptop), (px_ - 1, base)], fill=BRASS[2])
        for y in range(ptop + 14, base, 16):
            d.point((px_, y), fill=CRYSTAL[4])
            glows.append((px_, y, 5, GLOW))
        crystal(d, px_ - 3, ptop + 1, 13, 6)
        glows.append((px_, ptop - 6, 12, GLOW))
    fill_poly(im, [(cx - 22, base), (cx - 7, ty), (cx + 7, ty), (cx + 22, base)], st)
    fill_poly(im, [(cx + 3, base), (cx + 1, ty), (cx + 7, ty), (cx + 22, base)], shade(st, 0.66))
    for u in (-1, 1):
        d.line([(cx + u * 22, base), (cx + u * 7, ty)], fill=BRASS[2], width=2)

    def hw(y):
        return 7 + 15 * (y - ty) / (base - ty)

    for y in (ty + 24, ty + 64, base - 20):
        R(d, cx - hw(y) - 1, y, cx + hw(y) + 1, y + 2, BRASS[1])
        d.line([(cx - hw(y) - 1, y), (cx + hw(y) + 1, y)], fill=BRASS[3])
    R(d, cx - 2, ty + 2, cx + 1, base - 22, CRYSTAL[1])
    R(d, cx - 1, ty + 2, cx, base - 22, CRYSTAL[3])
    for y in range(ty + 8, base - 22, 14):
        glows.append((cx, y, 9, GLOW))
    for y in (ty + 40, ty + 84):
        for sgn in (-1, 1):
            x = cx + sgn * int(hw(y) * 0.6)
            R(d, x - 1, y, x, y + 5, CRYSTAL[3])
    glow_arch(d, cx, base, 13, 19, glows)
    # cradle
    R(d, cx - 10, ty - 3, cx + 10, ty + 1, BRASS[1])
    d.line([(cx - 10, ty - 3), (cx + 10, ty - 3)], fill=BRASS[3])
    for sgn in (-1, 1):
        pts = [(cx + sgn * 9, ty - 2), (cx + sgn * 16, ty - 12), (cx + sgn * 15, ty - 22)]
        d.line(pts, fill=BRASS[1], width=3)
        d.line(pts, fill=BRASS[3])
    rng = random.Random(5)
    for y in range(ty - 26, ty - 3, 3):
        d.point((cx + rng.choice((-2, 0, 2)), y), fill=CRYSTAL[4])
    # floating heart
    hy_top, hy_mid, hy_bot, hr = 22, 48, 82, 21
    ring = [cx - 38, hy_mid - 9, cx + 38, hy_mid + 9]
    d.arc(ring, 180, 360, fill=BRASS[1], width=2)
    T_, L_, Rt, B_, M_ = (cx, hy_top), (cx - hr, hy_mid), (cx + hr, hy_mid), (cx, hy_bot), (cx - 5, hy_mid - 3)
    d.polygon([T_, L_, M_], fill=CRYSTAL[3])
    d.polygon([T_, M_, Rt], fill=CRYSTAL[2])
    d.polygon([L_, M_, B_], fill=CRYSTAL[2])
    d.polygon([M_, Rt, B_], fill=CRYSTAL[1])
    d.line([T_, M_, B_], fill=CRYSTAL[4])
    d.line([L_, M_], fill=CRYSTAL[4])
    d.line([M_, Rt], fill=CRYSTAL[3])
    d.polygon([(cx - 9, hy_top + 14), (cx - 4, hy_top + 6), (cx - 6, hy_top + 16)], fill=CRYSTAL[4])
    d.arc(ring, 0, 180, fill=BRASS[3], width=2)
    for a in (20, 75, 130):
        x = cx + 38 * math.cos(math.radians(a))
        y = hy_mid + 9 * math.sin(math.radians(a))
        d.ellipse([x - 2, y - 2, x + 2, y + 2], fill=CRYSTAL[3])
        glows.append((int(x), int(y), 6, GLOW))
    crystal(d, cx - 46, 34, 9, 4)
    crystal(d, cx + 40, 72, 8, 4)
    glows += [(cx, hy_mid, 54, GLOW), (cx, hy_mid, 22, CRYSTAL[4]), (cx - 44, 30, 8, GLOW), (cx + 42, 68, 8, GLOW)]
    return Sprite(im, 3, 3, glows, [], (0.9, 16))


# ------------------------------------------------------------------ City art (ticket 64)
WHITE = pal("9eb0b2", "c6d8d8", "e2f0f0", "f8ffff")
TEAL_GLOW = hexc("7ff0d8")
FORGE = hexc("ff8a3a")


def b_hut(seed=0):
    """Tent II: a small plank hut with a thatch roof, a step up from the tent."""
    return pack(*gable_house(17, 10, 8, 7, "thatch", "planks", 0, seed, lantern=False, door=(6, 9),
                             gable_window=False), shadow=(0.9, 7))


def b_lodge(seed=0):
    """Tent III: a stout stone-footed lodge, shingle roof, shuttered windows, a Lumen lantern at the door."""
    return pack(*gable_house(22, 13, 10, 8, "shingle", "planks", 2, seed, shutters=hexc("a83a3a"),
                             door=(7, 11)), shadow=(0.9, 9))


def b_purifier():
    """City water: a slim white tower with teal bands over a glowing teal filter basin (clean water, not Lumen)."""
    W, H = 32, 86
    im = Image.new("RGBA", (W, H))
    d = ImageDraw.Draw(im)
    cx, yb = W // 2, H - 1
    glows = []
    # basin
    cylinder(d, 1, 30, yb - 14, yb - 3, STONE)
    d.ellipse([1, yb - 20, 30, yb - 7], fill=STONE[3])
    d.ellipse([3, yb - 19, 28, yb - 9], fill=TEAL[1])
    d.ellipse([4, yb - 18, 27, yb - 10], fill=TEAL[3])
    d.ellipse([8, yb - 16, 23, yb - 11], fill=TEAL_GLOW)
    d.arc([7, yb - 17, 24, yb - 10], 190, 330, fill=hexc("eaffff"))
    # tower
    R(d, cx - 8, yb - 24, cx + 8, yb - 17, STONE[2])
    R(d, cx - 8, yb - 24, cx + 8, yb - 24, STONE[4])
    cylinder(d, cx - 6, cx + 5, 20, yb - 24, WHITE)
    for y in (30, 46, 62):
        R(d, cx - 7, y, cx + 6, y + 2, TEAL[2])
        d.line([(cx - 7, y), (cx + 6, y)], fill=TEAL[3])
        R(d, cx + 3, y + 1, cx + 6, y + 2, TEAL[0])
    for y in (35, 51):
        R(d, cx - 2, y, cx + 1, y + 6, TEAL[0])
        R(d, cx - 1, y + 1, cx, y + 5, TEAL_GLOW)
        glows.append((cx, y + 3, 7, TEAL_GLOW))
    d.ellipse([cx - 7, 13, cx + 6, 27], fill=TEAL[2])
    d.chord([cx - 7, 12, cx + 6, 26], 180, 360, fill=TEAL[2])
    R(d, cx - 7, 20, cx + 6, 21, TEAL[1])
    d.arc([cx - 5, 13, cx + 2, 22], 200, 280, fill=TEAL[3])
    R(d, cx, 4, cx, 13, BRASS[1])
    d.ellipse([cx - 2, 1, cx + 2, 5], fill=TEAL_GLOW)
    glows.append((cx, 3, 9, TEAL_GLOW))
    # settling pipes and the clean-water spout into the basin
    pipe(d, [(cx - 6, yb - 22), (cx - 12, yb - 22), (cx - 12, yb - 15)], 2)
    pipe(d, [(cx + 5, yb - 22), (cx + 11, yb - 22), (cx + 11, yb - 15)], 2)
    d.line([(cx, yb - 24), (cx, yb - 13)], fill=TEAL_GLOW)
    glows += [(cx, yb - 13, 16, TEAL_GLOW), (cx, yb - 12, 6, hexc("eaffff"))]
    for x in (2, 27):
        d.ellipse([x, yb - 5, x + 4, yb - 1], fill=LEAF["green"][3])
    return Sprite(im, 1, 1, glows, [], (1.0, 9))


def b_toolsmith(seed=0):
    """City refining: stone forge with a glowing furnace door and chimney, an anvil and a tool rack."""
    house, glows, smoke = gable_house(34, 15, 10, 8, "shingle", "stone", 0, seed, lantern=False, door=(9, 13),
                                      gable_window=False)
    hw_, hh = house.size
    W, H = 66, hh + 4
    im = Image.new("RGBA", (W, H))
    d = ImageDraw.Draw(im)
    hy = H - hh
    im.alpha_composite(house, (0, hy))
    glows = [(x, y + hy, r, c) for x, y, r, c in glows]
    smoke = [(x, y + hy) for x, y in smoke]
    yb = H - 1
    cx = 4 + 17
    # furnace mouth in the door arch: orange fire
    d.rectangle([cx - 3, yb - 12, cx + 3, yb - 1], fill=IRON[0])
    d.rectangle([cx - 2, yb - 10, cx + 2, yb - 1], fill=FORGE)
    d.rectangle([cx - 1, yb - 8, cx + 1, yb - 1], fill=hexc("ffd27a"))
    glows += [(cx, yb - 6, 16, FORGE), (cx, yb - 5, 6, hexc("ffd27a"))]
    # chimney glow
    glows.append((smoke[0][0], smoke[0][1] + 6, 9, FORGE))
    # sign: crossed hammer plate over the door
    R(d, cx - 5, yb - 20, cx + 5, yb - 17, WOOD[1])
    d.line([(cx - 3, yb - 19), (cx + 3, yb - 19)], fill=BRASS[3])
    # anvil on a stump
    ax = 46
    R(d, ax + 2, yb - 8, ax + 9, yb - 1, WOOD[2])
    R(d, ax + 2, yb - 8, ax + 3, yb - 1, WOOD[3])
    R(d, ax, yb - 13, ax + 11, yb - 10, IRON[2])
    R(d, ax, yb - 13, ax + 11, yb - 13, IRON[4])
    d.polygon([(ax + 11, yb - 13), (ax + 15, yb - 12), (ax + 11, yb - 10)], fill=IRON[2])
    R(d, ax + 3, yb - 10, ax + 8, yb - 9, IRON[1])
    d.point((ax + 5, yb - 15), fill=FORGE)
    d.point((ax + 7, yb - 14), fill=hexc("ffd27a"))
    glows.append((ax + 6, yb - 14, 7, FORGE))
    # tool rack: two posts, a bar, hanging tools
    rx = 58
    for px_ in (rx, rx + 7):
        R(d, px_, yb - 30, px_ + 1, yb - 1, WOOD[1])
    R(d, rx - 1, yb - 29, rx + 8, yb - 28, WOOD[3])
    R(d, rx - 1, yb - 19, rx + 8, yb - 18, WOOD[3])
    # hammer, saw, axe
    R(d, rx + 1, yb - 27, rx + 1, yb - 21, WOOD[4])
    R(d, rx - 1, yb - 27, rx + 3, yb - 25, IRON[3])
    d.polygon([(rx + 3, yb - 27), (rx + 6, yb - 27), (rx + 6, yb - 20), (rx + 3, yb - 22)], fill=IRON[3])
    d.line([(rx + 3, yb - 27), (rx + 3, yb - 22)], fill=IRON[4])
    R(d, rx + 4, yb - 17, rx + 4, yb - 9, WOOD[4])
    d.polygon([(rx + 1, yb - 17), (rx + 4, yb - 17), (rx + 4, yb - 12), (rx + 1, yb - 14)], fill=IRON[3])
    return Sprite(im, 2, 1, glows, smoke, (1.0, 10))


def b_bazaar(seed=0):
    """City civic: a long plaster hall under a slate roof, fronted by four striped market stalls."""
    rng = random.Random(seed)
    W, H = 100, 82
    im = Image.new("RGBA", (W, H))
    d = ImageDraw.Draw(im)
    x0, x1, yb = 3, W - 4, H - 1
    glows, smoke = [], []
    # hall: roof, wall, windows
    rt = tex_shingle(W, H, SLATE)
    ry0, ry1 = 12, 30
    fill_poly(im, [(x0 - 2, ry1), (x0 + 8, ry0), (x1 - 8, ry0), (x1 + 2, ry1)], rt)
    fill_poly(im, [(x1 - 22, ry0), (x1 - 8, ry0), (x1 + 2, ry1), (x1 - 12, ry1)], shade(rt, 0.75))
    d.line([(x0 + 8, ry0), (x1 - 8, ry0)], fill=SLATE[4])
    R(d, x0 - 2, ry1, x1 + 2, ry1 + 1, STONE[4])
    R(d, x0 - 2, ry1 + 2, x1 + 2, ry1 + 2, STONE[1])
    wy0 = ry1 + 3
    im.paste(tex_plaster(x1 - x0 + 1, yb - wy0 - 6, seed), (x0, wy0))
    for i in range(7):
        wx = x0 + 6 + i * 13
        window(d, wx, wy0 + 4, WARM if rng.random() < 0.75 else hexc("34445a"), box=False, w=7, h=9)
        R(d, wx - 1, wy0 + 3, wx + 7, wy0 + 3, PLASTER[0])
    for tx in (x0, x1 - 3):
        R(d, tx, wy0, tx + 2, yb - 6, WOOD[2])
    R(d, x0, wy0 + 17, x1, wy0 + 17, WOOD[2])
    # chimney and lumen lamp vane, pennants at the gable ends
    for chx, sd_ in ((x0 + 14, 1), (x1 - 20, 2)):
        im.paste(tex_stone(6, 12, seed + chx), (chx, ry0 - 9))
        R(d, chx - 1, ry0 - 10, chx + 6, ry0 - 9, STONE[1])
        smoke.append((chx + 3, ry0 - 13))
    for fx_, col in ((x0 + 36, hexc("c83a3a")), (x1 - 36, TEAL[2])):
        R(d, fx_, ry0 - 12, fx_, ry0 + 1, WOOD[1])
        d.polygon([(fx_, ry0 - 12), (fx_ + 8, ry0 - 9), (fx_, ry0 - 6)], fill=col)
    # grand brass sign above the arch
    cx = W // 2
    R(d, cx - 11, wy0 + 1, cx + 11, wy0 + 8, WOOD[0])
    R(d, cx - 10, wy0 + 2, cx + 10, wy0 + 7, BRASS[1])
    for k in range(-8, 9, 4):
        R(d, cx + k, wy0 + 4, cx + k + 1, wy0 + 5, BRASS[3])
    # stone footing
    im.paste(tex_stone(x1 - x0 + 1, 7, seed + 7), (x0, yb - 6))
    R(d, x0, yb - 7, x1, yb - 7, STONE[4])
    # stalls in front of the hall
    cols = [hexc("b83a32"), TEAL[2], hexc("e0a22e"), hexc("3a5a9a")]
    goods = [[hexc("d84a3a"), hexc("f4c040"), LEAF["green"][3]], [CRYSTAL[3], hexc("e88a3a"), hexc("f4f0e0")],
             [hexc("e88a3a"), hexc("d84a3a"), hexc("f4c040")], [LEAF["green"][3], hexc("c070d0"), hexc("f4c040")]]
    sw = 23
    for i in range(4):
        sx = x0 + 2 + i * (sw + 1)
        ay = wy0 + 22
        d.rectangle([sx + 1, ay + 4, sx + sw - 2, ay + 5], fill=WOOD[1])
        for px_ in (sx + 1, sx + sw - 3):
            R(d, px_, ay + 4, px_ + 1, yb - 2, WOOD[1])
        # counter with goods
        R(d, sx + 1, yb - 12, sx + sw - 2, yb - 8, WOOD[3])
        R(d, sx + 1, yb - 12, sx + sw - 2, yb - 12, WOOD[4])
        R(d, sx + 1, yb - 7, sx + sw - 2, yb - 2, WOOD[2])
        for k, c in enumerate(goods[i] * 2):
            ex = sx + 3 + k * 3
            d.ellipse([ex, yb - 16, ex + 3, yb - 12], fill=c)
            d.point((ex + 1, yb - 15), fill=mul(c, 1.3))
        # striped awning with scalloped valance
        for s in range(0, sw, 4):
            c = cols[i] if (s // 4) % 2 == 0 else CANVAS[3]
            d.polygon([(sx - 1 + s, ay + 5), (sx + 2 + s, ay - 3), (sx + 6 + s, ay - 3), (sx + 3 + s, ay + 5)], fill=c)
            d.polygon([(sx - 1 + s, ay + 5), (sx + 3 + s, ay + 5), (sx + 3 + s, ay + 8), (sx - 1 + s, ay + 8)],
                      fill=mul(c, 0.85))
            d.ellipse([sx - 1 + s, ay + 6, sx + 3 + s, ay + 10], fill=mul(c, 0.85))
        glows.append((sx + sw // 2, yb - 12, 11, WARM))
    # barrels and crates at the corners
    R(d, W - 6, yb - 10, W - 1, yb - 1, WOOD[2])
    R(d, W - 6, yb - 7, W - 1, yb - 7, BRASS[1])
    d.ellipse([W - 6, yb - 12, W - 1, yb - 8], fill=WOOD[3])
    R(d, 0, yb - 7, 5, yb - 1, WOOD[3])
    d.line([(0, yb - 7), (5, yb - 1)], fill=WOOD[1])
    return Sprite(im, 3, 2, glows, smoke, (1.0, 12))


def b_nexus():
    """City landmark: a crystal node floating over a brass cradle on a gold-and-stone plinth, flanked by pylons."""
    W, H = 96, 150
    im = Image.new("RGBA", (W, H))
    d = ImageDraw.Draw(im)
    cx, yb = W // 2, H - 1
    glows = []
    st = tex_stone(W, H, 91)
    im.paste(tex_stone(W - 6, 11, 92), (3, yb - 10))
    R(d, 3, yb - 11, W - 4, yb - 11, STONE[4])
    R(d, 3, yb - 4, W - 4, yb - 3, BRASS[1])
    im.paste(tex_stone(W - 24, 10, 93), (12, yb - 20))
    R(d, 12, yb - 21, W - 13, yb - 21, STONE[4])
    for ax in (10, W - 11):
        glow_arch(d, ax, yb - 1, 5, 7, glows)
    for ax in (22, W - 23):
        glow_arch(d, ax, yb - 11, 5, 7, glows)
    base, ty = yb - 21, 84
    # side pylons
    for sgn in (-1, 1):
        px_ = cx + sgn * 32
        ptop = 96
        d.polygon([(px_ - 4, base), (px_ - 2, ptop), (px_ + 2, ptop), (px_ + 4, base)], fill=BRASS[1])
        d.polygon([(px_ - 4, base), (px_ - 2, ptop), (px_, ptop), (px_ - 1, base)], fill=BRASS[2])
        for y in range(ptop + 12, base, 14):
            d.point((px_, y), fill=CRYSTAL[4])
        R(d, px_ - 4, ptop - 2, px_ + 4, ptop, BRASS[2])
        crystal(d, px_ - 3, ptop - 2, 14, 6)
        glows.append((px_, ptop - 9, 11, GLOW))
    # plinth
    fill_poly(im, [(cx - 20, base), (cx - 9, ty), (cx + 9, ty), (cx + 20, base)], st)
    fill_poly(im, [(cx + 3, base), (cx + 1, ty), (cx + 9, ty), (cx + 20, base)], shade(st, 0.66))
    for u in (-1, 1):
        d.line([(cx + u * 20, base), (cx + u * 9, ty)], fill=BRASS[2], width=2)

    def hw(y):
        return 9 + 11 * (y - ty) / (base - ty)

    for y in (ty + 14, base - 16):
        R(d, cx - hw(y) - 1, y, cx + hw(y) + 1, y + 2, BRASS[1])
        d.line([(cx - hw(y) - 1, y), (cx + hw(y) + 1, y)], fill=BRASS[3])
    R(d, cx - 1, ty + 3, cx, base - 18, CRYSTAL[3])
    for y in range(ty + 8, base - 18, 12):
        glows.append((cx, y, 7, GLOW))
    glow_arch(d, cx, base, 11, 15, glows)
    # cradle
    R(d, cx - 11, ty - 3, cx + 11, ty + 1, BRASS[1])
    d.line([(cx - 11, ty - 3), (cx + 11, ty - 3)], fill=BRASS[3])
    for sgn in (-1, 1):
        pts = [(cx + sgn * 10, ty - 2), (cx + sgn * 15, ty - 11), (cx + sgn * 13, ty - 19)]
        d.line(pts, fill=BRASS[1], width=3)
        d.line(pts, fill=BRASS[3])
    rng = random.Random(7)
    for y in range(ty - 22, ty - 3, 3):
        d.point((cx + rng.choice((-2, 0, 2)), y), fill=CRYSTAL[4])
    # floating node, a smaller sibling of the Skyheart
    hy_top, hy_mid, hy_bot, hr = 22, 42, 66, 15
    T_, L_, Rt, B_, M_ = (cx, hy_top), (cx - hr, hy_mid), (cx + hr, hy_mid), (cx, hy_bot), (cx - 4, hy_mid - 3)
    ring = [cx - 25, hy_mid - 6, cx + 25, hy_mid + 6]
    d.arc(ring, 180, 360, fill=BRASS[1], width=2)
    d.polygon([T_, L_, M_], fill=CRYSTAL[3])
    d.polygon([T_, M_, Rt], fill=CRYSTAL[2])
    d.polygon([L_, M_, B_], fill=CRYSTAL[2])
    d.polygon([M_, Rt, B_], fill=CRYSTAL[1])
    d.line([T_, M_, B_], fill=CRYSTAL[4])
    d.line([L_, M_], fill=CRYSTAL[4])
    d.line([M_, Rt], fill=CRYSTAL[3])
    d.polygon([(cx - 7, hy_top + 11), (cx - 3, hy_top + 5), (cx - 4, hy_top + 13)], fill=CRYSTAL[4])
    d.arc(ring, 0, 180, fill=BRASS[3], width=2)
    for a in (30, 100, 150):
        x = cx + 25 * math.cos(math.radians(a))
        y = hy_mid + 6 * math.sin(math.radians(a))
        d.ellipse([x - 2, y - 2, x + 2, y + 2], fill=CRYSTAL[3])
        glows.append((int(x), int(y), 5, GLOW))
    glows += [(cx, hy_mid, 40, GLOW), (cx, hy_mid, 16, CRYSTAL[4])]
    return Sprite(im, 3, 3, glows, [], (0.9, 14))


def b_pylon():
    """Lumen Pylon (1x1): a squat stone plinth, a stout brass mast with glowing coil bands and a big crystal on top."""
    W, H = 32, 64
    im = Image.new("RGBA", (W, H))
    d = ImageDraw.Draw(im)
    cx, yb = W // 2, H - 1
    glows = []
    # stone plinth with a brass rim
    im.paste(tex_stone(28, 11, 94), (cx - 14, yb - 10))
    R(d, cx - 14, yb - 11, cx + 13, yb - 11, STONE[4])
    R(d, cx - 14, yb - 3, cx + 13, yb - 2, STONE[1])
    R(d, cx - 14, yb - 6, cx + 13, yb - 6, BRASS[1])
    # stout mast
    top = 26
    base = yb - 11
    d.polygon([(cx - 7, base), (cx - 4, top), (cx + 4, top), (cx + 7, base)], fill=BRASS[1])
    d.polygon([(cx - 7, base), (cx - 4, top), (cx - 1, top), (cx - 2, base)], fill=BRASS[2])
    d.polygon([(cx + 3, base), (cx + 4, top), (cx + 7, base)], fill=BRASS[0])
    d.line([(cx - 7, base), (cx - 4, top)], fill=BRASS[3])
    # glowing coil bands
    for y in (top + 8, top + 17, top + 26):
        R(d, cx - 7, y, cx + 7, y + 2, BRASS[3])
        R(d, cx - 5, y + 1, cx + 5, y + 1, CRYSTAL[3])
        glows.append((cx, y + 1, 8, GLOW))
    # cradle and crystal, a sibling of the Nexus node
    R(d, cx - 7, top - 3, cx + 7, top, BRASS[2])
    R(d, cx - 7, top - 3, cx + 7, top - 3, BRASS[3])
    crystal(d, cx - 6, top - 3, 22, 12)
    d.arc([cx - 11, top - 20, cx + 11, top - 10], 200, 340, fill=BRASS[3], width=1)
    glows += [(cx, top - 14, 20, GLOW), (cx, top - 14, 7, CRYSTAL[4])]
    return Sprite(im, 1, 1, glows, [], (0.9, 8))


def b_battery():
    """Grid Battery (2x1): a squat iron housing with a glass tank window showing three glowing Lumen cells."""
    W, H = 64, 46
    im = Image.new("RGBA", (W, H))
    d = ImageDraw.Draw(im)
    yb = H - 1
    glows = []
    im.paste(tex_stone(W - 4, 8, 95), (2, yb - 7))
    R(d, 2, yb - 8, W - 3, yb - 8, STONE[4])
    # housing
    R(d, 3, yb - 32, W - 4, yb - 9, IRON[1])
    R(d, 3, yb - 32, W - 4, yb - 31, IRON[4])
    R(d, W - 10, yb - 30, W - 4, yb - 9, IRON[0])
    R(d, 3, yb - 9, W - 4, yb - 9, IRON[0])
    # glass tank window, brass-framed
    R(d, 6, yb - 28, W - 7, yb - 12, BRASS[1])
    R(d, 6, yb - 28, W - 7, yb - 28, BRASS[3])
    R(d, 8, yb - 26, W - 9, yb - 14, CRYSTAL[0])
    for k in range(3):
        x0 = 9 + k * 16
        R(d, x0, yb - 25, x0 + 11, yb - 15, CRYSTAL[2])
        R(d, x0, yb - 21, x0 + 11, yb - 15, CRYSTAL[3])
        R(d, x0 + 1, yb - 25, x0 + 3, yb - 15, CRYSTAL[4])
        R(d, x0, yb - 25, x0 + 11, yb - 25, CRYSTAL[1])
        # terminal cap on the roof
        R(d, x0 + 3, yb - 36, x0 + 8, yb - 32, BRASS[2])
        R(d, x0 + 4, yb - 38, x0 + 7, yb - 37, CRYSTAL[3])
        glows.append((x0 + 6, yb - 20, 12, GLOW))
        if k:
            R(d, x0 - 4, yb - 28, x0 - 3, yb - 14, BRASS[2])
    return Sprite(im, 2, 1, glows, [], (0.95, 8))


def b_rail_depot():
    """Rail Depot (3x1): a small shingled station house on the left, a long stone platform with a brass edge strip and,
    on the right, a canopy on timber posts with a lamp and a bench."""
    W, H = 96, 62
    im = Image.new("RGBA", (W, H))
    d = ImageDraw.Draw(im)
    yb = H - 1
    glows = []
    # platform slab
    im.paste(tex_stone(W - 4, 8, 131), (2, yb - 7))
    R(d, 2, yb - 8, W - 3, yb - 8, STONE[4])
    R(d, 2, yb - 9, W - 3, yb - 9, BRASS[2])
    # station house
    house, hg, hs = gable_house(34, 13, 11, 8, "shingle", "planks", 2, 71, chimney=True, lantern=False,
                                shutters=hexc("a83a3a"), door=(9, 12), gable_window=True)
    im.alpha_composite(house, (0, yb - 9 - house.height + 3))
    glows += [(x, y + yb - 9 - house.height + 3, r, c) for x, y, r, c in hg]
    # canopy: two posts, a sloped shingle roof with a lit board under it
    cx0, cx1 = 46, 92
    for px in (cx0 + 3, cx1 - 5):
        R(d, px, yb - 33, px + 2, yb - 10, WOOD[1])
        R(d, px, yb - 33, px, yb - 10, WOOD[3])
    d.polygon([(cx0, yb - 31), (cx1, yb - 31), (cx1 - 3, yb - 42), (cx0 + 3, yb - 42)], fill=SHINGLE[2])
    for k in range(4):
        R(d, cx0 + 3 - k, yb - 42 + 3 * k + 1, cx1 - 3 + k, yb - 42 + 3 * k + 1, SHINGLE[3 if k % 2 == 0 else 1])
    R(d, cx0, yb - 31, cx1, yb - 30, SHINGLE[0])
    R(d, cx0 + 6, yb - 29, cx1 - 8, yb - 24, WOOD[0])
    R(d, cx0 + 8, yb - 28, cx1 - 10, yb - 26, BRASS[2])  # station sign board
    R(d, cx0 + 8, yb - 28, cx1 - 10, yb - 28, BRASS[3])
    glows.append((cx0 + 22, yb - 20, 10, WARM))
    R(d, cx0 + 21, yb - 24, cx0 + 23, yb - 22, WARM)  # hanging lamp
    # bench
    R(d, cx0 + 10, yb - 15, cx0 + 24, yb - 14, WOOD[3])
    R(d, cx0 + 10, yb - 13, cx0 + 11, yb - 10, WOOD[1])
    R(d, cx0 + 23, yb - 13, cx0 + 24, yb - 10, WOOD[1])
    # luggage crates
    R(d, cx1 - 17, yb - 16, cx1 - 11, yb - 10, WOOD[2])
    R(d, cx1 - 17, yb - 16, cx1 - 11, yb - 15, WOOD[4])
    R(d, cx1 - 14, yb - 21, cx1 - 10, yb - 17, WOOD[3])
    return Sprite(im, 3, 1, glows, [], (1.0, 9))


def b_conduit_terraces():
    """Conduit Terraces (3x2, ticket 39): three stepped stone terraces climbing to the back, a brass-edged water channel
    running along each step and spilling down the front, and a little plaster home with a shingle roof on every step."""
    W, H = 96, 66
    im = Image.new("RGBA", (W, H))
    d = ImageDraw.Draw(im)
    yb = H - 1
    glows = []
    rng = random.Random(391)
    for k in range(3):
        x0, x1 = 2 + k * 8, W - 3 - k * 8
        ytop = yb - 14 - k * 17
        im.paste(tex_stone(x1 - x0 + 1, 15, 150 + k), (x0, ytop))
        R(d, x0, ytop, x1, ytop, STONE[4])
        R(d, x0, ytop + 1, x1, ytop + 2, BRASS[1])  # water channel lip
        R(d, x0, ytop + 1, x1, ytop + 1, TEAL[2])
        R(d, x0 + 1, ytop + 2, x1 - 1, ytop + 2, TEAL[1])
        # homes on the step
        for hx in range(x0 + 4, x1 - 14, 22):
            R(d, hx, ytop - 11, hx + 13, ytop - 1, PLASTER[2])
            R(d, hx + 10, ytop - 11, hx + 13, ytop - 1, PLASTER[0])
            d.polygon([(hx - 2, ytop - 10), (hx + 6, ytop - 17), (hx + 15, ytop - 10)], fill=SHINGLE[2])
            d.line([(hx - 2, ytop - 10), (hx + 6, ytop - 17), (hx + 15, ytop - 10)], fill=SHINGLE[0])
            window(d, hx + 2, ytop - 8, WARM if rng.random() < 0.7 else hexc("34445a"), box=False, w=4, h=5)
            R(d, hx + 7, ytop - 6, hx + 9, ytop - 1, WOOD[1])
        # green planter edge
        for px_ in range(x0 + 2, x1 - 1, 5):
            d.point((px_, ytop - 1), fill=LEAF["green"][3])
    # waterfall down the front of the lowest step
    for fx in (30, 62):
        R(d, fx, yb - 12, fx + 2, yb, TEAL[3])
        R(d, fx, yb - 12, fx, yb, TEAL[2])
    R(d, 2, yb - 1, W - 3, yb, STONE[1])
    glows.append((48, yb - 30, 10, WARM))
    return Sprite(im, 3, 2, glows, [], (1.0, 8))


def b_water_tower():
    """Water Tower (1x1, ticket 39): a tall timber tank on four braced legs, brass hoops and a conical shingle cap, with a
    brass pipe running to the ground and a drip basin."""
    W, H = 32, 72
    im = Image.new("RGBA", (W, H))
    d = ImageDraw.Draw(im)
    cx, yb = W // 2, H - 1
    # stone footing and basin
    im.paste(tex_stone(26, 6, 160), (cx - 13, yb - 5))
    R(d, cx - 13, yb - 6, cx + 12, yb - 6, STONE[4])
    R(d, cx - 8, yb - 8, cx + 8, yb - 6, TEAL[1])
    # braced legs
    for lx0, lx1 in ((cx - 11, cx - 8), (cx + 11, cx + 8)):
        d.line([(lx0, yb - 6), (lx1, yb - 34)], fill=WOOD[1], width=3)
        d.line([(lx0 - 1, yb - 6), (lx1 - 1, yb - 34)], fill=WOOD[3], width=1)
    for lx in (cx - 3, cx + 3):
        d.line([(lx, yb - 6), (lx, yb - 34)], fill=WOOD[2], width=2)
    d.line([(cx - 10, yb - 10), (cx + 9, yb - 28)], fill=WOOD[1])
    d.line([(cx + 10, yb - 10), (cx - 9, yb - 28)], fill=WOOD[1])
    R(d, cx - 10, yb - 20, cx + 10, yb - 19, WOOD[0])
    # tank
    tk = tex_planks(22, 24, 161, WOOD, vertical=True)
    im.paste(tk, (cx - 11, yb - 58))
    R(d, cx - 12, yb - 59, cx + 11, yb - 58, WOOD[4])
    for y in (yb - 54, yb - 44, yb - 36):
        R(d, cx - 12, y, cx + 11, y + 1, BRASS[2])
        R(d, cx - 12, y, cx + 11, y, BRASS[3])
    R(d, cx + 6, yb - 58, cx + 10, yb - 35, WOOD[1])  # shaded side
    for y in (yb - 54, yb - 44, yb - 36):
        R(d, cx + 6, y, cx + 11, y + 1, BRASS[1])
    # conical cap
    d.polygon([(cx - 14, yb - 59), (cx, yb - 71), (cx + 14, yb - 59)], fill=SHINGLE[2])
    d.polygon([(cx, yb - 71), (cx + 14, yb - 59), (cx + 4, yb - 59)], fill=SHINGLE[1])
    d.line([(cx - 14, yb - 59), (cx, yb - 71), (cx + 14, yb - 59)], fill=SHINGLE[0])
    R(d, cx - 14, yb - 59, cx + 14, yb - 59, BRASS[3])
    # brass pipe down to the basin and a ladder
    R(d, cx - 1, yb - 36, cx + 1, yb - 9, BRASS[2])
    R(d, cx - 1, yb - 36, cx - 1, yb - 9, BRASS[3])
    R(d, cx - 3, yb - 10, cx + 3, yb - 9, BRASS[1])
    for y in range(yb - 56, yb - 8, 4):
        R(d, cx - 8, y, cx - 6, y, WOOD[0])
    return Sprite(im, 1, 1, [], [], (0.8, 7))


def b_vein_bore():
    """Vein Bore (2x2, ticket 39b): a heavy iron drill rig on a stone collar over a glowing vein shaft. A tall braced
    derrick carries the drill string and a brass winch drum; Lumen crystal light climbs out of the shaft."""
    W, H = 68, 96
    im = Image.new("RGBA", (W, H))
    d = ImageDraw.Draw(im)
    cx, yb = W // 2, H - 1
    glows = []
    im.paste(tex_stone(W - 4, 12, 391), (2, yb - 11))
    R(d, 2, yb - 12, W - 3, yb - 12, STONE[4])
    # shaft mouth, glowing
    d.ellipse([cx - 14, yb - 22, cx + 14, yb - 8], fill=IRON[0])
    d.ellipse([cx - 11, yb - 20, cx + 11, yb - 10], fill=CRYSTAL[1])
    d.ellipse([cx - 7, yb - 18, cx + 7, yb - 12], fill=CRYSTAL[3])
    d.ellipse([cx - 3, yb - 16, cx + 3, yb - 14], fill=CRYSTAL[4])
    glows += [(cx, yb - 15, 22, GLOW), (cx, yb - 15, 9, CRYSTAL[4])]
    # derrick: four braced legs
    top = 12
    for lx0, lx1 in ((cx - 24, cx - 6), (cx + 24, cx + 6)):
        d.line([(lx0, yb - 12), (lx1, top + 4)], fill=IRON[2], width=3)
        d.line([(lx0 - 1, yb - 12), (lx1 - 1, top + 4)], fill=IRON[3])
    for y in range(top + 12, yb - 14, 14):
        k = (y - top) / (yb - 12 - top)
        xl, xr = cx - 6 - int(18 * k), cx + 6 + int(18 * k)
        d.line([(xl, y), (xr, y)], fill=IRON[1], width=2)
        d.line([(xl, y), (xr - 5, y + 14)], fill=IRON[3])
        d.line([(xr, y), (xl + 5, y + 14)], fill=IRON[3])
    # crown block and drill string
    R(d, cx - 9, top, cx + 9, top + 5, BRASS[1])
    R(d, cx - 9, top, cx + 9, top, BRASS[3])
    d.ellipse([cx - 3, top - 5, cx + 3, top + 1], fill=BRASS[2])
    R(d, cx - 2, top + 5, cx + 2, yb - 16, IRON[2])
    R(d, cx - 2, top + 5, cx - 2, yb - 16, IRON[4])
    for y in range(top + 12, yb - 18, 9):
        R(d, cx - 3, y, cx + 3, y + 2, BRASS[2])
    d.polygon([(cx - 4, yb - 22), (cx + 4, yb - 22), (cx, yb - 14)], fill=IRON[4])
    # winch drum with a Lumen lamp, and a motor housing
    R(d, 3, yb - 34, 19, yb - 13, IRON[1])
    cylinder(d, 5, 17, yb - 32, yb - 15, BRASS)
    R(d, 3, yb - 34, 19, yb - 34, IRON[4])
    d.line([(11, yb - 32), (cx - 2, top + 8)], fill=IRON[3])
    R(d, W - 20, yb - 28, W - 4, yb - 13, IRON[2])
    R(d, W - 20, yb - 28, W - 4, yb - 28, IRON[4])
    for x in range(W - 18, W - 5, 4):
        R(d, x, yb - 24, x, yb - 16, IRON[0])
    R(d, W - 17, yb - 32, W - 14, yb - 28, IRON[3])
    glows.append((W - 12, yb - 20, 6, CRYSTAL[3]))
    d.point((W - 12, yb - 20), fill=CRYSTAL[4])
    return Sprite(im, 2, 2, glows, [], (1.0, 10))


def b_hydroponic_hall():
    """Hydroponic Hall (3x2, ticket 39c): a long glass hall on a stone footing, tiers of green racks inside under teal
    grow-lamps, and brass water pipes with a tank running along the front."""
    W, H = 96, 68
    im = Image.new("RGBA", (W, H))
    d = ImageDraw.Draw(im)
    x0, x1, yb = 3, W - 4, H - 1
    ry, wy = 12, yb - 20
    glows = []
    rng = random.Random(392)
    inner = Image.new("RGBA", (W, H), hexc("163a34"))
    idr = ImageDraw.Draw(inner)
    for k, y in enumerate((ry + 6, ry + 18, ry + 30)):
        R(idr, x0, y + 5, x1, y + 6, IRON[2])
        for x in range(x0 + 1, x1, 3):
            h_ = rng.randint(3, 5)
            R(idr, x, y + 4 - h_, x + 1, y + 4, rng.choice(LEAF["green"][1:5]))
        R(idr, x0, y - 5, x1, y - 5, TEAL[3])
        glows.append((rng.randint(x0 + 12, x1 - 12), y - 4, 8, GLOW))
    glint = Image.new("RGBA", (W, H))
    gd = ImageDraw.Draw(glint)
    for k in range(-H, W, 16):
        gd.line([(k, H), (k + H, 0)], fill=(255, 255, 255, 60), width=2)
    roof, wall = inner.copy(), inner.copy()
    roof.alpha_composite(Image.new("RGBA", (W, H), CRYSTAL[3][:3] + (110,)))
    roof.alpha_composite(glint)
    wall.alpha_composite(Image.new("RGBA", (W, H), CRYSTAL[2][:3] + (55,)))
    wall.alpha_composite(glint)
    paste_box(im, shade(roof, 0.62), x0 + 2, ry - 4, x1 - 2, ry - 1)
    paste_box(im, roof, x0 - 1, ry, x1 + 1, wy)
    paste_box(im, wall, x0, wy + 1, x1, yb - 6)
    im.paste(tex_stone(x1 - x0 + 1, 6, 392), (x0, yb - 5))
    R(d, x0, yb - 6, x1, yb - 6, STONE[4])
    for x in range(x0, x1 + 1, 8):
        d.line([(x, ry), (x, wy)], fill=IRON[2])
        d.line([(x, wy + 1), (x, yb - 6)], fill=IRON[1])
    d.line([(x0 - 1, ry), (x1 + 1, ry)], fill=IRON[3])
    d.line([(x0 - 1, wy), (x1 + 1, wy)], fill=IRON[3])
    d.line([(x0 + 2, ry - 4), (x1 - 2, ry - 4)], fill=IRON[3])
    # water pipes along the front with a tank on the left and a valve
    R(d, x0, yb - 11, x1, yb - 9, BRASS[1])
    R(d, x0, yb - 11, x1, yb - 11, BRASS[3])
    for x in range(x0 + 10, x1, 18):
        R(d, x, yb - 12, x + 2, yb - 8, BRASS[3])
        R(d, x, yb - 8, x + 1, yb - 5, TEAL[3])
    cylinder(d, x1 - 12, x1 - 2, yb - 30, yb - 6, TEAL)
    R(d, x1 - 13, yb - 31, x1 - 1, yb - 29, BRASS[2])
    R(d, x1 - 13, yb - 10, x1 - 1, yb - 8, BRASS[2])
    # glass door
    cx = (x0 + x1) // 2
    R(d, cx - 5, yb - 19, cx + 5, yb - 6, BRASS[1])
    R(d, cx - 4, yb - 18, cx + 4, yb - 6, mul(CRYSTAL[2], 0.8))
    d.line([(cx, yb - 18), (cx, yb - 6)], fill=BRASS[1])
    return Sprite(im, 3, 2, glows, [], (1.0, 9))


def b_airship_dock():
    """Airship Dock (3x3, ticket 38): a timber-and-stone landing platform with a tall brass-capped mooring mast and a small
    airship (canvas envelope, wooden gondola) tied to it, a lamp on the mast and a crate stack on the deck."""
    W, H = 96, 130
    im = Image.new("RGBA", (W, H))
    d = ImageDraw.Draw(im)
    yb = H - 1
    glows = []
    # stone platform with a timber deck on top
    im.paste(tex_stone(W - 6, 14, 141), (3, yb - 13))
    R(d, 3, yb - 14, W - 4, yb - 14, STONE[4])
    R(d, 3, yb - 4, W - 4, yb - 3, BRASS[1])
    im.paste(tex_planks(W - 12, 8, 142, WOOD, vertical=False), (6, yb - 22))
    R(d, 6, yb - 23, W - 7, yb - 23, WOOD[4])
    for x in (10, 30, 50, 70, 84):
        R(d, x, yb - 21, x + 1, yb - 16, WOOD[1])  # deck posts
    # mooring mast
    mx = 70
    R(d, mx - 3, yb - 90, mx + 3, yb - 23, WOOD[2])
    R(d, mx - 3, yb - 90, mx - 2, yb - 23, WOOD[3])
    R(d, mx + 2, yb - 90, mx + 3, yb - 23, WOOD[1])
    for y in range(yb - 80, yb - 30, 12):
        R(d, mx - 4, y, mx + 4, y + 1, BRASS[1])
        R(d, mx - 4, y, mx + 4, y, BRASS[3])
    R(d, mx - 5, yb - 94, mx + 5, yb - 90, BRASS[2])
    R(d, mx - 5, yb - 94, mx + 5, yb - 94, BRASS[3])
    R(d, mx - 1, yb - 102, mx + 1, yb - 94, BRASS[1])
    R(d, mx - 2, yb - 106, mx + 2, yb - 102, WARM)  # beacon lamp
    glows.append((mx, yb - 104, 13, WARM))
    # airship moored to the mast: envelope, fins, gondola
    ex, ey = 34, yb - 62
    env = tex_planks(52, 26, 143, CANVAS, vertical=False)
    m = Image.new("L", (W, H))
    ImageDraw.Draw(m).ellipse([ex - 26, ey - 13, ex + 26, ey + 13], fill=255)
    layer = Image.new("RGBA", (W, H))
    layer.paste(env, (ex - 26, ey - 13))
    im.paste(layer, (0, 0), m)
    d.arc([ex - 26, ey - 13, ex + 26, ey + 13], 20, 160, fill=CANVAS[0])
    for k in (-14, -4, 6, 16):
        d.line([(ex + k, ey - 12), (ex + k - 2, ey + 12)], fill=CANVAS[1])
    R(d, ex - 24, ey - 1, ex + 24, ey, TEAL[1])  # painted stripe
    d.polygon([(ex - 24, ey - 3), (ex - 34, ey - 12), (ex - 33, ey + 8), (ex - 24, ey + 4)], fill=TEAL[2])  # tail fin
    d.polygon([(ex + 22, ey + 8), (ex + 30, ey + 16), (ex + 20, ey + 14)], fill=TEAL[1])
    R(d, ex - 9, ey + 17, ex + 9, ey + 25, WOOD[2])  # gondola
    R(d, ex - 9, ey + 17, ex + 9, ey + 17, WOOD[4])
    R(d, ex - 7, ey + 19, ex - 4, ey + 21, WARM)
    R(d, ex + 4, ey + 19, ex + 7, ey + 21, WARM)
    glows.append((ex, ey + 20, 9, WARM))
    for k in (-8, 8):
        d.line([(ex + k, ey + 12), (ex + k // 2, ey + 17)], fill=WOOD[1])
    # mooring line to the mast and a gangway down to the deck
    d.line([(ex + 26, ey), (mx - 3, yb - 86)], fill=WOOD[1], width=1)
    d.line([(ex + 9, ey + 25), (ex + 20, yb - 23)], fill=WOOD[3], width=2)
    # crate stack and a bollard
    R(d, 12, yb - 32, 22, yb - 23, WOOD[2])
    R(d, 12, yb - 32, 22, yb - 31, WOOD[4])
    R(d, 15, yb - 39, 21, yb - 33, WOOD[3])
    R(d, 46, yb - 29, 49, yb - 23, BRASS[2])
    return Sprite(im, 3, 3, glows, [], (1.0, 10))


AIRSHIP_CELL = (48, 32)


def airship_sprite():
    """Flying airship for the air freight view (ticket 68), 48x32, facing east: canvas envelope with a teal stripe and
    tail fins, a wooden gondola slung below, a propeller blur at the stern. Mirrored in code for west."""
    W, H = AIRSHIP_CELL
    im = Image.new("RGBA", (W, H))
    d = ImageDraw.Draw(im)
    ex, ey = 26, 11
    env = tex_planks(40, 20, 143, CANVAS, vertical=False)
    m = Image.new("L", (W, H))
    ImageDraw.Draw(m).ellipse([ex - 20, ey - 10, ex + 20, ey + 10], fill=255)
    layer = Image.new("RGBA", (W, H))
    layer.paste(env, (ex - 20, ey - 10))
    im.paste(layer, (0, 0), m)
    d.arc([ex - 20, ey - 10, ex + 20, ey + 10], 200, 340, fill=CANVAS[3])
    d.arc([ex - 20, ey - 10, ex + 20, ey + 10], 20, 160, fill=CANVAS[0])
    for k in (-10, -2, 6, 14):
        d.line([(ex + k, ey - 9), (ex + k - 1, ey + 9)], fill=CANVAS[1])
    R(d, ex - 18, ey, ex + 18, ey + 1, TEAL[1])
    d.polygon([(ex - 17, ey - 3), (ex - 25, ey - 10), (ex - 24, ey + 6), (ex - 17, ey + 3)], fill=TEAL[2])
    d.polygon([(ex - 17, ey + 3), (ex - 24, ey + 6), (ex - 22, ey + 12), (ex - 15, ey + 7)], fill=TEAL[0])
    R(d, ex + 17, ey - 1, ex + 18, ey + 1, TEAL[3])  # nose cap
    for k in (-6, 6):  # gondola struts
        d.line([(ex + k, ey + 9), (ex + k // 2, ey + 13)], fill=WOOD[1])
    R(d, ex - 7, ey + 13, ex + 7, ey + 19, WOOD[2])
    R(d, ex - 7, ey + 13, ex + 7, ey + 13, WOOD[4])
    R(d, ex - 7, ey + 19, ex + 7, ey + 19, WOOD[0])
    R(d, ex - 5, ey + 15, ex - 3, ey + 16, WARM)
    R(d, ex + 1, ey + 15, ex + 3, ey + 16, WARM)
    R(d, ex - 10, ey + 15, ex - 8, ey + 17, IRON[1])  # engine pod and propeller
    R(d, ex - 12, ey + 13, ex - 11, ey + 19, IRON[3])
    return im


# ------------------------------------------------------------------ citizens
def citizen(kind, facing, frame, cloth=None, hair=None, skin=None):
    """11x17 walker, about door height (D26: scaled down from 16x24). kinds: villager, weaver, farmer, mage."""
    im = Image.new("RGBA", (11, 17))
    d = ImageDraw.Draw(im)
    skin_d = mul(skin, 0.8) if skin else hexc("c88a62")
    skin = skin or hexc("eab48a")
    cloth = cloth or {"villager": LEAF["green"][2], "weaver": hexc("b0403a"), "farmer": hexc("4a6a9a"),
             "mage": hexc("3a3a8a")}[kind]
    cloth_d, cloth_l = mul(cloth, 0.7), mul(cloth, 1.25)
    hair = hair or {"villager": hexc("6a4428"), "weaver": hexc("3a2418"), "farmer": hexc("a87a3a"),
            "mage": hexc("e8e4dc")}[kind]
    st = frame % 2 if frame < 2 else 0
    mid = frame == 2  # standing pose between the two steps
    robe = kind in ("weaver", "mage")
    # legs
    if robe:
        d.point([(3 + st, 15), (4 + st, 15), (6 - st, 15), (7 - st, 15)], fill=WOOD[0])
    elif facing == "side":
        if mid:
            R(d, 4, 13, 5, 15, WOOD[1])
            R(d, 5, 13, 6, 15, WOOD[0])
        else:
            R(d, 3 + st, 13, 4 + st, 15, WOOD[1])
            R(d, 6 - st, 13, 7 - st, 15, WOOD[0])
    else:
        R(d, 3, 13, 4, 15 if mid else 15 - st, WOOD[1])
        R(d, 6, 13, 7, 15 if mid else 14 + st, WOOD[1])
    # body
    if robe:
        d.polygon([(3, 8), (7, 8), (8, 14), (2, 14)], fill=cloth)
        d.polygon([(6, 8), (7, 8), (8, 14), (6, 14)], fill=cloth_d)
        if kind == "weaver" and facing != "up":
            R(d, 4, 10, 5, 13, PLASTER[3])
    else:
        R(d, 3, 8, 7, 12, cloth)
        R(d, 7, 8, 7, 12, cloth_d)
        d.point((3, 8), fill=cloth_l)
        R(d, 3, 11, 7, 11, WOOD[1])
    if kind == "farmer" and facing != "up":
        d.point([(4, 8), (4, 9), (6, 8), (6, 9)], fill=hexc("f0e0c0"))
    # arms
    if facing != "side":
        R(d, 2, 8, 2, 10 + st, cloth_d)
        R(d, 8, 8, 8, 11 - st, cloth_d)
        d.point([(2, 11 + st), (8, 12 - st)], fill=skin)
    else:
        R(d, 5, 9, 5, 11, cloth_d)
        d.point((5 + st, 12), fill=skin)
    # head
    R(d, 3, 3, 7, 7, skin)
    R(d, 7, 4, 7, 7, skin_d)
    if facing == "down":
        R(d, 3, 2, 7, 3, hair)
        d.point([(3, 4), (7, 4)], fill=hair)
        d.point([(4, 5), (6, 5)], fill=hexc("2a1e18"))
    elif facing == "up":
        R(d, 3, 2, 7, 7, hair)
        R(d, 7, 3, 7, 7, mul(hair, 0.8))
    else:
        R(d, 3, 2, 7, 3, hair)
        R(d, 3, 4, 4, 6, hair)
        d.point((6, 5), fill=hexc("2a1e18"))
    if kind == "weaver":
        R(d, 4, 1, 6, 1, hair)
    if kind == "farmer":
        d.ellipse([1, 1, 9, 3], fill=THATCH[3])
        R(d, 3, 1, 7, 1, THATCH[2])
        R(d, 3, 3, 7, 3, hexc("b83a32"))
    glows = []
    if kind == "mage":
        d.polygon([(2, 3), (5, 0), (8, 3)], fill=cloth)
        d.polygon([(5, 0), (8, 3), (6, 3)], fill=cloth_d)
        R(d, 2, 3, 8, 3, cloth_l)
        sx = 9 if facing != "side" else 8
        R(d, sx, 5, sx, 15, WOOD[3])
        R(d, sx - 1, 3, sx + 1, 5, CRYSTAL[3])
        d.point((sx, 3), fill=CRYSTAL[4])
        glows.append((sx + 1, 5, 6, GLOW))
    return sel_outline(im), glows


# ------------------------------------------------------------------ ground
BAYER = np.array([[0, 8, 2, 10], [12, 4, 14, 6], [3, 11, 1, 9], [15, 7, 13, 5]], dtype=np.float32) / 16


def vnoise(w, h, cell, seed):
    rng = np.random.default_rng(seed)
    gw, gh = w // cell + 3, h // cell + 3
    g = (rng.random((gh, gw)) * 255).astype(np.uint8)
    im = Image.fromarray(g).resize((gw * cell, gh * cell), Image.BICUBIC)
    return np.asarray(im, dtype=np.float32)[:h, :w] / 255


def fbm(w, h, seed):
    return 0.55 * vnoise(w, h, 64, seed) + 0.3 * vnoise(w, h, 20, seed + 1) + 0.15 * vnoise(w, h, 7, seed + 2)


def quant(v, n, H, W, amt=0.7):
    thr = np.tile(BAYER, (H // 4 + 1, W // 4 + 1))[:H, :W]
    v = (v - v.min()) / (v.max() - v.min() + 1e-6)
    return np.clip((v * n + (thr - 0.5) * amt).astype(int), 0, n - 1)


def dist_from(mask, maxd):
    d = np.full(mask.shape, maxd + 1, dtype=np.int32)
    cur = mask.copy()
    d[cur] = 0
    for i in range(1, maxd + 1):
        grown = cur.copy()
        grown[1:] |= cur[:-1]
        grown[:-1] |= cur[1:]
        grown[:, 1:] |= cur[:, :-1]
        grown[:, :-1] |= cur[:, 1:]
        newly = grown & ~cur
        d[newly] = i
        cur = grown
    return d


def seg_dist(px, py, a, b):
    ax, ay = a
    bx, by = b
    vx, vy = bx - ax, by - ay
    L2 = vx * vx + vy * vy
    t = np.clip(((px - ax) * vx + (py - ay) * vy) / L2, 0, 1)
    return np.hypot(px - (ax + t * vx), py - (ay + t * vy))


MAP_W, MAP_H = 26, 16
TERR = {"grass": 0, "soil": 1, "forest": 2, "rock": 3, "water": 4, "vein": 5}


def build_map():
    rng = random.Random(11)
    m = [["grass"] * MAP_W for _ in range(MAP_H)]
    wobble = [1, 1, 1, 0, 0, 0, 0, 0, 0, 1, 1, 1, 0, 0, 1, 1]
    for y in range(MAP_H):
        for dx in range(2):
            m[y][18 + wobble[y] + dx] = "water"
    for y in range(0, 3):
        for x in range(20, 26):
            if not (y == 2 and x < 22):
                m[y][x] = "water"
    for x, y in [(23, 12), (24, 12), (23, 13), (24, 13)]:
        m[y][x] = "water"
    for y in range(0, 6):
        for x in range(0, 7 - y // 2):
            if rng.random() < 0.88:
                m[y][x] = "forest"
    for y in range(11, 16):
        for x in range(0, 4):
            if rng.random() < 0.7:
                m[y][x] = "rock"
    for y in range(8, 14):
        for x in range(14, 18):
            if m[y][x] == "grass":
                m[y][x] = "soil"
    for x, y in [(7, 13), (8, 14), (7, 14)]:
        m[y][x] = "vein"
    return m


ROADS = [((2, 7), (25.9, 7)), ((11, 2), (11, 13)), ((11, 13), (9, 13))]
BLIGHT_CENTER, BLIGHT_R = (8.0, 13.6), 3.4


def render_ground(m):
    W, H = MAP_W * T, MAP_H * T
    ys, xs = np.mgrid[0:H, 0:W].astype(np.float32)
    wx = xs + (vnoise(W, H, 24, 5) - 0.5) * 18
    wy = ys + (vnoise(W, H, 24, 6) - 0.5) * 18
    tx = np.clip((wx // T).astype(int), 0, MAP_W - 1)
    ty = np.clip((wy // T).astype(int), 0, MAP_H - 1)
    grid = np.array([[TERR[c] for c in row] for row in m])
    ter = grid[ty, tx]
    water = ter == TERR["water"]
    n = fbm(W, H, 1)
    out = np.zeros((H, W, 3), dtype=np.uint8)
    gi = quant(n, 4, H, W) + 1  # 1..4
    gi = np.where((ter == TERR["forest"]) | (ter == TERR["soil"]), gi - 1, gi)
    G = np.array([c[:3] for c in GRASS], dtype=np.uint8)
    out[:] = G[np.clip(gi, 0, 4)]
    # vein ground
    V = np.array([c[:3] for c in VEIN], dtype=np.uint8)
    vm = ter == TERR["vein"]
    out[vm] = V[quant(fbm(W, H, 9), 4, H, W)][vm]
    # blight (warped radial)
    bd = np.hypot(wx / T - BLIGHT_CENTER[0], (wy / T - BLIGHT_CENTER[1]) * 1.1)
    bm = (bd < BLIGHT_R) & ~water & ~vm
    B = np.array([c[:3] for c in BLIGHT], dtype=np.uint8)
    out[bm] = B[np.clip(gi, 0, 4)][bm]
    edge = (bd >= BLIGHT_R) & (bd < BLIGHT_R + 0.35) & ~water & ~vm
    thr = np.tile(BAYER, (H // 4 + 1, W // 4 + 1))[:H, :W]
    edge &= thr < (1 - (bd - BLIGHT_R) / 0.35) * 0.6
    out[edge] = B[np.clip(gi, 0, 4)][edge]
    # water depth bands + bank
    wd = dist_from(~water, 12)
    ld = dist_from(water, 3)
    Wp = np.array([c[:3] for c in WATER], dtype=np.uint8)
    lvl = np.select([wd <= 1, wd <= 3, wd <= 6, wd <= 10], [5, 4, 3, 2], 1)
    rip = (vnoise(W, H, 3, 77) > 0.8) & (wd > 3)
    lvl = np.where(rip, np.minimum(lvl + 1, 4), lvl)
    above_land = np.zeros_like(water)
    for k in range(1, 5):
        above_land[k:] |= ~water[:-k]
    lvl = np.where(above_land & water & (wd > 1), np.maximum(lvl - 2, 0), lvl)
    out[water] = Wp[lvl][water]
    Bk = np.array([c[:3] for c in BANK], dtype=np.uint8)
    out[(ld == 1)] = Bk[0]
    out[(ld == 2)] = Bk[1]
    out[(ld == 3) & (thr < 0.5)] = Bk[2]
    # roads (cobble)
    rd = np.full((H, W), 99.0, dtype=np.float32)
    rwx = xs + (vnoise(W, H, 16, 8) - 0.5) * 6
    rwy = ys + (vnoise(W, H, 16, 9) - 0.5) * 6
    for a, b in ROADS:
        rd = np.minimum(rd, seg_dist(rwx, rwy, (a[0] * T + 16, a[1] * T + 16), (b[0] * T + 16, b[1] * T + 16)))
    road = (rd < 10) & ~water & (ld > 2)
    D = np.array([c[:3] for c in DIRT], dtype=np.uint8)
    out[road] = D[quant(fbm(W, H, 4), 3, H, W) + 1][road]
    img = Image.fromarray(out, "RGB").convert("RGBA")
    d = ImageDraw.Draw(img)
    rng = random.Random(3)
    # cobblestones
    for y in range(0, H, 5):
        for x in range((y // 5) % 2 * 3, W, 6):
            jx, jy = x + rng.randint(-1, 1), y + rng.randint(-1, 1)
            if 0 <= jx < W and 0 <= jy < H and road[jy, jx] and rd[jy, jx] < 8.5:
                c = rng.choice(COBBLE[1:])
                d.ellipse([jx - 2, jy - 1, jx + 2, jy + 2], fill=COBBLE[0])
                d.ellipse([jx - 2, jy - 2, jx + 1, jy + 1], fill=c)
    # grass details
    grass_ok = (ter <= 2) & ~water & ~road & ~bm & (ld > 3)
    flowers = [hexc("f07aa8"), hexc("f6f0e0"), hexc("8ab8f8"), hexc("f4d050")]
    for _ in range(W * H // 70):
        x, y = rng.randrange(2, W - 2), rng.randrange(3, H - 1)
        if not grass_ok[y, x]:
            continue
        base = out[y, x]
        if rng.random() < 0.8:
            c = tuple(min(255, int(v * 1.25)) for v in base) + (255,)
            dc = tuple(int(v * 0.7) for v in base) + (255,)
            d.point([(x, y), (x - 1, y - 1), (x + 1, y - 1), (x, y - 2)], fill=c)
            d.point([(x, y + 1)], fill=dc)
        elif ter[y, x] == 0:
            c = rng.choice(flowers)
            for k in range(rng.randint(2, 4)):
                fx, fy = x + rng.randint(-3, 3), y + rng.randint(-2, 2)
                d.point((fx, fy + 1), fill=GRASS[0])
                d.point((fx, fy), fill=c)
    # blight specks + vein cracks
    for _ in range(600):
        x, y = rng.randrange(W), rng.randrange(H)
        if bm[y, x]:
            d.ellipse([x, y, x + rng.randint(2, 4), y + rng.randint(1, 3)], fill=BLIGHT[0])
            d.point((x + 1, y - 1), fill=BLIGHT[4])
    for _ in range(14):
        x, y = rng.randrange(W), rng.randrange(H)
        if vm[y, x]:
            pts = [(x, y)]
            for _ in range(4):
                x, y = x + rng.randint(-6, 6), y + rng.randint(-4, 4)
                pts.append((x, y))
            d.line(pts, fill=CRYSTAL[1], width=2)
            d.line(pts, fill=CRYSTAL[3])
    # lily pads
    for x, y in [(23 * T + 12, 12 * T + 14), (24 * T + 6, 12 * T + 22), (23 * T + 20, 13 * T + 6)]:
        d.ellipse([x - 4, y - 3, x + 4, y + 3], fill=LEAF["green"][1])
        d.ellipse([x - 3, y - 3, x + 3, y + 2], fill=LEAF["green"][3])
        d.point((x + 1, y - 1), fill=hexc("f4a0c0"))
    return img, water, road


# ------------------------------------------------------------------ scene
def render_scene(dimming=False):
    m = build_map()
    W, H = MAP_W * T, MAP_H * T
    ground, water, road = render_ground(m)
    rng = random.Random(21)
    objs = []  # (base_y, x, sprite, draw_x, draw_y)

    def put(sp, px, base_y):
        objs.append((base_y, px, sp))

    def place(sp, tx, ty):
        px = tx * T + (sp.fw * T - sp.img.width) // 2
        put(sp, px, (ty + sp.fh) * T)

    # forest
    for y in range(MAP_H):
        for x in range(MAP_W):
            if m[y][x] == "forest":
                for k in range(2 if rng.random() < 0.6 else 1):
                    r = rng.random()
                    s = rng.uniform(0.8, 1.15)
                    sp = pine(rng.random() * 1e6, s) if r < 0.3 else oak(rng.random() * 1e6, s,
                                                                         "autumn" if r > 0.85 else "green")
                    bx = x * T + rng.randint(4, 28)
                    put(sp, bx - sp.img.width // 2, y * T + rng.randint(18, 32))
            elif m[y][x] == "rock":
                for k in range(rng.randint(1, 2)):
                    sp = boulder(rng.random() * 1e6, rng.uniform(0.8, 1.3))
                    put(sp, x * T + rng.randint(0, 14), y * T + rng.randint(14, 30))
    for tx, ty, kind in [(14, 3, "green"), (16, 2, "autumn"), (22, 9, "green"), (25, 5, "deep"),
                         (25, 12, "green"), (5, 11, "autumn"), (21, 15, "green"), (13, 14, "green"),
                         (3, 9, "green"), (15, 15, "autumn")]:
        sp = pine(tx * 7, 1.0) if kind == "deep" else oak(tx * 13 + ty, rng.uniform(0.95, 1.15), kind)
        put(sp, tx * T + 16 - sp.img.width // 2, ty * T + 30)
    glowtree = oak(99, 1.35, "lumen")
    put(glowtree, 16 * T + 20 - glowtree.img.width // 2, 6 * T + 22)
    # buildings
    place(b_hearth(), 9, 8)
    put(b_brazier(), 10 * T - 8, 10 * T + 12)
    place(b_bell_tower(), 7, 9)
    for i, (tx, ty) in enumerate([(6, 5), (8, 5), (4, 8)]):
        place(b_tent(i), tx, ty)
    for i, (tx, ty, roof) in enumerate([(12, 5, "thatch"), (13, 5, "shingle"), (14, 6, "thatch"),
                                        (12, 9, "shingle"), (13, 8, "thatch")]):
        place(b_cottage(i + 3, roof), tx, ty)
    place(b_woodcutter(1), 7, 3)
    place(b_woodcutter(2), 3, 6)
    place(b_farm(1), 15, 9)
    place(b_farm(2), 15, 11)
    place(b_market(), 12, 10)
    place(b_shrine(), 14, 13)
    place(b_lumen_mill(), 8, 13)
    for tx, ty in [(7, 13), (8, 15), (6, 14)]:
        put(crystal_cluster(tx * 3 + ty), tx * T + 1, ty * T + 30)
    # lanterns along roads
    for px, py in [(10 * T + 24, 7 * T + 4), (12 * T + 8, 7 * T + 4), (16 * T, 7 * T + 4), (6 * T, 7 * T + 30),
                   (11 * T + 30, 11 * T + 8), (22 * T, 7 * T + 4), (3 * T, 7 * T + 4)]:
        put(lantern_post(), px, py)
    # mushrooms
    for i, (px, py) in enumerate([(7 * T + 4, 5 * T + 6), (2 * T + 10, 6 * T + 20), (5 * T + 8, 2 * T + 28),
                                  (18 * T + 2, 9 * T + 4), (9 * T + 20, 14 * T + 24)]):
        put(mushrooms(i, i % 2 == 0), px, py)
    # walkers
    walkers = [("villager", "side", 3 * T + 12, 7 * T + 22), ("farmer", "down", 11 * T + 10, 4 * T + 20),
               ("mage", "up", 11 * T + 14, 11 * T + 18), ("weaver", "down", 11 * T + 8, 9 * T + 2),
               ("farmer", "side", 15 * T + 8, 7 * T + 24), ("villager", "side", 6 * T + 20, 7 * T + 20),
               ("mage", "side", 22 * T + 12, 7 * T + 22), ("weaver", "side", 13 * T, 7 * T + 26)]

    class W_:
        pass

    for kind, facing, px, py in walkers:
        img, glows = citizen(kind, facing, rng.randrange(2))
        sp = W_()
        sp.img, sp.glows, sp.smoke, sp.shadow, sp.fw = img, [(x + 1, y + 1, r, c) for x, y, r, c in glows], [], (0.7, 2), 1
        put(sp, px - img.width // 2, py)

    # shadows onto the ground
    shadow = Image.new("L", (W, H))
    sd = ImageDraw.Draw(shadow)
    for base, px, sp in objs:
        if not sp.shadow:
            continue
        wf, hh = sp.shadow
        w = sp.img.width * wf
        cx = px + sp.img.width / 2 + w * 0.12
        sd.ellipse([cx - w / 2, base - hh * 0.6, cx + w / 2 + hh * 0.6, base + hh * 0.4], fill=255)
    g = np.array(ground, dtype=np.float32)
    sm = np.array(shadow, dtype=np.float32)[..., None] / 255
    g[..., :3] = g[..., :3] * (1 - 0.32 * sm) + np.array([10, 14, 40]) * 0.08 * sm
    scene = Image.fromarray(np.clip(g, 0, 255).astype(np.uint8), "RGBA")
    # bridge (flat, before objects)
    river_x = [x for x in range(MAP_W) if m[7][x] == "water"]
    bx0, bx1 = min(river_x) * T - 10, (max(river_x) + 1) * T + 10
    scene.alpha_composite(b_bridge(bx1 - bx0), (bx0, 7 * T + 3))
    glow = Image.new("RGBA", (W, H))
    smoke_pts = []
    objs.sort(key=lambda o: o[0])
    for base, px, sp in objs:
        py = base - sp.img.height + 1
        sx, sy = max(0, -px), max(0, -py)
        scene.alpha_composite(sp.img, (max(px, 0), max(py, 0)), (sx, sy))
        for gx, gy, r, c in sp.glows:
            gi = glow_img(r, c)
            x, y = px + gx - r, py + gy - r
            if x + gi.width > 0 and y + gi.height > 0:
                glow.alpha_composite(gi, (max(x, 0), max(y, 0)), (max(0, -x), max(0, -y)))
        smoke_pts += [(px + x, py + y) for x, y in sp.smoke]
    # smoke wisps
    sm_layer = Image.new("RGBA", (W, H))
    smd = ImageDraw.Draw(sm_layer)
    for x, y in smoke_pts:
        for k in range(4):
            r = 2 + k
            cx, cy = x + int(math.sin(k * 1.3) * 3) + k, y - k * 6
            smd.ellipse([cx - r, cy - r, cx + r, cy + r], fill=(235, 235, 240, 150 - k * 32))
    scene.alpha_composite(sm_layer)
    # floating motes near Lumen sources
    md = ImageDraw.Draw(glow)
    for cx, cy, n in [(8 * T, 13 * T, 26), (13 * T + 16, 11 * T, 14), (17 * T, 6 * T, 18), (10 * T, 9 * T, 10)]:
        for _ in range(n):
            x, y = int(cx + rng.gauss(0, 30)), int(cy + rng.gauss(0, 24))
            if 0 <= x < W and 0 <= y < H:
                glow.alpha_composite(glow_img(4, GLOW, 1.4), (max(0, x - 4), max(0, y - 4)))
                md.point((x, y), fill=CRYSTAL[4])
    if dimming:
        a = np.array(scene, dtype=np.float32)
        a[..., :3] = a[..., :3] * np.array([0.38, 0.46, 0.78]) + np.array([4, 8, 22])
        scene = Image.fromarray(np.clip(a, 0, 255).astype(np.uint8), "RGBA")
        g2 = glow.copy()
        g2.putalpha(g2.getchannel("A").point(lambda v: int(v * 0.55)))
        scene.alpha_composite(g2)
    else:
        scene.alpha_composite(glow)
    # soft vignette + warm grade
    a = np.array(scene, dtype=np.float32)
    yy, xx = np.mgrid[0:H, 0:W]
    v = 1 - 0.22 * (((xx - W / 2) / (W / 2)) ** 2 + ((yy - H / 2) / (H / 2)) ** 2) / 2
    a[..., :3] *= v[..., None]
    if not dimming:
        a[..., 0] *= 1.03
        a[..., 2] *= 0.97
    return Image.fromarray(np.clip(a, 0, 255).astype(np.uint8), "RGBA")


# ------------------------------------------------------------------ HUD
def icon(kind):
    im = Image.new("RGBA", (12, 12))
    d = ImageDraw.Draw(im)
    if kind == "food":
        d.ellipse([1, 3, 10, 11], fill=hexc("c84a3a"))
        d.ellipse([3, 4, 5, 6], fill=hexc("f08a7a"))
        d.line([(6, 3), (7, 0)], fill=WOOD[1])
        d.point((8, 1), fill=LEAF["green"][3])
    elif kind == "materials":
        R(d, 0, 5, 11, 10, WOOD[3])
        d.ellipse([8, 5, 11, 10], fill=hexc("d8b07a"))
        R(d, 2, 1, 7, 4, STONE[3])
    elif kind == "lumen":
        crystal(d, 3, 11, 10, 6)
    elif kind == "gold":
        d.ellipse([1, 1, 10, 10], fill=BRASS[2])
        d.ellipse([3, 3, 8, 8], fill=BRASS[3])
    elif kind == "pop":
        R(d, 4, 1, 7, 4, hexc("eab48a"))
        R(d, 2, 5, 9, 11, LEAF["green"][2])
    elif kind == "spirit":
        d.polygon([(6, 11), (1, 5), (3, 1), (6, 3), (9, 1), (11, 5)], fill=hexc("e06a8a"))
    elif kind == "moon":
        d.ellipse([1, 1, 10, 10], fill=hexc("c8d0f0"))
        d.ellipse([4, 0, 12, 8], fill=(0, 0, 0, 0))
    return sel_outline(im)


def panel(d, box, r=8):
    d.rounded_rectangle(box, r, fill=(30, 24, 20, 225), outline=BRASS[1], width=2)
    x0, y0, x1, y1 = box
    d.rounded_rectangle([x0 + 3, y0 + 3, x1 - 3, y1 - 3], r - 2, outline=(70, 56, 40, 255), width=1)


def upscale(im, s):
    return im.resize((im.width * s, im.height * s), Image.NEAREST)


def hud(img, s, dimming=False):
    d = ImageDraw.Draw(img, "RGBA")
    W, H = img.size
    panel(d, [8, 6, W - 8, 58])
    f = font(20)
    x = 24
    vals = [("food", "142  +6"), ("materials", "88  +4"), ("lumen", "36  +9" if not dimming else "36  -3"),
            ("gold", "51  +2"), ("pop", "23 / 28")]
    for k, v in vals:
        img.alpha_composite(upscale(icon(k), 3), (x, 13))
        d.text((x + 44, 32), v, font=f, fill=(240, 228, 204), anchor="lm")
        x += 186
    img.alpha_composite(upscale(icon("spirit"), 3), (x, 13))
    d.rounded_rectangle([x + 44, 24, x + 204, 40], 4, fill=(60, 46, 46))
    d.rounded_rectangle([x + 44, 24, x + 44 + (118 if not dimming else 70), 40], 4,
                        fill=(120, 196, 96) if not dimming else (214, 160, 60))
    d.text((x + 214, 32), "Spirit", font=font(16), fill=(240, 228, 204), anchor="lm")
    pw = 370
    px = W - pw - 16
    panel(d, [px, 70, W - 16, 160])
    d.text((px + 16, 80), "Era: Village", font=font(18), fill=BRASS[3])
    img.alpha_composite(upscale(icon("moon"), 2), (px + 16, 112))
    txt = "Dimming in 2 days - lasts 3" if not dimming else "DIMMING - day 1 of 3"
    d.text((px + 48, 111), txt, font=font(18), fill=(200, 214, 244))
    d.text((px + 16, 136), "Year 3, Summer" if not dimming else "Year 3, Summer - crops slowed",
           font=font(14), fill=(176, 164, 150))
    tx, ty = 1 * T * s, 10 * T * s - 40
    panel(d, [tx, ty, tx + 310, ty + 96])
    d.text((tx + 14, ty + 10), "Lumen Tap", font=font(18), fill=CRYSTAL[3])
    d.text((tx + 14, ty + 38), "Workers 2/2   Lumen " + ("+3/day (Dimming)" if dimming else "+9/day"),
           font=font(15), fill=(240, 228, 204))
    d.text((tx + 14, ty + 62), "Blight spreading: 6 tiles", font=font(15), fill=(190, 160, 220))
    cats = ["Roads", "Housing", "Food", "Materials", "Lumen", "Civic", "Landmark"]
    bw = 150
    bx = (W - len(cats) * (bw + 8)) // 2
    panel(d, [bx - 14, H - 70, W - bx + 6, H - 8])
    for i, c in enumerate(cats):
        x0 = bx + i * (bw + 8)
        sel = c == "Housing"
        d.rounded_rectangle([x0, H - 60, x0 + bw, H - 18], 6, fill=(78, 62, 46) if sel else (48, 40, 34),
                            outline=BRASS[3] if sel else (90, 74, 56), width=2)
        d.text((x0 + bw // 2, H - 39), c, font=font(17), fill=(240, 228, 204), anchor="mm")


# ------------------------------------------------------------------ sheets
def bg(w, h):
    return Image.new("RGBA", (w, h), hexc("1e1b18"))


def label(d, x, y, text, size=16, col=(232, 222, 202, 255), anchor="ma"):
    d.text((x, y), text, font=font(size), fill=col, anchor=anchor)


class _Plain:
    """Already-outlined image (citizens) shown on a sheet without a second outline pass."""

    def __init__(self, img, glows):
        self.img, self.glows = img, [(x + 1, y + 1, r, c) for x, y, r, c in glows]


def sheet_buildings():
    eras = [
        ("Camp", [("Hearth", b_hearth()), ("Tent", b_tent(0)), ("Woodcutter", b_woodcutter(1)),
                  ("Lumen Tap", b_lumen_mill()), ("Meeting Hall*", b_meeting_hall())]),
        ("Village", [("Cottage", b_cottage(3, "thatch")), ("Cottage (shingle)", b_cottage(4, "shingle")),
                     ("Farm", b_farm(1)), ("Market", b_market()), ("Shrine", b_shrine()),
                     ("Bell Tower*", b_bell_tower())]),
    ]
    return sheet(eras, "Hearthvein v2 - Camp and Village buildings (shown 3x, * = era landmark)")


def sheet_town_city():
    walker = _Plain(*citizen("villager", "down", 0))
    eras = [
        ("Town", [("Rowhouse", b_rowhouse(2)), ("citizen", walker), ("Greenhouse", b_greenhouse(3)),
                  ("Lumen Pump", b_lumen_pump()), ("Cleanser", b_cleanser(4)), ("Lumen Spire*", b_lumen_spire())]),
        ("City", [("Apartment Block", b_apartment(5)), ("Lumen Reactor", b_reactor()), ("Park", b_park(6)),
                  ("Skyheart*", b_skyheart())]),
    ]
    return sheet(eras, "Hearthvein v2 - Town and City buildings (shown 3x, * = era landmark, citizen for scale)",
                 Wd=1500)


def sheet(eras, title, Wd=1780):
    s = 3
    row_h = [max(sp.img.height for _, sp in row) * s + 70 for _, row in eras]
    img = bg(Wd, sum(row_h) + 120)
    d = ImageDraw.Draw(img)
    label(d, Wd // 2, 18, title, 22)
    y = 80
    for (era, row), rh in zip(eras, row_h):
        label(d, 20, y + rh // 2 - 20, era, 24, BRASS[3], anchor="la")
        x = 170
        base = y + rh - 56
        for name, sp in row:
            pad = 30
            canvas = Image.new("RGBA", (sp.img.width + 2 * pad, sp.img.height + 2 * pad))
            canvas.alpha_composite(sp.img, (pad, pad))
            gl = Image.new("RGBA", canvas.size)
            for gx, gy, r, c in sp.glows:
                gl.alpha_composite(glow_img(r, c), (max(0, pad + gx - r), max(0, pad + gy - r)))
            canvas.alpha_composite(gl)
            big = upscale(canvas, s)
            img.alpha_composite(big, (x - pad * s, base - big.height + pad * s))
            label(d, x + sp.img.width * s // 2, base + 10, name, 15)
            x += sp.img.width * s + 46
        y += rh
    return img


def sheet_citizens():
    kinds = ["villager", "weaver", "farmer", "mage"]
    frames = [(f, k) for f in ("down", "up", "side") for k in (0, 1)]
    s = 8
    cw = 13 * s + 20
    img = bg(220 + cw * len(frames), 90 + len(kinds) * (19 * s + 24))
    d = ImageDraw.Draw(img)
    label(d, img.width // 2, 18, "Hearthvein v2 - citizens (11x17, shown 8x): down / up / side, 2 walk frames", 22)
    names = {"villager": "Villager", "weaver": "Weaver", "farmer": "Farmer", "mage": "Lumen mage"}
    for r, kind in enumerate(kinds):
        y = 70 + r * (19 * s + 24)
        label(d, 20, y + 64, names[kind], 20, BRASS[3], anchor="la")
        for c, (facing, fr) in enumerate(frames):
            im, glows = citizen(kind, facing, fr)
            cv = Image.new("RGBA", (im.width + 16, im.height + 16))
            cv.alpha_composite(im, (8, 8))
            for gx, gy, rr, col in glows:
                cv.alpha_composite(glow_img(rr, col), (max(0, 8 + gx - rr), max(0, 8 + gy - rr)))
            img.alpha_composite(upscale(cv, s), (220 + c * cw - 8 * s, y - 8 * s))
    return img


def main(out=None):
    OUT = Path(out) if out else (Path(sys.argv[1]) if len(sys.argv) > 1 else
                                 Path(__file__).resolve().parent.parent / "docs" / "mockups")
    OUT.mkdir(parents=True, exist_ok=True)
    s = 2
    for dim, name in ((False, "scene_village.png"), (True, "scene_dimming.png")):
        sc = render_scene(dim)
        if not dim:
            upscale(sc.crop((6 * T, 4 * T, 6 * T + 330, 4 * T + 220)), 4).save(OUT / "scene_closeup.png")
        big = upscale(sc, s)
        hud(big, s, dim)
        big.save(OUT / name)
    sheet_buildings().save(OUT / "buildings_camp_village.png")
    sheet_town_city().save(OUT / "buildings_town_city.png")
    sheet_citizens().save(OUT / "citizens.png")
    print("wrote", *sorted(p.name for p in OUT.glob("*.png")))


if __name__ == "__main__":
    main()
