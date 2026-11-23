/* Archive: C64 and C128 GEOS disk images (D64, D71, D81) on Veranda.

   It opens an image from the card (the SDK's Open dialog, vrchoose.h,
   compiled into overlay 1: long names, DECISIONS V79, V82), lists its
   directory (each file's name, GEOS type, structure, size, class and the
   icon from its info block; plain CBM files too) and extracts files into
   the folder the image is in: a GEOS file (sequential or VLIR) as a CVT
   file (docs/APPFORMAT.md; its GEOS name kept inside), a plain PRG, SEQ
   or USR file as it is. geoPaint documents, Photo Scraps and photo
   albums become Paint documents (version 3).

   The image is read a block at a time with FSeek and FRead; its BAM, its
   directory, the info blocks and the names on the card are kept in RAM
   banks. tools/vdisk.py does the same on a PC (the gate's
   oracle): the names, the listing, the CVT bytes and the conversions are
   defined there, and this file follows it.

   MIT licence (see LICENSE). */
#include <veranda.h>
#include <vr.h>
#include <string.h>
#include <stdlib.h>
#include <vrpath.h>
#include <theme.h>
#include <vrchoose.h>
#include <vrwin.h>

#define RAMBANK (*(volatile unsigned char *)0)
#define BANKMEM ((unsigned char *)0xA000)

/* the banks (one BankAlloc) */
#define NB_DIR   2              /* 296 entries of 32 bytes */
#define NB_INFO  10             /* 296 info blocks of 256 */
#define NB_DATA  8              /* a file's data for a conversion: 64 KB */
#define NBANKS   (1 + NB_DIR + NB_INFO + 1 + 1 + NB_DATA)
static unsigned char bBam, bDir, bInfo, bNames, bMap, bData;
static unsigned char bDlg;              /* overlay 1: the Open dialog */

#define MAXE     296
#define NAMESZ   24             /* a name on the card, 0-terminated */
#define LISTSZ   (VRF_NAME + 1) /* an image's name */

/* the screen: 80 x 60 cards */
#define TOP      48             /* the first row (V148: under the column headings) */
#define ROWH     24
#define ROWS     17

enum { K_D64, K_D71, K_D81 };
static const char *const kname[] = { "D64", "D71", "D81" };

/*---------------------------------------------------------------
  errors
 ---------------------------------------------------------------*/
enum { E_OK, E_READ, E_LINK, E_LOOP, E_SIZE, E_WRITE, E_FULL, E_LONG, E_KIND, E_SHORT };
static const char *const emsg[] = {
    "", "The image cannot be read.", "A link points outside the disk.",
    "A chain of blocks runs in a loop.", "This is not a D64, D71 or D81 image.",
    "The file cannot be written.", "Too many files.", "A record is too long to convert.",
    "Not a picture.", "The picture's data ends early."
};

#ifdef ARCHIVE_TEST
void archive_test_listed(void);
void archive_test_clock_reset(void);
void archive_test_clock_log(const char *what);
void archive_test_dialog(void);
#endif

static char line[128];                 /* (a header line with a long image name: V82) */
static char msg[96];

static void status(const char *s);


/*---------------------------------------------------------------
  the image: blocks
 ---------------------------------------------------------------*/
static unsigned char img;               /* the stream, 0 none */
static unsigned char kind, tracks;
static unsigned int tstart[82];         /* a track's first block */
static unsigned int total;              /* blocks */
static unsigned long ipos;
static unsigned char sec[256];
static unsigned char cur_t, cur_s;

static unsigned char spt(unsigned char t)
{
    if (kind == K_D81)
        return 40;
    if (t > 35)
        t -= 35;
    return t <= 17 ? 21 : t <= 24 ? 19 : t <= 30 ? 18 : 17;
}

static unsigned char valid(unsigned char t, unsigned char s)
{
    return t >= 1 && t <= tracks && s < spt(t);
}

/* block t/s into sec */
static unsigned char rd(unsigned char t, unsigned char s)
{
    unsigned long off;
    if (t == cur_t && s == cur_s)
        return E_OK;
    if (!valid(t, s))
        return E_LINK;
    off = (unsigned long)(tstart[t] + s) << 8;
    cur_t = 0;
    if (off != ipos && FSeek(img, (unsigned int)off, (unsigned int)(off >> 16))) {
        ipos = 0xFFFFFFFF;
        return E_READ;
    }
    if (FRead(img, sec, 256) != 256) {
        ipos = 0xFFFFFFFF;
        return E_READ;
    }
    ipos = off + 256;
    cur_t = t;
    cur_s = s;
    return E_OK;
}

static void geometry(void)
{
    unsigned char t;
    tstart[1] = 0;
    for (t = 1; t <= tracks; ++t)
        tstart[t + 1] = tstart[t] + spt(t);
    total = tstart[tracks + 1];
}

/*---------------------------------------------------------------
  the directory, in banks
 ---------------------------------------------------------------*/
static unsigned int nents;
static unsigned char hash[MAXE];
static unsigned char selmap[(MAXE + 7) / 8];
static char diskname[17];
static unsigned int freeblk;
static char imgname[LISTSZ];

static unsigned char *entry(unsigned int i)         /* maps the bank */
{
    RAMBANK = bDir + (i >> 8);
    return BANKMEM + ((i & 255) << 5);
}

static unsigned char *info(unsigned int i)
{
    RAMBANK = bInfo + (i >> 5);
    return BANKMEM + ((i & 31) << 8);
}

static char *outname(unsigned int i)
{
    RAMBANK = bNames;
    return (char *)BANKMEM + i * NAMESZ;
}

/* entry flags, byte 30 of its slot */
#define F_GEOS   1
#define F_COPY   2

static unsigned char ent[32];           /* a copy of the entry in hand */
static unsigned char hdr[256];          /* and its info block */

static void get(unsigned int i)
{
    memcpy(ent, entry(i), 32);
    if (ent[30] & F_GEOS)
        memcpy(hdr, info(i), 256);
    RAMBANK = appBank;
}

/* names: $20-$7E as they are, $C1-$DA as A-Z, else '?' (vdisk.py's shown) */
static void shown(char *d, const unsigned char *s, unsigned char n)
{
    unsigned char i, c;
    for (i = 0; i < n; ++i) {
        c = s[i];
        d[i] = c >= 0x20 && c <= 0x7E ? c : c >= 0xC1 && c <= 0xDA ? c - 0x80 : '?';
    }
    d[n] = 0;
}

static unsigned char padlen(const unsigned char *s, unsigned char n)
{
    while (n && s[n - 1] == 0xA0)
        --n;
    return n;
}

static char dname[17];                  /* the entry's name, shown */
static char dclass[21];

static void names_of(void)
{
    unsigned char n;
    shown(dname, ent + 3, padlen(ent + 3, 16));
    dclass[0] = 0;
    if (ent[30] & F_GEOS) {
        for (n = 0; n < 20 && hdr[77 + n]; ++n)
            ;
        shown(dclass, hdr + 77, n);
    }
}

