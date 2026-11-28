/* gate edit: Veranda Edit's test build (apps/edit with EDIT_TEST, this
   file, tests/edit_play.s and tests/tk_hash.s). test_start (main RAM)
   reads the session, EDIT.PLY (tests/edit_script.py writes it), into
   overlay 4's bank from $B000 and starts the player; the rest is in
   overlay 4 (the test
   build's alone: misc.c's call4 maps it, V215), its arguments in main
   RAM: test_log_state is the player's 'L': the state on the console as
   "EDIT STATE n line col len lines modified lo hi top eol name"; the
   clock (the emulator's cycle counter) around a load, a save, a key and
   its drawing: "TIME what cycles"; 'L' $80 + n (V215): the window as the
   steps drew it against a full drawing (view_all), each text row's
   bitmap and colour map hashed: "EDIT REDRAW n rows first" (the rows
   unlike, the first of them).

   MIT licence (see LICENSE). */
#include <string.h>
#include "../apps/edit/edit.h"

extern unsigned char play_bank;
extern unsigned int play_cur;
void play_go(void);

unsigned char test_log;
extern unsigned char dragging;
unsigned char *const test_dragging = &dragging;
static char line[136];                  /* (main RAM: the kernel reads it; 132 at most) */
unsigned char t_arg;                    /* call4's arguments */
const char *t_what;
unsigned int t_col;

/* the script in overlay 4's bank, after the code (V215: the test build
   takes no bank more than it did, so HUGE.TXT still fits) */
void test_start(void)
{
    unsigned char h;
    h = FOpen("EDIT.PLY", 'r');
    if (h < 2) {
        LogText("EDIT NO SCRIPT");
        return;
    }
    MAPBANK(bank4);
    FRead(h, (void *)0xB000, 4096);
    MAPBANK(bank1);
    FClose(h);
    play_bank = bank4;
    play_cur = 0xB000;
    play_go();
}

/* the redraw check: the window as the steps drew it, then drawn whole
   (main RAM: with overlay 1 mapped, the caller's) */
void test_redraw(void)
{
    view_cursor(0);
    call4(test_redraw_a);
    view_all();
    view_cursor(0);
    call4(test_redraw_b);
}

#pragma code-name (push, "OVERLAY4")
#pragma bss-name (push, "OVL4BSS")

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

/* (t_col: view_col's, overlay 1's) */
void test_log_state(void)
{
    char *p = line;
    unsigned char n = test_log;
    test_log = 0;
    memcpy(p, "EDIT STATE ", 11);
    p += 11;
    p = hexn(p, n);
    p = hexn(p, cur_line + 1);
    p = hexn(p, t_col + 1);
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

/* (t_what: what) */
void test_clock_log(void)
{
    unsigned long a, b;
    unsigned char c[4];
    char *p = line;
    const char *what = t_what;
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
   cycles" (t_arg: the key) */
static unsigned char armed;

void test_key(void)
{
    unsigned char k = t_arg;
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
    t_what = w;
    test_clock_log();
}

/* the redraw check (V215): tests/tk_hash.s hashed the rows as the steps
   drew them (test_hash 0), then as view_all drew them (test_hash 1) */
static char *dec(char *p, unsigned char v)
{
    if (v >= 100)
        *p++ = '0' + v / 100;
    if (v >= 10)
        *p++ = '0' + v / 10 % 10;
    *p++ = '0' + v % 10;
    *p++ = ' ';
    return p;
}

void test_redraw_a(void)
{
    test_hash(0);
}

void test_redraw_b(void)
{
    char *p = line;
    test_hash(1);
    memcpy(p, "EDIT REDRAW ", 12);
    p = dec(p + 12, test_log & 0x7F);
    p = dec(p, test_hbad);
    p = dec(p, test_hfirst);
    *p = 0;
    LogText(line);
    test_log = 0;
}

#pragma bss-name (pop)
#pragma code-name (pop)
