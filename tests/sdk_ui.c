/* gate sdk: a C program with a menu and a dialog box, played by a script
   (tests/sdk_play.s): a press on the menu's "box" item runs box() after the
   flash; it opens a dialog box, the script types A, B, Backspace, C into
   its field and presses its OK icon (not Return), box() logs the result and
   the field's text, which must be "AC" ended by its 0 (V39) although the
   buffer held "XXXXXXXX" before; then it redraws the menu. Then a press
   where the OK icon was must reach otherPressVec: the box gave the menus
   and icons back (DECISIONS V40: it kept only the first byte of their 147,
   so its own icons stayed and the press flashed the gone OK icon and
   closed a box that was not there). */
#include <veranda.h>

extern void __fastcall__ vr_play(const void *script);

struct item { const char *text; unsigned char type; void (*fn)(void); };
struct menu { unsigned char top, bottom; unsigned int left, right; unsigned char flags; struct item items[1]; };

static void box(void);

static const struct menu bar = { 0, 14, 0, 80, HORIZONTAL | UN_CONSTRAINED | 1, { { "box", MENU_ACTION, box } } };

static const unsigned char dlg[] = {
    DEF_DB_POS | 1,
    DBTXTSTR, TXT_LN_X, TXT_LN_2_Y, 0, 0,       /* the text's address below */
    DBGETSTRING, TXT_LN_X, TXT_LN_3_Y, 0x0E, 8, /* r6: the field */
    OK, DBI_X_0, DBI_Y_2,
    0
};
static unsigned char table[sizeof dlg];
static const char text[] = "From C.";
static char done[24] = "C DIALOG 01 ";
static const char other[] = "C DIALOG ??";
static char field[9];
static const char after[] = "C PRESS AFTER THE BOX";

/* frame, x, y (low byte) | flags << 8 (bit 0 the button, bit 6 y + 256) */
static const unsigned int script[] = {
    0, 320, 240,
    10, 10, 7,
    11, 10, 7 | 0x100,          /* press "box" */
    13, 10, 7,
    40, 'A', 0x8000,            /* keys into the field (flags bit 7) */
    44, 'B', 0x8000,
    48, 0x14, 0x8000,           /* Backspace */
    52, 'C', 0x8000,
    60, 240, 16 | 0x4000,       /* the OK icon at y 272 (the box centred at */
    61, 240, 16 | 0x4100,       /* 640x480): y 16 + 256 (flags bit 6) */
    63, 240, 16 | 0x4000,
    90, 240, 16 | 0x4000,       /* where the OK icon was */
    91, 240, 16 | 0x4100,
    93, 240, 16 | 0x4000,
    0xFFFF, 140, 0
};

static void pressed(void)
{
    if (!(mouseData & 0x80))
        LogText((void *)after);
}

static void box(void)
{
    unsigned char r, i;
    for (i = 0; i < 8; ++i)
        field[i] = 'X';
    field[0] = 0;
    field[8] = 0;
    r6 = (unsigned int)field;
    r = DoDlgBox(table);
    for (i = 0; field[i] && i < 8; ++i)
        done[12 + i] = field[i];
    done[12 + i] = 0;
    LogText((void *)(r == OK ? done : other));
    otherPressVec = (unsigned int)pressed;
    ReDoMenu();
}

int main(void)
{
    unsigned char i;
    for (i = 0; i < sizeof dlg; ++i)
        table[i] = dlg[i];
    table[4] = (unsigned int)text & 255;
    table[5] = (unsigned int)text >> 8;
    SetPattern(2);
    WRectangle(0, 0, 639, 479);
    DoMenu((void *)&bar, 0);
    vr_play(script);
    return 0;
}
