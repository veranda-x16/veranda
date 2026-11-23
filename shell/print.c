/* Veranda shell: the printer (overlay 5; DECISIONS V70).

   A picture dropped on the printer's icon (or file/print) is printed to
   a PDF beside it (the kernel's print service, V38: PrintOpen, a row at
   a time with PrintBand, PrintClose): "Name.bmp" or the Paint picture
   "Name" to "Name.pdf", A4 at 150 dots an inch, twice the size when it
   fits across (a 640-pixel picture once), centred, a margin at the top.
   A BMP of 1, 4 or 8 bits a pixel, uncompressed, up to 640 x 480: a
   pixel is ink when its palette colour is dark. A Paint picture (a GEOS
   record file of class "Paint Image": 29 bands of 16 rows of 74 bytes,
   PackBits, apps/paint) prints its 592 x 464 pixels. Other documents
   need their application's printing (later): the shell says so.

   The buffers are this overlay's own, in its RAM bank: FRead, ReadRecord
   and PrintBand take a buffer at $A000 in the caller's bank (V47). */
#include <veranda.h>
#include <string.h>
#include "shell.h"
#pragma code-name ("OVERLAY5")
#pragma bss-name ("OVL5BSS")

#define MAXW    640
#define BANDH   16
#define CBYTES  74
#define BANDSZ  (CBYTES * BANDH)

static unsigned char hdr[54];
static unsigned char row[MAXW];         /* a BMP row as read */
static unsigned char src[MAXW / 8];     /* a picture row: 1 = ink */
static unsigned char out[320];          /* a page row */
static unsigned char ink[256];          /* the palette: 1 = dark */
static unsigned char packed[BANDSZ + 64];
static unsigned char band[BANDSZ];
#pragma bss-name ("BSS")

static unsigned int pw, prb, scale, xoff;
static unsigned int W, H;

static unsigned long le32(const unsigned char *p)
{
    return p[0] | (unsigned int)p[1] << 8 | (unsigned long)p[2] << 16 | (unsigned long)p[3] << 24;
}

/* the page set up for a picture W x H; 0 if it failed */
static unsigned char page(void)
{
    unsigned char e = PrintOpen(str, 0);
    unsigned int i;
    if (e) {
        shell_err("Cannot print:", e);
        return 0;
    }
    prb = r1;
    pw = r3;
    scale = W * 2 + 74 <= pw ? 2 : 1;
    xoff = (prb - (W * scale + 7) / 8) / 2;
    memset(out, 0, sizeof out);
    for (i = 0; i < 75; ++i)
        PrintBand(out, 1);
    return 1;
}

/* src (W pixels) sent, scale times */
static void send(void)
{
    unsigned int x, o;
    unsigned char b, m, k;
    memset(out, 0, sizeof out);
    if (scale == 1)
        memcpy(out + xoff, src, (W + 7) / 8);
    else
        for (x = 0, o = xoff * 8; x < W; ++x, o += 2) {
            b = src[x >> 3];
            m = 0x80 >> (x & 7);
            if (b & m) {
                out[o >> 3] |= 0xC0 >> (o & 7);
            }
        }
    for (k = 0; k < scale; ++k)
        PrintBand(out, 1);
}

