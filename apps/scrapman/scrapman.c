/* Photo Manager and Text Manager: Veranda desk accessories in C (one
   source; -DPHOTO or -DTEXT).

   An album of clipboard scraps (scrap.h, DECISIONS V54), kept as a
   record file in the system's data folder (/VERANDA/.SYSTEM, vrpath.h:
   DECISIONS V71; GEOS's managers keep theirs on the current disk; the
   accessory goes back to curDirName, the application's folder, when it
   closes): "Photo Album" (class "Photo Album V1.0") or "Text
   Album" ("Text Album V1.0"), a record a page, each record the scrap's
   data as it is (a Photo Scrap: the width, the height, the compacted
   bitmap and colours; a Text Scrap: the count and the text).

   The window is the whole screen (Veranda Look 3 "Sunroom", DECISIONS
   V148: the SDK's window chrome, vrwin.h): the title band with the close
   box at its right, a toolbar of buttons (previous, next, add, copy,
   delete), the page, and the status bar (the page's number at the left,
   what a button did at the right). The Text Manager has Veranda's palette
   (theme.h, light or dark) and shows the text in the UI font; the Photo
   Manager keeps the palette of the program underneath, which its
   pictures' colours are, so its chrome is in the ink only. Add puts the
   clipboard's scrap into the album
   after the page shown; copy puts the page shown on the clipboard;
   delete takes it out of the album. Keys: the left and right arrows,
   A, C, D, Escape (close).

   MIT licence (see LICENSE). */
#include <veranda.h>
#include <vr.h>
#include <string.h>
#include <scrap.h>
#include <vrpath.h>
#include <theme.h>
#include <vrwin.h>

#ifdef PHOTO
#define KIND    SCRAP_PHOTO
#define MTITLE  "Photo Manager"
#define ALBUM   "Photo Album"
#define ACLASS  "Photo Album V1.0"
#define ADESC   "Pictures kept by the Photo Manager."
#define WHAT    "picture"
#define WHATC   "Picture"
#define BUFSZ   20480
#else
#define KIND    SCRAP_TEXT
#define MTITLE  "Text Manager"
#define ALBUM   "Text Album"
#define ACLASS  "Text Album V1.0"
#define ADESC   "Texts kept by the Text Manager."
#define WHAT    "text"
#define WHATC   "Text"
#define BUFSZ   8192
#endif

#define BTNY    24              /* the buttons (in the toolbar, card rows 2-5) */
#define BTNH    16
#define BTNW    56
#define PAGEY   48              /* the page (to the status bar, card rows 58-59) */
#define PAGEB   464
#define NBTN    5

static unsigned char buf[BUFSZ];
static unsigned int blen;               /* the page's bytes in buf */
static unsigned char page, pages;
static char line[96];
static const struct vrwin win = { 0, 0, 80, 60, 4, 2, VW_CLOSE };
static char st[32];                     /* the status bar's left: the page */

#ifdef MAN_TEST
void man_test_start(void);
#endif

static const char *const btext[NBTN] = { "< Prev", "Next >", "Add", "Copy", "Delete" };

static unsigned int strw(const char *s)
{
    unsigned int w = 0;
    while (*s)
        w += GetCharWidth(*s++);
    return w;
}

static void say(const char *s)
{
    strcpy(line, "MAN ");
    strcat(line, s);
    LogText(line);
}

/*---------------------------------------------------------------
  the album
 ---------------------------------------------------------------*/
static unsigned char hdr[256];

static unsigned char album_open(void)
{
    unsigned char e = OpenRecordFile(ALBUM);
    if (e == FILE_NOT_FOUND) {          /* a new album: a record file of none */
        memset(hdr, 0, sizeof hdr);
        hdr[0] = (unsigned int)ALBUM & 255;
        hdr[1] = (unsigned int)ALBUM >> 8;
        hdr[2] = 3;
        hdr[3] = 21;
        hdr[4] = 0xBF;
        memset(hdr + 5, 0xFF, 3);
        memset(hdr + 5 + 60, 0xFF, 3);
        for (e = 1; e < 20; ++e) {
            hdr[5 + e * 3] = 0x80;
            hdr[7 + e * 3] = 0x01;
        }
        hdr[68] = 0x83;
        hdr[69] = APPL_DATA;
        hdr[70] = 1;                    /* VLIR */
        strcpy((char *)hdr + O_GHFNAME, ACLASS);
        strcpy((char *)hdr + O_GH_AUTHOR, "Veranda");
        strcpy((char *)hdr + O_GHINFO_TXT, ADESC);
        if ((e = SaveFile(hdr, 0)) != 0)
            return e;
        e = OpenRecordFile(ALBUM);
    }
    return e;
}

/* the number of pages, and page p (if there is one) into buf */
static unsigned char load(unsigned char p)
{
    unsigned char e = album_open();
    blen = 0;
    if (e) {
        pages = 0;
        return e;
    }
    pages = usedRecords;
    if (p < pages && (e = PointRecord(p)) == 0 && (e = ReadRecord(buf, BUFSZ)) == 0)
        blen = r7 - (unsigned int)buf;
    CloseRecordFile();
    return e;
}

