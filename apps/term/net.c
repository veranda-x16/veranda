/* Veranda Term: the serial port's C half, Telnet, the modem, XMODEM and
   the clock from the network (MIT licence, see LICENSE).

   The serial driver (the SDK's vrser.h, V98) has two back-ends behind
   one ring: the 16C550 (programmed by vrserc.c, read and written by the
   interrupt, vrser.s) and the script (bytes from a file in RAM banks,
   for gates without a port).

   Received bytes go: Telnet (IAC sequences answered and removed) -> the
   capture file -> XMODEM, while a download runs, else the modem's result
   lines (CONNECT, NO CARRIER, OK) are noticed and every byte goes to the
   screen (vt.c). */
#include <string.h>
#include "term.h"
#include "net.h"

/*---------------------------------------------------------------
  the serial port
 ---------------------------------------------------------------*/
/* the driver is the SDK's (vrser.h: vrser.s, vrserc.c; DECISIONS V98,
   moved there from here and ser.s unchanged); Term's settings pick the
   port, the rate and the back-end */
unsigned int ser_divisor(void)
{
    return ser_div(xtals[cfg.xtal], bauds[cfg.baud]);
}

unsigned char ser_start(void)
{
    if (cfg.backend == 1) {
        ser_script();
        return 0;
    }
    /* receive data and line status, only with settings/I on: by default
       the UART never interrupts (IER 0, polled from VERA's line interrupt),
       the set-up Packet16 runs on TexElec's card (V94) */
    return ser_open(cfg.port, ser_divisor(), cfg.uirq ? 0x05 : 0);
}

/* (V91) asideVector: the port off before the switcher; armed again by
   the main loop (term_wake) */
void term_aside(void)
{
    ser_aside();
    LogText("TERM ASIDE");
}

void term_wake(void)
{
    if (ser_wake())
        LogText("TERM BACK");
}

/*---------------------------------------------------------------
  Telnet (RFC 854): ECHO, SGA, BINARY, TERMINAL-TYPE, NAWS
 ---------------------------------------------------------------*/
#define IAC  255
#define DONT 254
#define DO   253
#define WONT 252
#define WILL 251
#define SB   250
#define SE   240
#define O_BIN   0
#define O_ECHO  1
#define O_SGA   3
#define O_TTYPE 24
#define O_NAWS  31

unsigned char tn_on;            /* Telnet is spoken */
unsigned char tn_echo;          /* the host echoes */
unsigned char tn_bin;
unsigned char tn_seen;          /* the options negotiated, bit by option (gates) */
static unsigned char tn_state, tn_cmd, tn_sbopt, tn_sblen;
static unsigned char tn_sb[8];

/* a byte to the host: the serial line, or in a TCP session (V112) the
   ring tcp.c sends from with ATT */
unsigned char tcp;              /* (net.h: TCP_WAIT ... TCP_RESET; 0 none) */
unsigned char tcp_ev, tcp_raw, tcp_quit;
unsigned char tcp_tx[TCP_TXSZ];
unsigned char tcp_txh, tcp_txt;

void tx_put(unsigned char c)
{
    if (tcp) {
        if (((tcp_txh + 1) & (TCP_TXSZ - 1)) != tcp_txt) {
            tcp_tx[tcp_txh] = c;
            tcp_txh = (tcp_txh + 1) & (TCP_TXSZ - 1);
        }
    } else
        ser_byte(c);
}

unsigned char tx_room(void)
{
    return tcp ? (TCP_TXSZ - 1) - ((tcp_txh - tcp_txt) & (TCP_TXSZ - 1)) : ser_txroom();
}

static void tn_send3(unsigned char c, unsigned char o)
{
    tx_put(IAC);
    tx_put(c);
    tx_put(o);
}

static void tn_sbsend(unsigned char o, const unsigned char *p, unsigned char n)
{
    tx_put(IAC);
    tx_put(SB);
    tx_put(o);
    while (n--) {
        if (*p == IAC)
            tx_put(IAC);
        tx_put(*p++);
    }
    tx_put(IAC);
    tx_put(SE);
}

static void naws(void)
{
    static const unsigned char sz[4] = { 0, COLS, 0, ROWS };
    tn_sbsend(O_NAWS, sz, 4);
}

/* the options as bits: ECHO 1, SGA 2, BINARY 4, TERMINAL-TYPE 8, NAWS 16
   (tn_seen's too); him: the host's on, us: ours on. A request for what is
   already so gets no answer (RFC 854's rule against loops, V112) */
