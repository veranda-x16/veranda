/* Veranda shell: Veranda Look 3 (overlay 12; "Sunroom", DECISIONS V132,
   V133): the colour icons' cache, the small icons, the soft shadow (the
   labels: look3b.c, overlay 16, since V165).

   MIT licence (see LICENSE). */
#include <veranda.h>
#include <string.h>
#include <theme.h>
#include "shell.h"
#pragma code-name ("OVERLAY12")
#pragma rodata-name ("OVL12RO")
#pragma data-name ("OVL12DATA")
#pragma bss-name ("OVL12BSS")

/*---------------------------------------------------------------- colour icons
   (Veranda Look 3, stage B: DECISIONS V133)

   On the plain tile desktop (wall.c: the theme's desktop colour in the
   kernel's tile mode) an icon is 4 x 4 cards of VERA's 4 bpp tiles in
   palette row IROW (tools/mkicons3.py's PAL; dark mode half as bright)
   under its outline in the ink. Where it comes from (by the file's
   class, 12 bytes of its info block):
   - the shell's library (tools/mkicons3.py lib shell/icons3.txt: overlay
     records 13 and 14, banks bLook3 + 1 and + 2; V207: past 24 after
     overlay 17's code, bank bPrg from OVF_BIG): the shell's own
     (folder, up, document, card, printer, trash), the ports, the
     programs of other repositories;
   - else the file's own colour icon (vpack.py's "icon3": 658 bytes at
     the file's end, flags bit 3), read when its folder is listed.
   The cache: NSLOT slots (a key, its tiles in VRAM: one allocator over
   the wallpaper area's tiles 17-479, which the plain desktop does not
   use, then the chrome's pool from 774 to 991; its map and ink in a RAM
   bank of its own, bInk). (V165) The cache holds what the screen shows,
   page by page: each slot says what shows it (sUse: window 0's page,
   window 1's, the desktop, the dock); a window drawn whole in front gives
   up its old page's (ic3_mark: a page turned, a folder opened; a window
   closed likewise), and a slot or tiles wanted take those nothing shows
   (evict), then, for the front window, the dock or the desktop, the
   window behind's (drawn again after: ic3Want bit 3); none left: Look 2's
   tile. The cache never starts again while the desktop stays (V161's
   flush and whole screen). All given back when tile mode starts again
   (ic3_reset). A desktop icon (on the desktop's colour) has
   its own copy of the tiles in row DROW, whose entry 14 is the desktop's
   colour (a tile's transparent pixels become 14 there; the icons' 14,
   lilac, white). Without the plain tile desktop (the pattern, Classic,
   640 x 240): Look 2's tiles, as before.

   (V153) On a picture (Dusk; V162 Still Water ...) too, when it keeps to palette
   rows 2-10 (tools/mkwall.py since V153; a file made before has rows
   2-12: Look 2's tiles then): the tiles given out are those above the
   picture's (352-479 for mkwall's default, wmLen) then the pool's; a
   desktop icon is the paper's row's (IROW: its transparent pixels and
   empty cards the paper, a white plate on the picture), no copy.
   (V152) The dock's programs: their class (the desk bank's icon n: a
   pin's, MAXPINS + a task's) kept by pins_icons (dir.c) through
   ic3_file(2, n, name), so a pinned or put-aside program shows its own
   icon or the library's. */

#define IROW    12              /* the icons' palette row (on the paper) */
#define DROW    11              /* the same with entry 14 the desktop's colour */
#define NSLOT   44              /* (V209: 40 held 40 keys; the package's Apps, both pages,
                                   the up icon and the desktop's three are 41: a page turned
                                   read a page's icons again from the card) */
#define NONE    0xFF            /* (V153) sN: a key with no colour icon (not looked for again) */
#define FULL    0xFE            /* (V157) sN: a key with a colour icon, no tiles left for it */
#define FREE    0xFD            /* (V165) sN: a slot given back (its key $FF) */
#define SLOT    144             /* a slot in bInk: the map (16), the ink (128) */
#define IC_LEN  658
#define PLAIN_T 16              /* the plain desktop's tile (wall.c), in row 2 */
#define T_LO    17              /* the tiles given out: 17-479 ... */
#define T_HI    480
#define P_LO    774             /* ... then the pool's free end (gui.s: DBOX + 4) */
#define P_HI    991             /* (991: the scroll bar's track, chrome.c: V151) */
#define MAPV    0x1AC00UL       /* the map: 256 bytes a row */
#define VREG(a) (*(volatile unsigned char *)(a))

