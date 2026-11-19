"""Ticket 110: signature props and door signs for the 23 generic buildings (D2).

Every prop and glyph is a small ASCII pixel map (legend below) stamped onto the finished gable house by
add_signature(), so the gable and the category tint stay and only the job-telling parts are new.
"""
from PIL import Image

import mockups as M

h = M.hexc
LEG = {
    "k": M.WOOD[0], "m": M.WOOD[1], "n": M.WOOD[2], "N": M.WOOD[3], "l": M.WOOD[4],
    "u": M.STONE[0], "s": M.STONE[1], "S": M.STONE[2], "t": M.STONE[3], "T": M.STONE[4],
    "D": M.LEAF["green"][1], "G": M.LEAF["green"][2], "H": M.LEAF["green"][3], "J": M.LEAF["green"][4],
    "o": M.THATCH[2], "y": M.THATCH[3], "Y": M.THATCH[4],
    "b": M.WATER[2], "B": M.WATER[3], "w": M.WATER[4], "W": M.WATER[5],
    "E": M.CRYSTAL[1], "c": M.CRYSTAL[2], "C": M.CRYSTAL[3], "e": M.CRYSTAL[4],
    "q": M.BRASS[1], "a": M.BRASS[2], "A": M.BRASS[3],
    "I": M.ROCK[1], "i": M.ROCK[2], "j": M.ROCK[3], "z": M.ROCK[4],
    "p": M.PLASTER[3], "P": M.PLASTER[2],
    "r": h("a83a3a"), "R": h("d8584a"), "O": h("e8902a"), "f": h("f0a030"), "F": h("f8d860"),
    "x": M.DIRT[1], "X": M.DIRT[2], "g": h("d8d8c8"), "V": h("f0d060"), "U": h("c8e0f0"),
}


def img(rows):
    wd = max(len(r) for r in rows)
    im = Image.new("RGBA", (wd, len(rows)))
    px = im.load()
    for y, r in enumerate(rows):
        for x, c in enumerate(r):
            if c != ".":
                px[x, y] = LEG[c]
    return im


def stamps(*parts):
    """parts: (rows, x, y) pieces on one canvas."""
    ims = [(img(r), x, y) for r, x, y in parts]
    cw = max(i.width + x for i, x, y in ims)
    ch = max(i.height + y for i, x, y in ims)
    out = Image.new("RGBA", (cw, ch))
    for i, x, y in ims:
        out.alpha_composite(i, (x, y))
    return out


CRATE = ["mmmmmm", "mNNNNm", "mNnnNm", "mNNNNm", "mmmmmm"]
CRATE_S = ["mmmmm", "mNNNm", "mNnNm", "mmmmm"]
BARREL = [".mm.", "nNNn", "iiii", "nNln", "iiii", ".mm."]
BLOCK = ["TTTTT", "tSSSs", "SSSss", "sssss"]
LOG = [".nn.", "nlYn", "nYln", ".nn."]
SPROUT = [".J.", "GJG", ".G.", ".n."]
TREE = ["..HHHH...", ".HJJHHG..", "HJJHHGGG.", "HHHJHHGG.", ".GHHHGG..", "..GGGG...", "...nn....", "...nn....",
        "...nn...."]
WHEEL = [".mmm.", "mlnlm", "mnanm", "mlnlm", ".mmm."]
CRYSTAL_T = ["..e..", ".eCc.", ".eCc.", "eCCCc", "eCCCc", "eCCcc", "ECCcc", "ECccc", "EEccc"]
CELL = [".aa.", "cCCc", "cCCc", "cEEc", "cCCc"]
DISC = ["..aaa..", ".aGGVa.", "aGGGVVa", "aaaaaaa", "aOOOUUa", ".aOOUa.", "..aaa.."]
BUSH = [".G.", "GHG"]