/* the base of a name on the card (vdisk.py's fat_base) */
static void fat_base(char *d, const char *s)
{
    unsigned char i, n;
    char c;
    for (i = 0; (c = s[i]) != 0; ++i)
        d[i] = strchr("/\\:*?\"<>|=,", c) ? '_' : c;
    d[i] = 0;
    if (d[0] == '$' || d[0] == '#' || d[0] == '@')
        d[0] = '_';
    n = i;
    while (n && (d[n - 1] == ' ' || d[n - 1] == '.'))
        d[--n] = 0;
    if (!n)
        strcpy(d, "_");
}

static unsigned char lower(unsigned char c)
{
    return c >= 'A' && c <= 'Z' ? c + 32 : c;
}

static unsigned char nhash(const char *s)
{
    unsigned char h = 0;
    while (*s)
        h = (h << 1 | h >> 7) ^ lower(*s++);
    return h;
}

static unsigned char sameci(const char *a, const char *b)
{
    while (*a && lower(*a) == lower(*b))
        ++a, ++b;
    return *a == 0 && *b == 0;
}

static const char *const cbmtype[] = { "DEL", "SEQ", "PRG", "USR", "REL", "CBM", "T6", "T7" };
static const char *const geostype[] = {
    "not GEOS", "BASIC", "assembly", "data", "system", "desk acc", "application", "document",
    "font", "printer", "input", "disk driver", "boot", "temporary", "auto exec", "input 128"
};

/* the name on the card for entry i (vdisk.py's unique): base ~2 ... */
static void make_outname(unsigned int i)
{
    static char base[24], cand[24], other[24];
    const char *ext = ent[30] & F_GEOS ? ".cvt" : cbmtype[ent[0] & 7];
    unsigned char k = 1, h, l;
    unsigned int j;
    fat_base(base, dname);
    base[16] = 0;
    strcpy(cand, base);
    for (;;) {
        l = strlen(cand);
        if (ent[30] & F_GEOS)
            strcpy(cand + l, ext);
        else {
            cand[l] = '.';
            strcpy(cand + l + 1, ext);
        }
        h = nhash(cand);
        for (j = 0; j < i; ++j) {
            if (hash[j] != h)
                continue;
            strcpy(other, outname(j));
            if (sameci(other, cand))
                break;
        }
        if (j == i)
            break;
        ++k;
        l = 16 - 1 - (k >= 100 ? 3 : k >= 10 ? 2 : 1);
        if (strlen(base) < l)
            l = strlen(base);
        memcpy(cand, base, l);
        cand[l++] = '~';
        utoa(k, cand + l, 10);
    }
    hash[i] = h;
    strcpy(outname(i), cand);
    RAMBANK = appBank;
}

static char kindbuf[12];

static const char *kind_of(void)
{
    if (ent[30] & F_GEOS) {
        if (ent[22] < 16)
            return geostype[ent[22]];
        strcpy(kindbuf, "type ");
        utoa(ent[22], kindbuf + 5, 10);
        return kindbuf;
    }
    return cbmtype[ent[0] & 7];
}

static char sname[24];

/* the listing's line for entry i (vdisk.py's Entry.line) */
static void entry_line(unsigned int i)
{
    get(i);
    names_of();
    utoa(ent[28] | ent[29] << 8, line, 10);
    strcat(line, "|");
    strcat(line, kind_of());
    strcat(line, ent[30] & F_GEOS ? (ent[21] == 1 ? "|V|" : "|S|") : "|-|");
    strcat(line, dname);
    strcat(line, "|");
    if (ent[30] & F_COPY) {
        strcpy(sname, outname(i));
        RAMBANK = appBank;
        strcat(line, sname);
    } else
        sname[0] = 0;
    strcat(line, "|");
    strcat(line, dclass);
}

/*---------------------------------------------------------------
  opening an image
 ---------------------------------------------------------------*/
static void close_image(void)
{
    if (img)
        FClose(img);
    img = 0;
    nents = 0;
}

static unsigned char read_bam(void)
{
    unsigned char e, t;
    unsigned char *b;
    freeblk = 0;
    if (kind == K_D81) {
        if ((e = rd(40, 0)))
            return e;
        RAMBANK = bBam;
        memcpy(BANKMEM, sec, 256);
        RAMBANK = appBank;
        shown(diskname, sec + 4, padlen(sec + 4, 16));
        for (t = 1; t <= 2; ++t) {
            if ((e = rd(40, t)))
                return e;
            RAMBANK = bBam;
            memcpy(BANKMEM + 256 * t, sec, 256);
            RAMBANK = appBank;
        }
        b = BANKMEM;
        RAMBANK = bBam;
        for (t = 1; t <= 80; ++t)
            if (t != 40)
                freeblk += b[(t <= 40 ? 256 : 512) + 0x10 + 6 * ((t - 1) % 40)];
        RAMBANK = appBank;
        return E_OK;
    }
    if ((e = rd(18, 0)))
        return e;
    shown(diskname, sec + 0x90, padlen(sec + 0x90, 16));
    for (t = 1; t <= 35; ++t)
        if (t != 18)
            freeblk += sec[4 * t];
    if (kind == K_D71)
        for (t = 36; t <= 70; ++t)
            if (t != 53)
                freeblk += sec[0xDD + t - 36];
    RAMBANK = bBam;
    memcpy(BANKMEM, sec, 256);
    RAMBANK = appBank;
    if (kind == K_D71) {
        if ((e = rd(53, 0)))
            return e;
        RAMBANK = bBam;
        memcpy(BANKMEM + 256, sec, 256);
        RAMBANK = appBank;
    }
    return E_OK;
}

static unsigned char read_dir(void)
{
    unsigned char e, t, s, k, n = 0;
    unsigned char *p;
    unsigned int i;
    if ((e = rd(kind == K_D81 ? 40 : 18, 0)))
        return e;
    t = sec[0];
    s = sec[1];
    nents = 0;
    while (t) {
        if (++n > 65)
            return E_LOOP;
        if ((e = rd(t, s)))
            return e;
        t = sec[0];
        s = sec[1];
        for (k = 0; k < 8; ++k) {
            if (sec[k * 32 + 2] == 0)
                continue;
            if (nents >= MAXE)
                return E_FULL;
            p = entry(nents);
            memcpy(p, sec + k * 32 + 2, 30);
            p[30] = 0;
            RAMBANK = appBank;
            ++nents;
        }
    }
    /* the info blocks, the names */
    for (i = 0; i < nents; ++i) {
        memcpy(ent, entry(i), 32);
        RAMBANK = appBank;
        k = ent[0] & 7;
        if (ent[19] && k >= 1 && k <= 3 && rd(ent[19], ent[20]) == E_OK) {
            ent[30] = F_GEOS | F_COPY;
            memcpy(hdr, sec, 256);
            memcpy(info(i), sec, 256);
        } else if (k >= 1 && k <= 3)
            ent[30] = F_COPY;
        entry(i)[30] = ent[30];
        RAMBANK = appBank;
        if (ent[30] & F_COPY) {
            names_of();
            make_outname(i);
        }
    }
    return E_OK;
}

