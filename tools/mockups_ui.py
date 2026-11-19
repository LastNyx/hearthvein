"""Hearthvein 1.1.6 UI mockups (ticket 106): five 1280x720 pictures for Ben to approve before anything is wired.

Usage: python3 tools/mockups_ui.py <out_dir>
Writes icons_sheet.png, clock_bar.png, resources_page.png, workforce_page.png, build_menu.png.
Mockup art only: numbers are made up except building names, costs, sizes and recipes (data/buildings/*.tres).
"""
import math
import random
import sys
from pathlib import Path

from PIL import Image, ImageDraw

sys.path.insert(0, str(Path(__file__).resolve().parent))
import mockups_v1 as M  # noqa: E402  (its OUT reads argv[1] but is not used here)

ROOT = Path(__file__).resolve().parent.parent
W, H = 1280, 720
PANEL = (28, 26, 23, 238)
PANEL_SOLID = (28, 26, 23, 255)
BORDER = (90, 80, 70)
GOLD = (242, 210, 122)
TEXT = (236, 226, 206)
DIM = (170, 160, 150)
FAINT = (110, 102, 94)
GREEN = (140, 200, 100)
RED = (226, 100, 86)
CYAN = (127, 224, 240)
ROW_SEL = (62, 54, 42)

# top bar order (the real bar will show these nine)
GOODS = ["food", "wood", "stone", "planks", "cut_stone", "tools", "lumen", "cells", "gold"]
NAMES = {"food": "Food", "wood": "Wood", "stone": "Stone", "planks": "Planks", "cut_stone": "Cut stone",
         "tools": "Tools", "lumen": "Lumen", "cells": "Lumen cells", "gold": "Gold", "people": "Citizens"}
STOCK = {"food": 142, "wood": 88, "stone": 64, "planks": 12, "cut_stone": 9, "tools": 2, "lumen": 36,
         "cells": 3, "gold": 51}
DELTA = {"food": 6, "wood": 4, "stone": 3, "planks": 1, "cut_stone": 0, "tools": 0, "lumen": 9, "cells": 0, "gold": 2}


# ---------------------------------------------------------------- helpers
def new_canvas():
    return Image.new("RGBA", (W, H), M.hexc("1c1a17"))


def txt(d, xy, s, size=16, col=TEXT, anchor="la"):
    d.text(xy, s, font=M.font(size), fill=col, anchor=anchor)


def tw(s, size):
    return M.font(size).getlength(s)


def panel(d, box, fill=PANEL, border=BORDER, r=8, width=2):
    d.rounded_rectangle(box, r, fill=fill, outline=border, width=width)


def put_icon(img, kind, x, y, s=3):
    img.alpha_composite(M.upscale(M.icon_v2(kind), s), (x, y))


def backdrop(dark=0.0):
    """The village scene at 2x (what the game looks like behind the UI), optionally darkened."""
    scene = M.upscale(M.render_scene(False), 2)
    scene = scene.crop((192, 150, 192 + W, 150 + H))  # the scene is 1664x1024 at 2x: take a 1280x720 window
    if dark:
        shade = Image.new("RGBA", scene.size, (10, 8, 6, int(255 * dark)))
        scene.alpha_composite(shade)
    return scene


def top_bar(img, date_right=None, dial_hour=None, spirit=False):
    """The HUD's top bar with the nine goods; Spirit is left out of these mockups to make room."""
    d = ImageDraw.Draw(img, "RGBA")
    d.rectangle([0, 0, W, 52], fill=(24, 20, 18, 232))
    x = 16
    for k in GOODS:
        put_icon(img, k, x, 5)
        low = k == "planks"
        txt(d, (x + 46, 19), str(STOCK[k]), 18, RED if low else TEXT, "lm")
        dl = DELTA[k]
        txt(d, (x + 46, 39), f"{dl:+d}" if dl else "0", 13, GREEN if dl > 0 else DIM, "lm")
        x += 104
    put_icon(img, "people", x, 5)
    txt(d, (x + 46, 19), "23 / 28", 18, TEXT, "lm")
    txt(d, (x + 46, 39), "3 idle", 13, DIM, "lm")
    if date_right:
        dial = dial_img(dial_hour, 2)
        img.alpha_composite(dial, (1080, 10))
        txt(d, (1146, 26), date_right, 17, TEXT, "lm")
    if spirit:
        img.alpha_composite(M.upscale(M.icon("spirit"), 3), (1084, 5))
        d.rectangle([1132, 18, 1252, 34], fill=(60, 50, 50))
        d.rectangle([1132, 18, 1132 + 88, 34], fill=(120, 190, 90))


