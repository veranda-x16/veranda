/* About this X16: what this machine is and how it is doing, in one window
   (C, MIT; DECISIONS V119).

   This machine: Veranda's version and API level (GetVersion) and the
   build it came from; the build installed on the card, from Veranda
   Update's list /VERANDA/UPDATE.LST (its "build" line; V130); the KERNAL ROM's release (its version byte, $FF80);
   the CPU's speed, measured against VERA's frame; VERA's version (DC_VER
   with DCSEL 63; the emulator reports its own release there, 47.x, so a
   major number of 40 or more says x16emu); the SMC's firmware over I2C.
   Memory: the RAM banks there are (found as the KERNAL's ramtas finds
   them: MEMTOP is Veranda's, lowered under its kernel); the switcher's summary
   (TaskCtl TASK_INFO $FF: the banks there are for programs, those free)
   and its tasks (each program put aside, its banks): the system's share,
   the programs aside, this program's, the rest (fonts, the desktop's
   picture lent), free. The SD card: its name and free space as the DOS
   lists them, its partition's size from its sectors (sysui's card.c).
   The network card: a 16C550 UART found where TexElec's card puts one
   (vrser.h's ser_probe); nothing is sent to it unless "Ask the modem" is
   chosen: then "AT" at the rates Zimodem may be at, and "ATI" at the one
   that answered, the firmware's lines shown (no ATB, no ATZ, no profile:
   the modem is left as it was). The clock and the time since the last
   reset (the KERNAL's jiffies).

   The clock, the memory and the uptime are drawn again every second;
   Refresh reads everything again; Copy puts all of it on the clipboard
   as text (the Text Scrap), for a bug report.

   Alt+Tab puts it aside at any time (no stream or listing stays open
   between two passes of the main loop); a modem question running then is
   dropped ("interrupted") and the UART turned off.

   MIT licence (see LICENSE). */
#include <veranda.h>
#include <vr.h>
#include <string.h>
#include <theme.h>
#include <scrap.h>
#include <vrser.h>
#include "../sysui/sysui.h"

#ifndef VR_BUILD
#define VR_BUILD "unknown"
#endif
#ifndef VR_RELEASE
#define VR_RELEASE "unknown"    /* (the file VERSION: docs/RELEASING.md) */
#endif

unsigned char __fastcall__ hw_kernal(void);
void __fastcall__ hw_vera(unsigned char *buf);
unsigned char __fastcall__ hw_rambanks(void);
void __fastcall__ hw_jiffies(unsigned char *buf);
int __fastcall__ hw_smc(unsigned char reg);
void __fastcall__ hw_version(unsigned char *buf);
unsigned int __fastcall__ hw_frame(void);

/*---------------------------------------------------------------- the lines */
enum {
    L_HEAD1, L_VERANDA, L_INSTALLED, L_KERNAL, L_MACHINE, L_CPU, L_VERA,
    L_HEAD2, L_RAM, L_SYSTEM, L_ASIDE, L_MINE, L_OTHER, L_FREE,
    L_HEAD3, L_CNAME, L_CSIZE, L_CFREE,
    L_HEAD4, L_UART, L_MODEM,
    L_HEAD5, L_NOW, L_UP,
    L_N
};
static const char *const label[L_N] = {
    "This machine", "Veranda", "Installed", "KERNAL ROM", "Machine", "CPU", "VERA and SMC",
    "Memory", "RAM", "The system", "Programs aside", "This program", "Fonts and others", "Free",
    "The SD card", "Name", "Size", "Free",
    "The network card", "Card", "Modem",
    "The clock", "Date and time", "Up"
};
#define VLEN 72
char val[L_N][VLEN];
static unsigned int ly[L_N];

static unsigned char is_head(unsigned char i)
{
    return i == L_HEAD1 || i == L_HEAD2 || i == L_HEAD3 || i == L_HEAD4 || i == L_HEAD5;
}

static void layout(void)
{
    unsigned int y = BODY_TOP + 4;
    unsigned char i;
    for (i = 0; i < L_N; ++i) {
        if (is_head(i) && i)
            y += 6;
        ly[i] = y;
        y += LINE_H;
    }
}

static void draw_line(unsigned char i)
{
    if (is_head(i)) {
        SetPattern(0);
        WRectangle(0, ly[i], 639, ly[i] + LINE_H - 1);
        ui_text(8, ly[i], label[i], 1);
        return;
    }
    ui_pair(ly[i], label[i], val[i]);
}