static unsigned char open_image(const char *name)
{
    unsigned long size;
    unsigned char e;
    close_image();
    img = FOpen((void *)name, 'r');
    if (img < 2) {
        img = 0;
        return E_READ;
    }
    FSize(img);
    size = r0 | (unsigned long)r1 << 16;
    ipos = 0;
    cur_t = 0;
    if (size == 174848UL || size == 175531UL)
        kind = K_D64, tracks = 35;
    else if (size == 196608UL || size == 197376UL)
        kind = K_D64, tracks = 40;
    else if (size == 349696UL || size == 351062UL)
        kind = K_D71, tracks = 70;
    else if (size == 819200UL || size == 822400UL)
        kind = K_D81, tracks = 80;
    else {
        close_image();
        return E_SIZE;
    }
    geometry();
    strcpy(imgname, name);
    memset(selmap, 0, sizeof selmap);
    if ((e = read_bam()) || (e = read_dir())) {
        close_image();
        return e;
    }
    return E_OK;
}

/*---------------------------------------------------------------
  the window (Veranda Look 3 "Sunroom", DECISIONS V148): the SDK's chrome
  (vrwin.h: the title band with the image's name at card rows 2-3, the
  status bar at rows 58-59: the messages at its left, the image's kind,
  name, files and free blocks at its right), the column headings on the
  chrome (rows 4-5), the list (17 rows of 24 lines from line 48, in the
  UI font; a selected row's cards in the selection colour), a scroll bar
  (vr_scroll, cards 78-79, rows 4-57). Overlay 2, mapped for good as
  appBank (the code that maps a bank of the image's maps appBank back);
  tests/check_archive.py draws the rows the same way.
 ---------------------------------------------------------------*/
static unsigned char mode;              /* 0 none, 1 an image */
static unsigned int first;              /* the first row shown */
static char info_[64];                  /* the status bar's right: the image */

static const unsigned char docicon[64] = {
    0xBF,
    0x7F, 0xFF, 0xC0, 0x40, 0x00, 0x60, 0x40, 0x00, 0x50, 0x40, 0x00, 0x78, 0x40, 0x00, 0x08,
    0x40, 0x00, 0x08, 0x40, 0x00, 0x08, 0x40, 0x00, 0x08, 0x40, 0x00, 0x08, 0x40, 0x00, 0x08,
    0x40, 0x00, 0x08, 0x40, 0x00, 0x08, 0x40, 0x00, 0x08, 0x40, 0x00, 0x08, 0x40, 0x00, 0x08,
    0x40, 0x00, 0x08, 0x40, 0x00, 0x08, 0x40, 0x00, 0x08, 0x40, 0x00, 0x08, 0x40, 0x00, 0x08,
    0x7F, 0xFF, 0xF8
};
static unsigned char ico[64];

static const struct vrwin win = { 0, 2, 80, 58, 0, 2, 0 };
static struct vrscroll sbar = { 78, 4, 54, 1 };

/* the columns: x, width (the size's: its right end) */
#define X_NAME   40
#define W_NAME   136
#define X_KIND   184
#define W_KIND   96
#define X_FORM   288
#define W_FORM   40
#define X_SIZE   368                    /* (right aligned) */
#define X_CLASS  384
#define W_CLASS  128
#define X_FILE   520
#define W_FILE   96

/* the file list's own part of the colour map: 0 none */
static unsigned char hilite;

/* the status bar (vrwin.h): s at the left, the image at the right */
static void status(const char *s)
{
    vr_win_status(&win, s, mode ? info_ : 0);
}

#pragma code-name (push, "OVERLAY2")
static unsigned int count(void)
{
    return mode ? nents : 0;
}

static unsigned char issel(unsigned int i)
{
    return selmap[i >> 3] & (1 << (i & 7));
}

static void icon_at(const unsigned char *pic, unsigned char r)
{
    memcpy(ico, pic, 64);
    ico[0] = 0xBF;
    WBitmapUp(ico, 1, 3, TOP + r * ROWH + 1, 21);
}

/* s's width in the font now */
static unsigned int ui_w(const char *s)
{
    unsigned int w = 0;
    while (*s)
        w += GetCharWidth(*s++);
    return w;
}

/* s cut to w pixels (outside $20-$7E as '?') at x, baseline y */
static void cell(const char *s, unsigned int x, unsigned int w, unsigned int y)
{
    static char c[40];
    unsigned char n = 0, k;
    unsigned int t = 0;
    while ((k = s[n]) != 0 && n < sizeof c - 1) {
        if (k < 32 || k > 126)
            k = '?';
        if ((t += GetCharWidth(k)) > w)
            break;
        c[n++] = k;
    }
    c[n] = 0;
    WPutString(c, x, y);
}

static void draw_row(unsigned char r)
{
    unsigned int i = first + r, y0 = TOP + r * ROWH, y = y0 + 15;
    static char num[8];
    unsigned char s;
    SetPattern(0);
    WRectangle(0, y0, 623, y0 + ROWH - 1);
    s = i < count() && issel(i);
    theme_rect(0, 78, y0 >> 3, 3, s ? hilite : 0);
    if (i >= count())
        return;
    entry_line(i);
    icon_at(ent[30] & F_GEOS ? hdr + 4 : docicon, r);
    UseFont(FONT_UI);
    cell(dname, X_NAME, W_NAME, y);
    cell(kind_of(), X_KIND, W_KIND, y);
    cell(ent[30] & F_GEOS ? (ent[21] == 1 ? "VLIR" : "Seq") : "-", X_FORM, W_FORM, y);
    utoa(ent[28] | ent[29] << 8, num, 10);
    cell(num, X_SIZE - ui_w(num), 64, y);
    cell(dclass, X_CLASS, W_CLASS, y);
    cell(sname, X_FILE, W_FILE, y);
    UseSystemFont();
    if (s && !hilite)                   /* (the Classic theme: no colours) */
        WInvertRectangle(0, y0, 623, y0 + ROWH - 1);
}

static void draw_bar(void)
{
    sbar.first = first;
    sbar.shown = ROWS;
    sbar.total = count();
    vr_scroll(&sbar);
}

static void draw_list(void)
{
    unsigned char r;
    for (r = 0; r < ROWS; ++r)
        draw_row(r);
    draw_bar();
}

static const char *const heads[6] = { "Name", "Kind", "Form", "Blocks", "Class", "File" };
static const unsigned int headx[6] = { X_NAME, X_KIND, X_FORM, X_SIZE, X_CLASS, X_FILE };
static const unsigned int sepx[5] = { X_KIND - 8, X_FORM - 8, X_FORM + W_FORM, X_CLASS - 8, X_FILE - 8 };

