/* Veranda Gemini: pictures (overlay 4; DECISIONS V125).

   A picture link (its URL ends .png .jpg .jpeg .gif .bmp: the picture
   badge, "[Show image]" after its label) is fetched to a file of its own
   (GEMINI.TMP in /VERANDA/.SYSTEM; File > Settings...'s limit, 256 KB at
   first: a bigger one asks to be saved instead), the status bar showing
   its type, its bytes as they come and, once PNG's IHDR has come, its
   size. A click shows it; Return asks: Yes show it, No save it, Cancel.

   Then the viewer: the kernel's tile mode (as the SDK's vr_pic sets it
   up, V105: palette entries 32-255 kept at $12C00, tiles 0-15 the solid
   colours, row 15 the paper), the window's chrome drawn again (its
   colours as solid tiles), the page's area clear (the bitmap's 0 bits
   show the tiles), the picture decoded a slice at a time from the main
   loop (png.c, pngcore.s: overlay 5; the menus off meanwhile: they would
   come back from the back screen, which holds the decoder's window), its
   palette row 2. Esc (or Backspace, Left, the toolbar's Back) goes back
   to the page; S, Ctrl+S or the toolbar's Save button copies the file to
   /DOCUMENTS (named by the URL; "Replace?"). Alt+Tab while it is drawn:
   the file closed (main.c's aside), drawn again from the start when back.
   Going anywhere else (a menu: Back, Home ...) closes it first.

   MIT licence (see LICENSE). */
#include <veranda.h>
#include <string.h>
#include <vrnet.h>
#include <vrser.h>
#include <vrpath.h>
#include <theme.h>
#include "gemini.h"
#include "png.h"
#pragma code-name ("OVERLAY4")
#pragma rodata-name ("OVL4RO")
#pragma bss-name ("OVL4BSS")

#define VCTRL  (*(volatile unsigned char *)0x9F25)
#define VAL    (*(volatile unsigned char *)0x9F20)
#define VAM    (*(volatile unsigned char *)0x9F21)
#define VAH    (*(volatile unsigned char *)0x9F22)
#define VD0    (*(volatile unsigned char *)0x9F23)
#define VD1    (*(volatile unsigned char *)0x9F24)


static unsigned int tshow;
#ifdef GEMINI_TEST
static unsigned int t_pic;              /* (the test: the drawing's start) */
#endif

static void __fastcall__ vport(unsigned char port, unsigned char h, unsigned int a)
{
    VCTRL = port;
    VAL = (unsigned char)a;
    VAM = a >> 8;
    VAH = 0x10 | h;
}

/* the status bar's left (ui.c's ui_status is overlay 1's: not mapped here) */
static void __fastcall__ pstatus(const char *s)
{
    if (s != msg)
        strcpy(msg, s);
    win_status(msg, right);
}

/* the picture's file (GEMINI.TMP in the system's folder): its handle, 0 */
static unsigned char __fastcall__ tmp_open(unsigned char mode)
{
    unsigned char h;
    vr_cd(VR_DATA);
    strcpy(line + 180, "GEMINI.TMP");
    h = FOpen(line + 180, mode);
    ChDir((char *)curDirName);
    return h < 2 || h > 4 ? 0 : h;
}

static void tmp_delete(void)
{
    vr_cd(VR_DATA);
    strcpy(line + 180, "GEMINI.TMP");
    FDelete(line + 180);
    ChDir((char *)curDirName);
}

/* palette rows 2 (the picture's 16 colours) and 15 (the paper) */
static void prows(void)
{
    unsigned char i, a, b;
    vport(0, 1, 0xFA00);                /* (entry 0, the paper) */
    a = VD0;
    b = VD0;
    vport(0, 1, 0xFA40);
    for (i = 0; i < 16; ++i) {
        VD0 = (unsigned char)ppal[i];
        VD0 = ppal[i] >> 8;
    }
    vport(0, 1, 0xFBE0);
    for (i = 0; i < 16; ++i) {
        VD0 = a;
        VD0 = b;
    }
}

/* the window's chrome, the page's area clear, the toolbar's Save */
static void chrome(void)
{
    strcpy(line, appname);
    strcat(line, ": ");
    strcat(line, title);
    win_all(line);
    toolbar();
    dispBufferOn = ST_WR_FORE;
    SetPattern(0);
    WRectangle(0, BODYY, 639, BODYY + TRACK * 8 - 1);
}

