#!/usr/bin/env python
"""Draw placeholder build-menu art for this mod's constructions, and say on the
art itself what would replace it.

Two images per constructable, both measured off the stock files they used to
borrow (`stations/rail/modular_station/station_era_c@2x.tga` and friends):

    icon      240 x 150, 32bpp BGRA, TGA type 2, descriptor 0x08, bottom-up,
              mostly transparent - this is the tile in the build menu;
    preview   720 x 405, 24bpp BGR, TGA type 2, descriptor 0x00, bottom-up,
              fully opaque - the large image in the side panel.

Both carry the 26-byte TGA v2 footer (`TRUEVISION-XFILE.`), which every stock
file has, and both are written as `<name>@2x.tga`: the `@2x` is the engine's
suffix and is not part of the name a `.con` or `.module` asks for. The 8bpp
greyscale masks the *menu categories* use are a different format again - those
live in `tools/make_menu_icon.py`.

    python tools/make_menu_art.py           # write all six files in place
    python tools/make_menu_art.py --dump    # ASCII-preview each one first

The point of generating rather than drawing: placeholder art should be
obviously placeholder, identical in treatment across the set, and cheap to
regenerate when a name changes. The text on each preview names the file to
replace and the format to replace it with, so a contributor needs nothing but
the picture in front of them.
"""
import os
import struct
import sys

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(HERE, "multi-layer-stations", "mod",
                   "multi_layer_stations_1", "content")

ICON_W, ICON_H = 240, 150
PREV_W, PREV_H = 720, 405

# 5 x 7 bitmap font, one line per glyph: the character, then its seven rows.
FONT_SRC = """
A 01110 10001 10001 11111 10001 10001 10001
B 11110 10001 10001 11110 10001 10001 11110
C 01110 10001 10000 10000 10000 10001 01110
D 11110 10001 10001 10001 10001 10001 11110
E 11111 10000 10000 11110 10000 10000 11111
F 11111 10000 10000 11110 10000 10000 10000
G 01110 10001 10000 10111 10001 10001 01111
H 10001 10001 10001 11111 10001 10001 10001
I 11111 00100 00100 00100 00100 00100 11111
J 00111 00010 00010 00010 00010 10010 01100
K 10001 10010 10100 11000 10100 10010 10001
L 10000 10000 10000 10000 10000 10000 11111
M 10001 11011 10101 10101 10001 10001 10001
N 10001 11001 10101 10011 10001 10001 10001
O 01110 10001 10001 10001 10001 10001 01110
P 11110 10001 10001 11110 10000 10000 10000
Q 01110 10001 10001 10001 10101 10011 01111
R 11110 10001 10001 11110 10100 10010 10001
S 01111 10000 10000 01110 00001 00001 11110
T 11111 00100 00100 00100 00100 00100 00100
U 10001 10001 10001 10001 10001 10001 01110
V 10001 10001 10001 10001 10001 01010 00100
W 10001 10001 10001 10101 10101 11011 10001
X 10001 10001 01010 00100 01010 10001 10001
Y 10001 10001 01010 00100 00100 00100 00100
Z 11111 00001 00010 00100 01000 10000 11111
0 01110 10001 10011 10101 11001 10001 01110
1 00100 01100 00100 00100 00100 00100 01110
2 01110 10001 00001 00010 00100 01000 11111
3 11110 00001 00001 01110 00001 00001 11110
4 00010 00110 01010 10010 11111 00010 00010
5 11111 10000 11110 00001 00001 10001 01110
6 00110 01000 10000 11110 10001 10001 01110
7 11111 00001 00010 00100 01000 01000 01000
8 01110 10001 10001 01110 10001 10001 01110
9 01110 10001 10001 01111 00001 00010 01100
. 00000 00000 00000 00000 00000 01100 01100
, 00000 00000 00000 00000 01100 00100 01000
- 00000 00000 00000 11111 00000 00000 00000
: 00000 01100 01100 00000 01100 01100 00000
/ 00001 00010 00010 00100 01000 01000 10000
+ 00000 00100 00100 11111 00100 00100 00000
( 00010 00100 01000 01000 01000 00100 00010
) 01000 00100 00010 00010 00010 00100 01000
_ 00000 00000 00000 00000 00000 00000 11111
"""


