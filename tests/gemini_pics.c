/* gate gemini (DECISIONS V125): Veranda Gemini's test build, its second
   overlay (8): the pictures' part of session main (tests/gemini_play.c's
   step 45 calls t_pics through main.c's t_ov7 until t_pics_done). Its
   own copies of the player's helpers (the script in gemini_play.c's
   scr, main RAM).

   The pictures' page (tests/gemini_server.py's /pics.gmi); each picture's
   link clicked: shown (its rows' sums logged by png.c, "GE IROW y sum";
   its tiles dumped to P<k>.DMP; Esc), or its box (interlaced, damaged:
   OK; over the limit, JPEG: No); the comic (740 x 300, 40 KB) put aside
   with Alt+Tab while it is drawn (drawn again when back; its time
   "GE PIC SHOWN frames" without the sums); Return on pal4.png: the box,
   No (saved to /DOCUMENTS); rgb.png shown and the toolbar's Save.
   (V138) Then Gemipedia's image gallery (the server's stand-in, its
   links Gemipedia's media route, /cgi-bin/wp.cgi/media/media.png?<a
   Wikimedia address UrlEncode'd>): the flag (its first connection
   refused by the server: tried again a second later), a picture behind
   a link of 281 characters (the request's rest from the page), a map
   behind a link with no extension (shown by its MIME type, image/png),
   a JPEG (its box: No), a picture on a port nothing listens on (tried
   twice, then the box with the address: OK); dumped to PA.DMP, PB.DMP,
   PC.DMP. Screens: PICRGB.RAW, PICCOMIC.RAW, GALLERY.RAW, PICFLAG.RAW.

   MIT licence (see LICENSE). */
#include <veranda.h>
#include <string.h>
#include <vrnet.h>
#include <vrser.h>
#include "../apps/gemini/gemini.h"
#include "../apps/gemini/png.h"
#pragma code-name ("OVERLAY8")
#pragma rodata-name ("OVL8RO")
#pragma bss-name ("OVL8BSS")

void __fastcall__ term_play(const unsigned int *script);
extern unsigned int scr[3 * 40], stopper[3];
extern unsigned char ns;
extern unsigned char t_pics_done, t_pics_prog;  /* (main.c's: gemini_play.c reads them) */

#define F_BTN 0x100
#define F_KEY 0x8000
#define NONE 0xFFFF
#define YESX 256
#define NOX 336
#define CANCELX 400

static const char *const pn[] = { "gray1", "pal1", "pal4", "pal8", "gray8", "rgb", "rgba", "gray16", "small",
    "comic", "interlaced", "corrupt", "big", "photo" };
#define P_SHOWN 10                      /* (the first 10 are shown; the others: a box) */
#define P_COMIC 9
static unsigned char ps, pk, asided, nbox, gk;
static const char *const gl[] = { "Flag of Poland [Show image]", "Biskupin, a reconstruction [Show image]",
    "Image: a map of Poland", "Wawel Castle in Krak\xF3w [Show image]", "Unreachable [Show image]" };
static const char *const gn[] = { "flag", "castle", "map", "wawel", "unreachable" };
#define G_SHOWN 3                       /* (the first 3 shown; the JPEG's box: No; the unreachable one's: OK) */
static unsigned int tplay, tlen;
static char pl[48];

#define VCTRL  (*(volatile unsigned char *)0x9F25)
#define VAL    (*(volatile unsigned char *)0x9F20)
#define VAM    (*(volatile unsigned char *)0x9F21)
#define VAH    (*(volatile unsigned char *)0x9F22)
#define VD0    (*(volatile unsigned char *)0x9F23)

static void __fastcall__ say(const char *s)
{
    strcpy(pl, s);
    gt_log(pl);
}

static void S(unsigned int f, unsigned int x, unsigned int y, unsigned int fl)
{
    if (!ns) {
        stopper[0] = stopper[1] = 0xFFFF;
        term_play(stopper);
    }
    scr[ns++] = f;
    scr[ns++] = x;
    scr[ns++] = (y & 255) | (y > 255 ? 0x4000 : 0) | fl;
    if (f > tlen)
        tlen = f;
}