/* the picture's file read again: its header, its place, the decoder; 0 */
static unsigned char start(void)
{
    if (png_h)                          /* (drawn again: Alt+Tab) */
        FClose(png_h);
    png_h = tmp_open('r');
    if (!png_h)
        return PE_DATA;
    ov5(png_open_v);
    if (u_ret)
        return u_ret;
    png_plan();
    prows();
    ov5(png_start);
    viewing = 1;                        /* (1 drawing, 2 shown) */
    mouseOn &= ~SET_MENUON;             /* (no menus while the back screen is the decoder's) */
#ifdef GEMINI_TEST
    t_pic = ser_frames;
#endif
    tshow = ser_frames;
    return 0;
}

/* the viewer gone: tile mode off, the chrome again (the page: ui.c's) */
static void off(void)
{
    if (png_h)
        FClose(png_h);
    png_h = 0;
    mouseOn |= SET_MENUON;
    ColorRect(0, 80, 0, 60, 0xFF);
    viewing = 0;
    tmp_delete();
    strcpy(line, appname);
    strcat(line, ": ");
    strcat(line, title);
    win_all(line);
    toolbar();
}

/* (ui.c's g_first: another page) */
void i_off(void)
{
    if (viewing)
        off();
}

static const char *const why[] = { "", "", "This is not a PNG picture.", "The picture is damaged.",
    "Interlaced PNG pictures are not shown here:", "The picture is too big to be shown here:" };

/* a failed picture: its box, the viewer gone */
static void __fastcall__ failed(unsigned char e)
{
#ifdef GEMINI_TEST
    strcpy(line, "GE PIC ERROR ");
    unum(line + 13, e);
    strcat(line, " ");
    unum(line + strlen(line), oy_done);
    strcat(line, " ");
    unum(line + strlen(line), viewing);
    gt_log(line);
#endif
    off();
    message(why[e], e >= PE_INTERLACE ? "save it (File > Download)." : "");
}

/* (ui.c's follow) a picture link, go resolved: u_ret 2 show, 1 save, 0 */
void i_link(void)
{
    unsigned char r;
    u_ret = 2;
    if (!retkey)
        return;
    strcpy(line + 52, "Yes: show it, No: save it to /DOCUMENTS,");
    strcpy(line + 100, "Cancel: neither.");
    strcpy(line, "The picture ");
    r = box3(go);
    u_ret = r == YES ? 2 : r == NO ? 1 : 0;
}

/* (ui.c's ui_done) the picture's fetch ended: shown; u_ret 1: save it
   instead (too big) */
void i_done(void)
{
    unsigned char e;
    unsigned int n;
    u_ret = 0;
    if (gerr == GE_LOCAL && pic_big) {
        pic_big = 0;
        tmp_delete();
        strcpy(line, "The picture is larger than ");
        unum(line + strlen(line), pic_kb);
        strcat(line, " KB (the limit).");
        if (yesno(line, "Save it to /DOCUMENTS instead?"))
            u_ret = 1;
        return;
    }
    if (gerr != GE_OK) {
        tmp_delete();
        if (gerr == GE_CANCEL)
            pstatus("Stopped.");
        else
            ov3(u_fail);
        return;
    }
    viewing = 1;                        /* (1 drawing, 2 shown) */
    pic_redo = 0;                       /* (an Alt+Tab before this picture: not its) */

    vport(1, 1, 0xFA40);                /* palette entries 32-255 kept at $12C00 */
    vport(0, 1, 0x2C00);
    for (e = 0; e < 224; ++e) {
        VD0 = VD1;
        VD0 = VD1;
    }
    ColorRect(0, 80, 0, 60, COLOR_TILES);
    vport(0, 1, 0x3000);                /* tiles 0-15: solid */
    for (e = 0, n = 0; n < 16 * 32; ++n) {
        VD0 = e;
        if ((n & 31) == 31)
            e += 0x11;
    }
    chrome();
    e = start();
    if (e)
        failed(e);
    else
        pstatus("Drawing the picture ...");
    u_ret = 0;                          /* (png_open_v's: not "save it instead") */
}

