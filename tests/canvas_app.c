/* gate canvas (DECISIONS V166): the kernel's canvas mode through the
   SDK's vrcanvas.h, in the 320 x 240 mode.

   CanvApp draws a picture of one byte a pixel whose bytes are a function
   of the place (pix: never 0), and palette entries 21-255 of its own
   (pal). It logs "CANVAS <what> L0 <L0_CONFIG> TB <L0_TILEBASE> L1
   <L1_CONFIG> VID <DC_VIDEO> BAD <bytes not as they should be> COV <cards
   covered> PAL <ok or the sum>": the picture's bytes are pix's but on
   covered cards, which are 0 (vr_canvas_covered).
   Its session (a frame counter in the interrupt; the menus by the
   script, tests/canvas_script.h through tests/sdk_play.s):
     START   before the canvas (PAL0: the sum of palette entries 16-255)
     ON      the canvas on, the picture and the palette drawn
     COVERED when cards become covered (the File menu opened by the
             script) and UNCOVERED when the last cover goes
     DIALOG  after the SDK's Open box (vr_file: the script's Esc ends it)
     DESK    after the test accessory CanvDA (GetFile; it ends itself)
     BACK    after TaskCtl(TASK_ASIDE) and the test desktop's TASK_RESUME
             (vr_canvas_back: the palette and the picture drawn again)
     OFF     vr_canvas_off; it quits (EnterDeskTop)
   -D HUGE: it holds every RAM bank TASK_ROOM allows first (Roomy: it
   goes onto the card). -D STOP=n: the emulator's dump at frame n (the
   script's shots). -D NOASIDE: it quits after DESK (no test desktop).

   MIT licence (see LICENSE). */
#include <veranda.h>
#include <vr.h>
#include <vrcanvas.h>
#include <vrchoose.h>
#include <vrpath.h>
#include <string.h>

#define VCTRL  (*(volatile unsigned char *)0x9F25)
#define VADDRL (*(volatile unsigned char *)0x9F20)
#define VADDRM (*(volatile unsigned char *)0x9F21)
#define VADDRH (*(volatile unsigned char *)0x9F22)
#define VDATA0 (*(volatile unsigned char *)0x9F23)
#define VDCV   (*(volatile unsigned char *)0x9F29)
#define L0CFG  (*(volatile unsigned char *)0x9F2D)
#define L0TB   (*(volatile unsigned char *)0x9F2F)
#define L1CFG  (*(volatile unsigned char *)0x9F34)

extern void __fastcall__ vr_play(const void *script);

#ifndef STOP
#define STOP 0xFFFE
#endif
#define AT(f, x, y) ((f) > STOP ? 0xFFFF : (f)), ((f) > STOP ? STOP : (x)), (y)
#define P(f, x, y, b) AT(f, x, ((y) & 255) | (((y) >> 8) << 14) | ((b) << 8))
#define K(f, c) AT(f, c, 0x8000)
#define END(f) 0xFFFF, ((f) > STOP ? STOP : (f)), 0

static const unsigned int script[] = {
#include "canvas_script.h"
};

static volatile unsigned int frames;
static unsigned char state, wascov;
static unsigned int pal0;
static char line[96];
static char name[64];
static const char hx[] = "0123456789ABCDEF";

static void vat(unsigned long a)
{
    VCTRL = 0;
    VADDRL = (unsigned char)a;
    VADDRM = (unsigned char)(a >> 8);
    VADDRH = (unsigned char)((a >> 16) & 1) | 0x10;
}

static unsigned int vsum(unsigned long a, unsigned int n)
{
    unsigned int s = 0;
    vat(a);
    while (n--)
        s += VDATA0;
    return s;
}

static char *hex(char *p, unsigned int v, unsigned char d)
{
    while (d--)
        *p++ = hx[(v >> (4 * d)) & 15];
    return p;
}