#ifdef AB_TEST
extern char ui_tl[];                    /* (sysui's test log line, 130 bytes) */
#define tl ui_tl
static void tlog(unsigned char i)
{
    strcpy(tl, "AB ");
    strcat(tl, label[i]);
    strcat(tl, "=");
    strcat(tl, val[i]);
    LogText(tl);
}
#endif

/* the modem asked (below): N_OFF, or what it waits for */
enum { N_OFF, N_AT, N_INFO };
unsigned char ab_net;

/*---------------------------------------------------------------- this machine */
static unsigned char vera[4];
unsigned char ab_emu;                   /* x16emu (VERA's version 40 or more) */
unsigned int ab_mhz10;                  /* the CPU's speed, MHz x 10 */

static void machine(void)
{
    unsigned char v[3], k;
    unsigned long c;
    unsigned int n;
    int a, b, d;
    char *p;
    hw_version(v);
    strcpy(val[L_VERANDA], VR_RELEASE ", kernel ");
    p = ui_num(val[L_VERANDA] + sizeof VR_RELEASE ", kernel " - 1, v[1]);
    *p++ = '.';
    p = ui_num(p, v[2]);
    strcpy(p, ", API level ");
    p = ui_num(p + strlen(p), v[0]);
    strcpy(p, ", build " VR_BUILD);

    k = hw_kernal();
    p = val[L_KERNAL];
    if (k == 0xFF)
        strcpy(p, "a custom build");
    else if (k & 0x80) {
        *p++ = 'R';
        p = ui_num(p, 256 - k);
        strcpy(p, " (a pre-release)");
    } else {
        *p++ = 'R';
        p = ui_num(p, k);
    }
    p = val[L_KERNAL] + strlen(val[L_KERNAL]);
    strcpy(p, ", version byte ");
    ui_hex(p + strlen(p), k, 2);

    hw_vera(vera);
    ab_emu = vera[0] == 'V' && vera[1] >= 40;
    strcpy(val[L_MACHINE], ab_emu ? "x16emu (VERA reports its release)" : "Commander X16");

    if (ab_net == N_OFF) {              /* (not while the UART is polled: two frames without the interrupt) */
        n = hw_frame();
        c = 13UL * n + 5UL * (n >> 8) + 30;
        ab_mhz10 = (unsigned int)((c * 5952UL + 5000000UL) / 10000000UL);
    }
    p = ui_num(val[L_CPU], ab_mhz10 / 10);
    *p++ = '.';
    p = ui_num(p, ab_mhz10 % 10);
    strcpy(p, " MHz (measured against VERA's frame)");

    p = val[L_VERA];
    if (vera[0] == 'V') {
        strcpy(p, "VERA ");
        p = ui_num(p + 5, vera[1]);
        *p++ = '.';
        p = ui_num(p, vera[2]);
        *p++ = '.';
        p = ui_num(p, vera[3]);
    } else {
        strcpy(p, "VERA before 0.3.1 (no version)");
        p += strlen(p);
    }
    a = hw_smc(0x30);
    b = hw_smc(0x31);
    d = hw_smc(0x32);
    if (a < 0 || b < 0 || d < 0 || (a == 0xFF && b == 0xFF))
        strcpy(p, ", the SMC does not say its version");
    else {
        strcpy(p, ", SMC ");
        p = ui_num(p + 6, a);
        *p++ = '.';
        p = ui_num(p, b);
        *p++ = '.';
        ui_num(p, d);
    }
}

/* the card's build (V130): /VERANDA/UPDATE.LST's second line,
   "build <id> <date>" */
static void installed(void)
{
    static char b[64];
    unsigned char h, n;
    char *p, *q;
    strcpy(val[L_INSTALLED], "not known (no /VERANDA/UPDATE.LST: from before V130)");
    if (ChDir(VR_SYSDIR))
        return;
    h = FOpen("UPDATE.LST", 'r');
    if (h < 2 || h > 9 || dosStatus >= 20)
        return;
    n = FRead(h, b, sizeof b - 1);
    FClose(h);
    b[n] = 0;
    if (memcmp(b, "VERANDA-UPDATE 1", 16))
        return;
    p = strstr(b, "\nbuild ");
    if (!p)
        return;
    p += 7;
    q = strchr(p, ' ');
    if (!q || q - p > 15 || strlen(q) < 11)
        return;
    *q = 0;
    q[11] = 0;
    strcpy(val[L_INSTALLED], "build ");
    strcat(val[L_INSTALLED], p);
    strcat(val[L_INSTALLED], " of ");
    strcat(val[L_INSTALLED], q + 1);
    strcat(val[L_INSTALLED], " (Veranda Update's list on the card)");
}