/* the main loop's pass, while a picture comes or is shown */
void i_tick(void)
{
    unsigned char e;
    if (gbusy && gdl != 2) {            /* (something else began) */
        i_off();
        return;
    }
    if (gbusy) {                        /* its size once IHDR has come */
        if (grx >= 24 && !strchr(xf_name, 'x') && !memcmp(pic_head + 12, "IHDR", 4)) {
            strcpy(xf_name, "the picture (PNG ");
            unum(xf_name + strlen(xf_name), ((unsigned int)pic_head[18] << 8) | pic_head[19]);
            strcat(xf_name, " x ");
            unum(xf_name + strlen(xf_name), ((unsigned int)pic_head[22] << 8) | pic_head[23]);
            strcat(xf_name, ")");
        }
        return;
    }
    if (!viewing)
        return;
    if (pic_redo) {                     /* (back from Alt+Tab: the palette rows, the drawing again) */
        pic_redo = 0;
        prows();
        if (viewing == 1) {
            e = start();
            if (e) {
                failed(e);
                return;
            }
        }
    }
    if (viewing != 1)
        return;
    png_frames = 2;
    ov5(png_step_v);
    e = u_ret;
    if (!e) {
        if (ser_frames - tshow > 30) {
            tshow = ser_frames;
            strcpy(msg, "Drawing the picture: row ");
            unum(msg + strlen(msg), oy_done);
            strcat(msg, " of ");
            unum(msg + strlen(msg), poh);
            pstatus(msg);
        }
        return;
    }
    if (e != 1) {
        failed(e);
        return;
    }
    FClose(png_h);
    png_h = 0;
    viewing = 2;
    WImprintRectangle(0, 0, 639, 479);  /* (menus and boxes come back from the back screen) */
    mouseOn |= SET_MENUON;
    strcpy(msg, "PNG ");
    unum(msg + 4, pw);
    strcat(msg, " x ");
    unum(msg + strlen(msg), ph);
    strcat(msg, ", shown at ");
    unum(msg + strlen(msg), pow_);
    strcat(msg, " x ");
    unum(msg + strlen(msg), poh);
    strcat(msg, ". Esc: the page; Save keeps it.");
    pstatus(msg);
#ifdef GEMINI_TEST
    strcpy(line, "GE PIC SHOWN ");
    unum(line + 13, ser_frames - t_pic);
    gt_log(line);
#endif
}

/* Save: the file to /DOCUMENTS (named by the URL) */
static void save(void)
{
    unsigned char s, d;
    unsigned int n;
    if (viewing != 2) {
        pstatus("Wait: the picture is not drawn yet.");
        return;
    }
    ov3(u_name);
    if (xf_exists(xf_name)) {
        strcpy(line, xf_name);
        strcat(line, " is in /DOCUMENTS already.");
        if (!yesno(line, "Replace it?"))
            return;
    }
    s = tmp_open('r');
    ChDir((char *)curDirName);
    strcpy(line + 150, xf_name);
    d = FOpen(line + 150, 'w');
    if (d < 2 || d > 4)
        d = 0;
    if (s && d)
        while ((n = FRead(s, ln, 256)) != 0 && !FWrite(d, ln, n))
            ;
    if (s)
        FClose(s);
    if (d)
        FClose(d);
    strcpy(msg, d && s ? "Saved to /DOCUMENTS: " : "Not saved: ");
    strcat(msg, xf_name);
    pstatus(msg);
}

/* the viewer's keys: Esc, Backspace, Left: the page; S, Ctrl+S: save */
void i_key(void)
{
    unsigned char k = keyData;
    if (k == KEY_ESC || k == 8 || (k == KEY_LEFT && (keyDataMods & KEYM_ARROW)))
        off();
    else if (k == 's' || k == 'S' || k == 19)
        save();
}

/* the viewer's clicks: the toolbar's Back (the page), Save (Go's place) */
void i_press(void)
{
    unsigned int x = mouseXPos >> 3, y = mouseYPosW;
    if (mouseData & 0x80 || y < TOOLY || y >= TOOLY + 14)
        return;
    if (x >= BX && x < BX + 3)
        off();
    else if (x >= GOX && x < GOX + 6)
        save();
}