PROPS = {
    "crates": stamps((CRATE, 0, 6), (CRATE_S, 1, 2), (BARREL, 7, 5)),
    "barrels": stamps((BARREL, 0, 4), (BARREL, 5, 4), (BARREL, 2, 0)),
    "basket": img(["..rRr.rR..", ".rRrrRrrR.", ".nlnlnlnl.", ".nNnNnNnN.", "..nlnlnl..", "..mmmmmm.."]),
    "mushrooms": stamps((["..rRr.", ".rpRrr", "..pp.."], 0, 0), ([".rr.", "rpr.", ".p.."], 4, 2)),
    "rack": img(["nnnnnnnnnn", "n..j..j..n", "n.jWj.jWj.n"[:10], "n.jjj.jjj.n"[:10], "n..j..j..n", "n........n",
                 "n........n", "n........n"]),
    "boat": img(["n.......n", "nnnnnnnnn", ".nlllllln", "..nnnnnn."]),
    "blocks": stamps((BLOCK, 0, 4), (BLOCK, 5, 4), (BLOCK, 2, 0)),
    "pick": img([".iziizi", "i..n..i", "...n...", "...n...", "...n...", "...n...", "...n...", "...n..."]),
    "logs": stamps((LOG, 0, 4), (LOG, 4, 4), (LOG, 8, 4), (LOG, 2, 0), (LOG, 6, 0)),
    "blade": stamps((["..j.j.j..", ".jjjzjjj.", "jjzzazzjj", "jzzaaazzj", "jjzzazzjj", ".jjjzjjj.", "..j.j.j.."], 0, 0),
                    (["n.......n", "n.......n"], 0, 7)),
    "sprouts": stamps((SPROUT, 0, 0), (SPROUT, 4, 0), (SPROUT, 8, 0), (["xXxXxXxXxXx", "mxXxXxXxXxm"], 0, 4)),
    "shovel": img([".nnn", "..n.", "..n.", "..n.", ".iii", ".iii", "..i."]),
    "planks": stamps((["llllllllll", "nnnnnnnnnn", "NNNNNNNNNN", "nnnnnnnnnn", "llllllllll", "nnnnnnnnnn"], 0, 0),
                     (["m......m", "m......m"], 1, 6)),
    "ladder": img(["n....n", "nnnnnn", "n....n", "nnnnnn", "n....n", "nnnnnn", "n....n", "nnnnnn", "n....n"]),
    "bench": stamps((["mmmmmmmmmmm", "mNNNNNNNNNm", "m.........m", "m.........m"], 0, 4),
                    ([".a.a.", "aaaaa", ".a.a."], 3, 1), ([".aaa.", "aa.aa", ".aaa."], 2, 0)),
    "anvil": img(["iiiiiii.", ".iIIIii.", "..iii...", "..iii...", ".iiiii.."]),
    "chest": stamps((["..aA..aA.", ".aAAaaAAa"], 0, 0),
                    (["mmmmmmmmm", "mNNNNNNNm", "mNNNaNNNm", "mnnnnnnnm"], 0, 2)),
    "coins": img([".AAA.", ".aaa.", ".AAA.", ".aaa.", ".AAA.", ".aaa."]),
    "well": img([".mmmmmmmm.", ".mNNNNNNm.", "..n.mm.n..", "..n.nn.n..", "..n.nn.n..", ".tTTTTTTt.",
                 "tTbBbBbBTt", "tSTTTTTTSs", "sSsSsSsSss", "sssssssSss"]),
    "column": img(["TTTTT", "sSSSs", ".SSs.", ".SSs.", ".STs.", ".SSs.", ".SSs.", "sSSSs", "TTTTT"]),
    "dressed": stamps((["TTTTTT", "tTTTTs", "tTTTTs", "ssssss"], 0, 5), (["..iI.", "..i.."], 4, 0)),
    "mallet": img(["nnnn.", "nnnn.", ".n...", ".n...", ".n...", ".n..."]),
    "tank": img(["..iIIi..", ".iIjjIi.", ".iIjjIi.", ".iCCCCi.", ".iCeeCi.", ".iCCCCi.", ".iIjjIi.", ".iIjjIi.",
                 ".iiiiii."]),
    "cells": stamps((CELL, 0, 0), (CELL, 5, 0), (CELL, 10, 0)),
    "pot": img(["..g..g...", ".g..g..g.", "..g..g...", ".iiiiiii.", "iIjIjIjIi", "iIIIIIIIi", ".iIIIIIi.", "..ff.ff..",
                ".fFfFfFf.", ".nnnnnnn."]),
    "cart": stamps((["mmmmmmmm", "mNNNNNNm", "mNpNpNNm", "mnnnnnnm"], 0, 0), (WHEEL, 2, 3),
                   (["nn..", ".nn.", "..nn", "...n"], 8, 2)),
    "sacks": stamps((["..pP", ".pPPp"[:4], "pPPp", ".pp."], 0, 0), ([".pP.", "pPPp", ".pp."], 4, 1)),
    "anchor": img(["...ii...", "..i..i..", "..iiii..", "...ii...", ".iiiiii.", "...ii...", "...ii...", "...ii...",
                   "i..ii..i", "ii.ii.ii", ".iiiiii.", "..iiii.."]),
    "rope": img([".yyyyyy.", "yoYYYYoy", "yoyyyyoy", ".oooooo."]),
    "crystals": stamps((CRYSTAL_T, 0, 0), ([".eCc.", "eCCCc", "ECCcc", "EECcc", "EEccc"], 5, 4)),
    "planter": stamps((["mmmmmmmm", "mxxxxxxm", "mmmmmmmm"], 0, 3), (BUSH, 0, 1), (BUSH, 3, 0), (BUSH, 5, 1)),
    "rootstump": img(["..nnnnnn..", ".nNNNNNNn.", "nNlYCYlNNn", "nnNNNNNNnn", ".nnnnnnnn.", "n.nn..nn.n"]),
    "tapbarrel": stamps((BARREL, 0, 4), (["iiii", "...i", "...i"], 0, 1), (["c", "C"], 3, 3)),
    "pool": img(["..tttttt..", ".tbBwBbbt.", "tbBbbBwbbt", ".tbbbbbbt.", "..tttttt.."]),
    "sprig": img([".J.J.", "GJGJG", ".G.G.", "..n.."]),
    "mender": img(["...C...", "..eCc..", ".eCCCc.", ".cCJCc.", ".cJJJc.", ".cCJCc.", ".cCCCc.", "eEEEEEc"]),
    "bigtree": img(["..HHHH...", ".HJJHHG..", "HJJHHGGG.", "HHHJHHGG.", ".GHHHGG..", "..GGGG...", "...nn....", "...nn....",
                    "...nn...."]),
    "flowerbush": img([".GHG.", "GHrHG", "GOGpG"]),
    "filter": img(["..jjjjjj..", ".jBBBBBBj.", "jBwwBBwwBj", "jbbbbbbbbj", "jbBbbbBbbj", "jbbbbbbbbj", ".jjjjjjjj."]),
    "spout": img(["iiiii.", "....i.", "....i.", "...ibi", "....b.", "....B.", "bbbbbbb"]),
    "fruittree": img(["..HHHH...", ".HOHHRG..", "HJJHHGOG.", "HRHJHHGG.", ".GHOHRG..", "..GGGG...", "...nn....", "...nn....",
                      "...nn...."]),
    "fruitbasket": img(["..OrO.", ".OrOrO", ".nlnln", ".nNnNn", "..mmmm"]),
    "emblem": stamps((DISC, 0, 0), (["n", "n", "n", "n"], 3, 7)),
    "seasonbushes": stamps((BUSH, 0, 0), ([".V.", "VYV"], 4, 0), ([".O.", "OfO"], 8, 0), ([".U.", "UgU"], 12, 0)),
}

