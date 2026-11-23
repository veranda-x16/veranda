/* gate net (tools/gate_net.sh; DECISIONS V98): a test application for
   vrnet (the SDK's sockets through the emulated Zimodem modem, the
   emulator's -uart 9FE0 modem back-end).

   NET.TST, one line: "<session> <echo port> <file port> <stall port>
   <baud / 100>". Sessions:
     main     vrnet started (the modem's rate found from 115200 down, moved
              to the rate asked); two sockets at once: the echo server
              (tests/net_servers.py) gets ECHO_LEN bytes (every byte value,
              "+++", "NO CARRIER 1", XON, XOFF, a packet header, then
              pseudo-random bytes) and every byte that comes back is
              checked; the file server sends FILE_LEN bytes (its
              generator, net_servers.py's) and closes: each byte checked,
              then NET_ECLOSED. Meanwhile, once 20,000 bytes of the file
              have come: switchReq = SWITCH_ASIDE (what Alt+Tab sets): the
              switcher puts the program aside (asideVector: vrnet finishes
              the packet arriving), the test desktop (tests/term_desk.s)
              waits 3 s and brings it back, and both transfers go on.
              Then a connection to the stall port (the modem stays busy,
              as with a host that never answers): NET_FAILED with
              NET_ETIMEOUT after 15 s, the main loop running meanwhile;
              the modem answers again (vrnet's recovery); a closed port:
              NET_FAILED, NET_ERR; the echo server again; net_stop.
     nomodem  nothing answers on the line (-uart 9FE0 file:): NET_FAULT,
              NET_ENOMODEM, after the five rates; the main loop running
     nocard   no UART: net_start returns NET_ENOCARD
   Each step logs a line "NET ..."; the end: the screen dumped (-dump V). */
#include <veranda.h>
#include <vr.h>
#include <string.h>
#include <vrser.h>
#include <vrnet.h>

#define ECHO_LEN 16384u
#define FILE_LEN 65536ul

static char tst[48], sess[10], w[4][8];
static unsigned int echo_port, file_port, stall_port, baud;
static unsigned char buf[256];
static char msg[80];
static unsigned char step;
static unsigned int y_line, x_col = 24;
static signed char s0, s1, s2;
static unsigned int t0, tlast, maxgap, passes, tstep;
static unsigned long got1, wrote0, got0;
static unsigned char aside_done, bad;
static unsigned int lost;

static void dump(void)
{
    *(volatile unsigned char *)0x9FB4 = 1;      /* EMU_SAVE_ON_EXIT */
    asm("jmp $FFFF");
}

static char *put_num(char *p, unsigned long v)
{
    char t[10];
    unsigned char n = 0;
    do {
        t[n++] = '0' + v % 10;
        v /= 10;
    } while (v);
    while (n)
        *p++ = t[--n];
    *p = 0;
    return p;
}

/* a line logged and shown */
static void say(const char *s, long v, unsigned char with)
{
    char *p = msg;
    while (*s)
        *p++ = *s++;
    if (with) {
        *p++ = ' ';
        if (v < 0) {
            *p++ = '-';
            v = -v;
        }
        p = put_num(p, v);
    }
    *p = 0;
    LogText(msg);
    if (y_line > 456 && x_col == 24) {
        x_col = 330;                            /* (a second column) */
        y_line = 52;
    }
    if (y_line <= 456) {
        WPutString(msg + 4, x_col, y_line);
        y_line += 12;
    }
}

/* the echo's bytes: 0-255, the traps, then a generator */
static const char traps[] = "+++ATH0\r\nNO CARRIER 1\r\n\x11\x13[ 1 254 0 ]\r\n+++";
struct gen { unsigned int i, x; };
static struct gen ew, er, fr;

static unsigned char echo_byte(struct gen *g)
{
    unsigned int i = g->i++;
    if (i < 256)
        return i;
    if (i < 256 + sizeof traps - 1)
        return traps[i - 256];
    g->x ^= g->x << 7;
    g->x ^= g->x >> 9;
    g->x ^= g->x << 8;
    return (unsigned char)(g->x ^ (g->x >> 8));
}

/* the file's (net_servers.py's file_bytes): page p counts from p * 77
   in steps of 2p + 1 (cheap: the check is not what limits the speed) */
static unsigned char fv, fstep;
static unsigned char file_byte(struct gen *g)
{
    unsigned char v;
    if (!(unsigned char)g->i) {
        fv = (g->i >> 8) * 77;
        fstep = 2 * (g->i >> 8) + 1;
    }
    ++g->i;
    v = fv;
    fv += fstep;
    return v;
}