static void draw_head(void)
{
    unsigned char i;
    unsigned int x;
    static char num[8];
    vr_win_title(&win, mode ? imgname : "Archive");
    SetPattern(0);
    WRectangle(0, 32, 623, 47);
    theme_rect(0, 78, 4, 2, CHROME);
    UseFont(FONT_UI);
    for (i = 0; i < 6; ++i) {
        x = headx[i];
        if (i == 3)
            x -= ui_w(heads[i]);
        WPutString((char *)heads[i], x, 44);
        if (i)
            WVerticalLine(0xFF, sepx[i - 1], 35, 44);
    }
    UseSystemFont();
    WHorizontalLine(0xFF, 0, 623, 47);
    if (mode) {
        strcpy(info_, kname[kind]);
        strcat(info_, "  \"");
        strcat(info_, diskname);
        strcat(info_, "\"  ");
        utoa(nents, num, 10);
        strcat(info_, num);
        strcat(info_, nents == 1 ? " file, " : " files, ");
        utoa(freeblk, num, 10);
        strcat(info_, num);
        strcat(info_, " blocks free");
    }
}

static const char none2[] = "File > Open... (Ctrl O) opens a D64, D71 or D81 image.";

static void redraw(void)
{
    draw_head();
    draw_list();
    if (!mode) {                        /* nothing open: what to do, in the middle */
        UseFont(FONT_UI);
        currentMode = SET_BOLD;
        WPutString("No disk image open", (624 - ui_w("No disk image open") - 18) >> 1, 228);
        currentMode = 0;
        WPutString(none2, (624 - ui_w(none2)) >> 1, 246);
        UseSystemFont();
    }
}

static void scroll(int by)
{
    long f = (long)first + by;
    unsigned int n = count();
    if (f > (long)n - ROWS)
        f = (long)n - ROWS;
    if (f < 0)
        f = 0;
    if ((unsigned int)f != first) {
        first = f;
        draw_list();
    }
}
#pragma code-name (pop)

/*---------------------------------------------------------------
  the Open dialog (vrchoose.h, DECISIONS V79, V82): the SDK's, compiled
  into overlay 1 (file_dlg maps it): the images by their long names
 ---------------------------------------------------------------*/
static const char atypes[] = "Disk images:D64 D71 D81";
static char pick[VRF_NAME + 1];

static unsigned char file_dlg(void)
{
    unsigned char r, b = RAMBANK;
    vr_file_types = atypes;
    RAMBANK = bDlg;
    r = vr_file(VRF_OPEN, "Open a disk image", pick);
    RAMBANK = b;
    return r;
}

#pragma code-name (push, "OVERLAY2")
static void do_open(const char *name);

static void show_none(void)
{
    mode = 0;
    first = 0;
    redraw();
    status("File > Open... opens a disk image (D64, D71, D81).");
}

/* the dialog; an image chosen is opened (its folder current: curDirName) */
static void choose(void)
{
#ifdef ARCHIVE_TEST
    archive_test_dialog();
#endif
    if (file_dlg())
        do_open(pick);
    else if (!mode)
        show_none();
}

static void log_listing(void)
{
    unsigned int i;
    static char num[8];
    strcpy(msg, "ARCHIVE IMAGE|");
    strcat(msg, kname[kind]);
    strcat(msg, "|");
    strcat(msg, diskname);
    strcat(msg, "|");
    utoa(nents, num, 10);
    strcat(msg, num);
    strcat(msg, "|");
    utoa(freeblk, num, 10);
    strcat(msg, num);
    LogText(msg);
    for (i = 0; i < nents; ++i) {
        entry_line(i);
        strcpy(msg, "ARCHIVE ");
        strcat(msg, line);
        LogText(msg);
    }
}

static void show_image(void)
{
    mode = 1;
    first = 0;
    redraw();
    status("Click files to select them (none selected: all of them).");
}

static void do_open(const char *name)
{
    unsigned char e;
    status("Reading the image ...");
#ifdef ARCHIVE_TEST
    archive_test_clock_reset();
#endif
    e = open_image(name);
    if (e) {
        Beep();
        status(emsg[e]);
        return;
    }
    log_listing();
    show_image();
#ifdef ARCHIVE_TEST
    archive_test_listed();
#endif
}
#pragma code-name (pop)

/*---------------------------------------------------------------
  extracting
 ---------------------------------------------------------------*/
static const char sig[] = "PRG formatted GEOS file V1.0";
static unsigned char out;               /* the output stream */
/* two work buffers: extracting (a block, the record table) and converting
   (the Paint document's info block, the VLIR index) */
static unsigned char work1[256], work2[256];
#define wbuf   work1
#define table  work2
#define phdr   work1
#define index_ work2

static unsigned char put(const void *p, unsigned int n)
{
    return FWrite(out, (void *)p, n) ? E_WRITE : E_OK;
}

/* a chain's data to the output; its blocks and last byte in nb, last;
   pad 1: whole 254-byte blocks; 2: nothing written (counted only) */
static unsigned int nb;
static unsigned char last;

static unsigned char copy_chain(unsigned char t, unsigned char s, unsigned char pad)
{
    unsigned char e, n;
    nb = 0;
    for (;;) {
        if (++nb > total)
            return E_LOOP;
        if ((e = rd(t, s)))
            return e;
        t = sec[0];
        s = sec[1];
        if (t == 0) {
            if (s < 1)
                return E_LINK;
            last = s;
            n = s - 1;
            if (pad == 2)
                return E_OK;
            if (pad) {
                memset(sec + 2 + n, 0, 254 - n);
                n = 254;
                cur_t = 0;              /* (sec changed) */
            }
            return n ? put(sec + 2, n) : E_OK;
        }
        if (pad != 2 && (e = put(sec + 2, 254)))
            return e;
    }
}


static unsigned char extract_one(unsigned int i)
{
    unsigned char e, k, t, s;
    get(i);
    strcpy(sname, outname(i));
    RAMBANK = appBank;
    out = FOpen(sname, 'w');
    if (out < 2)
        return E_WRITE;
    if (!(ent[30] & F_GEOS)) {
        e = copy_chain(ent[1], ent[2], 0);
        FClose(out);
        goto done;
    }
    memcpy(wbuf, ent, 30);
    wbuf[1] = wbuf[2] = wbuf[19] = wbuf[20] = 0;
    memset(wbuf + 30, 0, 224);
    memcpy(wbuf + 30, sig, sizeof sig - 1);
    if ((e = put(wbuf, 254)) || (e = put(hdr + 2, 254)))
        goto close;
    if (ent[21] != 1) {
        e = copy_chain(ent[1], ent[2], 0);
        goto close;
    }
    /* VLIR: the record table (each record's chain walked to count its
       blocks), then the records, in one pass. (Writing the table last
       into a stream opened again with 'm' came out wrong on the SD card:
       R49's MCIOUT, DECISIONS V55; the kernel now writes 'm' streams
       byte by byte, so that would work too, but one pass is simpler.) */
    if ((e = rd(ent[1], ent[2])))
        goto close;
    memcpy(wbuf, sec, 256);             /* the index */
    memset(table, 0, 254);
    for (k = 0; k < 127; ++k) {
        t = wbuf[2 + 2 * k];
        s = wbuf[3 + 2 * k];
        if (t == 0) {
            table[2 * k + 1] = s;
            continue;
        }
        if ((e = copy_chain(t, s, 2)))
            goto close;
        table[2 * k] = nb;
        table[2 * k + 1] = last;
    }
    if ((e = put(table, 254)))
        goto close;
    for (k = 0; k < 127; ++k)
        if ((t = wbuf[2 + 2 * k]) != 0 && (e = copy_chain(t, wbuf[3 + 2 * k], 1)))
            break;
close:
    FClose(out);
done:
    if (e)
        FDelete(sname);
    return e;
}