# id -> (category glyph, [(prop, slot)]); slots: L/R beside the door, L2/R2 at the outer corners.
GLYPHS = {
    "forager": [".GG....".replace("G", "G"), "..GG...", ".rr.rr.", "rRrrRrr", ".rr.rr.", "..r.r..", "......."],
    "storehouse": ["mmmmmmm", "mNNmNNm", "mNNmNNm", "mmmmmmm", "mNNmNNm", "mNNmNNm", "mmmmmmm"],
    "fishing_dock": [".......", "..bbb.b", ".bbbbbb", "bkbbbb.", ".bbbbbb", "..bbb.b", "......."],
    "quarry": [".iziizi", "i...i.i", "....n.i", "...n...", "..n....", ".n.....", "n......"],
    "sawmill": ["..i.i..", ".iiiii.", "iiipiii", ".ipppi.", "iiipiii", ".iiiii.", "..i.i.."],
    "forester": ["..GGG..", ".GJJJG.", ".GJJJG.", "..GGG..", "...n...", "...n...", "..nnn.."],
    "builders_yard": [".iiiii.", ".iiiii.", "...n...", "...n...", "...n...", "...n...", "...n..."],
    "workshop": ["...a...", ".a.a.a.", "..aaa..", "aaa.aaa", "..aaa..", ".a.a.a.", "...a..."],
    "tax_office": ["..aaa..", ".aAAAa.", "aAAaAAa", "aAAaAAa", "aAAaAAa", ".aAAAa.", "..aaa.."],
    "well": ["..mmm..", ".m...m.", "iiiiiii", "iIIIIIi", "iIbbbIi", ".iIIIi.", "..iii.."],
    "mason": [".ttttt.", "tSSSSSs", "tSSTSSs", "tSTTTSs", "tSSTSSs", "ssssssS", "......."],
    "refinery": ["..aaa..", ".cCCCc.", ".cCeCc.", ".cCeCc.", ".cCCCc.", ".cEEEc.", ".ccccc."],
    "kitchen": [".i.i.i.", ".i.i.i.", ".......", "iiiiiii", "iIIIIIi", "iIIIIIi", ".iiiii."],
    "handcart_shed": ["..mmm..", ".mnlnm.", "mnnlnnm", "mllallm", "mnnlnnm", ".mnlnm.", "..mmm.."],
    "lift_anchor": ["...i...", "..iii..", "...i...", ".iiiii.", "...i...", "i..i..i", ".iiiii."],
    "lumen_arcology": ["...c...", "..cCc..", "..cCc..", ".cCeCc.", ".cCeCc.", ".cCCCc.", ".ccccc."],
    "heartroot_tap": ["...c...", "..cCc..", ".cCeCc.", ".cCCCc.", "..ccc..", "n.n.n.n", ".nnnnn."],
    "verdant_spring": [".J...J.", "JJJ.JJJ", ".JJGJJ.", "..JGJ..", "...G...", "bbbbbbb", ".bbbbb."],
    "vein_mender": ["..JJJ..", "..JJJ..", "JJJJJJJ", "JJJJJJJ", "JJJJJJJ", "..JJJ..", "..JJJ.."],
    "rewilding_grove": ["..HHH..", ".HJJJH.", "HJJJHGG", "HHJHHGG", ".GHHGG.", "...n...", "..nnn.."],
    "clearwater_works": ["...b...", "..bbb..", ".bbBbb.", ".bBbbb.", "bbbbbbb", ".bbbbb.", "..bbb.."],
    "bloom_orchard": ["...G...", "..nG...", ".rrrrr.", "rRrrrrr", "rrrrrrr", ".rrrrr.", "..r.r.."],
    "hall_of_seasons": ["..aaa..", ".aGGVa.", "aGGGVVa", "aaaaaaa", "aOOOUUa", ".aOOUa.", "..aaa.."],
}
SLOTS = {
    "forager": [("basket", "L"), ("mushrooms", "R")], "storehouse": [("crates", "L"), ("barrels", "R")],
    "fishing_dock": [("rack", "L"), ("boat", "R")], "quarry": [("blocks", "L"), ("pick", "R")],
    "sawmill": [("logs", "L"), ("blade", "R"), ("logs", "R2")],
    "forester": [("sprouts", "L"), ("shovel", "R")],
    "builders_yard": [("planks", "L"), ("ladder", "R"), ("planks", "R2")],
    "workshop": [("bench", "L"), ("anvil", "R")], "tax_office": [("chest", "L"), ("coins", "R")],
    "well": [("well", "L")],
    "mason": [("column", "L"), ("dressed", "R"), ("mallet", "R2")],
    "refinery": [("tank", "L"), ("cells", "R"), ("tank", "R2")],
    "kitchen": [("pot", "L")], "handcart_shed": [("cart", "L"), ("sacks", "R")],
    "lift_anchor": [("anchor", "L"), ("rope", "R"), ("anchor", "R2"), ("rope", "L2")],
    "lumen_arcology": [("crystals", "L"), ("planter", "R"), ("crystals", "R2")],
    "heartroot_tap": [("rootstump", "L"), ("tapbarrel", "R")],
    "verdant_spring": [("pool", "L"), ("sprig", "R")],
    "vein_mender": [("mender", "L"), ("sprig", "R")],
    "rewilding_grove": [("bigtree", "L"), ("flowerbush", "R"), ("bigtree", "R2")],
    "clearwater_works": [("filter", "L"), ("spout", "R")],
    "bloom_orchard": [("fruittree", "L"), ("fruitbasket", "R"), ("fruittree", "L2"), ("fruittree", "R2")],
    "hall_of_seasons": [("emblem", "L"), ("seasonbushes", "R"), ("emblem", "R2")],
}


