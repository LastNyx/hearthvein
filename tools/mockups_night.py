"""Hearthvein night shift mockups (spec: .scratch/v1/night-shift-spec.md): five pictures for Ben to approve.

Usage: python3 tools/mockups_night.py [out_dir]     (default: .scratch/v1/mockups/night)
Writes night_map.png, lamp_tiers.png, new_buildings.png, build_cards.png, workforce_shift.png, gain_popup.png.
Mockup art only: real sprites, tiles and walkers from assets/, drawn pictures for the new things (lamps, Charcoal Kiln,
Glowcap Grove, two goods icons). Numbers that are not in the spec (costs, stock, worker counts) are made up.
"""
import json
import math
import random
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

sys.path.insert(0, str(Path(__file__).resolve().parent))
import mockups_ui as U  # noqa: E402  (panel look, top bar, page frame, cost icons: the approved 1.1.6 mockups)

M = U.M
ROOT = Path(__file__).resolve().parent.parent
ASSETS = ROOT / "assets"
OUT_DEFAULT = ROOT / ".scratch" / "v1" / "mockups" / "night"
MAN = json.loads((ASSETS / "art_manifest.json").read_text())
T = 32
NIGHT = np.array([0.50, 0.55, 0.78])  # data/daynight/day_night.tres night_color, multiplied over the map

GOLD, TEXT, DIM, FAINT, GREEN, RED, BORDER = U.GOLD, U.TEXT, U.DIM, U.FAINT, U.GREEN, U.RED, U.BORDER
MOON_BLUE = (150, 170, 235)
AMBER = (232, 176, 84)
c = M.hexc


# ---------------------------------------------------------------- asset loading
_cache = {}


def load(rel):
    if rel not in _cache:
        _cache[rel] = Image.open(ASSETS / rel).convert("RGBA")
    return _cache[rel]


def pick(items, x, y, salt=0):
    return items[((x * 73856093) ^ (y * 19349663) ^ (salt * 83492791)) % len(items)]


def tile_img(sheet, idx):
    return load(sheet).crop((idx * T, 0, idx * T + T, T))


def to_arr(im):
    return np.asarray(im.convert("RGB"), dtype=np.float32) / 255.0


def to_img(a):
    return Image.fromarray((np.clip(a, 0, 1) * 255 + 0.5).astype(np.uint8), "RGB").convert("RGBA")


# ---------------------------------------------------------------- new icons (12x12, same key and outline as icon_v2)
_NEW_KEY = {
    "a": c("26242a"), "b": c("3e3c44"), "e": c("5e5c68"), "f": c("f08a2a"), "y": c("ffd060"),
    "p": c("3cbfa0"), "q": c("1f7470"), "w": c("b4ffe0"), "x": c("dde6d0"), "z": c("98aa96"),
}
M._ICON_KEY.update(_NEW_KEY)
M._ICON_V2["charcoal"] = [  # three black lumps stacked, ember glints in the cracks
    "............",
    "............",
    "....eeb.....",
    "...eabbb....",
    "...abfabb...",
    ".eeb.aabb...",
    "eabbbaabbe..",
    "abfaabbbbbb.",
    "abbaabfabbb.",
    "aabbbaaabbb.",
    ".aaaaaaaaaa.",
    "............",
]
M._ICON_V2["glowcap"] = [  # a big teal cap with pale spots and a small one beside it
    "............",
    ".....wwww...",
    "....wppwpq..",
    "...wpppppqq.",
    "...ppwppppq.",
    "...qqqqqqqq.",
    "......xz....",
    "..ww..xz....",
    ".wppq.xz....",
    ".qqqq.xz....",
    "....xxzz....",
    "............",
]
U.NAMES.update({"charcoal": "Charcoal", "glowcap": "Glowcap"})
U.STOCK.update({"charcoal": 18, "glowcap": 12})
U.DELTA.update({"charcoal": 3, "glowcap": 2})
U.GOODS = ["food", "wood", "stone", "planks", "cut_stone", "tools", "charcoal", "lumen", "cells", "gold"]