/* the picture: a byte of (x, y), never 0 */
#define PIX0(y) ((unsigned char)((y) << 1))
static unsigned char pfix(unsigned char v)
{
    return v ? v : 255;
}

/* palette entry i (21-255) */
static unsigned int palw(unsigned char i)
{
    return (i * 0x0123u + 0x0456u) & 0x0FFF;
}

static unsigned int pal[256];

static void put_palette(void)
{
    unsigned int i;
    for (i = 21; i < 256; ++i)
        pal[i] = palw(i);
    vr_canvas_palette(pal + 21, 21, 235);
}

static unsigned int pal_sum(unsigned char first)
{
    return vsum(0x1FA00UL + 2 * first, 2 * (256 - first));
}

static unsigned int pal_want(void)
{
    unsigned int s = 0, i, w;
    for (i = 21; i < 256; ++i) {
        w = palw(i);
        s += (w & 255) + (w >> 8);
    }
    return s;
}

/* cards x .. x + w - 1 of card row cy drawn (the kernel's repaint, and the
   whole picture) */
static void draw_cards(unsigned char cx, unsigned char w, unsigned char cy)
{
    unsigned char r, y, v;
    unsigned int n, x0 = cx * 8;
    unsigned long a = VR_CANVAS + 2560UL * cy + x0;
    for (r = 0; r < 8; ++r, a += 320) {
        y = cy * 8 + r;
        vat(a);
        v = PIX0(y) + (unsigned char)x0;
        for (n = w * 8; n; --n) {
            VDATA0 = pfix(v);
            ++v;
        }
    }
}

static void repaint(void)
{
    draw_cards(vr_canvas_area[0], vr_canvas_area[1], vr_canvas_area[2]);
}

static void draw_all(void)
{
    unsigned char cy;
    for (cy = 0; cy < 30; ++cy)
        draw_cards(0, 40, cy);
}

/* the bytes not as they should be; *cov = the cards covered (a row of
   VRAM at a time, the address counting up) */
static unsigned char covrow[40];

static unsigned int bad(unsigned int *cov)
{
    unsigned char cx, cy, r, y, v, k;
    unsigned int b = 0;
    unsigned long a = VR_CANVAS;
    *cov = 0;
    for (cy = 0; cy < 30; ++cy) {
        for (cx = 0; cx < 40; ++cx)
            if ((covrow[cx] = vr_canvas_covered(cx, cy)) != 0)
                ++*cov;
        for (r = 0; r < 8; ++r, a += 320) {
            y = cy * 8 + r;
            vat(a);
            v = PIX0(y);
            for (cx = 0; cx < 40; ++cx) {
                if (covrow[cx]) {
                    for (k = 8; k; --k, ++v)
                        if (VDATA0)
                            ++b;
                } else {
                    for (k = 8; k; --k, ++v)
                        if (VDATA0 != (v ? v : 255))
                            ++b;
                }
            }
        }
    }
    return b;
}

static void say(const char *what)
{
    char *p = line;
    unsigned int cov, b, s;
    b = bad(&cov);
    s = pal_sum(21);
    *p++ = 10;
    strcpy(p, "CANVAS ");
    p += 7;
    while (*what)
        *p++ = *what++;
    *p++ = ' ', *p++ = 'L', *p++ = '0', *p++ = ' ';
    p = hex(p, L0CFG, 2);
    *p++ = ' ', *p++ = 'T', *p++ = 'B', *p++ = ' ';
    p = hex(p, L0TB, 2);
    *p++ = ' ', *p++ = 'L', *p++ = '1', *p++ = ' ';
    p = hex(p, L1CFG, 2);
    VCTRL = 0;
    *p++ = ' ', *p++ = 'V', *p++ = 'I', *p++ = 'D', *p++ = ' ';
    p = hex(p, VDCV, 2);
    *p++ = ' ', *p++ = 'B', *p++ = 'A', *p++ = 'D', *p++ = ' ';
    p = hex(p, b, 4);
    *p++ = ' ', *p++ = 'C', *p++ = 'O', *p++ = 'V', *p++ = ' ';
    p = hex(p, cov, 4);
    *p++ = ' ', *p++ = 'P', *p++ = 'A', *p++ = 'L', *p++ = ' ';
    if (s == pal_want())
        *p++ = 'o', *p++ = 'k';
    else
        p = hex(p, s, 4);
    *p++ = ' ', *p++ = 'F', *p++ = ' ';
    p = hex(p, frames, 4);
    *p = 0;
    LogText(line);
}

