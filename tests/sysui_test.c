/* gates disktools and about (DECISIONS V119): what both test builds share.
   snap(name): the screen as gate ftp's tests/ftp_play.c writes it (the
   foreground's 480 rows of 80 bytes, the cards' paper colours, 60 rows of
   80, the palette's 16 entries) to the card's top folder: tools' ftp_shot.py
   makes it a PNG. t_session: the first word of the session file (NAME.TST
   in the top folder). t_say: a line on the console. t_end: "<pfx> END",
   VRAM dumped (the emulator's -dump: dump.bin), the emulator stopped.
   MIT licence (see LICENSE). */
#include <veranda.h>
#include <string.h>
#include "../apps/sysui/sysui.h"

void term_dump(void);

char t_session[16];
char t_arg[48];
extern char ui_tl[140];                 /* (sysui.c's: one test log line for all) */
#define tl ui_tl
static unsigned char row[80];

void __fastcall__ t_say(const char *s)
{
    strncpy(tl, s, sizeof tl - 1);
    LogText(tl);
}

void __fastcall__ t_say2(const char *a, const char *b)
{
    strncpy(tl, a, sizeof tl - 1);
    strncat(tl, b, sizeof tl - 1 - strlen(tl));
    LogText(tl);
}

void __fastcall__ t_saynum(const char *a, unsigned long v)
{
    char n[12];
    ui_num(n, v);
    t_say2(a, n);
}

/* the session file: its first word, then the rest of the line */
void __fastcall__ t_read(const char *name)
{
    unsigned char h, n, i;
    strcpy(tl, VR_ROOTPATH);
    strcat(tl, name);
    h = FOpen(tl, 'r');
    t_session[0] = t_arg[0] = 0;
    if (h < 2 || h > 4)
        return;
    n = FRead(h, tl, 60);
    FClose(h);
    tl[n] = 0;
    for (i = 0; i < n && tl[i] > ' ' && i < sizeof t_session - 1; ++i)
        t_session[i] = tl[i];
    t_session[i] = 0;
    while (tl[i] == ' ')
        ++i;
    for (n = 0; tl[i] >= ' ' && n < sizeof t_arg - 1; ++i)
        t_arg[n++] = tl[i];
    t_arg[n] = 0;
}

void __fastcall__ snap(const char *name)
{
    unsigned char h, keep = dispBufferOn, x, y, i;
    unsigned int r;
    strcpy(tl, VR_ROOTPATH);
    strcat(tl, name);
    h = FOpen(tl, 'w');
    if (h < 2 || h > 4) {
        t_say2("SNAP FAILED ", name);
        return;
    }
    dispBufferOn = ST_WR_FORE;
    for (r = 0; r < 480; ++r) {
        ReadRow(row, 0, 80, r);
        FWrite(h, row, 80);
    }
    for (y = 0; y < 60; ++y) {
        for (x = 0; x < 80; ++x)
            row[x] = GetCardColor(x, y);
        FWrite(h, row, 80);
    }
    asm("sei");
    *(volatile unsigned char *)0x9F25 &= 0xFE;      /* ADDRSEL 0 */
    *(volatile unsigned char *)0x9F20 = 0x00;       /* $1FA00, step 1 */
    *(volatile unsigned char *)0x9F21 = 0xFA;
    *(volatile unsigned char *)0x9F22 = 0x11;
    for (i = 0; i < 32; ++i)
        row[i] = *(volatile unsigned char *)0x9F23;
    asm("cli");
    FWrite(h, row, 32);
    FClose(h);
    dispBufferOn = keep;
    t_say2("SNAP ", name);
}

void __fastcall__ t_end(const char *pfx)
{
    t_say2(pfx, " END");
    term_dump();
}