/*---------------------------------------------------------------- memory */
static unsigned char sum[TASK_SUM], rec[TASK_REC];
unsigned int ab_total;
unsigned char ab_free, ab_progs, ab_aside, ab_naside, ab_mine;
unsigned char ab_bank;                  /* the modem question's ring (vrser's) */

static char *banks(char *p, unsigned int n)
{
    p = ui_num(p, n);
    strcpy(p, n == 1 ? " bank" : " banks");
    return p + strlen(p);
}

/* a GEOS name (17 bytes, padded) shown */
static char *gname(char *p, const unsigned char *s, char *end)
{
    unsigned char i, l = 0;
    for (i = 0; i < 16 && s[i] && s[i] != 0xA0; ++i)
        l = i + 1;
    for (i = 0; i < l && p < end; ++i)
        *p++ = s[i] >= 32 && s[i] < 127 ? s[i] : '?';
    *p = 0;
    return p;
}

static void memory(void)
{
    unsigned int t = hw_rambanks(), other;
    unsigned char i;
    char *p, *q, *end = val[L_ASIDE] + VLEN - 12;
    if (!t)
        t = 256;
    ab_total = t;
    p = ui_num(val[L_RAM], (unsigned long)t << 3);
    strcpy(p, " KB: ");
    p = banks(p + 5, t);
    strcpy(p, " of 8 KB");

    TaskCtl(TASK_INFO, 0xFF, sum);
    ab_free = sum[TS_FREE];
    ab_progs = sum[TS_BANKS];
    ab_mine = ab_bank ? 1 : 0;
    p = banks(val[L_SYSTEM], t - ab_progs);
    strcpy(p, " (Veranda's kernel banks, their copy, bank 0)");

    ab_aside = ab_naside = 0;
    q = val[L_ASIDE];
    *q = 0;
    for (i = 0; i < TASK_MAX; ++i) {
        TaskCtl(TASK_INFO, i, rec);
        if (rec[TR_STATE] != TASK_ASIDE)
            continue;
        ab_aside += rec[TR_BANKS];
        ++ab_naside;
#ifdef AB_TEST
        strcpy(tl, "AB TASK ");
        gname(tl + 8, rec + TR_NAME, tl + 40);
        strcat(tl, " ");
        ui_num(tl + strlen(tl), rec[TR_BANKS]);
        LogText(tl);
#endif
    }
    p = banks(q, ab_aside);
    if (!ab_naside)
        strcpy(p, " (none)");
    else {
        strcpy(p, ": ");
        p += 2;
        for (i = 0; i < TASK_MAX && p < end; ++i) {
            TaskCtl(TASK_INFO, i, rec);
            if (rec[TR_STATE] != TASK_ASIDE)
                continue;
            if (p[-2] != ':') {
                *p++ = ',';
                *p++ = ' ';
            }
            p = gname(p, rec + TR_NAME, end);
            *p++ = ' ';
            *p++ = '(';
            p = ui_num(p, rec[TR_BANKS]);
            *p++ = ')';
            *p = 0;
        }
    }
    banks(val[L_MINE], ab_mine);
    other = ab_progs - ab_free - ab_aside - ab_mine;
    if (other > ab_progs)
        other = 0;
    p = banks(val[L_OTHER], other);
    strcpy(p, " (fonts in RAM, the desktop's picture lent)");
    p = banks(val[L_FREE], ab_free);
    strcpy(p, " (");
    p = ui_size(p + 2, (unsigned long)ab_free << 13);
    strcpy(p, ")");
}