static unsigned char picked(unsigned int i)
{
    unsigned int j;
    for (j = 0; j < (MAXE + 7) / 8; ++j)
        if (selmap[j])
            return issel(i);
    return 1;
}

static void extract(void)
{
    unsigned int i, n = 0, bad = 0;
    unsigned char e;
    static char num[8];
    if (!mode)
        return;
    for (i = 0; i < nents; ++i) {
        get(i);
        if (!(ent[30] & F_COPY) || !picked(i))
            continue;
        e = extract_one(i);
        strcpy(msg, e ? "ARCHIVE FAILED " : "ARCHIVE GOT ");
        strcat(msg, sname);
        LogText(msg);
        if (e) {
            ++bad;
            status(emsg[e]);
        } else
            ++n;
    }
    utoa(n, num, 10);
    strcpy(line, "Extracted ");
    strcat(line, num);
    strcat(line, n == 1 ? " file" : " files");
    if (bad) {
        strcat(line, ", ");
        utoa(bad, num, 10);
        strcat(line, num);
        strcat(line, " failed");
        Beep();
    }
    strcat(line, ".");
    status(line);
    strcpy(msg, "ARCHIVE EXTRACTED ");
    strcat(msg, num);
    LogText(msg);
}

/*---------------------------------------------------------------
  pictures: geoPaint, Photo Scraps, photo albums to Paint documents
 ---------------------------------------------------------------*/
#define P_BYTES  74
#define P_ROWS   16
#define P_BANDS  29
#define BANDSZ   (P_BYTES * P_ROWS)
#define MRECSZ   (29 * 37)
#define REC_LEN  1448

static unsigned char band[BANDSZ];
static unsigned char packed[1600];             /* also a geoPaint record, packed */
/* the colour map (58 rows of 37 bytes) is at $A000 in bank bMap */
#define raw packed
static unsigned char rec[REC_LEN];
static unsigned int rawlen;
static char docname[17];
static unsigned char head[9] = { 'V', 'P', 'N', 'T', 3, P_BYTES, P_ROWS, P_BANDS, 1 };
static const char pdclass[] = "Paint Image V1.0";
static const char ppclass[] = "Paint       V1.0";
static const char pdesc[] = "A picture from Paint.";

static void make_phdr(void)
{
    unsigned char i;
    memset(phdr, 0, sizeof phdr);
    phdr[0] = (unsigned int)docname & 255;
    phdr[1] = (unsigned int)docname >> 8;
    phdr[2] = 3;
    phdr[3] = 21;
    phdr[4] = 0xBF;
    for (i = 0; i < 21; ++i) {
        unsigned char *p = phdr + 5 + i * 3;
        if (i == 0 || i == 20) {
            p[0] = 0x7F; p[1] = 0xFF; p[2] = 0xFE;
        } else {
            p[0] = 0x40; p[1] = 0; p[2] = 0x02;
        }
    }
    for (i = 4; i < 17; ++i)
        phdr[5 + i * 3 + (i + 2) / 8] |= 0x80 >> ((i + 2) & 7);
    phdr[68] = 0x83;
    phdr[69] = APPL_DATA;
    phdr[70] = 1;
    memcpy(phdr + O_GHFNAME, pdclass, sizeof pdclass);
    memcpy(phdr + O_GH_AUTHOR, "Veranda", 8);
    memcpy(phdr + O_GHP_FNAME, ppclass, sizeof ppclass);
    memcpy(phdr + O_GHINFO_TXT, pdesc, sizeof pdesc);
}

/* PackBits (as Paint's pack): band -> packed; the length */
static unsigned int pack(void)
{
    static unsigned char *p, *q, *o, *lim;
    static unsigned char c, n;
    p = band;
    o = packed;
    while (p < band + BANDSZ) {
        c = *p;
        lim = p + 128 < band + BANDSZ ? p + 128 : band + BANDSZ;
        for (q = p + 1; q < lim && *q == c; ++q)
            ;
        n = q - p;
        if (n >= 3) {                           /* a run */
            *o++ = 257 - n;
            *o++ = c;
            p = q;
            continue;
        }
        for (q = p; q < lim; ++q)               /* bytes, up to a run of three */
            if (q + 2 < band + BANDSZ && q[0] == q[1] && q[0] == q[2])
                break;
        n = q - p;
        *o++ = n - 1;
        memcpy(o, p, n);
        o += n;
        p = q;
    }
    return o - packed;
}

/* a new Paint document docname: record 0 (the head, the ink written at
   the end), the bands follow */
static void drop_doc(void)
{
    static char n[24];
    strcpy(n, docname);
    strcat(n, ".cvt");
    FDelete(n);
}

static unsigned char doc_open(void)
{
    unsigned char e;
    make_phdr();
    if ((e = SaveFile(phdr, 0)))
        return e;
    if ((e = OpenRecordFile(docname)))
        return e;
    if ((e = AppendRecord()) || (e = WriteRecord(head, 9))) {
        CloseRecordFile();
        return e;
    }
    return 0;
}

static unsigned char doc_band(void)
{
    unsigned char e;
    if ((e = AppendRecord()) || (e = WriteRecord(packed, pack())))
        return e;
    return 0;
}

static unsigned char doc_close(unsigned char ink)
{
    unsigned char e, h;
    for (h = 0, e = 0; !e && h < 2; ++h)
        if (!(e = AppendRecord())) {
            RAMBANK = bMap;             /* (WriteRecord: $A000 in the caller's bank) */
            e = WriteRecord(BANKMEM + h * MRECSZ, MRECSZ);
            RAMBANK = appBank;
        }
    head[8] = ink;
    if (!e && !(e = PointRecord(0)))
        e = WriteRecord(head, 9);
    h = CloseRecordFile();
    if (!e)
        e = h;
    if (!e) {
        strcpy(msg, "ARCHIVE PAINT ");
        strcat(msg, docname);
        LogText(msg);
    }
    return e;
}

static void clear_map(void)
{
    RAMBANK = bMap;
    memset(BANKMEM, 0, 2 * MRECSZ);
    RAMBANK = appBank;
}