static unsigned char bmp(const char *name)
{
    unsigned char h, bpp, v, sh;
    unsigned int stride, x, y, i, ncol;
    unsigned long off, pos;
    signed long hs;
    unsigned char *pal = packed;
    h = FOpen((void *)name, 'r');
    if (h < 2)
        return 1;
    if (FRead(h, hdr, 54) != 54 || hdr[0] != 'B' || hdr[1] != 'M' || le32(hdr + 30)) {
        FClose(h);
        return 2;
    }
    off = le32(hdr + 10);
    W = le32(hdr + 18);
    hs = (signed long)le32(hdr + 22);
    H = hs < 0 ? -hs : hs;
    bpp = hdr[28];
    if (W > MAXW || H > 480 || !W || !H || (bpp != 1 && bpp != 4 && bpp != 8)) {
        FClose(h);
        return 2;
    }
    ncol = le32(hdr + 46);
    if (!ncol || ncol > (1u << bpp))
        ncol = 1u << bpp;
    memset(ink, 0, sizeof ink);
    FSeek(h, 14 + (unsigned int)le32(hdr + 14), 0);
    FRead(h, pal, ncol * 4);
    for (i = 0; i < ncol; ++i)
        ink[i] = (unsigned int)pal[i * 4 + 2] * 3 + pal[i * 4 + 1] * 6 + pal[i * 4] < 1280;
    stride = ((W * bpp + 31) / 32) * 4;
    if (!page()) {
        FClose(h);
        return 0;
    }
    for (y = 0; y < H; ++y) {
        pos = off + (unsigned long)(hs < 0 ? y : H - 1 - y) * stride;
        FSeek(h, (unsigned int)pos, (unsigned int)(pos >> 16));
        FRead(h, row, stride);
        memset(src, 0, sizeof src);
        for (x = 0; x < W; ++x) {
            if (bpp == 1)
                v = row[x >> 3] >> (7 - (x & 7)) & 1;
            else if (bpp == 4) {
                sh = x & 1 ? 0 : 4;
                v = row[x >> 1] >> sh & 15;
            } else
                v = row[x];
            if (ink[v])
                src[x >> 3] |= 0x80 >> (x & 7);
        }
        send();
    }
    FClose(h);
    PrintClose();
    return 0;
}

static unsigned char unpack(unsigned int n)
{
    unsigned int i = 0, o = 0, k;
    unsigned char c;
    while (i < n) {
        c = packed[i++];
        if (c < 128) {
            k = c + 1;
            if (o + k > BANDSZ || i + k > n)
                return 0;
            memcpy(band + o, packed + i, k);
            i += k;
        } else if (c > 128) {
            k = 257 - c;
            if (o + k > BANDSZ || i >= n)
                return 0;
            memset(band + o, packed[i++], k);
        } else
            continue;
        o += k;
    }
    return o == BANDSZ;
}

/* a Paint picture (tmp: its GEOS name) */
static unsigned char paint(void)
{
    unsigned char b, r, e;
    if (OpenRecordFile(tmp))
        return 1;
    W = CBYTES * 8;
    H = 29 * BANDH;
    if (!page()) {
        CloseRecordFile();
        return 0;
    }
    for (b = 0; b < 29; ++b) {
        memset(band, 0, BANDSZ);
        if (!(e = PointRecord(b + 1)) && !(e = ReadRecord(packed, sizeof packed)))
            unpack(r7 - (unsigned int)packed);
        for (r = 0; r < BANDH; ++r) {
            memcpy(src, band + r * CBYTES, CBYTES);
            send();
        }
    }
    CloseRecordFile();
    PrintClose();
    return 0;
}

void print_drop(const char *nm)
{
    static char name[NAMELEN + 1];
    unsigned char l, e, isBmp, isPaint = 0;
    char *d;
    strcpy(name, nm);
    l = strlen(name);
    isBmp = l > 4 && name[l - 4] == '.' && (name[l - 3] | 32) == 'b' && (name[l - 2] | 32) == 'm'
        && (name[l - 1] | 32) == 'p';
    if (!isBmp && shell_is_cvt(name)) {
        strcpy(tmp, name);
        tmp[l - 4] = 0;
        isPaint = FindFile(tmp) == 0 && GetFHdrInfo((void *)dirEntryBuf) == 0
            && !memcmp((void *)(fileHeader + 77), "Paint Image", 11);
    }
    if (!isBmp && !isPaint) {
        shell_say("Pictures print here (BMP, Paint); documents print from their application.");
        return;
    }
    strcpy(str, name);
    d = strrchr(str, '.');
    strcpy(d, ".pdf");
    play_busy = 1;
    e = isBmp ? bmp(name) : paint();
    play_busy = 0;
    if (e) {
        shell_warn(e == 1 ? "The picture cannot be read." : "Only BMPs of 1, 4 or 8 bits, up to 640 x 480.");
        return;
    }
    strcpy(msg, "SHELL PRINTED ");
    strcat(msg, name);
    strcat(msg, " AS ");
    strcat(msg, str);
    LogText(msg);
    shell_reload();
}