/*---------------------------------------------------------------
  drawing
 ---------------------------------------------------------------*/
/* (V148) a button as the dialog boxes': white on the toolbar (card
   aligned), a frame with its corners cut */
static void button(unsigned char i)
{
    unsigned int x = 8 + i * (BTNW + 8), r = x + BTNW - 1, b = BTNY + BTNH - 1;
    SetPattern(0);
    WRectangle(x, BTNY, r, b);
    theme_rect(x >> 3, BTNW >> 3, BTNY >> 3, BTNH >> 3, 0);
    WFrameRectangle(0xFF, x, BTNY, r, b);
    WDrawPoint(DRAW_ERASE, x, BTNY);
    WDrawPoint(DRAW_ERASE, r, BTNY);
    WDrawPoint(DRAW_ERASE, x, b);
    WDrawPoint(DRAW_ERASE, r, b);
    WPutString((char *)btext[i], x + (BTNW - strw(btext[i])) / 2, BTNY + 11);
}

static void number(unsigned char n, char *s)
{
    if (n >= 100)
        *s++ = '0' + n / 100;
    if (n >= 10)
        *s++ = '0' + n / 10 % 10;
    *s++ = '0' + n % 10;
    *s = 0;
}

/* the status bar: the page at the left, a (what a button did) at the right */
static void message(const char *a)
{
    dispBufferOn = ST_WR_FORE;
    vr_win_status(&win, st, a);
    UseFont(FONT_UI);                   /* (vrwin ends with the system font) */
}

static void status(void)
{
    if (pages) {
        strcpy(st, WHATC " ");
        number(page + 1, st + strlen(st));
        strcat(st, " of ");
        number(pages, st + strlen(st));
    } else
        strcpy(st, "The album is empty.");
    message(0);
}

#ifdef PHOTO
/* the compacted data at p, n bytes of it decoded, each to f (or none);
   the end past them (end: the data's end) */
static unsigned char *dp, *dend;
static unsigned int dn;
static void (*df)(unsigned char);

static void out1(unsigned char b)
{
    if (dn) {
        --dn;
        if (df)
            df(b);
    }
}

static void simple(void)                /* one code from dp (not a pattern) */
{
    unsigned char c = *dp++, k;
    if (c >= 0x80) {
        for (k = c - 0x80; k && dp < dend; --k)
            out1(*dp++);
    } else {
        for (k = c; k; --k)
            out1(*dp);
        ++dp;
    }
}

static void decode(void)
{
    unsigned char c, rep, len, *start;
    while (dn && dp < dend) {
        c = *dp;
        if (c < 0xDC) {
            simple();
            continue;
        }
        len = c - 0xDC;
        rep = dp[1];
        start = dp + 2;
        while (rep--) {
            dp = start;
            while (dp < start + len && dp < dend)
                simple();
        }
        dp = start + len;
    }
}

static unsigned char cw, ccx, ccy;

static void card(unsigned char c)
{
    ColorRect(ccx, 1, PAGEY / 8 + ccy, 1, c & 15);
    if (++ccx == cw) {
        ccx = 0;
        ++ccy;
    }
}

static void show_page(void)
{
    unsigned char w = buf[0];
    unsigned int h = buf[1] | buf[2] << 8, vh = PAGEB - PAGEY;
    if (blen < 4)
        return;
    if (w > screenWidth / 8)            /* wider than the screen: not shown */
        return;
    WBitmapUp(buf + 3, 0, w, PAGEY, h > vh ? vh : h);
    /* the colours after the bitmap, if any */
    dp = buf + 3;
    dend = buf + blen;
    dn = w * h;
    df = 0;
    decode();
    if (dp < dend) {
        cw = w;
        ccx = ccy = 0;
        dn = w * ((h > vh ? vh : h) + 7 >> 3);
        df = card;
        decode();
    }
}
#else
/* the text, plain, in lines broken at spaces to fit the screen */
static void show_page(void)
{
    unsigned int len = buf[0] | buf[1] << 8, i, y = PAGEY + 14, w = 0, maxw = screenWidth - 24;
    unsigned char n = 0, skip = 0, sp = 0, c, k;
    if (len > blen - 2)
        len = blen - 2;
    for (i = 2; i < len + 2 && y < PAGEB - 4; ++i) {
        c = buf[i];
        if (skip) {
            --skip;
            continue;
        }
        if (c == SCRAP_NEWCARDSET) { skip = 3; continue; }
        if (c == SCRAP_ESC_RULER) { skip = 26; continue; }
        if (c == SCRAP_ESC_GRAPHICS) { skip = 4; continue; }
        if (c == 9)
            c = ' ';
        if (c == 13 || c == SCRAP_PAGE_BREAK) {
            line[n] = 0;
            WPutString(line, 12, y);
            y += 13;
            n = sp = 0;
            w = 0;
            continue;
        }
        if (c < 32 || c > 126)
            continue;
        if (c == ' ')
            sp = n;
        line[n++] = c;
        w += GetCharWidth(c);
        if (w > maxw || n == sizeof line - 1) {  /* a line full: break at its last space */
            k = sp ? sp : n - 1;
            c = line[k];
            line[k] = 0;
            WPutString(line, 12, y);
            y += 13;
            line[k] = c;
            if (sp)
                ++k;
            memmove(line, line + k, n - k);
            n -= k;
            line[n] = 0;
            w = strw(line);
            sp = 0;
        }
    }
    if (n && y < PAGEB - 4) {
        line[n] = 0;
        WPutString(line, 12, y);
    }
}
#endif

