/* Veranda Term: the modem's rate (DECISIONS V94), in a banked overlay
   (record 2, $A000 of its own RAM bank; term.c maps it before each call
   and does what follows itself: the status line, the dial, the log, so
   nothing here calls a resident function that maps another bank).

   After Packet16 (x16-ftp: link.c's link_open, net_zimodem.c's zn_sync
   and zn_set_baud), whose approach is used here under the MIT licence
   with its author's permission: Zimodem keeps the rate it was left at
   (115200 on TexElec's card) until it is powered off, and a terminal at
   another rate gets noise and sends noise. "AT" at 115200, 57600,
   38400, 19200 and 9600 until "OK" (or "ERROR") comes back; at another
   rate than settings/B, "ATB<rate>" moves the modem to B (it answers at
   the new rate) and the UART follows once the command has left the
   chip. Nothing answers (no modem, or it is online): the UART stays at
   B. A dial typed meanwhile waits (net.c: dialing 4). The steps
   themselves are the SDK's now (vrsync.c, shared with vrnet: V98).

   Also here, out of the resident program for room (V94): the date and
   time read from a line (net.c's modem_line), the time zone and the day
   of the week (term.c's clock_offer); they map this bank first.

   MIT licence (see LICENSE). */
#pragma code-name ("OVERLAY2")
#pragma rodata-name ("OVL2RO")
#pragma data-name ("OVL2DATA")
#pragma bss-name ("OVL2BSS")
#include <string.h>
#include "term.h"
#include "net.h"

/* the sync itself is the SDK's (vrser.h's ser_sync, vrsync.c, compiled
   into this overlay too: V98); here Term's side of it: its line reader
   (net.c's modem_line sets got_ok) and its flags */
void o_sync(void)
{
    syncing = 0;
    if (ser_on != 1 || online || dialing == 3 || tcp > TCP_WAIT)
        return;
    got_ok = 0;
    ser_sync(xtals[cfg.xtal], bauds[cfg.baud]);
    syncing = 1;
}

/* 1: done (the UART at B, the modem too if it answered) */
unsigned char o_sync_tick(void)
{
    unsigned char r = ser_sync_tick(got_ok);
    got_ok = 0;
    if (ser_sync_new) {         /* (a new rate: the line read afresh) */
        ser_sync_new = 0;
        net_mlen = 0;
    }
    if (!r)
        return 0;
    syncing = 0;
    return 1;
}

/*---------------------------------------------------------------
  the date and time in a line: YY-MM-DD HH:MM:SS (the daytime service,
  NIST's format) or YYYY-MM-DD[ T]HH:MM:SS (ISO); UTC
 ---------------------------------------------------------------*/
static unsigned char num(const char *s, unsigned char n, unsigned int *v)
{
    unsigned int x = 0;
    while (n--) {
        if (*s < '0' || *s > '9')
            return 0;
        x = x * 10 + (*s++ - '0');
    }
    *v = x;
    return 1;
}

unsigned char parse_time(const char *s, struct when *w)
{
    unsigned int y, mo, d, h, mi, se;
    unsigned char yl;
    for (; *s; ++s) {
        for (yl = 4; yl >= 2; yl -= 2) {
            const char *p = s;
            if (!num(p, yl, &y) || p[yl] != '-')
                continue;
            p += yl + 1;
            if (!num(p, 2, &mo) || p[2] != '-' || !num(p + 3, 2, &d) || (p[5] != ' ' && p[5] != 'T'))
                continue;
            p += 6;
            if (!num(p, 2, &h) || p[2] != ':' || !num(p + 3, 2, &mi) || p[5] != ':' || !num(p + 6, 2, &se))
                continue;
            if (yl == 2)
                y += 2000;
            if (y < 2000 || y > 2099 || mo < 1 || mo > 12 || d < 1 || d > 31 || h > 23 || mi > 59 || se > 60)
                continue;
            w->yr = y - 1900;
            w->mon = mo;
            w->dy = d;
            w->hr = h;
            w->mn = mi;
            w->sec = se > 59 ? 59 : se;
            return 1;
        }
    }
    return 0;
}

