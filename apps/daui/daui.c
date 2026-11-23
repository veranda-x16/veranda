/* daui: the desk accessories' toolkit (daui.h). MIT licence (see LICENSE). */
#include <veranda.h>
#include <string.h>
#include <theme.h>
#include <vrpath.h>
#include <vrwin.h>
#include <vralert.h>
#include "daui.h"

unsigned char ui_accent = C_BLUE, ui_sel = C_BLUE;
unsigned int ui_x0, ui_y0, ui_w, ui_h;
unsigned char ui_tall;
unsigned int ui_px, ui_py;

unsigned int __fastcall__ ui_strw(const char *s)
{
    unsigned int w = 0;
    while (*s)
        w += GetCharWidth(*s++);
    return w;
}

void ui_clear(unsigned int x, unsigned int y, unsigned int w, unsigned int h)
{
    SetPattern(0);
    WRectangle(x, y, x + w - 1, y + h - 1);
}

void ui_color(unsigned int x, unsigned int y, unsigned int w, unsigned int h, unsigned char c)
{
    ColorRect(x >> 3, w >> 3, y >> 3, h >> 3, c);
}

void ui_frame(unsigned int x, unsigned int y, unsigned int w, unsigned int h)
{
    WFrameRectangle(0xFF, x, y, x + w - 1, y + h - 1);
}

void ui_text(const char *s, unsigned int x, unsigned int y)
{
    WPutString((void *)s, x, y);
}

/* s clipped to w pixels (its head) */
static char clip[64];

void ui_textw(const char *s, unsigned int x, unsigned int y, unsigned int w)
{
    unsigned char n = 0;
    unsigned int t = 0, cw;
    while (s[n] && n < sizeof clip - 1) {
        cw = GetCharWidth(s[n]);
        if (t + cw > w)
            break;
        t += cw;
        clip[n] = s[n];
        ++n;
    }
    clip[n] = 0;
    WPutString(clip, x, y);
}

void ui_textc(const char *s, unsigned int x, unsigned int w, unsigned int y)
{
    unsigned int t = ui_strw(s);
    if (t > w)
        ui_textw(s, x, y, w);
    else
        WPutString((void *)s, x + (w - t) / 2, y);
}

void ui_bold(const char *s, unsigned int x, unsigned int y)
{
    currentMode = SET_BOLD;
    WPutString((void *)s, x, y);
    currentMode = 0;
}

/* the theme, and Look 2's palette (DECISIONS V74; an accessory's palette
   entries 0-15 are put back with the application: V31, V33) */
void ui_theme(void)
{
    theme_load();
    theme_palette();
    ui_accent = theme.accent ? theme.accent : C_BLUE;
    ui_sel = theme.hilite ? theme.hilite : SELECT;
}

/* the window: the SDK's window chrome (vrwin.h, DECISIONS V79): a frame,
   the title band (the theme's accent, the title bold in the UI font, the
   close glyph at the right), the shadow (right and below: one card of the
   shadow's colour with Look 2's palette, V126; else a dither) */
void ui_window(const char *title, unsigned int w, unsigned int h)
{
    static struct vrwin win;
    ui_theme();
    theme_menus();                      /* (V79: its dialog boxes in the UI font) */
    ui_tall = screenHeight >= 400;
    ui_w = w;
    ui_h = h;
    ui_x0 = ((screenWidth - w) / 2) & ~7;
    ui_y0 = ((screenHeight - h) / 2) & ~7;
    dispBufferOn = ST_WR_FORE;          /* the application's screen is put aside whole */
    win.x = ui_x0 >> 3;
    win.y = ui_y0 >> 3;
    win.w = w >> 3;
    win.h = h >> 3;
    /* (V148, Sunroom) the 3-pixel shadow (vrwin.h) in light mode; none in
       dark mode, where the ink is light and a shadow would glow */
    win.flags = VW_CLOSE | VW_FRAME | (theme.dark ? 0 : VW_SHADOW);
    vr_win(&win, title);
}

/* (V148, Sunroom) a button as the dialog boxes' (the kernel's OK, Cancel):
   a frame with its corners cut, the label centred */