/* the shell's own tiles (tiles.h's order: the ports by class, then
   folder, up, document, card, printer, trash) -> their library keys */
static const char bkeys[13][13] = {
    "geoWrite    ", "TopDesk     ", "GeoChess    ", "VCalc       ", "VModPlay    ", "Solitaire   ",
    "VSidPlay    ", "*Folder     ", "*Up         ", "*Document   ", "*SD card    ", "*Printer    ",
    "*Trash      " };

static unsigned char on = 0;                    /* the tile desktop: plain or a picture (DATA: an */
static unsigned char bInk = 0;                  /* overlay's BSS is not cleared) */
static unsigned char ns = 0;
static unsigned char plain = 0;                 /* (V153) the plain desktop: desktop icons in DROW */
static unsigned int tLo;
static char sKey[NSLOT][12];
static unsigned int sBase[NSLOT][2];            /* its tiles (0: not in VRAM), paper and desktop */
static unsigned char sN[NSLOT];
static unsigned char sLib[NSLOT];               /* its library bank (0: the file's own) */
static unsigned int sOff[NSLOT];
static unsigned char sUse[NSLOT];               /* (V165) what shows it: U_WIN << w, U_DESK, U_DOCK */
#define U_WIN   1
#define U_DESK  4
#define U_DOCK  8
#define ONE     0x80            /* (V209) evict: one slot */
static unsigned char retry = 0;                   /* (V165) a FULL key tried again (ic3_want: before a page is drawn) */
#define tset(t, n, v) XCALL(bIc2, ic3_tset, void (*)(unsigned int, unsigned int, unsigned char))(t, n, v)
#define WKEY    6400            /* (merge of V151-V153: the windows' GEOS files' classes in bInk,
                                   2 x MAXICON x 13 bytes from here (V209: after NSLOT x SLOT),
                                   for overlay 12's room; V165:
                                   the 13th its colour icon: 0 none, 1 the library's, 2 its own) */
#define WREC    13
extern char k3buf[13];                          /* (main.c: a class read back) */
#define NDOCK (MAXPINS + TASK_MAX)
static char dKey[NDOCK][12];                    /* (V152) the dock's programs' (the desk bank's icons) */
extern unsigned char wRows[2];                  /* (wall.c, overlay 11) the picture's first palette row, rows */

static unsigned int shT;                        /* (V151) the soft shadow's 5 tiles: T_LO (the first
                                                   given out: bars.c's SH_T), 0 none */
static void smInit(void);
static unsigned char fromLib(const char *k);
static void tileAt(unsigned int t);
static void smKeys(void);
static unsigned char smFind(const char *k);
static unsigned char wSm[2][MAXICON];           /* (V151) the windows' GEOS files' small icons ($FF: none) */

/* palette rows IROW and DROW, the shadow's shades: look3b.c (V165, for
   the room) */
static void pal(void)
{
    XCALL(bIc2, ic3_rows, FB)(plain);
}

/* the cache emptied (tile mode on again: wall.c); o 0 none (the
   pattern), 2 a picture, 3 the plain tile desktop; the rows written */
void ic3_reset(unsigned char o)
{
    unsigned char k;
    unsigned int lo = T_LO;
    tileAt(991);                    /* (V151) the scroll bar's track (chrome.c): the paper */
    for (k = 0; k < 32; ++k)        /* and the chrome, a pixel each */
        VREG(0x9F23) = k & 4 ? 0x20 : 0x02;
    if (o == 2) {                   /* (V153) a picture: above its tiles, if it leaves rows 11-12 */
        bget(bWall, (unsigned int)wRows - 0xA000, tileBuf, 2);
        lo = wmLen >> 5;
        if (tileBuf[0] + tileBuf[1] > DROW)
            o = 0;
    }
    if (o && on && lo == tLo && (o & 1) == plain) {     /* (the same desktop: its tiles are kept) */
        pal();
        return;
    }
    if (ns && o)                    /* (V161) the keys of the shell's windows and dock */
        ic3Want |= 4;               /* forgotten: the dock's read again (bars.c's ic3_idle) */
    on = o != 0;
    plain = o & 1;
    ns = 0;
    tLo = lo;
    XCALL(bIc2, ic3_tinit, void (*)(unsigned int))(lo);    /* (V165) the tiles given out: none */
    if (o && !bInk)
        bInk = BankAlloc(1);
    if (!bInk)
        on = 0;
    shT = 0;
    if (on) {
        pal();
        smInit();                   /* (V161: the shell's own six no longer loaded first, V157:
                                       when the tiles run out the cache starts again and what
                                       is on the screen is loaded, in the order it is drawn) */
    }
    ic3On = on;
}

