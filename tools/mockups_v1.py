"""Generate Hearthvein design mockups (pixel art, 32x32 tiles) with Pillow.

Usage: python3 tools/mockups.py [out_dir]
Writes tiles.png, buildings.png, citizens.png, scene_village.png, scene_dimming.png.
Mockup art only: drawn procedurally to settle look and scale, not final assets.
"""
import random
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

T = 32
OUT = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(__file__).resolve().parent.parent / "docs" / "mockups"
FONT_B = "/usr/share/fonts/noto/NotoSans-Bold.ttf"
FONT_M = "/usr/share/fonts/noto/NotoSansMono-Bold.ttf"
OUTLINE = (34, 26, 22, 255)


def hexc(h, a=255):
    h = h.lstrip("#")
    return (int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16), a)


def font(size, mono=False):
    try:
        return ImageFont.truetype(FONT_M if mono else FONT_B, size)
    except OSError:
        return ImageFont.load_default(size)


# ---------------------------------------------------------------- palette
P = {k: hexc(v) for k, v in {
    "grass": "5f8f3e", "grass_l": "74a64a", "grass_d": "4c7632",
    "soil": "5a6b2c", "soil_b": "6e5430", "soil_l": "7d9a3a",
    "tree": "2f5e2c", "tree_l": "4a8a3a", "tree_d": "21431f", "trunk": "5a3d22",
    "rock": "8b8a84", "rock_l": "b0ada4", "rock_d": "5f5e5a",
    "water": "3b6fa8", "water_l": "6a9ad0", "water_d": "2f5a8c", "foam": "b8d6ec",
    "vein": "47534f", "vein_d": "36403d", "lumen": "7fe0f0", "lumen_l": "d8fcff", "lumen_d": "2a8aa0",
    "blight": "6e5f7e", "blight_d": "4e4260", "blight_l": "8d7ea0",
    "dirt": "a2805a", "dirt_d": "86673f", "dirt_l": "b8996e",
    "pave": "8f8d88", "pave_d": "6a6863", "pave_l": "aaa7a0",
    "wood": "8a5a32", "wood_d": "64401f", "wood_l": "a8743e",
    "thatch": "c09a48", "thatch_d": "967430", "thatch_l": "d8b864",
    "plaster": "e4d8bc", "plaster_d": "c4b694",
    "stone": "a39d90", "stone_d": "7c766a", "stone_l": "c0bbb0",
    "brick": "9a5040", "brick_d": "763a2e",
    "slate": "3e5a66", "slate_l": "567682", "slate_d": "2c424c",
    "redroof": "9a4a32", "redroof_l": "b6603e", "redroof_d": "763622",
    "iron": "4c5058", "iron_l": "6e737c", "iron_d": "33363c", "brass": "c49a3a", "brass_l": "e0c060",
    "canvas": "d9c49a", "canvas_d": "b39d72",
    "win": "f2d27a", "win_l": "7fe0f0", "door": "4a2e18",
    "skin": "e0a878", "skin_d": "b98058", "hair": "4a2e1c",
}.items()}


def R(d, x0, y0, x1, y1, c):
    d.rectangle([x0, y0, x1, y1], fill=c)


def outline(img, pad=1):
    w, h = img.size
    out = Image.new("RGBA", (w + 2 * pad, h + 2 * pad))
    out.paste(img, (pad, pad))
    src = out.load()
    res = out.copy()
    o = res.load()
    W, H = out.size
    for y in range(H):
        for x in range(W):
            if src[x, y][3] > 0:
                continue
            for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                nx, ny = x + dx, y + dy
                if 0 <= nx < W and 0 <= ny < H and src[nx, ny][3] > 200:
                    o[x, y] = OUTLINE
                    break
    return res


def glow_layer(size, glows):
    layer = Image.new("RGBA", size)
    d = ImageDraw.Draw(layer)
    for gx, gy, r, col in glows:
        for i in range(r, 0, -1):
            a = int(70 * (1 - i / r) ** 1.5) + 4
            d.ellipse([gx - i, gy - i, gx + i, gy + i], fill=col[:3] + (a,))
    return layer


class Sprite:
    """Outlined sprite + glow specs; footprint in tiles."""

    def __init__(self, img, fw, fh, glows=()):
        self.img = outline(img)
        self.fw, self.fh = fw, fh
        self.glows = [(x + 1, y + 1, r, c) for x, y, r, c in glows]


# ---------------------------------------------------------------- terrain tiles
def speckle(d, rng, cols, n, w=T, h=T):
    for _ in range(n):
        d.point((rng.randrange(w), rng.randrange(h)), fill=rng.choice(cols))


def t_grass(seed):
    rng = random.Random(seed)
    im = Image.new("RGBA", (T, T), P["grass"])
    d = ImageDraw.Draw(im)
    speckle(d, rng, [P["grass_l"], P["grass_d"]], 80)
    for _ in range(4):
        x, y = rng.randrange(2, 29), rng.randrange(3, 30)
        d.point([(x, y), (x - 1, y - 1), (x + 1, y - 1), (x, y - 2)], fill=P["grass_l"])
    return im


def t_soil(seed):
    rng = random.Random(seed)
    im = Image.new("RGBA", (T, T), P["soil"])
    d = ImageDraw.Draw(im)
    speckle(d, rng, [P["soil_b"], P["soil_l"], P["grass_d"]], 140)
    for _ in range(5):
        x, y = rng.randrange(1, 28), rng.randrange(1, 30)
        R(d, x, y, x + 2, y + 1, P["soil_b"])
    return im


def tree(d, cx, cy, s=1.0):
    r = int(6 * s)
    R(d, cx - 1, cy + 1, cx + 1, cy + r, P["trunk"])
    d.ellipse([cx - r - 1, cy - r - 2, cx + r + 1, cy + r - 2], fill=P["tree_d"])
    d.ellipse([cx - r, cy - r - 2, cx + r, cy + r - 3], fill=P["tree"])
    d.ellipse([cx - r + 2, cy - r - 1, cx + 1, cy - 1], fill=P["tree_l"])


def t_forest(seed):
    rng = random.Random(seed)
    im = t_grass(seed)
    d = ImageDraw.Draw(im)
    R(d, 0, 0, T - 1, T - 1, P["grass_d"])
    speckle(d, rng, [P["grass"], P["tree_d"]], 60)
    for cx, cy in [(9, 9), (23, 11), (15, 21), (5, 24), (26, 25)]:
        tree(d, cx + rng.randint(-1, 1), cy + rng.randint(-1, 1), rng.choice([0.85, 1.0, 1.1]))
    return im