void ui_button(unsigned int x, unsigned int y, unsigned int w, const char *label, unsigned char c)
{
    unsigned int r = x + w - 1, b = y + UI_BH - 1;
    ui_clear(x, y, w, UI_BH);
    ui_color(x, y, w, UI_BH, c);
    WFrameRectangle(0xFF, x, y, r, b);
    WDrawPoint(DRAW_ERASE, x, y);
    WDrawPoint(DRAW_ERASE, r, y);
    WDrawPoint(DRAW_ERASE, x, b);
    WDrawPoint(DRAW_ERASE, r, b);
    ui_textc(label, x + 2, w - 4, y + 11);
}

unsigned char ui_press(void)
{
    if (mouseData & 0x80)
        return 0;
    ui_px = mouseXPos;
    ui_py = mouseYPosW;
    return 1;
}

unsigned char ui_in(unsigned int x, unsigned int y, unsigned int w, unsigned int h)
{
    return ui_px >= x && ui_px < x + w && ui_py >= y && ui_py < y + h;
}

unsigned char ui_closebox(void)
{
    return ui_in(ui_x0 + ui_w - 20, ui_y0 + 1, 16, 14);   /* (the close glyph at the right, V79) */
}

/*---------------------------------------------------------------
  fields
 ---------------------------------------------------------------*/
void ui_field(const struct field *f, unsigned char focus)
{
    const char *s = f->buf;
    unsigned int tw = f->w - 8;
    ui_clear(f->x, f->y, f->w, UI_BH);
    WFrameRectangle(0xFF, f->x, f->y, f->x + f->w - 1, f->y + UI_BH - 1);
    if (focus) {
        WFrameRectangle(0xFF, f->x + 1, f->y + 1, f->x + f->w - 2, f->y + UI_BH - 2);
        while (*s && ui_strw(s) > tw - 2)      /* the tail, if it is long */
            ++s;
    }
    ui_textw(s, f->x + 4, f->y + 11, tw);
    if (focus) {
        unsigned int cx = f->x + 4 + ui_strw(s);
        if (cx > f->x + f->w - 4)
            cx = f->x + f->w - 4;
        WVerticalLine(0xFF, cx, f->y + 3, f->y + UI_BH - 4);
    }
}

unsigned char ui_field_key(const struct field *f, unsigned char c)
{
    unsigned char n = strlen(f->buf);
    if (c == 8 && !(keyDataMods & KEYM_ARROW)) {
        if (!n)
            return 0;
        f->buf[n - 1] = 0;
        return 1;
    }
    if (c < 32 || c > 126 || n >= f->max)
        return 0;
    f->buf[n] = c;
    f->buf[n + 1] = 0;
    return 1;
}

/*---------------------------------------------------------------
  boxes
 ---------------------------------------------------------------*/
/* (V148) Sunroom's alerts (the SDK's vralert.h): the accessory's icon
   (vr_alert_icon, which the accessory sets), the headline a in bold, the
   explanation b */
void ui_msg(const char *a, const char *b)
{
    vr_alert(VA_OK, a, b);
}

unsigned char ui_ask(const char *a, const char *b)
{
    return vr_alert(VA_YESNO, a, b) == YES;
}

char *ui_put(char *p, const char *s)
{
    while (*s)
        *p++ = *s++;
    *p = 0;
    return p;
}

char *ui_num(char *p, unsigned int n, unsigned char digits)
{
    char t[6];
    unsigned char k = 0;
    do {
        t[k++] = '0' + n % 10;
        n /= 10;
    } while (n);
    while (k < digits)
        t[k++] = '0';
    while (k)
        *p++ = t[--k];
    *p = 0;
    return p;
}

/*---------------------------------------------------------------
  the system folder
 ---------------------------------------------------------------*/
void sys_enter(void)
{
    vr_cd(VR_DATA);                     /* /VERANDA/.SYSTEM (vrpath.h, V71) */
}

void sys_leave(void)
{
    if (curDirName[0] != '/' || ChDir((void *)curDirName))
        ChDir("/");
}