static char *word(char *p, char *out)
{
    while (*p == ' ')
        ++p;
    while (*p > ' ')
        *out++ = *p++;
    *out = 0;
    return p;
}

static unsigned int atou(const char *s)
{
    unsigned int v = 0;
    while (*s >= '0' && *s <= '9')
        v = v * 10 + (*s++ - '0');
    return v;
}

static void finish(void)
{
    say("NET PASSES", passes, 1);
    say("NET MAXGAP", maxgap, 1);
    say("NET PULLS", net_stats.pulls, 1);
    say("NET PACKETS", net_stats.packets, 1);
    say("NET EMPTIES", net_stats.empties, 1);
    say("NET SENDS", net_stats.sends, 1);
    say("NET XONRETRY", net_stats.xon_retries, 1);
    say("NET BADCRC", net_stats.badcrc, 1);
    say("NET ORPHANS", net_stats.orphans, 1);
    say("NET LOST", ser_lost + ser_oe, 1);
    net_stop();
    say(bad ? "NET END FAILED" : "NET END", 0, 0);
    dump();
}

static void failed(const char *s, long v)
{
    bad = 1;
    say(s, v, 1);
    finish();
}

/* the two transfers, a little each pass */
static unsigned char transfers(void)
{
    int n, i;
    unsigned char st;
    /* the echo: written as room allows, read back and checked */
    if (wrote0 < ECHO_LEN) {
        n = net_room(s0);
        if (n > ECHO_LEN - wrote0)
            n = ECHO_LEN - wrote0;
        if (n > (int)sizeof buf)
            n = sizeof buf;
        for (i = 0; i < n; ++i)
            buf[i] = echo_byte(&ew);
        if (n && net_write(s0, buf, n) != n)
            failed("NET FAIL ECHO WRITE", n);
        wrote0 += n;
    }
    n = net_read(s0, buf, sizeof buf);
    if (n < 0)
        failed("NET FAIL ECHO READ", n);
    for (i = 0; i < n; ++i)
        if (buf[i] != echo_byte(&er))
            failed("NET FAIL ECHO BYTE AT", got0 + i);
    got0 += n;
    /* the file: read and checked; then the close */
    if (got1 <= FILE_LEN) {
        n = net_read(s1, buf, sizeof buf);
        if (n == NET_ECLOSED) {
            if (got1 != FILE_LEN)
                failed("NET FAIL FILE SHORT", got1);
            say("NET FILE EOF", got1, 1);
            say("NET FILE FRAMES", ser_frames - t0, 1);
            got1 = FILE_LEN + 1;
        } else if (n < 0)
            failed("NET FAIL FILE READ", n);
        else {
            for (i = 0; i < n; ++i)
                if (buf[i] != file_byte(&fr))
                    failed("NET FAIL FILE BYTE AT", got1 + i);
            got1 += n;
        }
    }
    if (!aside_done && got1 >= 20000 && got1 <= FILE_LEN) {
        aside_done = 1;
        say("NET ALT+TAB AT", got1, 1);
        switchReq = SWITCH_ASIDE;               /* (Alt+Tab's request: V83) */
    }
    st = net_sock(s0);
    if (st == NET_FAILED)
        failed("NET FAIL ECHO SOCKET", net_sockerr(s0));
    return got0 == ECHO_LEN && got1 > FILE_LEN;
}