def boulder(d, x, y, w, h):
    d.ellipse([x, y, x + w, y + h], fill=P["rock_d"])
    d.ellipse([x, y, x + w - 1, y + h - 2], fill=P["rock"])
    d.ellipse([x + 2, y + 1, x + w // 2, y + h // 2], fill=P["rock_l"])


def t_rock(seed):
    rng = random.Random(seed)
    im = t_grass(seed)
    d = ImageDraw.Draw(im)
    speckle(d, rng, [P["rock_d"], P["dirt_d"]], 50)
    boulder(d, 3, 4, 14, 11)
    boulder(d, 16, 12, 13, 12)
    boulder(d, 4, 19, 10, 9)
    return im


def t_water(seed):
    rng = random.Random(seed)
    im = Image.new("RGBA", (T, T), P["water"])
    d = ImageDraw.Draw(im)
    speckle(d, rng, [P["water_d"]], 40)
    for _ in range(5):
        x, y = rng.randrange(0, 26), rng.randrange(2, 30)
        R(d, x, y, x + rng.randint(3, 6), y, P["water_l"])
    return im


def crystal(d, x, y, h, w=6):
    d.polygon([(x, y), (x + w // 2, y - h), (x + w, y)], fill=P["lumen"])
    d.polygon([(x, y), (x + w // 2, y - h), (x + w // 2, y)], fill=P["lumen_l"])
    d.line([(x, y), (x + w // 2, y - h), (x + w, y)], fill=P["lumen_d"])


def t_vein(seed):
    rng = random.Random(seed)
    im = Image.new("RGBA", (T, T), P["vein"])
    d = ImageDraw.Draw(im)
    speckle(d, rng, [P["vein_d"], P["rock_d"], P["lumen_d"]], 110)
    # glowing cracks
    d.line([(2, 26), (10, 20), (14, 22), (22, 14), (30, 12)], fill=P["lumen_d"], width=2)
    d.line([(10, 20), (14, 22), (22, 14)], fill=P["lumen"])
    crystal(d, 6, 18, 11)
    crystal(d, 17, 28, 14, 7)
    crystal(d, 22, 12, 9, 5)
    return im


def t_blight(base):
    im = Image.blend(base, Image.new("RGBA", (T, T), P["blight"]), 0.5)
    d = ImageDraw.Draw(im)
    rng = random.Random(7)
    speckle(d, rng, [P["blight_d"], P["blight_l"]], 70)
    for _ in range(3):
        x, y = rng.randrange(3, 26), rng.randrange(3, 26)
        d.ellipse([x, y, x + 4, y + 3], fill=P["blight_d"])
    return im


def t_dirt_road(seed, conn=(1, 1, 1, 1)):
    """conn = (up, right, down, left)."""
    im = t_grass(seed)
    d = ImageDraw.Draw(im)
    rng = random.Random(seed + 9)
    a, b = 9, 22
    R(d, a, a, b, b, P["dirt"])
    up, rt, dn, lf = conn
    if up: R(d, a, 0, b, a, P["dirt"])
    if dn: R(d, a, b, b, T - 1, P["dirt"])
    if lf: R(d, 0, a, a, b, P["dirt"])
    if rt: R(d, b, a, T - 1, b, P["dirt"])
    px = im.load()
    for _ in range(40):
        x, y = rng.randrange(T), rng.randrange(T)
        if px[x, y] == P["dirt"]:
            px[x, y] = rng.choice([P["dirt_d"], P["dirt_l"]])
    return im


def t_paved(seed, conn=(1, 1, 1, 1)):
    im = t_grass(seed)
    d = ImageDraw.Draw(im)
    a, b = 7, 24
    up, rt, dn, lf = conn
    boxes = [(a, a, b, b)]
    if up: boxes.append((a, 0, b, a))
    if dn: boxes.append((a, b, b, T - 1))
    if lf: boxes.append((0, a, a, b))
    if rt: boxes.append((b, a, T - 1, b))
    for x0, y0, x1, y1 in boxes:
        R(d, x0, y0, x1, y1, P["pave"])
    px = im.load()
    for y in range(T):
        for x in range(T):
            if px[x, y] == P["pave"]:
                off = 4 if (y // 4) % 2 else 0
                if y % 4 == 0 or (x + off) % 8 == 0:
                    px[x, y] = P["pave_d"]
                elif (x + y) % 7 == 0:
                    px[x, y] = P["pave_l"]
    return im


# ---------------------------------------------------------------- buildings
def house(w, wall_h, roof_h, wall, roof, roof_l, roof_d, win=P["win"], door=True, nwin=2,
          timber=False, brick=False, stone=False, shingle=True):
    im = Image.new("RGBA", (w, wall_h + roof_h))
    d = ImageDraw.Draw(im)
    # wall
    R(d, 1, roof_h - 1, w - 2, roof_h + wall_h - 1, wall)
    wy0, wy1 = roof_h, roof_h + wall_h - 1
    if timber:
        for x in range(1, w - 1, 6):
            d.line([(x, wy0), (x, wy1)], fill=P["wood_d"])
        d.line([(1, wy0 + 1), (w - 2, wy0 + 1)], fill=P["wood_d"])
    if brick or stone:
        dark = P["brick_d"] if brick else P["stone_d"]
        step = 3 if brick else 4
        for y in range(wy0, wy1, step):
            d.line([(1, y), (w - 2, y)], fill=dark)
            off = 0 if (y // step) % 2 else step
            for x in range(1 + off, w - 1, step * 2):
                d.line([(x, y), (x, y + step - 1)], fill=dark)
    R(d, 1, wy1, w - 2, wy1, P["door"])
    # door + windows
    cx = w // 2
    if door:
        R(d, cx - 3, wy1 - 8, cx + 2, wy1, P["door"])
        R(d, cx - 2, wy1 - 7, cx + 1, wy1 - 1, P["wood"])
        d.point((cx + 1, wy1 - 4), fill=P["brass"])
    slots = [cx - 9, cx + 6] if nwin == 2 else ([cx - 12, cx - 5, cx + 4, cx + 11] if nwin == 4 else [])
    for x in slots:
        if 1 < x < w - 5:
            R(d, x, wy0 + 3, x + 3, wy0 + 6, P["door"])
            R(d, x + 1, wy0 + 4, x + 2, wy0 + 5, win)
    # roof (3/4 view: back slope light, front slope mid, ridge dark)
    R(d, 0, 0, w - 1, roof_h - 1, roof)
    R(d, 0, 0, w - 1, roof_h // 2 - 1, roof_l)
    d.line([(0, roof_h // 2), (w - 1, roof_h // 2)], fill=roof_d)
    R(d, 0, roof_h - 1, w - 1, roof_h - 1, roof_d)
    if shingle:
        for y in range(2, roof_h - 1, 3):
            for x in range((y // 3) % 2 * 2, w, 4):
                d.point((x, y), fill=roof_d)
    return im


def canvas_on(fw, fh, H):
    im = Image.new("RGBA", (fw * T, H))
    return im, ImageDraw.Draw(im)


def b_tent():
    im, d = canvas_on(1, 1, 34)
    d.polygon([(3, 31), (16, 8), (29, 31)], fill=P["canvas"])
    d.polygon([(16, 8), (29, 31), (16, 31)], fill=P["canvas_d"])
    d.polygon([(12, 31), (16, 20), (20, 31)], fill=P["door"])
    d.line([(16, 4), (16, 9)], fill=P["wood_d"])
    d.line([(14, 5), (18, 7)], fill=P["wood"])
    return Sprite(im, 1, 1)


def b_hearth():
    im, d = canvas_on(2, 2, 92)
    body = house(60, 26, 30, P["stone"], P["slate"], P["slate_l"], P["slate_d"], stone=True, nwin=4)
    im.paste(body, (2, 92 - 56 - 2), body)
    # big chimney + Lumen flame
    R(d, 26, 14, 37, 40, P["stone_d"])
    R(d, 27, 15, 36, 40, P["stone"])
    R(d, 25, 13, 38, 15, P["stone_d"])
    d.polygon([(28, 13), (31, 3), (32, 8), (34, 1), (36, 13)], fill=P["lumen"])
    d.polygon([(30, 13), (32, 6), (34, 13)], fill=P["lumen_l"])
    # banners
    for x in (8, 50):
        R(d, x, 60, x + 4, 70, P["redroof"])
        d.point((x + 2, 69), fill=P["brass_l"])
    return Sprite(im, 2, 2, [(32, 8, 16, P["lumen"])])


def b_woodcutter():
    im, d = canvas_on(1, 1, 44)
    body = house(24, 13, 14, P["wood_l"], P["thatch"], P["thatch_l"], P["thatch_d"], timber=True, nwin=0)
    im.paste(body, (0, 44 - 27 - 3), body)
    for i, (x, y) in enumerate([(24, 38), (28, 38), (26, 34)]):
        d.ellipse([x - 2, y - 2, x + 2, y + 2], fill=P["wood"])
        d.ellipse([x - 1, y - 1, x + 1, y + 1], fill=P["dirt_l"])
    d.line([(4, 41), (9, 36)], fill=P["iron_l"])
    return Sprite(im, 1, 1)


def b_lumen_tap():
    im, d = canvas_on(1, 1, 52)
    crystal(d, 10, 48, 14, 12)
    # A-frame derrick
    for a, b in [((4, 50), (15, 6)), ((27, 50), (16, 6)), ((7, 38), (24, 38)), ((10, 24), (21, 24))]:
        d.line([a, b], fill=P["wood_d"], width=2)
        d.line([a, b], fill=P["wood"])
    R(d, 13, 3, 18, 8, P["iron"])
    d.line([(16, 8), (16, 36)], fill=P["iron_l"])
    # barrel with glow
    R(d, 21, 41, 28, 50, P["wood_d"])
    R(d, 22, 42, 27, 49, P["wood"])
    R(d, 22, 43, 27, 44, P["lumen"])
    return Sprite(im, 1, 1, [(16, 42, 12, P["lumen"])])


def b_meeting_hall():
    im, d = canvas_on(2, 2, 84)
    body = house(64, 24, 34, P["wood_l"], P["thatch"], P["thatch_l"], P["thatch_d"], timber=True, nwin=4)
    im.paste(body, (0, 84 - 58 - 4), body)
    for x in (2, 60):
        R(d, x, 22, x + 2, 82, P["wood_d"])
        d.polygon([(x - 2, 22), (x + 1, 16), (x + 4, 22)], fill=P["redroof"])
    return Sprite(im, 2, 2)


def b_cottage():
    im, d = canvas_on(1, 1, 46)
    body = house(30, 15, 17, P["plaster"], P["redroof"], P["redroof_l"], P["redroof_d"], timber=True)
    im.paste(body, (1, 46 - 32 - 2), body)
    R(d, 21, 8, 25, 16, P["stone_d"])
    for i in range(3):
        d.point((23 + i, 6 - 2 * i), fill=hexc("d0d0d0"))
    return Sprite(im, 1, 1)


def b_farm():
    im, d = canvas_on(2, 2, 64)
    R(d, 0, 0, 63, 63, P["soil_b"])
    for y in range(4, 60, 6):
        R(d, 3, y, 60, y + 2, P["dirt_d"])
        for x in range(4, 60, 3):
            d.line([(x, y + 3), (x, y)], fill=P["thatch_l"] if y < 30 else P["grass_l"])
            d.point((x, y - 1), fill=P["thatch"] if y < 30 else P["tree_l"])
    for x in range(0, 64, 8):
        R(d, x, 0, x + 1, 3, P["wood_d"])
        R(d, x, 60, x + 1, 63, P["wood_d"])
    d.line([(0, 1), (63, 1)], fill=P["wood"])
    d.line([(0, 61), (63, 61)], fill=P["wood"])
    # scarecrow
    d.line([(46, 26), (46, 38)], fill=P["wood_d"])
    d.line([(42, 30), (50, 30)], fill=P["wood_d"])
    R(d, 44, 23, 48, 26, P["canvas"])
    R(d, 43, 22, 49, 22, P["thatch_d"])
    return Sprite(im, 2, 2)


def b_market():
    im, d = canvas_on(2, 2, 70)
    R(d, 2, 40, 61, 68, P["pave"])
    for i, (x, y, c) in enumerate([(4, 30, "a83a32"), (34, 30, "3a62a8"), (18, 48, "4a8a3a")]):
        c = hexc(c)
        R(d, x + 1, y + 8, x + 2, y + 20, P["wood_d"])
        R(d, x + 23, y + 8, x + 24, y + 20, P["wood_d"])
        R(d, x, y + 14, x + 25, y + 19, P["wood"])
        for k in range(4):
            d.point((x + 4 + k * 5, y + 13), fill=[P["win"], hexc("c84a3a"), P["grass_l"], P["lumen"]][k])
        for s in range(0, 26, 4):
            R(d, x + s, y, x + s + 1, y + 8, c)
            R(d, x + s + 2, y, x + s + 3, y + 8, hexc("eee4d0"))
    return Sprite(im, 2, 2)


def b_shrine():
    im, d = canvas_on(1, 1, 56)
    R(d, 6, 44, 25, 54, P["stone_d"])
    R(d, 7, 44, 24, 52, P["stone"])
    d.polygon([(11, 44), (13, 14), (18, 14), (20, 44)], fill=P["stone_l"])
    d.polygon([(16, 14), (18, 14), (20, 44), (16, 44)], fill=P["stone"])
    d.polygon([(12, 14), (15, 6), (19, 14)], fill=P["stone_l"])
    d.line([(15, 20), (15, 26), (13, 30), (17, 34), (15, 40)], fill=P["lumen"])
    for x in (4, 8, 23, 27):
        d.point((x, 53), fill=hexc("e06a8a"))
        d.point((x + 1, 52), fill=P["win"])
    return Sprite(im, 1, 1, [(15, 28, 12, P["lumen"])])


def b_bell_tower():
    im, d = canvas_on(1, 1, 104)
    R(d, 4, 40, 27, 102, P["stone"])
    house_body = Image.new("RGBA", (24, 62))
    hd = ImageDraw.Draw(house_body)
    for y in range(0, 62, 4):
        hd.line([(0, y), (23, y)], fill=P["stone_d"])
        for x in range(0 if (y // 4) % 2 else 4, 24, 8):
            hd.line([(x, y), (x, y + 3)], fill=P["stone_d"])
    im.paste(house_body, (4, 40), house_body)
    R(d, 7, 22, 24, 40, P["door"])
    d.ellipse([11, 26, 20, 36], fill=P["brass"])
    d.ellipse([12, 27, 16, 31], fill=P["brass_l"])
    R(d, 4, 20, 27, 22, P["stone_d"])
    R(d, 4, 40, 27, 41, P["stone_d"])
    d.polygon([(2, 21), (15, 0), (16, 0), (29, 21)], fill=P["slate"])
    d.polygon([(16, 0), (29, 21), (16, 21)], fill=P["slate_d"])
    R(d, 12, 92, 19, 102, P["door"])
    R(d, 13, 60, 18, 66, P["door"])
    return Sprite(im, 1, 1)


def b_rowhouse():
    im, d = canvas_on(2, 1, 52)
    body = house(64, 18, 20, P["brick"], P["slate"], P["slate_l"], P["slate_d"], brick=True, door=False, nwin=0)
    im.paste(body, (0, 52 - 38), body)
    wy1 = 51
    for k, cx in enumerate((10, 32, 54)):
        R(d, cx - 3, wy1 - 8, cx + 2, wy1, P["door"])
        R(d, cx - 2, wy1 - 7, cx + 1, wy1 - 1, [P["slate_l"], P["wood"], P["redroof"]][k])
        R(d, cx + 5 if cx < 54 else cx - 9, 37, cx + 8 if cx < 54 else cx - 6, 41, P["win"])
    for x in (12, 34, 52):
        R(d, x, 6, x + 3, 18, P["iron"])
        R(d, x - 1, 5, x + 4, 6, P["iron_d"])
    return Sprite(im, 2, 1)


def b_greenhouse():
    im, d = canvas_on(2, 2, 72)
    R(d, 2, 22, 61, 70, P["iron_d"])
    glass = hexc("9fd8d0")
    for gx in range(4, 60, 8):
        R(d, gx, 24, gx + 5, 68, glass)
        R(d, gx, 24, gx + 1, 68, hexc("c8f0ea"))
    d.polygon([(2, 22), (12, 6), (52, 6), (61, 22)], fill=hexc("b8e8e0"))
    for gx in range(12, 53, 8):
        d.line([(gx, 6), (gx - 10 + (gx - 12) // 4, 22)], fill=P["iron"])
    d.line([(12, 6), (52, 6)], fill=P["iron_d"])
    rng = random.Random(3)
    for _ in range(40):
        x, y = rng.randrange(5, 59), rng.randrange(44, 66)
        d.point((x, y), fill=rng.choice([P["tree"], P["tree_l"], P["grass_l"], hexc("e06a8a")]))
    R(d, 0, 66, 63, 67, P["lumen_d"])
    R(d, 0, 66, 63, 66, P["lumen"])
    return Sprite(im, 2, 2, [(32, 66, 14, P["lumen"])])


def b_lumen_pump():
    im, d = canvas_on(2, 2, 84)
    R(d, 2, 50, 61, 82, P["iron"])
    R(d, 2, 50, 61, 52, P["iron_l"])
    for x in range(6, 60, 10):
        R(d, x, 56, x + 5, 62, P["lumen"])
        R(d, x + 1, 57, x + 2, 58, P["lumen_l"])
    # tank
    R(d, 8, 14, 30, 50, P["brass"])
    R(d, 8, 14, 12, 50, P["brass_l"])
    d.ellipse([8, 8, 30, 20], fill=P["brass_l"])
    for y in (24, 36):
        R(d, 8, y, 30, y + 1, P["iron_d"])
    # piston + pipes
    R(d, 40, 20, 48, 50, P["iron_d"])
    R(d, 42, 10, 46, 20, P["iron_l"])
    d.line([(30, 30), (40, 30)], fill=P["lumen_d"], width=3)
    d.line([(30, 30), (40, 30)], fill=P["lumen"])
    R(d, 52, 6, 57, 50, P["iron"])
    R(d, 51, 4, 58, 6, P["iron_d"])
    for i, (x, y) in enumerate([(55, 1), (52, -4)]):
        pass
    R(d, 18, 76, 28, 82, P["door"])
    return Sprite(im, 2, 2, [(19, 28, 14, P["lumen"]), (32, 60, 22, P["lumen"])])


def b_cleanser():
    im, d = canvas_on(1, 1, 64)
    R(d, 5, 22, 26, 62, P["stone"])
    R(d, 5, 22, 9, 62, P["stone_l"])
    d.ellipse([3, 12, 28, 28], fill=P["iron"])
    d.ellipse([6, 14, 25, 25], fill=hexc("9fe8c0"))
    d.line([(9, 19), (22, 19)], fill=P["iron_d"])
    d.line([(15, 14), (15, 25)], fill=P["iron_d"])
    R(d, 12, 52, 19, 62, P["door"])
    R(d, 12, 34, 19, 38, hexc("9fe8c0"))
    return Sprite(im, 1, 1, [(15, 19, 14, hexc("9fe8c0"))])


def b_lumen_spire():
    im, d = canvas_on(2, 2, 136)
    R(d, 4, 104, 59, 134, P["stone"])
    R(d, 4, 104, 59, 106, P["stone_l"])
    R(d, 26, 122, 37, 134, P["door"])
    d.polygon([(16, 104), (26, 30), (37, 30), (47, 104)], fill=P["iron"])
    d.polygon([(31, 30), (37, 30), (47, 104), (31, 104)], fill=P["iron_d"])
    for y in (50, 70, 90):
        R(d, 18 + (104 - y) // 8, y, 45 - (104 - y) // 8, y + 2, P["brass"])
    d.line([(31, 34), (31, 102)], fill=P["lumen"])
    d.polygon([(24, 30), (31, 4), (39, 30)], fill=P["lumen"])
    d.polygon([(24, 30), (31, 4), (31, 30)], fill=P["lumen_l"])
    return Sprite(im, 2, 2, [(31, 18, 26, P["lumen"])])


def b_apartment():
    im, d = canvas_on(2, 2, 104)
    R(d, 2, 10, 61, 102, P["brick"])
    for y in range(10, 102, 3):
        d.line([(2, y), (61, y)], fill=P["brick_d"])
    R(d, 0, 6, 63, 10, P["stone_d"])
    for fl in range(4):
        y = 16 + fl * 20
        R(d, 2, y + 15, 61, y + 16, P["stone"])
        for x in range(7, 58, 10):
            R(d, x, y, x + 5, y + 8, P["door"])
            lit = (x + fl * 3) % 4 != 0
            R(d, x + 1, y + 1, x + 4, y + 7, P["win_l"] if lit else P["slate_d"])
    R(d, 26, 90, 37, 102, P["door"])
    for x in (8, 48):
        R(d, x, 0, x + 4, 6, P["iron"])
    return Sprite(im, 2, 2)


def b_reactor():
    im, d = canvas_on(3, 3, 112)
    R(d, 4, 60, 91, 110, P["iron"])
    R(d, 4, 60, 91, 63, P["iron_l"])
    for x in range(8, 90, 8):
        R(d, x, 66, x + 3, 104, P["iron_d"])
    d.ellipse([14, 10, 82, 78], fill=P["slate"])
    d.ellipse([18, 12, 60, 50], fill=P["slate_l"])
    R(d, 14, 44, 82, 64, P["iron"])
    d.ellipse([36, 26, 60, 50], fill=P["lumen_d"])
    d.ellipse([39, 29, 57, 47], fill=P["lumen"])
    d.ellipse([43, 32, 51, 40], fill=P["lumen_l"])
    for x in (2, 86):
        R(d, x, 30, x + 8, 66, P["iron_d"])
        R(d, x + 2, 34, x + 6, 62, P["lumen"])
    R(d, 42, 96, 54, 110, P["door"])
    return Sprite(im, 3, 3, [(48, 38, 34, P["lumen"]), (6, 48, 10, P["lumen"]), (90, 48, 10, P["lumen"])])


def b_park():
    im, d = canvas_on(2, 2, 70)
    base = Image.new("RGBA", (64, 64), P["grass_l"])
    bd = ImageDraw.Draw(base)
    speckle(bd, random.Random(5), [P["grass"], hexc("e06a8a"), P["win"]], 90, 64, 64)
    R(bd, 28, 0, 35, 63, P["dirt_l"])
    R(bd, 0, 28, 63, 35, P["dirt_l"])
    im.paste(base, (0, 6))
    d.ellipse([22, 28, 41, 44], fill=P["stone_d"])
    d.ellipse([24, 30, 39, 41], fill=P["water_l"])
    d.line([(31, 26), (31, 34)], fill=P["foam"])
    for cx, cy in [(10, 16), (52, 16), (10, 52), (52, 52)]:
        tree(d, cx, cy, 1.2)
    return Sprite(im, 2, 2)


def b_skyheart():
    im, d = canvas_on(3, 3, 168)
    R(d, 6, 128, 89, 166, P["stone"])
    R(d, 6, 128, 89, 131, P["stone_l"])
    for x in (6, 78):
        d.polygon([(x, 166), (x + 6, 80), (x + 12, 166)], fill=P["stone_d"])
    d.polygon([(28, 128), (40, 56), (56, 56), (68, 128)], fill=P["iron"])
    d.polygon([(48, 56), (56, 56), (68, 128), (48, 128)], fill=P["iron_d"])
    for y in (72, 92, 112):
        w = 8 + (y - 56) // 5
        R(d, 48 - w, y, 48 + w, y + 2, P["brass"])
    R(d, 40, 146, 56, 166, P["door"])
    # floating heart crystal
    d.polygon([(48, 8), (62, 26), (48, 46), (34, 26)], fill=P["lumen"])
    d.polygon([(48, 8), (48, 46), (34, 26)], fill=P["lumen_l"])
    d.line([(48, 46), (48, 56)], fill=P["lumen"])
    for a, b in [((36, 50), (30, 44)), ((60, 50), (66, 44))]:
        d.line([a, b], fill=P["brass_l"], width=2)
    return Sprite(im, 3, 3, [(48, 27, 40, P["lumen"])])


# ---------------------------------------------------------------- citizens
def citizen(kind, facing, frame):
    """12x18 walker. kind: villager | farmer | engineer. facing: down|up|side."""
    im = Image.new("RGBA", (12, 18))
    d = ImageDraw.Draw(im)
    tunic = {"villager": hexc("4a7a9a"), "farmer": hexc("8a6a3a"), "engineer": hexc("3a3f48")}[kind]
    tunic_d = tuple(max(0, c - 30) for c in tunic[:3]) + (255,)
    step = frame % 2
    # legs
    if facing == "side":
        R(d, 4 + step, 13, 5 + step, 17, hexc("3a2a20"))
        R(d, 6 - step, 13, 7 - step, 17, hexc("2a1e18"))
    else:
        R(d, 3, 13, 4, 17 - step, hexc("3a2a20"))
        R(d, 7, 13, 8, 16 + step, hexc("3a2a20"))
    # body
    R(d, 2, 7, 9, 13, tunic)
    R(d, 2, 12, 9, 13, tunic_d)
    if facing != "side":
        R(d, 1, 8, 1, 11 + step, P["skin"])
        R(d, 10, 8, 10, 12 - step, P["skin"])
    else:
        R(d, 5 + step, 8, 6 + step, 11, P["skin_d"])
    # head
    R(d, 3, 1, 8, 6, P["skin"])
    R(d, 3, 1, 8, 2, P["hair"])
    if facing == "down":
        d.point([(4, 4), (7, 4)], fill=hexc("2a1e18"))
    elif facing == "up":
        R(d, 3, 1, 8, 5, P["hair"])
    else:
        R(d, 3, 1, 5, 5, P["hair"])
        d.point((7, 4), fill=hexc("2a1e18"))
    if kind == "farmer":
        R(d, 1, 0, 10, 1, P["thatch_l"])
        R(d, 3, 0, 8, 0, P["thatch"])
    if kind == "engineer":
        if facing == "down":
            R(d, 3, 3, 8, 4, P["lumen"])
        if facing in ("up", "side"):
            R(d, 3 if facing == "up" else 1, 7, 8 if facing == "up" else 3, 12, P["lumen_d"])
            R(d, 4 if facing == "up" else 1, 8, 7 if facing == "up" else 2, 10, P["lumen"])
    return outline(im)


# ---------------------------------------------------------------- sheet helpers
def upscale(im, s):
    return im.resize((im.width * s, im.height * s), Image.NEAREST)


def bg(w, h):
    return Image.new("RGBA", (w, h), hexc("1e1b18"))


def label(d, x, y, text, size=16, col=(230, 220, 200, 255), anchor="ma"):
    d.text((x, y), text, font=font(size), fill=col, anchor=anchor)


def sheet_tiles():
    tiles = [
        ("Grass", t_grass(1)), ("Fertile soil", t_soil(2)), ("Forest", t_forest(3)),
        ("Rock", t_rock(4)), ("Water", t_water(5)), ("Lumen vein", t_vein(6)),
        ("Blighted grass", t_blight(t_grass(1))), ("Dirt road", t_dirt_road(8)), ("Paved road", t_paved(9)),
    ]
    s, cell = 4, 128 + 40
    img = bg(cell * 5 + 40, cell * 2 + 110)
    d = ImageDraw.Draw(img)
    label(d, img.width // 2, 18, "Hearthvein - terrain tiles (32x32, shown 4x)", 22)
    for i, (name, t) in enumerate(tiles):
        x, y = 30 + (i % 5) * cell, 70 + (i // 5) * (cell + 10)
        img.paste(upscale(t, s), (x, y))
        label(d, x + 64, y + 134, name, 15)
    return img


def sheet_buildings():
    eras = [
        ("Camp", [("Hearth", b_hearth()), ("Tent", b_tent()), ("Woodcutter", b_woodcutter()),
                  ("Lumen Tap", b_lumen_tap()), ("Meeting Hall*", b_meeting_hall())]),
        ("Village", [("Cottage", b_cottage()), ("Farm", b_farm()), ("Market", b_market()),
                     ("Shrine", b_shrine()), ("Bell Tower*", b_bell_tower())]),
        ("Town", [("Rowhouse", b_rowhouse()), ("Greenhouse", b_greenhouse()), ("Lumen Pump", b_lumen_pump()),
                  ("Cleanser", b_cleanser()), ("Lumen Spire*", b_lumen_spire())]),
        ("City", [("Apartment Block", b_apartment()), ("Lumen Reactor", b_reactor()), ("Park", b_park()),
                  ("Skyheart*", b_skyheart())]),
    ]
    s = 3
    row_h = [max(sp.img.height for _, sp in row) * s + 60 for _, row in eras]
    W = 1500
    img = bg(W, sum(row_h) + 110)
    d = ImageDraw.Draw(img)
    label(d, W // 2, 18, "Hearthvein - buildings by era (shown 3x, * = era landmark)", 22)
    y = 70
    for (era, row), rh in zip(eras, row_h):
        label(d, 20, y + rh // 2 - 20, era, 22, hexc("f2d27a"), anchor="la")
        x = 160
        base = y + rh - 50
        for name, sp in row:
            g = glow_layer(sp.img.size, sp.glows)
            spr = sp.img.copy()
            spr.alpha_composite(g)
            big = upscale(spr, s)
            # ground footprint
            fw = sp.fw * T * s
            d.rectangle([x, base - sp.fh * T * s // 3, x + fw, base], fill=hexc("2c2824"))
            img.alpha_composite(big, (x, base - big.height))
            label(d, x + big.width // 2, base + 8, name, 15)
            x += big.width + 40
        y += rh
    return img


def sheet_citizens():
    kinds = ["villager", "farmer", "engineer"]
    frames = [(f, k) for f in ("down", "up", "side") for k in (0, 1)]
    s = 7
    cw = 14 * s + 20
    img = bg(200 + cw * len(frames), 90 + len(kinds) * (20 * s + 30))
    d = ImageDraw.Draw(img)
    label(d, img.width // 2, 18, "Hearthvein - citizens (12x18, shown 7x): down / up / side, 2 walk frames", 22)
    for r, kind in enumerate(kinds):
        y = 70 + r * (20 * s + 30)
        label(d, 20, y + 60, kind.capitalize(), 20, hexc("f2d27a"), anchor="la")
        for c, (facing, fr) in enumerate(frames):
            img.alpha_composite(upscale(citizen(kind, facing, fr), s), (200 + c * cw, y))
    return img


# ---------------------------------------------------------------- scene
MAP_W, MAP_H = 26, 16
SCENE_SEED = 11


def build_map():
    rng = random.Random(SCENE_SEED)
    m = [["grass"] * MAP_W for _ in range(MAP_H)]
    # river: gently wobbling 2-wide column on the right, fed by a lake top-right
    wobble = [1, 1, 1, 0, 0, 0, 0, 0, 0, 1, 1, 1, 0, 0, 1, 1]
    for y in range(MAP_H):
        for dx in range(2):
            m[y][18 + wobble[y] + dx] = "water"
    for y in range(0, 3):
        for x in range(20, 26):
            if not (y == 2 and x < 22):
                m[y][x] = "water"
    # forest top-left, rock bottom-left
    for y in range(0, 6):
        for x in range(0, 7 - y // 2):
            if rng.random() < 0.85:
                m[y][x] = "forest"
    for y in range(11, 16):
        for x in range(0, 4):
            if rng.random() < 0.7:
                m[y][x] = "rock"
    # fertile soil near river
    for y in range(8, 14):
        for x in range(14, 19):
            if m[y][x] == "grass":
                m[y][x] = "soil"
    # Lumen vein + blight bottom-middle
    for x, y in [(7, 13), (8, 13), (8, 14)]:
        m[y][x] = "vein"
    return m


def render_scene(dimming=False):
    m = build_map()
    W, H = MAP_W * T, MAP_H * T
    ground = Image.new("RGBA", (W, H))
    blight = {(x, y) for x in range(5, 12) for y in range(11, 16)
              if abs(x - 8) + abs(y - 13.5) < 4 and m[y][x] in ("grass", "soil")}
    roads_h = {(x, 7) for x in range(2, MAP_W)}
    roads_v = {(10, y) for y in range(2, 14)}
    roads = roads_h | roads_v

    def conn(x, y):
        return tuple(int(p in roads) for p in [(x, y - 1), (x + 1, y), (x, y + 1), (x - 1, y)])

    gen = {"grass": t_grass, "soil": t_soil, "forest": t_forest, "rock": t_rock, "water": t_water, "vein": t_vein}
    for y in range(MAP_H):
        for x in range(MAP_W):
            seed = x * 97 + y * 13
            if (x, y) in roads and m[y][x] == "water":
                t = t_water(seed)
                d = ImageDraw.Draw(t)
                R(d, 0, 8, T - 1, 23, P["wood"])
                for bx in range(0, T, 4):
                    d.line([(bx, 8), (bx, 23)], fill=P["wood_d"])
                R(d, 0, 7, T - 1, 7, P["wood_d"])
                R(d, 0, 24, T - 1, 25, P["water_d"])
            elif (x, y) in roads:
                t = t_dirt_road(seed, conn(x, y))
            else:
                kind = m[y][x]
                t = gen[kind](seed) if kind != "forest" else t_grass(seed)
                if kind == "water" and y > 0 and m[y - 1][x] != "water":
                    ImageDraw.Draw(t).line([(0, 0), (T - 1, 0)], fill=P["foam"])
                if (x, y) in blight:
                    t = t_blight(t)
            ground.paste(t, (x * T, y * T))
    scene = ground
    glow = Image.new("RGBA", (W, H))

    # depth-sorted objects: (base_y, kind, payload)
    objs = []
    for y in range(MAP_H):
        for x in range(MAP_W):
            if m[y][x] == "forest":
                objs.append((y * T + 30, "forest", (x, y)))
    placements = [
        (b_hearth(), 9, 8), (b_tent(), 6, 5), (b_tent(), 7, 5), (b_tent(), 4, 8),
        (b_cottage(), 11, 5), (b_cottage(), 12, 5), (b_cottage(), 13, 6), (b_cottage(), 11, 9),
        (b_cottage(), 12, 9), (b_woodcutter(), 7, 3), (b_woodcutter(), 3, 6),
        (b_farm(), 15, 9), (b_farm(), 15, 11), (b_market(), 13, 10),
        (b_lumen_tap(), 9, 13), (b_shrine(), 14, 8), (b_bell_tower(), 8, 10),
    ]
    for sp, tx, ty in placements:
        objs.append(((ty + sp.fh) * T, "sprite", (sp, tx, ty)))
    rng = random.Random(4)
    walkers = [("villager", "side", 3, 7, 12), ("farmer", "down", 10, 4, 18), ("engineer", "up", 10, 11, 4),
               ("villager", "down", 10, 9, 22), ("farmer", "side", 15, 7, 8), ("villager", "side", 6, 7, 20),
               ("engineer", "side", 22, 7, 6)]
    for kind, facing, tx, ty, ox in walkers:
        objs.append((ty * T + 26, "walker", (kind, facing, tx, ty, ox)))
    objs.sort(key=lambda o: o[0])

    for _, kind, pl in objs:
        if kind == "forest":
            x, y = pl
            t = Image.new("RGBA", (T, T + 8))
            d = ImageDraw.Draw(t)
            rr = random.Random(x * 31 + y)
            for cx, cy in [(9, 15), (23, 17), (15, 27), (4, 30), (27, 31)]:
                tree(d, cx + rr.randint(-1, 1), cy + rr.randint(-1, 1), rr.choice([0.9, 1.0, 1.15]))
            scene.alpha_composite(outline(t), (x * T - 1, y * T - 9))
        elif kind == "sprite":
            sp, tx, ty = pl
            px, py = tx * T - 1, (ty + sp.fh) * T - sp.img.height + 1
            sh = Image.new("RGBA", (sp.fw * T, 8))
            ImageDraw.Draw(sh).ellipse([0, 0, sp.fw * T - 1, 7], fill=(0, 0, 0, 60))
            scene.alpha_composite(sh, (tx * T, (ty + sp.fh) * T - 5))
            scene.alpha_composite(sp.img, (px, max(py, 0)) if py >= 0 else (px, 0),
                                  (0, 0) if py >= 0 else (0, -py))
            for gx, gy, r, c in sp.glows:
                gl = glow_layer((2 * r + 2, 2 * r + 2), [(r + 1, r + 1, r, c)])
                glow.alpha_composite(gl, (max(0, px + gx - r - 1), max(0, py + gy - r - 1)))
        else:
            kind_, facing, tx, ty, ox = pl
            c = citizen(kind_, facing, rng.randrange(2))
            scene.alpha_composite(c, (tx * T + ox - 7, ty * T + 8))

    if dimming:
        dark = Image.new("RGBA", (W, H), (20, 30, 70, 150))
        scene.alpha_composite(dark)
        g2 = glow.copy()
        g2.putalpha(g2.getchannel("A").point(lambda a: a // 3))
        scene.alpha_composite(g2)
    else:
        scene.alpha_composite(glow)
    return scene


def icon(kind):
    im = Image.new("RGBA", (12, 12))
    d = ImageDraw.Draw(im)
    if kind == "food":
        d.ellipse([1, 3, 10, 11], fill=hexc("c84a3a"))
        d.ellipse([3, 4, 5, 6], fill=hexc("f08a7a"))
        d.line([(6, 3), (7, 0)], fill=P["wood_d"])
        d.point((8, 1), fill=P["grass_l"])
    elif kind == "wood":  # placeholder: a log with a cut end (the real icon set is 1.1.6)
        R(d, 0, 4, 11, 9, P["wood"])
        d.ellipse([8, 4, 11, 9], fill=P["dirt_l"])
    elif kind == "stone":  # placeholder: two grey blocks
        R(d, 1, 5, 6, 10, P["stone"])
        R(d, 5, 2, 10, 7, P["stone"])
        R(d, 2, 6, 3, 7, P["stone_l"])
    elif kind == "lumen":
        crystal(d, 3, 11, 10, 6)
    elif kind == "gold":
        d.ellipse([1, 1, 10, 10], fill=P["brass"])
        d.ellipse([3, 3, 8, 8], fill=P["brass_l"])
    elif kind == "pop":
        R(d, 4, 1, 7, 4, P["skin"])
        R(d, 2, 5, 9, 11, hexc("4a7a9a"))
    elif kind == "spirit":
        d.polygon([(6, 11), (1, 5), (3, 1), (6, 3), (9, 1), (11, 5)], fill=hexc("e06a8a"))
    elif kind == "moon":
        d.ellipse([1, 1, 10, 10], fill=hexc("c8d0f0"))
        d.ellipse([4, 0, 12, 8], fill=(0, 0, 0, 0))
    return outline(im)


# 1.1.6 icon set (ticket 106): hand-placed 12x12 maps, one char per pixel, "." is clear. export_icons() still uses
# icon() until the set is approved and wired (ticket 112).
ICON_V2_KINDS = ["wood", "stone", "planks", "cut_stone", "tools", "food", "lumen", "gold", "people", "cells"]
_BR_D = hexc("8a6a20")
_ICON_KEY = {
    "L": P["wood_l"], "W": P["wood"], "D": P["wood_d"], "r": P["dirt_l"], "c": P["dirt"], "o": P["dirt_d"],
    "g": P["stone_l"], "s": P["stone"], "d": P["stone_d"],
    "t": P["thatch_l"], "u": P["thatch"], "v": P["thatch_d"],
    "m": P["pave_l"], "n": P["pave"], "k": P["pave_d"],
    "i": P["iron_l"], "j": P["iron"], "h": P["iron_d"],
    "R": hexc("c84a3a"), "H": hexc("f08a7a"), "E": hexc("8a2c26"), "G": P["grass_l"], "T": P["grass_d"],
    "C": P["lumen"], "A": P["lumen_l"], "B": P["lumen_d"],
    "Y": P["brass"], "X": P["brass_l"], "Z": _BR_D,
    "S": P["skin"], "F": P["skin_d"], "N": hexc("4a7a9a"), "M": hexc("356080"), "Q": P["hair"], "P": hexc("c0702e"),
}
_ICON_V2 = {
    "wood": [  # a log with growth rings on the cut end, two bark ticks
        "............",
        "............",
        "..LLLLLLoor.",
        ".LWWWWWWcrco",
        ".LWDWWWWcrco",
        ".WWWWWDWcooc",
        ".WWWWWWWcrco",
        ".WDWWWWWcrco",
        ".DWWWWDWoccr",
        ".DDDDDDDDooo",
        "............",
        "............",
    ],
    "charcoal": [  # a heap of three black lumps with grey highlights (ticket 133)
        "............",
        "............",
        ".....hhh....",
        "....hjjjh...",
        "..hhhjjjih..",
        ".hjjjhhhjih.",
        ".hjjjjhhjih.",
        "hhjjjihhjhih",
        "hjjjihhjjiih",
        "hjjhhhjjjih.",
        ".hhhh.hhhhh.",
        "............",
    ],
    "stone": [  # a rough grey block with chipped corners
        "............",
        "....gggg....",
        "..ggssssg...",
        ".gssssssssd.",
        ".gsssdssssd.",
        "gssssssdsssd",
        "gsssssssssdd",
        "gssdsssssdsd",
        ".sssssssssdd",
        ".ssssdsssddd",
        "..dddddddd..",
        "............",
    ],
    "planks": [  # four stacked boards, end grain on the left
        "............",
        ".rLLLLLLLLL.",
        ".cWWWWWWWWW.",
        ".oDDDDDDDDD.",
        "..rLLLLLLLLL",
        "..cWWWWWWWWW",
        "..oDDDDDDDDD",
        ".rLLLLLLLLL.",
        ".cWWWWWWWWW.",
        ".oDDDDDDDDD.",
        "............",
        "............",
    ],
    "cut_stone": [  # a dressed block: bevelled face, mortar courses of bricks
        "............",
        ".mmmmmmmmmm.",
        ".mnnknnnnnk.",
        ".mnnknnnnnk.",
        ".kkkkkkkkkk.",
        ".mnnnnknnnk.",
        ".mnnnnknnnk.",
        ".kkkkkkkkkk.",
        ".mnnknnnnnk.",
        ".mnnknnnnnk.",
        ".kkkkkkkkkk.",
        "............",
    ],
    "tools": None,  # built below from point sets
    "food": [  # an apple with a stem and a leaf
        "......D.GG..",
        "......DGGG..",
        "..RRR.DRRR..",
        ".RHHRRRRRRR.",
        ".RHRRRRRRRE.",
        "RRRRRRRRRRRE",
        "RRRRRRRRRRRE",
        "RRRRRRRRRRER",
        ".RRRRRRRRRE.",
        ".RRRRRRRREE.",
        "..ERRRRREE..",
        "............",
    ],
    "lumen": [  # a cluster of cyan crystals, one tall
        ".....AA.....",
        "....ACCB....",
        "....ACCB..A.",
        "..A.ACCB.ACB",
        ".ACBACCBBACB",
        ".ACBACCCBCCB",
        ".ACCCCCCCCCB",
        ".CCCCCCCCCCB",
        ".BCCCCCCCCBB",
        "..BBCCCCCBB.",
        "...BBBBBBB..",
        "............",
    ],
    "gold": [  # one round coin: pale rim, a glint on the left, dark shading along the lower right (a single coin, D22)
        "............",
        "....XXXX....",
        "..XXYYYYXX..",
        ".XYYtYYYYYX.",
        ".XYYtYYYYYX.",
        "XYYYYYYYYYYX",
        "XYYYYYYYYYYX",
        "XYYYYYYYZZZX",
        ".XYYYYYZZZX.",
        ".XYYYYYZZYX.",
        "..XXYYYYXX..",
        "....XXXX....",
    ],
    "people": [  # two citizens, the nearer one in front
        "............",
        "..QQQQ......",
        "..QSSQ......",
        "..SSSS..QQQQ",
        "..FSSF..QSSQ",
        ".MNNNNM.SSSS",
        "MNNNNNNMFSSF",
        "MNNNNNNMPPPP",
        "MNNNNNNMPPPP",
        "MNNNNNNMPPPM",
        "MMMMMMMMMMMM",
        "............",
    ],
    "cells": [  # a lumen cell: brass capped glass cylinder with a bright core
        "............",
        "....hhhh....",
        "...YXXXXY...",
        "...ZZZZZZ...",
        "..BAACCCCB..",
        "..BACCCCCB..",
        "..BACCCCCB..",
        "..BACCCCCB..",
        "..BCCCCCBB..",
        "...ZZZZZZ...",
        "...YYYYYY...",
        "............",
    ],
}


def _tools_rows():
    """Hammer (handle x+y=11, block head top right) crossed with a pick (handle x=y, head band x+y in 4..5)."""
    g = [["."] * 12 for _ in range(12)]
    for x in range(12):
        for y in range(12):
            if x + y == 11 and 2 <= x <= 8 or x == y and 3 <= x <= 10:
                g[y][x] = "W"
            if 7 <= x <= 11 and 0 <= y <= 3:
                g[y][x] = "i" if y == 0 else "j"
            if x + y in (4, 5) and x <= 5 and y <= 5:
                g[y][x] = "i" if x + y == 4 else "j"
    g[10][1] = g[9][1] = "W"
    return ["".join(r) for r in g]


_ICON_V2["tools"] = _tools_rows()


def icon_v2(kind):
    """The 1.1.6 pixel icon for a good (12x12 art, 14x14 with the 1 px dark outline, like icon())."""
    rows = _ICON_V2[kind]
    assert len(rows) == 12 and all(len(r) == 12 for r in rows), kind
    im = Image.new("RGBA", (12, 12))
    px = im.load()
    for y, row in enumerate(rows):
        for x, ch in enumerate(row):
            if ch != ".":
                px[x, y] = _ICON_KEY[ch]
    return outline(im)


def hud(img, s, dimming=False):
    d = ImageDraw.Draw(img, "RGBA")
    W, H = img.size
    d.rectangle([0, 0, W, 52], fill=(24, 20, 18, 225))
    f = font(20)
    x = 16
    vals = [("food", "142  +6"), ("wood", "88  +4"), ("lumen", "36  +9" if not dimming else "36  -3"),
            ("gold", "51  +2"), ("pop", "23 / 28")]
    for k, v in vals:
        img.alpha_composite(upscale(icon(k), 3), (x, 6))
        d.text((x + 44, 26), v, font=f, fill=(236, 226, 206), anchor="lm")
        x += 190
    img.alpha_composite(upscale(icon("spirit"), 3), (x, 6))
    d.rectangle([x + 44, 18, x + 204, 34], fill=(60, 50, 50))
    d.rectangle([x + 44, 18, x + 44 + (118 if not dimming else 70), 34],
                fill=(120, 190, 90) if not dimming else (210, 160, 60))
    d.text((x + 214, 26), "Spirit", font=font(16), fill=(236, 226, 206), anchor="lm")
    # era + forecast panel
    pw = 360
    px = W - pw - 14
    d.rounded_rectangle([px, 64, W - 14, 150], 8, fill=(24, 20, 18, 225),
                        outline=(127, 224, 240) if dimming else (90, 80, 70), width=2)
    d.text((px + 14, 74), "Era: Village", font=font(18), fill=(242, 210, 122))
    img.alpha_composite(upscale(icon("moon"), 2), (px + 14, 106))
    txt = "Dimming in 2 days - lasts 3" if not dimming else "DIMMING - day 1 of 3"
    d.text((px + 46, 106), txt, font=font(18), fill=(200, 210, 240))
    d.text((px + 14, 130), "Year 3, Summer", font=font(14), fill=(170, 160, 150))
    # tooltip over the Lumen Tap
    tx, ty = 9 * T * s + 70, 12 * T * s - 30
    d.rounded_rectangle([tx, ty, tx + 300, ty + 92], 8, fill=(24, 20, 18, 235), outline=(90, 80, 70), width=2)
    d.text((tx + 12, ty + 8), "Lumen Tap", font=font(18), fill=(127, 224, 240))
    d.text((tx + 12, ty + 36), "Workers 2/2   Lumen " + ("+3/day (Dimming)" if dimming else "+9/day"), font=font(15), fill=(236, 226, 206))
    d.text((tx + 12, ty + 60), "Blight spreading: 6 tiles", font=font(15), fill=(180, 150, 210))
    # build bar
    cats = ["Roads", "Housing", "Food", "Materials", "Lumen", "Civic", "Landmark"]
    bw = 150
    bx = (W - len(cats) * (bw + 8)) // 2
    d.rectangle([0, H - 64, W, H], fill=(24, 20, 18, 225))
    for i, c in enumerate(cats):
        x0 = bx + i * (bw + 8)
        sel = c == "Housing"
        d.rounded_rectangle([x0, H - 54, x0 + bw, H - 12], 6,
                            fill=(70, 60, 50) if sel else (44, 38, 34), outline=(242, 210, 122) if sel else None)
        d.text((x0 + bw // 2, H - 33), c, font=font(17), fill=(236, 226, 206), anchor="mm")


def scene_png(dimming):
    s = 2
    img = upscale(render_scene(dimming), s)
    hud(img, s, dimming)
    return img


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    sheet_tiles().save(OUT / "tiles.png")
    sheet_buildings().save(OUT / "buildings.png")
    sheet_citizens().save(OUT / "citizens.png")
    scene_png(False).save(OUT / "scene_village.png")
    scene_png(True).save(OUT / "scene_dimming.png")
    print("wrote", *sorted(p.name for p in OUT.glob("*.png")))


if __name__ == "__main__":
    main()