/*---------------------------------------------------------------- the card */
static void sdcard(void)
{
    char *p;
    card_read();
    strcpy(val[L_CNAME], card.label[0] ? card.label : "(none)");
    if (card.host) {
        strcpy(val[L_CSIZE], "the emulator's host folder (no SD card)");
        strcpy(val[L_CFREE], "(the host does not say)");
        return;
    }
    p = val[L_CSIZE];
    if (card.sd_ok) {
        p = ui_size(p, card.part_sec << 9);
        strcpy(p, " FAT32");
        p += 6;
        if (card.csd_kb) {
            strcpy(p, ", on a card of ");
            p = ui_size(p + strlen(p), card.csd_kb << 10);
        }
    } else
        strcpy(p, card.err);
    p = val[L_CFREE];
    if (card.sd_ok && card.fsi_free != 0xFFFFFFFFUL)
        ui_size(p, card.fsi_free * card.spc << 9);
    else if (card.dunit && card.dunit != 'B')
        ui_size(p, card.dfree << 10);
    else
        strcpy(p, "(not known)");
}

/*---------------------------------------------------------------- the network card */
unsigned char ab_uart;                  /* the UART's address - $9F00, 0 none */

static void uart(void)
{
    char *p;
    ab_uart = ab_bank ? ab_uart : ser_probe();
    if (!ab_uart) {
        strcpy(val[L_UART], "none found (no UART at $9F60-$9FF0)");
        return;
    }
    p = val[L_UART];
    strcpy(p, "a UART (16C550) at ");
    ui_hex(p + strlen(p), 0x9F00 + ab_uart, 4);
    strcat(p, ab_uart == 0xE0 ? ": TexElec's network card, its modem" : ": a serial or network card");
}

/* the modem asked: "AT" at each rate until OK or ERROR, then "ATI" */
static const unsigned int rates[] = { 1152, 576, 384, 192, 96 };
static unsigned char nrate;
static unsigned int t0;
static char nl[80];
static unsigned char nlen, ninfo;
static unsigned char rx[64];

static void live(void);

static void net_end(const char *why)
{
    if (ab_bank) {
        ser_stop();
        intFirstVector = 0;
        BankFree(ab_bank);
        ab_bank = 0;
    }
    ab_net = N_OFF;
    if (why)
        strcpy(val[L_MODEM], why);
    draw_line(L_MODEM);
    live();                             /* (its bank given back) */
#ifdef AB_TEST
    tlog(L_MODEM);
#endif
}

static void send(const char *s)
{
    while (*s)
        ser_byte(*s++);
    nlen = 0;
    t0 = ser_frames;
}

static void at_try(void)
{
    ser_setdiv(ser_div(SER_X14, rates[nrate]));
    send("AT\r");
}

void ab_ask(void)
{
    if (ab_net != N_OFF)
        return;
    uart();
    if (!ab_uart) {
        strcpy(val[L_MODEM], "no card to ask");
        draw_line(L_MODEM);
        return;
    }
    ab_bank = BankAlloc(1);
    if (!ab_bank) {
        strcpy(val[L_MODEM], "not enough memory (1 RAM bank)");
        draw_line(L_MODEM);
        return;
    }
    ser_rxbank = ab_bank;
    intFirstVector = VR_FN(SerIrq);
    if (ser_open(ab_uart, ser_div(SER_X14, rates[0]), 0)) {
        net_end("the UART does not answer");
        return;
    }
    nrate = 0;
    ninfo = 0;
    val[L_MODEM][0] = 0;
    strcpy(val[L_MODEM], "asking (AT, then ATI) ...");
    draw_line(L_MODEM);
    ab_net = N_AT;
    at_try();
}

/* a whole line from the modem */
static void net_line(void)
{
    nl[nlen] = 0;
    if (!nlen)
        return;
    if (ab_net == N_AT) {
        if (!strcmp(nl, "OK") || !strcmp(nl, "ERROR")) {
            ab_net = N_INFO;
            strcpy(val[L_MODEM], "(no firmware line)");
            send("ATI\r");
        }
        return;
    }
    if (!strcmp(nl, "OK")) {
        net_end(0);
        return;
    }
    if (nl[0] == 'A' && nl[1] == 'T')
        return;                         /* (its echo) */
    if (!ninfo)
        val[L_MODEM][0] = 0;
    else if (strlen(val[L_MODEM]) < VLEN - 4)
        strcat(val[L_MODEM], " / ");
    strncat(val[L_MODEM], nl, VLEN - 1 - strlen(val[L_MODEM]));
    ++ninfo;
}

