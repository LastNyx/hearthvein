#!/usr/bin/env python3
"""One-off (ticket 99): split every "materials" cost in data/buildings/*.tres into wood and stone.

Rule (patch-115 spec): Camp era and the raw-good producers (category "materials", Workshop) cost wood only, because
no stone source exists yet. Housing, food, logistics: 70% wood / 30% stone. Everything else (civic, landmark, lumen,
refining, water, gold, sky): 40% wood / 60% stone. Whole units, the total is kept, wood takes the odd unit.
Only `cost = ...` and `stages = ...` lines are touched. Re-running is harmless: nothing is left to convert.

    python3 tools/convert_materials_cost.py [--dry]
"""
import glob
import re
import sys

WOOD_ONLY_IDS = {"workshop"}  # the Workshop is the stone fallback: it must be buildable before any stone exists
WOOD_ONLY_CATEGORIES = {"materials"}
SHARE_STONE = {"housing": 0.3, "food": 0.3, "logistics": 0.3}
DEFAULT_STONE = 0.6


def split(total, stone_share):
    stone = int(stone_share * total + 0.5)
    return total - stone, stone


def convert_line(line, stone_share):
    def repl(m):
        wood, stone = split(int(m.group(1)), stone_share)
        parts = []
        if wood:
            parts.append('"wood": %d' % wood)
        if stone:
            parts.append('"stone": %d' % stone)
        return ", ".join(parts)
    return re.sub(r'"materials": (\d+)', repl, line)


def main():
    dry = "--dry" in sys.argv
    for path in sorted(glob.glob("data/buildings/*.tres")):
        text = open(path).read()
        if '"materials": ' not in text:
            continue
        def field(name):
            m = re.search(r'^%s = "([^"]*)"' % name, text, re.M)
            return m.group(1) if m else ""
        bid, era, cat = field("id"), field("era"), field("category")
        if era == "camp" or cat in WOOD_ONLY_CATEGORIES or bid in WOOD_ONLY_IDS:
            share = 0.0
        else:
            share = SHARE_STONE.get(cat, DEFAULT_STONE)
        out = []
        for line in text.split("\n"):
            if line.startswith("cost = ") or line.startswith("stages = "):
                line = convert_line(line, share)
            out.append(line)
        new = "\n".join(out)
        print("%-18s %-9s %-10s %s" % (bid, era, cat, [l for l in out if l.startswith("cost = ")][:1]))
        if not dry:
            open(path, "w").write(new)


main()