/* the rows again (a theme or mode change) */
void ic3_pal(void)
{
    if (on)
        pal();
}

/* (V165) the tiles: look3b.c's ic3_tget (a bit each, the first free run
   that fits, the holes evicted icons left too); none:
   the icons that nothing on the screen shows are given back (evict) and
   the holes looked for again. The cache no longer starts again (V161's
   flush: the whole screen drawn again, every icon read again from the
   card) */
#define tget(n) XCALL(bIc2, ic3_tget, unsigned int (*)(unsigned char))(n)
static unsigned char evict(unsigned char m);
static unsigned char prio = 0;                    /* (V165) the icon wanted is the front window's,
                                                   the dock's or the desktop's */
static unsigned char noEv = 0;                    /* (V165) ic3_spare: nothing given up for it */

/* (V165) still none: the window behind gives up its page's (prio), and
   is drawn again when the drawing is done (main.c's idle, bars.c's
   ic3_idle: ic3Want bit 3), its icons then from what is left */
static unsigned char back(void)
{
    if (!prio || front >= NWIN || !evict(U_WIN << (front ^ 1)))
        return 0;
    ic3Want |= 8;
    return 1;
}

static unsigned int talloc(unsigned char n)
{
    unsigned int t;
    if (!(t = tget(n)) && !noEv && (!evict(0) || !(t = tget(n))) && back())
        t = tget(n);
    return t;
}

/* (V165) the slots nothing on the screen shows but what m says (m 0:
   sUse 0, not in a window's page since it was drawn whole, not the
   desktop's, not the dock's) given back, their tiles freed; 0 none
   (V209: m ONE, a slot wanted: only the first of them, so a page turned
   back finds the rest of its icons still there). The
   cache holds what the screen shows: the windows' pages, the desktop, the
   dock, the sidebars' (the small icons), NSLOT keys at most */
static unsigned char evict(unsigned char m)
{
    unsigned char s, any = 0, n;
    for (s = 0; s < ns; ++s) {
        if ((sUse[s] & ~m) || (n = sN[s]) == FREE)
            continue;
        if (n && n <= 16) {
            tset(sBase[s][0], n, 0);
            if (sBase[s][1])
                tset(sBase[s][1], n, 0);
        }
        sN[s] = FREE;
        memset(sKey[s], 0xFF, 12);
        any = 1;
        if (m & ONE)
            break;
    }
    return any;
}

/* (V165) window w (in front) drawn whole: what it showed no longer keeps
   its icons, nor a closed window's (look3b.c's ic3_page) */
void ic3_mark(unsigned char w)
{
    unsigned char s, m = U_WIN << w;
    if (!wins[w ^ 1].open)
        m |= U_WIN << (w ^ 1);
    for (s = 0; s < ns; ++s)
        sUse[s] &= ~m;
}

/* the key k's slot, or ns */
static unsigned char sHash[NSLOT];              /* (V165) its key's bytes added: find compares those first */

static unsigned char hash(const char *k)
{
    unsigned char i, h = 0;
    for (i = 0; i < 12; ++i)
        h += k[i];
    return h;
}

static unsigned char find(const char *k)
{
    unsigned char s, h = hash(k);
    for (s = 0; s < ns; ++s)
        if (sHash[s] == h && !memcmp(sKey[s], k, 12))
            break;
    return s;
}

/* (V165) a slot for key k: its own, a slot given back, a new one, or
   one evicted for it; NSLOT none */
static unsigned char slotFor(const char *k)
{
    unsigned char s = find(k), e = 0;
    if (s < ns)
        return s;
again:
    for (s = 0; s < ns; ++s)
        if (sN[s] == FREE)
            goto got;
    if (ns < NSLOT)
        goto got;
    if (!noEv && !e++ && (evict(ONE) || back()))
        goto again;
    return NSLOT;
got:
    sUse[s] = 0;
    return s;
}

/* VERA's port 0 at tile t's first byte, increment 1 */
static void tileAt(unsigned int t)
{
    unsigned long a = 0x13000UL + ((unsigned long)t << 5);
    VREG(0x9F25) = 0;
    VREG(0x9F20) = a;
    VREG(0x9F21) = a >> 8;
    VREG(0x9F22) = 0x10 | (unsigned char)(a >> 16);
}

/* (V153) vn tiles (32 bytes each, vn 1-16) from vp to VERA's port 0
   (the C loop took 1,300 cycles a tile's byte: gate tile's ALL) */
