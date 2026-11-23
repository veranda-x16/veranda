/* gate disktools (DECISIONS V119): Disk Tools' test build (apps/disktools,
   make test: DT_TEST), in main RAM; tests/term_play.s plays keys and
   clicks through mouseSource (the boxes: Return for OK, a click on
   Cancel). DT.TST in the top folder names the session:
     host     the host folder: the card (Host folder); Space use of the top
              (logged "DT SPACE <bytes> <files> <name>"), Down and Return
              into the largest folder, Backspace back; a count stopped by
              Esc; a count stopped by Alt+Tab (TaskCtl TASK_ASIDE: the test
              desktop tests/term_desk.s brings it back after 3 s), counted
              again; Check (no FAT here: its box); Clean up: the trash's
              items, Empty with Cancel, then with OK; leftovers looked for,
              each kind deleted (OK) but the Font Editor's (Cancel);
              CARD.RAW, SPACE.RAW, CLEAN.RAW
     sdcheck  an SD card image with faults planted: Check (its fault
              lines "DT FAULT ...", "DT CHECK DONE ..."); nothing written
     sdmod    an SD card image: Rename (the box: the name typed), Space
              use, Empty the trash (OK), then Check: no problems; the Card
              tab for the screenshot
   Every session ends with "DT END" and dump.bin (the screen).
   MIT licence (see LICENSE). */
#include <veranda.h>
#include <string.h>
#include "../apps/disktools/dt.h"

extern char t_session[];
void __fastcall__ t_read(const char *name);
void __fastcall__ t_say(const char *s);
void __fastcall__ t_saynum(const char *a, unsigned long v);
void __fastcall__ snap(const char *name);
void __fastcall__ t_end(const char *pfx);
void __fastcall__ term_play(const unsigned int *script);
void __fastcall__ dt_tab(unsigned char t);
void __fastcall__ dt_hot(unsigned char h);
extern unsigned char ui_box_open, ui_boxes;

#define F_BTN  0x100
#define F_KEY  0x8000
#define F_WAIT 0x1000
#define F_Y256 0x4000

static unsigned int scr[3 * 40];
static unsigned char ns, step, sd, wait_t;
static unsigned int t0, t1, tlen;
static const unsigned int stopper[3] = { 0xFFFF, 0xFFFF, 0 };

/* the KERNAL's jiffies (RDTIM: a, x = the low word) */
static unsigned int now(void)
{
    asm("jsr $FFDE");
    asm("rts");
    return 0;
}

static void S(unsigned int f, unsigned int x, unsigned int y)
{
    if (!ns)
        term_play(stopper);
    scr[ns++] = f;
    scr[ns++] = x;
    scr[ns++] = y;
    if (f > tlen)
        tlen = f;
}

static void K(unsigned int f, unsigned char k)
{
    S(f, k, F_KEY);
}

/* the next box: wait for it, then Return (OK) or a click on Cancel */
static void box(unsigned char ok)
{
    S(0, (unsigned int)&ui_box_open, F_WAIT);
    if (ok)
        K(20, 13);
    else {                              /* (y 272: 16 + 256) */
        S(20, 384, 16 | F_Y256);
        S(23, 384, 16 | F_Y256 | F_BTN);
        S(27, 384, 16 | F_Y256);
    }
}

static void go(void)
{
    scr[ns++] = 0xFFFF;
    scr[ns++] = 0xFFFF;
    scr[ns++] = 0;
    term_play(scr);
    ns = 0;
    t0 = now();
}

static unsigned char played(void)
{
    return now() - t0 > tlen + 30;
}

static void next(void)
{
    ++step;
    tlen = 0;
    t0 = now();
}

void dt_test_start(void)
{
    t_read("DT.TST");
    t_say(t_session);
    sd = t_session[0] == 's';
    t0 = now();
}

static void end(void)
{
    t_end("DT");
}

