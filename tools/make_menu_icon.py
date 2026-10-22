#!/usr/bin/env python
"""Draw the 48x48 greyscale TGA icons the build menu wants for a mod's own
menu categories.

A category is a `.res.lua` resource (`type = "menu_category"`) whose `icon` is
`resolve("<name>.tga")`, and the file that has to be beside it is
`<name>@2x.tga`. Measured off the stock icons, which this matches exactly:

    48 x 48, 8 bits per pixel, TGA image type 3 (uncompressed greyscale),
    descriptor 0x00, so rows are stored bottom-up.

The glyph is bright on a black field - `building@2x.tga` is 1342 pixels of 0,
885 of 255 and a handful of intermediate values along its edges, so the byte is
read as coverage rather than as colour and the shapes below are drawn with 4x4
supersampling to get the same soft edge.

    python tools/make_menu_icon.py            # write both icons in place
    python tools/make_menu_icon.py --dump     # also print an ASCII preview

Shapes are axis-aligned rectangles in a top-left-origin 48 x 48 space, which is
all these glyphs need and keeps them legible at the size they are actually
drawn: an icon with a diagonal reads as mush in a 24 px menu strip.
"""
import os
import struct
import sys

SIZE = 48
SS = 4  # supersampling factor per axis

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(HERE, "multi-layer-stations", "mod",
                   "multi_layer_stations_1", "content")

# Two decks, one over the other, on piers: the station itself.
STATION = [
    (5.0, 9.0, 43.0, 15.0),    # upper deck
    (14.0, 15.0, 18.0, 25.0),  # pier, left
    (30.0, 15.0, 34.0, 25.0),  # pier, right
    (5.0, 25.0, 43.0, 31.0),   # lower deck
    (14.0, 31.0, 18.0, 39.0),  # pier, left
    (30.0, 31.0, 34.0, 39.0),  # pier, right
    (3.0, 39.0, 45.0, 42.0),   # ground
]

# One deck on piers with the span left open: the support and the concourse,
# which is what both of those modules are.
MODULES = [
    (5.0, 11.0, 43.0, 17.0),   # deck
    (10.0, 17.0, 17.0, 39.0),  # pier, left
    (31.0, 17.0, 38.0, 39.0),  # pier, right
    (3.0, 39.0, 45.0, 42.0),   # ground
]


def raster(rects):
    """Coverage per pixel, 0..255, from axis-aligned rectangles."""
    px = bytearray(SIZE * SIZE)
    step = 1.0 / SS
    for y in range(SIZE):
        for x in range(SIZE):
            hits = 0
            for sy in range(SS):
                py = y + (sy + 0.5) * step
                for sx in range(SS):
                    pxx = x + (sx + 0.5) * step
                    for x0, y0, x1, y1 in rects:
                        if x0 <= pxx < x1 and y0 <= py < y1:
                            hits += 1
                            break
            px[y * SIZE + x] = (hits * 255) // (SS * SS)
    return px


def write_tga(path, px):
    """8bpp uncompressed greyscale, bottom-up, exactly as the stock icons are."""
    header = struct.pack("<BBBHHBHHHHBB",
                         0,        # id length
                         0,        # no colour map
                         3,        # uncompressed greyscale
                         0, 0, 0,  # colour map spec
                         0, 0,     # origin
                         SIZE, SIZE, 8, 0x00)
    rows = [px[y * SIZE:(y + 1) * SIZE] for y in range(SIZE)]
    with open(path, "wb") as f:
        f.write(header)
        for row in reversed(rows):   # descriptor 0x00 means bottom row first
            f.write(bytes(row))


def dump(px):
    ramp = " .:-=+*#%@"
    for y in range(SIZE):
        print("".join(ramp[px[y * SIZE + x] * (len(ramp) - 1) // 255]
                      for x in range(SIZE)))


def main():
    for name, rects in (("category_ml_station", STATION),
                        ("category_ml_modules", MODULES)):
        px = raster(rects)
        path = os.path.join(OUT, name + "@2x.tga")
        write_tga(path, px)
        print("wrote %s (%d bytes)" % (path, os.path.getsize(path)))
        if "--dump" in sys.argv:
            dump(px)


if __name__ == "__main__":
    main()