static void net_tick(void)
{
    unsigned int n, i;
    unsigned char c;
    if (ab_net == N_OFF)
        return;
    n = ser_get(rx, sizeof rx);
    for (i = 0; i < n; ++i) {
        c = rx[i];
        if (c == 13 || c == 10) {
            net_line();
            nlen = 0;
            if (ab_net == N_OFF)
                return;
        } else if (c >= 32 && c < 127 && nlen < sizeof nl - 1)
            nl[nlen++] = c;
    }
    if (ab_net == N_AT && ser_frames - t0 > 30) {
        if (++nrate == sizeof rates / sizeof rates[0]) {
            net_end("no answer at 115200 to 9600 baud");
            return;
        }
        at_try();
    } else if (ab_net == N_INFO && ser_frames - t0 > 120)
        net_end(0);
}

/*---------------------------------------------------------------- the clock */
static void clock_(void)
{
    unsigned char j[3];
    unsigned long s;
    char *p;
    ui_clock(val[L_NOW]);
    hw_jiffies(j);
    s = (j[0] | (unsigned int)j[1] << 8 | (unsigned long)j[2] << 16) / 60;
    p = val[L_UP];
    if (s >= 3600) {
        p = ui_num(p, s / 3600);
        strcpy(p, " h ");
        p += 3;
    }
    p = ui_num(p, s / 60 % 60);
    strcpy(p, " min ");
    p = ui_num(p + 5, s % 60);
    strcpy(p, " s since the last reset (the ROM's clock: 24 hours at most)");
}

/*---------------------------------------------------------------- the window */
static const struct btn tools[] = { { 1, 10, "Refresh" }, { 12, 8, "Copy" }, { 21, 17, "Ask the modem" } };
#define NTOOLS 3

static void draw_all(void)
{
    unsigned char i;
    ui_clear(BODY_TOP, BODY_BOT);
    for (i = 0; i < L_N; ++i)
        draw_line(i);
}

static void live(void)
{
    memory();
    clock_();
    draw_line(L_SYSTEM);
    draw_line(L_ASIDE);
    draw_line(L_MINE);
    draw_line(L_OTHER);
    draw_line(L_FREE);
    draw_line(L_NOW);
    draw_line(L_UP);
}

void ab_refresh(void)
{
    unsigned char i;
    SetPointer(PTR_BUSY);
    machine();
    installed();
    memory();
    sdcard();
    uart();
    if (ab_net == N_OFF && !val[L_MODEM][0])
        strcpy(val[L_MODEM], "not asked (Ask the modem sends AT and ATI)");
    clock_();
    draw_all();
    SetPointer(PTR_ARROW);
    ui_status("Refreshed every second; Copy puts it all on the clipboard", 0);
#ifdef AB_TEST
    for (i = 0; i < L_N; ++i)
        if (!is_head(i))
            tlog(i);
#else
    (void)i;
#endif
}

static char clip[1800];

/* everything as text on the clipboard */
unsigned int ab_copy(void)
{
    unsigned char i;
    char *p = clip, *end = clip + sizeof clip - VLEN - 24;
    strcpy(p, "About this X16\n");
    p += strlen(p);
    for (i = 0; i < L_N && p < end; ++i) {
        if (is_head(i)) {
            *p++ = '\n';
            strcpy(p, label[i]);
            p += strlen(p);
            *p++ = '\n';
            continue;
        }
        strcpy(p, "  ");
        strcat(p, label[i]);
        strcat(p, ": ");
        strcat(p, val[i]);
        p += strlen(p);
        *p++ = '\n';
    }
    *p = 0;
    if (scrap_put_text(clip, p - clip)) {
        ui_message("The clipboard was not written.", "");
        return 0;
    }
    ui_status("Copied to the clipboard (as text)", 0);
    return p - clip;
}

/*---------------------------------------------------------------- menus */
static void m_about(void), m_quit(void), m_copy(void), m_refresh(void), m_ask(void);

struct item { const char *text; unsigned char type; void *p; };
struct menu1 { unsigned char top, bottom; unsigned int left, right; unsigned char flags; struct item i[1]; };
struct menu2 { unsigned char top, bottom; unsigned int left, right; unsigned char flags; struct item i[2]; };
struct menu3 { unsigned char top, bottom; unsigned int left, right; unsigned char flags; struct item i[3]; };

#define IH 14
static struct menu2 mapp = { 14, 14 + 2 * IH, 0, 0, VERTICAL | 2, {
    { "About this X16...", MENU_ACTION, m_about }, { "\x1f" "Quit\tCtrl Q", MENU_ACTION, m_quit } } };