static void tick(void)
{
    ++frames;
}

/* the menus: the program's, File */
static void m_close(void);
struct item { const char *text; unsigned char type; void *p; };
struct menu1 { unsigned char top, bottom; unsigned int left, right; unsigned char flags; struct item i[1]; };
struct menu2 { unsigned char top, bottom; unsigned int left, right; unsigned char flags; struct item i[2]; };
static struct menu1 mfile = { 14, 14 + 16, 40, 120, VERTICAL | 1, { { "Close", MENU_ACTION, m_close } } };
static struct menu2 mbar = { 0, 14, 0, 100, HORIZONTAL | UN_CONSTRAINED | 2, {
    { "CanvApp", MENU_ACTION, 0 }, { "File", SUB_MENU, &mfile } } };

static void m_close(void)
{
    GotoFirstMenu();
}

static void quit(void)
{
    vr_canvas_off();
    say("OFF");
    LogText("\nCANVAS QUIT");
    EnterDeskTop();
}

static void loop(void)
{
    unsigned int cov;
    unsigned char c;
    if (vr_canvas_back()) {             /* back from the switcher */
        put_palette();
        draw_all();
        say("BACK");
        quit();
    }
    /* the covers: a change logged */
    c = vr_canvas_covers != 0;
    if (c != wascov) {
        wascov = c;
        say(c ? "COVERED" : "UNCOVERED");
    }
    (void)cov;
    if (state == 0 && frames >= 480) {
        state = 1;
        name[0] = 0;
        vr_file(VRF_OPEN, "Open a picture", name);
        say("DIALOG");
    }
    if (state == 1 && frames >= 700) {
        state = 2;
        vr_cd(VR_APPS);                 /* (the Open box went to the documents) */
        c = GetFile("CanvDA", 0, 0, 0, 0);
        vr_cdback();
        if (c) {
            line[0] = 10;
            strcpy(line + 1, "CANVAS NO DA 00");
            line[15] = hx[c >> 4];
            line[16] = hx[c & 15];
            LogText(line);
        }
        say("DESK");
#ifdef NOASIDE
        quit();
#endif
    }
    if (state == 2 && frames >= 800) {
        state = 3;
        TaskCtl(TASK_ASIDE, 0, 0);
    }
}

int main(void)
{
    char *p;
#ifdef HUGE
    unsigned char n = vr_room();
    if (n > 16)
        n -= 16;                        /* (vr_file's list, the accessory's) */
    BankAlloc(n);
#endif
    pal0 = pal_sum(16);
    p = line;
    *p++ = 10;
    strcpy(p, "CANVAS PAL0 ");
    p = hex(p + 12, pal0, 4);
#ifdef HUGE
    strcpy(p, " HUGE ");
    p = hex(p + 6, n, 2);
#endif
    *p = 0;
    LogText(line);
    dispBufferOn = ST_WR_FORE;          /* (the back screen is the picture's room) */
#ifndef NOCANV
    if (vr_canvas_on(repaint)) {
        LogText("\nCANVAS REFUSED");
        return 0;
    }
#endif
    put_palette();
    draw_all();
    uiLook = LOOK_BAR;
    DoMenu((void *)&mbar, 0);
    say("ON");
    vr_set_irq(tick);
    appMain = VR_FN(loop);
    vr_play(script);
    return 0;
}