static const unsigned char *vp;
static unsigned char vn;
static void vout(void)
{
    __asm__("lda %v", vp);
    __asm__("sta ptr1");
    __asm__("lda %v+1", vp);
    __asm__("sta ptr1+1");
    __asm__("ldx %v", vn);
    __asm__("ic3vo1: ldy #0");
    __asm__("ic3vo2: lda (ptr1),y");
    __asm__("sta $9F23");
    __asm__("iny");
    __asm__("cpy #32");
    __asm__("bne ic3vo2");
    __asm__("tya");
    __asm__("clc");
    __asm__("adc ptr1");
    __asm__("sta ptr1");
    __asm__("bcc ic3vo3");
    __asm__("inc ptr1+1");
    __asm__("ic3vo3: dex");
    __asm__("bne ic3vo1");
}

/* the record in buf (IC_LEN bytes) into slot ns for key k (or its
   slot that says none: V153); its paper tiles to VRAM; NSLOT if no room */
static unsigned char load(const char *k, unsigned char lib, unsigned int off)
{
    unsigned char s = slotFor(k), n = buf[0];
    unsigned int t;
    if (s >= NSLOT || n > 16 || buf[1] != 3)
        return NSLOT;
    t = n ? talloc(n) : 1;
    if (!t)
        return NSLOT;
    memcpy(sKey[s], k, 12);
    sHash[s] = hash(k);
    sN[s] = n;
    sLib[s] = lib;
    sOff[s] = off;
    sBase[s][0] = t;
    sBase[s][1] = 0;
    bput(bInk, s * SLOT, buf + 2, SLOT);
    tileAt(t);
    vp = buf + 146;
    if ((vn = n) != 0)
        vout();
    if (s == ns)
        ++ns;
    return s;
}

/* (V157) key k kept as v (NONE: no colour icon; FULL: one, but no tiles
   were left for it), so it is not looked for again until the cache
   empties; full says which (no slot left to keep it: FULL) */
static unsigned char full;

static void keep(const char *k, unsigned char v)
{
    unsigned char s = slotFor(k);
    if (s >= NSLOT) {
        full = 1;
        return;
    }
    memcpy(sKey[s], k, 12);
    sHash[s] = hash(k);
    sN[s] = v;
    if (s == ns)
        ++ns;
    full = v == FULL;
}

/* key k in the library: its bank (libB) and record offset (libO); 0 none */
static unsigned char libB;
static unsigned int libO;

/* (V207) prg.c's ic3_lib (overlay 17, for this one's room; its third
   record after its code) */
typedef unsigned int (*FLIB)(const char *);

static unsigned char inLib(const char *k)
{
    memcpy(k3buf, k, 12);               /* (the other overlay sees main RAM alone: bkeys) */
    if (!(libO = XCALL(bPrg, ic3_lib, FLIB)(k3buf)))
        return 0;
    libB = k3buf[12];
    return 1;
}

/* key k from the library: its slot, or NSLOT (kept as NONE or FULL) */
static unsigned char fromLib(const char *k)
{
    unsigned char s;
    if (!inLib(k)) {
        keep(k, NONE);
        return NSLOT;
    }
    bget(libB, libO, buf, IC_LEN);
    if ((s = load(k, libB, libO)) >= NSLOT)
        keep(k, FULL);
    return s;
}

/* window w's GEOS file n (look3b.c's dir_info: its info block in
   fileHeader, its folder the current one): its class kept, and (V165)
   where its colour icon is (the library, its own, none: so a drawing never
   opens a file to learn it has none); 1 when it carries its own and the
   tile desktop shows (dir_info reads it into RAM in the same open: no
   tiles are given yet, V157). The dock's program n (w 2; V152; n $FF:
   none yet): its icon into the cache now */
static unsigned char own(const char *k, const char *name, unsigned char w);