static struct menu1 medit = { 14, 14 + IH, 0, 0, VERTICAL | 1, {
    { "Copy all\tC", MENU_ACTION, m_copy } } };
static struct menu2 mview = { 14, 14 + 2 * IH, 0, 0, VERTICAL | 2, {
    { "Refresh\tR", MENU_ACTION, m_refresh }, { "\x1f" "Ask the modem (ATI)", MENU_ACTION, m_ask } } };
static struct menu3 mbar = { 0, 14, 0, 0, HORIZONTAL | UN_CONSTRAINED | 3, {
    { "About this X16", SUB_MENU, &mapp }, { "Edit", SUB_MENU, &medit }, { "View", SUB_MENU, &mview } } };
static const char *const barnames[3] = { "About this X16", "Edit", "View" };
static const char *const longest[3] = { "About this X16...", "Copy all\tC", "Ask the modem (ATI)" };
static unsigned int *const lefts[3] = { &mapp.left, &medit.left, &mview.left };
static unsigned int *const rights[3] = { &mapp.right, &medit.right, &mview.right };
unsigned int barx[3], barl[3];

static void m_about(void)
{
    GotoFirstMenu();
    ui_message("About this X16 1.0, MIT licence.", "What this machine is and has.");
}

void ab_quit(void)
{
    net_end(0);
    EnterDeskTop();
}

static void m_quit(void) { GotoFirstMenu(); ab_quit(); }
static void m_copy(void) { GotoFirstMenu(); ab_copy(); }
static void m_refresh(void) { GotoFirstMenu(); ab_refresh(); }
static void m_ask(void) { GotoFirstMenu(); ab_ask(); }

static void press(void)
{
    unsigned int x = mouseXPos, y = mouseYPosW;
    if (mouseData & 0x80)
        return;
    if (y >= TOOL_TOP && y < BODY_TOP) {
        switch (ui_tool_at(tools, NTOOLS, x)) {
        case 0: ab_refresh(); break;
        case 1: ab_copy(); break;
        case 2: ab_ask(); break;
        }
    }
}

static void key(void)
{
    unsigned char k = keyData;
    if (k == KEY_ESC && ab_net != N_OFF)
        net_end("stopped");
    else if (k == 'r' || k == 'R')
        ab_refresh();
    else if (k == 'c' || k == 'C')
        ab_copy();
    else if (k == 'q' - 96 && (keyDataMods & (2 | KEYM_ARROW)) == 2)
        ab_quit();                      /* Ctrl Q (KEY_DOWN is 17 too) */
}

#ifdef AB_TEST
unsigned char ab_asided;
#endif

/* the switcher: a question to the modem dropped */
static void aside(void)
{
    if (ab_net != N_OFF) {
        ser_stop();
        intFirstVector = 0;
        BankFree(ab_bank);
        ab_bank = 0;
        ab_net = N_OFF;
        strcpy(val[L_MODEM], "interrupted (put aside); ask again");
    }
#ifdef AB_TEST
    ab_asided = 1;
    LogText("AB ASIDE");
#endif
}

#ifdef AB_TEST
void ab_test_tick(void);
void ab_test_start(void);
#endif

static unsigned char lastsec;

static void tick(void)
{
    net_tick();
    if (seconds != lastsec) {
        lastsec = seconds;
        live();
    }
#ifdef AB_TEST
    ab_test_tick();
#endif
}

int main(void)
{
    dispBufferOn = ST_WR_FORE;          /* (the foreground only: menus and boxes save what they cover) */
    SetPattern(0);
    WRectangle(0, 0, 639, 15);
    theme_load();
    theme_palette();
    ui_window("About this X16");
    theme_menus();
    ui_menus(barnames, 3, (unsigned int **)lefts, (unsigned int **)rights, longest, &mbar.right, barx, barl);
    DoMenu((void *)&mbar, 0);
    ui_toolbar(tools, NTOOLS, 0xFF);
    layout();
    ab_refresh();
    lastsec = seconds;
    otherPressVec = VR_FN(press);
    keyVector = VR_FN(key);
    asideVector = VR_FN(aside);
    appMain = VR_FN(tick);
#ifdef AB_TEST
    ab_test_start();
#endif
    return 0;
}