/* a page with a corner turned down: the icon of the files written here */
static const unsigned char icon[64] = {
    0xBF,
    0x3F, 0xFC, 0x00,  0x20, 0x06, 0x00,  0x20, 0x05, 0x00,  0x20, 0x04, 0x80,
    0x20, 0x07, 0xC0,  0x20, 0x00, 0x40,  0x27, 0xFC, 0x40,  0x20, 0x00, 0x40,
    0x27, 0xFC, 0x40,  0x20, 0x00, 0x40,  0x27, 0xFC, 0x40,  0x20, 0x00, 0x40,
    0x27, 0xFC, 0x40,  0x20, 0x00, 0x40,  0x20, 0x00, 0x40,  0x20, 0x00, 0x40,
    0x20, 0x00, 0x40,  0x20, 0x00, 0x40,  0x20, 0x00, 0x40,  0x3F, 0xFF, 0xC0,
    0x00, 0x00, 0x00
};

static unsigned char blk[256];          /* the CVT file's head; record files' info block */
static char path[48];

static unsigned char cvt_head(unsigned char h, const char *name, const char *cls,
                              const char *desc, unsigned int len, unsigned char vlir,
                              unsigned char type)
{
    unsigned int b;
    unsigned char n = strlen(name), e;
    /* the entry: USR, the name padded with $A0, the type, the date, the
       size in blocks (+ 1: the info block) */
    memset(blk, 0, 254);
    blk[0] = 0x83;
    memset(blk + 3, 0xA0, 16);
    memcpy(blk + 3, name, n);
    blk[21] = vlir;
    blk[22] = type;
    memcpy(blk + 23, (void *)0x054F, 5);         /* year ... minutes */
    b = len / 254 + (len % 254 != 0) + 1;
    blk[28] = b;
    blk[29] = b >> 8;
    strcpy((char *)blk + 30, "PRG formatted GEOS file V1.0");
    FWrite(h, blk, 254);
    /* the info block from its byte 2 */
    memset(blk, 0, 254);
    blk[0] = 3;
    blk[1] = 21;
    memcpy(blk + 2, icon, 64);
    blk[66] = 0x83;
    blk[67] = type;
    blk[68] = vlir;
    blk[71] = len;
    blk[72] = len >> 8;
    strcpy((char *)blk + 75, cls);
    strcpy((char *)blk + 95, "Veranda");
    strcpy((char *)blk + 158, desc);
    e = FWrite(h, blk, 254);
    return e;
}

unsigned char sys_write(const char *name, const char *cls, const char *desc,
                        const void *data, unsigned int len)
{
    static const char *const dirs[3] = { VR_DATAPATH, VR_SYSPATH, VR_ROOTPATH };
    unsigned char h, e, d;
    sys_enter();                        /* (.SYSTEM made when it is missing) */
    sys_leave();
    for (d = 0; d < 3; ++d) {
        *ui_put(ui_put(ui_put(path, dirs[d]), name), ".cvt") = 0;
        h = FOpen(path, 'w');
        if (h >= 2 && h <= 9 && dosStatus < 20)
            break;
        h = 0;
    }
    if (!h)
        return DOS_ERROR;
    e = cvt_head(h, name, cls, desc, len, 0, SYSTEM);
    if (!e && len)
        e = FWrite(h, (void *)data, len);
    if (FClose(h) && !e)
        e = DOS_ERROR;
    return e;
}

unsigned char ui_rec_busy(void)
{
    return RecordInfo(0, blk) == 0;
}

unsigned char ui_rec_open(const char *name, const char *cls, const char *desc)
{
    unsigned char e = OpenRecordFile((void *)name), i;
    if (e != FILE_NOT_FOUND)
        return e;
    /* a new record file of none (SaveFile's info block: as fileHeader) */
    memset(blk, 0, sizeof blk);
    blk[0] = (unsigned int)name & 255;
    blk[1] = (unsigned int)name >> 8;
    blk[2] = 3;
    blk[3] = 21;
    memcpy(blk + 4, icon, 64);
    blk[68] = 0x83;
    blk[69] = APPL_DATA;
    blk[70] = 1;                        /* VLIR */
    strcpy((char *)blk + O_GHFNAME, cls);
    strcpy((char *)blk + O_GH_AUTHOR, "Veranda");
    strcpy((char *)blk + O_GHINFO_TXT, desc);
    i = SaveFile(blk, 0);
    if (i)
        return i;
    return OpenRecordFile((void *)name);
}