static void C(unsigned int f, unsigned int x, unsigned int y)
{
    S(f, x, y, 0);
    S(f + 3, x, y, F_BTN);
    S(f + 7, x, y, 0);
}

static void go_(void)
{
    nbox = t_nbox;
    scr[ns++] = 0xFFFF;
    scr[ns++] = 0xFFFF;
    scr[ns++] = 0;
    term_play(scr);
    ns = 0;
    tplay = ser_frames;
}

static unsigned char played(void)
{
    return ser_frames - tplay > tlen + 40;
}

static unsigned char idle(void)
{
    return played() && !gbusy && !t_box;
}

static unsigned char idle_box(void)
{
    return idle() && t_nbox != nbox;
}

static void W(void)
{
    S(tlen + 10, (unsigned int)&t_box, 0, 0x1000);
}

static void __fastcall__ logn(const char *k, unsigned int v)
{
    strcpy(pl, k);
    unum(pl + strlen(pl), v);
    gt_log(pl);
}

static unsigned char __fastcall__ head_link(unsigned int i)
{
    unsigned char k = doc_kind(i);
    return k != 0xFF && !(k & K_CONT) && (k & K_TYPE) == K_LINK;
}

/* the link labelled t (its first row); NONE */
static unsigned int find(const char *t)
{
    unsigned int i;
    unsigned char n = strlen(t), k;
    for (i = 0; i < doc_lines; ++i) {
        if (!head_link(i))
            continue;
        render(i);
        for (k = ROWW; k > 3 && row[k - 1] == ' '; --k)
            ;
        if (k - 3 == n && !memcmp(row + 3, t, n))
            return i;
    }
    return NONE;
}

/* a click on the link t (the pictures' page is one screen) */
static void __fastcall__ click(const char *t)
{
    unsigned int i = find(t);
    if (i == NONE) {
        say("GE TEST FAILED NO PICTURE LINK");
        return;
    }
    C(10, 200, BODYY + (i - v_top) * rowh + rowh / 2);
}

static void __fastcall__ vat(unsigned int a)
{
    VCTRL = 0;
    VAL = (unsigned char)a;
    VAM = a >> 8;
    VAH = 0x11;
}

/* the screen as gemini_play.c's snap writes it */
static void __fastcall__ snap(const char *name)
{
    unsigned char h, x, y, i;
    unsigned int r;
    strcpy(rel, VR_ROOTPATH);
    strcat(rel, name);
    h = FOpen(rel, 'w');
    if (h < 2 || h > 4)
        return;
    dispBufferOn = ST_WR_FORE;
    for (r = 0; r < 480; ++r) {
        ReadRow((unsigned char *)line, 0, 80, r);
        FWrite(h, line, 80);
    }
    for (y = 0; y < 60; ++y) {
        for (x = 0; x < 80; ++x)
            line[x] = GetCardColor(x, y);
        FWrite(h, line, 80);
    }
    asm("sei");
    *(volatile unsigned char *)0x9F25 &= 0xFE;
    *(volatile unsigned char *)0x9F20 = 0x00;
    *(volatile unsigned char *)0x9F21 = 0xFA;
    *(volatile unsigned char *)0x9F22 = 0x11;
    for (i = 0; i < 32; ++i)
        line[i] = *(volatile unsigned char *)0x9F23;
    asm("cli");
    FWrite(h, line, 32);
    FClose(h);
    strcpy(pl, "GE SNAP ");
    strcat(pl, name);
    gt_log(pl);
}

/* the picture as VRAM shows it: P<k>.DMP: pw, ph, pow_, poh (2 bytes
   each), pmode, ptw, pth, ptx, pty; palette row 2 (32 bytes); the map's
   tiles row by row (32 bytes each) */
