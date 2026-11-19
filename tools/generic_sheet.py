"""Ticket 110 contact sheet: old vs new sprite of the 23 generic buildings.
python3 tools/generic_sheet.py <old_dir> <out.png> [scale] [cols]   (old_dir = copy of assets/buildings before the change)"""
import sys
from pathlib import Path

from PIL import Image, ImageDraw

import generic_props as GP

old_dir, out = Path(sys.argv[1]), Path(sys.argv[2])
sc = int(sys.argv[3]) if len(sys.argv) > 3 else 4
cols = int(sys.argv[4]) if len(sys.argv) > 4 else 3
new_dir = Path(__file__).resolve().parent.parent / "assets" / "buildings"
ids = list(GP.GLYPHS)
cw, ch = 2 * 96 * sc + 12, 78 * sc + 14
rows = (len(ids) + cols - 1) // cols
sheet = Image.new("RGBA", (cols * cw, rows * ch), (74, 120, 62, 255))
d = ImageDraw.Draw(sheet)
for i, bid in enumerate(ids):
    ox, oy = (i % cols) * cw, (i // cols) * ch
    d.text((ox + 4, oy + 2), bid, fill=(255, 255, 255, 255))
    for k, p in enumerate((old_dir / f"{bid}.png", new_dir / f"{bid}.png")):
        im = Image.open(p).convert("RGBA")
        im = im.resize((im.width * sc, im.height * sc), Image.NEAREST)
        sheet.alpha_composite(im, (ox + k * 96 * sc + 4 + (96 * sc - im.width) // 2, oy + 14 + (78 * sc - im.height)))
sheet.save(out)