static void set_card(unsigned char cx, unsigned char cy, unsigned char c)
{
    unsigned char *q = BANKMEM + cy * 37 + (cx >> 1);
    RAMBANK = bMap;
    *q = cx & 1 ? (*q & 0xF0) | c : (*q & 0x0F) | c << 4;
    RAMBANK = appBank;
}

/* a chain into raw (at most sizeof raw) */
static unsigned char read_raw(unsigned char t, unsigned char s)
{
    unsigned char e, n;
    unsigned int k = 0;
    rawlen = 0;
    for (;;) {
        if (++k > total)
            return E_LOOP;
        if ((e = rd(t, s)))
            return e;
        t = sec[0];
        s = sec[1];
        n = t ? 254 : s - 1;
        if (!t && s < 1)
            return E_LINK;
        if (rawlen + n > sizeof raw)
            return E_LONG;
        memcpy(raw + rawlen, sec + 2, n);
        rawlen += n;
        if (!t)
            return E_OK;
    }
}

/* geoPaint's compaction (vdisk.py's geopaint_unpack): raw -> rec */
static unsigned int gi, go, gn, gk;

static void gp_unpack(void)
{
    static unsigned char c;
    gi = 0;
    go = 0;
    while (gi < rawlen && go < REC_LEN) {
        c = raw[gi++];
        if (c < 64) {                           /* c bytes follow */
            gn = rawlen - gi;
            if (gn > c)
                gn = c;
            if (gn > REC_LEN - go)
                gn = REC_LEN - go;
            memcpy(rec + go, raw + gi, gn);
            go += gn;
            gi += c;
        } else if (c < 128) {                   /* a card, c - 64 times */
            gn = gi < rawlen ? rawlen - gi : 0;
            if (gn > 8)
                gn = 8;
            for (c -= 64; c && gn && go < REC_LEN; --c) {
                gk = REC_LEN - go;
                if (gk > gn)
                    gk = gn;
                memcpy(rec + go, raw + gi, gk);
                go += gk;
            }
            gi += 8;
        } else {                                /* a byte, c - 128 times */
            gn = c - 128;
            if (gn > REC_LEN - go)
                gn = REC_LEN - go;
            memset(rec + go, gi < rawlen ? raw[gi] : 0, gn);
            go += gn;
            ++gi;
        }
    }
    if (go < REC_LEN)
        memset(rec + go, 0, REC_LEN - go);
}

static unsigned char paper(unsigned char c)
{
    return c == 1 ? 0 : c == 0 ? 1 : c;
}

/* rec (two card rows) into band, the cards' paper into the map's rows
   2b and 2b + 1, the inks of cards with ink counted */
static unsigned int counts[16];
static unsigned char mrow[74];

static void gp_cards(unsigned char b)
{
    static unsigned char half, cx, any, col;
    static unsigned char *card, *dst, *q;
    for (half = 0; half < 2; ++half) {
        card = rec + half * 640;
        dst = band + half * 8 * P_BYTES;
        q = rec + 1288 + half * 80;
        for (cx = 0; cx < P_BYTES; ++cx) {
            any = dst[0] = card[0];             /* a card's 8 rows down the band */
            any |= dst[P_BYTES] = card[1];
            any |= dst[2 * P_BYTES] = card[2];
            any |= dst[3 * P_BYTES] = card[3];
            any |= dst[4 * P_BYTES] = card[4];
            any |= dst[5 * P_BYTES] = card[5];
            any |= dst[6 * P_BYTES] = card[6];
            any |= dst[7 * P_BYTES] = card[7];
            col = q[cx];
            mrow[cx] = paper(col & 15);
            if (any)
                ++counts[col >> 4];
            card += 8;
            ++dst;
        }
        q = BANKMEM + (b * 2 + half) * 37;
        RAMBANK = bMap;
        for (cx = 0; cx < 37; ++cx)
            q[cx] = mrow[2 * cx] << 4 | mrow[2 * cx + 1];
        RAMBANK = appBank;
    }
}

static unsigned char nrecs;             /* records before the index's 0/0 */

static void count_recs(void)
{
    for (nrecs = 0; nrecs < 127; ++nrecs)
        if (index_[2 + 2 * nrecs] == 0 && index_[3 + 2 * nrecs] == 0)
            break;
}

static unsigned char present(unsigned char r)
{
    return r < nrecs && index_[2 + 2 * r];
}

static unsigned char part_name(const char *base, unsigned char n)
{
    unsigned char l = strlen(base), d = n >= 100 ? 3 : n >= 10 ? 2 : 1;
    if (l > 16 - 1 - d)
        l = 16 - 1 - d;
    memcpy(docname, base, l);
    docname[l] = ' ';
    utoa(n, docname + l + 1, 10);
    return 0;
}

static char pbase[24];

static unsigned char geopaint(void)
{
    unsigned char e, p, b, r, best, k;
    for (p = 0; p < 2; ++p) {
        if (p == 1) {
            for (r = 29; r < 45 && !present(r); ++r)
                ;
            if (r == 45)
                break;
        }
        part_name(pbase, p + 1);
        clear_map();
        memset(counts, 0, sizeof counts);
        if ((e = doc_open()))
            return e;
        for (b = 0; b < P_BANDS; ++b) {
            r = 29 * p + b;
            if (r >= 45 || !present(r)) {
                memset(band, 0, BANDSZ);
            } else {
                if ((e = read_raw(index_[2 + 2 * r], index_[3 + 2 * r]))) {
                    CloseRecordFile();
                    drop_doc();
                    return e;
                }
                gp_unpack();
                gp_cards(b);
            }
            if ((e = doc_band())) {
                CloseRecordFile();
                drop_doc();
                return e;
            }
        }
        best = 0;
        for (k = 1; k < 16; ++k)
            if (counts[k] > counts[best])
                best = k;
        if ((e = doc_close(counts[best] ? (best < 2 ? 1 : best) : 1)))
            return e;
    }
    return 0;
}

/* a file's data (a chain) into the data banks; its length */
static unsigned long dlen;

static unsigned char read_data(unsigned char t, unsigned char s)
{
    unsigned char e, n, m;
    unsigned int k = 0;
    unsigned char *src;
    dlen = 0;
    for (;;) {
        if (++k > total)
            return E_LOOP;
        if ((e = rd(t, s)))
            return e;
        t = sec[0];
        s = sec[1];
        if (!t && s < 1)
            return E_LINK;
        n = t ? 254 : s - 1;
        if (dlen + n > (unsigned long)NB_DATA * 8192)
            return E_LONG;
        src = sec + 2;
        while (n) {
            m = 8192 - (unsigned int)(dlen & 8191) < n ? 8192 - (unsigned int)(dlen & 8191) : n;
            RAMBANK = bData + (unsigned char)(dlen >> 13);
            memcpy(BANKMEM + (unsigned int)(dlen & 8191), src, m);
            dlen += m;
            src += m;
            n -= m;
        }
        RAMBANK = appBank;
        if (!t)
            return E_OK;
    }
}