unsigned char ic3_file(unsigned char w, unsigned char n, const char *name)
{
    const char *k = (const char *)fileHeader + 77;
    unsigned char s, mine = !memcmp(fileHeader + 137, "VRND", 4) && (fileHeader[143] & 8);
    if (w == 2) {
        if (n >= NDOCK) {
            memset(dKey, 0, sizeof dKey);
            for (s = 0; s < ns; ++s)
                sUse[s] &= ~U_DOCK;
            return 0;
        }
        memcpy(dKey[n], k, 12);
        if (!on)
            return 0;
        s = find(k);                    /* (cached, or none yet: V153; FULL tried again; V180:
                                           NONE too, a drawing's before its file was read) */
        if (s >= ns || sN[s] >= FULL)
            if ((s = fromLib(k)) >= NSLOT && !full && mine)
                s = own(k, name, 2);
        if ((s = find(k)) < ns)
            sUse[s] |= U_DOCK;
        return 0;
    }
    if (!bInk)
        bInk = BankAlloc(1);
    wSm[w][n] = 0xFF;
    if (on) {                           /* (its small icon: V151) */
        smKeys();
        wSm[w][n] = smFind(k);
    }
    if (!bInk)
        return 0;
    memcpy(k3buf, k, 12);
    k3buf[12] = inLib(k) ? 1 : mine ? 2 : 0;
    bput(bInk, WKEY + (w * MAXICON + n) * WREC, k3buf, WREC);
    return on && k3buf[12] == 2;
}

/* key k's colour icon: (V165) kept in RAM (look3b.c), else from the end
   of the file name (window w's: its folder made the current one; the
   dock's, 2: it is), then kept in RAM; kept as NONE when it cannot be
   read, FULL when no tiles are left; its slot or NSLOT */
static unsigned char own(const char *k, const char *name, unsigned char w)
{
    unsigned char h, ok, s = NSLOT;
    unsigned long o;
    memcpy(k3buf, k, 12);               /* (the other overlay sees main RAM alone) */
    if (XCALL(bIc2, ic3_stget, unsigned char (*)(void))())
        goto got;
    if (noEv)                           /* (V165: ic3_spare, the next page ahead: no file read) */
        return NSLOT;
    if (w < 2 && w != front)
        ChDir(wins[w].path);
    h = FOpen((void *)name, 'r');
    ok = 0;
    if (h >= 2 && h <= 9) {
        ok = FRead(h, buf, 230) == 230 && buf[225] == 'I' && buf[226] == '3';
        if (ok) {
            o = buf[227] | (unsigned long)buf[228] << 8 | (unsigned long)buf[229] << 16;
            ok = !FSeek(h, (unsigned int)o, (unsigned int)(o >> 16)) && FRead(h, buf, IC_LEN) == IC_LEN;
        }
        FClose(h);
    }
    if (w < 2 && w != front && front < NWIN)
        ChDir(wins[front].path);
    if (!ok) {
        keep(k, NONE);
        return NSLOT;
    }
    XCALL(bIc2, ic3_stput, FV)();
got:
    if ((s = load(k, 0, 0)) >= NSLOT)
        keep(k, FULL);                  /* (V157: its own, no tiles left) */
    return s;
}

/* (V156) Veranda Write's documents: geoWrite's class (Veranda Write opens
   them: V135), and its own .cwr files (not GEOS files: E, a window's
   entry, ends in ".cwr") shown with it too; (V197) a plain ".prg", an
   X16 program BASIC runs (prg.c), with the library's "X16 program" (the
   small icons: a program's); (V207) the players' music and video files.
   prg.c's ic3_ext (overlay 18, for this one's room): E's kind (1 ".cwr",
   2 ".prg", 3 music, 4 video; 0 none, or not a window's plain file) or
   kind's, its library key in k3buf */
typedef unsigned char (*FEXT)(unsigned char, unsigned char);
#define ext(w, kind) XCALL(bPrg, ic3_ext, FEXT)(w, kind)

/* the slot of window w's (2: the desk's) tile t, its GEOS file's icon i
   (w 0, 1); NSLOT: none */
static unsigned char slotOf(unsigned char w, unsigned char t, unsigned char i)
{
    const char *k;
    unsigned char s, b = t & TL_BUILT;
    if (!on)
        return NSLOT;
    if (b) {
        t &= 0x1F;
        if (t >= 13)
            return NSLOT;
        k = bkeys[t];
        if (t == 9 && ext(w, 0))                /* (9: tiles.h's T_DOCUMENT) */
            k = k3buf;
    } else if (w < 2 && i < MAXICON) {
        bget(bInk, WKEY + (w * MAXICON + i) * WREC, k3buf, WREC);
        k = k3buf;
    }
    else if (w == 2 && i < NDOCK && dKey[i][0])
        k = dKey[i];
    else
        return NSLOT;
    s = find(k);
    if (s < ns && !(retry && sN[s] == FULL)) {
        full = sN[s] == FULL;
        if (sN[s] < FULL)
            goto use;
        return NSLOT;
    }
    /* (V165) a window's file: where its icon is, from its listing (V161:
       a key not kept, the cache reset by another desktop: read again, never
       taken for one with none); its own kept in RAM, read from its file
       (E: its entry) only when it is not */
    prio = w == 2 || w == front;
    if (w < 2 && !b && k3buf[12] != 1) {
        full = 0;
        if (!k3buf[12])
            return NSLOT;
        s = own(k, E.name, w);
    } else
        s = fromLib(k);                 /* (V153: kept as none, V156: or full) */
    if (s >= NSLOT)
        return s;
use:
    if (!noEv)
        sUse[s] |= w < 2 ? U_WIN << w : b ? U_DESK : U_DOCK;
    return s;
}

