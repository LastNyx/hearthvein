"""Hearthvein HUD redesign mockups (spec: .scratch/v1/hud-rts-spec.md): five 1280x720 pictures for Ben to approve.

Usage: python3 tools/mockups_hud.py [out_dir]     (default: .scratch/v1/mockups/hud)
Writes hud_town_day.png, hud_category_open.png, hud_nothing_selected.png, hud_compare.png, hud_night.png.

Mockup art only: real tiles, building sprites, goods icons and the two game fonts (PixelifySans headings, Tiny5 body)
from assets/. Drawn pictures: the 12x12 command glyphs (no category icons exist in the repo yet). Numbers that are not
in data/ (stock, workers, buffers, planet health) are made up. The arrangement is the classic RTS one; the look is
Hearthvein's own warm panels. Everything is drawn on the 1x pixel grid: no anti-aliased text, nearest-neighbour sprites.
"""
import random
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFont

sys.path.insert(0, str(Path(__file__).resolve().parent))
import mockups_night as N  # noqa: E402  (Scene, tiles, sprite loading, night tint colour)

U, M = N.U, N.M
ROOT = Path(__file__).resolve().parent.parent
ASSETS = ROOT / "assets"
OUT_DEFAULT = ROOT / ".scratch" / "v1" / "mockups" / "hud"
W, H = 1280, 720
T = 32

# ---------------------------------------------------------------- palette (ui/hud.gd)
INK = (236, 226, 206)
GOLD = (242, 210, 122)
DIM = (170, 160, 150)
FAINT = (120, 112, 104)
CYAN = (127, 224, 240)
RED = (232, 106, 90)
GREEN = (144, 200, 112)
AMBER = (232, 163, 58)
MOONC = (200, 210, 240)
PANEL = (24, 20, 18, 235)  # PANEL_BG 0.094 0.078 0.071 at 0.92
EDGE = (90, 80, 70)  # PANEL_EDGE
BTN = (44, 38, 34)  # normal button
BTN_ON = (70, 60, 51)
BTN_HOV = (84, 71, 59)
BAR_BG = (60, 50, 50)
SLOT = (36, 32, 28)


# ---------------------------------------------------------------- fonts and drawing helpers
_fonts = {}


def font(size, body=False):
    if body and size == 12:
        size = 14  # Tiny5 is clean on the pixel grid at 8, 14, 15, 16, 24 only
    k = (size, body)
    if k not in _fonts:
        _fonts[k] = ImageFont.truetype(str(ASSETS / "ui" / ("Tiny5.ttf" if body else "PixelifySans.ttf")), size)
    return _fonts[k]


def draw(img):
    d = ImageDraw.Draw(img, "RGBA")
    d.fontmode = "1"  # 1-bit text: no anti-aliasing
    return d


def txt(d, xy, s, size=16, col=INK, anchor="la", body=False):
    d.text(xy, s, font=font(size, body), fill=col, anchor=anchor)


def tw(s, size, body=False):
    return font(size, body).getlength(s)


def panel(d, box, fill=PANEL, edge=EDGE, r=6):
    d.rounded_rectangle(box, r, fill=fill, outline=edge, width=2)