def sign(rows):
    """9x9 board: wood frame, plaster face, 7x7 glyph."""
    im = Image.new("RGBA", (9, 9), M.WOOD[1])
    im.paste(Image.new("RGBA", (7, 7), M.PLASTER[3]), (1, 1))
    im.alpha_composite(img(rows), (1, 1))
    return im


def put(im, piece, x, bottom):
    o = M.sel_outline(piece)
    im.paste(o, (x - 1, bottom - o.height + 1), o)


def add_signature(im, bid, fw, w, door):
    """Draw the door sign and the signature props on the gable-house image (in place)."""
    W, H = im.size
    x0 = 4
    x1 = x0 + w - 1
    cx = (x0 + x1) // 2
    dw, dh = door
    bot = H - 1 - dh - 2
    put(im, sign(GLYPHS[bid]), cx - 4, bot)
    for name, slot in SLOTS[bid]:
        p = PROPS[name]
        if fw >= 3:  # big buildings: props at double size so they still read next to the long frontage
            p = p.resize((p.width * 2, p.height * 2), Image.NEAREST)
        pw = p.width
        if slot == "L":
            x = cx - dw // 2 - 2 - pw
        elif slot == "R":
            x = cx + dw // 2 + 7
        elif slot == "L2":
            x = x0 - 1
        else:
            x = x1 - pw + 3
        x = max(1, min(W - pw - 1, x))
        put(im, p, x, H - 2)