def build_bar(img, sel):
    d = ImageDraw.Draw(img, "RGBA")
    cats = ["Roads", "Housing", "Food", "Water", "Lumen", "Logistics", "Resources", "Refining", "Gold", "Civic",
            "Landmark"]
    bw, gap = 100, 6
    bx = (W - len(cats) * (bw + gap) + gap) // 2
    d.rectangle([0, H - 64, W, H], fill=(24, 20, 18, 232))
    for i, c in enumerate(cats):
        x0 = bx + i * (bw + gap)
        s = c == sel
        d.rounded_rectangle([x0, H - 54, x0 + bw, H - 12], 6, fill=(70, 60, 50) if s else (44, 38, 34),
                            outline=GOLD if s else None, width=2)
        txt(d, (x0 + bw // 2, H - 33), c, 15, TEXT, "mm")


# ---------------------------------------------------------------- day/night dial
_SKY = [(0, (18, 24, 52)), (5, (30, 34, 70)), (6, (200, 116, 84)), (7.5, (110, 160, 206)),
        (16.5, (110, 160, 206)), (18, (214, 120, 76)), (19.5, (30, 34, 70)), (24, (18, 24, 52))]


def sky_colour(h):
    for (h0, c0), (h1, c1) in zip(_SKY, _SKY[1:]):
        if h0 <= h <= h1:
            t = (h - h0) / (h1 - h0)
            return tuple(round(a + (b - a) * t) for a, b in zip(c0, c1))
    return _SKY[-1][1]


def dial_art(hour):
    """28x16 art pixels: sky by hour, ground strip, the sun on its arc by day (06-18), the moon by night."""
    sky = sky_colour(hour % 24)
    im = Image.new("RGBA", (28, 16), sky + (255,))
    d = ImageDraw.Draw(im)
    night = not 6 <= hour % 24 < 18
    if night:
        rng = random.Random(7)
        for _ in range(7):
            im.putpixel((rng.randrange(1, 27), rng.randrange(1, 8)), (200, 210, 240, 255))
    t = (hour % 24 - 6) / 12 if not night else ((hour % 24 - 18) % 24) / 12
    for i in range(1, 12):  # the arc, dotted
        a = math.pi * i / 12
        px, py = round(14 - 11 * math.cos(a)), round(12.5 - 9.5 * math.sin(a))
        im.putpixel((px, py), tuple(min(255, c + 40) for c in sky) + (255,))
    a = math.pi * t
    cx, cy = 14 - 11 * math.cos(a), 12.5 - 9.5 * math.sin(a)
    if night:
        d.ellipse([cx - 2.6, cy - 2.6, cx + 2.6, cy + 2.6], fill=(214, 222, 248, 255))
        d.ellipse([cx - 1.2, cy - 3.4, cx + 3.6, cy + 1.4], fill=sky + (255,))
    else:
        d.ellipse([cx - 3.4, cy - 3.4, cx + 3.4, cy + 3.4], fill=(255, 190, 70, 255))
        d.ellipse([cx - 2.4, cy - 2.4, cx + 2.4, cy + 2.4], fill=(255, 232, 130, 255))
    d.rectangle([0, 13, 27, 15], fill=(44, 66, 40, 255))
    d.line([(0, 13), (27, 13)], fill=(78, 110, 60, 255))
    return im


def dial_img(hour, s):
    im = M.upscale(dial_art(hour), s)
    d = ImageDraw.Draw(im)
    d.rectangle([0, 0, im.width - 1, im.height - 1], outline=(90, 80, 70, 255), width=2)
    return im


# ---------------------------------------------------------------- 1. icon sheet
def icons_sheet():
    img = new_canvas()
    d = ImageDraw.Draw(img, "RGBA")
    txt(d, (40, 24), "Icon set 1.1.6: preview", 30, GOLD)
    txt(d, (40, 64), "New icons are 12x12 art with a 1 px dark outline (14x14 file), drawn at 3x in the game.", 15, DIM)
    txt(d, (40, 84), "Old icons are shown for comparison; planks, cut stone, tools and cells have no old icon.", 15, DIM)
    kinds = M.ICON_V2_KINDS
    old = {"wood": "wood", "stone": "stone", "food": "food", "lumen": "lumen", "gold": "gold", "people": "pop"}
    colw = 108
    x0 = 140
    rows = [("New 4x", 150), ("New 1x, 2x", 238), ("Old 4x", 306), ("Old 1x", 396)]
    for label_, y in rows:
        txt(d, (24, y), label_, 13, FAINT)
    panel(d, (x0 - 8, 112, x0 + colw * len(kinds) + 8, 424), fill=(34, 31, 27, 255), r=6, width=1)
    for i, k in enumerate(kinds):
        cx = x0 + i * colw + colw // 2
        txt(d, (cx, 122), k, 16, TEXT, "mt")
        im = M.icon_v2(k)
        img.alpha_composite(M.upscale(im, 4), (cx - 28, 148))
        img.alpha_composite(im, (cx - 24, 236))
        img.alpha_composite(M.upscale(im, 2), (cx + 2, 226))
        if k in old:
            o = M.icon(old[k])
            img.alpha_composite(M.upscale(o, 4), (cx - 28, 296))
            img.alpha_composite(o, (cx - 7, 394))
        else:
            txt(d, (cx, 322), "(none)", 14, FAINT, "mt")
    # as in the game: top bar strip at 3x, then on the map green at 1x/2x/3x
    txt(d, (40, 446), "In the top bar (3x, on the HUD panel)", 16, GOLD)
    panel(d, (40, 474, W - 40, 540), fill=(24, 20, 18, 255))
    x = 60
    for k in kinds:
        put_icon(img, k, x, 486)
        txt(d, (x + 46, 507), str(STOCK.get(k, 23)), 18, TEXT, "lm")
        x += 118
    txt(d, (40, 564), "On the map green (1x, 2x, 3x): readable without the panel behind", 16, GOLD)
    d.rectangle([40, 592, W - 40, 676], fill=M.P["grass"])
    rng = random.Random(3)
    for _ in range(260):
        gx, gy = rng.randrange(40, W - 40), rng.randrange(592, 676)
        d.point((gx, gy), fill=M.P["grass_l"] if rng.random() < 0.5 else M.P["grass_d"])
    x = 56
    for k in kinds:
        im = M.icon_v2(k)
        img.alpha_composite(im, (x, 628))
        img.alpha_composite(M.upscale(im, 2), (x + 20, 616))
        img.alpha_composite(M.upscale(im, 3), (x + 54, 604))
        x += 118
    return img


# ---------------------------------------------------------------- 2. clock bar
def clock_bar():
    img = new_canvas()
    d = ImageDraw.Draw(img, "RGBA")
    txt(d, (40, 20), "Clock bar: two places for the dial", 30, GOLD)
    txt(d, (40, 62), 'Date reads "Day 3, 06:40" (whole hours from the sim, minutes interpolated while drawing). '
        "Sun arc 06-18, moon by night.", 15, DIM)
    base = backdrop()
    shots = []
    for var in "AB":
        s = base.copy()
        top_bar(s, "Day 3, 06:40" if var == "B" else None, 6 + 40 / 60, spirit=var == "A")
        sd = ImageDraw.Draw(s, "RGBA")
        px, pw = W - 360 - 14, 360
        if var == "A":
            ph = 128
            panel(sd, (px, 64, W - 14, 64 + ph), fill=(24, 20, 18, 235))
            txt(sd, (px + 14, 74), "Era: Town", 18, GOLD)
            s.alpha_composite(dial_img(6 + 40 / 60, 2), (px + 14, 102))
            txt(sd, (px + 84, 112), "Day 3, 06:40", 20, TEXT, "lm")
            txt(sd, (px + 84, 134), "Year 3, Summer", 14, DIM, "lm")
            s.alpha_composite(M.upscale(M.icon("moon"), 2), (px + 14, 144))
            txt(sd, (px + 46, 156), "Dimming in 2 days - lasts 3", 17, (200, 210, 240), "lm")
        else:
            panel(sd, (px, 64, W - 14, 64 + 98), fill=(24, 20, 18, 235))
            txt(sd, (px + 14, 74), "Era: Town", 18, GOLD)
            s.alpha_composite(M.upscale(M.icon("moon"), 2), (px + 14, 106))
            txt(sd, (px + 46, 118), "Dimming in 2 days - lasts 3", 17, (200, 210, 240), "lm")
            txt(sd, (px + 14, 144), "Year 3, Summer", 14, DIM, "lm")
        shots.append(s.crop((636, 0, 1272, 200)))
    for i, (var, title, lines) in enumerate([
        ("A", "A: dial left of the date, in the era panel",
         ["+ time, season and Dimming forecast sit together in one panel",
          "+ the top bar keeps room for goods, citizens and the Spirit bar",
          "- the clock is a glance away from the top bar"]),
        ("B", "B: dial in the top bar, right",
         ["+ always at the same place, reads like a status bar",
          "- no room left for the Spirit bar at 1280 wide (it would move)",
          "- the date sits apart from the season and Dimming lines"]),
    ]):
        x = 2 + i * 640
        txt(d, (x + 2, 100), title, 20, TEXT)
        img.alpha_composite(shots[i], (x, 134))
        d.rectangle([x - 1, 133, x + 636, 334], outline=BORDER)
        for j, ln in enumerate(lines):
            txt(d, (x + 2, 350 + j * 24), ln, 15, GREEN if ln.startswith("+") else (RED if ln.startswith("-") else DIM))
    txt(d, (20, 440), "Dial by hour (same art in both variants, shown at 5x)", 20, TEXT)
    hours = [(6 + 40 / 60, "06:40"), (9, "09:00"), (12, "12:00"), (18.5, "18:30"), (21, "21:00"), (2, "02:00")]
    for i, (h, lab) in enumerate(hours):
        x = 20 + i * 208
        img.alpha_composite(dial_img(h, 5), (x, 480))
        txt(d, (x + 70, 570), lab, 16, TEXT, "mt")
    txt(d, (20, 612), "Both bars show nine goods and citizens at 3x icons; hover for the full ledger (press E).", 14, DIM)
    return img


# ---------------------------------------------------------------- shared page frame
def page_frame(title, hint="Esc closes", pw=900, ph=560):
    img = backdrop(0.55)
    top_bar(img)
    build_bar(img, None)
    d = ImageDraw.Draw(img, "RGBA")
    px, py = (W - pw) // 2, (H - ph) // 2
    panel(d, (px, py, px + pw, py + ph), fill=PANEL_SOLID, border=(150, 128, 80), r=10, width=2)
    txt(d, (px + 24, py + 14), title, 26, GOLD)
    txt(d, (px + pw - 24, py + 24), hint, 14, FAINT, "rm")
    d.line([(px + 16, py + 52), (px + pw - 16, py + 52)], fill=BORDER)
    return img, d, px, py


# ---------------------------------------------------------------- 3. resources page
LEDGER = {  # stock, change/day, made yesterday, used yesterday
    "food": (142, 6, 96, 90), "wood": (88, 4, 48, 44), "stone": (64, 3, 36, 33), "planks": (12, 1, 15, 14),
    "cut_stone": (9, 0, 6, 6), "tools": (2, 0, 0, 0), "lumen": (36, 9, 40, 31), "cells": (3, 0, 2, 2),
    "gold": (51, 2, 12, 10),
}


def series(n, end, seed):
    rng = random.Random(seed)
    v = [end * 0.5]
    for _ in range(n - 1):
        v.append(max(2, v[-1] + rng.uniform(-6, 8) + (end - v[-1]) * 0.05))
    v[-1] = end
    return v


def resources_page():
    img, d, px, py = page_frame("Resources (E)", "Esc or E closes. Click a row to chart it.")
    cols = {"stock": 250, "chg": 352, "made": 472, "used": 592}
    y = py + 62
    txt(d, (px + 24, y), "Good", 14, FAINT)
    for k, lab in (("stock", "Stock"), ("chg", "Change/day"), ("made", "Made yesterday"), ("used", "Used yesterday")):
        txt(d, (px + cols[k], y), lab, 14, FAINT, "ra")
    rh = 30
    y0 = y + 26
    sel = "wood"
    for i, k in enumerate(GOODS[:7] + ["cells", "gold"]):
        ry = y0 + i * rh
        st, ch, made, used = LEDGER[k]
        if k == sel:
            d.rectangle([px + 16, ry, px + 604, ry + rh - 2], fill=ROW_SEL)
            d.rectangle([px + 16, ry, px + 19, ry + rh - 2], fill=GOLD)
        elif i % 2:
            d.rectangle([px + 16, ry, px + 604, ry + rh - 2], fill=(34, 31, 27, 255))
        put_icon(img, k, px + 28, ry, 2)
        txt(d, (px + 62, ry + rh // 2 - 1), NAMES[k], 16, TEXT, "lm")
        cy = ry + rh // 2 - 1
        txt(d, (px + cols["stock"], cy), str(st), 16, TEXT, "rm")
        txt(d, (px + cols["chg"], cy), f"{ch:+d}" if ch else "0", 16, GREEN if ch > 0 else DIM, "rm")
        txt(d, (px + cols["made"], cy), str(made), 16, TEXT if made else FAINT, "rm")
        txt(d, (px + cols["used"], cy), str(used), 16, TEXT if used else FAINT, "rm")
    # hovered Made cell of Wood: underline + cursor + hover box
    wy = y0 + GOODS.index("wood") * rh
    d.line([(px + cols["made"] - 24, wy + rh - 3), (px + cols["made"], wy + rh - 3)], fill=GOLD, width=2)
    d.polygon([(px + cols["made"] + 6, wy + 16), (px + cols["made"] + 6, wy + 34), (px + cols["made"] + 11, wy + 29),
               (px + cols["made"] + 17, wy + 29)], fill=(250, 250, 250), outline=(20, 20, 20))
    bx, by, bw, bh = px + 624, wy - 4, 252, 232
    panel(d, (bx, by, bx + bw, by + bh), fill=(20, 17, 14, 250), border=GOLD)
    txt(d, (bx + 14, by + 10), "Wood made yesterday: 48", 16, GOLD)
    made_by = [("Woodcutter x3", 30), ("Forester x1", 6), ("Clearing trees", 12)]
    for j, (n, v) in enumerate(made_by):
        txt(d, (bx + 14, by + 44 + j * 24), n, 15, TEXT)
        txt(d, (bx + bw - 14, by + 44 + j * 24), str(v), 15, TEXT, "ra")
        d.rectangle([bx + 14, by + 64 + j * 24, bx + 14 + int((bw - 28) * v / 48), by + 66 + j * 24],
                    fill=(168, 116, 62))
    d.line([(bx + 14, by + 124), (bx + bw - 14, by + 124)], fill=BORDER)
    txt(d, (bx + 14, by + 134), "Used yesterday: 44", 16, GOLD)
    for j, (n, v) in enumerate([("Sawmill", 24), ("Building sites", 20)]):
        txt(d, (bx + 14, by + 168 + j * 24), n, 15, TEXT)
        txt(d, (bx + bw - 14, by + 168 + j * 24), str(v), 15, TEXT, "ra")
    # 60-day chart
    cx0, cy0, cx1, cy1 = px + 24, py + 362, px + 876, py + 544
    panel(d, (cx0, cy0, cx1, cy1), fill=(22, 20, 17, 255), r=6, width=1)
    put_icon(img, sel, cx0 + 10, cy0 + 6, 2)
    txt(d, (cx0 + 46, cy0 + 20), "Wood stock, last 60 days", 16, TEXT, "lm")
    ser = series(60, 88, 11)
    lo, hi = 0, 120
    gx0, gy0, gx1, gy1 = cx0 + 56, cy0 + 40, cx1 - 24, cy1 - 30
    for v in (0, 40, 80, 120):
        yy = gy1 - (gy1 - gy0) * (v - lo) / (hi - lo)
        d.line([(gx0, yy), (gx1, yy)], fill=(52, 47, 41))
        txt(d, (gx0 - 8, yy), str(v), 13, FAINT, "rm")
    pts = [(gx0 + (gx1 - gx0) * i / 59, gy1 - (gy1 - gy0) * (v - lo) / (hi - lo)) for i, v in enumerate(ser)]
    d.polygon(pts + [(gx1, gy1), (gx0, gy1)], fill=(168, 116, 62, 70))
    d.line(pts, fill=(224, 164, 90), width=2)
    d.ellipse([pts[-1][0] - 4, pts[-1][1] - 4, pts[-1][0] + 4, pts[-1][1] + 4], fill=GOLD)
    for i, lab in ((0, "60 days ago"), (30, "30"), (59, "today")):
        xx = gx0 + (gx1 - gx0) * i / 59
        txt(d, (xx, gy1 + 6), lab, 13, FAINT, "ma" if i == 30 else ("la" if i == 0 else "ra"))
    txt(d, (pts[-1][0] - 10, pts[-1][1] - 14), "88", 14, GOLD, "ra")
    return img


# ---------------------------------------------------------------- 4. workforce page
def workforce_page():
    img, d, px, py = page_frame("Workforce (Q)", "Esc or Q closes")
    txt(d, (px + 24, py + 62), "Workers 42, idle 3, haulers 9, builders 8", 18, TEXT)
    txt(d, (px + 876, py + 62), "Priority orders jobs inside a category only", 13, FAINT, "ra")
    # columns
    cx = {"name": px + 40, "work": px + 350, "low": px + 400, "norm": px + 458, "high": px + 530, "pause": px + 596,
          "note": px + 690}
    ch = py + 96
    for k, lab, anc in (("name", "Building", "la"), ("work", "Workers", "ma"), ("low", "Priority", "la"),
                        ("pause", "", "la"), ("note", "Note", "la")):
        if lab:
            txt(d, (cx[k], ch), lab, 13, FAINT, anc)
    d.line([(px + 16, ch + 22), (px + 884, ch + 22)], fill=BORDER)
    rows = [
        ("hdr", "Construction sites", "build"),
        ("row", "Sawmill (site)", "builders 4/4", "Normal", False, "waiting for stone"),
        ("row", "Mason (site)", "builders 3/4", "High", False, ""),
        ("hdr", "Food", "food"),
        ("row", "Farm", "3/3", "High", False, ""),
        ("row", "Forager", "2/2", "Normal", False, ""),
        ("row", "Fishing Dock", "1/2", "Normal", False, "1 short"),
        ("hdr", "Water", "water"),
        ("row", "Well", "0/0", "Normal", False, "no workers needed"),
        ("hdr", "Lumen", "lumen"),
        ("row", "Lumen Tap", "2/2", "High", False, ""),
        ("row", "Lumen Pump", "3/3", "Normal", False, "x0.5 Dimming"),
        ("hdr", "Logistics", "logistics"),
        ("row", "Storehouse", "haulers 4/4", "Normal", False, ""),
        ("row", "Builder's Yard", "builders 4/4", "Normal", False, ""),
        ("hdr", "Resources", "resources"),
        ("row", "Woodcutter", "2/2", "Normal", False, ""),
        ("row", "Quarry", "0/2", "Low", True, "paused"),
        ("hdr", "Refining", "refining"),
    ]
    rh = 22
    ry = ch + 28
    bottom = py + 560 - 18
    for r in rows:
        if ry + rh > bottom:
            break
        if r[0] == "hdr":
            d.rectangle([px + 16, ry, px + 884, ry + rh - 2], fill=(40, 36, 30))
            txt(d, (px + 26, ry + rh // 2 - 1), r[1], 14, GOLD, "lm")
        else:
            _, name, wk, pri, paused, note = r
            txt(d, (cx["name"], ry + rh // 2 - 1), name, 15, FAINT if paused else TEXT, "lm")
            a, _, b = wk.split()[-1].partition("/")
            colr = DIM if paused else (RED if a != b else GREEN)
            txt(d, (cx["work"], ry + rh // 2 - 1), wk, 14, colr, "mm")
            for key, lab, wdt in (("low", "Low", 50), ("norm", "Normal", 66), ("high", "High", 50)):
                on = lab == pri
                x = cx[key]
                d.rounded_rectangle([x, ry + 1, x + wdt, ry + rh - 3], 4, fill=(84, 70, 44) if on else (44, 38, 34),
                                    outline=GOLD if on else (70, 62, 54))
                txt(d, (x + wdt // 2, ry + rh // 2 - 1), lab, 12, TEXT if on else DIM, "mm")
            x = cx["pause"]
            d.rounded_rectangle([x, ry + 1, x + 66, ry + rh - 3], 4, fill=(110, 60, 50) if paused else (44, 38, 34),
                                outline=(180, 100, 80) if paused else (70, 62, 54))
            txt(d, (x + 33, ry + rh // 2 - 1), "Resume" if paused else "Pause", 12, TEXT, "mm")
            if note:
                txt(d, (cx["note"], ry + rh // 2 - 1), note, 13, RED if "short" in note or "waiting" in note else
                    ((200, 160, 90) if "Dimming" in note else DIM), "lm")
        ry += rh
    # scrollbar + fade, the list goes on
    d.rounded_rectangle([px + 888, ch + 28, px + 894, bottom], 3, fill=(44, 38, 34))
    d.rounded_rectangle([px + 888, ch + 28, px + 894, ch + 28 + 230], 3, fill=(120, 106, 80))
    return img


# ---------------------------------------------------------------- 5. build menu
def lock(img, x, y, s=3):
    rows = ["..jjjj..", ".j....j.", ".j....j.", "bbbbbbbb", "bYYYYYYb", "bYYhhYYb", "bYYhhYYb", "bbbbbbbb"]
    key = {"j": (200, 200, 200, 255), "b": (40, 30, 20, 255), "Y": (200, 160, 60, 255), "h": (60, 40, 20, 255)}
    for j, row in enumerate(rows):
        for i, c in enumerate(row):
            if c != ".":
                ImageDraw.Draw(img).rectangle([x + i * s, y + j * s, x + (i + 1) * s - 1, y + (j + 1) * s - 1],
                                              fill=key[c])


def sprite(name, maxh, maxw, grey=False, scale=None):
    im = Image.open(ROOT / "assets" / "buildings" / f"{name}.png").convert("RGBA")
    im = im.crop(im.getbbox())
    if scale is None:
        scale = 2 if im.height * 2 <= maxh and im.width * 2 <= maxw else 1
    im = M.upscale(im, scale)
    if grey:
        a = im.getchannel("A")
        g = im.convert("L").convert("RGBA")
        g.putalpha(a.point(lambda v: v * 2 // 5))
        return g
    return im


CARDS = [  # id, name, cost (the real ones from data/buildings), state
    ("sawmill", "Sawmill", {"wood": 14, "stone": 21}, "ok"),
    ("mason", "Mason", {"wood": 18, "stone": 27, "planks": 10}, "ok"),
    ("kitchen", "Kitchen", {"wood": 12, "stone": 18, "planks": 10}, "ok"),
    ("refinery", "Refinery", {"wood": 24, "stone": 36, "gold": 20, "planks": 15}, "short"),
    ("toolsmith", "Toolsmith", {"cut_stone": 20, "gold": 30, "wood": 32, "stone": 48}, "locked"),
]


def cost_rows(img, d, x, y, cost, colw=70, per=2, size=14, grey=False):
    for i, (g, n) in enumerate(cost.items()):
        gx = x + (i % per) * colw
        gy = y + (i // per) * (30 if not grey else 22)
        short = STOCK.get("cells" if g == "lumen_cells" else g, 0) < n
        sc = 2 if not grey else 1
        put_icon(img, g, gx, gy, sc)
        c = FAINT if grey else ((255, 130, 114) if short else TEXT)
        txt(d, (gx + 14 * sc + 4, gy + 7 * sc), str(n), size, c, "lm")


def build_menu():
    img = backdrop(0.25)
    top_bar(img)
    build_bar(img, "Refining")
    d = ImageDraw.Draw(img, "RGBA")
    fx0, fy0, cw, chh, gap = 16, 364, 154, 246, 8
    fx1 = fx0 + 5 * cw + 4 * gap + 20
    panel(d, (fx0, fy0, fx1, 648), fill=(24, 20, 18, 240))
    txt(d, (fx0 + 14, fy0 + 10), "Refining", 18, GOLD)
    txt(d, (fx1 - 14, fy0 + 14), "Hover a card for details", 13, FAINT, "ra")
    for i, (bid, name, cost, state) in enumerate(CARDS):
        x = fx0 + 10 + i * (cw + gap)
        y = fy0 + 36
        hov = bid == "sawmill"
        locked, short = state == "locked", state == "short"
        d.rounded_rectangle([x, y, x + cw, y + chh - 10], 6, fill=(34, 30, 26) if not locked else (30, 28, 26),
                            outline=GOLD if hov else ((200, 80, 66) if short else (70, 62, 54)), width=3 if hov or short else 1)
        if short:
            d.rounded_rectangle([x + 3, y + 3, x + cw - 3, y + chh - 13], 4, fill=(120, 30, 24, 26))
        sp = sprite(bid, 132, cw - 10, grey=locked)
        img.alpha_composite(sp, (x + (cw - sp.width) // 2, y + 8 + (132 - sp.height)))
        if locked:
            lock(img, x + cw // 2 - 12, y + 62, 3)
        txt(d, (x + cw // 2, y + 148), name, 16, FAINT if locked else TEXT, "ma")
        if locked:
            txt(d, (x + cw // 2, y + 168), "Needs City era", 13, (200, 160, 90), "ma")
        cost_rows(img, d, x + 8, y + 190 if locked else y + 172, cost, colw=72, grey=locked)
    # hover detail panel (Sawmill)
    dx0, dy0, dx1, dy1 = fx1 + 16, 150, W - 16, 648
    panel(d, (dx0, dy0, dx1, dy1), fill=(24, 20, 18, 245), border=GOLD)
    sp = sprite("sawmill", 190, dx1 - dx0 - 40, scale=3)
    d.rounded_rectangle([dx0 + 14, dy0 + 14, dx1 - 14, dy0 + 214], 6, fill=(60, 84, 48))
    img.alpha_composite(sp, ((dx0 + dx1 - sp.width) // 2, dy0 + 214 - 10 - sp.height))
    y = dy0 + 228
    txt(d, (dx0 + 18, y), "Sawmill", 22, GOLD)
    txt(d, (dx1 - 18, y + 6), "Refining, Village era", 13, FAINT, "ra")
    txt(d, (dx0 + 18, y + 34), "Turns wood into planks for sturdier buildings.", 14, TEXT)
    d.line([(dx0 + 18, y + 62), (dx1 - 18, y + 62)], fill=BORDER)
    txt(d, (dx0 + 18, y + 82), "Cost", 14, FAINT, "lm")
    for i, (g, n) in enumerate({"wood": 14, "stone": 21}.items()):
        gx = dx0 + 90 + i * 150
        put_icon(img, g, gx, y + 68, 2)
        txt(d, (gx + 34, y + 82), f"{n}  (have {STOCK[g]})", 14, TEXT, "lm")
    rowsd = [("Workers", "2"), ("Size", "2 x 1 tiles")]
    for j, (k, v) in enumerate(rowsd):
        txt(d, (dx0 + 18, y + 106 + j * 22), k, 14, FAINT)
        txt(d, (dx0 + 90, y + 106 + j * 22), v, 14, TEXT)
    txt(d, (dx0 + 18, y + 166), "Per day", 14, FAINT, "lm")
    put_icon(img, "wood", dx0 + 90, y + 152, 2)
    txt(d, (dx0 + 124, y + 166), "6", 14, TEXT, "lm")
    txt(d, (dx0 + 148, y + 166), "->", 14, DIM, "lm")
    put_icon(img, "planks", dx0 + 176, y + 152, 2)
    txt(d, (dx0 + 210, y + 166), "3", 14, TEXT, "lm")
    txt(d, (dx0 + 18, y + 204), "Unlock", 14, FAINT)
    txt(d, (dx0 + 90, y + 204), "Village era (unlocked)", 14, GREEN)
    return img


# ---------------------------------------------------------------- main
def main():
    out = Path(sys.argv[1]) if len(sys.argv) > 1 else Path("mockups-116")
    out.mkdir(parents=True, exist_ok=True)
    for name, fn in (("icons_sheet", icons_sheet), ("clock_bar", clock_bar), ("resources_page", resources_page),
                     ("workforce_page", workforce_page), ("build_menu", build_menu)):
        im = fn()
        assert im.size == (W, H), (name, im.size)
        im.convert("RGB").save(out / f"{name}.png")
    print("wrote", *sorted(p.name for p in out.glob("*.png")))


if __name__ == "__main__":
    main()