static unsigned char tn_him, tn_us, tn_cr;

static unsigned char tn_bit(unsigned char o)
{
    return o == O_ECHO ? 1 : o == O_SGA ? 2 : o == O_BIN ? 4 : o == O_TTYPE ? 8 : o == O_NAWS ? 16 : 0;
}

static void tn_option(unsigned char cmd, unsigned char o)
{
    unsigned char b = tn_bit(o);
    tn_seen |= b;
    switch (cmd) {
    case WILL:                  /* the host's ECHO, SGA, BINARY */
        if (!(b & 7))
            tn_send3(DONT, o);
        else if (!(tn_him & b)) {
            tn_him |= b;
            tn_send3(DO, o);
        }
        break;
    case WONT:
        if (tn_him & b) {
            tn_him &= ~b;
            tn_send3(DONT, o);
        }
        break;
    case DO:                    /* ours: SGA, BINARY, TERMINAL-TYPE, NAWS */
        if (!(b & 30))
            tn_send3(WONT, o);
        else if (!(tn_us & b)) {
            tn_us |= b;
            tn_send3(WILL, o);
            if (b == 16)
                naws();
        }
        break;
    case DONT:
        if (tn_us & b) {
            tn_us &= ~b;
            tn_send3(WONT, o);
        }
        break;
    }
    tn_echo = tn_him & 1;
    tn_bin = (tn_him & 4 ? 1 : 0) | (tn_us & 4 ? 2 : 0);
}

/* Telnet off, or on (a new session) */
void tn_reset(unsigned char on)
{
    tn_on = on;
    tn_echo = tn_bin = tn_him = tn_us = tn_state = tn_cr = 0;
}

static void deliver(unsigned char c);

static void rx(unsigned char c)
{
    if (!tn_on) {
        deliver(c);
        return;
    }
    switch (tn_state) {
    case 0:
        if (c == IAC)
            tn_state = 1;
        else if (!c && tn_cr && !(tn_bin & 1))
            ;                   /* (NVT's CR NUL: the CR alone, V112) */
        else
            deliver(c);
        tn_cr = c == 13;
        break;
    case 1:
        tn_state = 0;
        if (c == IAC)
            deliver(c);
        else if (c >= WILL && c <= DONT) {
            tn_cmd = c;
            tn_state = 2;
        } else if (c == SB) {
            tn_state = 3;
        }
        break;
    case 2:
        tn_state = 0;
        tn_option(tn_cmd, c);
        break;
    case 3:
        tn_sbopt = c;
        tn_sblen = 0;
        tn_state = 4;
        break;
    case 4:
        if (c == IAC)
            tn_state = 5;
        else if (tn_sblen < sizeof tn_sb)
            tn_sb[tn_sblen++] = c;
        break;
    case 5:
        if (c == SE) {
            tn_state = 0;
            if (tn_sbopt == O_TTYPE && tn_sblen && tn_sb[0] == 1) {
                static const unsigned char is[] = { 0, 'A', 'N', 'S', 'I' };
                tn_sbsend(O_TTYPE, is, 5);
                tn_seen |= 32;
            }
        } else {
            tn_state = 4;
            if (tn_sblen < sizeof tn_sb)
                tn_sb[tn_sblen++] = c;
        }
        break;
    }
}

void net_send(unsigned char c)
{
    if (tn_on && c == IAC)
        tx_put(IAC);
    tx_put(c);
}

void term_reply(const char *s)
{
    while (*s)
        net_send(*s++);
}

/*---------------------------------------------------------------
  the modem: result lines, dialling, hanging up
 ---------------------------------------------------------------*/
unsigned char online;
unsigned int online_since;      /* ser_frames / 60 at CONNECT */
unsigned char dialing;          /* 1 init sent, 2 dial sent */
static unsigned int dtimer;
char target[48];                /* (V112: a TCP session's host:port too) */
unsigned char hangup_state;
static unsigned int htimer;
static char mline[64];
unsigned char net_mlen;        /* (V94: ui.c's o_sync too) */
unsigned char syncing;
unsigned char got_ok;
unsigned char clockwant;        /* 1: a time line is looked for */
struct when net_time;           /* the last date and time seen */
unsigned char net_time_ok;
unsigned long rx_total;

