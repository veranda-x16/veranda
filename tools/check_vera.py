#!/usr/bin/env python3
"""Check VERA's display registers in an x16emu dump (-dump V, or with V).

    check_vera.py <dump.bin> [640x480|640x240|320x240]

The gates compare the bitmap in VRAM; this checks that the display shows
it: a 1 bpp bitmap at VRAM_FG ($00000) with the mode's tile width, and
the mode's scale; either layer 0 the bitmap, layer 1 off (the plain
display), or, with the colour map on (docs/DECISIONS.md V30), layer 1 the
bitmap over layer 0, a 1 bpp tile map at $1AC00 (128 x 64, tile 0 at
$1E800); sprites on. (A video mode set with the wrong registers left VRAM
right and the screen noise: found on a real X16.)

The dump ends with video_save(): VRAM (128 KB), the composer (256), the
palette (512), the layers (2 x 7), the sprites (128 x 8).
"""
import sys

VRAM, COMPOSER, PALETTE, LAYERS, SPRITES = 131072, 256, 512, 14, 1024
TAIL = VRAM + COMPOSER + PALETTE + LAYERS + SPRITES
MODES = {  # hscale, vscale, tile width bit
    "640x480": (128, 128, 1),
    "640x240": (128, 64, 1),
    "320x240": (64, 64, 0),
}


def main():
    if len(sys.argv) not in (2, 3):
        sys.exit(__doc__)
    mode = sys.argv[2] if len(sys.argv) == 3 else "640x480"
    hs, vs, tw = MODES[mode]
    d = open(sys.argv[1], "rb").read()
    if len(d) < TAIL:
        sys.exit("check_vera: no VRAM section in the dump")
    t = d[-TAIL:]
    c = t[VRAM:VRAM + COMPOSER]
    l0 = t[VRAM + COMPOSER + PALETTE:][:7]
    l1 = t[VRAM + COMPOSER + PALETTE + 7:][:7]
    bad = []
    cmap = c[0] & 0x70 == 0x70
    if cmap:
        bm = l1
        if l0[:3] != bytes([0x60, 0xD6, 0xF4]) and l0[:3] != bytes([0x62, 0xD6, 0x98]):    # (or tile mode: V101, V133)
            bad.append("layer 0 $%02X $%02X $%02X: want the colour map (1 bpp tiles, 128 x 64, $1AC00, tile 0 "
                       "$1E800; or tile mode's 4 bpp tiles at $13000)" % tuple(l0[:3]))
    else:
        bm = l0
        if c[0] & 0x70 != 0x50:
            bad.append(f"DC_VIDEO ${c[0]:02X}: want layer 0 and sprites on, layer 1 off (or both layers: the "
                       "colour map)")
    if (c[1], c[2]) != (hs, vs):
        bad.append(f"scale ${c[1]:02X}/${c[2]:02X}, want ${hs:02X}/${vs:02X}")
    if bm[0] & 0x07 != 0x04:
        bad.append(f"the bitmap layer's CONFIG ${bm[0]:02X}: want a 1 bpp bitmap")
    if bm[2] != tw:
        bad.append(f"the bitmap layer's TILEBASE ${bm[2]:02X}: want ${tw:02X} (VRAM_FG, the width)")
    for b in bad:
        print("check_vera:", b)
    if bad:
        sys.exit(1)
    print(f"check_vera: the display shows the bitmap ({mode}{', the colour map under it' if cmap else ''})")


if __name__ == "__main__":
    main()