static void host(void)
{
    switch (step) {
    case 0:
        if (now() - t0 < 30)
            return;
        snap("CARD.RAW");
        dt_tab(T_SPACE);                /* (counts the top at once) */
        next();
        return;
    case 1:
        if (job)
            return;
        snap("SPACE.RAW");
        K(5, 0x11);                     /* Down: the largest folder */
        K(15, 13);                      /* Return: into it */
        go();
        next();
        return;
    case 2:
        if (!played() || job)
            return;
        K(5, 0x14);                     /* Backspace: back up */
        go();
        next();
        return;
    case 3:
        if (!played() || job)
            return;
        dt_hot(H_COUNT);                /* counted again, Esc at once */
        K(2, 0x1B);
        go();
        next();
        return;
    case 4:
        if (!played() || job)
            return;
        dt_hot(H_COUNT);                /* counted again, put aside after 3 passes */
        wait_t = 0;
        next();
        return;
    case 5:
        if (++wait_t < 3)
            return;
        t_say("DT GOING ASIDE");
        TaskCtl(TASK_ASIDE, 0, 0);
        next();
        return;
    case 6:
        if (job || !put_aside)
            return;                     /* (back: the count stopped) */
        t_say("DT BACK");
        put_aside = 0;
        dt_hot(H_COUNT);
        next();
        return;
    case 7:
        if (job)
            return;
        dt_tab(T_CHECK);
        box(1);                         /* (the host has no FAT: its box) */
        go();
        dt_hot(H_CHECK);
        next();
        return;
    case 8:
        dt_tab(T_CLEAN);
        box(0);                         /* Empty: Cancel */
        go();
        dt_hot(H_EMPTY);
        box(1);                         /* Empty: OK */
        go();
        dt_hot(H_EMPTY);
        dt_hot(H_SCAN);
        next();
        return;
    case 9:
        if (job)
            return;
        snap("CLEAN.RAW");
        box(1);
        go();
        dt_hot(H_DEL0 + 0);             /* Veranda Edit's: OK */
        box(1);
        go();
        dt_hot(H_DEL0 + 1);             /* VeraBASIC's: OK */
        box(0);
        go();
        dt_hot(H_DEL0 + 2);             /* the Font Editor's: Cancel */
        box(1);
        go();
        dt_hot(H_DEL0 + 3);             /* Veranda Ask's: OK */
        t_saynum("DT BOXES ", ui_boxes);
        end();
        return;
    }
}

static void sdcheck(void)
{
    switch (step) {
    case 0:
        if (now() - t0 < 30)
            return;
        dt_tab(T_CHECK);
        t1 = now();
        dt_hot(H_CHECK);
        next();
        return;
    case 1:
        if (job)
            return;
        t_saynum("DT CHECK JIFFIES ", now() - t1);
        end();
        return;
    }
}

static void sdmod(void)
{
    unsigned char i;
    switch (step) {
    case 0:
        if (now() - t0 < 30)
            return;
        S(0, (unsigned int)&ui_box_open, F_WAIT);
        for (i = 0; i < 12; ++i)
            K(20 + i * 3, 0x14);        /* the old name rubbed out */
        K(60, 'X');
        K(63, '1');
        K(66, '6');
        K(69, 'c');
        K(72, 'a');
        K(75, 'r');
        K(78, 'd');
        K(84, 13);
        go();
        dt_hot(H_RENAME);
        dt_tab(T_SPACE);
        next();
        return;
    case 1:
        if (job)
            return;
        dt_tab(T_CLEAN);
        box(1);
        go();
        dt_hot(H_EMPTY);
        dt_tab(T_CHECK);
        dt_hot(H_CHECK);
        next();
        return;
    case 2:
        if (job)
            return;
        dt_tab(T_CARD);                 /* (the screenshot: the card renamed) */
        end();
        return;
    }
}

void dt_test_tick(void)
{
    if (!strcmp(t_session, "host"))
        host();
    else if (!strcmp(t_session, "sdcheck"))
        sdcheck();
    else if (!strcmp(t_session, "sdmod"))
        sdmod();
    else {
        t_say("DT NO SESSION");
        end();
    }
}