static void modem_line(void)
{
    mline[net_mlen] = 0;
    if (!memcmp(mline, "CONNECT", 7)) {
        online = 1;
        online_since = ser_frames;
        dialing = 0;
        status();
    } else if (!memcmp(mline, "NO CARRIER", 10) || !memcmp(mline, "NO ANSWER", 9) || !memcmp(mline, "BUSY", 4)) {
        if (online || dialing)
            net_dropped();
        online = 0;
        dialing = 0;
        tn_reset(0);
        status();
    } else if (!strcmp(mline, "OK")) {
        got_ok = 1;
    } else if (!strcmp(mline, "ERROR")) {
        got_ok = 2;
    }
    MAPBANK(term_ovl2);         /* (parse_time: overlay 2, V94) */
    if (parse_time(mline, &net_time))
        net_time_ok = 1;
}

static void deliver(unsigned char c)
{
    ++rx_total;
    if (!syncing) {             /* (V94: while the modem's rate is looked
                                   for, what comes at a wrong one is noise:
                                   the result lines only, nothing shown) */
        capture_byte(c);
        if (xm_active) {
            xm_byte(c);
            return;
        }
    }
    if (tcp)
        ;                       /* (V112: the host's bytes, no modem lines) */
    else if (c == 13 || c == 10) {
        if (net_mlen)
            modem_line();
        net_mlen = 0;
    } else if (c >= 32 && net_mlen < sizeof mline - 1)
        mline[net_mlen++] = c;
    if (!syncing)
        vt_put(c);
}

/* (V212) a run of printable characters (32-126) where only deliver's
   ground path would take them (no rate looked for, no XMODEM, Telnet in
   its ground state): as rx takes them one by one (counted, captured, the
   modem's line, tn_cr cleared, the model: vt_text), in one go, not some
   2,700 cycles a character through rx, deliver and vt_put */
void net_rx(const unsigned char *p, unsigned int n)
{
    unsigned char k, c;
    while (n) {
        k = syncing | xm_active | tn_state ? 0 : net_run(p, n);
        if (!k) {
            rx(*p++);
            --n;
            continue;
        }
        rx_total += k;
        tn_cr = 0;
        for (c = 0; c < k; ++c) {
            capture_byte(p[c]);
            if (!tcp && net_mlen < sizeof mline - 1)
                mline[net_mlen++] = p[c];
        }
        vt_text(p, k);
        p += k;
        n -= k;
    }
}

void sends(const char *s)
{
    while (*s)
        ser_byte(*s++);
}

/* dial: an AT command as it is, else "host:port" (Zimodem: ATDT) */
void net_dial(const char *s)
{
    unsigned char at = (s[0] | 0x20) == 'a' && (s[1] | 0x20) == 't';
    strncpy(target, s, sizeof target - 1);
    tn_reset(0);
    tn_seen = 0;
    if (!at && cfg.telnet != 2)
        tn_auto = 1;
    else
        tn_auto = cfg.telnet == 1;
    got_ok = 0;
    dialing = 4;                /* (V94: after the modem's rate is found) */
    if (!syncing)
        dial_go();
    status();
}

void dial_go(void)
{
    got_ok = 0;                 /* (the init string's own OK, not the sync's) */
    if (cfg.init[0]) {
        sends(cfg.init);
        ser_byte(13);
        dialing = 1;
    } else
        dialing = 2;
    dtimer = ser_frames;
    if (dialing == 2)
        net_tick();
    status();
}

unsigned char tn_auto;

void net_hangup(void)
{
    if (tcp) {                  /* (V112: tcp.c closes it) */
        tcp_quit = 1;
        return;
    }
    if (!online && !dialing)
        return;
    dialing = 0;
    hangup_state = 1;
    htimer = ser_frames;
    status();
}

void net_tick(void)
{
    unsigned int t = ser_frames;
    if (dialing == 1 && (got_ok || t - dtimer > 120)) {
        dialing = 2;
        dtimer = t;
    }
    if (dialing == 2 && dtimer != 0xFFFF) {
        if ((target[0] | 0x20) == 'a' && (target[1] | 0x20) == 't')
            sends(target);
        else {
            sends("ATDT");
            sends(target);
        }
        ser_byte(13);
        dtimer = 0xFFFF;
        dialing = 3;
        tn_on = tn_auto;
    }
    if (hangup_state == 1 && t - htimer > 70) {
        sends("+++");
        hangup_state = 2;
        htimer = t;
    } else if (hangup_state == 2 && t - htimer > 70) {
        sends("ATH0");
        ser_byte(13);
        hangup_state = 0;
        online = 0;
        tn_reset(0);
        status();
    }
    xm_tick();
}