/* (V165) look3b.c's ic3_page: window w's cell of tile t (its GEOS file's
   icon i) loaded before the page is drawn */
void ic3_want(unsigned char w, unsigned char t, unsigned char i)
{
    retry = 1;
    slotOf(w, t, i);
    retry = 0;
}

/* (V165) look3b.c's ic3_ahead: the next page's icon loaded while the
   shell waits, in tiles nothing on the screen uses (none given up for it,
   not kept as shown: the page's drawing marks it) */
void ic3_spare(unsigned char w, unsigned char t, unsigned char i)
{
    noEv = 1;
    slotOf(w, t, i);
    noEv = 0;
}

typedef unsigned char (*FTILE)(unsigned char, unsigned int, unsigned char, unsigned char, unsigned char);

/* the ink of window w's tile t at card cx, row y (tiles.c's tile_draw
   when there is no colour icon: its colour then); $FF a colour icon
   ($FE the desk's on a picture: its plate wants a frame, V153). (V156) On
   the tile desktop a file with no colour icon (none, or no tiles left) is
   its 1-bit picture alone, as a colour icon's ink: no Look 2 frame */
unsigned char ic3_draw(unsigned char cx, unsigned int y, unsigned char w, unsigned char t, unsigned char icon)
{
    unsigned char s, c = clipOn, r = 0xFF;
    full = 1;
    s = slotOf(w, t, icon);
    if (s >= NSLOT) {
        if (full)                       /* (V157: no tiles left, or no tile desktop: Look 2's tile) */
            r = XCALL(bTile, tile_draw, FTILE)(cx, y, w, t, icon);
        else
            XCALL(bTile, tile_draw, FTILE)(cx, y, w | 0x80, t, icon);
        goto done;
    }
    bget(bInk, s * SLOT + 16, tileBuf, 128);
    if (c && cx * 8 >= leftMargin && (cx + 4) * 8 - 1 <= rightMargin && y >= windowTopW && y + 31 <= windowBottomW)
        clipOn = 0;
    WBitmapUp(tileBuf, cx, 4, y, 0x8000 | 32);
    clipOn = c;
done:
    if (ic3Now == w + 1)                /* (V165) the cell's colours with its ink: drawn once */
        ic3_colour(cx, y >> 3, w, t, 0xFF);
    if (r != 0xFF)
        return r;
    return w == 2 && !plain ? 0xFE : 0xFF;      /* (V153: a desktop icon on a picture gets a frame) */
}

/* map entry lo, hi at card x, y (in the colour clip; a card a menu or a
   dialog box covers keeps the row it shows, its own into its shadow
   byte: gui.s's Put) */
static void put(unsigned char x, unsigned char y, unsigned char lo, unsigned char hi)
{
    unsigned char a;
    unsigned int m = 0xAC00 + ((unsigned int)y << 8) + (x << 1);
    if (colClip && (x < colX0 || x > colX1 || y < colY0 || y > colY1))
        return;
    VREG(0x9F25) = 0;
    VREG(0x9F20) = m + 1;
    VREG(0x9F21) = (m + 1) >> 8;
    VREG(0x9F22) = 1;
    a = VREG(0x9F23);
    if (a >= 0xE0) {
        VREG(0x9F23) = (a & 0xF0) | (hi & 0x0F);
        VREG(0x9F20) = m;
        VREG(0x9F23) = lo;
        m = 0xAC00 + ((unsigned int)y << 8) + 160 + x;
        VREG(0x9F20) = m;
        VREG(0x9F21) = m >> 8;
        a = VREG(0x9F23);
        VREG(0x9F23) = (a & 0x0F) | (hi & 0xF0);
        return;
    }
    VREG(0x9F20) = m;
    VREG(0x9F21) = m >> 8;
    VREG(0x9F22) = 0x11;
    VREG(0x9F23) = lo;
    VREG(0x9F23) = hi;
}

