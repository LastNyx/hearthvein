"""Hearthvein nightlife + river mockups: six picture groups for Ben to approve (nothing is wired into the game).

Usage: python3 tools/mockups_nightlife.py [out_dir]     (default: .scratch/v1/mockups/nightlife)
Writes nl_build_cards.png, nl_build_cards_2.png, nl_town_night.png, nl_dimming_night.png, nl_moon_phases.png,
nl_river.png, nl_surge.png (1280x720 each).

Reuses by import (not edited): mockups_hud (new RTS HUD parts, fonts, panels, glyphs), mockups_night (Scene, tiles, Art,
lamps, Kiln, Grove, night tint), mockups_ui (clock dial art). New buildings are composed from existing building sprites
plus small hand-drawn pixel details (1 px dark outline), the way mockups_night did for the Kiln and the Grove.
Numbers that are not in data/ (costs, stock, workers, radii of the new things) are made up. Text is 1-bit PixelifySans
(headings) and Tiny5 (body); every sprite is nearest-neighbour at integer scales; no glow, no gradients, no glass.
"""
import math
import random
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw

sys.path.insert(0, str(Path(__file__).resolve().parent))
import mockups_hud as H  # noqa: E402
import mockups_night as N  # noqa: E402
import mockups_ui as U  # noqa: E402

M = U.M
T = 32
W, HT = 1280, 720
ROOT = Path(__file__).resolve().parent.parent
OUT_DEFAULT = ROOT / ".scratch" / "v1" / "mockups" / "nightlife"
c = M.hexc
P = M.P
INK, GOLD, DIM, FAINT, CYAN, RED, GREEN, AMBER, MOONC = H.INK, H.GOLD, H.DIM, H.FAINT, H.CYAN, H.RED, H.GREEN, H.AMBER, H.MOONC
EDGE, BTN, BTN_ON, SLOT = H.EDGE, H.BTN, H.BTN_ON, H.SLOT
txt, tw, panel, button, bar, up = H.txt, H.tw, H.panel, H.button, H.bar, H.up
PAL_DARK = (28, 26, 23)


# ---------------------------------------------------------------- new goods icons (12x12, same key and outline as the others)
M._ICON_KEY.update({"I": c("d6c8f0"), "J": c("aa96d2"), "K": c("6e6096"), "O": c("d6a050"), "U": c("96622c"),
                    "V": c("f0ce82"), "1": c("e6ecff")})
M._ICON_V2["bread"] = ["............", "............", "....OOOO....", "..OOVOVOOO..", ".OVOUOUOVOO.", ".OOOOOOOOOU.",
                       ".OOOOOOOOUU.", "..UOOOOOUU..", "...UUUUUU...", "............", "............", "............"]
M._ICON_V2["silk"] = ["....JJJJ....", "...JIIIIJ...", "..JIJKKJIJ..", "..JIK..KIJ..", "..JIK..KIJ..", "..JIJ..JIJ..",
                      "..JIK..KIJ..", "..JIJ..JIJ..", "..JIJKKJIJ..", "...JIIIIJ...", "....JJJJ....", "............"]
H._GLYPH["night"] = ["............", "....wwww....", "...wwww.....", "..wwww......", "..wwww...y..", "..wwww..yyy.",
                     "..wwww...y..", "..wwww......", "...wwww..y..", "....wwwwww..", "............", "............"]
H._GLYPH["crates"] = ["............", "............", ".bbbbbbbbbb.", ".bttttttttb.", ".btbbbbbbtb.", ".bttttttttb.",
                      ".bbbbbbbbbb.", "............", "............", "............", "............", "............"]


def gicon(kind, s=2):
    if kind in ("bread", "silk", "charcoal", "glowcap"):
        return up(M.icon_v2(kind), s)
    return H.icon(kind, s)


def put_gicon(img, kind, x, y, s=2):
    H.blit(img, gicon(kind, s), (x, y))