def button(d, box, label, on=False, hover=False, size=16, body=False, col=INK, edge=None):
    fill = BTN_HOV if hover else (BTN_ON if on else BTN)
    ec = edge if edge else (GOLD if on else (EDGE if hover else None))
    d.rounded_rectangle(box, 4, fill=fill, outline=ec, width=2 if ec else 0)
    if label:
        txt(d, ((box[0] + box[2]) // 2 + 1, (box[1] + box[3]) // 2), label, size, col, "mm", body)


def blit(img, sp, xy):
    sp = sp.convert("RGBA")
    img.paste(sp, (int(xy[0]), int(xy[1])), sp)


def up(im, s):
    return im.resize((im.width * s, im.height * s), Image.NEAREST)


_icons = {}


def icon(kind, s=2):
    """The real game goods icons (assets/ui/icon_*.png, 14x14) at an integer scale."""
    k = (kind, s)
    if k not in _icons:
        _icons[k] = up(Image.open(ASSETS / "ui" / f"icon_{kind}.png").convert("RGBA"), s)
    return _icons[k]


def put_icon(img, kind, x, y, s=2):
    blit(img, icon(kind, s), (x, y))


def bar(d, box, frac, fill, bg=BAR_BG):
    d.rectangle(box, fill=bg)
    d.rectangle([box[0], box[1], box[0] + max(1, int((box[2] - box[0]) * frac)) - 1, box[3]], fill=fill)
    d.rectangle(box, outline=(14, 12, 10))


# ---------------------------------------------------------------- command glyphs: 12x12 art, 1 px dark outline
_GK = {
    "b": (96, 62, 34), "t": (206, 176, 112), "y": (242, 210, 122), "Y": (190, 150, 60), "r": (190, 100, 66),
    "R": (122, 56, 36), "g": (150, 152, 158), "G": (206, 208, 212), "n": (112, 176, 84), "N": (70, 120, 56),
    "c": (90, 160, 214), "C": (52, 100, 156), "w": (240, 232, 212), "p": (150, 120, 90), "d": (110, 112, 118),
    "o": (232, 140, 60),
}
_GLYPH = {
    "roads": ["............", "........tt..", ".......tttt.", "......tttp..", ".....tttp...", "....tttp....", "...tttp.....",
              "..tttp......", ".tttp.......", "tttp........", "ttp.........", "............"],
    "housing": ["............", ".....rr.....", "....rrrr....", "...rrrrRr...", "..rrrrrrRr..", ".rrrrrrrrRR.",
                "..tttttttt..", "..ttyyttbt..", "..ttyyttbt..", "..tttttttb..", "..bbbbbbbb..", "............"],
    "water": ["............", ".....cc.....", ".....cc.....", "....cccc....", "...ccwccc...", "...cwcccC...",
              "..ccwccccC..", "..cccccccC..", "..ccccccCC..", "...cCCCCC...", "....CCCC....", "............"],
    "logistics": ["............", "............", ".bbbbbbbbbb.", ".bttttttttb.", ".bttttttttb.", ".bbbbbbbbbb.",
                  ".bttttttttb.", ".bttttttttb.", ".bbbbbbbbbb.", "..dd....dd..", "..dd....dd..", "............"],
    "civic": ["............", ".b..........", ".bbbbbbb....", ".bRRRRRRb...", ".bRRwwRRRb..", ".bRRRRRRb...",
              ".bbbbbbb....", ".b..........", ".b..........", ".b..........", "bbb.........", "............"],
    "demolish": ["............", "..dddddd....", ".dGGGGdd....", ".dddddddb...", ".dGGGGdbb...", "..dddddb....",
                 ".....bb.....", ".....bb.....", ".....bb.....", ".....bb.....", ".....bb.....", "............"],
    "upgrade": ["............", ".....nn.....", "....nnnn....", "...nnnnnn...", "..nnnnnnnn..", ".nnnNnnNnnn.",
                "....nnnn....", "....nNnn....", "....nnnn....", "....nnnN....", "....NNNN....", "............"],
    "clear": ["............", "....ggggg...", "....gGGggg..", "....gGggg...", ".....bgg....", ".....b......",
              ".....b......", ".....b......", ".....b......", ".....b......", ".....bb.....", "............"],
    "plant": ["............", ".....nn.....", "...nnnnNn...", "..nnnnnnNn..", "...nnnNnn...", ".....nN.....",
              ".....bb.....", ".....bb.....", ".....bb.....", "....tbbtt...", "..tttttttt..", "............"],
    "region": ["............", ".bbbbbbbbbb.", ".btttgttttb.", ".bttggtnnnb.", ".bttgtnnnnb.", ".btgggtnncb.",
               ".btttgttccb.", ".bttttgtccb.", ".bttttgtttb.", ".bbbbbbbbbb.", "............", "............"],
    "help": ["............", "....wwww....", "...ww..ww...", "...ww..ww...", ".......ww...", "......ww....",
             ".....ww.....", ".....ww.....", "............", ".....ww.....", ".....ww.....", "............"],
    "back": ["............", "............", "....y.......", "...yy.......", "..yyyyyyyy..", ".yyyyyyyyyy.",
             "..yyyyyyyy..", "...yy.......", "....y.......", "............", "............", "............"],
}
_gcache = {}


def glyph(kind, s=2):
    k = (kind, s)
    if k not in _gcache:
        rows = _GLYPH[kind]
        assert len(rows) == 12 and all(len(r) == 12 for r in rows), kind
        im = Image.new("RGBA", (12, 12))
        px = im.load()
        for y, row in enumerate(rows):
            for x, ch in enumerate(row):
                if ch != ".":
                    px[x, y] = _GK[ch] + (255,)
        _gcache[k] = up(M.outline(im), s)
    return _gcache[k]


# ---------------------------------------------------------------- the town: day look and night look
VX, VY = 0, 0  # the picture is the top-left 640x360 of a 20x12 tile scene at 2x
LAMPS = [("lantern", 5, 4, 4), ("lantern", 9, 4, 5), ("lantern", 14, 4, 5), ("lumen", 15, 6, 6)]
SAW = (11, 4)  # Sawmill footprint (2x1)

MAN = N.MAN["buildings"]


def bsprite(name):
    im = N.load(MAN[name]["file"])
    return im.crop(im.getbbox())


def build_scene(night=False):
    sc = N.Scene(20, 12, seed=5)
    kinds = {}
    rng = random.Random(4)
    for y in range(0, 4):
        for x in range(0, 6 - y):
            if rng.random() < 0.9:
                kinds[(x, y)] = "forest"
    for y in range(8, 12):
        for x in range(0, 3):
            if rng.random() < 0.8:
                kinds[(x, y)] = "rock"
    for y in range(9, 12):
        for x in range(17, 20):
            if rng.random() < 0.7:
                kinds[(x, y)] = "forest"
    roads = {(x, 5) for x in range(0, 20)} | {(10, y) for y in range(0, 12)} | {(15, y) for y in range(2, 6)} \
        | {(x, 8) for x in range(10, 20)}
    for p in list(roads):
        kinds.pop(p, None)
    sc.terrain(kinds, roads)
    sc.trees(kinds)
    lamp_pts = [(l[1] * T + 16, l[2] * T + 16, l[3]) for l in LAMPS] if False else [(l[1] * T + 16, l[2] * T + 16, l[3]) for l in LAMPS]

    def win(tx, ty, fw=1):
        if not night:
            return None
        cx, cy = (tx + fw / 2) * T, ty * T + 16
        return "lit" if any(((cx - lx) ** 2 + (cy - ly) ** 2) ** 0.5 < (r + 0.5) * T for lx, ly, r in lamp_pts) else "dark"

    for kind, tx, ty, r in LAMPS:
        sc.lamp(kind, tx, ty, lit=night)
        if night:
            sc.light(tx * T + 16, ty * T + 16, r, kind, 0.92)
    placed = [("cottage", 3, 4, 1), ("cottage_shingle", 4, 4, 1), ("rowhouse", 6, 4, 2), ("well", 8, 4, 1),
              ("sawmill", 11, 4, 2), ("woodcutter", 13, 4, 1), ("market", 16, 3, 2),
              ("cottage", 3, 6, 1), ("cottage_shingle", 4, 6, 1), ("cottage", 5, 6, 1), ("rowhouse", 6, 6, 2),
              ("bell_tower", 8, 6, 1), ("hearth", 11, 6, 2), ("meeting_hall", 13, 6, 2), ("storehouse", 16, 6, 2),
              ("lumen_tap", 13, 1, 1), ("farm", 12, 9, 2), ("cottage", 15, 9, 1), ("cottage_shingle", 16, 9, 1),
              ("mason", 6, 8, 2), ("quarry", 3, 8, 1)]
    for name, tx, ty, fw in placed:
        sc.building(name, tx, ty, windows=win(tx, ty, fw))
    for v, dr, fr, x, y in [(0, "right", 1, 7 * T + 6, 5 * T + 22), (5, "left", 2, 12 * T + 4, 5 * T + 20),
                            (9, "down", 1, 10 * T + 16, 7 * T + 14), (14, "up", 0, 10 * T + 16, 3 * T + 20),
                            (3, "right", 2, 17 * T + 10, 8 * T + 24), (11, "left", 1, 14 * T + 8, 5 * T + 24),
                            (7, "right", 1, 4 * T + 14, 5 * T + 22)]:
        sc.walker(v, dr, fr, x, y)
    return sc


def stepped_night(sc):
    """Night tint on the map only; lamp pools are flat three-step rings (no gradient), lit pixels stay bright."""
    day, em = sc.render_day()
    base = N.to_arr(day)
    out = base * N.NIGHT
    yy, xx = np.mgrid[0:sc.H, 0:sc.W]
    for cx, cy, R, mul, strength in sc.lights:
        d = np.hypot(xx - cx, (yy - cy) * 1.15)
        t = np.where(d < R * 0.55, 1.0, np.where(d < R * 0.8, 0.62, np.where(d < R, 0.30, 0.0)))
        m = t[..., None] * strength
        out = out * (1 - m) + base * np.array(mul) * m
    img = N.to_img(out)
    img.alpha_composite(em)
    return img


def world_map(night=False):
    sc = build_scene(night)
    im = stepped_night(sc) if night else sc.render_plain()
    big = up(im, 2).crop((0, 0, W, H)).convert("RGB")
    d = draw(big)
    # selection marker: gold corner brackets round the Sawmill footprint (2x scale: 2 px = 1 art pixel)
    x0, y0 = SAW[0] * 64 - 4, SAW[1] * 64 - 4
    x1, y1 = (SAW[0] + 2) * 64 + 4, (SAW[1] + 1) * 64 + 4
    for (cx, cy, sx, sy) in ((x0, y0, 1, 1), (x1, y0, -1, 1), (x0, y1, 1, -1), (x1, y1, -1, -1)):
        d.rectangle([min(cx, cx + sx * 16), cy if sy > 0 else cy - 3, max(cx, cx + sx * 16), cy + (3 if sy > 0 else 0)], fill=GOLD)
        d.rectangle([cx if sx > 0 else cx - 3, min(cy, cy + sy * 16), cx + (3 if sx > 0 else 0), max(cy, cy + sy * 16)], fill=GOLD)
    return big, sc


# ---------------------------------------------------------------- minimap
def minimap(night=False, size=128):
    """128x128: 64x64 world tiles at 2 px. The camera window is tiles (22,26)..(42,37.25)."""
    ox, oy = 22, 26
    rng = random.Random(11)
    world = [["grass"] * 64 for _ in range(64)]

    def blob(cx, cy, r, kind):
        for y in range(max(0, cy - r), min(64, cy + r + 1)):
            for x in range(max(0, cx - r), min(64, cx + r + 1)):
                if (x - cx) ** 2 + (y - cy) ** 2 <= r * r * (0.7 + 0.3 * rng.random()):
                    world[y][x] = kind
    for cx, cy, r, k in ((8, 10, 9, "forest"), (52, 8, 7, "forest"), (12, 52, 10, "rock"), (54, 54, 8, "forest"),
                         (6, 34, 6, "forest"), (58, 30, 8, "water"), (44, 60, 6, "water"), (30, 8, 5, "rock"),
                         (28, 54, 5, "forest"), (36, 4, 4, "forest")):
        blob(cx, cy, r, k)
    # the camera window: the same terrain the big map shows (forest top-left, rock bottom-left, forest bottom-right)
    for y in range(26, 38):
        for x in range(22, 42):
            world[y][x] = "grass"
    for y in range(0, 4):
        for x in range(0, 6 - y):
            world[oy + y][ox + x] = "forest"
    for y in range(8, 12):
        for x in range(0, 3):
            world[oy + y][ox + x] = "rock"
    for y in range(9, 12):
        for x in range(17, 20):
            world[oy + y][ox + x] = "forest"
    col = {"grass": M.P["grass"][:3], "forest": M.P["tree"][:3], "rock": M.P["rock"][:3], "water": M.P["water"][:3]}
    im = Image.new("RGB", (size, size))
    px = im.load()
    for y in range(64):
        for x in range(64):
            c = col[world[y][x]]
            for dy in range(2):
                for dx in range(2):
                    px[x * 2 + dx, y * 2 + dy] = c
    d = draw(im)
    road = (170, 138, 98)
    for x in range(14, 54):  # roads
        d.rectangle([x * 2, (oy + 5) * 2, x * 2 + 1, (oy + 5) * 2 + 1], fill=road)
    for y in range(18, 48):
        d.rectangle([(ox + 10) * 2, y * 2, (ox + 10) * 2 + 1, y * 2 + 1], fill=road)
    for x in range(ox + 10, 54):
        d.rectangle([x * 2, (oy + 8) * 2, x * 2 + 1, (oy + 8) * 2 + 1], fill=road)
    homes = (214, 124, 72)
    other = (236, 226, 206)
    for tx, ty, k in [(3, 4, 0), (4, 4, 0), (6, 4, 0), (8, 4, 1), (13, 4, 1), (16, 3, 1), (3, 6, 0), (4, 6, 0), (5, 6, 0),
                      (6, 6, 0), (8, 6, 1), (11, 6, 1), (13, 6, 1), (16, 6, 1), (13, 1, 1), (12, 9, 1), (15, 9, 0),
                      (16, 9, 0), (6, 8, 1), (3, 8, 1)]:
        d.rectangle([(ox + tx) * 2, (oy + ty) * 2, (ox + tx) * 2 + 1, (oy + ty) * 2 + 1], fill=homes if k == 0 else other)
    for (tx, ty) in [(18, 22), (19, 22), (20, 23), (16, 38), (17, 38), (18, 40), (48, 24), (50, 26), (49, 26), (30, 44),
                     (32, 45), (14, 30), (13, 31)]:
        d.rectangle([tx * 2, ty * 2, tx * 2 + 1, ty * 2 + 1], fill=homes if (tx + ty) % 3 else other)
    d.rectangle([(ox + SAW[0]) * 2 - 1, (oy + SAW[1]) * 2 - 1, (ox + SAW[0]) * 2 + 4, (oy + SAW[1]) * 2 + 2], fill=GOLD)
    cx0, cy0 = ox * 2, oy * 2
    d.rectangle([cx0, cy0, cx0 + 39, cy0 + 22], outline=(255, 255, 255))  # camera rectangle
    if night:
        pass
    return im


def draw_minimap_panel(img, d, mini, sky=False):
    panel(d, (8, 566, 226, 714))
    img.paste(mini, (16, 578))
    d.rectangle([15, 577, 16 + 128, 578 + 128], outline=(14, 12, 10))
    x0, x1 = 152, 220
    button(d, (x0, 578, x1, 594), "Ground", on=not sky, size=12, body=True, col=INK)
    button(d, (x0, 596, x1, 612), "Sky", on=sky, size=12, body=True, col=INK)
    for i, (key, lab, on) in enumerate([("V", "Blight", False), ("G", "Roads", True), ("T", "Water", False),
                                        ("H", "Cover", False), ("L", "Grid", False)]):
        y = 618 + i * 18
        button(d, (x0, y, x1, y + 16), "", on=on)
        txt(d, (x0 + 5, y + 8), key, 12, GOLD, "lm", True)
        txt(d, (x0 + 18, y + 8), lab, 12, INK if on else DIM, "lm", True)


# ---------------------------------------------------------------- top-right: goods, clock, speed
def draw_resources(img, d):
    items = [("pop", "62/70", "3 idle", INK, DIM, 84), ("food", "142", "+6", INK, GREEN, 68), ("wood", "88", "+4", INK, GREEN, 68),
             ("stone", "64", "+3", INK, GREEN, 68), ("lumen", "36", "+9", INK, GREEN, 68),
             ("gold", "318", "+12", INK, GREEN, 72), ("planks", "12", "+1", RED, GREEN, 68)]
    total = sum(i[5] for i in items) + 88
    x0 = W - 8 - total - 12
    panel(d, (x0, 8, W - 8, 52))
    x = x0 + 12
    for k, val, delta, vc, dc, w in items:
        put_icon(img, k, x, 12, 2)
        txt(d, (x + 32, 22), val, 16, vc, "lm")
        txt(d, (x + 32, 40), delta, 12, dc, "lm", True)
        if k == "planks":  # pinned good: a small gold pin in the corner
            d.rectangle([x + w - 12, 12, x + w - 8, 15], fill=GOLD)
            d.rectangle([x + w - 11, 16, x + w - 9, 18], fill=GOLD)
            d.rectangle([x + w - 10, 19, x + w - 10, 21], fill=(190, 150, 60))
        x += w
    gx = W - 8 - 12 - 74
    button(d, (gx, 14, gx + 74, 46), "", hover=False)
    txt(d, (gx + 8, 30), "Goods", 16, INK, "lm")
    d.rectangle([gx + 58, 22, gx + 68, 36], fill=(24, 20, 18), outline=GOLD)
    txt(d, (gx + 64, 30), "E", 12, GOLD, "mm", True)
    return x0


def draw_clock(img, d, hour=14 + 20 / 60, label="Day 3, 14:20", speed=1):
    x0 = W - 8 - 348
    panel(d, (x0, 58, W - 8, 100))
    img.paste(U.dial_img(hour, 2).convert("RGB"), (x0 + 8, 62))
    txt(d, (x0 + 72, 70), label, 16, INK, "lm")
    txt(d, (x0 + 72, 88), "Year 2, Summer", 12, DIM, "lm", True)
    bx = x0 + 200
    for i, lab in enumerate(["||", "1x", "2x", "3x"]):
        b = (bx + i * 36, 64, bx + i * 36 + 32, 94)
        on = (i == speed)
        button(d, b, "", on=on)
        cx, cy = (b[0] + b[2]) // 2, (b[1] + b[3]) // 2
        if lab == "||":
            d.rectangle([cx - 5, cy - 6, cx - 2, cy + 6], fill=INK)
            d.rectangle([cx + 2, cy - 6, cx + 5, cy + 6], fill=INK)
        else:
            txt(d, (cx + 1, cy), lab, 16, GOLD if on else INK, "mm")


# ---------------------------------------------------------------- top-left: objectives
def draw_objectives(img, d):
    box = (8, 8, 322, 200)
    panel(d, box)
    txt(d, (20, 22), "Objectives", 16, GOLD, "lm")
    button(d, (294, 14, 314, 34), "", hover=False)  # collapse toggle
    d.rectangle([299, 23, 309, 24], fill=INK)
    txt(d, (20, 44), "Town -> City: gate parts", 12, DIM, "lm", True)
    rows = [("pop", "People", 62, 100, "62 / 100", GREEN), ("gold", "Gold", 318, 500, "318 / 500", GOLD)]
    y = 56
    for k, lab, a, b, val, bc in rows:
        put_icon(img, k, 18, y, 2)
        txt(d, (54, y + 8), lab, 12, INK, "lm", True)
        txt(d, (312, y + 8), val, 12, INK, "rm", True)
        bar(d, (54, y + 18, 312, y + 24), a / b, bc)
        y += 34
    put_icon(img, "lumen", 18, y, 2)
    txt(d, (54, y + 8), "Lumen Spire", 12, INK, "lm", True)
    txt(d, (312, y + 8), "not built", 12, RED, "rm", True)
    d.rectangle([54, y + 18, 312, y + 24], fill=BAR_BG, outline=(14, 12, 10))
    y += 36
    d.line([(18, y), (312, y)], fill=EDGE)
    put_icon(img, "moon", 18, y + 6, 2)
    txt(d, (54, y + 14), "Dimming in 2 days, lasts 3", 16, MOONC, "lm")
    txt(d, (54, y + 32), "Lumen output halves. Stock: 4 days.", 12, DIM, "lm", True)


# ---------------------------------------------------------------- bottom-centre: selection and town summary
SELX0, SELX1 = 234, 914


def portrait(img, d, sp, scale):
    d.rounded_rectangle([242, 578, 374, 706], 4, fill=(41, 54, 36), outline=(14, 12, 10), width=2)
    s = up(sp, scale)
    blit(img, s, (308 - s.width // 2, 700 - s.height))


def pips(d, x, y, n, of, col):
    for i in range(of):
        d.rectangle([x + i * 16, y, x + i * 16 + 11, y + 11], fill=col if i < n else SLOT, outline=(14, 12, 10) if i < n else EDGE)


def draw_selection(img, d):
    panel(d, (SELX0, 566, SELX1, 714))
    portrait(img, d, bsprite("sawmill"), 2)
    txt(d, (388, 592), "Sawmill", 24, GOLD, "lm")
    cw = tw("Tier II", 12, True)
    cx = 388 + tw("Sawmill", 24) + 12
    d.rounded_rectangle([cx, 582, cx + cw + 12, 600], 4, fill=BTN_ON, outline=GOLD)
    txt(d, (cx + 6, 591), "Tier II", 12, GOLD, "lm", True)
    txt(d, (388, 614), "Refining, Town era", 12, DIM, "lm", True)
    txt(d, (388, 636), "Workers", 12, FAINT, "lm", True)
    # day row (sun) and night row (moon)
    d.ellipse([388, 646, 400, 658], fill=(255, 190, 70))
    d.ellipse([390, 648, 398, 656], fill=(255, 232, 130))
    txt(d, (408, 652), "Day", 12, INK, "lm", True)
    pips(d, 448, 646, 2, 2, GREEN)
    txt(d, (488, 652), "2/2", 12, GREEN, "lm", True)
    blit(img, icon("moon", 1), (387, 664))
    txt(d, (408, 672), "Night", 12, INK, "lm", True)
    pips(d, 448, 666, 1, 2, AMBER)
    txt(d, (488, 672), "1/2", 12, AMBER, "lm", True)
    d.rectangle([388, 694, 394, 700], fill=GREEN)
    txt(d, (402, 697), "Working", 12, GREEN, "lm", True)
    # makes + buffers
    bx = 570
    txt(d, (bx, 586), "Makes", 12, FAINT, "lm", True)
    put_icon(img, "planks", bx + 54, 576, 2)
    txt(d, (bx + 90, 590), "6 planks / day", 16, INK, "lm")
    txt(d, (bx + 232, 590), "uses 12 wood", 12, DIM, "lm", True)
    d.line([(bx, 612), (SELX1 - 12, 612)], fill=EDGE)
    for i, (lab, k, have, cap, col) in enumerate([("In", "wood", 22, 40, (168, 116, 62)), ("Out", "planks", 9, 40, GOLD)]):
        y = 624 + i * 24
        txt(d, (bx, y + 8), lab, 12, FAINT, "lm", True)
        put_icon(img, k, bx + 34, y + 1, 1)
        bar(d, (bx + 56, y + 3, bx + 276, y + 13), have / cap, col)
        txt(d, (bx + 286, y + 8), f"{have} / {cap}", 12, INK, "lm", True)
    txt(d, (bx, 682), "Priority", 12, FAINT, "lm", True)
    x = bx + 50
    for lab, w, on in (("Low", 46, False), ("Normal", 66, True), ("High", 46, False)):
        button(d, (x, 672, x + w, 696), lab, on=on, size=12, body=True, col=INK if on else DIM)
        x += w + 4
    x += 10
    button(d, (x, 672, x + 62, 696), "Pause", size=12, body=True)


def stat_tile(img, d, x, y, icon_kind, val, lab, col=INK, glyph_kind=None):
    if glyph_kind:
        blit(img, glyph(glyph_kind), (x, y))
    else:
        put_icon(img, icon_kind, x, y, 2)
    txt(d, (x + 36, y + 10), val, 24, col, "lm")
    txt(d, (x + 36, y + 32), lab, 12, DIM, "lm", True)


def draw_town_summary(img, d):
    panel(d, (SELX0, 566, SELX1, 714))
    portrait(img, d, bsprite("hearth"), 1)
    txt(d, (388, 592), "Hearthvein", 24, GOLD, "lm")
    txt(d, (388, 614), "Town era, Year 2, Summer", 12, DIM, "lm", True)
    stat_tile(img, d, 388, 630, "pop", "62", "People")
    stat_tile(img, d, 500, 630, None, "70", "Beds", glyph_kind="housing")
    stat_tile(img, d, 612, 630, "pop", "3", "Idle", AMBER)
    for i, (k, lab, frac, val, col, extra) in enumerate([
            ("spirit", "Spirit", 0.74, "74", (120, 190, 90), "Good"),
            ("planet", "Planet", 0.81, "81", (120, 190, 90), "+0.4 this year")]):
        pass
    # bars: Spirit and Planet health, to the right of the tiles
    bx = 724
    for i, (k, lab, frac, val, extra) in enumerate([("spirit", "Spirit", 0.74, "74 / 100", "good"),
                                                    ("planet", "Planet", 0.81, "81 / 100", "+0.4 / yr")]):
        y = 584 + i * 40
        put_icon(img, k, bx, y, 2)
        txt(d, (bx + 36, y + 6), lab, 12, INK, "lm", True)
        txt(d, (SELX1 - 12, y + 6), val_text(val), 12, INK, "rm", True)
        bar(d, (bx + 36, y + 14, SELX1 - 12, y + 22), frac, (120, 190, 90))
        txt(d, (bx + 36, y + 30), extra, 12, DIM, "lm", True)
    txt(d, (388, 698), "Click a building to see it here. Esc clears the selection.", 12, FAINT, "lm", True)


def val_text(v):
    return v


# ---------------------------------------------------------------- bottom-right: command grid
CELL_W, CELL_H, GAP = 66, 44, 2
GX0, GY0 = 928, 572

TOP = [("roads", "Roads", "R"), ("housing", "Housing", "N"), ("food", "Food", "F"), ("water", "Water", "W"),
       ("lumen", "Lumen", "I"), ("logistics", "Logistics", "K"), ("resources", "Resources", "S"),
       ("refining", "Refining", "D"), ("civic", "Civic", "A"), ("demolish", "Demolish", "X"),
       ("upgrade", "Upgrade", "U"), ("clear", "Clear", "Z"), ("plant", "Plant", "Y"), ("region", "Region", "M"),
       ("help", "Help", "F1")]
REAL_ICON = {"food": "food", "lumen": "lumen", "resources": "wood", "refining": "planks"}
POSKEYS = ["Q", "W", "E", "R", "T", "A", "S", "D", "F", "G", "Z", "X", "C", "V", "B"]


def cell_box(i):
    r, c = divmod(i, 5)
    x = GX0 + c * (CELL_W + GAP)
    y = GY0 + r * (CELL_H + GAP)
    return (x, y, x + CELL_W - 1, y + CELL_H - 1)


def draw_grid_frame(d, title, hint):
    # tab over the grid panel
    tabw = tw(title, 16) + 24
    d.rounded_rectangle([GX0 - 6, 540, GX0 - 6 + tabw, 570], 6, fill=PANEL, outline=EDGE, width=2)
    txt(d, (GX0 + 6, 554), title, 16, GOLD, "lm")
    txt(d, (1266, 554), hint, 12, FAINT, "rm", True)
    panel(d, (922, 566, 1272, 714))


def draw_cell(img, d, i, label, key, ic=None, thumb=None, state="ok", hover=False, label_col=None, dx=0):
    b = cell_box(i)
    fill = BTN_HOV if hover else BTN
    edge = GOLD if hover else None
    if state == "short":
        fill, edge = (92, 36, 30), (200, 80, 66)
    if state == "locked":
        fill = (30, 28, 26)
    d.rounded_rectangle(b, 4, fill=fill, outline=edge, width=2 if edge else 0)
    cx = (b[0] + b[2]) // 2
    pic = thumb if thumb is not None else ic
    if pic is not None:
        blit(img, pic, (cx - pic.width // 2 + 1 + dx, b[1] + 31 - pic.height if thumb is not None else b[1] + 1))
    lc = label_col or (DIM if state == "locked" else INK)
    txt(d, (cx + 1, b[1] + 38), label, 12, lc, "mm", True)
    txt(d, (b[0] + 4, b[1] + 3), key, 12, GOLD if state != "locked" else FAINT, "la", True)
    if state == "locked":
        U.lock(img, cx - 8, b[1] + 8, 2)


def draw_top_grid(img, d, hover=None):
    draw_grid_frame(d, "Build", "R road   X demolish")
    for i, (kind, label, key) in enumerate(TOP):
        ic = icon(REAL_ICON[kind], 2) if kind in REAL_ICON else glyph(kind)
        draw_cell(img, d, i, label, key, ic=ic, hover=(hover == kind))


def thumb(name, grey=False):
    sp = bsprite(name)
    sp = sp.resize((max(1, sp.width // 2), max(1, sp.height // 2)), Image.NEAREST)
    if grey:
        a = sp.getchannel("A")
        g = sp.convert("L").convert("RGBA")
        g.putalpha(a.point(lambda v: v * 2 // 5))
        return g
    return sp


REFINING = [("kitchen", "Kitchen", "ok"), ("mason", "Mason", "ok"), ("refinery", "Refinery", "short"),
            ("workshop", "Workshop", "ok"), ("sawmill", "Sawmill", "ok"), ("toolsmith", "Toolsmith", "locked")]


def draw_category_grid(img, d, hover="refinery"):
    draw_grid_frame(d, "Refining", "Esc: back")
    for i, (bid, label, state) in enumerate(REFINING):
        draw_cell(img, d, i, label, POSKEYS[i], thumb=thumb(bid, state == "locked"), state=state, hover=(hover == bid))
    draw_cell(img, d, 14, "Back", "Esc", ic=glyph("back"), dx=10)


def draw_hover_card(img, d):
    box = (968, 280, 1272, 538)
    panel(d, box, fill=(20, 17, 14, 250), edge=GOLD)
    x0, y0 = box[0] + 12, box[1] + 12
    d.rounded_rectangle([x0, y0, x0 + 80, y0 + 80], 4, fill=(41, 54, 36), outline=(14, 12, 10), width=2)
    sp = up(bsprite("refinery"), 1)
    blit(img, sp, (x0 + 40 - sp.width // 2, y0 + 76 - sp.height))
    txt(d, (x0 + 94, y0 + 14), "Refinery", 24, GOLD, "lm")
    txt(d, (x0 + 94, y0 + 36), "Refining, Town era", 12, DIM, "lm", True)
    txt(d, (x0 + 94, y0 + 54), "Size 2x2   Workers 2", 12, INK, "lm", True)
    txt(d, (x0 + 94, y0 + 70), "Hotkey E", 12, FAINT, "lm", True)
    d.line([(x0, y0 + 90), (box[2] - 12, y0 + 90)], fill=EDGE)
    txt(d, (x0, y0 + 102), "Turns Lumen into Lumen cells,", 12, INK, "lm", True)
    txt(d, (x0, y0 + 119), "which power the finest buildings.", 12, INK, "lm", True)
    txt(d, (x0, y0 + 140), "Cost", 12, FAINT, "lm", True)
    cost = [("wood", 24, 88), ("stone", 36, 64), ("gold", 20, 318), ("planks", 15, 12)]
    for i, (k, n, have) in enumerate(cost):
        x = x0 + i * 70
        short = have < n
        put_icon(img, k, x, y0 + 150, 2)
        txt(d, (x + 32, y0 + 164), str(n), 16, RED if short else INK, "lm")
        txt(d, (x + 2, y0 + 190), f"have {have}", 12, RED if short else FAINT, "lm", True)
    txt(d, (x0, y0 + 212), "Makes", 12, FAINT, "lm", True)
    put_icon(img, "lumen", x0 + 44, y0 + 200, 2)
    txt(d, (x0 + 78, y0 + 214), "12", 16, INK, "lm")
    txt(d, (x0 + 104, y0 + 214), "->", 12, DIM, "lm", True)
    put_icon(img, "cells", x0 + 124, y0 + 200, 2)
    txt(d, (x0 + 158, y0 + 214), "2 cells / day", 16, INK, "lm")
    # the card points at its cell
    cb = cell_box(2)
    cx = (cb[0] + cb[2]) // 2
    d.polygon([(cx - 6, box[3] - 1), (cx + 6, box[3] - 1), (cx, box[3] + 7)], fill=(20, 17, 14))
    d.line([(cx - 6, box[3]), (cx, box[3] + 7), (cx + 6, box[3])], fill=GOLD, width=2)


def draw_notice(img, d, x=SELX0, y=520):
    text = "Dimming in 2 days: Lumen output will halve"
    w = int(tw(text, 16, True)) + 56
    panel(d, (x, y, x + w, y + 38), edge=CYAN)
    put_icon(img, "moon", x + 10, y + 5, 2)
    txt(d, (x + 46, y + 19), text, 16, INK, "lm", True)


# ---------------------------------------------------------------- the whole new HUD
def new_hud(img, mode="sel", night=False):
    d = draw(img)
    draw_objectives(img, d)
    draw_resources(img, d)
    if night:
        draw_clock(img, d, 22 + 40 / 60, "Day 3, 22:40", speed=1)
    else:
        draw_clock(img, d)
    draw_minimap_panel(img, d, minimap(night))
    if mode == "sel":
        draw_selection(img, d)
        draw_top_grid(img, d)
        draw_notice(img, d)
    elif mode == "cat":
        draw_selection(img, d)
        draw_category_grid(img, d)
        draw_hover_card(img, d)
        draw_notice(img, d)
    else:
        draw_town_summary(img, d)
        draw_top_grid(img, d)
        draw_notice(img, d)
    return img


# ---------------------------------------------------------------- the current HUD (ui/hud.gd), for the comparison
def old_hud(img):
    d = draw(img)
    # top bar: nine goods (value over delta), people + growth bar, Spirit bar, planet, Ground (Tab), Overlays
    panel(d, (6, 6, W - 6, 58), r=4)
    x = 16
    goods = [("food", "142", "+6"), ("wood", "88", "+4"), ("stone", "64", "+3"), ("planks", "12", "+1"),
             ("cut_stone", "9", "0"), ("tools", "2", "0"), ("lumen", "36", "+9"), ("cells", "3", "0"), ("gold", "318", "+12")]
    for k, v, dl in goods:
        put_icon(img, k, x, 16, 2)
        txt(d, (x + 32, 26), v, 16, RED if k == "planks" else INK, "lm")
        txt(d, (x + 32, 44), dl, 12, GREEN if dl.startswith("+") else DIM, "lm", True)
        x += 78
    put_icon(img, "pop", x, 16, 2)
    txt(d, (x + 32, 32), "62 / 70", 16, INK, "lm")
    bar(d, (x + 92, 28, x + 130, 36), 0.4, (120, 190, 90))
    x += 142
    put_icon(img, "spirit", x, 16, 2)
    bar(d, (x + 34, 24, x + 124, 40), 0.74, (120, 190, 90))
    txt(d, (x + 130, 32), "74", 12, INK, "lm", True)
    x += 156
    put_icon(img, "planet", x, 16, 2)
    txt(d, (x + 32, 32), "81", 12, INK, "lm", True)
    for lab, bx0, bx1 in (("Ground (Tab)", 1086, 1190), ("Overlays", 1196, 1272)):
        button(d, (bx0, 16, bx1, 48), lab, size=12, body=True)
    # era panel under the bar, right
    ex0 = W - 6 - 360
    panel(d, (ex0, 64, W - 6, 232), r=4)
    txt(d, (ex0 + 12, 80), "Era: Town", 16, GOLD, "lm")
    img.paste(U.dial_img(14 + 20 / 60, 2).convert("RGB"), (ex0 + 12, 96))
    txt(d, (ex0 + 80, 110), "Day 3, 14:20", 16, INK, "lm")
    txt(d, (ex0 + 80, 128), "Year 2, Summer", 12, DIM, "lm", True)
    put_icon(img, "moon", ex0 + 12, 136, 2)
    txt(d, (ex0 + 48, 150), "Dimming in 2 days - lasts 3", 16, (200, 210, 240), "lm")
    txt(d, (ex0 + 12, 176), "Lumen output halves. Stock: 4 days.", 12, (200, 210, 240), "lm", True)
    txt(d, (ex0 + 12, 196), "Next: City  pop 62/100  gold 318/500", 12, DIM, "lm", True)
    txt(d, (ex0 + 12, 212), "Lumen Spire not built", 12, DIM, "lm", True)
    # selection panel (old: a plain text list on the left)
    panel(d, (6, 64, 306, 250), r=4)
    txt(d, (18, 82), "Sawmill", 16, CYAN, "lm")
    for i, ln in enumerate(["Workers 2/2 (day), 1/2 (night)", "Makes 6 planks per day", "Wood 22/40 in, planks 9/40 out",
                            "Working"]):
        txt(d, (18, 106 + i * 18), ln, 12, INK, "lm", True)
    txt(d, (18, 184), "Priority", 12, DIM, "lm", True)
    x = 18
    for lab, w, on in (("Low", 42, False), ("Normal", 62, True), ("High", 42, False), ("Pause", 54, False)):
        button(d, (x, 196, x + w, 220), lab, on=on, size=12, body=True)
        x += w + 4
    # notice, top centre
    text = "Dimming in 2 days: Lumen output will halve"
    w = int(tw(text, 12, True)) + 24
    panel(d, ((W - w) // 2 - 80, 66, (W - w) // 2 - 80 + w, 92), edge=CYAN, r=4)
    txt(d, ((W - w) // 2 - 68, 79), text, 12, INK, "lm", True)
    # bottom: plain category bar, one row of eleven
    cats = ["Roads", "Housing", "Food", "Resources", "Lumen", "Refining", "Gold", "Water", "Logistics", "Civic", "Landmark"]
    panel(d, (6, H - 54, W - 6, H - 6), r=4)
    pad = 12
    widths = [tw(c, 16) + 2 * pad for c in cats]
    gap = (W - 12 - 16 - sum(widths)) / (len(cats) - 1)
    x = 14
    for c, w in zip(cats, widths):
        button(d, (int(x), H - 46, int(x + w), H - 14), c, size=16)
        x += w + gap
    return img


# ---------------------------------------------------------------- frames
def frame_day(mode):
    big, _ = world_map(False)
    return new_hud(big, mode)


def frame_night():
    big, _ = world_map(True)
    return new_hud(big, "sel", night=True)


def frame_compare():
    big, _ = world_map(False)
    old = old_hud(big.copy())
    new = new_hud(big.copy(), "sel")
    sw, sh = 612, 344
    old_s = old.resize((sw, sh), Image.BOX)
    new_s = new.resize((sw, sh), Image.BOX)
    img = Image.new("RGB", (W, H), (28, 26, 23))
    d = draw(img)
    txt(d, (20, 16), "HUD: Now and New", 24, GOLD, "lm")
    txt(d, (W - 20, 16), "Both shown at 0.48x of 1280x720", 12, FAINT, "rm", True)
    for i, (lab, im) in enumerate((("Now", old_s), ("New", new_s))):
        x = 20 + i * (sw + 16)
        txt(d, (x, 62), lab, 20, GOLD if i else INK, "lm")
        img.paste(im, (x, 80))
        d.rectangle([x - 1, 79, x + sw, 80 + sh], outline=EDGE)
    notes = [
        [("-", "12 numbers across the whole top edge: nine goods, people, Spirit, planet"),
         ("-", "Era, clock and Dimming sit in a tall panel that covers the map's corner"),
         ("-", "Selection is a text list; commands are one plain row of 11 buttons"),
         ("-", "Notices float in mid-screen, over the town")],
        [("+", "Six numbers top-right; Goods (E) opens the rest, any good can be pinned"),
         ("+", "Objectives top-left: gate parts and the Dimming forecast, collapsible"),
         ("+", "Minimap bottom-left; selection panel bottom-centre with a big picture"),
         ("+", "5x3 command grid with hotkeys; notices stack above the selection panel")],
    ]
    for i, lst in enumerate(notes):
        x = 20 + i * (sw + 16)
        for j, (sg, ln) in enumerate(lst):
            y = 470 + j * 34
            txt(d, (x, y), sg, 16, RED if sg == "-" else GREEN, "lm", True)
            txt(d, (x + 16, y), ln, 12, INK, "lm", True)
    txt(d, (20, 640), "Bottom band: Now 54 px of category buttons; New 148 px with minimap, selection panel and command grid.", 12, DIM, "lm", True)
    return img


def main():
    out = Path(sys.argv[1]) if len(sys.argv) > 1 else OUT_DEFAULT
    out.mkdir(parents=True, exist_ok=True)
    frames = (("hud_town_day", lambda: frame_day("sel")), ("hud_category_open", lambda: frame_day("cat")),
              ("hud_nothing_selected", lambda: frame_day("none")), ("hud_compare", frame_compare),
              ("hud_night", frame_night))
    for name, fn in frames:
        im = fn()
        assert im.size == (W, H), (name, im.size)
        im.convert("RGB").save(out / f"{name}.png")
    print("wrote", *sorted(p.name for p in out.glob("*.png")))


if __name__ == "__main__":
    main()
