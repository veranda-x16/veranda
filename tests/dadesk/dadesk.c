/* gate da: a test program (an application, mode keep; MIT licence).

   DADESK.TST in its folder, one line, picks what it does:
     cal [stop]  a backdrop; a counter of interrupts from intTopVector
                 (in zero page and in RAM, V91: both logged equal after
                 the Calendar, "DADESK COUNT z r", and 30 frames later);
                 GetFile("Calendar") (its test build plays its
                 session and closes); then, back here, a watch on PSG voice
                 15 (the beep) from intFirstVector (watch.s), logged ("PSG
                 <freq> <volume> <wave> <frame>"), and a
                 script: OK on the alarm's box at frame 2400, the end (a
                 dump) at 2700, or at <stop> (a screenshot with the box)
     (none)      the settings as the kernel has them (SysPrefs PREFS_GET),
                 blankDelay, palette entries 0 and 1 and graphMode logged
                 ("DADESK PREFS ..."), then the end (a dump): the test
                 desktop started by EnterDeskTop as DESKTOP.cvt (TopDesk's
                 stand-in), after a reboot with "Veranda Prefs" */
#include <veranda.h>
#include <vr.h>
#include <string.h>

extern void __fastcall__ vr_play(const void *script);

#define VCTRL  (*(volatile unsigned char *)0x9F25)
#define VADDRL (*(volatile unsigned char *)0x9F20)
#define VADDRM (*(volatile unsigned char *)0x9F21)
#define VADDRH (*(volatile unsigned char *)0x9F22)
#define VDATA0 (*(volatile unsigned char *)0x9F23)

static char line[80];
static const char hex[] = "0123456789ABCDEF";

static char *hx(char *p, unsigned char b)
{
    *p++ = hex[b >> 4];
    *p++ = hex[b & 15];
    *p = 0;
    return p;
}

static void dump_now(void)
{
    *(volatile unsigned char *)0x9FB4 = 1;      /* EMU_SAVE_ON_EXIT */
    asm("jmp $FFFF");
}

/* the PSG watch (watch.s, from intFirstVector): voice 15's registers at
   each change, and the frame */
extern unsigned char wring[32][5], whead, wtail;
void watch_irq(void);

/* (V91) a counter of interrupts from intTopVector, in zero page and in
   RAM (watch.s); count_get copies both into cget at one moment */
extern unsigned int cget[2];
void count_irq(void);
void count_get(void);
void count_zero(void);

static void logcount(void)
{
    char *p = (char *)memcpy(line, "DADESK COUNT ", 13) + 13;
    count_get();
    p = hx(hx(p, cget[0] >> 8), cget[0] & 255);
    *p++ = ' ';
    hx(hx(p, cget[1] >> 8), cget[1] & 255);
    LogText(line);
}

static void logpsg(void)
{
    char *p;
    while (wtail != whead) {
        p = line;
        p = (char *)memcpy(p, "PSG 15 ", 7) + 7;
        p = hx(hx(p, wring[wtail][1]), wring[wtail][0]);
        *p++ = ' ';
        p = hx(p, wring[wtail][2]);
        *p++ = ' ';
        p = hx(p, wring[wtail][3]);
        *p++ = ' ';
        hx(p, wring[wtail][4]);
        LogText(line);
        wtail = (wtail + 1) & 31;
    }
}

#define S(f, x, y, b) (f), (x), ((y) & 255) | (((y) >> 8) << 14) | ((b) << 8)
static unsigned int script[] = {
    S(2400, 384, 272, 0), S(2401, 384, 272, 1), S(2403, 384, 272, 0),
    S(2500, 100, 100, 0),
    0xFFFF, 2700, 0
};

static char tst[24];

static void backdrop(void)
{
    SetPattern(2);
    WRectangle(0, 0, screenWidth - 1, screenHeight - 1);
    SetPattern(0);
    WRectangle(16, 16, 263, 39);
    WFrameRectangle(0xFF, 16, 16, 263, 39);
    WPutString("A test program runs here.", 24, 31);
}

static void prefs(void)
{
    static unsigned char b[PREFS_SIZE];
    unsigned char i, v[4];
    char *p = line;
    SysPrefs(PREFS_GET, b);
    p = (char *)memcpy(p, "DADESK PREFS", 12) + 12;
    for (i = 0; i < PREFS_SIZE; ++i) {
        *p++ = ' ';
        p = hx(p, b[i]);
    }
    LogText(line);
    VCTRL = 0;
    VADDRL = 0;
    VADDRM = 0xFA;
    VADDRH = 0x11;
    for (i = 0; i < 4; ++i)
        v[i] = VDATA0;
    p = (char *)memcpy(line, "DADESK PALETTE ", 15) + 15;
    p = hx(hx(p, v[1]), v[0]);
    *p++ = ' ';
    p = hx(hx(p, v[3]), v[2]);
    p = (char *)memcpy(p, " BLANK ", 7) + 7;
    p = hx(hx(p, blankDelay >> 8), blankDelay & 255);
    p = (char *)memcpy(p, " MODE ", 6) + 6;
    hx(p, graphMode);
    LogText(line);
}

int main(void)
{
    unsigned char h = FOpen("DADESK.TST", 'r'), n = 0, e;
    if (h >= 2 && h <= 9 && dosStatus < 20) {
        n = FRead(h, tst, sizeof tst - 1);
        FClose(h);
    }
    tst[n] = 0;
    LogText("DADESK RUNNING");
    if (tst[0] != 'c') {
        prefs();
        dump_now();
    }
    if (tst[3] == ' ' && tst[4] >= '0') {       /* the stop frame */
        unsigned int f = 0;
        for (n = 4; tst[n] >= '0' && tst[n] <= '9'; ++n)
            f = f * 10 + tst[n] - '0';
        script[sizeof script / 2 - 2] = f;
    }
    dispBufferOn = ST_WR_FORE | ST_WR_BACK;
    backdrop();
    count_zero();
    intTopVector = VR_FN(count_irq);
    while (count_get(), cget[0] < 20)           /* counting */
        ;
    e = GetFile("Calendar", 0, 0, 0, 0);
    LogText(e ? "DADESK NO CALENDAR" : "DADESK BACK");
    logcount();                 /* both equal when GetFile returns */
    {
        unsigned int z;
        count_get();
        z = cget[0] + 30;
        while (count_get(), cget[0] < z)        /* and they count on */
            ;
    }
    logcount();
    intFirstVector = VR_FN(watch_irq);
    appMain = VR_FN(logpsg);
    vr_play(script);
    return 0;
}