static void tick(void)
{
    unsigned int t = ser_frames;
    unsigned char st;
    signed char r;
    if (ser_asleep && aside_done == 1) {
        aside_done = 2;
        say("NET BACK AT", got1, 1);
        t = tlast = ser_frames;
    }
    if (ser_oe + ser_lost != lost) {            /* (where it happened) */
        lost = ser_oe + ser_lost;
        say("NET OVERRUN AT", got1, 1);
        say("NET OVERRUN FRAME", t - t0, 1);
    }
    if (passes && t - tlast > maxgap)
        maxgap = t - tlast;
    tlast = t;
    ++passes;
    net_poll();
    st = net_state();
    if (st == NET_FAULT) {
        if (step == 1 && sess[0] == 'n') {
            say("NET NOMODEM", net_error(), 1);
            say("NET FRAMES", ser_frames - t0, 1);
            finish();
        }
        failed("NET FAIL FAULT", net_error());
    }
    switch (step) {
    case 1:                                     /* the modem found, set up */
        if (st == NET_READY) {
            say("NET READY FRAMES", ser_frames - t0, 1);
            say("NET RATE FOUND", (long)ser_sync_found * 100, 1);
            s0 = net_open("127.0.0.1", echo_port);
            s1 = net_open("localhost", file_port);
            if (s0 < 0 || s1 < 0)
                failed("NET FAIL OPEN", s0 < 0 ? s0 : s1);
            step = 2;
            t0 = ser_frames;
        }
        break;
    case 2:                                     /* both open */
        if (net_sock(s0) == NET_FAILED || net_sock(s1) == NET_FAILED)
            failed("NET FAIL CONNECT", net_sockerr(net_sock(s0) == NET_FAILED ? s0 : s1));
        if (net_sock(s0) == NET_OPEN && net_sock(s1) >= NET_OPEN) {
            say("NET OPEN BOTH FRAMES", ser_frames - t0, 1);
            step = 3;
        }
        transfers();
        break;
    case 3:
        if (transfers()) {
            say("NET ECHO OK", got0, 1);
            say("NET FILE OK", got1 - 1, 1);
            say("NET BOTH FRAMES", ser_frames - t0, 1);
            net_close(s0);
            net_close(s1);
            s2 = net_open("127.0.0.1", stall_port);
            t0 = ser_frames;
            say("NET STALL OPEN", s2, 1);
            step = 4;
        }
        break;
    case 4:                                     /* nothing answers */
        if (net_sock(s2) == NET_FAILED) {
            r = net_sockerr(s2);
            say("NET STALL FAILED", r, 1);
            say("NET STALL FRAMES", ser_frames - t0, 1);
            if (r != NET_ETIMEOUT)
                failed("NET FAIL STALL ERR", r);
            net_close(s2);
            step = 5;
        } else if (net_sock(s2) != NET_DIAL && net_sock(s2) != NET_OPENING)
            failed("NET FAIL STALL STATE", net_sock(s2));
        break;
    case 5:                                     /* the modem back: a closed port */
        if (st == NET_READY && net_sock(s0) == NET_FREE && net_sock(s1) == NET_FREE) {
            say("NET RECOVERED FRAMES", ser_frames - t0, 1);
            s2 = net_open("127.0.0.1", 1);
            step = 6;
        }
        break;
    case 6:
        if (net_sock(s2) == NET_FAILED) {
            say("NET REFUSED", net_sockerr(s2), 1);
            net_close(s2);
            s0 = net_open("127.0.0.1", echo_port);
            step = 7;
        } else if (net_sock(s2) == NET_OPEN)
            failed("NET FAIL REFUSED OPEN", 0);
        break;
    case 7:                                     /* the echo once more */
        if (net_sock(s0) == NET_OPEN) {
            net_write(s0, "after", 5);
            tstep = 0;
            step = 8;
        }
        break;
    case 8:
        r = net_read(s0, buf + tstep, sizeof buf - tstep);
        if (r > 0)
            tstep += r;
        if (tstep >= 5) {
            buf[5] = 0;
            if (memcmp(buf, "after", 5))
                failed("NET FAIL AFTER", tstep);
            say("NET AFTER OK", tstep, 1);
            net_close(s0);
            step = 9;
            t0 = ser_frames;
        }
        break;
    case 9:                                     /* its ATH answered */
        if (net_sock(s0) == NET_FREE || ser_frames - t0 > 300) {
            say("NET CLOSED", net_sock(s0), 1);
            finish();
        }
        break;
    }
}

int main(void)
{
    unsigned char h;
    char *p;
    signed char r;
    dispBufferOn = ST_WR_FORE | ST_WR_BACK;
    SetPattern(0);
    WRectangle(0, 0, 639, 479);
    WFrameRectangle(0xFF, 8, 8, 631, 471);
    y_line = 52;
    WPutString("vrnet: gate net (DECISIONS V98)", 24, 26);
    h = FOpen("NET.TST", 'r');
    if (h < 2) {
        LogText("NET NO NET.TST");
        dump();
    }
    tst[FRead(h, tst, sizeof tst - 1)] = 0;
    FClose(h);
    p = word(tst, sess);
    for (h = 0; h < 4; ++h)
        p = word(p, w[h]);
    echo_port = atou(w[0]);
    file_port = atou(w[1]);
    stall_port = atou(w[2]);
    baud = atou(w[3]);
    ew.x = er.x = 0x1234;
    fr.i = 0;
    r = net_start(0, baud);
    say("NET START", r, 1);
    if (sess[0] == 'n' && sess[2] == 'c') {     /* nocard */
        if (r != NET_ENOCARD)
            bad = 1;
        say(bad ? "NET END FAILED" : "NET END", 0, 0);
        dump();
    }
    if (r)
        failed("NET FAIL START", r);
    say("NET PORT", ser_lo, 1);
    t0 = ser_frames;
    step = 1;
    appMain = VR_FN(tick);
    return 0;
}
