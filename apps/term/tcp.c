/* Veranda Term: a TCP session through the Zimodem modem's command mode
   (DECISIONS V112), in overlay 2 (term.c maps it before each call).

   Why not ATDT: Zimodem's ATD takes the letters after it as modifiers,
   and T is "Telnet translation" (the firmware answers the options
   itself and changes 0xFF bytes), stream mode ends on "+++" with guard
   times, and a refused port comes as NO ANSWER like a host that is not
   there. In command mode (ATC"host:port", ATT<n>, an XON for each packet
   with its CRC-8: vrnet's way, after Packet16's, docs/NET.md) every byte
   is carried as it is, so Term speaks Telnet itself (net.c) or nothing
   (raw TCP), and XMODEM's bytes arrive whole.

   Why not vrnet itself: it is 6 KB of resident code with two RAM banks
   and sockets Term does not need, and Term's resident program has about
   1 KB left (its test build); vrnet's code maps its own bank over $A000,
   so it cannot run from an overlay either. This is the one-connection
   subset of vrnet (the same profile, the same packets, the same
   deadlines), on Term's own serial set-up: the port, the ring, the rate
   (V94's sync) and the interrupt stay as they are, so the plain serial
   terminal is untouched; at the end ATZ gives the modem back its saved
   profile (echo, flow control) for typing AT commands again.

   Rules (sdk/docs/GUIDE.md, overlays): nothing here calls a resident
   function that maps another bank. Bytes from the serial ring come
   through crow (resident: ser_get copies with the ring's bank mapped);
   a packet's payload goes to rxbuf (resident), and term.c gives it to
   net_rx (Telnet, the capture, XMODEM, the screen).

   MIT licence (see LICENSE). */
#pragma code-name ("OVERLAY2")
#pragma rodata-name ("OVL2RO")
#pragma data-name ("OVL2DATA")
#pragma bss-name ("OVL2BSS")
#include <string.h>
#include "term.h"
#include "net.h"

#define XON     0x11
#define PKT     254             /* ATS40 */
#define RAWSZ   64              /* (crow: 81 bytes) */
#define T_CMD     180           /* a command's OK: 3 s */
#define T_CONNECT 900           /* ATC: 15 s */
#define T_PULL    30            /* an XON's packet: 0.5 s, then XON again */
#define PULL_TRIES 8

static unsigned char crctab[256];
static unsigned char stage[256];        /* a packet's payload */
static char line[48];
static unsigned char llen, trunc;
static unsigned char pst, pid, pcrc, hascrc;
static unsigned int pwant, plen;
static unsigned char rawp, rawn;        /* crow's bytes not taken yet */
static unsigned char cid;               /* the modem's channel */
static unsigned char setup_i, tries, lastempty, flip, ended;
static unsigned int idle_t;

#define OP_NONE 0
#define OP_CMD  1
#define OP_DIAL 2
#define OP_SEND 3
#define OP_PULL 4
static unsigned char op;
static unsigned int ot, olen;
static char cmd[56];
static unsigned char cmdl, cmdp, sendn, sendp;

static const char *const profile[] = {
    "ATE0V1X1Q0&M&D", "ATS40=254S45=0S0=0", "ATF3", "ATH0"
};

static void start(unsigned char o, unsigned int t)
{
    cmd[cmdl++] = 13;
    cmdp = 0;
    op = o;
    ot = ser_frames;
    olen = t;
}

static void command(const char *s)
{
    strcpy(cmd, s);
    cmdl = strlen(s);
    start(OP_CMD, T_CMD);
}

/* the session is over (ev, if not one already): ATZ next, unless the
   modem is gone */
static void end(unsigned char ev)
{
    if (!ended) {
        ended = 1;
        tcp_ev = ev;
    }
    op = OP_NONE;
    tcp = ev == TEV_NOMODEM || ev == TEV_LOST ? 0 : TCP_RESET;
    if (tcp)
        command("ATZ");
}

/* ATZ answered (or not, in time): Term is the serial terminal again */
static void idle(void)
{
    tcp = 0;
    tcp_ev = TEV_IDLE;
}

/* Connect: target and tcp_raw set (hosts.c); nocard: no UART, or the
   script back-end */
void o_tcp_start(unsigned char nocard)
{
    unsigned char i = 0;
    if (nocard) {
        message("There is no serial card", "(no modem to connect through).");
        return;
    }
    do {                        /* Dallas/Maxim CRC-8 ($8C reflected) */
        unsigned char c = i, k;
        for (k = 8; k; --k)
            c = (c & 1) ? (c >> 1) ^ 0x8C : c >> 1;
        crctab[i] = c;
    } while (++i);
    op = OP_NONE;
    pst = llen = trunc = rawp = rawn = cid = setup_i = tries = lastempty = flip = ended = 0;
    tcp_quit = 0;
    tcp_ev = 0;
    tcp_txh = tcp_txt = 0;
    tcp = TCP_WAIT;
    tn_reset(!tcp_raw);
    tn_seen = 0;
    if (!ser_sync_found && !syncing)
        o_sync();               /* (the modem not found before: again, V94) */
    LogText("TERM TCP");
    LogText(target);
    status();
}