/* the compacted bitmap (BitmapUp's), a byte at a time from the banks */
static unsigned long sp, pstart, pend;
static unsigned char prep, inpat, left, lit, val, bad;

static unsigned char dbyte(void)
{
    unsigned char b;
    if (sp >= dlen) {
        bad = 1;
        return 0;
    }
    RAMBANK = bData + (unsigned char)(sp >> 13);
    b = BANKMEM[(unsigned int)(sp & 8191)];
    ++sp;
    if (inpat && sp == pend) {
        if (--prep)
            sp = pstart;
        else
            inpat = 0;
    }
    return b;
}

static unsigned char bm_next(void)
{
    unsigned char c, plen;
    while (!left && !bad) {
        c = dbyte();
        if (!inpat && c >= 0xDC) {
            plen = c - 0xDC;
            prep = dbyte();
            if (!prep || !plen) {
                sp += plen;
                continue;
            }
            pstart = sp;
            pend = sp + plen;
            inpat = 1;
            continue;
        }
        if (c < 0x80) {
            left = c;
            lit = 0;
            val = dbyte();
        } else {
            left = c - 0x80;
            lit = 1;
        }
    }
    if (bad)
        return 0;
    --left;
    return lit ? dbyte() : val;
}

/* a Photo Scrap in the data banks from byte at as a Paint document */
static unsigned char scrap(unsigned long at)
{
    unsigned char e, w, b, r, x, v;
    unsigned int h, y;
    if (dlen < at + 3)
        return E_SHORT;
    sp = at;
    bad = inpat = left = 0;
    w = dbyte();
    h = dbyte();
    h |= dbyte() << 8;
    clear_map();
    if ((e = doc_open()))
        return e;
    y = 0;
    for (b = 0; b < P_BANDS; ++b) {
        memset(band, 0, BANDSZ);
        for (r = 0; r < P_ROWS; ++r, ++y)
            for (x = 0; y < h && x < w; ++x) {
                v = bm_next();
                if (x < P_BYTES)
                    band[r * P_BYTES + x] = v;
            }
        if (bad || (e = doc_band())) {
            RAMBANK = appBank;
            CloseRecordFile();
            drop_doc();
            return bad ? E_SHORT : e;
        }
    }
    for (; y < h && !bad; ++y)              /* the rest, read and dropped */
        for (x = 0; x < w; ++x)
            bm_next();
    RAMBANK = appBank;
    if (bad) {
        CloseRecordFile();
        drop_doc();
        return E_SHORT;
    }
    return doc_close(1);
}

static unsigned char ciprefix(const char *s, const char *p)
{
    while (*p)
        if (lower(*s++) != *p++)
            return 0;
    return 1;
}

static unsigned char convert_one(unsigned int i)
{
    unsigned char e, r;
    get(i);
    names_of();
    fat_base(pbase, dname);
    if (!(ent[30] & F_GEOS))
        return E_KIND;
    if (ent[21] == 1) {
        if ((e = rd(ent[1], ent[2])))
            return e;
        memcpy(index_, sec, 256);
        count_recs();
        if (ciprefix(dclass, "paint image")) {
            if (present(0)) {                   /* not Veranda's own */
                if ((e = rd(index_[2], index_[3])))
                    return e;
                if ((sec[0] || sec[1] >= 5) && !memcmp(sec + 2, "VPNT", 4))
                    return E_KIND;
            }
            return geopaint();
        }
        if (ciprefix(dclass, "photo album")) {
            for (r = 0; r < nrecs; ++r) {
                if (!present(r))
                    continue;
                if ((e = read_data(index_[2 + 2 * r], index_[3 + 2 * r])))
                    return e;
                part_name(pbase, r + 1);
                e = scrap(0);
                if (e && e != E_SHORT)
                    return e;
            }
            return 0;
        }
        return E_KIND;
    }
    if (ciprefix(dclass, "photo scrap")) {
        if ((e = read_data(ent[1], ent[2])))
            return e;
        part_name(pbase, 1);
        return scrap(0);
    }
    return E_KIND;
}

static unsigned char convertible(void)
{
    if (!(ent[30] & F_GEOS))
        return 0;
    names_of();
    if (ent[21] == 1)
        return ciprefix(dclass, "paint image") || ciprefix(dclass, "photo album");
    return ciprefix(dclass, "photo scrap");
}

static void to_paint(void)
{
    unsigned int i, n = 0;
    unsigned char e;
    static char num[8];
    if (!mode)
        return;
    for (i = 0; i < nents; ++i) {
        get(i);
        if (!picked(i) || !convertible())
            continue;
#ifdef ARCHIVE_TEST
        archive_test_clock_reset();
#endif
        e = convert_one(i);
#ifdef ARCHIVE_TEST
        strcpy(msg, "convert ");
        strcat(msg, dname);
        archive_test_clock_log(msg);
#endif
        if (e && e != E_KIND) {
            strcpy(msg, "ARCHIVE NOT CONVERTED ");
            strcat(msg, dname);
            LogText(msg);
            status(emsg[e]);
            Beep();
            return;
        }
        if (!e)
            ++n;
    }
    utoa(n, num, 10);
    strcpy(line, "Converted ");
    strcat(line, num);
    strcat(line, n == 1 ? " picture to Paint." : " pictures to Paint.");
    status(line);
    strcpy(msg, "ARCHIVE CONVERTED ");
    strcat(msg, num);
    LogText(msg);
}

/*---------------------------------------------------------------
  the menus, the mouse, the keys
 ---------------------------------------------------------------*/
struct item { const char *text; unsigned char type; void *p; };
struct menu2 { unsigned char top, bottom; unsigned int left, right; unsigned char flags; struct item i[2]; };
struct menu4 { unsigned char top, bottom; unsigned int left, right; unsigned char flags; struct item i[4]; };

static void m_open(void), m_extract(void), m_paint(void), m_all(void), m_quit(void), m_about(void);

/* the menus in the Veranda look (DECISIONS V74, V79): the first is
   Archive's own. Look 3 "Sunroom" (V148): an item starting with $1F has
   a dotted line above it (a group starts), its key after a tab is drawn
   at the list's right (key()); the lists' widths from the texts */
static struct menu2 march = { 14, 14 + 2 * 14, 0, 0, VERTICAL | 2, {
    { "About Archive", MENU_ACTION, m_about }, { "\x1f" "Quit\tCtrl Q", MENU_ACTION, m_quit } } };
static struct menu4 mfile = { 14, 14 + 4 * 14, 0, 0, VERTICAL | 4, {
    { "Open...\tCtrl O", MENU_ACTION, m_open }, { "\x1f" "Select all\tCtrl A", MENU_ACTION, m_all },
    { "\x1f" "Extract\tCtrl E", MENU_ACTION, m_extract }, { "To Paint", MENU_ACTION, m_paint } } };