def build_font():
    font = {" ": ["00000"] * 7}
    for line in FONT_SRC.strip().splitlines():
        parts = line.split()
        font[parts[0]] = parts[1:]
    return font


FONT = build_font()
GLYPH_W, GLYPH_H = 5, 7


def text_width(s, scale, tracking=1):
    return len(s) * (GLYPH_W + tracking) * scale - tracking * scale


class Canvas:
    """An 8-bit coverage field. Colour is applied when the file is written, so
    the same drawing code serves the transparent icon and the opaque preview."""

    def __init__(self, w, h):
        self.w, self.h = w, h
        self.px = bytearray(w * h)

    def rect(self, x0, y0, x1, y1, v=255):
        for y in range(max(0, int(y0)), min(self.h, int(y1))):
            row = y * self.w
            for x in range(max(0, int(x0)), min(self.w, int(x1))):
                self.px[row + x] = v

    def frame(self, x0, y0, x1, y1, t, v=255):
        self.rect(x0, y0, x1, y0 + t, v)
        self.rect(x0, y1 - t, x1, y1, v)
        self.rect(x0, y0, x0 + t, y1, v)
        self.rect(x1 - t, y0, x1, y1, v)

    def dashes(self, x0, y0, x1, y1, t, dash, v=255):
        for x in range(int(x0), int(x1), dash * 2):
            self.rect(x, y0, min(x + dash, x1), y0 + t, v)
            self.rect(x, y1 - t, min(x + dash, x1), y1, v)
        for y in range(int(y0), int(y1), dash * 2):
            self.rect(x0, y, x0 + t, min(y + dash, y1), v)
            self.rect(x1 - t, y, x1, min(y + dash, y1), v)

    def text(self, s, x, y, scale, v=255, tracking=1):
        # Overflow is the one mistake this file can make that still produces a
        # plausible image, so it is an error rather than a clipped line.
        end = x + text_width(s, scale, tracking)
        if end > self.w or y + GLYPH_H * scale > self.h:
            raise ValueError("%r at x=%d scale=%d runs to %d, past %d"
                             % (s, x, scale, end, self.w))
        for ch in s.upper():
            rows = FONT.get(ch, FONT[" "])
            for ry, row in enumerate(rows):
                for rx, bit in enumerate(row):
                    if bit == "1":
                        self.rect(x + rx * scale, y + ry * scale,
                                  x + (rx + 1) * scale, y + (ry + 1) * scale, v)
            x += (GLYPH_W + tracking) * scale
        return x

    def text_centred(self, s, y, scale, v=255):
        self.text(s, (self.w - text_width(s, scale)) // 2, y, scale, v)

    def dump(self, step=3):
        ramp = " .:-=+*#%@"
        for y in range(0, self.h, step * 2):
            print("".join(ramp[self.px[y * self.w + x] * (len(ramp) - 1) // 255]
                          for x in range(0, self.w, step)))


def footer():
    return b"\x00" * 8 + b"TRUEVISION-XFILE." + b"\x00"


def write_bgra(path, c, rgb=(236, 236, 230)):
    """32bpp BGRA, descriptor 0x08: coverage becomes alpha, so the glyph sits on
    transparency the way every stock menu icon does."""
    head = struct.pack("<BBBHHBHHHHBB", 0, 0, 2, 0, 0, 0, 0, 0,
                       c.w, c.h, 32, 0x08)
    r, g, b = rgb
    body = bytearray()
    for y in reversed(range(c.h)):
        row = y * c.w
        for x in range(c.w):
            a = c.px[row + x]
            body += bytes((b, g, r, a))
    open(path, "wb").write(head + bytes(body) + footer())


def write_bgr(path, c, ink=(238, 238, 232), paper=(34, 36, 38)):
    """24bpp BGR, descriptor 0x00: coverage interpolates paper to ink, because a
    preview has no alpha and a transparent one shows as black."""
    head = struct.pack("<BBBHHBHHHHBB", 0, 0, 2, 0, 0, 0, 0, 0,
                       c.w, c.h, 24, 0x00)
    body = bytearray()
    for y in reversed(range(c.h)):
        row = y * c.w
        for x in range(c.w):
            v = c.px[row + x]
            body += bytes(tuple(
                (paper[i] * (255 - v) + ink[i] * v) // 255 for i in (2, 1, 0)))
    open(path, "wb").write(head + bytes(body) + footer())


def glyph_station(c, x, y, s):
    """Two decks on piers: the station."""
    c.rect(x, y, x + 44 * s, y + 5 * s)
    c.rect(x + 9 * s, y + 5 * s, x + 13 * s, y + 17 * s)
    c.rect(x + 31 * s, y + 5 * s, x + 35 * s, y + 17 * s)
    c.rect(x, y + 17 * s, x + 44 * s, y + 22 * s)
    c.rect(x + 9 * s, y + 22 * s, x + 13 * s, y + 32 * s)
    c.rect(x + 31 * s, y + 22 * s, x + 35 * s, y + 32 * s)
    c.rect(x - 2 * s, y + 32 * s, x + 46 * s, y + 35 * s)


def glyph_support(c, x, y, s):
    """One filled pier under a deck: the support."""
    c.rect(x, y, x + 44 * s, y + 5 * s)
    c.rect(x + 12 * s, y + 5 * s, x + 32 * s, y + 32 * s)
    c.rect(x - 2 * s, y + 32 * s, x + 46 * s, y + 35 * s)


def glyph_concourse(c, x, y, s):
    """A deck on two piers with the span open: the concourse over its road."""
    c.rect(x, y, x + 44 * s, y + 8 * s)
    c.rect(x + 2 * s, y + 8 * s, x + 12 * s, y + 32 * s)
    c.rect(x + 32 * s, y + 8 * s, x + 42 * s, y + 32 * s)
    c.rect(x - 2 * s, y + 32 * s, x + 46 * s, y + 35 * s)


# name, glyph, preview title, kind, and the caption the *icon* carries.
#
# The caption names the thing, not its state. It said "PLACEHOLDER" until
# 2026-10-22 and that was the wrong word in the wrong place: the menu tile is
# where a player looks to find a building, so it has to answer "what is this",
# while "this art is unfinished" is the preview's job and the dashed frame's.
# At scale 2 a line of n characters is 12n - 2 px wide, so two short lines beat
# one long one inside 240.
PIECES = [
    ("ml_station", glyph_station, "MULTI-LAYER STATION", "CONSTRUCTION",
     ("MULTI-LAYER", "STATION")),
    ("ml_support", glyph_support, "ELEVATED SUPPORT", "MODULE",
     ("ELEVATED", "SUPPORT")),
    ("ml_concourse", glyph_concourse, "CONCOURSE", "MODULE",
     ("CONCOURSE",)),
]


def make_icon(glyph, caption):
    c = Canvas(ICON_W, ICON_H)
    c.dashes(4, 4, ICON_W - 4, ICON_H - 4, 2, 8, 90)
    glyph(c, 72, 16, 2)
    y = 96 if len(caption) > 1 else 104
    for line in caption:
        c.text_centred(line, y, 2, 210)
        y += 20
    return c


def make_preview(name, glyph, title, kind):
    """Glyph top left, name beside it, and what to replace it with across the
    bottom - where there is room for a filename and its format on one line."""
    c = Canvas(PREV_W, PREV_H)
    c.dashes(10, 10, PREV_W - 10, PREV_H - 10, 3, 14, 70)
    glyph(c, 50, 80, 4)
    c.text(title, 270, 92, 3)
    c.text(kind + " - PLACEHOLDER ART", 270, 140, 2, 170)
    c.text("ART WANTED: REPLACE " + name + "@2X.TGA (240X150 BGRA)",
           46, 268, 2, 210)
    c.text("AND " + name + "_PREVIEW@2X.TGA (720X405 BGR)", 46, 296, 2, 210)
    c.text("SEE README, CONTRIBUTING ART", 46, 330, 2, 160)
    return c


def main():
    for name, glyph, title, kind, caption in PIECES:
        icon = make_icon(glyph, caption)
        prev = make_preview(name, glyph, title, kind)
        if "--dump" in sys.argv:
            print("==", name, "icon"); icon.dump(2)
            print("==", name, "preview"); prev.dump(4)
        for suffix, canvas, writer in (("@2x.tga", icon, write_bgra),
                                       ("_preview@2x.tga", prev, write_bgr)):
            path = os.path.join(OUT, name + suffix)
            writer(path, canvas)
            print("wrote %-44s %7d bytes" % (os.path.basename(path),
                                             os.path.getsize(path)))


if __name__ == "__main__":
    main()