/*---------------------------------------------------------------
  what the modem says
 ---------------------------------------------------------------*/
static unsigned char lnum(unsigned char i)
{
    unsigned char v = 0;
    while (line[i] == ' ')
        ++i;
    while (line[i] >= '0' && line[i] <= '9')
        v = v * 10 + (line[i++] - '0');
    return v;
}

/* a command's answer: ok 1 (OK), 0 (ERROR: the profile's first three
   must be taken, ATH and ATZ are best effort) */
static void cmd_done(unsigned char ok)
{
    char *p;
    op = OP_NONE;
    if (tcp == TCP_SETUP) {
        if (!ok && setup_i < 3) {
            end(TEV_NOMODEM);   /* (not a Zimodem) */
            return;
        }
        if (++setup_i < sizeof profile / sizeof profile[0])
            return;             /* (next() sends the next one) */
        tcp = TCP_DIAL;
        p = put_str(put_str(cmd, "ATC\""), target);
        *p++ = '"';
        cmdl = p - cmd;
        start(OP_DIAL, T_CONNECT);
    } else if (tcp == TCP_HANGUP)
        end(TEV_ENDED);
    else if (tcp == TCP_RESET)
        idle();
}

static void on_line(void)
{
    unsigned char i;
    if (!strcmp(line, "OK")) {
        if (op == OP_SEND) {
            if (cmdp < cmdl || sendp < sendn)
                return;
            tcp_txt = (tcp_txt + sendn) & (TCP_TXSZ - 1);
            op = OP_NONE;
        } else if (op == OP_CMD)
            cmd_done(1);
        return;
    }
    if (!memcmp(line, "CONNECT", 7)) {
        i = lnum(7);
        if (op == OP_DIAL && i) {
            cid = i;
            op = OP_NONE;
            tcp = TCP_OPEN;
            tcp_ev = TEV_OPEN;
        }
        return;
    }
    if (!memcmp(line, "NO CARRIER", 10)) {
        i = lnum(10);
        if (op == OP_DIAL)
            end(TEV_REFUSED);
        else if (tcp == TCP_OPEN && (!i || i == cid))
            end(TEV_CLOSED);    /* (after its data: Zimodem sends it then) */
        else if (op == OP_PULL)
            op = OP_NONE;       /* (it used up the XON) */
        return;
    }
    if (strcmp(line, "ERROR") && memcmp(line, "NO ANSWER", 9) && memcmp(line, "BUSY", 4))
        return;
    if (op == OP_DIAL)
        end(TEV_REFUSED);       /* (the emulator: ERROR; the firmware: NO ANSWER) */
    else if (op == OP_SEND)
        end(TEV_CLOSED);        /* (the channel is gone) */
    else if (op == OP_CMD)
        cmd_done(0);
}


/* "[ ch sz ]", "[ ch sz crc ]", "[ ch num sz crc ]" (ATS45=0; Packet16) */
static unsigned char header(void)
{
    unsigned int v[4];
    unsigned char n = 0, i = 1, d;
    for (;;) {
        while (line[i] == ' ')
            ++i;
        if (line[i] == ']')
            break;
        if (line[i] < '0' || line[i] > '9' || n == 4)
            return 0;
        v[n] = 0;
        for (d = 0; line[i] >= '0' && line[i] <= '9'; ++i) {
            if (++d > 5)
                return 0;
            v[n] = v[n] * 10 + (line[i] - '0');
        }
        ++n;
    }
    if (n < 2)
        return 0;
    pid = v[0];
    hascrc = n > 2;
    pwant = n == 4 ? v[2] : v[1];
    pcrc = v[n - 1];
    plen = 0;
    if (op == OP_PULL)
        tries = 0;
    if (!pwant) {               /* nothing on any channel */
        if (op == OP_PULL) {
            op = OP_NONE;
            lastempty = 1;
            idle_t = ser_frames;
        }
        return 1;
    }
    if (pwant > 256)
        pwant = 0;              /* (corruption) */
    else
        pst = 1;
    return 1;
}

/* a whole packet: its payload into rxbuf, the count (0: not ours, or bad) */
static unsigned char packet(void)
{
    unsigned char c = 0, i = 0, n = plen;
    pst = 0;
    if (op == OP_PULL) {
        op = OP_NONE;
        lastempty = 0;
    }
    if (hascrc) {
        while (i != n)
            c = crctab[c ^ stage[i++]];
        if (c != pcrc) {
            LogText("TERM TCP BAD CRC");
            return 0;           /* (its bytes lost: XMODEM asks again) */
        }
    }
    if (pid != cid || tcp != TCP_OPEN)
        return 0;
    memcpy(rxbuf, stage, n);
    return n;
}

