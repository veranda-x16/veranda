/* gate about (DECISIONS V119): About this X16's test build (apps/about,
   make test: AB_TEST). AB.TST in the top folder names the session:
     host     the values (logged "AB <label>=<value>" at every Refresh), a
              second of live updates, Copy (the clipboard), Ask the modem
              with no card, a screenshot (ABOUT.RAW), then Alt+Tab
              (TaskCtl TASK_ASIDE): the test desktop (tests/about_desk.c)
              starts a helper that puts itself aside too, then brings this
              back: Refresh again (the helper among the programs aside), the
              end
     plain    the values, the end (2 MB, an SD card image)
     modem    Ask the modem (the emulator's Zimodem): its firmware line,
              MODEM.RAW, the end
   Every session ends with "AB END" and dump.bin (the screen).
   MIT licence (see LICENSE). */
#include <veranda.h>
#include <string.h>
#include "../apps/sysui/sysui.h"

extern char t_session[];
void __fastcall__ t_read(const char *name);
void __fastcall__ t_say(const char *s);
void __fastcall__ t_saynum(const char *a, unsigned long v);
void __fastcall__ snap(const char *name);
void __fastcall__ t_end(const char *pfx);
void __fastcall__ hw_jiffies(unsigned char *buf);

void ab_refresh(void);
unsigned int ab_copy(void);
void ab_ask(void);
extern unsigned char ab_asided, ab_net, ab_naside, ab_aside, ab_free, ab_progs, ab_mine, ab_uart, ab_emu;
extern unsigned int ab_total, ab_mhz10;

static unsigned char step;
static unsigned int t0;

static unsigned int now(void)
{
    unsigned char j[3];
    hw_jiffies(j);
    return j[0] | (unsigned int)j[1] << 8;
}

static void numbers(void)
{
    t_saynum("AB N TOTAL ", ab_total);
    t_saynum("AB N PROGS ", ab_progs);
    t_saynum("AB N FREE ", ab_free);
    t_saynum("AB N ASIDE ", ab_aside);
    t_saynum("AB N NASIDE ", ab_naside);
    t_saynum("AB N MINE ", ab_mine);
    t_saynum("AB N UART ", ab_uart);
    t_saynum("AB N EMU ", ab_emu);
    t_saynum("AB N MHZ10 ", ab_mhz10);
}

void ab_test_start(void)
{
    t_read("AB.TST");
    t_say(t_session);
    numbers();
    t0 = now();
}

void ab_test_tick(void)
{
    switch (step) {
    case 0:
        if (now() - t0 < 150)           /* (2.5 s: the live lines drawn again) */
            return;
        t_say("AB LIVE");
        if (!strcmp(t_session, "modem")) {
            ab_ask();
            step = 20;
            t0 = now();
            return;
        }
        if (strcmp(t_session, "host")) {
            t_end("AB");
            return;
        }
        t_saynum("AB COPIED ", ab_copy());
        ab_ask();                       /* (no card: "no card to ask") */
        snap("ABOUT.RAW");
        step = 1;
        return;
    case 1:
        t_say("AB GOING ASIDE");
        TaskCtl(TASK_ASIDE, 0, 0);
        step = 2;
        return;
    case 2:                             /* (back from the test desktop) */
        if (!ab_asided)
            return;
        t_say("AB BACK");
        ab_refresh();
        numbers();
        snap("ASIDE.RAW");
        t_end("AB");
        return;
    case 20:
        if (ab_net && now() - t0 < 900)
            return;
        numbers();
        snap("MODEM.RAW");
        t_end("AB");
        return;
    }
}