# ---------------------------------------------------------------- pixel art helper for the drawn sprites
class Art:
    """A small sprite canvas: `img` is the sprite, `em` holds the emissive pixels only (drawn untinted at night)."""

    def __init__(self, w, h):
        self.img = Image.new("RGBA", (w, h))
        self.em = Image.new("RGBA", (w, h))
        self.d = ImageDraw.Draw(self.img)
        self.de = ImageDraw.Draw(self.em)

    def px(self, x, y, col, em=False):
        if 0 <= x < self.img.width and 0 <= y < self.img.height:
            self.d.point((x, y), fill=col)
            if em:
                self.de.point((x, y), fill=col)

    def rect(self, x0, y0, x1, y1, col, em=False):
        self.d.rectangle([x0, y0, x1, y1], fill=col)
        if em:
            self.de.rectangle([x0, y0, x1, y1], fill=col)

    def line(self, pts, col, em=False):
        self.d.line(pts, fill=col)
        if em:
            self.de.line(pts, fill=col)

    def ellipse(self, box, col, em=False):
        self.d.ellipse(box, fill=col)
        if em:
            self.de.ellipse(box, fill=col)

    def finish(self):
        """Crops to the content, adds the 1 px dark outline; returns (sprite, emissive, base) with base = bottom centre."""
        box = self.img.getbbox()
        im, em = self.img.crop(box), self.em.crop(box)
        w, h = im.size
        out = M.outline(im)
        em2 = Image.new("RGBA", out.size)
        em2.paste(em, (1, 1))
        return out, em2, (out.width // 2, out.height - 2)


# ---------------------------------------------------------------- lamp sprites (1x1, lit = night look)
LAMP_LIGHT = {  # light colour multiplied over the ground in the pool
    "brazier": (1.0, 0.70, 0.40), "lantern": (1.0, 0.82, 0.52), "lumen": (0.55, 0.95, 1.0), "grid": (0.86, 0.96, 1.0),
}
LAMP_HALO = {"brazier": (255, 150, 60), "lantern": (255, 190, 90), "lumen": (127, 224, 240), "grid": (205, 240, 255)}


def lamp_art(kind, lit=True):
    a = Art(20, 40)
    P = M.P
    iron, iron_l, iron_d = P["iron"], P["iron_l"], P["iron_d"]
    if kind == "brazier":
        for (x0, y0, x1, y1) in ((6, 27, 4, 37), (13, 27, 15, 37), (10, 28, 10, 37)):
            a.line([(x0, y0), (x1, y1)], iron_d)
        a.rect(3, 36, 5, 37, iron_d)
        a.rect(14, 36, 16, 37, iron_d)
        a.rect(2, 21, 17, 22, iron_l)  # rim
        for i, y in enumerate(range(23, 28)):
            a.rect(3 + i, y, 16 - i, y, iron if i < 3 else iron_d)
        a.px(4, 23, iron_l)
        a.px(5, 24, iron_l)
        # logs
        logs = P["wood"] if lit else c("2a2420")
        a.rect(4, 18, 15, 20, logs)
        a.line([(5, 17), (14, 20)], P["wood_d"] if lit else c("1c1814"))
        a.line([(14, 17), (5, 20)], P["wood_l"] if lit else c("3a322c"))
        if lit:
            a.d.polygon([(10, 4), (14, 11), (15, 16), (12, 19), (7, 19), (5, 15), (7, 10), (8, 8)], fill=c("e8651c"))
            a.de.polygon([(10, 4), (14, 11), (15, 16), (12, 19), (7, 19), (5, 15), (7, 10), (8, 8)], fill=c("e8651c"))
            a.d.polygon([(10, 8), (13, 13), (13, 17), (11, 19), (8, 19), (7, 15), (9, 12)], fill=c("ffae3c"))
            a.de.polygon([(10, 8), (13, 13), (13, 17), (11, 19), (8, 19), (7, 15), (9, 12)], fill=c("ffae3c"))
            a.rect(9, 13, 11, 18, c("ffe58a"), True)
            a.px(10, 10, c("ffcf5c"), True)
    elif kind == "lantern":
        a.rect(5, 36, 14, 37, P["stone_d"])
        a.rect(6, 34, 13, 35, P["stone"])
        a.rect(6, 34, 13, 34, P["stone_l"])
        a.rect(9, 14, 10, 34, P["wood"])
        a.rect(10, 14, 10, 34, P["wood_d"])
        a.rect(9, 14, 9, 34, P["wood_l"])
        a.rect(6, 13, 13, 14, P["wood_d"])  # bracket
        a.rect(4, 12, 15, 12, iron)  # lantern floor
        glass = (c("ffc65a"), c("ffe9a0"), c("f08a2a")) if lit else (c("54504c"), c("6a665f"), c("46423e"))
        a.rect(5, 5, 14, 11, glass[0], lit)
        a.rect(7, 6, 12, 10, glass[1], lit)
        a.rect(8, 8, 11, 10, glass[2], lit)
        if lit:
            a.rect(8, 7, 11, 8, c("fff3c0"), True)
        for x in (4, 9, 10, 15):  # cage bars
            a.rect(x, 5, x, 11, iron_d)
        a.rect(4, 4, 15, 4, iron_d)
        a.rect(6, 3, 13, 3, iron)
        a.rect(8, 2, 11, 2, iron_l)
        a.rect(9, 1, 10, 1, iron_d)
    elif kind == "lumen":
        a.rect(5, 36, 14, 37, P["stone_d"])
        a.rect(6, 34, 13, 35, P["stone"])
        a.rect(6, 34, 13, 34, P["stone_l"])
        a.rect(8, 19, 11, 33, P["stone"])
        a.rect(8, 19, 8, 33, P["stone_l"])
        a.rect(11, 19, 11, 33, P["stone_d"])
        for y in (31, 23):
            a.rect(7, y, 12, y + 1, P["brass"])
            a.rect(7, y, 12, y, P["brass_l"])
        a.rect(6, 18, 13, 19, P["brass"])  # cradle
        a.rect(6, 18, 13, 18, P["brass_l"])
        for x in (5, 14):
            a.rect(x, 14, x, 18, P["brass"])
        cr = (P["lumen"], P["lumen_l"], P["lumen_d"]) if lit else (c("5a8a94"), c("86b0b8"), c("3e646c"))
        a.d.polygon([(9, 3), (13, 8), (13, 16), (10, 17), (6, 16), (6, 8)], fill=cr[0])
        a.d.polygon([(9, 3), (6, 8), (6, 16), (8, 16), (8, 7)], fill=cr[1])
        a.d.polygon([(11, 6), (13, 8), (13, 16), (10, 17), (11, 14)], fill=cr[2])
        if lit:
            a.de.polygon([(9, 3), (13, 8), (13, 16), (10, 17), (6, 16), (6, 8)], fill=cr[0])
            a.de.polygon([(9, 3), (6, 8), (6, 16), (8, 16), (8, 7)], fill=cr[1])
            a.de.polygon([(11, 6), (13, 8), (13, 16), (10, 17), (11, 14)], fill=cr[2])
            a.rect(8, 7, 9, 10, c("effeff"), True)
            for (x, y) in ((3, 8), (16, 5), (15, 12)):
                a.px(x, y, P["lumen_l"], True)
    elif kind == "grid":
        a.rect(6, 31, 13, 37, P["slate"])  # cabinet
        a.rect(6, 31, 13, 31, P["slate_l"])
        a.rect(12, 32, 13, 37, P["slate_d"])
        a.rect(6, 37, 13, 37, P["slate_d"])
        a.rect(7, 33, 8, 34, iron_d)
        a.px(8, 33, c("7fe0f0") if lit else c("3a5a62"), lit)  # status light
        a.rect(9, 12, 10, 30, iron_l)  # pole
        a.rect(10, 12, 10, 30, iron)
        a.rect(8, 22, 11, 25, P["slate"])  # junction box
        a.rect(8, 22, 11, 22, P["slate_l"])
        a.px(10, 24, c("7fe0f0") if lit else c("3a5a62"), lit)
        if lit:
            a.line([(9, 26), (9, 30)], c("7fe0f0"), True)  # live conduit stripe
        a.rect(3, 9, 16, 10, iron_l)  # arm
        a.rect(3, 10, 16, 10, iron)
        a.rect(2, 8, 3, 11, iron_d)
        a.rect(16, 8, 17, 11, iron_d)
        lens = (c("d8f6ff"), c("ffffff")) if lit else (c("52606c"), c("66767f"))
        a.rect(4, 11, 15, 13, lens[0], lit)
        a.rect(6, 12, 13, 12, lens[1], lit)
        a.rect(5, 6, 14, 8, iron_d)
        a.rect(7, 5, 12, 5, iron)
    return a.finish()


# ---------------------------------------------------------------- Charcoal Kiln and Glowcap Grove (2x2)
def lerp_c(a, b, t):
    return tuple(round(x + (y - x) * t) for x, y in zip(a[:3], b[:3])) + (255,)


def kiln_art(lit=True):
    a = Art(72, 68)
    P = M.P
    rng = random.Random(5)
    # packed earth pad
    a.d.ellipse([2, 44, 70, 66], fill=P["dirt_d"])
    a.d.ellipse([4, 44, 68, 63], fill=P["dirt"])
    for _ in range(90):
        x, y = rng.randrange(6, 66), rng.randrange(47, 62)
        if ((x - 36) / 31) ** 2 + ((y - 54) / 9.5) ** 2 < 1:
            a.px(x, y, rng.choice([P["dirt_l"], P["dirt_d"], c("5a4a36")]))
    # chimney / vent behind the dome
    a.rect(30, 13, 38, 28, P["stone"])
    a.rect(30, 13, 31, 28, P["stone_l"])
    a.rect(37, 13, 38, 28, P["stone_d"])
    for y in range(16, 28, 4):
        a.rect(30, y, 38, y, P["stone_d"])
    a.rect(28, 11, 40, 13, P["iron_d"])
    a.rect(28, 11, 40, 11, P["iron"])
    # brick dome
    cx, base, rx, ry = 34, 53, 24, 29
    for y in range(base - ry, base + 1):
        k = (base - y) / ry
        hw = int(rx * math.sqrt(max(0.0, 1 - k * k)) + 0.5)
        for x in range(cx - hw, cx + hw + 1):
            u = (x - cx) / max(hw, 1)
            col = P["redroof_l"] if u < -0.45 else (P["brick"] if u < 0.25 else P["brick_d"])
            soot = max(0.0, (k - 0.55) / 0.45) * 0.8
            col = lerp_c(col, c("3a3436"), soot)
            if y % 5 == 0:
                col = lerp_c(col, c("22181a"), 0.45)
            elif (x + (y // 5) * 4) % 8 == 0:
                col = lerp_c(col, c("22181a"), 0.3)
            a.px(x, y, col)
    # arched mouth with the fire
    for y in range(42, 54):
        hw = 6 if y > 44 else (5 if y == 44 else 3 if y == 42 else 4)
        a.rect(cx - hw - 1, y, cx + hw + 1, y, c("2a1e1c"))
    for y in range(43, 54):
        hw = 6 if y > 44 else (4 if y == 44 else 3 if y == 43 else 4)
        a.rect(cx - hw, y, cx + hw, y, c("120c0c"))
    if lit:
        a.rect(cx - 5, 49, cx + 5, 53, c("e8651c"), True)
        a.rect(cx - 4, 47, cx + 4, 51, c("ff9a30"), True)
        a.rect(cx - 2, 45, cx + 2, 50, c("ffd060"), True)
        a.rect(cx - 1, 47, cx + 1, 50, c("fff0b0"), True)
        a.rect(cx - 5, 53, cx + 5, 53, c("c04810"), True)
    else:
        a.rect(cx - 5, 50, cx + 5, 53, c("4a2a20"))
        a.rect(cx - 3, 51, cx + 3, 53, c("7a3a22"))
        a.px(cx - 1, 52, c("a84a26"))
    a.rect(cx - 8, 41, cx + 8, 42, P["stone"])  # lintel stones
    a.rect(cx - 8, 41, cx + 8, 41, P["stone_l"])
    a.rect(cx - 8, 54, cx + 8, 54, P["stone_d"])
    # vent holes along the dome
    for (x, y) in ((22, 40), (46, 40), (26, 30), (42, 30)):
        a.rect(x, y, x + 1, y + 1, c("120c0c"))
    # woodpile left
    for row, (y, n, x0) in enumerate(((57, 3, 4), (53, 3, 6), (49, 2, 8))):
        for i in range(n):
            x = x0 + i * 5
            a.rect(x, y, x + 5, y + 3, P["wood"])
            a.rect(x, y, x + 5, y, P["wood_l"])
            a.rect(x, y + 3, x + 5, y + 3, P["wood_d"])
            a.ellipse([x - 1, y, x + 2, y + 3], P["dirt_l"])
            a.px(x, y + 1, P["dirt_d"])
    # charcoal heap and a sack on the right
    a.d.polygon([(48, 62), (51, 54), (56, 50), (62, 53), (67, 58), (68, 62)], fill=c("2a282e"))
    a.d.polygon([(51, 54), (56, 50), (62, 53), (58, 55), (54, 56)], fill=c("4a484f"))
    for (x, y) in ((54, 54), (58, 52), (61, 56), (56, 58), (64, 60)):
        a.rect(x, y, x + 2, y + 1, c("5e5c68"))
    ember = [(55, 57), (60, 54), (63, 59)]
    for (x, y) in ember:
        a.px(x, y, c("f08a2a") if lit else c("6a4030"), lit)
    a.rect(58, 60, 66, 64, c("c8b48a"))  # sack
    a.rect(58, 60, 66, 60, c("e0cca0"))
    a.rect(58, 64, 66, 64, c("a08c62"))
    a.rect(61, 58, 63, 60, c("a08c62"))
    a.rect(61, 59, 63, 59, P["wood_d"])
    return a.finish()


def grove_art(lit=True):
    a = Art(72, 62)
    P = M.P
    rng = random.Random(9)
    # mossy bed
    a.d.ellipse([2, 36, 70, 61], fill=c("2c4a30"))
    a.d.ellipse([4, 36, 68, 58], fill=c("3a5e3a"))
    for _ in range(120):
        x, y = rng.randrange(6, 66), rng.randrange(39, 57)
        if ((x - 36) / 31) ** 2 + ((y - 47) / 10.5) ** 2 < 1:
            a.px(x, y, rng.choice([c("4a7a46"), c("2c4a30"), c("5a6b2c"), c("33523a")]))
    # dark undergrowth at the back (the shade it wants)
    for (bx, by, r) in ((8, 36, 7), (20, 32, 8), (34, 30, 9), (50, 32, 8), (62, 36, 7), (27, 28, 6), (44, 27, 6)):
        a.ellipse([bx - r, by - r + 2, bx + r, by + r - 2], P["tree_d"])
        a.ellipse([bx - r + 2, by - r + 1, bx + r - 3, by + r - 4], P["tree"])
        a.ellipse([bx - r + 3, by - r + 2, bx - 1, by - 1], P["tree_l"])
    # glowcaps: (centre x, ground y, cap half width, stem height)
    caps = [(14, 52, 5, 6), (24, 56, 4, 5), (34, 49, 9, 14), (47, 54, 6, 8), (58, 51, 5, 7), (40, 58, 4, 4),
            (20, 45, 4, 5), (54, 44, 4, 5), (8, 45, 3, 4)]
    cap_col = (c("3cbfa0"), c("1f7470"), c("b4ffe0")) if lit else (c("3e8a7a"), c("27575a"), c("86c4b0"))
    stem_col = (c("dde6d0"), c("98aa96")) if lit else (c("b6bfae"), c("7c8a7c"))
    for (x, y, hw, sh) in sorted(caps, key=lambda t: t[1]):
        a.rect(x - 1, y - sh, x + 1, y, stem_col[0])
        a.rect(x + 1, y - sh, x + 1, y, stem_col[1])
        top = y - sh - hw // 2 - 1
        a.d.pieslice([x - hw, top - 1, x + hw, top + hw + 1], 180, 360, fill=cap_col[0])
        a.rect(x - hw, top + hw // 2 + 1, x + hw, top + hw // 2 + 1, cap_col[1])
        a.rect(x + hw // 2, top + 2, x + hw - 1, max(top + 2, top + hw // 2), cap_col[1])
        if lit:
            a.de.pieslice([x - hw, top - 1, x + hw, top + hw + 1], 180, 360, fill=cap_col[0])
            a.de.rectangle([x - hw, top + hw // 2 + 1, x + hw, top + hw // 2 + 1], fill=cap_col[1])
        for k in range(max(1, hw // 3)):
            sx, sy = x - hw // 2 + k * (hw // 2 + 1), top + 2 + (k % 2)
            a.px(sx, sy, cap_col[2], lit)
            if hw >= 6:
                a.px(sx + 2, sy + 1, cap_col[2], lit)
        a.px(x - hw + 1, top + hw // 2 - 1, cap_col[2], lit)
    # woven basket and a plank step in front
    a.rect(52, 58, 62, 61, c("a0782f"))
    a.rect(52, 58, 62, 58, c("c09a48"))
    a.rect(52, 60, 62, 60, c("7a5a22"))
    for x in range(53, 62, 2):
        a.px(x, 59, c("7a5a22"))
    a.ellipse([54, 55, 59, 58], cap_col[0], lit)
    a.ellipse([57, 54, 61, 58], cap_col[1], lit)
    for i, x in enumerate((6, 12, 18)):
        a.rect(x, 58, x + 4, 60, P["wood"])
        a.rect(x, 58, x + 4, 58, P["wood_l"])
        a.rect(x, 60, x + 4, 60, P["wood_d"])
    return a.finish()


# ---------------------------------------------------------------- Moonmoth Loft (1x1, ticket 144)
def loft_art(lit=True):
    """A stilted loft with a silk drying rack, a lantern by the door and pale moths (2x2 pixels, readable at 1x)."""
    a = Art(40, 46)
    P = M.P
    # stilts and floor
    for x in (5, 14, 25, 34):
        a.rect(x, 33, x + 2, 45, P["wood_d"])
        a.rect(x, 33, x, 45, P["wood"])
    a.rect(3, 31, 37, 34, P["wood_d"])
    a.rect(3, 31, 37, 31, P["wood_l"])
    # plank walls and the steep thatch roof
    a.rect(6, 13, 34, 31, P["wood"])
    for y in range(15, 31, 4):
        a.rect(6, y, 34, y, P["wood_d"])
    a.rect(6, 13, 6, 31, P["wood_l"])
    a.d.polygon([(3, 14), (20, 2), (37, 14)], fill=P["thatch"])
    a.d.polygon([(8, 14), (20, 6), (32, 14)], fill=P["thatch_l"])
    a.d.line([(3, 14), (37, 14)], fill=P["thatch_d"])
    # door, shuttered window and the jar lantern
    a.rect(17, 22, 23, 31, P["wood_d"])
    a.rect(18, 23, 22, 31, c("4a3a2a"))
    a.rect(8, 17, 13, 21, c("2a2436"))
    if lit:
        a.rect(9, 18, 12, 20, c("ffd060"), True)
    a.rect(13, 24, 16, 28, c("ffc65a"), lit)
    a.rect(13, 23, 16, 23, P["iron_d"])
    if lit:
        a.rect(14, 25, 15, 27, c("fff3c0"), True)
    # silk drying rack in front: a frame and five hanging strips
    for x in (10, 30):
        a.rect(x, 34, x + 1, 43, P["wood_d"])
    a.rect(10, 34, 31, 35, P["wood_l"])
    cols = (c("d6c8f0"), c("aa96d2"), c("e6ecff"))
    for i, x in enumerate((13, 17, 21, 25, 28)):
        ln = (7, 9, 6, 8, 5)[i]
        a.rect(x, 36, x + 1, 36 + ln, cols[i % 3])
        a.rect(x + 1, 36, x + 1, 36 + ln, c("6e6096"))
    # pale moths round the loft: 2x2 pixels, so they read at 1x; emissive (for the glow) once the lamp is lit
    for (x, y) in ((8, 8), (30, 6), (22, 1), (3, 16), (35, 20), (6, 25)):
        a.rect(x, y, x + 1, y + 1, c("e6ecff"), lit)
    return a.finish()


# ---------------------------------------------------------------- scene: day render first, then the night pass
class Scene:
    def __init__(self, tw, th, seed=3):
        self.tw, self.th = tw, th
        self.W, self.H = tw * T, th * T
        self.rng = random.Random(seed)
        self.day = Image.new("RGBA", (self.W, self.H))
        self.shadow_ops = []  # (img, (x, y))
        self.objs = []  # (sort_y, img, (x, y), emissive or None, lit_windows)
        self.lights = []  # (cx, cy, R, colour mul, strength)
        self.halos = []  # (cx, cy, R, rgb, alpha) additive blobs
        self.puffs = []
        self.extra_em = Image.new("RGBA", (self.W, self.H))

    # --- terrain
    def terrain(self, kinds, roads):
        def conn(x, y):
            m = 0
            for bit, (dx, dy) in zip((1, 2, 4, 8), ((0, -1), (1, 0), (0, 1), (-1, 0))):
                if (x + dx, y + dy) in roads:
                    m |= bit
            return m
        for y in range(self.th):
            for x in range(self.tw):
                k = kinds.get((x, y), "grass")
                if k == "grass":
                    t = tile_img("terrain/grass.png", pick([0, 0, 1, 1, 2, 2, 2, 3, 4], x, y))
                elif k == "forest":
                    t = tile_img("terrain/forest.png", pick([0, 1, 2, 3], x, y))
                else:
                    t = tile_img("terrain/rock.png", pick([0, 1, 2, 3], x, y))
                self.day.alpha_composite(t, (x * T, y * T))
                if (x, y) in roads:
                    m = conn(x, y)
                    row = ((x * 31 + y * 17) >> 1) & 1
                    self.day.alpha_composite(load("roads/dirt.png").crop((m * T, row * T, m * T + T, row * T + T)),
                                             (x * T, y * T))

    # --- objects
    def _shadow(self, shadow, pos):
        self.shadow_ops.append((shadow, pos))

    def add(self, img, origin, base, sort_y=None, shadow=None, emissive=None, windows=None):
        """origin: pixel of the sprite's base point on the map. windows: None, 'lit' or 'dark' (recolours window pixels)."""
        if windows:
            img, emissive = self._windows(img, windows)
        pos = (int(origin[0] - base[0]), int(origin[1] - base[1]))
        if shadow is not None:
            self._shadow(*shadow(origin))
        self.objs.append((origin[1] if sort_y is None else sort_y, img, pos, emissive))

    @staticmethod
    def _windows(img, mode):
        a = np.array(img)
        m = (a[..., 3] > 0) & (a[..., 0] > 225) & (a[..., 1] > 170) & (a[..., 2] < 150)
        em = np.zeros_like(a)
        if mode == "lit":
            em[m] = a[m]
            em[m, 0] = 255
            em[m, 1] = np.minimum(255, a[m, 1] + 12)
        else:
            a[m] = (46, 52, 74, 255)
        return Image.fromarray(a, "RGBA"), (Image.fromarray(em, "RGBA") if mode == "lit" else None)

    def building(self, name, tx, ty, windows="lit"):
        e = MAN["buildings"][name]
        fw, fh = e["footprint"]
        img = load(e["file"])
        origin = ((tx + fw / 2) * T, (ty + fh) * T - 3)
        sh = None
        if "shadow" in e:
            simg, off = load(e["shadow"]["file"]), e["shadow"]["offset"]
            sh = lambda o, simg=simg, off=off: (simg, (int(o[0] + off[0]), int(o[1] + off[1])))
        self.add(img, origin, e["base"], shadow=sh, windows=windows)
        return origin

    def custom(self, art, tx, ty, fw, fh):
        img, em, base = art
        origin = ((tx + fw / 2) * T, (ty + fh) * T - 3)
        w = int(img.width * 0.92)
        shw = Image.new("RGBA", (w + 6, 14))
        ImageDraw.Draw(shw).ellipse([0, 0, w + 5, 13], fill=(4, 6, 18, 84))
        sh = lambda o, shw=shw: (shw, (int(o[0] - shw.width // 2), int(o[1] - 7)))
        self.add(img, origin, base, shadow=sh, emissive=em)
        return origin

    def lamp(self, kind, tx, ty, lit=True):
        art = lamp_art(kind, lit)
        img, em, base = art
        origin = (tx * T + T // 2, (ty + 1) * T - 4)
        shw = Image.new("RGBA", (16, 8))
        ImageDraw.Draw(shw).ellipse([0, 0, 15, 7], fill=(4, 6, 18, 84))
        sh = lambda o, shw=shw: (shw, (int(o[0] - 8), int(o[1] - 4)))
        self.add(img, origin, base, shadow=sh, emissive=em if lit else None)
        return origin

    def prop(self, name, x, y):
        e = MAN["props"][name]
        sh = None
        if "shadow" in e:
            simg, off = load(e["shadow"]["file"]), e["shadow"]["offset"]
            sh = lambda o, simg=simg, off=off: (simg, (int(o[0] + off[0]), int(o[1] + off[1])))
        self.add(load(e["file"]), (x, y), e["base"], shadow=sh)

    def walker(self, variant, direction, frame, x, y):
        w = load("walkers/walkers.png")
        row = variant * 4 + ["down", "up", "left", "right"].index(direction)
        cell = w.crop((frame * 16, row * 20, frame * 16 + 16, row * 20 + 20))
        sh = lambda o: (load("walkers/shadow.png"), (int(o[0] - 7), int(o[1] - 3)))
        self.add(cell, (x, y), (8, 18), shadow=sh)

    def trees(self, kinds, keep_clear=()):
        for (x, y), k in kinds.items():
            if k != "forest":
                continue
            r = random.Random(x * 131 + y * 7)
            for _ in range(2 if r.random() < 0.8 else 1):
                name = r.choice(["pine_0", "pine_1", "pine_2", "oak_green_0", "oak_green_1", "oak_green_2",
                                 "oak_green_3", "oak_deep_0"])
                self.prop(name, x * T + r.randint(6, 26), y * T + r.randint(18, 31))

    def light(self, cx, cy, tiles, kind, strength=0.97):
        self.lights.append((cx, cy, (tiles + 0.5) * T, LAMP_LIGHT[kind], strength))
        return

    # --- render
    def render_day(self):
        img = self.day.copy()
        for shadow, pos in self.shadow_ops:
            img.alpha_composite(shadow, pos)
        em = self.extra_em.copy()
        for _, sp, pos, e in sorted(self.objs, key=lambda o: o[0]):
            img.alpha_composite(sp, pos)
            if e is not None:
                em.alpha_composite(e, pos)
        return img, em

    def render_night(self, smoke_at=()):
        day, em = self.render_day()
        base = to_arr(day)
        out = base * NIGHT
        yy, xx = np.mgrid[0:self.H, 0:self.W]
        for cx, cy, R, mul, strength in self.lights:
            d = np.hypot(xx - cx, (yy - cy) * 1.0)
            t = np.clip((R - d) / (R * 0.42), 0, 1)
            m = (t * t * (3 - 2 * t))[..., None] * strength
            out = out * (1 - m) + base * np.array(mul) * m
        img = to_img(out)
        # emissive pixels stay bright, with a soft halo around them
        bright = em.copy()
        img.alpha_composite(bright)
        halo = to_arr(bright.filter(ImageFilter.GaussianBlur(5)).convert("RGBA"))
        ha = np.asarray(bright.filter(ImageFilter.GaussianBlur(5)).getchannel("A"), dtype=np.float32)[..., None] / 255.0
        arr = to_arr(img)
        arr = 1 - (1 - arr) * (1 - np.clip(halo * 1.2 * np.clip(ha * 3, 0, 1), 0, 0.55))
        for cx, cy, R, rgb, alpha in self.halos:
            d = np.hypot(xx - cx, yy - cy)
            t = np.clip(1 - d / R, 0, 1)[..., None] ** 2 * alpha
            arr = 1 - (1 - arr) * (1 - t * (np.array(rgb) / 255.0))
        img = to_img(arr)
        img.alpha_composite(bright)
        for (x, y, r, a) in self.puffs:
            lay = Image.new("RGBA", img.size)
            ImageDraw.Draw(lay).ellipse([x - r, y - r, x + r, y + r], fill=(150, 150, 180, a))
            img.alpha_composite(lay.filter(ImageFilter.GaussianBlur(1.2)))
        return img

    def render_plain(self):
        return self.render_day()[0]


def px_text_panel(d, box, fill=(24, 20, 18, 235), border=BORDER):
    d.rounded_rectangle(box, 8, fill=fill, outline=border, width=2)


# ---------------------------------------------------------------- 1. night map
def night_map():
    tw, th = 25, 14
    sc = Scene(tw, th)
    kinds = {}
    rng = random.Random(21)
    for y in range(0, 6):  # forest top-left
        for x in range(0, 8 - y):
            if rng.random() < 0.9 or x < 3:
                kinds[(x, y)] = "forest"
    for y in range(10, 14):  # rock bottom-left
        for x in range(0, 4):
            if rng.random() < 0.75:
                kinds[(x, y)] = "rock"
    for y in range(11, 14):  # a small stand bottom-right
        for x in range(21, 25):
            if rng.random() < 0.6 and y >= 12:
                kinds[(x, y)] = "forest"
    roads = {(x, 7) for x in range(2, 25)} | {(12, y) for y in range(1, 14)} | {(x, 11) for x in range(12, 21)} \
        | {(22, y) for y in range(3, 8)} | {(x, 3) for x in range(7, 12)} | {(7, y) for y in range(3, 7)}
    for p in list(roads):
        if kinds.get(p) in ("forest", "rock"):
            kinds.pop(p)
    sc.terrain(kinds, roads)
    sc.trees(kinds)

    def foot(tx, ty, fw=1, fh=1):
        return ((tx + fw / 2) * T, (ty + fh) * T - 3)

    # lamps first (lights), buildings after
    lamps = [("lantern", 11, 8, 5), ("lantern", 19, 8, 5), ("brazier", 5, 6, 3), ("lantern", 14, 11 + 1, 5)]
    lamps = [l for l in lamps if l[3]]
    for kind, tx, ty, r in lamps:
        o = sc.lamp(kind, tx, ty)
        sc.light(tx * T + T // 2, ty * T + T // 2, r, kind)
        sc.halos.append((o[0], o[1] - 22, 30, LAMP_HALO[kind], 0.7))
    # houses (lit: inside a lamp pool)
    for name, tx, ty in [("cottage", 8, 6), ("cottage_shingle", 10, 6), ("well", 13, 6), ("cottage", 14, 6),
                         ("cottage_shingle", 16, 6), ("hut", 18, 6), ("hut", 7, 8), ("cottage", 9, 8),
                         ("cottage_shingle", 17, 8), ("tent", 3, 7 - 1), ("cottage", 20, 6)]:
        if (tx, ty) in roads:
            continue
        sc.building(name, tx, ty)
    sc.building("hearth", 13, 8)
    sc.building("woodcutter", 4, 5)
    sc.building("storehouse", 15, 12)
    # Charcoal Kiln (night job, glowing) next to the lamp at (19, 8)
    kiln = kiln_art(True)
    ko = sc.custom(kiln, 21, 9, 2, 2)
    sc.halos.append((ko[0], ko[1] - 12, 62, (255, 140, 50), 0.55))
    sc.lights.append((ko[0], ko[1] - 8, 84, (1.0, 0.72, 0.42), 0.55))
    sc.puffs += [(ko[0] - 2, ko[1] - 58, 5, 60), (ko[0] + 1, ko[1] - 66, 6, 46), (ko[0] - 3, ko[1] - 75, 7, 32)]
    # Glowcap Grove at the forest edge, glowing faintly blue-green
    gr = grove_art(True)
    go = sc.custom(gr, 5, 3, 2, 2)
    sc.halos.append((go[0], go[1] - 14, 70, (60, 220, 190), 0.30))
    sc.lights.append((go[0], go[1] - 12, 88, (0.45, 1.0, 0.85), 0.32))
    # the unlit Sawmill at the edge (22..23, 3): out of every pool
    so = sc.building("sawmill", 22, 2, windows="dark")
    # walkers near lit buildings
    for v, dr, fr, x, y in [(0, "right", 1, 9 * T + 6, 7 * T + 22), (5, "left", 2, 16 * T + 4, 7 * T + 20),
                            (9, "down", 1, 12 * T + 16, 9 * T + 14), (14, "up", 0, 12 * T + 16, 5 * T + 20),
                            (3, "right", 2, 19 * T + 10, 11 * T + 24), (18, "left", 0, 20 * T + 20, 11 * T + 22),
                            (11, "down", 1, 14 * T + 8, 10 * T + 28), (7, "right", 1, 6 * T + 14, 7 * T + 22)]:
        sc.walker(v, dr, fr, x, y)
    # the unlit building is out of the pools: nothing to add. Render.
    img = sc.render_night()
    big = M.upscale(img, 2)
    d = ImageDraw.Draw(big, "RGBA")
    # "needs a lamp" marker above the Sawmill
    mx, my = int(so[0] * 2), int((so[1] - 70) * 2)
    label = "needs a lamp"
    wv = int(U.tw(label, 15))
    box = (mx - wv // 2 - 28, my - 30, mx + wv // 2 + 12, my + 2)
    d.rounded_rectangle(box, 7, fill=(24, 20, 18, 238), outline=(214, 140, 72), width=2)
    d.polygon([(mx - 6, my + 1), (mx + 6, my + 1), (mx, my + 9)], fill=(24, 20, 18, 238))
    d.line([(mx - 6, my + 2), (mx, my + 9), (mx + 6, my + 2)], fill=(214, 140, 72), width=2)
    d.rectangle([mx - 5, my + 1, mx + 5, my + 2], fill=(24, 20, 18, 238))
    ic = M.upscale(lamp_art("lantern", False)[0].crop((0, 0, 18, 20)), 1)
    big.alpha_composite(ic, (box[0] + 6, box[1] + 6))
    U.txt(d, (box[0] + 28, (box[1] + box[3]) // 2), label, 15, (240, 196, 130), "lm")
    # clock (top right) and the building panel (bottom right)
    pw = 290
    px = 18
    px_text_panel(d, (px, 16, px + pw, 110))
    big.alpha_composite(U.dial_img(23 + 10 / 60, 3), (px + 14, 26))
    U.txt(d, (px + 110, 40), "Day 3, 23:10", 20, TEXT, "lm")
    U.txt(d, (px + 110, 64), "Night shift 20:00-06:00", 13, MOON_BLUE, "lm")
    U.txt(d, (px + 110, 84), "Lamps burn 19:00-07:00", 13, DIM, "lm")
    bx0, by0, bw, bh = big.width - 330, big.height - 190, 312, 172
    px_text_panel(d, (bx0, by0, bx0 + bw, by0 + bh), border=GOLD)
    U.txt(d, (bx0 + 16, by0 + 14), "Sawmill", 20, GOLD)
    U.txt(d, (bx0 + bw - 16, by0 + 20), "Refining", 13, FAINT, "rm")
    U.txt(d, (bx0 + 16, by0 + 46), "Day shift", 14, FAINT)
    U.txt(d, (bx0 + 130, by0 + 46), "closed (it is night)", 14, DIM)
    U.txt(d, (bx0 + 16, by0 + 70), "Night shift", 14, FAINT)
    U.txt(d, (bx0 + 130, by0 + 70), "0 / 2 workers", 14, RED)
    d.rounded_rectangle([bx0 + 14, by0 + 100, bx0 + bw - 14, by0 + 130], 5, fill=(52, 34, 26), outline=(214, 140, 72))
    U.txt(d, (bx0 + 26, by0 + 115), "needs a lamp", 16, (240, 196, 130), "lm")
    U.txt(d, (bx0 + bw - 26, by0 + 115), "nearest: 6 tiles", 13, DIM, "rm")
    U.txt(d, (bx0 + 16, by0 + 148), "Build a Lamp within 5 tiles to open the slot.", 13, DIM, "lm")
    # small legend, bottom left
    lx0, ly0 = 18, big.height - 112
    px_text_panel(d, (lx0, ly0, lx0 + 360, ly0 + 96))
    U.txt(d, (lx0 + 14, ly0 + 12), "Lit at night", 15, GOLD)
    U.txt(d, (lx0 + 14, ly0 + 34), "Lantern Post r5, Brazier r3 (warm pools)", 13, TEXT)
    U.txt(d, (lx0 + 14, ly0 + 54), "Charcoal Kiln glows. Glowcap Grove glows teal.", 13, TEXT)
    U.txt(d, (lx0 + 14, ly0 + 74), "Houses in a pool show lit windows.", 13, DIM)
    return big


# ---------------------------------------------------------------- 2. lamp tiers
TIERS = [
    ("brazier", "Brazier", "I", "Camp", "wood", "wood", 3, "1x1, burns logs", (255, 160, 70)),
    ("lantern", "Lantern Post", "II", "Village", "charcoal", "charcoal", 5, "charcoal lantern", (255, 200, 110)),
    ("lumen", "Lumen Lamp", "III", "Town", "Lumen", "lumen", 7, "Lumen crystal glow", (127, 224, 240)),
    ("grid", "Grid Lamp", "IV", "City", "Lumen from the grid", "cells", 9, "wired, no hauling", (205, 240, 255)),
]


def lamp_tiers():
    gap = 24
    diam = [(2 * t[6] + 1) * T for t in TIERS]
    W = sum(diam) + gap * 5
    top, ground_h = 452, 608
    H = top + ground_h
    img = Image.new("RGBA", (W, H), c("1c1a17"))
    d = ImageDraw.Draw(img, "RGBA")
    U.txt(d, (gap, 18), "Lamp tiers: one building, upgraded by era", 30, GOLD)
    U.txt(d, (gap, 58), "Game scale (1x) and 4x. The ring is the light radius in tiles (night shift buildings inside it work); "
          "the lit ground is the pool you see on the map.", 15, DIM)
    # night ground strip at game scale
    kinds = {}
    sc = Scene(W // T + 1, ground_h // T + 1, seed=8)
    sc.terrain(kinds, set())
    x0 = gap
    centres = []
    for t, dm in zip(TIERS, diam):
        cx = x0 + dm // 2
        cy = ground_h // 2
        centres.append((cx, cy))
        x0 += dm + gap
    for t, (cx, cy) in zip(TIERS, centres):
        kind = t[0]
        tx, ty = (cx - T // 2) // T, (cy - T // 2) // T
        # snap the lamp to the centre of its slot
        art = lamp_art(kind, True)
        o = (cx, cy + 14)
        sc.add(art[0], o, art[2], emissive=art[1], shadow=lambda oo: (_ell(16, 8), (int(oo[0] - 8), int(oo[1] - 4))))
        sc.lights.append((cx, cy, (t[6] + 0.5) * T, LAMP_LIGHT[kind], 0.75))
        sc.halos.append((cx, cy - 8, 30, LAMP_HALO[kind], 0.6))
    strip = sc.render_night()
    strip = strip.crop((0, 0, W, ground_h))
    strip_base = strip
    strip = Image.new("RGBA", strip_base.size)
    sd = ImageDraw.Draw(strip)
    # tile grid inside each ring, the ring itself and a radius arrow
    for t, (cx, cy) in zip(TIERS, centres):
        r = t[6]
        R = (r + 0.5) * T
        gx0 = cx - T // 2
        gy0 = cy - T // 2
        for i in range(-r, r + 2):
            for j in range(-r, r + 2):
                if math.hypot(i, j) <= r + 0.7:
                    pass
        for i in range(-r, r + 1):
            for j in range(-r, r + 1):
                if math.hypot(i, j) <= r + 0.01:
                    sd.rectangle([gx0 + i * T, gy0 + j * T, gx0 + i * T + T - 1, gy0 + j * T + T - 1],
                                 outline=(255, 255, 255, 22))
        n = 96
        for k in range(n):
            if k % 2:
                continue
            a0, a1 = 2 * math.pi * k / n, 2 * math.pi * (k + 1) / n
            sd.line([(cx + R * math.cos(a0), cy + R * math.sin(a0)), (cx + R * math.cos(a1), cy + R * math.sin(a1))],
                    fill=t[8] + (210,), width=2)
        sd.line([(cx + 10, cy), (cx + R - 3, cy)], fill=t[8] + (220,), width=1)
        for k in range(1, r + 1):
            xx = cx + k * T
            sd.line([(xx, cy - 4), (xx, cy + 4)], fill=t[8] + (230,), width=1)
        lab = f"{r} tiles"
        sd.rounded_rectangle([cx + R / 2 - 30, cy + 8, cx + R / 2 + 30, cy + 28], 4, fill=(20, 18, 16, 190))
        sd.text((cx + R / 2, cy + 18), lab, font=M.font(13), fill=(236, 226, 206), anchor="mm")
    # grid lamp: cable run on the ground between the lamp base and a junction box
    cx, cy = centres[3]
    cable = c("2c3236")
    pts = [(cx, cy + 16), (cx, cy + 40), (cx + 70, cy + 40), (cx + 70, cy + 70)]
    for a, b in zip(pts, pts[1:]):
        sd.line([a, b], fill=cable, width=3)
        sd.line([(a[0], a[1] - 1), (b[0], b[1] - 1)], fill=(60, 120, 132, 170), width=1)
    sd.rectangle([cx + 62, cy + 70, cx + 78, cy + 82], fill=c("3e5a66"), outline=c("1a1c20"))
    sd.rectangle([cx + 69, cy + 74, cx + 71, cy + 76], fill=c("7fe0f0"))
    sd.text((cx + 70, cy + 94), "from the grid", font=M.font(12), fill=(170, 200, 210), anchor="mm")
    strip_base.alpha_composite(strip)
    img.alpha_composite(strip_base, (0, top))
    d.rectangle([0, top - 1, W, top], fill=BORDER)
    # header columns, aligned over each slot
    x0 = gap
    for t, dm, (cx, cy) in zip(TIERS, diam, centres):
        kind, name, tier, era, fuel_name, fuel_icon, r, note, col = t
        mid = x0 + dm // 2
        U.txt(d, (mid, 98), name, 26, GOLD, "mm")
        d.rounded_rectangle([mid - 72, 118, mid + 72, 142], 6, fill=(44, 38, 34), outline=(70, 62, 54))
        U.txt(d, (mid, 130), f"Tier {tier}  -  {era} era", 14, TEXT, "mm")
        fx = mid - 100
        U.txt(d, (fx, 166), "Fuel/night", 13, FAINT, "lm")
        U.put_icon(img, fuel_icon, fx + 78, 157, 2)
        U.txt(d, (fx + 112, 166), fuel_name, 14, TEXT, "lm")
        U.txt(d, (fx, 188), "Radius", 13, FAINT, "lm")
        U.txt(d, (fx + 78, 188), f"{r} tiles ({2 * r + 1} wide)", 14, TEXT, "lm")
        U.txt(d, (fx, 210), note, 13, DIM, "lm")
        # sprites: 1x lit, 4x lit, 1x unlit (the dark look before dusk and when out of fuel)
        lit = lamp_art(kind, True)
        off = lamp_art(kind, False)
        box = (x0 + 6, 240, x0 + dm - 6, top - 14)
        d.rounded_rectangle(box, 8, fill=(30, 28, 25), outline=(60, 54, 48))
        ground = Image.new("RGBA", (box[2] - box[0] - 4, box[3] - box[1] - 4), M.P["grass"])
        gtile = tile_img("terrain/grass.png", 1)
        for gx in range(0, ground.width, T):
            for gy in range(0, ground.height, T):
                ground.alpha_composite(gtile, (gx, gy))
        night_ground = to_img(to_arr(ground) * NIGHT)
        gl = Image.new("RGBA", ground.size)
        ImageDraw.Draw(gl).ellipse([ground.width // 2 - 62, ground.height // 2 - 62, ground.width // 2 + 62,
                                    ground.height // 2 + 62], fill=LAMP_HALO[kind] + (40,))
        night_ground.alpha_composite(gl.filter(ImageFilter.GaussianBlur(22)))
        img.alpha_composite(night_ground, (box[0] + 2, box[1] + 2))
        mx = (box[0] + box[2]) // 2
        big = M.upscale(lit[0], 4)
        by = box[3] - 22
        img.alpha_composite(big, (mx - big.width // 2, by - big.height))
        img.alpha_composite(M.upscale(lit[1], 4), (mx - big.width // 2, by - big.height))
        img.alpha_composite(lit[0], (box[0] + 18, by - lit[0].height))
        img.alpha_composite(lit[1], (box[0] + 18, by - lit[0].height))
        img.alpha_composite(off[0], (box[2] - 18 - off[0].width, by - off[0].height))
        d.text((mx, box[3] - 8), "4x", font=M.font(13), fill=FAINT, anchor="mm")
        d.text((box[0] + 18 + lit[0].width // 2, box[3] - 8), "1x", font=M.font(13), fill=FAINT, anchor="mm")
        d.text((box[2] - 18 - off[0].width // 2, box[3] - 8), "off", font=M.font(13), fill=FAINT, anchor="mm")
        x0 += dm + gap
    return img


def _ell(w, h):
    s = Image.new("RGBA", (w, h))
    ImageDraw.Draw(s).ellipse([0, 0, w - 1, h - 1], fill=(4, 6, 18, 84))
    return s


# ---------------------------------------------------------------- 3. new buildings and goods
def patch_scene(art_day, art_night, tx_w=5, tx_h=4):
    """Returns (day_img, night_img) of the building on a grass patch, at game scale."""
    outs = []
    for lit, art in ((False, art_day), (True, art_night)):
        sc = Scene(tx_w, tx_h, seed=4)
        sc.terrain({}, set())
        o = sc.custom(art, (tx_w - 2) // 2, tx_h - 3, 2, 2)
        if lit:
            tag = art[3] if len(art) > 3 else None
        outs.append((sc, o))
    return outs


def new_buildings():
    W, H = 1280, 900
    img = Image.new("RGBA", (W, H), c("1c1a17"))
    d = ImageDraw.Draw(img, "RGBA")
    U.txt(d, (30, 18), "New buildings and goods", 30, GOLD)
    U.txt(d, (30, 58), "Both are 2x2 and work only at night. Day look on the left, night look on the right (3x). "
          "Sprites are 1x pixel art, same palette and 1 px outline as the real ones.", 15, DIM)
    rows = [
        ("Charcoal Kiln", "Village era, Refining", "Night only. Burns wood into charcoal, the Lantern Post's fuel.",
         "wood", "charcoal", "6 wood -> 3 charcoal per night, 2 workers", kiln_art, (255, 140, 50, 0.55, 62), (1.0, 0.72, 0.42, 0.55)),
        ("Glowcap Grove", "Village era, Food", "Night only. Grows glowing mushrooms in the shade. Counts as food.",
         None, "glowcap", "5 food per night, 2 workers, needs shade or forest edge, no water", grove_art,
         (60, 220, 190, 0.30, 70), (0.45, 1.0, 0.85, 0.32)),
    ]
    y = 96
    for name, sub, desc, gin, gout, rate, fn, halo, lightc in rows:
        panel = (24, y, W - 24, y + 318)
        d.rounded_rectangle(panel, 8, fill=(34, 31, 27), outline=BORDER)
        U.txt(d, (48, y + 16), name, 26, GOLD)
        U.txt(d, (48, y + 50), sub, 14, FAINT)
        U.txt(d, (48, y + 76), desc, 14, TEXT)
        U.txt(d, (48, y + 98), rate, 14, DIM)
        # icons for goods in the recipe line
        if gin:
            U.put_icon(img, gin, 48, y + 124, 3)
            U.txt(d, (96, y + 145), "->", 18, DIM, "lm")
        U.put_icon(img, gout, 124 if gin else 48, y + 124, 3)
        imgs = []
        for lit in (False, True):
            art = fn(lit)
            sc = Scene(7, 6, seed=4)
            sc.terrain({}, set())
            o = sc.custom(art, 2, 2, 2, 2)
            if lit:
                sc.halos.append((o[0], o[1] - 14, halo[4], halo[:3], halo[3]))
                sc.lights.append((o[0], o[1] - 10, halo[4] + 24, lightc[:3], lightc[3]))
                if name == "Charcoal Kiln":
                    sc.puffs += [(o[0] - 2, o[1] - 58, 5, 60), (o[0] + 1, o[1] - 66, 6, 46), (o[0] - 3, o[1] - 75, 7, 32)]
                imgs.append(sc.render_night())
            else:
                imgs.append(sc.render_plain())
        for i, (im, lab) in enumerate(zip(imgs, ("Day", "Night"))):
            big = M.upscale(im, 2)  # 224x192 -> 448 x 384 would not fit: 7x6 tiles at 2x is 448x384
            big = big.crop((0, 0, big.width, big.height))
            x = 400 + i * 436
            img.alpha_composite(big.resize((int(big.width * 0.9), int(big.height * 0.9)), Image.NEAREST) if False else big,
                                (x, y + 10))
            U.txt(d, (x + 8, y + 18), lab, 15, TEXT if i == 0 else MOON_BLUE)
        x1 = 400 + 2 * 436 - 16
        y += 330
    # we shrink nothing: the panels above are 318 tall with 384 of picture at 2x; see layout fix below
    return img


def new_buildings_layout():
    """Final layout: two building rows (day and night at 2x) and the goods strip."""
    W, H = 1280, 970
    img = Image.new("RGBA", (W, H), c("1c1a17"))
    d = ImageDraw.Draw(img, "RGBA")
    U.txt(d, (30, 18), "New buildings and goods", 30, GOLD)
    U.txt(d, (30, 58), "Both 2x2, both work only at night. Day look and night look at 2x; the small ones are game scale.",
          15, DIM)
    rows = [
        ("Charcoal Kiln", "Village era, Refining, 2x2",
         ["Night only. Burns wood into charcoal,", "the Lantern Post's fuel (and a good to sell)."],
         ("wood", "6"), ("charcoal", "3"), "2 workers, night shift", kiln_art, (255, 140, 50, 0.55, 62), (1.0, 0.72, 0.42, 0.55)),
        ("Glowcap Grove", "Village era, Food, 2x2",
         ["Night only. Tends glowing mushrooms in the", "shade. Counts as food."],
         None, ("glowcap", "5"), "2 workers, needs shade or forest edge, no water", grove_art,
         (60, 220, 190, 0.30, 70), (0.45, 1.0, 0.85, 0.32)),
    ]
    y = 90
    for name, sub, desc, gin, gout, extra, fn, halo, lightc in rows:
        d.rounded_rectangle((24, y, W - 24, y + 300), 8, fill=(34, 31, 27), outline=BORDER)
        U.txt(d, (48, y + 16), name, 26, GOLD)
        U.txt(d, (48, y + 50), sub, 14, FAINT)
        for i, ln in enumerate(desc):
            U.txt(d, (48, y + 78 + i * 20), ln, 14, TEXT)
        U.txt(d, (48, y + 128), "Per night", 13, FAINT, "lm")
        xx = 48
        if gin:
            U.put_icon(img, gin[0], xx, y + 146, 2)
            U.txt(d, (xx + 32, y + 160), gin[1], 16, TEXT, "lm")
            U.txt(d, (xx + 62, y + 160), "->", 16, DIM, "lm")
            xx += 92
        U.put_icon(img, gout[0], xx, y + 146, 2)
        U.txt(d, (xx + 32, y + 160), gout[1], 16, TEXT, "lm")
        U.txt(d, (48, y + 196), extra, 13, DIM)
        U.txt(d, (48, y + 220), "Works only inside a lamp's radius.", 13, (240, 196, 130))
        ims = []
        for lit in (False, True):
            art = fn(lit)
            sc = Scene(5, 4, seed=4)
            sc.terrain({}, set())
            o = sc.custom(art, 1, 1, 2, 2)
            if lit:
                sc.halos.append((o[0], o[1] - 14, halo[4], halo[:3], halo[3]))
                sc.lights.append((o[0], o[1] - 10, halo[4] + 24, lightc[:3], lightc[3]))
                if name == "Charcoal Kiln":
                    sc.puffs += [(o[0] - 2, o[1] - 58, 5, 60), (o[0] + 1, o[1] - 66, 6, 46), (o[0] - 3, o[1] - 75, 7, 32)]
                ims.append(sc.render_night())
            else:
                ims.append(sc.render_plain())
        for i, (im, lab) in enumerate(zip(ims, ("Day", "Night"))):
            big = M.upscale(im, 2)
            x = 420 + i * 420
            img.paste(big.convert("RGB"), (x, y + 18))
            d.rectangle([x - 1, y + 17, x + big.width, y + 18 + big.height], outline=BORDER)
            U.txt(d, (x + 10, y + 26), lab, 15, (255, 255, 255, 230) if i == 0 else (190, 205, 245))
            # game-scale sprite beside, on the same ground
            sm = ims[i].crop((T, T, T * 3 + 4, T * 3 + 4))
            img.paste(sm.convert("RGB"), (x + big.width - sm.width - 12, y + 18 + 12 + 0))
        y += 312
    # goods strip
    d.rounded_rectangle((24, y, W - 24, y + 230), 8, fill=(34, 31, 27), outline=BORDER)
    U.txt(d, (48, y + 14), "Goods icons (12x12 art, 1 px dark outline, drawn at 3x in the game)", 18, GOLD)
    for i, k in enumerate(("charcoal", "glowcap")):
        x = 48 + i * 270
        im = M.icon_v2(k)
        U.txt(d, (x, y + 52), U.NAMES[k], 16, TEXT)
        img.alpha_composite(M.upscale(im, 8), (x, y + 76))
        img.alpha_composite(M.upscale(im, 3), (x + 128, y + 76))
        img.alpha_composite(M.upscale(im, 2), (x + 128, y + 126))
        img.alpha_composite(im, (x + 168, y + 128))
    # next to the old ones on the HUD panel
    x = 600
    U.txt(d, (x, y + 52), "Next to the others (top bar, 3x)", 14, FAINT)
    d.rounded_rectangle((x, y + 76, W - 48, y + 140), 6, fill=(24, 20, 18))
    xx = x + 14
    for k in ("wood", "stone", "planks", "charcoal", "food", "glowcap", "lumen"):
        U.put_icon(img, k, xx, y + 86)
        U.txt(d, (xx + 46, y + 108), str(U.STOCK.get(k, 12)), 17, TEXT, "lm")
        xx += 88
    U.txt(d, (x, y + 164), "Glowcap counts as food: it feeds the Food total, and has its own row in the ledger.", 14, DIM)
    U.txt(d, (x, y + 186), "Charcoal gets a row in the top bar, the Resources page and the ledger.", 14, DIM)
    return img


# ---------------------------------------------------------------- 4. build cards
CARD_W, CARD_H = 146, 200


def card_sprite(art_or_img, maxw, maxh):
    im = art_or_img
    s = max(1, min(maxw // im.width, maxh // im.height))
    return M.upscale(im, s)


def icon20(kind):
    return M.icon_v2(kind).resize((20, 20), Image.NEAREST)


def build_card(img, x, y, name, sprite, cost, chip, chip_col, state="ok", hover=False):
    d = ImageDraw.Draw(img, "RGBA")
    bg = (28, 24, 22)
    edge = (90, 80, 70)
    if state == "short":
        bg, edge = (94, 23, 20), (226, 100, 86)
    d.rounded_rectangle([x, y, x + CARD_W, y + CARD_H], 5, fill=bg, outline=GOLD if hover else edge, width=2)
    sp = card_sprite(sprite, CARD_W - 12, 84)
    img.alpha_composite(sp, (x + (CARD_W - sp.width) // 2, y + 6 + 84 - sp.height))
    U.txt(d, (x + CARD_W // 2, y + 96), name, 16, TEXT, "ma")
    cw = int(U.tw(chip, 11)) + 14
    d.rounded_rectangle([x + (CARD_W - cw) // 2, y + 118, x + (CARD_W + cw) // 2, y + 134], 4, fill=(chip_col[0] // 4, chip_col[1] // 4, chip_col[2] // 4),
                        outline=chip_col)
    U.txt(d, (x + CARD_W // 2, y + 126), chip, 11, chip_col, "mm")
    for i, (g, n) in enumerate(cost.items()):
        gx = x + 18 + (i % 2) * 58
        gy = y + 142 + (i // 2) * 24
        img.alpha_composite(icon20(g), (gx, gy))
        short = U.STOCK.get(g, 0) < n
        U.txt(d, (gx + 24, gy + 11), str(n), 14, (255, 130, 114) if short else TEXT, "lm")


def build_cards():
    U.STOCK["planks"] = 12
    img = U.backdrop(0.35)
    U.top_bar(img)
    U.build_bar(img, None)
    d = ImageDraw.Draw(img, "RGBA")
    lamp_sprite = lamp_art("brazier", True)[0]
    cards = [
        ("Civic", "Lamp", lamp_sprite, {"wood": 6}, "Lights 3 tiles", (255, 190, 100), "ok", True),
        ("Refining", "Charcoal Kiln", kiln_art(False)[0], {"wood": 20, "stone": 24, "planks": 8}, "Night shift", MOON_BLUE, "ok", False),
        ("Food", "Glowcap Grove", grove_art(False)[0], {"wood": 14, "stone": 10, "planks": 16}, "Night shift", MOON_BLUE, "short", False),
    ]
    pw = CARD_W + 28
    x0 = 16
    for i, (cat, name, spr, cost, chip, chip_col, state, hover) in enumerate(cards):
        x = x0 + i * (pw + 12)
        py0, py1 = 330, 330 + 36 + CARD_H + 28
        U.panel(d, (x, py0, x + pw, py1), fill=(24, 20, 18, 240))
        U.txt(d, (x + 14, py0 + 10), cat, 18, GOLD)
        build_card(img, x + 14, py0 + 38, name, spr, cost, chip, chip_col, state, hover)
    U.txt(d, (x0, 330 + 36 + CARD_H + 38), "Three category flyouts shown together. Red: planks short. Gold: hovered.", 13, (200, 190, 175))
    # hover detail panel for the Lamp
    dx0, dy0, dx1, dy1 = 660, 92, U.W - 16, 648
    U.panel(d, (dx0, dy0, dx1, dy1), fill=(24, 20, 18, 245), border=GOLD)
    d.rounded_rectangle([dx0 + 14, dy0 + 14, dx1 - 14, dy0 + 184], 6, fill=(60, 84, 48))
    tiers = ["brazier", "lantern", "lumen", "grid"]
    names = ["Brazier", "Lantern Post", "Lumen Lamp", "Grid Lamp"]
    eras = ["Camp", "Village", "Town", "City"]
    slot = (dx1 - dx0 - 28) // 4
    for i, (k, nm, er) in enumerate(zip(tiers, names, eras)):
        spr = M.upscale(lamp_art(k, True)[0], 3)
        cx = dx0 + 14 + slot * i + slot // 2
        img.alpha_composite(spr, (cx - spr.width // 2, dy0 + 150 - spr.height))
        U.txt(d, (cx, dy0 + 160), nm, 12, (240, 250, 230), "mm")
        U.txt(d, (cx, dy0 + 176), er, 11, (200, 225, 190), "mm")
        if i < 3:
            U.txt(d, (cx + slot // 2, dy0 + 100), ">", 20, (230, 240, 210), "mm")
    y = dy0 + 198
    U.txt(d, (dx0 + 18, y), "Lamp", 22, GOLD)
    U.txt(d, (dx1 - 18, y + 6), "Civic, Camp era", 13, FAINT, "ra")
    U.txt(d, (dx0 + 18, y + 34), "Lights the ground around it from dusk to dawn.", 14, TEXT)
    U.txt(d, (dx0 + 18, y + 54), "Night shift buildings only work inside a lit radius.", 14, TEXT)
    U.txt(d, (dx0 + 18, y + 74), "Upgrades with your era; an unfuelled lamp goes dark.", 14, TEXT)
    d.line([(dx0 + 18, y + 98), (dx1 - 18, y + 98)], fill=BORDER)
    U.txt(d, (dx0 + 18, y + 118), "Cost", 14, FAINT, "lm")
    U.put_icon(img, "wood", dx0 + 110, y + 104, 2)
    U.txt(d, (dx0 + 144, y + 118), f"6  (have {U.STOCK['wood']})", 14, TEXT, "lm")
    rows = [("Size", "1 x 1 tile"), ("Radius", "3 tiles, 5, 7, 9 with each tier"), ("Fuel/night", None)]
    for j, (k, v) in enumerate(rows):
        yy = y + 142 + j * 24
        U.txt(d, (dx0 + 18, yy), k, 14, FAINT, "lm")
        if v:
            U.txt(d, (dx0 + 110, yy), v, 14, TEXT, "lm")
    fy = y + 142 + 2 * 24
    xx = dx0 + 110
    for g, lab in (("wood", "wood"), ("charcoal", "charcoal"), ("lumen", "Lumen"), ("cells", "grid")):
        img_icon = M.icon_v2(g)
        img.alpha_composite(M.upscale(img_icon, 1), (xx, fy - 7))
        U.txt(d, (xx + 18, fy), lab, 13, TEXT, "lm")
        xx += 28 + int(U.tw(lab, 13)) + 16
    U.txt(d, (dx0 + 18, y + 142 + 3 * 24), "Unlock", 14, FAINT, "lm")
    U.txt(d, (dx0 + 110, y + 142 + 3 * 24), "Camp era (unlocked)", 14, GREEN, "lm")
    return img


# ---------------------------------------------------------------- 5. workforce page with shifts
def sun_glyph(d, x, y, col=(250, 200, 90)):
    d.ellipse([x - 4, y - 4, x + 4, y + 4], fill=col)
    for a in range(8):
        r0, r1 = 6, 8
        d.line([(x + r0 * math.cos(a * math.pi / 4), y + r0 * math.sin(a * math.pi / 4)),
                (x + r1 * math.cos(a * math.pi / 4), y + r1 * math.sin(a * math.pi / 4))], fill=col)


def moon_glyph(img, x, y):
    img.alpha_composite(M.icon("moon"), (x - 7, y - 7))


def workforce_shift():
    img, d, px, py = U.page_frame("Workforce (Q)", "Esc or Q closes")
    txt = lambda *a, **k: U.txt(d, *a, **k)
    txt((px + 24, py + 62), "Workers 42:  day 31,  night 11.   Idle 3, haulers 9, builders 8", 16, TEXT)
    # shift filter chips, top right
    cx0 = px + 700
    for i, (lab, on) in enumerate((("All", True), ("Day", False), ("Night", False))):
        x = cx0 + i * 62
        d.rounded_rectangle([x, py + 58, x + 56, py + 82], 5, fill=(84, 70, 44) if on else (44, 38, 34),
                            outline=GOLD if on else (70, 62, 54))
        txt((x + 28, py + 70), lab, 13, TEXT if on else DIM, "mm")
    txt((px + 24, py + 86), "Night shift 20:00-06:00. A person works days or nights, not both; "
        "night jobs fill in the same rank order.", 12, FAINT)
    cx = {"name": px + 40, "work": px + 262, "shift": px + 316, "low": px + 424, "norm": px + 478, "high": px + 548,
          "pause": px + 604, "note": px + 686}
    ch = py + 108
    for k, lab, anc in (("name", "Building", "la"), ("work", "Workers", "ma"), ("shift", "Shift", "la"),
                        ("low", "Priority", "la"), ("note", "Note", "la")):
        txt((cx[k], ch), lab, 13, FAINT, anc)
    d.line([(px + 16, ch + 22), (px + 884, ch + 22)], fill=BORDER)
    DAY, NGT = "Day", "Night"
    rows = [
        ("hdr", "Food"),
        ("row", "Farm", "3/3", DAY, "High", False, ""),
        ("row", "Forager", "2/2", DAY, "Normal", False, ""),
        ("row", "Glowcap Grove", "2/2", NGT, "Normal", False, "lit by Lantern Post"),
        ("hdr", "Lumen"),
        ("row", "Lumen Tap", "2/2", DAY, "High", False, ""),
        ("row", "Lumen Tap", "1/2", NGT, "High", False, "1 short"),
        ("hdr", "Logistics"),
        ("row", "Storehouse", "haulers 4/4", DAY, "Normal", False, ""),
        ("row", "Storehouse", "haulers 2/2", NGT, "Normal", False, "half the slots"),
        ("hdr", "Refining"),
        ("row", "Sawmill", "2/2", DAY, "Normal", False, ""),
        ("row", "Sawmill", "0/2", NGT, "Normal", False, "needs a lamp"),
        ("row", "Mason", "2/2", DAY, "Normal", False, ""),
        ("row", "Mason", "2/2", NGT, "Low", False, ""),
        ("row", "Charcoal Kiln", "2/2", NGT, "High", False, "lit by Lantern Post"),
        ("hdr", "Resources"),
        ("row", "Woodcutter", "2/2", DAY, "Normal", False, ""),
        ("row", "Quarry", "0/2", DAY, "Low", True, "paused"),
    ]
    rh = 21
    ry = ch + 28
    bottom = py + 560 - 18
    for r in rows:
        if ry + rh > bottom:
            break
        mid = ry + rh // 2 - 1
        if r[0] == "hdr":
            d.rectangle([px + 16, ry, px + 884, ry + rh - 2], fill=(40, 36, 30))
            txt((px + 26, mid), r[1], 14, GOLD, "lm")
        else:
            _, name, wk, shift, pri, paused, note = r
            night = shift == NGT
            if night:
                d.rectangle([px + 16, ry, px + 884, ry + rh - 2], fill=(27, 31, 48))
                d.rectangle([px + 16, ry, px + 18, ry + rh - 2], fill=(110, 130, 210))
            txt((cx["name"], mid), name, 15, FAINT if paused else (200, 210, 240) if night else TEXT, "lm")
            a, _, b = wk.split()[-1].partition("/")
            colr = DIM if paused else (RED if a != b else GREEN)
            if note == "needs a lamp":
                colr = (232, 150, 84)
            txt((cx["work"], mid), wk, 13, colr, "mm")
            # shift pill
            x = cx["shift"]
            d.rounded_rectangle([x, ry + 1, x + 76, ry + rh - 3], 4, fill=(36, 44, 74) if night else (66, 54, 30),
                                outline=(110, 130, 210) if night else (170, 140, 70))
            if night:
                moon_glyph(img, x + 13, mid)
            else:
                sun_glyph(d, x + 13, mid)
            txt((x + 26, mid), shift, 12, (200, 212, 250) if night else (250, 224, 150), "lm")
            for key, lab, wdt in (("low", "Low", 46), ("norm", "Normal", 62), ("high", "High", 46)):
                on = lab == pri
                x = cx[key]
                d.rounded_rectangle([x, ry + 1, x + wdt, ry + rh - 3], 4, fill=(84, 70, 44) if on else (44, 38, 34),
                                    outline=GOLD if on else (70, 62, 54))
                txt((x + wdt // 2, mid), lab, 12, TEXT if on else DIM, "mm")
            x = cx["pause"]
            d.rounded_rectangle([x, ry + 1, x + 66, ry + rh - 3], 4, fill=(110, 60, 50) if paused else (44, 38, 34),
                                outline=(180, 100, 80) if paused else (70, 62, 54))
            txt((x + 33, mid), "Resume" if paused else "Pause", 12, TEXT, "mm")
            if note:
                if note == "needs a lamp":
                    nw = int(U.tw(note, 13)) + 36
                    d.rounded_rectangle([cx["note"] - 4, ry + 1, cx["note"] + nw, ry + rh - 3], 4, fill=(60, 38, 26),
                                        outline=(214, 140, 72))
                    lamp = lamp_art("lantern", False)[0]
                    sm = lamp.crop((0, 0, lamp.width, 20)).resize((9, 10), Image.NEAREST)
                    img.alpha_composite(sm, (cx["note"] + 2, ry + 4))
                    txt((cx["note"] + 18, mid), note, 13, (244, 200, 140), "lm")
                else:
                    txt((cx["note"], mid), note, 13, RED if "short" in note else (130, 150, 220) if "lit" in note else DIM, "lm")
        ry += rh
    d.rounded_rectangle([px + 888, ch + 28, px + 894, bottom], 3, fill=(44, 38, 34))
    d.rounded_rectangle([px + 888, ch + 28, px + 894, ch + 28 + 250], 3, fill=(120, 106, 80))
    return img


# ---------------------------------------------------------------- 6. gain popup (Woodcutter, Quarry, Clear tool)
TINY5 = str(ASSETS / "ui" / "Tiny5.ttf")
POP_RISE, POP_HOLD = 10, 0.35  # px drifted over the life, share of the second the popup stays fully opaque


def popup_sprite(good, n):
    """Small icon (1x, with its own 1 px outline) and '+n' in Tiny5 16: white, 1 px dark outline, nothing else."""
    from PIL import ImageFont
    f = ImageFont.truetype(TINY5, 16)
    label = f"+{n}"
    tw_ = int(f.getlength(label))
    im = Image.new("RGBA", (14 + 1 + tw_ + 2, 16))
    im.alpha_composite(M.icon_v2(good), (0, 1))
    d = ImageDraw.Draw(im)
    d.fontmode = "1"  # no anti-aliasing: the pixel font stays on the pixel grid
    tx, ty = 16, -2
    for dx in (-1, 0, 1):
        for dy in (-1, 0, 1):
            if dx or dy:
                d.text((tx + dx, ty + dy), label, font=f, fill=M.OUTLINE)
    d.text((tx, ty), label, font=f, fill=(255, 255, 255, 255))
    return im


def popup_at(layer, sprite, anchor, t):
    """Draws the popup at life t (0..1): rises POP_RISE px, opaque for the first part, then fades out."""
    alpha = 1.0 if t < POP_HOLD else max(0.0, 1.0 - (t - POP_HOLD) / (1.0 - POP_HOLD))
    sp = sprite.copy()
    sp.putalpha(sp.getchannel("A").point(lambda v: int(v * alpha)))
    layer.alpha_composite(sp, (int(anchor[0] - sp.width // 2), int(anchor[1] - sp.height - round(POP_RISE * t))))


def popup_scene(kind):
    """Returns (scene, anchors): anchor is a point just above each producer's roof."""
    if kind == "pair":
        sc = Scene(7, 5, seed=2)
        sc.terrain({}, {(x, 4) for x in range(0, 7)})
        spots = {"wood": ("woodcutter", 1, 2), "stone": ("quarry", 4, 2)}
        props = [("pine_1", 14, 148), ("oak_green_1", 58, 150), ("pine_0", 30, 102), ("boulder_3", 6 * 32 + 6, 150),
                 ("boulder_1", 5 * 32 + 20, 156), ("boulder_2", 3 * 32 + 20, 100)]
    else:
        sc = Scene(10, 5, seed=6)
        sc.terrain({}, {(x, 4) for x in range(0, 10)})
        spots = {"wood1": ("woodcutter", 1, 2), "wood2": ("woodcutter", 3, 3), "stone": ("quarry", 6, 2),
                 "food": ("forager", 8, 2), "clear": None}
        props = [("pine_1", 10, 120), ("pine_2", 86, 90), ("boulder_3", 7 * 32 + 22, 150),
                 ("boulder_1", 5 * 32 + 24, 150), ("oak_green_2", 190, 150), ("stump_0", 5 * 32 + 16, 3 * 32 + 26),
                 ("sapling_0", 9 * 32 + 20, 3 * 32 + 26)]
    for n, x, y in props:
        sc.prop(n, x, y)
    anchors = {}
    for k, v in spots.items():
        if v is None:
            anchors[k] = (5 * 32 + 16, 3 * 32 + 8)  # a cleared tile, a stump left behind
            continue
        name, tx, ty = v
        o = sc.building(name, tx, ty, windows=None)
        e = MAN["buildings"][name]
        anchors[k] = (o[0] - e["base"][0] + e["w"] // 2, o[1] - e["h"] + 12)
    return sc, anchors


def frame_img(base, pops, scale, crop=None):
    lay = base.copy()
    for sprite, anchor, t in pops:
        popup_at(lay, sprite, anchor, t)
    if crop:
        lay = lay.crop(crop)
    return M.upscale(lay, scale)


def gain_popup():
    sc, an = popup_scene("pair")
    base = sc.render_plain()
    wood, stone = popup_sprite("wood", 3), popup_sprite("stone", 2)
    times = [(0.05, "start"), (0.5, "mid"), (0.9, "end")]
    W = 1470
    fa = [frame_img(base, [(wood, an["wood"], t), (stone, an["stone"], t)], 2) for t, _ in times]

    def crop_for(k):
        ax, ay = an[k]
        return (int(ax) - 40, int(ay) - 50, int(ax) + 40, int(ay) + 38)
    fb = {k: [frame_img(base, [(spr, an[k], t)], 4, crop_for(k)) for t, _ in times]
          for k, spr in (("wood", wood), ("stone", stone))}
    sc2, an2 = popup_scene("busy")
    base2 = sc2.render_plain()
    w3, w1, s2, f2 = popup_sprite("wood", 3), popup_sprite("wood", 1), popup_sprite("stone", 2), popup_sprite("food", 2)
    moments = [
        [(w3, an2["wood1"], 0.2), (s2, an2["stone"], 0.7)],
        [(w3, an2["wood2"], 0.5), (w1, an2["clear"], 0.1), (f2, an2["food"], 0.85)],
    ]
    fc = [frame_img(base2, m, 2) for m in moments]
    H = 90 + (fa[0].height + 60) + 2 * (fb["wood"][0].height + 14) + 90 + (fc[0].height + 110)
    img = Image.new("RGBA", (W, H), c("1c1a17"))
    d = ImageDraw.Draw(img, "RGBA")
    U.txt(d, (30, 16), "Gain popup: +N and a small icon, nothing else", 30, GOLD)
    U.txt(d, (30, 58), "Tiny5 16, white, 1 px dark outline (no anti-aliasing), icon at 1x. Rises 10 px in about 1 s, "
          "full for the first third, then fades. No glow, bounce, sparkle, shadow or colour change.", 14, DIM)
    y = 90
    U.txt(d, (30, y), "a) Game zoom (2x). Woodcutter +3 wood, Quarry +2 stone. Frames: start, mid, end of the second.",
          16, TEXT)
    y += 28
    for i, (fr, (t, lab)) in enumerate(zip(fa, times)):
        x = 30 + i * (fr.width + 14)
        img.alpha_composite(fr, (x, y))
        d.rectangle([x - 1, y - 1, x + fr.width, y + fr.height], outline=BORDER)
        U.txt(d, (x + 8, y + 8), f"{lab}  ({int(t * 1000)} ms)", 13, (255, 255, 255, 230))
    y += fa[0].height + 28
    U.txt(d, (30, y), "b) Same at 4x so the pixels show.", 16, TEXT)
    y += 28
    for k in ("wood", "stone"):
        for i, fr in enumerate(fb[k]):
            x = 30 + i * (fr.width + 14)
            img.alpha_composite(fr, (x, y))
            d.rectangle([x - 1, y - 1, x + fr.width, y + fr.height], outline=BORDER)
            U.txt(d, (x + 8, y + 8), times[i][1], 13, (255, 255, 255, 230))
        y += fb[k][0].height + 14
    y += 20
    U.txt(d, (30, y), "c) A busy village (2x): five producers, at most three popups at once. Left: Woodcutter and Quarry. "
          "Right: second Woodcutter, a cleared tile (+1 wood), Forager.", 16, TEXT)
    y += 28
    for i, fr in enumerate(fc):
        x = 30 + i * (fr.width + 14)
        img.alpha_composite(fr, (x, y))
        d.rectangle([x - 1, y - 1, x + fr.width, y + fr.height], outline=BORDER)
    return img.crop((0, 0, W, y + fc[0].height + 20))


# ---------------------------------------------------------------- main
def main():
    out = Path(sys.argv[1]) if len(sys.argv) > 1 else OUT_DEFAULT
    out.mkdir(parents=True, exist_ok=True)
    for name, fn in (("night_map", night_map), ("lamp_tiers", lamp_tiers), ("new_buildings", new_buildings_layout),
                     ("build_cards", build_cards), ("workforce_shift", workforce_shift),
                     ("gain_popup", gain_popup)):
        im = fn()
        im.convert("RGB").save(out / f"{name}.png")
        print("wrote", name, im.size)


if __name__ == "__main__":
    main()
