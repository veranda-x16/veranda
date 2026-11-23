/* gate edit: Veranda Edit's test build (apps/edit with EDIT_TEST, this
   file and tests/edit_play.s; in main RAM). test_start reads the session,
   EDIT.PLY (tests/edit_script.py writes it), into a RAM bank and starts
   the player; test_log_state is the player's 'L': the state on the
   console as "EDIT STATE n line col len lines modified lo hi top eol
   name"; the clock (the emulator's cycle counter) around a load, a save,
   a key and its drawing: "TIME what cycles".

   MIT licence (see LICENSE). */
#include <string.h>
#include "../apps/edit/edit.h"

extern unsigned char play_bank;
void play_go(void);

unsigned char test_log;
extern unsigned char dragging;
unsigned char *const test_dragging = &dragging;
static char line[160];
static unsigned char clk[4];
static const char hex[] = "0123456789ABCDEF";

static char *hexn(char *p, unsigned long v)
{
    unsigned char i;
    for (i = 8; i-- > 0;)
        *p++ = hex[(v >> (i * 4)) & 15];
    *p++ = ' ';
    return p;
}

void test_start(void)
{
    unsigned char h, b;
    b = BankAlloc(1);
    h = FOpen("EDIT.PLY", 'r');
    if (h < 2 || !b) {
        LogText("EDIT NO SCRIPT");
        return;
    }
    MAPBANK(b);
    FRead(h, (void *)0xA000, 8192);
    MAPBANK(bank1);
    FClose(h);
    play_bank = b;
    play_go();
}

void test_log_state(void)
{
    char *p = line;
    unsigned char n = test_log;
    test_log = 0;
    memcpy(p, "EDIT STATE ", 11);
    p += 11;
    p = hexn(p, n);
    p = hexn(p, cur_line + 1);
    p = hexn(p, view_col() + 1);
    p = hexn(p, gb_len);
    p = hexn(p, nlines);
    p = hexn(p, modified);
    p = hexn(p, sel_lo());
    p = hexn(p, sel_hi());
    p = hexn(p, top_line);
    p = hexn(p, eol);
    strncpy(p, docname, 30);
    p[30] = 0;
    LogText(line);
}

void test_clock_reset(void)
{
    clk[0] = *(volatile unsigned char *)0x9FB8;
    clk[1] = *(volatile unsigned char *)0x9FB9;
    clk[2] = *(volatile unsigned char *)0x9FBA;
    clk[3] = *(volatile unsigned char *)0x9FBB;
}

void test_clock_log(const char *what)
{
    unsigned long a, b;
    unsigned char c[4];
    char *p = line;
    c[0] = *(volatile unsigned char *)0x9FB8;
    c[1] = *(volatile unsigned char *)0x9FB9;
    c[2] = *(volatile unsigned char *)0x9FBA;
    c[3] = *(volatile unsigned char *)0x9FBB;
    memcpy(&a, clk, 4);
    memcpy(&b, c, 4);
    memcpy(p, "TIME ", 5);
    p += 5;
    while (*what)
        *p++ = *what++;
    *p++ = ' ';
    p = hexn(p, b - a);
    *p = 0;
    LogText(line);
}

/* a key typed ('x'), a page (PgDn), a line (Down at the window's last
   row: the view scrolls): from the key to its drawing done, "TIME KEYxx
   cycles" */
static unsigned char armed;

void __fastcall__ test_key(unsigned char k)
{
    if (k == 'x' || k == 'y' || k == KEY_PGDN || (k == KEY_DOWN && (keyDataMods & KEYM_ARROW))) {
        armed = k;
        test_clock_reset();
    }
}

void test_drawn(void)
{
    static char w[6] = "KEYxx";
    if (!armed)
        return;
    w[3] = hex[armed >> 4];
    w[4] = hex[armed & 15];
    armed = 0;
    test_clock_log(w);
}