static unsigned char mdays(unsigned char m, unsigned char y)
{
    static const unsigned char dm[12] = { 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 };
    return m == 2 && !(y & 3) ? 29 : dm[m - 1];
}

/* UTC + quarter hours, across days, months and years */
void time_zone(struct when *w, signed char q)
{
    int m = (int)w->hr * 60 + w->mn + (int)q * 15;
    while (m < 0) {
        m += 1440;
        if (--w->dy == 0) {
            if (--w->mon == 0) {
                w->mon = 12;
                --w->yr;
            }
            w->dy = mdays(w->mon, w->yr);
        }
    }
    while (m >= 1440) {
        m -= 1440;
        if (++w->dy > mdays(w->mon, w->yr)) {
            w->dy = 1;
            if (++w->mon > 12) {
                w->mon = 1;
                ++w->yr;
            }
        }
    }
    w->hr = m / 60;
    w->mn = m % 60;
}

char *o_fmt_when(char *p, unsigned char y, unsigned char mo, unsigned char d,
                 unsigned char h, unsigned char mi, unsigned char s)
{
    p = put_str(p, "20");
    p = put2(p, y % 100);
    *p++ = '-';
    p = put2(p, mo);
    *p++ = '-';
    p = put2(p, d);
    *p++ = ' ';
    p = put2(p, h);
    *p++ = ':';
    p = put2(p, mi);
    *p++ = ':';
    p = put2(p, s);
    *p = 0;
    return p;
}


/* the time seen (net_time) with the time zone, asked about (unless
   settings/U), into the RTC and Veranda's clock (SetClock, V42); from
   term.c, moved here for room (V112) */
void o_clock_offer(void)
{
    static char oldt[32], newt[32];
    struct when w;
    char *p;
    memcpy(&w, &net_time, sizeof w);
    time_zone(&w, cfg.tz);
    p = put_str(oldt, "Now: ");
    o_fmt_when(p, year, month, day, hour, minutes, seconds);
    p = put_str(newt, "New: ");
    o_fmt_when(p, w.yr, w.mon, w.dy, w.hr, w.mn, w.sec);
    if (!cfg.autoclock && !yesno(oldt, newt))
        return;
    SetClock(w.yr, w.mon, w.dy, w.hr, w.mn, w.sec, weekday(&w));
    LogText("TERM CLOCK SET");
}

/* modem status (term.c's m_status): the status commands (cfg.info, ';'
   between them), one a second and a half, their answers in the window;
   then the clock offered if a date came (moved here for room, V112) */
void o_info_pump(void)
{
    static unsigned char pos;
    static unsigned int t;
    if (info_on == 1) {
        info_on = 2;
        pos = 0;
        t = ser_frames - 200;
    }
    if (ser_frames - t < 90)
        return;
    t = ser_frames;
    if (!cfg.info[pos]) {
        info_on = 0;
        if (net_time_ok)
            o_clock_offer();
        return;
    }
    while (cfg.info[pos] && cfg.info[pos] != ';')
        ser_byte(cfg.info[pos++]);
    if (cfg.info[pos] == ';')
        ++pos;
    ser_byte(13);
}

/* 1 Monday .. 7 Sunday (the RTC's day of the week; Sakamoto's method) */
unsigned char weekday(const struct when *w)
{
    static const unsigned char t[12] = { 0, 3, 2, 5, 0, 3, 5, 1, 4, 6, 2, 4 };
    unsigned int y = 1900 + w->yr - (w->mon < 3);
    unsigned char d = (y + y / 4 - y / 100 + y / 400 + t[w->mon - 1] + w->dy) % 7;
    return d ? d : 7;
}