/* slot s's tiles for the desktop (row DROW: 0 -> 14, 14 -> 1) */
static const unsigned char nib[16] = { 14, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 1, 15 };
static unsigned int deskTiles(unsigned char s)
{
    unsigned int t, i;
    unsigned char v, *p;
    if (sBase[s][1] || !sLib[s] || !sN[s])
        return sBase[s][1];
    t = talloc(sN[s]);
    if (!t)
        return 0;
    i = sN[s] << 5;
    bget(sLib[s], sOff[s] + 146, buf, i);
    for (p = buf; i; --i, ++p) {        /* (V153: the count once; it was evaluated a byte) */
        v = *p;
        *p = nib[v >> 4] << 4 | nib[v & 15];
    }
    tileAt(t);
    vp = buf;
    vn = sN[s];
    vout();
    sBase[s][1] = t;
    return t;
}

/* the colours of window w's tile t at cards cx, cy (gui.s's gui_icon
   when there is no colour icon); d a desktop icon (0-2), else $FF;
   window w's (0, 1) GEOS file is E's */
void ic3_colour(unsigned char cx, unsigned char cy, unsigned char w, unsigned char t, unsigned char d)
{
    unsigned char s, k, m, row, lo, hi;
    unsigned int b = 0;
    if (ic3Now == (0x80 | (w + 1)))     /* (V165) written with its ink (win.c's content) */
        return;
    full = 1;
    s = slotOf(w, t, E.icon - I_OWN);
    if (s >= NSLOT && full)
        goto look2;
    row = IROW;
    if (s < NSLOT)
        b = sBase[s][0];
    if (w == 2 && d != 0xFF && plain) {         /* (on a picture: the paper's row, V153) */
        row = DROW;
        if (s < NSLOT && !(b = deskTiles(s))) {
look2:                                          /* (no tiles left: Look 2's colours, V157) */
            XCALL(bWall, gui_icon, FICON)(cx, cy, w, t, d);
            return;
        }
    }
    /* (V156) none (no colour icon, or no tiles left for it): every card
       empty, the paper (the desktop's colour on the plain desktop) under
       the picture's ink (ic3_draw) */
    memset(tileBuf, 0x80, 16);
    if (b)
        bget(bInk, s * SLOT, tileBuf, 16);
    for (k = 0; k < 16; ++k) {
        m = tileBuf[k];
        if (m & 0x80) {
            lo = row == DROW ? PLAIN_T : 0;
            hi = row == DROW ? 0x20 : 0;
        } else {
            lo = b + (m & 15);
            hi = row << 4 | ((b + (m & 15)) >> 8) | (m & 0x10 ? 4 : 0) | (m & 0x20 ? 8 : 0);
        }
        put(cx + (k & 3), cy + (k >> 2), lo, hi);
    }
}

/*---------------------------------------------------------------- the soft shadow
   (Look 3, V151) On the plain tile desktop a window's shadow is 3 pixels
   right and below it (from 3 pixels in), in the desktop's colour halved
   and, its outer pixel, three quarters (entries 2 and 3 of row 2: pal):
   five tiles over the plain tile (the right column's first card, its
   others, the corner, the bottom row's first card, its others), made
   here, the first given out after a reset (tile T_LO); bars.c puts
   them on the cards (ic3_shadow, chrome_shadow: the ink) */

static void shTiles(void)
{
    if ((shT = talloc(5)) != 0)         /* (its five tiles written by look3b.c: V165) */
        XCALL(bIc2, ic3_shadow5, void (*)(unsigned int))(shT);
}

/*---------------------------------------------------------------- the small icons
   (Look 3, V151) 16 x 16 colour icons in the list, the small icons' view
   and the sidebar, 2 x 2 cards in row IROW under their ink: the shell's
   library of them (tools/mkicons3.py lib icons3s.txt: overlay record 15,
   bank bLook3 + 3; V207: past NSM after overlay 17's code, bank bPrg; by class as the large ones, "*App" any other
   program); their tiles to VRAM when first drawn (the large ones'
   allocator). None (no room, Look 2): the caller draws Look 2's badge */

#define SM_AT   560             /* the record: [count, keys (12 bytes)] ... */
#define SM_LEN  165             /* ... icon i at SM_AT + SM_LEN i: tiles n, the map (4), the ink (32), the tiles */
#define NSM     46
#define bSm     (bLook3 + 3)
#define NOVF    8                       /* (V207) icons NSM and up: after prg.c's code (bank bPrg, */
#define OVF     0x1000                  /* tools/mkicons3.py ovf: [count, keys] at OVF, icon j at */
#define OVF_AT  (OVF + 1 + NOVF * 12)   /* OVF_AT + SM_LEN j) */

