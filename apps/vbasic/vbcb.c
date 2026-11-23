/* VeraBASIC Run: the C overlays' bank B (record 11; vbc.cfg, DECISIONS
   V90): CLIPBOARD$, CLIPBOARD, CLIPBOARD PICTURE (the SDK's scrap
   library, V54) and TILE (the SDK's vr_tile, V77). vbcb.s holds the
   entries; the arguments and results are in main RAM's inbuf (vb.s
   _vb_inbuf), the strings the kernel reads below $A000.

   MIT licence (LICENSE). */
#include <veranda.h>
#include <string.h>
#include <scrap.h>
#include <theme.h>
#include <vr.h>

extern unsigned char vb_inbuf[256];

/* the Text Scrap as plain text into inbuf (CR, a paragraph's end, as LF:
   VeraBASIC's line end); its length */
unsigned char vbc_clipget(void)
{
    unsigned int n = scrap_get_text((char *)vb_inbuf, 256), i;
    for (i = 0; i < n; ++i)
        if (vb_inbuf[i] == 13)
            vb_inbuf[i] = 10;
    return (unsigned char)n;
}

/* inbuf's text (+0 its length) to the Text Scrap: 0 or the error */
unsigned char vbc_clipput(void)
{
    return scrap_put_text((const char *)vb_inbuf + 1, vb_inbuf[0]);
}

/* ---- CLIPBOARD PICTURE: an area of the screen to the Photo Scrap ---- */
static unsigned char px, pw;
static unsigned int py;

static void get_row(unsigned int y, unsigned char *row)
{
    dispBufferOn = ST_WR_BACK;
    ReadRow(vb_inbuf + 16, px, pw, py + y);
    memcpy(row, vb_inbuf + 16, pw);
}

static unsigned char get_col(unsigned char cx, unsigned char cy)
{
    return 1 << 4 | GetCardColor(px + cx, (py >> 3) + cy);
}

unsigned char vbc_photo(void)
{
    unsigned char e, x, y, any = 0, keep = dispBufferOn;
    px = vb_inbuf[0];
    pw = vb_inbuf[1];
    py = vb_inbuf[2] | vb_inbuf[3] << 8;
    for (y = py >> 3; y <= (py + (vb_inbuf[4] | vb_inbuf[5] << 8) - 1) >> 3; ++y)
        for (x = px; x < px + pw; ++x)
            any |= GetCardColor(x, y);
    e = scrap_put_photo(pw, vb_inbuf[4] | vb_inbuf[5] << 8, get_row, any ? get_col : 0);
    dispBufferOn = keep;
    return e;
}

/* ---- TILE x, y, name$ [, colour] ---- */
static unsigned char hdr[512];          /* the file's first two blocks (in bank B: FRead) */
static const char *const where[4] = { "", "//VERANDA/APPS/:", "//VERANDA/:", "//:" };

/* the program's file, its tile drawn: 0, or FILE_NOT_FOUND */
unsigned char vbc_tile(void)
{
    unsigned char h = 0, i, r, a, b, c, col, *d;
    char *p = (char *)vb_inbuf + 70;
    const char *s;
    for (i = 0; i < 4 && !h; ++i) {
        strcpy(p, where[i]);
        strcat(p, (char *)vb_inbuf + 3);
        strcat(p, ".cvt");
        h = FOpen(p, 'r');
        if (h < 2 || h > 9 || dosStatus >= 20)
            h = 0;
    }
    if (!h)
        return FILE_NOT_FOUND;
    r = FRead(h, hdr, 510) == 510;
    FClose(h);
    if (!r || memcmp(hdr + 30, "PRG formatted GEOS file", 23))
        return INCOMPATIBLE;
    /* the info block: header byte n at 254 + n - 2 */
    d = vb_inbuf + 120 + 2;          /* (composed at +120: vr_tile) */
    if (!memcmp(hdr + 389, "VRND", 4) && (hdr[395] & 2)) {
        memcpy(d, hdr + 97, 128);       /* its own tile (APPFORMAT.md) */
        col = hdr[96] & 15;
    } else {                            /* its GEOS icon, 24 x 21, centred */
        s = (const char *)hdr + 257;
        memset(d, 0, 128);
        d += 6 * 4;
        for (r = 0; r < 21; ++r, s += 3, d += 4) {
            a = s[0];
            b = s[1];
            c = s[2];
            d[0] = a >> 4;
            d[1] = a << 4 | b >> 4;
            d[2] = b << 4 | c >> 4;
            d[3] = c << 4;
        }
        col = CHROME;
    }
    if (vb_inbuf[2] != 0xFF)
        col = vb_inbuf[2];
    dispBufferOn = ST_WR_FORE | ST_WR_BACK;
    vr_tile(vb_inbuf[0], vb_inbuf[1] << 3, vb_inbuf + 120 + 2, vb_inbuf + 120);
    ColorRect(vb_inbuf[0], 4, vb_inbuf[1], 4, col);
    return 0;
}