static void draw_page(void)
{
    dispBufferOn = ST_WR_FORE;
    SetPattern(0);
    WRectangle(0, PAGEY, screenWidth - 1, PAGEB - 1);
#ifdef PHOTO
    ColorRect(0, screenWidth / 8, PAGEY / 8, (PAGEB - PAGEY) / 8, 0);
#endif
    status();
    if (blen)
        show_page();
}

static void draw(void)
{
    unsigned char i;
    dispBufferOn = ST_WR_FORE;          /* the application's screen is put aside whole */
#ifndef PHOTO
    theme_load();                       /* (V148: Veranda's palette, light or dark) */
    theme_palette();
#endif
    vr_win(&win, MTITLE);
    UseFont(FONT_UI);
    for (i = 0; i < NBTN; ++i)
        button(i);
    draw_page();
}

/*---------------------------------------------------------------
  the buttons
 ---------------------------------------------------------------*/
static void go(unsigned char p)
{
    load(p);
    page = p;
    draw_page();
}

static void m_add(void)
{
    unsigned char e;
    if (!scrap_open(KIND)) {
        message("There is no " WHAT " on the clipboard.");
        return;
    }
    blen = scrap_read(buf, BUFSZ);
    if (blen == BUFSZ && scrap_read(&e, 1)) {
        scrap_close();
        blen = 0;
        message("The clipboard's " WHAT " is too big for the album.");
        return;
    }
    scrap_close();
    if ((e = album_open()) == 0) {
        if (usedRecords) {
            PointRecord(page);
            e = AppendRecord();         /* after the page shown */
        } else
            e = AppendRecord();
        if (!e)
            e = WriteRecord(buf, blen);
        page = curRecord;
        pages = usedRecords;
        if (CloseRecordFile() && !e)
            e = DOS_ERROR;
    }
    if (e) {
        message("The album could not be written.");
        return;
    }
    say("ADDED");
    go(page);
}

static void m_copy(void)
{
    unsigned char e;
    if (!blen) {
        message("The album is empty.");
        return;
    }
    e = scrap_create(KIND, blen);
    if (!e)
        e = scrap_write(buf, blen);
    if (scrap_close() && !e)
        e = DOS_ERROR;
    if (e) {
        message("The clipboard could not be written.");
        return;
    }
    say("COPIED");
    message("Copied to the clipboard.");
}

static void m_delete(void)
{
    unsigned char e;
    if (!pages)
        return;
    if ((e = album_open()) == 0) {
        if ((e = PointRecord(page)) == 0)
            e = DeleteRecord();
        CloseRecordFile();
    }
    if (page && page >= pages - 1)
        --page;
    say("DELETED");
    go(page);
}

static void close_box(void)
{
    say("CLOSED");
    ChDir(curDirName[0] == '/' ? (char *)curDirName : "/");
    RstrAppl();
}

static void act(unsigned char b)
{
    switch (b) {
    case 0: if (page) go(page - 1); break;
    case 1: if (page + 1 < pages) go(page + 1); break;
    case 2: m_add(); break;
    case 3: m_copy(); break;
    case 4: m_delete(); break;
    }
}

/* otherPressVec: a press on a button or the close box */
static void press(void)
{
    unsigned int x = mouseXPos, y = mouseYPosW;
    unsigned char b;
    if (mouseData & 0x80)
        return;
    if (vr_win_hit(&win, x, y) == VW_XCLOSE) {
        close_box();
        return;
    }
    if (y < BTNY || y >= BTNY + BTNH || x < 8)
        return;
    b = (x - 8) / (BTNW + 8);
    if (b < NBTN && (x - 8) % (BTNW + 8) < BTNW)
        act(b);
}

static void typed(void)
{
    switch (keyData) {
    case 8: act(0); break;              /* (the left arrow: Backspace's code) */
    case 30: act(1); break;             /* the right arrow */
    case 'a': case 'A': act(2); break;
    case 'c': case 'C': act(3); break;
    case 'd': case 'D': act(4); break;
    case 27: close_box(); break;
    }
}

int main(void)
{
    vr_cd(VR_DATA);                     /* (the album's folder) */
    load(0);
    page = 0;
    draw();
    otherPressVec = VR_FN(press);
    keyVector = VR_FN(typed);
    say("RUNNING");
#ifdef MAN_TEST
    man_test_start();
#endif
    return 0;
}