static unsigned int smT[NSM + NOVF];            /* icon i's tiles in VRAM (0: not yet) */
static unsigned char smN;                       /* the library's icons */
static unsigned char smB[13];                   /* the shell's own tiles' (tiles.h's order) */
static unsigned char smApp;
static unsigned char smB2;                      /* (V207) ic3_small's icon's bank */
static unsigned char smX[5];                    /* (V156, V207) a plain file's by its extension (ext's kind) */

/* the library's keys into buf (V207: the overflow's from buf + 1 +
   NSM * 12, its count first); their count */
static void smKeys(void)
{
    bget(bSm, 0, buf, 1 + NSM * 12);
    bget(bPrg, OVF, buf + 1 + NSM * 12, 1 + NOVF * 12);
    smN = buf[0] + buf[1 + NSM * 12];   /* (tools/mkicons3.py lib: NSM, then the overflow's) */
}

/* key k's icon (smKeys first), $FF none */
static unsigned char smFind(const char *k)
{
    unsigned char i;
    for (i = 0; i < smN; ++i)
        if (!memcmp(buf + 1 + 12 * i + (i >= NSM), k, 12))
            return i;
    return 0xFF;
}

#pragma static-locals (push, on)

static void smInit(void)
{
    unsigned char t;
    memset(smT, 0, sizeof smT);
    shTiles();
    smKeys();
    for (t = 0; t < 13; ++t)
        smB[t] = smFind(bkeys[t]);
    smApp = smFind("*App        ");
    for (t = 1; t < 5; ++t) {
        ext(0, t);
        smX[t] = smFind(k3buf);
    }
    smX[2] = smApp;
}

/* window w's (2: the sidebar's) tile t (E's, its GEOS file's i): the
   small icon, $FF none */
static unsigned char smOf(unsigned char w, unsigned char t)
{
    unsigned char i = E.icon - I_OWN;
    if (t & TL_BUILT) {
        if ((t &= 0x1F) >= 13)
            return 0xFF;
        if (t == 9 && (i = ext(w, 0)) != 0)
            return smX[i];
        return smB[t];
    }
    if (w < 2 && i < MAXICON && (i = wSm[w][i]) != 0xFF)
        return i;
    return E.geos == APPLICATION || E.geos == DESK_ACC ? smApp : smB[9];   /* (tiles.h: T_DOCUMENT) */
}

/* window w's tile t (E's; w 2: the sidebar's) as a small icon at card cx,
   line y: its ink (ink 1) or its colours (0: map entries at card row
   y / 8); 0 none */
unsigned char ic3_small(unsigned char cx, unsigned int y, unsigned char w, unsigned char t, unsigned char ink)
{
    unsigned char s, k, m, lo, hi;
    unsigned int b, o;
    if (!on || (s = smOf(w, t)) >= NSM + NOVF)
        return 0;
    k = bSm;
    o = SM_AT + s * SM_LEN;
    if (s >= NSM) {
        k = bPrg;
        o += OVF_AT - SM_AT - NSM * SM_LEN;     /* (OVF_AT + (s - NSM) SM_LEN, modulo 2^16) */
    }
    smB2 = k;
    if (!(b = smT[s])) {
        bget(k, o, buf, SM_LEN);
        if (buf[0] > 4 || !(b = talloc(buf[0])))
            return 0;
        tileAt(b);
        for (k = 0; k < 128; ++k)
            VREG(0x9F23) = buf[37 + k];
        smT[s] = b;
    }
    if (ink) {
        bget(smB2, o + 5, tileBuf, 32);
        WBitmapUp(tileBuf, cx, 2, y, 0x8000 | 16);
        return 1;
    }
    bget(smB2, o + 1, tileBuf, 4);
    y >>= 3;
    for (k = 0; k < 4; ++k) {
        m = tileBuf[k];
        lo = hi = 0;
        if (!(m & 0x80)) {
            o = b + (m & 3);
            lo = o;
            hi = IROW << 4 | o >> 8 | (m & 0x30) >> 2;
        }
        put(cx + (k & 1), y + (k >> 1), lo, hi);
    }
    return 1;
}

#pragma static-locals (pop)

/* (V161) the tiles ran out while drawing (talloc: ic3Want): the cache
   started again (the shell's own six first), so the next drawing (main.c:
   the dock's icons first, then everything) loads only what is on the
   screen */
void ic3_flush(void)
{
    if (on) {
        tLo = 0;                    /* (not the same desktop: all given back) */
        ic3_reset(plain | 2);
    }
}