static void dump(void)
{
    unsigned char h, tx, ty, i, n = 0, lo, hi;
    strcpy(rel, VR_ROOTPATH "P0.DMP");
    rel[strlen(rel) - 5] += pk;
    h = FOpen(rel, 'w');
    if (h < 2 || h > 4) {
        say("GE PIC DUMP FAILED");
        return;
    }
    memcpy(line, &pw, 2);
    memcpy(line + 2, &ph, 2);
    memcpy(line + 4, &pow_, 2);
    memcpy(line + 6, &poh, 2);
    line[8] = pmode;
    line[9] = ptw;
    line[10] = pth;
    line[11] = ptx;
    line[12] = pty;
    vat(0xFA40);
    for (i = 0; i < 32; ++i)
        line[13 + i] = VD0;
    FWrite(h, line, 45);
    for (ty = 0; ty < pth; ++ty)
        for (tx = 0; tx < ptw; ++tx) {
            vat(0xAC00 + ((unsigned int)(pty + ty) << 8) + ((ptx + tx) << 1));
            lo = VD0;
            hi = VD0 & 3;
            vat((((unsigned int)hi << 8) | lo) * 32 + 0x3000);
            for (i = 0; i < 32; ++i)
                line[n++] = VD0;
            if (n == 128) {
                FWrite(h, line, 128);
                n = 0;
            }
        }
    if (n)
        FWrite(h, line, n);
    FClose(h);
}

/* Tabs from the selection to link row i (round the end as ui.c's tab) */
static unsigned char __fastcall__ tabs_to(unsigned int i)
{
    unsigned int j = v_sel != NONE ? v_sel : (v_top ? v_top - 1 : doc_lines - 1);
    unsigned char n = 0;
    do {
        j = j + 1 < doc_lines ? j + 1 : 0;
        if (head_link(j))
            ++n;
    } while (j != i && n < 60);
    return n;
}

/* a step (gemini_play.c's step 46, the pictures' page shown): t_pics_done 1 at the end */
void t_pics(void)
{
    unsigned int i;
    unsigned char n;
    switch (ps) {
    case 1:
        if (!idle() || !doc_done || viewing)
            return;
        if (pk == sizeof pn / sizeof pn[0]) {
            ps = 10;
            return;
        }
        strcpy(pl, "GE PIC ");
        strcat(pl, pn[pk]);
        gt_log(pl);
        png_sums = pk != P_COMIC;
        strcpy(pl, pn[pk]);
        strcat(pl, pk == 13 ? ".jpg [Show image]" : ".png [Show image]");
        click(pl);
        if (pk >= P_SHOWN) {
            W();
            C(tlen + 30, pk < 12 ? YESX : CANCELX, 272);        /* (a box's OK; Yes/No's No) */
        }
        go_();
        break;
    case 2:
        if (pk >= P_SHOWN) {
            if (!idle_box())
                return;
            ++pk;
            ++t_pics_prog;
            ps = 1;
            return;
        }
        if (pk == P_COMIC && viewing == 1 && oy_done > 40 && !asided) {
            asided = 1;
            logn("GE PIC ASIDE AT ", oy_done);
            logn("GE PIC HANDLES ", (xf_h << 8) | png_h);
            switchReq = SWITCH_ASIDE;
            return;
        }
        if (viewing != 2 || !played())
            return;
        dump();
        if (pk == 5)
            snap("PICRGB.RAW");
        if (pk == P_COMIC)
            snap("PICCOMIC.RAW");
        S(10, 0x1B, 0, F_KEY);          /* (Esc) */
        go_();
        break;
    case 3:
        if (!idle() || viewing)
            return;
        ++pk;
        ++t_pics_prog;
        ps = 1;
        return;
    case 10:                            /* Return on pal4.png: Show, Save, Cancel: No */
        if (!idle())
            return;
        n = tabs_to(find("pal4.png [Show image]"));
        for (i = 0; i < n; ++i)
            S(10 + i * 20, 0x09, 0, F_KEY);
        S(30 + n * 20, 13, 0, F_KEY);
        W();
        C(tlen + 30, NOX, 272);
        go_();
        break;
    case 11:                            /* (saved) rgb.png shown, the toolbar's Save */
        if (!idle_box() || viewing)
            return;
        say("GE PIC RETURN");
        click("rgb.png [Show image]");
        go_();
        break;
    case 12:
        if (viewing != 2 || !played())
            return;
        C(10, GOX * 8 + 20, TOOLY + 7);
        go_();
        break;
    case 13:
        if (!idle())
            return;
        say("GE PIC SAVED");
        S(10, 0x1B, 0, F_KEY);
        go_();
        break;
    case 14:                            /* (V138) Gemipedia's gallery */
        if (!idle() || viewing)
            return;
        click("Gallery: Poland");
        go_();
        ps = 20;
        ++t_pics_prog;
        return;
    case 20:
        if (!idle() || !doc_done || viewing)
            return;
        if (!gk)
            snap("GALLERY.RAW");
        if (gk == sizeof gn / sizeof gn[0]) {
            t_pics_done = 1;
            return;
        }
        strcpy(pl, "GE PIC ");
        strcat(pl, gn[gk]);
        gt_log(pl);
        png_sums = 1;
        click(gl[gk]);
        if (gk >= G_SHOWN) {
            W();
            C(tlen + 30, gk == G_SHOWN ? CANCELX : YESX, 272);        /* (the JPEG's No; the box's OK) */
        }
        go_();
        break;
    case 21:
        if (gk >= G_SHOWN) {
            if (!idle_box())
                return;
            ++gk;
            ps = 20;
            ++t_pics_prog;
            return;
        }
        if (viewing != 2 || !played())
            return;
        pk = 17 + gk;                   /* (PA.DMP, PB.DMP, PC.DMP) */
        dump();
        if (!gk)
            snap("PICFLAG.RAW");
        S(10, 0x1B, 0, F_KEY);          /* (Esc) */
        go_();
        break;
    case 22:
        if (!idle() || viewing)
            return;
        ++gk;
        ps = 20;
        ++t_pics_prog;
        return;
    }
    ++ps;
    ++t_pics_prog;
}

