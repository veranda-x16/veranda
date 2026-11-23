/* The desktop's background (Veranda Look 2, step C: DECISIONS V78), for
   the shell and Preferences.

   WALL_CFG, a plain file of WALL_CFGLEN bytes in the system's data folder
   (VR_DATADIR, /VERANDA/.SYSTEM), written by Preferences (Desktop page)
   and by the shell (options > desktop pattern), read by the shell at its
   start and when a desk accessory closes:
     0-1   "WP"
     2     1 (the version)
     3     the kind: WALL_PICTURE, WALL_PLAIN (the theme's desktop colour),
           WALL_PATTERN (a GEOS pattern on it, the classic look)
     4     the pattern (0-7: the shell's eight)
     8-31  the picture: its GEOS name (a wallpaper file, NAME.cvt;
           0-terminated)
     32-63 its folder (0-terminated; VR_WALLDIR, /VERANDA/WALLPAPERS)
   No file: the plain desktop colour (WALL_DEFKIND; Look 3's Sunroom, V132:
   the sage; before V132 the picture WALL_DEFAULT, which Preferences still
   offers first), the picture WALL_DEFAULT in VR_WALLDIR once a picture is
   chosen. A wallpaper is a GEOS
   document of class WALL_CLASS made by tools/mkwall.py
   (docs/APPFORMAT.md, "Wallpapers"); a missing one, the Classic theme
   (no colours) or a screen other than 640 x 480 give the pattern
   instead. Dark mode takes the file's dark palette rows. */
#ifndef WALLCFG_H
#define WALLCFG_H

#define WALL_CFG      "WALLPAPER.CFG"
#define WALL_CFGLEN   64
#define WALL_KIND     3
#define WALL_PAT      4
#define WALL_NAME     8
#define WALL_NAMELEN  24
#define WALL_DIR      32
#define WALL_DIRLEN   32
#define WALL_PICTURE  0
#define WALL_PLAIN    1
#define WALL_PATTERN  2
#define WALL_DEFAULT  "Dusk"
#define WALL_DEFKIND  WALL_PLAIN    /* (V132) no WALL_CFG: the plain colour */
#define WALL_CLASS    "Wallpaper"

/* the file's data (from byte 508 of the CVT file; version 3, DECISIONS
   V102: VERA 4 bpp tiles in palette rows 2-12 of 10 colours, 11-15 of each
   row and row 13 the shell's colour chrome; version 2, V101's, rows 2-13
   of 15 colours, still shown, without the chrome; version 1, V78's 1 bpp
   bitmap over a colour a card, is no longer shown: tools/mkwall.py --from
   makes it again) */
#define WALL_MAGIC    "VWAL"
#define WALL_VERSION  3
#define WALL_HEAD     16            /* 8-9 the tiles, 10 the first palette row, 11 the rows; */
#define WALL_ROWS     12            /* (at most) then the rows (light, dark), the map, the tiles */
#define WALL_GUIROW   13            /* version 3: the shell's palette row (its icons, the shades) */
#define WALL_MAXTILES 480           /* VRAM $13000-$16BFF */
#define WALL_MAP      9600u         /* 80 x 60 entries of 2 bytes */
/* the kernel's tile mode (ColorRect COLOR_TILES; x16hw.inc's TILE_*) */
#define WALL_TILEBASE 0x98          /* VERA's L0_TILEBASE in tile mode */
#define WALL_HIROW    14            /* palette row: a covered card's highlight */
#define WALL_COVROW   15            /* palette row: a covered card's paper */

#endif