# ---------------------------------------------------------------- composing sprites from parts
class Comp:
    """A sprite canvas: existing sprites pasted in, then a hand-drawn detail layer with its own 1 px dark outline."""

    def __init__(self, w, h):
        self.w, self.h = w, h
        self.img = Image.new("RGBA", (w, h))
        self.em = Image.new("RGBA", (w, h))

    def paste(self, sp, x, y):
        self.img.alpha_composite(sp.convert("RGBA"), (x, y))

    def layer(self):
        return N.Art(self.w, self.h)

    def add(self, a, outline=True):
        o = M.outline(a.img).crop((1, 1, self.w + 1, self.h + 1)) if outline else a.img
        self.img.alpha_composite(o)
        self.em.alpha_composite(a.em)

    def finish(self):
        box = self.img.getbbox()
        im, em = self.img.crop(box), self.em.crop(box)
        return im, em, (im.width // 2, im.height - 2)


def dark(art):
    """The unlit look of an art tuple: no emissive pixels."""
    return art[0], Image.new("RGBA", art[0].size), art[2]


def recolor(img, rules):
    a = np.array(img)
    for test, col in rules:
        m = test(a) & (a[..., 3] > 0)
        a[m, 0], a[m, 1], a[m, 2] = col
    return Image.fromarray(a, "RGBA")


def star(a, x, y, col=(230, 236, 255, 255), n=1, em=True):
    a.px(x, y, col, em)
    for k in range(1, n + 1):
        for dx, dy in ((k, 0), (-k, 0), (0, k), (0, -k)):
            a.px(x + dx, y + dy, col if k == 1 else (150, 170, 235, 255), em)


def moth(a, x, y, col=(228, 232, 255, 255)):
    for dx, dy in ((0, 0), (2, 0), (1, 1)):
        a.px(x + dx, y + dy, col, True)
    a.px(x + 1, y, (170, 150, 210, 255), True)


# ---------------------------------------------------------------- the new buildings
def tavern_art(lit=True):
    cp = Comp(66, 60)
    cp.paste(H.bsprite("storehouse"), 2, 9)
    a = cp.layer()
    a.rect(1, 20, 2, 58, P["wood_d"])
    a.rect(1, 20, 1, 58, P["wood"])
    a.rect(1, 20, 14, 21, P["iron"])  # arm
    a.px(4, 22, P["iron_d"])
    a.px(13, 22, P["iron_d"])
    a.rect(3, 23, 14, 35, c("e4d8bc"))  # sign board
    a.rect(3, 23, 14, 23, P["wood_d"])
    a.rect(3, 35, 14, 35, P["wood_d"])
    a.rect(3, 23, 3, 35, P["wood_d"])
    a.rect(14, 23, 14, 35, P["wood_d"])
    a.rect(6, 28, 10, 33, c("e8a33a"), lit)  # mug
    a.rect(6, 28, 6, 33, c("ffd060"), lit)
    a.rect(6, 26, 10, 27, c("fff8e0"))  # foam
    a.px(5, 26, c("fff8e0"))
    a.px(11, 29, c("e8a33a"), lit)
    a.px(12, 29, c("e8a33a"), lit)
    a.px(12, 30, c("e8a33a"), lit)
    a.px(12, 31, c("e8a33a"), lit)
    a.px(11, 32, c("e8a33a"), lit)
    for bx in (48, 55):  # barrels
        a.rect(bx, 49, bx + 5, 57, P["wood"])
        a.rect(bx, 49, bx, 57, P["wood_l"])
        a.rect(bx + 5, 49, bx + 5, 57, P["wood_d"])
        a.rect(bx, 51, bx + 5, 51, P["iron"])
        a.rect(bx, 55, bx + 5, 55, P["iron"])
        a.rect(bx + 1, 48, bx + 4, 48, P["wood_l"])
    a.rect(60, 38, 62, 42, c("ffc65a"), lit)  # door lantern
    a.rect(61, 39, 61, 40, c("fff3c0"), lit)
    a.rect(60, 37, 62, 37, P["iron_d"])
    a.px(61, 36, P["iron_d"])
    cp.add(a)
    return cp.finish()


def bakery_art(lit=True):
    cp = Comp(58, 62)
    cp.paste(H.bsprite("kitchen"), 14, 22)
    a = cp.layer()
    # taller stone chimney over the kitchen's own stack, ember glow at its mouth
    a.rect(32, 10, 41, 23, P["stone"])
    a.rect(32, 10, 33, 23, P["stone_l"])
    a.rect(40, 10, 41, 23, P["stone_d"])
    for y in (13, 17, 21):
        a.rect(32, y, 41, y, P["stone_d"])
    a.rect(30, 8, 43, 9, P["iron_d"])
    a.rect(30, 8, 43, 8, P["iron"])
    if lit:
        a.rect(33, 6, 40, 7, c("e8651c"), True)
        a.rect(34, 5, 39, 6, c("ff9a30"), True)
        a.rect(35, 6, 38, 7, c("ffd060"), True)
        for (x, y) in ((36, 2), (40, 0), (33, 3), (38, 3)):
            a.px(x, y, c("ffae3c"), True)
    else:
        a.rect(33, 6, 40, 7, c("4a2a20"))
    # loaf sign on a post
    a.rect(2, 30, 3, 59, P["wood_d"])
    a.rect(2, 30, 2, 59, P["wood"])
    a.rect(2, 31, 12, 32, P["iron"])
    a.rect(4, 33, 13, 43, c("e4d8bc"))
    a.rect(4, 33, 13, 33, P["wood_d"])
    a.rect(4, 43, 13, 43, P["wood_d"])
    a.rect(4, 33, 4, 43, P["wood_d"])
    a.rect(13, 33, 13, 43, P["wood_d"])
    a.rect(6, 36, 11, 41, c("d6a050"))
    a.rect(7, 35, 10, 35, c("d6a050"))
    a.rect(6, 36, 11, 36, c("f0ce82"))
    a.px(7, 38, c("96622c"))
    a.px(9, 38, c("96622c"))
    a.px(8, 40, c("96622c"))
    a.rect(6, 41, 11, 41, c("96622c"))
    # a bench of loaves in front
    a.rect(34, 56, 54, 57, P["wood"])
    a.rect(34, 56, 54, 56, P["wood_l"])
    a.rect(36, 58, 37, 60, P["wood_d"])
    a.rect(51, 58, 52, 60, P["wood_d"])
    for lx in (36, 42, 48):
        a.rect(lx, 53, lx + 4, 55, c("d6a050"))
        a.rect(lx + 1, 52, lx + 3, 52, c("f0ce82"))
        a.px(lx + 2, 54, c("96622c"))
    cp.add(a)
    return cp.finish()


def market_art(lit=True):
    cp = Comp(92, 84)
    a0 = cp.layer()
    rng = random.Random(3)
    a0.ellipse([0, 54, 91, 82], P["dirt_d"])
    a0.ellipse([2, 54, 89, 79], P["dirt"])
    for _ in range(100):
        x, y = rng.randrange(6, 86), rng.randrange(58, 78)
        if ((x - 46) / 43) ** 2 + ((y - 67) / 11.5) ** 2 < 1:
            a0.px(x, y, rng.choice([P["dirt_l"], P["dirt_d"], c("5a4a36")]))
    cp.add(a0, outline=False)
    mk = recolor(H.bsprite("market"), [
        (lambda a: (a[..., 0] > 150) & (a[..., 1] < 90) & (a[..., 2] < 90), (98, 70, 160)),
        (lambda a: (a[..., 1] > 100) & (a[..., 2] > 100) & (a[..., 0] < 100), (48, 92, 150)),
    ])
    cp.paste(mk, 10, 15)
    a = cp.layer()
    # a rug in front of the stalls and crates of surplus
    a.rect(30, 66, 62, 74, c("5a3c8a"))
    a.rect(30, 66, 62, 66, c("d6a050"))
    a.rect(30, 74, 62, 74, c("d6a050"))
    for x in range(32, 62, 4):
        a.px(x, 70, c("d6a050"))
    for (x0, y0) in ((12, 60), (68, 62)):
        a.rect(x0, y0, x0 + 9, y0 + 8, P["wood"])
        a.rect(x0, y0, x0 + 9, y0 + 1, P["wood_l"])
        a.rect(x0, y0 + 8, x0 + 9, y0 + 8, P["wood_d"])
        a.rect(x0 + 1, y0 - 2, x0 + 3, y0 - 1, c("c84a3a"))
        a.rect(x0 + 5, y0 - 2, x0 + 8, y0 - 1, c("e0c060"))
    a.rect(78, 58, 84, 69, P["wood"])
    a.rect(78, 61, 84, 61, P["iron"])
    a.rect(78, 66, 84, 66, P["iron"])
    a.rect(78, 58, 78, 69, P["wood_l"])
    # lantern posts and a string of lanterns
    for px_ in (3, 88):
        a.rect(px_, 7, px_ + 1, 70, P["wood_d"])
        a.rect(px_, 7, px_, 70, P["wood"])
    a.rect(0, 3, 6, 9, c("ffc65a"), lit)
    a.rect(85, 3, 91, 9, c("ffc65a"), lit)
    a.rect(2, 4, 4, 8, c("fff3c0"), lit)
    a.rect(86, 4, 90, 8, c("fff3c0"), lit)
    xs = list(range(5, 88))
    pts = [(x, 10 + int(7 * (1 - ((x - 46) / 42.0) ** 2))) for x in xs]
    a.d.line(pts, fill=P["iron_d"])
    for x in range(14, 84, 11):
        y = 10 + int(7 * (1 - ((x - 46) / 42.0) ** 2))
        a.rect(x, y + 1, x + 2, y + 5, c("ffc65a"), lit)
        a.rect(x + 1, y + 2, x + 1, y + 4, c("fff3c0"), lit)
        a.px(x + 1, y + 6, P["iron_d"])
    cp.add(a)
    return cp.finish()


def observatory_art(lit=True, starlight=False):
    cp = Comp(74, 114)
    cp.paste(H.bsprite("observatory"), 6, 12)
    a = cp.layer()
    if lit:
        pale = (230, 236, 255, 255)
        for (x, y, n) in ((60, 6, 2), (68, 18, 1), (52, 2, 1), (70, 34, 1), (64, 28, 1)):
            star(a, x, y, pale, n)
    if starlight:
        for (x, y, n) in ((12, 8, 1), (30, 3, 2)):
            star(a, x, y, (200, 230, 255, 255), n)
    cp.add(a)
    return cp.finish()


def watch_art(lit=True):
    cp = Comp(54, 62)
    cp.paste(H.bsprite("lodge"), 4, 22)
    a = cp.layer()
    a.rect(42, 14, 43, 60, P["wood_d"])
    a.rect(42, 14, 42, 60, P["wood"])
    a.rect(35, 15, 44, 16, P["iron"])  # arm
    a.rect(36, 4, 45, 13, c("ffc65a"), lit)  # lantern cage
    a.rect(38, 5, 43, 12, c("ffe9a0"), lit)
    a.rect(39, 7, 42, 10, c("fff3c0"), lit)
    for x in (36, 40, 41, 45):
        a.rect(x, 4, x, 13, P["iron_d"])
    a.rect(35, 3, 46, 3, P["iron_d"])
    a.rect(38, 2, 43, 2, P["iron"])
    a.rect(35, 14, 46, 14, P["iron_d"])
    # bell on a bracket and a plank bench
    a.rect(1, 36, 7, 36, P["iron"])
    a.rect(3, 37, 5, 41, P["brass"])
    a.rect(2, 41, 6, 42, P["brass_l"])
    a.px(4, 43, P["iron_d"])
    a.rect(36, 55, 41, 56, P["wood"])
    a.rect(36, 57, 37, 59, P["wood_d"])
    cp.add(a)
    return cp.finish()


def loft_art(lit=True):
    cp = Comp(66, 62)
    cp.paste(H.bsprite("forager"), 4, 22)
    a = cp.layer()
    # pennant with a crescent
    a.rect(8, 6, 8, 24, P["wood_d"])
    a.d.polygon([(9, 7), (19, 9), (9, 13)], fill=c("aa96d2"))
    a.px(11, 9, c("fff3c0"))
    a.px(10, 10, c("fff3c0"))
    a.px(11, 11, c("fff3c0"))
    # silk drying rack
    for x in (42, 60):
        a.rect(x, 28, x + 1, 58, P["wood_d"])
        a.rect(x, 28, x, 58, P["wood"])
    a.rect(42, 28, 61, 29, P["wood_l"])
    cols = [c("d6c8f0"), c("aa96d2"), c("d6c8f0"), c("e6ecff"), c("aa96d2")]
    for i, x in enumerate((45, 49, 53, 56, 59)):
        ln = (18, 22, 16, 24, 14)[i]
        a.rect(x, 30, x + 1, 30 + ln, cols[i])
        a.rect(x + 1, 30, x + 1, 30 + ln, c("6e6096"))
        a.rect(x, 30 + ln, x + 1, 31 + ln, c("6e6096"))
    # jar lantern by the door and moths round the roof
    a.rect(38, 52, 41, 56, c("ffc65a"), lit)
    a.rect(39, 53, 40, 55, c("fff3c0"), lit)
    a.rect(38, 51, 41, 51, P["iron_d"])
    if lit:
        for (x, y) in ((24, 4), (32, 10), (14, 14), (44, 14), (36, 2), (50, 20), (4, 28)):
            moth(a, x, y)
    cp.add(a)
    return cp.finish()


def wheel_art(lit=True):
    cp = Comp(62, 50)
    a = cp.layer()
    cx, cy = 24, 28
    # stone abutment and the beam holding the axle
    a.rect(0, 16, 9, 47, P["stone"])
    a.rect(0, 16, 9, 18, P["stone_l"])
    a.rect(8, 16, 9, 47, P["stone_d"])
    for y in (24, 31, 38):
        a.rect(0, y, 9, y, P["stone_d"])
    a.rect(9, cy - 1, 62, cy + 1, P["wood"])
    a.rect(9, cy - 1, 62, cy - 1, P["wood_l"])
    a.rect(9, cy + 1, 62, cy + 1, P["wood_d"])
    # wheel: rim, spokes, paddles
    for ang in range(0, 360, 2):
        r = math.radians(ang)
        for rr, col in ((15, P["wood_d"]), (14, P["wood"]), (13, P["wood_l"] if ang < 180 else P["wood"])):
            a.px(round(cx + rr * math.cos(r)), round(cy + rr * math.sin(r)), col)
    for k in range(8):
        r = math.radians(k * 45 + 10)
        a.line([(cx, cy), (cx + 13 * math.cos(r), cy + 13 * math.sin(r))], P["wood"])
        r2 = math.radians(k * 45 + 11)
        a.line([(cx + 1, cy), (cx + 1 + 12 * math.cos(r2), cy + 12 * math.sin(r2))], P["wood_d"])
    for k in range(12):
        r = math.radians(k * 30 + 8)
        x0, y0 = cx + 15 * math.cos(r), cy + 15 * math.sin(r)
        x1, y1 = cx + 18 * math.cos(r), cy + 18 * math.sin(r)
        a.line([(x0, y0), (x1, y1)], P["wood_l"])
        a.px(round(x1), round(y1), P["wood_d"])
    a.ellipse([cx - 3, cy - 3, cx + 3, cy + 3], P["iron"])
    a.ellipse([cx - 1, cy - 1, cx + 1, cy + 1], P["iron_l"])
    # drive cog on the shaft
    gx = 52
    a.rect(gx - 3, cy - 4, gx + 3, cy + 4, P["iron"])
    a.rect(gx - 4, cy - 1, gx + 4, cy + 1, P["iron_l"])
    a.rect(gx - 1, cy - 5, gx + 1, cy + 5, P["iron_l"])
    a.px(gx, cy, P["iron_d"])
    # splash at the bottom of the wheel
    for (x, y) in ((cx - 8, 44), (cx - 4, 46), (cx + 2, 46), (cx + 7, 44), (cx - 11, 42), (cx + 10, 42), (cx, 47)):
        a.px(x, y, c("d8ecfa"))
    cp.add(a)
    return cp.finish()


def dock_art():
    cp = Comp(48, 46)
    a = cp.layer()
    for y in range(16, 44):  # a pier's shadow on the water
        a.px(28, y, c("2a5a94"))
    for y in range(2, 41):  # deck planks: a pier running south into the river
        col = P["wood_l"] if (y // 3) % 2 == 0 else P["wood"]
        a.rect(17, y, 28, y, P["wood_d"] if y % 3 == 2 else col)
    a.rect(17, 2, 17, 40, P["wood_d"])
    a.rect(28, 2, 28, 40, P["wood_d"])
    for y in (16, 34):  # posts with rope between
        a.rect(13, y, 16, y + 5, P["wood_d"])
        a.rect(29, y, 32, y + 5, P["wood_d"])
        a.rect(13, y, 14, y + 1, P["wood"])
        a.rect(29, y, 30, y + 1, P["wood"])
    a.line([(15, 22), (15, 34)], P["thatch_d"])
    a.line([(30, 22), (30, 34)], P["thatch_d"])
    a.rect(2, 3, 12, 10, c("d8b864"))  # a stack of planks on the bank
    for y in (5, 8):
        a.rect(2, y, 12, y, c("b08a40"))
    a.rect(2, 3, 12, 3, c("e8cc80"))
    a.d.ellipse([20, 28, 25, 33], fill=P["thatch"])  # rope coil
    a.d.ellipse([21, 29, 23, 31], fill=P["thatch_d"])
    a.rect(30, 3, 30, 15, P["wood_d"])  # teal pennant on the first post: marks a pair
    a.d.polygon([(31, 4), (38, 6), (31, 9)], fill=c("3cbfa0"))
    for (x, y) in ((12, 41), (31, 42), (14, 43), (26, 44)):
        a.px(x, y, c("d8ecfa"))
    cp.add(a)
    return cp.finish()


def boat_art(cargo=True):
    cp = Comp(38, 20)
    a = cp.layer()
    a.d.polygon([(2, 9), (30, 9), (36, 6), (31, 15), (5, 15)], fill=P["wood"])
    a.rect(3, 9, 30, 9, P["wood_l"])
    a.rect(6, 14, 30, 15, P["wood_d"])
    for x in range(8, 30, 5):
        a.rect(x, 11, x, 13, P["wood_d"])
    if cargo:
        for i, y in enumerate((7, 5, 3)):
            a.rect(6, y, 24, y + 1, c("d8b864"))
            a.rect(6, y + 1, 24, y + 1, c("b08a40"))
        a.rect(6, 3, 24, 3, c("e8cc80"))
    a.rect(33, 2, 33, 8, P["wood_d"])  # bow lantern post
    a.rect(32, 0, 34, 2, c("ffc65a"))
    cp.add(a)
    return cp.finish()


def wagon_art(lit=True):
    cp = Comp(54, 44)
    a = cp.layer()
    a.rect(6, 22, 40, 31, P["wood"])  # bed
    a.rect(6, 22, 40, 22, P["wood_l"])
    a.rect(6, 31, 40, 31, P["wood_d"])
    for x in (12, 20, 28, 36):
        a.rect(x, 23, x, 30, P["wood_d"])
    a.d.pieslice([4, 4, 42, 44], 180, 360, fill=c("d9c49a"))  # canvas hood
    a.d.pieslice([4, 4, 42, 44], 180, 360, outline=c("b39d72"))
    for x in (12, 20, 28, 36):
        a.line([(x, 14), (x, 22)], c("b39d72"))
    a.rect(6, 22, 40, 23, c("5a3c8a"))
    a.rect(14, 18, 32, 19, c("98aa96"))
    a.rect(16, 24, 30, 28, c("0e0c0a"))  # open back with crates
    a.rect(17, 25, 21, 28, P["wood_l"])
    a.rect(23, 25, 29, 28, P["wood_l"])
    a.px(19, 26, P["iron_l"])
    a.px(26, 26, P["iron_l"])
    for wx in (12, 34):  # wheels
        a.ellipse([wx - 6, 26, wx + 6, 38], P["wood_d"])
        a.ellipse([wx - 4, 28, wx + 4, 36], P["wood"])
        a.ellipse([wx - 1, 31, wx + 1, 33], P["iron"])
        a.line([(wx - 4, 32), (wx + 4, 32)], P["wood_d"])
        a.line([(wx, 28), (wx, 36)], P["wood_d"])
    a.rect(41, 27, 52, 28, P["wood_d"])  # shaft, no horse: parked
    a.rect(50, 28, 52, 30, P["wood"])
    a.rect(41, 11, 42, 22, P["wood_d"])  # lantern post
    a.rect(39, 5, 44, 11, c("ffc65a"), lit)
    a.rect(40, 6, 43, 10, c("fff3c0"), lit)
    cp.add(a)
    return cp.finish()


def gate_art(lit=True):
    cp = Comp(56, 52)
    a = cp.layer()
    for x0 in (4, 38):
        a.rect(x0, 14, x0 + 11, 49, P["stone"])
        a.rect(x0, 14, x0 + 1, 49, P["stone_l"])
        a.rect(x0 + 10, 14, x0 + 11, 49, P["stone_d"])
        for y in range(20, 49, 7):
            a.rect(x0, y, x0 + 11, y, P["stone_d"])
        a.rect(x0 - 1, 12, x0 + 12, 14, P["stone_l"])
        a.rect(x0 + 2, 3, x0 + 9, 11, c("ffc65a"), lit)
        a.rect(x0 + 4, 4, x0 + 7, 10, c("fff3c0"), lit)
        a.rect(x0 + 1, 2, x0 + 10, 2, P["iron_d"])
    a.rect(16, 16, 37, 21, P["wood"])  # lintel beam with a pennant
    a.rect(16, 16, 37, 16, P["wood_l"])
    a.rect(16, 21, 37, 21, P["wood_d"])
    a.rect(24, 22, 29, 28, c("5a3c8a"))
    a.rect(26, 24, 27, 26, c("d6a050"))
    cp.add(a)
    return cp.finish()


def lantern_walker(lit=True):
    """The Night Watch walker: an existing walker cell in a watchman's blue-grey with a lantern held out front."""
    w = N.load("walkers/walkers.png")
    row = 21 * 4 + 3
    cell = w.crop((16, row * 20, 32, row * 20 + 20))
    cp = Comp(30, 28)
    cp.paste(cell, 6, 6)
    a = cp.layer()
    a.rect(23, 14, 23, 18, P["iron_d"])  # stick
    a.rect(21, 18, 25, 23, c("ffc65a"), lit)
    a.rect(22, 19, 24, 22, c("fff3c0"), lit)
    a.rect(21, 17, 25, 17, P["iron_d"])
    a.rect(21, 24, 25, 24, P["iron_d"])
    a.px(23, 16, P["iron_d"])
    cp.add(a)
    im, em, _ = cp.finish()
    return im, em, (im.width // 2 - 3, im.height - 2)


# ---------------------------------------------------------------- terrain, scene helpers
def _conn(roads, x, y):
    m = 0
    for bit, (dx, dy) in zip((1, 2, 4, 8), ((0, -1), (1, 0), (0, 1), (-1, 0))):
        if (x + dx, y + dy) in roads:
            m |= bit
    return m


def _tint(img, mul):
    a = np.array(img).astype(np.float32)
    a[..., :3] *= np.array(mul, dtype=np.float32)
    return Image.fromarray(np.clip(a, 0, 255).astype(np.uint8), "RGBA")


def terrain(sc, kinds, roads=(), water=(), flood=(), silt=(), levee=(), veins=()):
    """Grass/forest/rock tiles like Scene.terrain, plus river water with banks, shallow flood, silt, veins, levee."""
    roads, water, flood, silt, levee, veins = set(roads), set(water), set(flood), set(silt), set(levee), set(veins)
    for y in range(sc.th):
        for x in range(sc.W // T):
            p = (x, y)
            k = kinds.get(p, "grass")
            if p in water:
                t = N.tile_img("terrain/water.png", N.pick([0, 0, 1, 1, 2, 2, 3, 3, 4], x, y))
            elif p in veins:
                t = N.tile_img("terrain/lumen_vein.png", N.pick([0, 1, 2, 3], x, y))
            elif k == "forest":
                t = N.tile_img("terrain/forest.png", N.pick([0, 1, 2, 3], x, y))
            elif k == "rock":
                t = N.tile_img("terrain/rock.png", N.pick([0, 1, 2, 3], x, y))
            else:
                t = N.tile_img("terrain/grass.png", N.pick([0, 0, 1, 1, 2, 2, 2, 3, 4], x, y))
            sc.day.alpha_composite(t, (x * T, y * T))
            if p in silt:
                s = N.tile_img("terrain/fertile_soil.png", N.pick([0, 1, 2, 3], x, y))
                s = _tint(s, (0.66, 0.52, 0.40))
                sc.day.alpha_composite(s, (x * T, y * T))
                rr = random.Random(x * 31 + y)
                ds = ImageDraw.Draw(sc.day)
                for _ in range(26):
                    ds.point((x * T + rr.randrange(T), y * T + rr.randrange(T)), fill=(60, 42, 26, 255))
                for _ in range(8):
                    xx, yy = x * T + rr.randrange(2, T - 6), y * T + rr.randrange(T)
                    ds.line([(xx, yy), (xx + 4, yy)], fill=(120, 92, 62, 255))
            if p in flood:
                wt = N.tile_img("terrain/water.png", N.pick([0, 1, 2, 3, 4], x, y)).copy()
                wt.putalpha(150)
                sc.day.alpha_composite(wt, (x * T, y * T))
                rr = random.Random(x * 17 + y * 3)
                ds = ImageDraw.Draw(sc.day)
                for _ in range(5):
                    xx, yy = x * T + rr.randrange(2, T - 6), y * T + rr.randrange(2, T - 2)
                    ds.line([(xx, yy), (xx + 4, yy)], fill=(190, 222, 242, 255))
                for dx, dy, bx0, by0, bx1, by1 in ((0, -1, 0, 0, T - 1, 0), (0, 1, 0, T - 1, T - 1, T - 1),
                                                   (-1, 0, 0, 0, 0, T - 1), (1, 0, T - 1, 0, T - 1, T - 1)):
                    if (x + dx, y + dy) not in flood and (x + dx, y + dy) not in water:
                        ds.rectangle([x * T + bx0, y * T + by0, x * T + bx1, y * T + by1], fill=(176, 216, 240, 255))
            if p in roads:
                m = _conn(roads, x, y)
                row = ((x * 31 + y * 17) >> 1) & 1
                sc.day.alpha_composite(N.load("roads/dirt.png").crop((m * T, row * T, m * T + T, row * T + T)),
                                       (x * T, y * T))
    ds = ImageDraw.Draw(sc.day)
    for (x, y) in water:  # banks: dark edge, brown bank, light foam, wobbling by tile
        for dx, dy in ((0, -1), (1, 0), (0, 1), (-1, 0)):
            if (x + dx, y + dy) in water or not (0 <= x + dx < sc.W // T and 0 <= y + dy < sc.th):
                continue
            for i in range(T):
                wdt = 3 + ((i * 5 + x * 7 + y * 3) // 4) % 2
                for j in range(wdt + 2):
                    col = [(78, 54, 36), (128, 92, 62), (150, 112, 78), (150, 112, 78)][j] if j < min(wdt, 4) else \
                        ((176, 216, 240) if (i + j) % 5 else (130, 184, 226))
                    if dx == 0:
                        pxy = (x * T + i, y * T + (j if dy < 0 else T - 1 - j))
                    else:
                        pxy = (x * T + (j if dx < 0 else T - 1 - j), y * T + i)
                    ds.point(pxy, fill=col + (255,))
    for (x, y) in levee:
        levee_tile(sc, x, y, (x - 1, y) in levee, (x + 1, y) in levee)


def levee_tile(sc, x, y, left, right):
    """A stone wall along the bank (water to the north) on a low earth bank: it connects to neighbours like a road."""
    ds = ImageDraw.Draw(sc.day)
    ox, oy = x * T, y * T
    dk = (58, 80, 44, 255)
    ds.rectangle([ox, oy + 14, ox + T - 1, oy + 21], fill=dk)  # earth bank behind the wall
    ds.rectangle([ox, oy + 14, ox + T - 1, oy + 15], fill=(88, 120, 62, 255))
    ds.rectangle([ox, oy + 3, ox + T - 1, oy + 17], fill=P["stone"])
    ds.rectangle([ox, oy + 3, ox + T - 1, oy + 6], fill=P["stone_l"])  # cap
    ds.rectangle([ox, oy + 7, ox + T - 1, oy + 7], fill=P["stone_d"])
    for k, (y0, y1) in enumerate(((8, 11), (12, 15))):  # two brick courses with staggered joints
        ds.rectangle([ox, oy + y1, ox + T - 1, oy + y1], fill=P["stone_d"])
        for jx in range(4 if k else 0, T, 8):
            ds.rectangle([ox + jx, oy + y0, ox + jx, oy + y1], fill=P["stone_d"])
    ds.rectangle([ox, oy + 16, ox + T - 1, oy + 17], fill=(70, 66, 60, 255))  # shadow at the foot
    ds.rectangle([ox, oy + 2, ox + T - 1, oy + 2], fill=(40, 36, 32, 255))  # dark outline against the water
    if not left:
        ds.rectangle([ox, oy + 3, ox + 1, oy + 17], fill=P["stone_d"])
    if not right:
        ds.rectangle([ox + T - 2, oy + 3, ox + T - 1, oy + 17], fill=P["stone_d"])


def place(sc, art, tx, ty, fw, fh, windows=None, dy=0, dx=0, shadow=True, shadow_w=None):
    """Like Scene.custom, but a lit/dark window recolour and offsets are possible."""
    img, em, base = art
    origin = ((tx + fw / 2) * T + dx, (ty + fh) * T - 3 + dy)
    if windows:
        img, em2 = sc._windows(img, windows)
        if em2 is not None:
            em = em.copy()
            em.alpha_composite(em2)
        else:
            em = None
    sh = None
    if shadow:
        w = int((shadow_w or img.width) * 0.92)
        shw = Image.new("RGBA", (w + 6, 14))
        ImageDraw.Draw(shw).ellipse([0, 0, w + 5, 13], fill=(4, 6, 18, 84))
        sh = lambda o, shw=shw: (shw, (int(o[0] - shw.width // 2), int(o[1] - 7)))
    sc.add(img, origin, base, shadow=sh, emissive=em)
    return origin


def put(sc, name, tx, ty, lit=True):
    return sc.building(name, tx, ty, windows="lit" if lit else "dark")


def foot(tx, ty, fw=1, fh=1):
    return ((tx + fw / 2) * T, (ty + fh) * T - 3)


# ---------------------------------------------------------------- night render: round stepped light, gloom, glow tiles
WARM = (255, 160, 70)
N.LAMP_LIGHT.update({"market": (1.0, 0.78, 0.45), "glow": (0.45, 1.0, 0.85)})


def circle(tx, ty, r, kind="lantern", at=None):
    cx, cy = at if at else (tx * T + 16, ty * T + 16)
    return (cx, cy, r * T, N.LAMP_LIGHT[kind], {"lantern": WARM, "brazier": (255, 130, 50), "lumen": (127, 224, 240),
                                                "market": (255, 190, 90), "glow": (60, 220, 190)}.get(kind, WARM))


def is_lit(circles, x, y):
    return any(math.hypot(x - cx, y - cy) <= R for cx, cy, R, _, _ in circles)


def gloom_map(tw_, th_, forest, circles, extra_lit=(), depth=6):
    """Tile -> depth (0 = forest) over unlit tiles, 4-neighbour creep from the forest edge, stopping at light."""
    extra_lit = set(extra_lit)
    out = {p: 0 for p in forest}
    front = list(forest)
    d = 0
    while front and d < depth:
        d += 1
        nxt = []
        for (x, y) in front:
            for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                p = (x + dx, y + dy)
                if p in out or not (0 <= p[0] < tw_ and 0 <= p[1] < th_) or p in extra_lit:
                    continue
                if is_lit(circles, p[0] * T + 16, p[1] * T + 16):
                    continue
                out[p] = d
                nxt.append(p)
        front = nxt
    return out


def render_map(sc, night=False, circles=(), glow=(), gloom=None, specks=()):
    day, em = sc.render_day()
    if not night:
        return day.convert("RGB")
    base = N.to_arr(day)
    out = base * N.NIGHT
    yy, xx = np.mgrid[0:sc.H, 0:sc.W]
    for cx, cy, R, mul, warm in circles:  # three concentric flat rings, low alpha, warm
        dist = np.hypot(xx - cx, yy - cy)
        for frac in (1.0, 0.72, 0.45):
            m = (dist < R * frac)[..., None] * 0.34
            out = out * (1 - m) + base * np.array(mul) * m
            out = out + m * (np.array(warm) / 255.0) * 0.14
    for tiles, mul, a in glow:  # flat tile steps (the river's glow)
        mk = np.zeros((sc.H, sc.W), dtype=np.float32)
        for (x, y) in tiles:
            mk[y * T:(y + 1) * T, x * T:(x + 1) * T] = a
        m = mk[..., None]
        out = out * (1 - m) + base * np.array(mul) * m
    if gloom:
        steps = [0.78, 0.66, 0.54, 0.42, 0.32, 0.22, 0.14]
        col = np.array([26, 8, 40], dtype=np.float32) / 255.0
        for (x, y), dd in gloom.items():
            a = steps[min(dd, len(steps) - 1)]
            blk = out[y * T:(y + 1) * T, x * T:(x + 1) * T]
            if dd >= 3 and dd == max(gloom.values()):  # the creeping front is ragged: a checker of 2x2 blocks
                ck = (((np.arange(T)[None, :] // 2) + (np.arange(T)[:, None] // 2)) % 2 == 0)[..., None]
                aa = np.where(ck, a, a * 0.5)
            else:
                aa = a
            out[y * T:(y + 1) * T, x * T:(x + 1) * T] = blk * (1 - aa) + col * aa
    img = N.to_img(out)
    img.alpha_composite(em)
    d = ImageDraw.Draw(img)
    for (x, y, col) in specks:
        d.point((x, y), fill=col)
    return img.convert("RGB")


def to_big(img1x):
    return up(img1x, 2).crop((0, 0, W, HT)).convert("RGB")


def brackets(d, tx, ty, fw, fh, col=GOLD):
    x0, y0 = tx * 64 - 4, ty * 64 - 4
    x1, y1 = (tx + fw) * 64 + 4, (ty + fh) * 64 + 4
    for (cx, cy, sx, sy) in ((x0, y0, 1, 1), (x1, y0, -1, 1), (x0, y1, 1, -1), (x1, y1, -1, -1)):
        d.rectangle([min(cx, cx + sx * 16), cy if sy > 0 else cy - 3, max(cx, cx + sx * 16), cy + (3 if sy > 0 else 0)], fill=col)
        d.rectangle([cx if sx > 0 else cx - 3, min(cy, cy + sy * 16), cx + (3 if sx > 0 else 0), max(cy, cy + sy * 16)], fill=col)


def tag(d, cx, cy, text, col=INK, edge=EDGE, ic=None, img=None, size=14, up=False):
    """A small map tag centred on (cx, cy): panel, optional icon, 1-bit text; a pointer tick under (or over) it."""
    w = int(tw(text, size, True)) + 16 + (22 if ic else 0)
    box = (int(cx - w / 2), int(cy - 12), int(cx + w / 2), int(cy + 12))
    panel(d, box, edge=edge, r=4)
    x = box[0] + 8
    if ic:
        put_gicon(img, ic, x, box[1] + 5, 1)
        x += 22
    txt(d, (x, cy), text, size, col, "lm", True)
    if up:
        d.polygon([(cx - 4, box[1] + 1), (cx + 4, box[1] + 1), (cx, box[1] - 5)], fill=PANEL_FILL)
        d.line([(cx - 4, box[1]), (cx, box[1] - 5), (cx + 4, box[1])], fill=edge, width=2)
    else:
        d.polygon([(cx - 4, box[3] - 1), (cx + 4, box[3] - 1), (cx, box[3] + 5)], fill=PANEL_FILL)
        d.line([(cx - 4, box[3]), (cx, box[3] + 5), (cx + 4, box[3])], fill=edge, width=2)
    return box


PANEL_FILL = (24, 20, 18, 235)


# ---------------------------------------------------------------- HUD parts (parameterised copies of the new HUD's)
def hud_resources(img, d, lumen=("36", "+9", GREEN, False)):
    items = [("pop", "62/70", "3 idle", INK, DIM, 84), ("food", "142", "+6", INK, GREEN, 68), ("wood", "88", "+4", INK, GREEN, 68),
             ("stone", "64", "+3", INK, GREEN, 68), ("lumen", lumen[0], lumen[1], INK, lumen[2], 76 if lumen[3] else 68),
             ("gold", "318", "+12", INK, GREEN, 72), ("planks", "12", "+1", RED, GREEN, 68)]
    total = sum(i[5] for i in items) + 88
    x0 = W - 8 - total - 12
    panel(d, (x0, 8, W - 8, 52))
    x = x0 + 12
    for k, val, delta, vc, dc, w in items:
        H.put_icon(img, k, x, 12, 2)
        txt(d, (x + 32, 22), val, 16, vc, "lm")
        txt(d, (x + 32, 40), delta, 12, dc, "lm", True)
        if k == "lumen" and lumen[3]:  # a green pixel plus after the number
            px = x + 32 + int(tw(val, 16)) + 6
            d.rectangle([px + 3, 16, px + 5, 24], fill=GREEN)
            d.rectangle([px, 19, px + 8, 21], fill=GREEN)
        if k == "planks":
            d.rectangle([x + w - 12, 12, x + w - 8, 15], fill=GOLD)
            d.rectangle([x + w - 11, 16, x + w - 9, 18], fill=GOLD)
            d.rectangle([x + w - 10, 19, x + w - 10, 21], fill=(190, 150, 60))
        x += w
    gx = W - 8 - 12 - 74
    button(d, (gx, 14, gx + 74, 46), "", hover=False)
    txt(d, (gx + 8, 30), "Goods", 16, INK, "lm")
    d.rectangle([gx + 58, 22, gx + 68, 36], fill=(24, 20, 18), outline=GOLD)
    txt(d, (gx + 64, 30), "E", 12, GOLD, "mm", True)


def dial_art2(hour, phase, dark_hour=None, moon_t=None):
    """The clock dial like U.dial_art, with the moon drawn in its phase (0 new .. 4 full .. 7 waning)."""
    h = hour % 24
    night = dark_hour if dark_hour is not None else not 6 <= h < 18
    sky = U.sky_colour(h) if not dark_hour else (18, 24, 52)
    if dark_hour:
        sky = (18, 24, 52)
    elif night:
        sky = U.sky_colour(h)
    im = Image.new("RGBA", (28, 16), sky + (255,))
    d = ImageDraw.Draw(im)
    if night:
        rng = random.Random(7)
        for _ in range(7):
            im.putpixel((rng.randrange(1, 27), rng.randrange(1, 8)), (200, 210, 240, 255))
    t = moon_t if moon_t is not None else (((h - 18) % 24) / 12 if night else (h - 6) / 12)
    for i in range(1, 12):
        a = math.pi * i / 12
        im.putpixel((round(14 - 11 * math.cos(a)), round(12.5 - 9.5 * math.sin(a))), tuple(min(255, v + 40) for v in sky) + (255,))
    a = math.pi * t
    cx, cy = 14 - 11 * math.cos(a), 12.5 - 9.5 * math.sin(a)
    if night:
        ic, jc = round(cx), round(cy)
        for dy in range(-3, 4):
            for dx in range(-3, 4):
                u, v = dx / 3.2, dy / 3.2
                if u * u + v * v > 1.05:
                    continue
                w_ = math.sqrt(max(0.0, 1 - v * v))
                th = phase * math.pi / 4
                tt = math.cos(th) * w_
                if phase <= 4:
                    lit = u >= tt + 0.0001 if phase > 0 else False
                else:
                    th2 = (8 - phase) * math.pi / 4
                    lit = u <= -math.cos(th2) * w_ + 0.0001
                if phase == 4:
                    lit = True
                px_, py_ = ic + dx, jc + dy
                if 0 <= px_ < 28 and 0 <= py_ < 16:
                    im.putpixel((px_, py_), (222, 230, 252, 255) if lit else (52, 60, 98, 255))
    else:
        d.ellipse([cx - 3.4, cy - 3.4, cx + 3.4, cy + 3.4], fill=(255, 190, 70, 255))
        d.ellipse([cx - 2.4, cy - 2.4, cx + 2.4, cy + 2.4], fill=(255, 232, 130, 255))
    d.rectangle([0, 13, 27, 15], fill=(44, 66, 40, 255))
    d.line([(0, 13), (27, 13)], fill=(78, 110, 60, 255))
    return im


def dial2(hour, phase, s=2, **kw):
    im = up(dial_art2(hour, phase, **kw), s)
    ImageDraw.Draw(im).rectangle([0, 0, im.width - 1, im.height - 1], outline=(90, 80, 70, 255), width=2)
    return im


def hud_clock(img, d, hour, label, sub="Year 2, Summer", speed=1, phase=4, note=None, note_col=MOONC, **kw):
    x0 = W - 8 - 348
    panel(d, (x0, 58, W - 8, 100))
    img.paste(dial2(hour, phase, 2, **kw).convert("RGB"), (x0 + 8, 62))
    txt(d, (x0 + 72, 70), label, 16, INK, "lm")
    txt(d, (x0 + 72, 88), sub, 12, DIM, "lm", True)
    bx = x0 + 200
    for i, lab in enumerate(["||", "1x", "2x", "3x"]):
        b = (bx + i * 36, 64, bx + i * 36 + 32, 94)
        on = i == speed
        button(d, b, "", on=on)
        cx, cy = (b[0] + b[2]) // 2, (b[1] + b[3]) // 2
        if lab == "||":
            d.rectangle([cx - 5, cy - 6, cx - 2, cy + 6], fill=INK)
            d.rectangle([cx + 2, cy - 6, cx + 5, cy + 6], fill=INK)
        else:
            txt(d, (cx + 1, cy), lab, 16, GOLD if on else INK, "mm")
    if note:
        w = int(tw(note, 14, True)) + 34
        box = (W - 8 - w, 104, W - 8, 126)
        panel(d, box, edge=note_col, r=4)
        H.blit(img, H.icon("moon", 1), (box[0] + 8, 108))
        txt(d, (box[0] + 28, 115), note, 14, note_col, "lm", True)


def hud_objectives(img, d, lines, people=(62, 100), gold=(318, 500), spire="not built"):
    panel(d, (8, 8, 322, 200))
    txt(d, (20, 22), "Objectives", 16, GOLD, "lm")
    button(d, (294, 14, 314, 34), "", hover=False)
    d.rectangle([299, 23, 309, 24], fill=INK)
    txt(d, (20, 44), "Town -> City: gate parts", 12, DIM, "lm", True)
    y = 56
    for k, lab, (a, b), bc in (("pop", "People", people, GREEN), ("gold", "Gold", gold, GOLD)):
        H.put_icon(img, k, 18, y, 2)
        txt(d, (54, y + 8), lab, 12, INK, "lm", True)
        txt(d, (312, y + 8), f"{a} / {b}", 12, INK, "rm", True)
        bar(d, (54, y + 18, 312, y + 24), a / b, bc)
        y += 34
    H.put_icon(img, "lumen", 18, y, 2)
    txt(d, (54, y + 8), "Lumen Spire", 12, INK, "lm", True)
    txt(d, (312, y + 8), spire, 12, RED, "rm", True)
    d.rectangle([54, y + 18, 312, y + 24], fill=H.BAR_BG, outline=(14, 12, 10))
    y += 36
    d.line([(18, y), (312, y)], fill=EDGE)
    (ic, t1, col1), t2 = lines
    if ic in H._GLYPH:
        H.blit(img, H.glyph(ic), (18, y + 6))
    else:
        H.put_icon(img, ic, 18, y + 6, 2)
    txt(d, (54, y + 14), t1, 16, col1, "lm")
    txt(d, (54, y + 32), t2, 12, DIM, "lm", True)


def portrait2(img, d, sp, scale=2, sky=(41, 54, 36)):
    box = (242, 578, 374, 706)
    d.rounded_rectangle(box, 4, fill=sky, outline=(14, 12, 10), width=2)
    s = up(sp, scale)
    tile = Image.new("RGBA", (128, 124))
    tile.alpha_composite(s, (64 - s.width // 2, 122 - s.height)) if s.height <= 124 else \
        tile.alpha_composite(s.crop((0, s.height - 124, s.width, s.height)), (64 - s.width // 2, 0))
    img.paste(tile.convert("RGBA"), (244, 580), tile)


def hud_selection(img, d, sp, name, tier, sub, workers, status, makes, buffers, scale=2, note=None, priority="Normal",
                  sky=(41, 54, 36)):
    """workers: list of (kind 'day'|'night', n, of, text)  makes: list of (label, icon, main, small)  buffers: (lab, icon, have, cap, col)"""
    panel(d, (H.SELX0, 566, H.SELX1, 714))
    portrait2(img, d, sp, scale, sky)
    txt(d, (388, 592), name, 24, GOLD, "lm")
    if tier:
        cw = tw(tier, 12, True)
        cx = 388 + tw(name, 24) + 12
        d.rounded_rectangle([cx, 582, cx + cw + 12, 600], 4, fill=BTN_ON, outline=GOLD)
        txt(d, (cx + 6, 591), tier, 12, GOLD, "lm", True)
    txt(d, (388, 614), sub, 12, DIM, "lm", True)
    txt(d, (388, 636), "Workers", 12, FAINT, "lm", True)
    for i, (kind, n, of, text) in enumerate(workers):
        y = 646 + i * 20
        if kind == "day":
            d.ellipse([388, y, 400, y + 12], fill=(255, 190, 70))
            d.ellipse([390, y + 2, 398, y + 10], fill=(255, 232, 130))
            lab = "Day"
        else:
            H.blit(img, H.icon("moon", 1), (387, y - 2))
            lab = "Night"
        txt(d, (408, y + 6), lab, 12, INK, "lm", True)
        col = GREEN if n == of else (RED if n == 0 else AMBER)
        H.pips(d, 448, y, n, of, col)
        txt(d, (448 + of * 16 + 8, y + 6), f"{n}/{of}", 12, col, "lm", True)
        if text:
            txt(d, (448 + of * 16 + 40, y + 6), text, 12, DIM, "lm", True)
    scol, stext = status
    d.rectangle([388, 694, 394, 700], fill=scol)
    txt(d, (402, 697), stext, 12, scol, "lm", True)
    bx = 570
    for i, (lab, ic, main, small) in enumerate(makes):
        y = 586 + i * 24
        txt(d, (bx, y), lab, 12, FAINT, "lm", True)
        put_gicon(img, ic, bx + 58, y - 10, 2)
        txt(d, (bx + 94, y), main, 16, INK, "lm")
        if small:
            txt(d, (H.SELX1 - 12, y), small, 12, DIM, "rm", True)
    d.line([(bx, 636), (H.SELX1 - 12, 636)], fill=EDGE)
    for i, (lab, ic, have, cap, col) in enumerate(buffers):
        y = 644 + i * 22
        txt(d, (bx, y + 8), lab, 12, FAINT, "lm", True)
        put_gicon(img, ic, bx + 34, y + 1, 1)
        bar(d, (bx + 56, y + 3, bx + 276, y + 13), have / cap, col)
        txt(d, (bx + 286, y + 8), f"{have} / {cap}", 12, INK, "lm", True)
    txt(d, (bx, 692), "Priority", 12, FAINT, "lm", True)
    x = bx + 50
    for lab, w, on in (("Low", 46, False), ("Normal", 66, True), ("High", 46, False)):
        button(d, (x, 682, x + w, 706), lab, on=on, size=12, body=True, col=INK if on else DIM)
        x += w + 4
    x += 10
    button(d, (x, 682, x + 62, 706), "Pause", size=12, body=True)
    if note:
        nx, text, col = note
        w = int(tw(text, 12, True)) + 24
        y0 = 586 + len(makes) * 24 - 10
        d.rounded_rectangle([bx, y0, bx + w, y0 + 20], 4, fill=(40, 34, 30), outline=col)
        txt(d, (bx + 12, y0 + 10), text, 12, col, "lm", True)


def hud_notice(img, d, text, y=520, x=H.SELX0, edge=CYAN, icon=("moon", None), tcol=INK):
    w = int(tw(text, 16, True)) + 56
    panel(d, (x, y, x + w, y + 38), edge=edge)
    kind, glyph_kind = icon
    if glyph_kind:
        H.blit(img, H.glyph(glyph_kind), (x + 10, y + 7))
    else:
        put_gicon(img, kind, x + 10, y + 5, 2)
    txt(d, (x + 46, y + 19), text, 16, tcol, "lm", True)
    return w


NIGHT_CELLS = []


def top_grid(img, d, hover=None):
    """The top-level build grid; 'Night' takes the last slot (Help stays on F1 only)."""
    H.draw_grid_frame(d, "Build", "R road   X demolish")
    cats = [t for t in H.TOP if t[0] != "help"] + [("night", "Night", "O")]
    for i, (kind, label, key) in enumerate(cats):
        ic = H.icon(H.REAL_ICON[kind], 2) if kind in H.REAL_ICON else H.glyph(kind)
        H.draw_cell(img, d, i, label, key, ic=ic, hover=(hover == kind))


def common_hud(img, night=False, minimap_night=None):
    d = H.draw(img)
    H.draw_minimap_panel(img, d, H.minimap(night if minimap_night is None else minimap_night))
    return d


# ---------------------------------------------------------------- 1. build cards
def thumb_for(art):
    im = art[0]
    n = max(1, math.ceil(max(im.height / 29, im.width / 60)))
    return im.resize((max(1, im.width // n), max(1, im.height // n)), Image.NEAREST)


NEW = {}  # filled in main: name -> dict(art=..., ...)


def build_specs():
    return {
        "tavern": dict(name="Tavern", art=tavern_art(True), era="Village era, Night", size="2x1", workers=(0, 2),
                       cost={"wood": 24, "planks": 12, "gold": 20},
                       needs=[("food", "4 crops / night")], makes=[("spirit", "+5 Spirit, houses within 4")],
                       flavour="Warm windows, loud songs, and a bed to sleep it off.", key="W", cell="Tavern"),
        "bakery": dict(name="Bakery", art=bakery_art(True), era="Town era, Night", size="1x1", workers=(0, 2),
                       cost={"wood": 18, "stone": 20, "planks": 10}, needs=[("food", "4"), ("charcoal", "2")],
                       makes=[("bread", "3 bread / night")],
                       flavour="Bakes while the town sleeps. The chimney never cools.", key="E", cell="Bakery"),
        "night_market": dict(name="Night Market", art=market_art(True), era="Town era, Night", size="2x2", workers=(0, 3),
                             cost={"wood": 30, "planks": 20, "gold": 60}, needs=[("text", "Surplus goods, lit tiles")],
                             makes=[("gold", "Sells surplus for gold")],
                             flavour="Lanterns on a string, prices on a whisper.", key="T", cell="Night Mkt"),
        "observatory": dict(name="Observatory", art=observatory_art(True), era="City era, Night", size="2x2",
                            workers=(1, 2), cost={"stone": 40, "planks": 24, "gold": 120},
                            needs=[("text", "Clear night, lit tile")],
                            makes=[("text", "Dimming warning, star chart")],
                            flavour="Charts the stars: surveys fly faster, starlight feeds Lumen.", key="S",
                            cell="Observ."),
        "night_watch": dict(name="Night Watch", art=watch_art(True), era="Village era, Night", size="1x1", workers=(0, 1),
                            cost={"wood": 14, "stone": 8, "gold": 10}, needs=[("charcoal", "1 / night")],
                            makes=[("text", "Walker with a lantern")],
                            flavour="A lantern on a lonely road keeps the gloom at arm's length.", key="R",
                            cell="Watch"),
        "moonmoth_loft": dict(name="Moonmoth Loft", art=loft_art(True), era="Town era, Night", size="1x1",
                              workers=(0, 2), cost={"wood": 20, "planks": 12, "gold": 30},
                              needs=[("text", "Lit tiles nearby")], makes=[("silk", "1 silk / night")],
                              flavour="Pale moths come for the lamps; silk is spun while you sleep.", key="A",
                              cell="Moth Loft"),
        "water_wheel": dict(name="Water Wheel", art=wheel_art(True), era="Village era, Water", size="1x1 on a bank",
                            workers=(0, 0), cost={"wood": 16, "stone": 10, "planks": 8},
                            needs=[("text", "A river bank tile")], makes=[("text", "-1 worker next door")],
                            flavour="Drives the Sawmill, Mason or Bakery next to it. No lamp.", key="Q",
                            cell="Water Wheel"),
        "river_dock": dict(name="River Dock", art=dock_art(), era="Town era, Logistics", size="1x1 on the bank",
                           workers=(1, 0), cost={"wood": 18, "planks": 14, "gold": 25},
                           needs=[("text", "Built in pairs")], makes=[("text", "Boats carry goods")],
                           flavour="Downstream is quick; the way back is a long pull on the oars.", key="W",
                           cell="River Dock"),
        "levee": dict(name="Levee", art=levee_preview(), era="Town era, Water", size="1x1, like a road",
                      workers=(0, 0), cost={"stone": 6, "cut_stone": 2}, needs=[("text", "A tile on the bank")],
                      makes=[("text", "Stops spring floods")],
                      flavour="A low stone wall; cottages behind it keep dry feet.", key="E", cell="Levee"),
    }


def levee_preview():
    sc = N.Scene(3, 2)
    kinds = {}
    terrain(sc, kinds, water={(0, 0), (1, 0), (2, 0)}, levee={(0, 1), (1, 1), (2, 1)})
    im = sc.day.crop((8, 28, 88, 64))
    return im, Image.new("RGBA", im.size), (im.width // 2, im.height - 2)


def chips(img, d, x, y, items, size=14):
    """A row of small items: (icon kind, text) or ('text', text). Returns the x after the last one."""
    for kind, text in items:
        if kind == "text":
            txt(d, (x, y), text, size, INK, "lm", True)
            x += int(tw(text, size, True)) + 14
        else:
            put_gicon(img, kind, x, y - 7, 1)
            txt(d, (x + 18, y), text, size, INK, "lm", True)
            x += 22 + int(tw(text, size, True)) + 14
    return x


def card(img, d, x, y, sp, w=410, h=220):
    box = (x, y, x + w - 1, y + h - 1)
    panel(d, box, fill=(20, 17, 14, 250), edge=GOLD)
    bx, by = x + 12, y + 12
    pw = 120
    d.rounded_rectangle([bx, by, bx + pw, by + pw], 4, fill=(41, 54, 36), outline=(14, 12, 10), width=2)
    art = sp["art"][0]
    s = art
    if art.height > pw - 6 or art.width > pw - 6:
        n = max(math.ceil(art.height / (pw - 6)), math.ceil(art.width / (pw - 6)))
        s = art.resize((art.width // n, art.height // n), Image.NEAREST)
    elif art.width * 2 <= pw - 6 and art.height * 2 <= pw - 6:
        s = up(art, 2)
    H.blit(img, s, (bx + pw // 2 - s.width // 2, by + pw - 4 - s.height))
    tx = bx + pw + 14
    txt(d, (tx, y + 30), sp["name"], 24, GOLD, "lm")
    txt(d, (tx, y + 56), sp["era"], 12, DIM, "lm", True)
    txt(d, (tx, y + 76), f"Size {sp['size']}", 12, INK, "lm", True)
    wd, wn = sp["workers"]
    txt(d, (tx, y + 96), "Workers", 12, FAINT, "lm", True)
    xx = tx + 60
    d.ellipse([xx, y + 90, xx + 11, y + 101], fill=(255, 190, 70))
    d.ellipse([xx + 2, y + 92, xx + 9, y + 99], fill=(255, 232, 130))
    txt(d, (xx + 18, y + 96), f"day {wd}", 12, INK if wd else FAINT, "lm", True)
    H.blit(img, H.icon("moon", 1), (xx + 66, y + 89))
    txt(d, (xx + 84, y + 96), f"night {wn}", 12, INK if wn else FAINT, "lm", True)
    txt(d, (tx, y + 118), f"Hotkey {sp['key']}", 12, FAINT, "lm", True)
    d.line([(bx, y + 136), (x + w - 14, y + 136)], fill=EDGE)
    txt(d, (bx, y + 156), "Cost", 12, FAINT, "lm", True)
    cx = bx + 50
    for k, n in sp["cost"].items():
        put_gicon(img, k, cx, y + 142, 2)
        txt(d, (cx + 32, y + 156), str(n), 16, INK, "lm")
        cx += 32 + int(tw(str(n), 16)) + 22
    txt(d, (bx, y + 177), "Needs", 12, FAINT, "lm", True)
    chips(img, d, bx + 50, y + 177, sp["needs"])
    txt(d, (bx, y + 192), "Makes", 12, FAINT, "lm", True)
    chips(img, d, bx + 50, y + 192, sp["makes"])
    assert tw(sp["flavour"], 12, True) <= w - 28, sp["flavour"]
    txt(d, (bx, y + 207), sp["flavour"], 12, DIM, "lm", True)


def frame_build_cards():
    big, _ = H.world_map(False)  # the approved town, in the evening
    d = common_hud(big)
    hud_resources(big, d)
    hud_clock(big, d, 17 + 40 / 60, "Day 3, 17:40", phase=4)
    hud_objectives(big, d, (("moon", "Dimming in 2 days, lasts 3", MOONC), "Lumen output halves. Stock: 4 days."))
    hud_selection(big, d, H.bsprite("sawmill"), "Sawmill", "Tier II", "Refining, Town era",
                  [("day", 2, 2, ""), ("night", 1, 2, "")], (GREEN, "Working"), [("Makes", "planks", "6 planks / day", "uses 12 wood")],
                  [("In", "wood", 22, 40, (168, 116, 62)), ("Out", "planks", 9, 40, GOLD)])
    specs = build_specs()
    H.draw_grid_frame(d, "Night", "Esc: back")
    order = [("lamp", "Lamp", "Q"), ("tavern", None, "W"), ("bakery", None, "E"), ("night_watch", None, "R"),
             ("night_market", None, "T"), ("moonmoth_loft", None, "A"), ("observatory", None, "S"),
             ("kiln", "Kiln", "D"), ("grove", "Grove", "F")]
    arts = {"lamp": N.lamp_art("brazier", True), "kiln": N.kiln_art(True), "grove": N.grove_art(True)}
    for i, (bid, lab, key) in enumerate(order):
        art = arts[bid] if bid in arts else specs[bid]["art"]
        label = lab or specs[bid]["cell"]
        assert tw(label, 12, True) <= 62, label
        H.draw_cell(big, d, i, label, key, thumb=thumb_for(art), hover=(bid == "tavern"))
    H.draw_cell(big, d, 14, "Back", "Esc", ic=H.glyph("back"), dx=10)
    # hover card for the Tavern, pointing at its cell
    sp = dict(specs["tavern"])
    cw, ch = 410, 220
    cxb = 862
    cyb = 540 - 8 - ch
    card(big, d, cxb, cyb, sp, cw, ch)
    cb = H.cell_box(1)
    ax = (cb[0] + cb[2]) // 2
    d.polygon([(ax - 6, 539 - 8 + 1 - 1), (ax + 6, 539 - 8 + 1 - 1), (ax, 539 - 8 + 7)], fill=(20, 17, 14))
    d.line([(ax - 6, 539 - 8), (ax, 539 - 8 + 7), (ax + 6, 539 - 8)], fill=GOLD, width=2)
    return big


def frame_build_cards_2():
    img = Image.new("RGB", (W, HT), PAL_DARK)
    d = H.draw(img)
    txt(d, (20, 20), "New buildings: hover cards", 24, GOLD, "lm")
    txt(d, (W - 20, 20), "Costs and worker counts are made up; Water Wheel, River Dock, Levee sit in Water and Logistics.", 12, FAINT, "rm", True)
    specs = build_specs()
    order = ["tavern", "bakery", "night_market", "observatory", "night_watch", "moonmoth_loft", "water_wheel",
             "river_dock", "levee"]
    for i, k in enumerate(order):
        r, cc = divmod(i, 3)
        card(img, d, 14 + cc * 421, 42 + r * 224, specs[k], 410, 220)
    return img


# ---------------------------------------------------------------- 2. town at night
def forest_tiles(spec):
    k = {}
    for (x0, y0, x1, y1, p, seed) in spec:
        rr = random.Random(seed)
        for y in range(y0, y1 + 1):
            for x in range(x0, x1 + 1):
                if rr.random() < p:
                    k[(x, y)] = "forest"
    return k


def walkers(sc, items):
    for v, dr, fr, x, y in items:
        sc.walker(v, dr, fr, x, y)


def moths(sc, pts):
    """Pale moth pixels (emissive, so they stay bright at night)."""
    for (x, y) in pts:
        for dx, dy, col in ((0, 0, (228, 232, 255, 255)), (2, 0, (228, 232, 255, 255)), (1, 1, (228, 232, 255, 255)),
                            (1, 0, (170, 150, 210, 255))):
            sc.extra_em.putpixel((int(x) + dx, int(y) + dy), col)


def town_scene():
    sc = N.Scene(20, 12, seed=7)
    kinds = forest_tiles([(0, 3, 1, 9, 0.95, 1), (2, 4, 2, 9, 0.6, 2), (0, 0, 4, 1, 0.9, 3), (18, 6, 19, 9, 0.85, 4),
                          (5, 0, 8, 1, 0.8, 5)])
    roads = {(x, 5) for x in range(2, 20)} | {(9, y) for y in range(2, 9)} | {(x, 8) for x in range(9, 20)}
    for p in roads:
        kinds.pop(p, None)
    terrain(sc, kinds, roads)
    sc.trees(kinds)
    return sc, kinds


def frame_town_night():
    sc, kinds = town_scene()
    circles = []
    sc.lamp("lantern", 4, 4, True)
    circles.append(circle(4, 4, 4, "lantern"))  # Lantern Post r3, +1 under the full moon
    sc.lamp("lantern", 15, 6, True)
    circles.append(circle(15, 6, 4, "lantern"))
    arts = {k: v["art"] for k, v in build_specs().items()}
    to = place(sc, tavern_art(True), 7, 4, 2, 1, "lit")
    circles.append(circle(0, 0, 2.4, "market", at=(to[0], to[1] - 10)))
    for n, tx, ty in (("cottage", 5, 4), ("cottage_shingle", 6, 4), ("cottage", 5, 6), ("cottage_shingle", 6, 6),
                      ("cottage", 7, 6), ("cottage_shingle", 18, 4), ("cottage", 17, 6)):
        put(sc, n, tx, ty)
    bo = place(sc, bakery_art(True), 10, 4, 1, 1, "lit")
    circles.append(circle(0, 0, 1.8, "brazier", at=(bo[0], bo[1] - 10)))
    place(sc, watch_art(True), 8, 6, 1, 1, "lit")
    mo = place(sc, market_art(True), 12, 3, 2, 2, "lit")
    circles.append(circle(0, 0, 3.0, "market", at=(mo[0], mo[1] - 12)))
    wo = place(sc, wagon_art(True), 14, 4, 1, 1, dx=10, dy=-2)
    circles.append(circle(0, 0, 1.8, "market", at=(wo[0] - 2, wo[1] - 12)))
    place(sc, observatory_art(True), 16, 3, 2, 2, "lit")
    lo = place(sc, loft_art(True), 10, 6, 1, 1, "lit")
    circles.append(circle(0, 0, 1.8, "lantern", at=(lo[0] + 12, lo[1] - 12)))
    ko = place(sc, N.kiln_art(True), 12, 6, 2, 2)
    circles.append(circle(0, 0, 2.4, "brazier", at=(ko[0], ko[1] - 8)))
    sc.puffs += [(ko[0] - 2, ko[1] - 58, 5, 60), (ko[0] + 1, ko[1] - 66, 6, 46), (ko[0] - 3, ko[1] - 75, 7, 32)]
    go = place(sc, N.grove_art(True), 3, 6, 2, 2)
    circles.append(circle(0, 0, 2.2, "glow", at=(go[0], go[1] - 12)))
    walkers(sc, [(0, "right", 1, 5 * T + 6, 5 * T + 22), (5, "left", 2, 13 * T + 4, 5 * T + 20), (9, "down", 1, 9 * T + 16, 7 * T + 14),
                 (14, "up", 0, 9 * T + 16, 3 * T + 20), (3, "right", 2, 17 * T + 10, 5 * T + 24), (11, "left", 1, 8 * T + 8, 5 * T + 24)])
    # the Night Watch walker with its lantern: a small moving pool
    wx, wy = 12 * T + 8, 5 * T + 22
    place(sc, lantern_walker(True), 0, 0, 1, 1, shadow=False, dx=wx - 16, dy=wy - 29 + 3)
    circles.append(circle(0, 0, 3, "lantern", at=(wx + 5, wy - 6)))
    moths(sc, [(lo[0] - 26, lo[1] - 50), (lo[0] - 14, lo[1] - 40), (lo[0] + 4, lo[1] - 58), (lo[0] + 20, lo[1] - 36),
               (lo[0] - 30, lo[1] - 28), (lo[0] + 28, lo[1] - 50), (lo[0] - 4, lo[1] - 26),
               (15 * T + 4, 6 * T - 18), (15 * T + 24, 6 * T - 6), (4 * T + 22, 4 * T - 10), (4 * T - 8, 4 * T - 22)])
    img = render_map(sc, True, circles)
    big = to_big(img)
    d = H.draw(big)
    brackets(d, 7, 4, 2, 1)
    tag(d, int(wo[0] * 2) + 6, int(2 * wo[1]) + 24, "Night caravan", INK, AMBER, img=big, ic="tools", up=True)
    tag(d, int(mo[0] * 2) - 24, int(2 * (mo[1] - 80) - 20), "Night Market", INK, AMBER, img=big)
    tag(d, int(lo[0] * 2) + 4, int(2 * lo[1]) + 26, "Moonmoth Loft", INK, MOONC, img=big, ic="silk", up=True)
    tag(d, int(bo[0] * 2) - 4, int(2 * (bo[1] - 60)) - 14, "Bakery", INK, AMBER, img=big)
    hud_objectives(big, d, (("moon", "Next Dimming in 6 days", MOONC), "Full moon tonight: lamps +1, Spirit +2."))
    hud_resources(big, d)
    hud_clock(big, d, 23 + 10 / 60, "Day 5, 23:10", phase=4, note="Full moon")
    H.draw_minimap_panel(big, d, H.minimap(True))
    hud_selection(big, d, arts["tavern"][0], "Tavern", "Tier I", "Village era, evening to dawn",
                  [("night", 2, 2, "")], (GREEN, "Working"),
                  [("Makes", "spirit", "+5 Spirit, houses within 4", ""), ("Drinks", "food", "4 crops / night", "")],
                  [("In", "food", 11, 20, (200, 90, 70)), ("Out", "spirit", 5, 5, (120, 190, 90))], scale=2)
    top_grid(big, d)
    hud_notice(big, d, "Night caravan: tools x5 for 40 gold, tonight only", y=520, edge=AMBER, icon=("tools", None))
    return big


# ---------------------------------------------------------------- 3. a Dimming night
def frame_dimming():
    sc = N.Scene(20, 12, seed=11)
    forest = forest_tiles([(0, 2, 3, 9, 0.97, 1), (4, 2, 6, 2, 0.95, 2), (0, 0, 8, 1, 0.97, 3), (9, 0, 12, 0, 0.8, 4),
                           (4, 7, 5, 9, 0.8, 5)])
    water = {(x, y) for x in (17, 18, 19) for y in range(2, 10)} | {(17, 0), (17, 1), (16, 0), (16, 1), (18, 0), (18, 1),
                                                                      (19, 0), (19, 1)}
    roads = {(x, 5) for x in range(4, 17)} | {(11, y) for y in range(2, 9)}
    for p in roads:
        forest.pop(p, None)
    for p in ((6, 3), (7, 3)):
        forest.pop(p, None)
    terrain(sc, forest, roads, water=water)
    sc.trees(forest)
    circles = []
    sc.lamp("lantern", 12, 4, True)
    circles.append(circle(12, 4, 3.5, "lantern"))
    wx, wy = 8 * T + 16, 5 * T + 22  # the Night Watch walker's lantern on the road
    circles.append(circle(0, 0, 2.3, "lantern", at=(wx + 5, wy - 6)))
    go_at = (8 * T + 32, 8 * T - 15)
    circles.append(circle(0, 0, 2.2, "glow", at=go_at))
    glow_t = set()
    for (x, y) in water:
        for dx, dy in ((0, 0), (1, 0), (-1, 0), (0, 1), (0, -1)):
            glow_t.add((x + dx, y + dy))
    glow_t = {(x, y) for (x, y) in glow_t if 0 <= x < 20 and 0 <= y < 12}
    forest_set = {p for p, k in forest.items() if k == "forest"}
    gloom = gloom_map(20, 12, forest_set, circles, extra_lit=glow_t, depth=6)

    def lit_at(tx, ty, fw=1, fh=1):
        return "lit" if is_lit(circles, (tx + fw / 2) * T, (ty + fh / 2) * T) or (tx, ty) in glow_t else "dark"

    sc.building("sawmill", 6, 3, windows=lit_at(6, 3, 2))  # in the gloom
    for n, tx, ty in (("cottage", 9, 4), ("cottage_shingle", 10, 4), ("cottage", 13, 4), ("cottage_shingle", 12, 6)):
        sc.building(n, tx, ty, windows=lit_at(tx, ty))
    place(sc, watch_art(True), 7, 6, 1, 1, lit_at(7, 6))
    go = place(sc, N.grove_art(True), 8, 6, 2, 2)
    obs = place(sc, observatory_art(True, starlight=True), 14, 6, 2, 2, lit_at(14, 6, 2, 2))
    place(sc, lantern_walker(True), 0, 0, 1, 1, shadow=False, dx=wx - 16, dy=wy - 29 + 3)
    walkers(sc, [(2, "right", 1, 14 * T + 6, 5 * T + 24), (9, "left", 2, 12 * T + 6, 5 * T + 22), (5, "down", 1, 11 * T + 16, 3 * T + 18)])
    rr = random.Random(5)
    specks = []
    for (x, y) in water:
        for _ in range(3):
            specks.append((x * T + rr.randrange(3, T - 3), y * T + rr.randrange(3, T - 3), (216, 250, 255, 255)))
    img = render_map(sc, True, circles, glow=[(glow_t, (0.62, 0.95, 1.0), 0.20)], gloom=gloom, specks=specks)
    big = to_big(img)
    d = H.draw(big)
    brackets(d, 6, 3, 2, 1)
    tag(d, 7 * 64, 2 * (3 * T - 54) - 22, "In gloom", RED, RED, img=big)
    tag(d, int(go[0] * 2), int(2 * (go[1] - 58)) - 18, "x2 in the Dimming", GREEN, GREEN, img=big, ic="glowcap")
    tag(d, int(obs[0] * 2) - 6, int(2 * (obs[1] - 108)) - 8, "Starlight: +Lumen", CYAN, CYAN, img=big)
    hud_objectives(big, d, (("moon", "Dimming: day 2 of 5", MOONC), "Nights run 16-09. Lumen output halves."))
    hud_resources(big, d, lumen=("29", "-6", RED, False))
    hud_clock(big, d, 17.5, "Day 7, 17:30", phase=1, note="Dimming: night 16-09", dark_hour=True, moon_t=0.1)
    H.draw_minimap_panel(big, d, H.minimap(True))
    hud_selection(big, d, H.bsprite("sawmill"), "Sawmill", "Tier II", "Refining, Town era",
                  [("day", 0, 2, ""), ("night", 0, 2, "")], (RED, "Stopped: in gloom - light it"),
                  [("Makes", "planks", "6 planks / day", "uses 12 wood")],
                  [("In", "wood", 22, 40, (168, 116, 62)), ("Out", "planks", 9, 40, GOLD)],
                  note=(0, "Needs a lamp, or the Night Watch", (214, 140, 72)))
    top_grid(big, d)
    hud_notice(big, d, "Dimming: the nights are long. Gloom creeps from the forest.", y=520, edge=MOONC)
    return big


# ---------------------------------------------------------------- 4. moon phases and arrivals
PHASES = ["New moon", "Waxing crescent", "First quarter", "Waxing gibbous", "Full moon", "Waning gibbous", "Last quarter",
          "Waning crescent"]


def gate_scene(lit):
    sc = N.Scene(6, 3, seed=2)
    roads = {(x, 2) for x in range(0, 6)}
    terrain(sc, {}, roads)
    circles = []
    go = place(sc, gate_art(lit), 4, 1, 2, 1, windows=None, dy=3)
    for tx in (0, 2):
        sc.lamp("lantern", tx, 1, lit)
        if lit:
            circles.append(circle(tx, 1, 2.2, "lantern"))
    if lit:
        circles.append(circle(4, 1, 2.0, "lantern", at=(go[0], go[1] - 24)))
    sc.walker(7, "right", 1, 1 * T + 12, 2 * T + 22)
    sc.walker(12, "right", 2, 2 * T + 22, 2 * T + 24)
    return render_map(sc, True, circles).crop((0, 12, 192, 96))


def moon_sample(kind):
    """A night ground sample with one lantern: new moon darker, normal, full moon (lamp radius +1)."""
    sc = N.Scene(6, 4, seed=9)
    terrain(sc, {})
    sc.lamp("lantern", 3, 2, True)
    r = {"new": 3.0, "normal": 3.0, "full": 4.0}[kind]
    img = render_map(sc, True, [circle(3, 2, r, "lantern")])
    if kind == "new":
        a = np.asarray(img, dtype=np.float32) * np.array([0.7, 0.7, 0.8])
        img = Image.fromarray(np.clip(a, 0, 255).astype(np.uint8))
    return img


def frame_moon():
    img = Image.new("RGB", (W, HT), PAL_DARK)
    d = H.draw(img)
    txt(d, (20, 22), "Moon phases and arrivals", 24, GOLD, "lm")
    txt(d, (W - 20, 22), "8-day cycle, one phase per day. The clock dial shows tonight's moon.", 12, FAINT, "rm", True)
    for i, nm in enumerate(PHASES):
        x = 16 + i * 156
        hi = i in (0, 4)
        panel(d, (x, 44, x + 148, 168), edge=GOLD if hi else EDGE)
        im = dial2(23 + 10 / 60, i, 4, dark_hour=True, moon_t=0.5)
        img.paste(im.convert("RGB"), (x + 18, 54))
        txt(d, (x + 74, 134), nm, 12, INK if hi else DIM, "mm", True)
        txt(d, (x + 74, 152), f"Day {i + 1}", 12, GOLD if hi else FAINT, "mm", True)
    ty = 180
    panel(d, (16, ty, 676, 676))
    txt(d, (32, ty + 22), "What the moon does", 16, GOLD, "lm")
    cols = [32, 168, 296, 380]
    for cx_, lab in zip(cols, ("Phase", "Lamps", "Spirit", "Other")):
        txt(d, (cx_, ty + 50), lab, 12, FAINT, "lm", True)
    d.line([(28, ty + 62), (664, ty + 62)], fill=EDGE)
    rows = [("Full moon", "Day 5", "radius +1", "+2", "Brighter night", GREEN, "lantern"),
            ("New moon", "Day 1", "as usual", "0", "Darker night, Glowcap +25%", MOONC, "glowcap"),
            ("Other six", "Days 2-4, 6-8", "neutral", "0", "Neutral", DIM, None)]
    for i, (nm, days, lamps, sp, other, col, ik) in enumerate(rows):
        y = ty + 90 + i * 48
        txt(d, (cols[0], y - 7), nm, 16, INK, "lm")
        txt(d, (cols[0], y + 12), days, 12, FAINT, "lm", True)
        txt(d, (cols[1], y), lamps, 12, GREEN if i == 0 else INK, "lm", True)
        txt(d, (cols[2], y), sp, 12, GREEN if sp.startswith("+") else INK, "lm", True)
        if i == 0:
            H.blit(img, H.icon("spirit", 1), (cols[2] + 24, y - 7))
        if i == 1:
            put_gicon(img, "glowcap", cols[3], y - 7, 1)
            txt(d, (cols[3] + 22, y), other, 12, col, "lm", True)
        else:
            txt(d, (cols[3], y), other, 12, INK if i == 2 else GREEN, "lm", True)
        if i < 2:
            d.line([(28, y + 28), (664, y + 28)], fill=(52, 46, 40))
    sy = ty + 244
    txt(d, (32, sy), "The same Lantern Post on three nights", 12, FAINT, "lm", True)
    for i, (k, lab) in enumerate((("new", "New moon: darker"), ("normal", "Other phases: neutral"), ("full", "Full moon: radius +1"))):
        x = 32 + i * 214
        s = moon_sample(k)
        img.paste(s, (x, sy + 14))
        d.rectangle([x - 1, sy + 13, x + s.width, sy + 14 + s.height], outline=EDGE)
        txt(d, (x, sy + 14 + s.height + 16), lab, 12, INK, "lm", True)
    txt(d, (32, sy + 14 + 128 + 44), "Lamp radius is in tiles; the pool is drawn as three flat steps.", 12, DIM, "lm", True)
    ax = 692
    panel(d, (ax, ty, W - 16, 676))
    txt(d, (ax + 16, ty + 22), "Arrivals", 16, GOLD, "lm")
    txt(d, (ax + 16, ty + 50), "Newcomers arrive at night if the road", 16, INK, "lm", True)
    txt(d, (ax + 16, ty + 70), "to the town gate is lit.", 16, INK, "lm", True)
    for i, (lit, l1, l2, col) in enumerate(((True, "Lit road", "They arrive", GREEN), (False, "Dark road", "They wait outside", RED))):
        y = ty + 94 + i * 192
        s = up(gate_scene(lit), 2)
        img.paste(s, (ax + 16, y))
        d.rectangle([ax + 15, y - 1, ax + 16 + s.width, y + s.height], outline=EDGE)
        lx = ax + 16 + s.width + 14
        cxm, cym = lx + 12, y + 26
        d.rounded_rectangle([cxm - 12, cym - 12, cxm + 12, cym + 12], 4, fill=(24, 20, 18), outline=col, width=2)
        if lit:
            for k in range(5):
                d.rectangle([cxm - 7 + k, cym + k - 1, cxm - 6 + k, cym + k], fill=col)
            for k in range(8):
                d.rectangle([cxm - 2 + k, cym + 3 - k, cxm - 1 + k, cym + 4 - k], fill=col)
        else:
            for k in range(11):
                d.rectangle([cxm - 5 + k, cym - 5 + k, cxm - 4 + k, cym - 4 + k], fill=col)
                d.rectangle([cxm + 5 - k, cym - 5 + k, cxm + 6 - k, cym - 4 + k], fill=col)
        txt(d, (lx, y + 64), l1, 16, col, "lm")
        txt(d, (lx, y + 86), l2, 12, INK, "lm", True)
    txt(d, (ax + 16, ty + 94 + 2 * 192 - 8), "Day arrivals are unchanged. One lamp at the gate is enough.", 12, DIM, "lm", True)
    return img


# ---------------------------------------------------------------- 5. river day
def frame_river():
    sc = N.Scene(20, 12, seed=13)
    water = {(x, y) for x in range(0, 20) for y in (4, 5)}
    kinds = forest_tiles([(0, 3, 3, 3, 0.6, 3), (18, 2, 19, 3, 0.9, 6), (0, 0, 7, 1, 0.9, 7)])
    silt = {(18, 6), (19, 6), (18, 7), (19, 7), (11, 7)}
    flood = {(x, y) for x in range(0, 11) for y in (6, 7)} | {(11, 6)}
    levee = {(x, 6) for x in range(12, 18)}
    terrain(sc, kinds, water=water, flood=flood, silt=silt, levee=levee)
    sc.trees(kinds)
    for (nm, tx, ty) in (("farm", 2, 6), ("farm", 6, 6)):
        sc.building(nm, tx, ty, windows=None)
    place(sc, wheel_art(), 9, 3, 1, 1, dy=4, dx=-2)
    sc.building("sawmill", 10, 3, windows=None)
    place(sc, dock_art(), 6, 3, 1, 1, dy=32, shadow=False)
    place(sc, dock_art(), 16, 3, 1, 1, dy=32, shadow=False)
    for nm, tx, ty in (("cottage", 14, 7), ("cottage_shingle", 16, 7), ("cottage", 12, 7),
                       ("cottage_shingle", 13, 3)):
        sc.building(nm, tx, ty, windows=None)
    place(sc, boat_art(True), 0, 0, 1, 1, shadow=False, dx=12 * T + 6 - 16, dy=4 * T + 26 - 29)
    place(sc, boat_art(False), 0, 0, 1, 1, shadow=False, dx=3 * T + 18 - 16, dy=5 * T + 16 - 29)
    walkers(sc, [(4, "right", 1, 8 * T + 2, 3 * T + 28), (9, "left", 0, 15 * T + 12, 3 * T + 28),
                 (12, "down", 1, 9 * T + 26, 3 * T + 30)])
    big = to_big(render_map(sc, False))
    d = H.draw(big)
    for i in range(3):  # chevrons ">>>" in pixels (2x scale): fast, three of them
        x0, y0 = 13 * 64 + 20 + i * 30, 4 * 64 + 12
        for k in range(6):
            d.rectangle([x0 + k * 4, y0 + k * 4, x0 + k * 4 + 3, y0 + k * 4 + 3], fill=(236, 246, 255))
            d.rectangle([x0 + k * 4, y0 + 40 - k * 4, x0 + k * 4 + 3, y0 + 43 - k * 4], fill=(236, 246, 255))
    x0, y0 = 1 * 64 + 20, 5 * 64 + 2  # a single small "<": slow
    for k in range(4):
        d.rectangle([x0 + (3 - k) * 4, y0 + k * 4, x0 + (3 - k) * 4 + 3, y0 + k * 4 + 3], fill=(236, 246, 255))
        d.rectangle([x0 + (3 - k) * 4, y0 + 28 - k * 4, x0 + (3 - k) * 4 + 3, y0 + 31 - k * 4], fill=(236, 246, 255))
    tag(d, 13 * 64 + 84, 4 * 64 - 10, "downstream fast", GREEN, GREEN, img=big)
    tag(d, 3 * 64 + 50, 4 * 64 + 4, "upstream slow", AMBER, AMBER, img=big)
    tag(d, 9 * 64 + 12, 3 * 64 - 56, "Water Wheel", INK, CYAN, img=big)
    tag(d, 14 * 64 + 40, 7 * 64 - 28, "Levee keeps it dry", GREEN, GREEN, img=big)
    tag(d, 9 * 64 + 8, 7 * 64 + 28, "Flood water", CYAN, CYAN, img=big)
    tag(d, 18 * 64 + 64, 7 * 64 + 28, "Silt", (210, 170, 120), (160, 120, 80), img=big)
    tag(d, 6 * 64 + 36, 3 * 64 - 12, "River Dock", INK, EDGE, img=big)
    tag(d, 16 * 64 + 36, 3 * 64 - 12, "River Dock", INK, EDGE, img=big)
    brackets(d, 10, 3, 2, 1)
    hud_objectives(big, d, (("water", "Spring flood: day 1 of 3", CYAN), "Low tiles by the river are under water."))
    hud_resources(big, d)
    hud_clock(big, d, 13 + 10 / 60, "Day 12, 13:10", sub="Year 2, Spring")
    H.draw_minimap_panel(big, d, H.minimap(False))
    hud_selection(big, d, H.bsprite("sawmill"), "Sawmill", "Tier II", "Refining, Town era",
                  [("day", 1, 1, ""), ("night", 1, 1, "")], (GREEN, "Working"),
                  [("Makes", "planks", "6 planks / day", "uses 12 wood")],
                  [("In", "wood", 22, 40, (168, 116, 62)), ("Out", "planks", 9, 40, GOLD)],
                  note=(0, "Water Wheel: -1 worker, runs at night", CYAN))
    top_grid(big, d)
    hud_notice(big, d, "Spring flood: 3 days. Fields get silt.", y=520, edge=CYAN, icon=("water", "water"))
    return big


# ---------------------------------------------------------------- 6. vein surge, the day after a Dimming
def frame_surge():
    sc = N.Scene(20, 12, seed=17)
    veins = set()
    for (x0, y0, x1, y1) in ((6, 3, 8, 4), (13, 3, 15, 4), (11, 7, 13, 8), (1, 6, 3, 7)):
        for y in range(y0, y1 + 1):
            for x in range(x0, x1 + 1):
                veins.add((x, y))
    kinds = forest_tiles([(0, 0, 4, 1, 0.9, 2), (17, 6, 19, 9, 0.85, 4)])
    roads = {(x, 5) for x in range(0, 20)} | {(10, y) for y in range(2, 9)}
    for p in roads:
        kinds.pop(p, None)
        veins.discard(p)
    terrain(sc, kinds, roads, veins=veins)
    sc.trees(kinds)
    for (nm, tx, ty) in (("cottage", 4, 4), ("cottage_shingle", 5, 4), ("rowhouse", 11, 4), ("well", 9, 4),
                         ("cottage", 4, 6), ("cottage_shingle", 5, 6), ("rowhouse", 6, 6), ("storehouse", 14, 6),
                         ("market", 17, 3), ("cottage", 8, 6)):
        sc.building(nm, tx, ty, windows=None)
    for tx, ty in ((7, 4), (14, 4), (12, 7), (2, 6)):
        sc.building("lumen_tap", tx, ty, windows=None)
    walkers(sc, [(0, "right", 1, 3 * T + 6, 5 * T + 22), (5, "left", 2, 13 * T + 4, 5 * T + 20), (9, "down", 1, 10 * T + 16, 7 * T + 14),
                 (3, "right", 2, 17 * T + 10, 5 * T + 24)])
    big = to_big(render_map(sc, False))
    d = H.draw(big)
    rr = random.Random(23)
    pts = []
    for (x, y) in sorted(veins):
        for _ in range(3):
            pts.append((x * 64 + rr.randrange(6, 58), y * 64 + rr.randrange(6, 58), rr.choice((1, 2, 2, 3, 4))))
    for (sx, sy, n) in pts:  # pixel crosses, 2x2 px per art pixel: white centre, pale arms, cyan tips
        s = 2
        d.rectangle([sx, sy, sx + s - 1, sy + s - 1], fill=(255, 255, 255))
        for k in range(1, n + 1):
            col = (216, 252, 255) if (k < n or n == 1) else CYAN
            for ddx, ddy in ((k, 0), (-k, 0), (0, k), (0, -k)):
                d.rectangle([sx + ddx * s, sy + ddy * s, sx + ddx * s + s - 1, sy + ddy * s + s - 1], fill=col)
    brackets(d, 7, 4, 1, 1)
    tag(d, 7 * 64 + 32, 4 * 64 - 118, "Surge +50%", CYAN, CYAN, img=big, ic="lumen")
    tag(d, 14 * 64 + 32, 4 * 64 - 118, "Surge +50%", CYAN, CYAN, img=big, ic="lumen")
    hud_objectives(big, d, (("lumen", "Vein surge: day 1 of 2", CYAN), "Dimming over. Veins run hot: Lumen +50%."))
    hud_resources(big, d, lumen=("58", "+24", GREEN, True))
    hud_clock(big, d, 8 + 40 / 60, "Day 12, 08:40", note="Dimming over", phase=0, note_col=CYAN)
    H.draw_minimap_panel(big, d, H.minimap(False))
    hud_selection(big, d, H.bsprite("lumen_tap"), "Lumen Tap", None, "Lumen, Town era, on a vein",
                  [("day", 2, 2, "")], (GREEN, "Working"),
                  [("Makes", "lumen", "15 Lumen / day", "")],
                  [("Out", "lumen", 14, 40, CYAN)], scale=1, note=(0, "Vein surge: +50% for 2 days (was 10)", CYAN))
    top_grid(big, d)
    hud_notice(big, d, "Vein surge: Lumen +50% for 2 days", y=520, edge=CYAN, icon=("lumen", None))
    return big


# ---------------------------------------------------------------- main
def main():
    out = Path(sys.argv[1]) if len(sys.argv) > 1 and not sys.argv[1].startswith("-") else OUT_DEFAULT
    out.mkdir(parents=True, exist_ok=True)
    frames = (("nl_build_cards", frame_build_cards), ("nl_build_cards_2", frame_build_cards_2),
              ("nl_town_night", frame_town_night), ("nl_dimming_night", frame_dimming), ("nl_moon_phases", frame_moon),
              ("nl_river", frame_river), ("nl_surge", frame_surge))
    only = set(sys.argv[2:])
    for name, fn in frames:
        if only and name not in only:
            continue
        im = fn()
        assert im.size == (W, HT), (name, im.size)
        im.convert("RGB").save(out / f"{name}.png")
        print("wrote", name)


if __name__ == "__main__":
    main()
