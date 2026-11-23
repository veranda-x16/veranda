/* Veranda Gemini: the toolbar (Veranda Gopher's): Back and Forward, Home,
   the address line, Go (Stop, Save); in overlay 6 with the window's
   chrome since V149 (main RAM's room: main.c's field and toolbar map it).

   MIT licence (see LICENSE). */
#include <veranda.h>
#include <string.h>
#include "gemini.h"
#pragma code-name ("OVERLAY6")
#pragma rodata-name ("OVL6RO")

/* a control's frame (Sunroom, V149: square, its corners' pixels cut) */
static void __fastcall__ rframe(unsigned int l, unsigned int t, unsigned int r, unsigned int b)
{
    WHorizontalLine(0xFF, l + 1, r - 1, t);
    WHorizontalLine(0xFF, l + 1, r - 1, b);
    WVerticalLine(0xFF, l, t + 1, b - 1);
    WVerticalLine(0xFF, r, t + 1, b - 1);
}

void field6(void)
{
    unsigned char o = 0;
    if (!v_edit) {
        strcpy(abuf, gbusy && !gdl ? go : cur);
        alen = strlen(abuf);
    }
    if (alen > FW - 2)
        o = v_edit ? alen - (FW - 2) : 0;
    put(FX + 1, TOOLY + 4, abuf + o, FW - 2, 0);
    if (v_edit)
        put(FX + 1 + alen - o, TOOLY + 4, fresh ? "" : " ", fresh ? 0 : 1, 1);
    if (v_edit && fresh)
        put(FX + 1, TOOLY + 4, abuf, alen > FW - 2 ? FW - 2 : alen, 1);
}

void toolbar6(void)
{
    unsigned int x;
    const char *t = gbusy ? "Stop" : viewing ? "Save" : "Go";
    SetPattern(0);
    WRectangle(0, TOOLY, 639, TOOLY + 14);
    glyph(BX * 8 + 6, TOOLY, G_BACK, 15, hpos ? 0 : GL_DIM);
    glyph(BX * 8 + 30, TOOLY, G_FWD, 15, hpos + 1 < hn ? 0 : GL_DIM);
    glyph(HOMEX * 8 + 6, TOOLY, G_HOME, 15, 0);
    rframe(BX * 8, TOOLY + 1, BX * 8 + 47, TOOLY + 13);
    WVerticalLine(0xFF, BX * 8 + 24, TOOLY + 1, TOOLY + 13);
    rframe(HOMEX * 8, TOOLY + 1, HOMEX * 8 + 23, TOOLY + 13);
    rframe(FX * 8, TOOLY + 1, (FX + FW) * 8 - 1, TOOLY + 13);
    rframe(GOX * 8, TOOLY + 1, GOX * 8 + 47, TOOLY + 13);
    field6();
    UseFont(FONT_UI);
    currentMode = SET_BOLD;
    strcpy(line, t);
    for (x = 0; *t; ++t)
        x += GetCharWidth(*t) + 1;
    WPutString(line, GOX * 8 + 24 - (x >> 1), TOOLY + 3 + baselineOffset);
    currentMode = 0;
    UseSystemFont();
}