/* (V149, gemini_play.c's step 40) the File menu opened, its picture
   (MENU.RAW) when the script has played: u_ret 1 then */
extern unsigned int barx[4], barl[4];
static unsigned char mstep = 0;         /* (initialised: main RAM's DATA) */
void t_menu7(void)
{
    u_ret = 0;
    if (!mstep) {
        tlen = 0;
        S(10, barx[1], 7, 0);
        S(11, barx[1], 7, F_BTN);
        S(12, barl[1] + 12, 24, 0);
        go_();
        mstep = 1;
    } else if (idle()) {
        if (mstep == 1)
            snap("MENU.RAW");
        mstep = 2;
        u_ret = 1;
    }
}

/* (gemini_play.c's start) this overlay's state */
void t_pics_init(void)
{
    ps = 1;
    pk = asided = nbox = gk = 0;
    tlen = 0;
    t_pics_done = 0;
}

/* (gemini_play.c's page_log, called by ui.c; here since V128 for overlay
   6's room) the page as shown: "GE PAGE url", "GE L kk text" (the first
   120 rows: the kind in hex, the row's text, trailing spaces cut), "GE
   PAGE END rows full bytes" */
void page_log7(void)
{
    unsigned int i;
    unsigned char k, n;
    static const char hx[] = "0123456789abcdef";
    strcpy(line, "GE PAGE ");
    strncat(line, cur, 150);
    gt_log(line);
    for (i = 0; i < doc_lines + (doc_full && doc_done ? 2 : 0) && i < 120; ++i) {
        k = render(i);
        for (n = ROWW; n && row[n - 1] == ' '; --n)
            ;
        row[n] = 0;
        strcpy(line, "GE L xx ");
        line[5] = hx[k >> 4];
        line[6] = hx[k & 15];
        strcat(line, row);
        gt_log(line);
    }
    strcpy(line, "GE PAGE END ");
    unum(line + strlen(line), doc_lines);
    strcat(line, " ");
    unum(line + strlen(line), doc_full);
    strcat(line, " ");
    unum(line + strlen(line), doc_len);
    gt_log(line);
}