/* the bytes in crow: lines and packets; a payload's count when one is whole */
static unsigned char feed(void)
{
    unsigned char c, t;
    while (rawp < rawn) {
        if (pst) {
            t = rawn - rawp;
            if (t > pwant)
                t = pwant;
            memcpy(stage + plen, crow + rawp, t);
            plen += t;
            pwant -= t;
            rawp += t;
            if (!pwant && (t = packet()) != 0)
                return t;
            continue;
        }
        c = crow[rawp++];
        if (c == 10) {
            if (trunc || !llen) {
                trunc = llen = 0;
                continue;
            }
            line[llen] = 0;
            llen = 0;
            if (line[0] == '[' && tcp >= TCP_DIAL && header())
                continue;
            on_line();
        } else if (c == 13) {
        } else if (llen < sizeof line - 1)
            line[llen++] = c;
        else
            trunc = 1;
    }
    return 0;
}

/*---------------------------------------------------------------
  what is sent, what comes next
 ---------------------------------------------------------------*/
static void push(void)
{
    while (cmdp < cmdl && ser_txroom())
        ser_byte(cmd[cmdp++]);
    if (op != OP_SEND || cmdp < cmdl)
        return;
    while (sendp < sendn && ser_txroom()) {
        ser_byte(tcp_tx[(tcp_txt + sendp) & (TCP_TXSZ - 1)]);
        ++sendp;
    }
}

static void timeout(void)
{
    unsigned char o = op;
    op = OP_NONE;
    if (o == OP_PULL) {
        pst = llen = 0;
        if (++tries < PULL_TRIES)
            return;             /* (XON again: the firmware may drop one) */
        end(TEV_LOST);
    } else if (o == OP_DIAL)
        end(TEV_TIMEOUT);       /* (ATZ: a late CONNECT hung up with it) */
    else if (tcp == TCP_SETUP)
        end(TEV_NOMODEM);
    else if (tcp == TCP_HANGUP)
        end(TEV_ENDED);
    else if (tcp == TCP_RESET)
        idle();
    else
        end(TEV_LOST);          /* (an ATT not answered) */
}

static void next(void)
{
    unsigned char n;
    if (tcp == TCP_WAIT) {
        if (!syncing) {
            tcp = TCP_SETUP;
            command(profile[0]);
        }
        return;
    }
    if (tcp == TCP_SETUP) {
        command(profile[setup_i]);
        return;
    }
    if (tcp_quit && (tcp == TCP_DIAL || tcp == TCP_OPEN)) {
        tcp_quit = 0;
        if (tcp == TCP_OPEN) {
            tcp = TCP_HANGUP;
            cmdl = put_num(put_str(cmd, "ATH"), cid) - cmd;
            start(OP_CMD, T_CMD);
        } else
            end(TEV_ENDED);
        return;
    }
    if (tcp != TCP_OPEN)
        return;
    n = (tcp_txh - tcp_txt) & (TCP_TXSZ - 1);
    if (n && (flip || lastempty)) {
        flip = 0;
        sendn = n;              /* (TCP_TXSZ - 1 < PKT) */
        sendp = 0;
        cmdl = put_num(put_str(cmd, "ATT"), n) - cmd;
        start(OP_SEND, T_CMD);
        return;
    }
    if (!lastempty || ser_frames != idle_t) {
        flip = 1;
        cmd[0] = XON;
        cmdl = 1;
        cmdp = 0;
        op = OP_PULL;
        ot = ser_frames;
        olen = T_PULL;
    }
}

/* one step (each pass of the main loop, maybe more): a packet's payload
   in rxbuf, its count; 0 none yet */
unsigned char o_tcp_poll(void)
{
    unsigned char n;
    for (;;) {
        n = feed();
        if (n)
            return n;
        if (rawp < rawn)
            continue;
        rawp = 0;
        rawn = ser_get(crow, RAWSZ);
        if (!rawn)
            break;
    }
    if (op != OP_NONE && ser_frames - ot > olen)
        timeout();
    if (op == OP_NONE && tcp)
        next();
    push();
    return 0;
}


/* what happened (tcp_ev): the line state, the log line (the gates), the
   status line, and for a failure or the host's close a box */
void o_tcp_event(void)
{
    static const char *const logs[] = {
        "TERM TCP OPEN", "TERM TCP REFUSED", "TERM TCP NO MODEM", "TERM TCP TIMEOUT",
        "TERM TCP CLOSED", "TERM TCP LOST", "TERM TCP ENDED", "TERM TCP IDLE"
    };
    static const char *const a[] = {
        0, "Could not connect (refused, or no such host):", "The modem does not answer",
        "No answer in 15 seconds from", "The host closed the connection:",
        "The modem stopped answering:"
    };
    unsigned char ev = tcp_ev;
    tcp_ev = 0;
    if (!ev || ev > TEV_IDLE)
        return;
    LogText((void *)logs[ev - 1]);
    if (ev == TEV_OPEN) {
        online = 1;
        online_since = ser_frames;
    } else {
        online = 0;
        tn_reset(0);
        tcp_txh = tcp_txt;
    }
    status();
    if (ev == TEV_OPEN || ev >= TEV_ENDED)
        return;
    strcpy(msga, a[ev - 1]);
    strcpy(msgb, ev == TEV_NOMODEM ? "(is the card's Wi-Fi modem on?)" : ev == TEV_LOST ? "the connection is lost." : (const char *)target);
    msg_box();
}