static struct menu2 mbar = { 0, 14, 0, 136, HORIZONTAL | UN_CONSTRAINED | 2, {
    { "Archive", SUB_MENU, &march }, { "File", SUB_MENU, &mfile } } };

#pragma code-name (push, "OVERLAY2")
/* a list's width: its widest item (a key 24 pixels after its text) + 16 */
static unsigned int menu_w(const struct item *it, unsigned char n)
{
    unsigned int w, t, m = 0;
    const char *s;
    UseFont(FONT_UI);
    while (n--) {
        s = (it++)->text;
        w = t = 0;
        if (*s == 0x1F)
            ++s;
        for (; *s; ++s)
            if (*s == '\t') {
                t = w + 24;
                w = 0;
            } else
                w += GetCharWidth(*s);
        if (t + w > m)
            m = t + w;
    }
    UseSystemFont();
    return m + 16;
}

static void m_about(void)
{
    GotoFirstMenu();
    status("Archive 1.0: GEOS files from D64, D71 and D81 disk images. MIT licence");
}

static void m_open(void)
{
    GotoFirstMenu();
    choose();
}

static void m_all(void)
{
    unsigned int i;
    GotoFirstMenu();
    if (!mode)
        return;
    for (i = 0; i < nents; ++i)
        selmap[i >> 3] |= 1 << (i & 7);
    draw_list();
}

static void m_extract(void)
{
    GotoFirstMenu();
    extract();
}

static void m_paint(void)
{
    GotoFirstMenu();
    to_paint();
}

static void m_quit(void)
{
    GotoFirstMenu();
    close_image();
    EnterDeskTop();
}

/* a click: a row selected or not; the scroll bar (its arrows a row, its
   track a page) */
static void press(void)
{
    unsigned int x = mouseXPos, y = mouseYPosW, i;
    unsigned char r;
    if (mouseData & 0x80)
        return;
    switch (vr_scroll_hit(&sbar, x, y)) {
    case VS_BACK: scroll(-1); return;
    case VS_FWD: scroll(1); return;
    case VS_PGBACK: scroll(-ROWS); return;
    case VS_PGFWD: scroll(ROWS); return;
    }
    if (y < TOP || y >= TOP + ROWS * ROWH || x >= 624)
        return;
    r = (y - TOP) / ROWH;
    i = first + r;
    if (i >= count())
        return;
    selmap[i >> 3] ^= 1 << (i & 7);
    draw_row(r);
}

/* the keys: the arrows a row, PgUp and PgDn a page; Ctrl + O, A, E, Q */
static void key(void)
{
    unsigned char k = keyData;
    if (keyDataMods & 2) {
        switch (k & 0x1F) {
        case 'O' & 0x1F: m_open(); break;
        case 'A' & 0x1F: m_all(); break;
        case 'E' & 0x1F: m_extract(); break;
        case 'Q' & 0x1F: m_quit(); break;
        }
        return;
    }
    if (k == KEY_DOWN)
        scroll(1);
    else if (k == KEY_UP)
        scroll(-1);
    else if (k == KEY_PGDN)
        scroll(ROWS);
    else if (k == KEY_PGUP)
        scroll(-ROWS);
}

/* the window, the menus (overlay 2 is mapped: main) */
static void start(void)
{
    dispBufferOn = ST_WR_FORE | ST_WR_BACK;
    SetPattern(0);
    WRectangle(0, 0, 639, 479);
    theme_load();
    theme_palette();                    /* (V148: Look 2's palette, light or dark) */
    hilite = theme_none() ? 0 : theme.hilite ? theme.hilite : SELECT;
    vr_win(&win, "Archive");
    march.right = menu_w(march.i, 2);
    mfile.right = menu_w(mfile.i, 4);
    theme_menus();                      /* the menu bar (V74, V79) */
    DoMenu((void *)&mbar, 0);
    otherPressVec = VR_FN(press);
    keyVector = VR_FN(key);
    redraw();                           /* (the empty window, behind the first Open box) */
}
#pragma code-name (pop)

#ifdef ARCHIVE_TEST
void archive_test_start(void);
static unsigned char test_step;

/* the test build: after the chooser's double click, the sequence */
void archive_test_end(void);

static void test_open(const char *dir, const char *name)
{
    ChDir("/");
    ChDir(dir);
    strcpy((char *)curDirName, "/");
    strcat((char *)curDirName, dir);
    do_open(name);
}

void archive_test_listed(void)
{
    unsigned char s = test_step++;
    archive_test_clock_log("list");
#ifdef ARCHIVE_DOC
    strcpy(msg, "ARCHIVE DOC ");                /* the shell's document */
    strcat(msg, imgname);
    strcat(msg, " IN ");
    strcat(msg, (char *)curDirName);
    LogText(msg);
    archive_test_end();
#endif
    if (s == 0) {
#if ARCHIVE_STOP == 1
        archive_test_end();
#endif
        archive_test_clock_reset();
        extract();
        archive_test_clock_log("extract all");
        m_all();
        to_paint();
        test_open("D71", "Side.d71");
    } else if (s == 1) {
        archive_test_clock_reset();
        extract();
        archive_test_clock_log("extract all");
        test_open("D81", "Big.d81");
    } else if (s == 2) {
        archive_test_clock_reset();
        extract();
        archive_test_clock_log("extract all");
        to_paint();
        memset(selmap, 0, sizeof selmap);
        selmap[2] = 0x14;               /* Note 07 and Note 09 picked */
        scroll(ROWS);
        archive_test_end();
    }
}
#endif

int main(void)
{
    unsigned char opts = r0L;
    unsigned char b;
    LoadOverlay(1, 0);                  /* (overlay 1: the Open dialog, mapped by file_dlg) */
    bDlg = r1L;
    LoadOverlay(2, 0);                  /* (overlay 2: the window, mapped for good, as appBank: V148) */
    appBank = r1L;
    RAMBANK = appBank;
    b = BankAlloc(NBANKS);
    start();
    LogText("ARCHIVE RUNNING");
    if (!b) {
        status("Not enough memory (RAM banks).");
        return 0;
    }
    bBam = b;
    bDir = b + 1;
    bInfo = bDir + NB_DIR;
    bNames = bInfo + NB_INFO;
    bMap = bNames + 1;
    bData = bMap + 1;
    vr_home(opts);                      /* images and extracts: /DOCUMENTS first (V71) */
    if (curDirName[0] != '/') {
        strcpy((char *)curDirName, "/");
        ChDir("/");
    } else
        ChDir((char *)curDirName);
#ifdef ARCHIVE_TEST
    archive_test_start();
#endif
    if (opts & ST_LD_DATA) {                    /* the shell's document */
        strcpy(imgname, (char *)dataLongName);         /* (its whole name: V82) */
        strcpy(msg, imgname);
        do_open(msg);
        if (img)
            return 0;
        show_none();
        strcpy(line, "Cannot open ");
        strcat(line, imgname);
        status(line);
        return 0;
    }
    choose();
    return 0;
}
