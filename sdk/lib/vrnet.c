/* vrnet: TCP sockets through a Zimodem Wi-Fi modem in command mode
   (vrnet.h, docs/NET.md; DECISIONS V98).

   Derived from Packet16 (x16-ftp: zim.c, the packet parser, and
   net_zimodem.c, the AT session; Copyright (c) 2026 Marcin Spoczynski),
   used in Veranda under the MIT licence with its author's permission, and
   rewritten so that nothing waits: Packet16's zn_cmd, zn_pull, net_open
   and net_send spin up to 3 s on the clock; here each is an operation
   that net_poll() starts, feeds with what the modem sends, and ends
   (or times out) on a later pass of the main loop. Kept from Packet16
   as it was proven on the user's card (Zimodem 4.0.2, TexElec's Serial &
   ESP32 Network Card; its docs/ZIMODEM-FRAMING.md):
   - the profile, one command at a time, each OK awaited:
     ATE0V1X1Q0&M&D (V1X1: CONNECT and NO CARRIER carry the channel id;
     &M&D clear the global mask and delimiters, which would delete payload
     bytes), ATS40=254S45=0S0=0 (packets of 254 bytes at most: 255 is the
     firmware's ceiling; raw binary payload), ATF3 (one XON, one packet);
   - ATC"host:port" gives "CONNECT <id>" and leaves the new channel
     current; ATC<id> selects (cached); ATT<n> and n raw bytes, then OK
     (never ATT"...", which appends CR LF); ATH<id> best effort;
     (V114) ATCS"host:port" when the socket was opened with net_tls: the
     modem's TLS connection (unverified on the card: see vrnet.h);
   - an XON gets one packet "[ id size crc ]" CR LF + size raw bytes
     (Dallas/Maxim CRC-8), or "[ id 0 0 ]" (nothing on any channel: its id
     means nothing), or "NO CARRIER <id>" (a close, after that channel's
     data: it uses up the XON); the firmware may drop an XON when its
     buffer is full, so a pull times out and sends XON again;
   - a packet for a socket that has no room would be lost, so XON is
     sent only when every open socket has room for a whole packet;
   - the rate found first (vrsync.c, from Packet16's zn_sync).
   New here: the rate's sync and these steps are state machines with
   deadlines in frames (ser_frames: they stand still while the program is
   put aside); the sockets' buffers are in a RAM bank of their own (the
   receive ring in another, vrser's); a late CONNECT after a timeout is
   hung up; after a timeout the modem is asked "AT" until it answers OK
   (it may still be busy with the command that timed out); before the
   switcher puts the program aside (asideVector), a packet arriving is
   taken whole, so the 16-byte FIFO never has to hold one.

   MIT licence (see LICENSE). */
#include <veranda.h>
#include <vr.h>
#include <string.h>
#include "vrser.h"
#include "vrnet.h"
#include "vrnetp.h"

#define RAMBANK (*(volatile unsigned char *)0)

/* the sockets' bank ($A000) */
#define CRCTAB  ((unsigned char *)0xA000)       /* 256: the CRC-8 table */
#define STAGE   ((unsigned char *)0xA100)       /* 256: a packet's payload */
#define RXBUF(s) ((unsigned char *)0xA200 + ((unsigned int)(s) << 10))
#define TXBUF(s) ((unsigned char *)0xB200 + ((unsigned int)(s) << 8))
#define HOST(s)  ((char *)0xB600 + ((unsigned int)(s) << 6))

/* deadlines, in frames */
#define T_CMD     180           /* a command's OK: 3 s (Packet16's reply_timeout) */
#define T_CONNECT 900           /* ATC: 15 s */
#define T_PULL    30            /* an XON's packet: 0.5 s (Packet16's pull_timeout) */
#define T_RECOVER 1800          /* the modem answering again after a timeout: 30 s */
#define PULL_TRIES 4

struct sock sk[NET_SOCKS];      /* (vrnetp.h's struct; not static since V210: vrahead.c reads them) */

unsigned int net_xtal = SER_X14;
unsigned char net_tls;
void (*net__ahead)(void);       /* (V210: vrahead.c's, once net_ahead_on is called) */
struct net_stats net_stats;

static unsigned char rbank, nbank;
static unsigned char gst;
static signed char gerr;
static unsigned int want;
static unsigned char setup_i;

/* the operation under way: one at a time, as the modem takes them */
#define OP_NONE    0
#define OP_CMD     1
#define OP_CONNECT 2
#define OP_SEND    3
#define OP_PULL    4
#define K_SETUP    0
#define K_SELECT   1
#define K_HANGUP   2
#define K_ORPHAN   3
#define K_RECOVER  4
static unsigned char op, kind, osk, tries;
unsigned char draining;
unsigned int ot;                /* its start (ser_frames) */
static unsigned int olen;       /*   its deadline */
static unsigned char cur = 0xFF;        /* the modem's current channel */
unsigned char orphan;                   /* a late CONNECT's channel, to hang up */
static unsigned char sendn, sendp;      /* ATT's payload: its size, pushed so far */
static char cmd[80];
static unsigned char cmdl, cmdp;        /* the command line: its length, pushed so far */
static unsigned char lastempty, flip;
unsigned char nxt;                      /* (V210) an XON sent ahead: its answer comes after this one's */
static unsigned int idle_t;
static unsigned char reply;             /* the sync: 1 OK, 2 ERROR seen */
unsigned char hold;                     /* no new pull yet: just back */
static unsigned int hold_t;
#define HOLD 10

/* the parser (Packet16's zim.c, its payload into STAGE) */
static unsigned char pst;               /* 0 a line, 1 a payload */
static char line[80];
static unsigned char llen, trunc;
static unsigned char pch, hascrc, crcw;
static unsigned int pwant, plen;
static unsigned char raw[64];

static const char *const profile[] = {
    "ATE0V1X1Q0&M&D", "ATS40=254S45=0S0=0", "ATF3", "ATH0"
};

/*---------------------------------------------------------------
  the CRC-8 (Dallas/Maxim: polynomial $8C reflected, init 0): a table in
  the sockets' bank, made at start
 ---------------------------------------------------------------*/
static void crc_table(void)
{
    unsigned char i = 0, c, k;
    do {
        c = i;
        for (k = 8; k; --k)
            c = (c & 1) ? (c >> 1) ^ 0x8C : c >> 1;
        CRCTAB[i] = c;
    } while (++i);
}

/* over STAGE's first n bytes (n <= 255; the firmware's byte length):
   vrnetcrc.s's loop (V210: some 17 cycles a byte, the C one's 60) */
unsigned char __fastcall__ net_crc8(unsigned char n);

/*---------------------------------------------------------------
  helpers
 ---------------------------------------------------------------*/
static char *put_num(char *p, unsigned int v)
{
    char t[5];
    unsigned char n = 0;
    do {
        t[n++] = '0' + v % 10;
        v /= 10;
    } while (v);
    while (n)
        *p++ = t[--n];
    return p;
}

static unsigned char num(const char *s)
{
    unsigned char v = 0;
    while (*s == ' ')
        ++s;
    while (*s >= '0' && *s <= '9')
        v = v * 10 + (*s++ - '0');
    return v;
}

static struct sock *by_id(unsigned char id)
{
    unsigned char i;
    for (i = 0; i < NET_SOCKS; ++i)
        if (sk[i].st >= NET_OPEN && sk[i].st <= NET_EOF && sk[i].id == id)
            return &sk[i];
    return 0;
}

static void fail(struct sock *s, signed char e)
{
    if (s->st == NET_CLOSING && !s->id) {
        s->st = NET_FREE;       /* (closed while it was being made) */
        return;
    }
    s->st = NET_FAILED;
    s->err = e;
}

static void fault(signed char e)
{
    gst = NET_FAULT;
    gerr = e;
    op = OP_NONE;
}

static unsigned int rx_used(const struct sock *s)
{
    return (s->rxh - s->rxt) & (RXSZ - 1);
}

/* a command line: built in cmd, pushed by push() */
static void start(unsigned char o, unsigned char k, unsigned int t)
{
    cmd[cmdl++] = 13;
    cmdp = 0;
    op = o;
    kind = k;
    ot = ser_frames;
    olen = t;
}

static void command(const char *s, unsigned char k)
{
    strcpy(cmd, s);
    cmdl = strlen(s);
    start(OP_CMD, k, T_CMD);
}

static void cmd_id(const char *at, unsigned char id, unsigned char k)
{
    cmdl = put_num(strcpy(cmd, at) + 3, id) - cmd;
    start(OP_CMD, k, T_CMD);
}

static void recover(void)
{
    command("AT", K_RECOVER);
    olen = T_RECOVER;
    pst = 0;
    llen = 0;
}

/*---------------------------------------------------------------
  the operations' ends
 ---------------------------------------------------------------*/
static void done(void)
{
    op = OP_NONE;
}

/* (V210) a pull's answer has come: the pull ends, or, with an XON sent
   ahead, goes on for that one's answer (it follows on the line) */
static void answered(void)
{
    tries = 0;
    if (nxt) {
        nxt = 0;
        ot = ser_frames;
    } else
        done();
}

static void op_ok(void)
{
    struct sock *s = &sk[osk];
    if (op == OP_SEND) {
        if (cmdp < cmdl || sendp < sendn)
            return;             /* (not ours: the payload is not all out) */
        s->txt += sendn;
        ++net_stats.sends;
    } else if (op != OP_CMD)
        return;
    else if (kind == K_SETUP) {
        if (++setup_i == sizeof profile / sizeof profile[0])
            gst = NET_READY;
    } else if (kind == K_SELECT)
        cur = s->id;
    else if (kind == K_HANGUP) {
        if (cur == s->id)
            cur = 0xFF;
        s->st = NET_FREE;
    } else if (kind == K_ORPHAN)
        orphan = 0;
    done();
}

static void op_err(void)
{
    struct sock *s = &sk[osk];
    if (op == OP_CONNECT || op == OP_SEND)
        fail(s, NET_ERR);
    else if (op != OP_CMD)
        return;
    else if (kind == K_RECOVER)
        return;                 /* (a late answer to what timed out) */
    else if (kind == K_SETUP) {
        if (setup_i < 3) {
            fault(NET_ERR);
            return;
        }
        gst = NET_READY;        /* (ATH0: best effort) */
    } else if (kind == K_SELECT)
        fail(s, NET_ERR);
    else if (kind == K_HANGUP)
        s->st = NET_FREE;
    else if (kind == K_ORPHAN)
        orphan = 0;
    done();
}

static void timeout(void)
{
    struct sock *s = &sk[osk];
    unsigned char k = kind, o = op;
    done();
    nxt = 0;                    /* (an answer to the one sent ahead may still come: as one late) */
    if (o == OP_PULL) {
        if (pst) {              /* a packet cut short: its data lost */
            pst = 0;
            s = by_id(pch);
            if (s)
                fail(s, NET_EIO);
        }
        llen = 0;
        if (++tries < PULL_TRIES) {
            ++net_stats.xon_retries;
            return;             /* (the next pass: XON again) */
        }
        recover();
        return;
    }
    if (o == OP_CMD) {
        if (k == K_SETUP || k == K_RECOVER) {
            fault(gst == NET_SETUP && setup_i == 0 ? NET_ENOMODEM : NET_ETIMEOUT);
            return;
        }
        if (k == K_HANGUP)
            s->st = NET_FREE;
        if (k == K_SELECT)
            fail(s, NET_ETIMEOUT);
        if (k == K_ORPHAN)
            orphan = 0;
    } else
        fail(s, NET_ETIMEOUT);  /* (the connect, or the send) */
    recover();
}

/*---------------------------------------------------------------
  what the modem sends
 ---------------------------------------------------------------*/
static void on_line(void)
{
    struct sock *s;
    unsigned char i;
    if (!strcmp(line, "OK")) {
        reply = 1;
        if (op == OP_CMD || op == OP_SEND)
            op_ok();
    } else if (!strcmp(line, "ERROR")
               || (op == OP_CONNECT && (*line == 'B' || (*line == 'N' && line[3] == 'A')))) {
        /* (BUSY, NO ANSWER: the real firmware's answer to an ATC refused
           or a host that is not there, where the emulator says ERROR:
           refused at once, not after the 15 s timeout, V113) */
        reply = 2;
        if (op == OP_CMD || op == OP_SEND || op == OP_CONNECT)
            op_err();
    } else if (!memcmp(line, "CONNECT", 7)) {
        i = num(line + 7);
        if (op == OP_CONNECT && i) {
            s = &sk[osk];
            if (s->st == NET_DIAL)
                s->st = NET_OPEN;       /* (else closed meanwhile: hung up next) */
            s->id = i;
            cur = i;            /* (ATC leaves the new channel current) */
            done();
        } else if (i) {
            orphan = i;         /* (after its timeout: hung up) */
            ++net_stats.orphans;
        }
    } else if (!memcmp(line, "NO CARRIER", 10)) {
        i = num(line + 10);
        if (i) {
            s = by_id(i);
            if (s && s->st == NET_CLOSING)
                s->txt = s->txh;        /* (V138: it stays closing, its ATH next: that frees the modem's node) */
            else if (s && s->st != NET_FAILED)
                s->st = NET_EOF;
            if (cur == i)
                cur = 0xFF;
        } else {
            /* no id: which one cannot be told, so all (Packet16) */
            for (i = 0; i < NET_SOCKS; ++i)
                if (sk[i].st == NET_OPEN)
                    fail(&sk[i], NET_ECLOSED);
        }
        if (op == OP_PULL)
            answered();         /* (it used up the XON) */
    }
}

/* "[ a b ]", "[ a b c ]", "[ a b c d ]": ch sz | ch sz crc | ch num sz crc
   (ATS45 0, 3 or 4, told apart by the count, as Packet16 does) */
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
    pch = v[0];
    hascrc = n > 2;
    pwant = n == 4 ? v[2] : v[1];
    crcw = v[n - 1];
    plen = 0;
    if (!pwant) {
        ++net_stats.empties;
        if (op == OP_PULL) {
            lastempty = 1;
            idle_t = ser_frames;
            answered();
        }
        return 1;
    }
    if (pwant > 256) {          /* (corruption, not a big packet) */
        pwant = 0;
        return 1;
    }
    pst = 1;
    if (net__ahead && op == OP_PULL && !nxt)
        net__ahead();           /* (V210: vrahead.c, the next XON at once) */
    return 1;
}

static void packet(void)
{
    struct sock *s = by_id(pch);
    unsigned int i, h;
    unsigned char *r;
    pst = 0;
    llen = 0;
    if (op == OP_PULL) {
        lastempty = 0;
        answered();
    }
    if (hascrc && (plen > 255 ? 0 : net_crc8(plen)) != crcw) {    /* (256: the firmware's CRC covers nothing) */
        ++net_stats.badcrc;
        if (s)
            fail(s, NET_EBADCRC);
        return;
    }
    ++net_stats.packets;
    if (!s || s->st == NET_FAILED)
        return;                 /* (for a socket closed meanwhile) */
    if (RXSZ - 1 - rx_used(s) < plen) {
        fail(s, NET_EIO);       /* (cannot happen: XON only with room) */
        return;
    }
    r = RXBUF(s - sk);
    h = s->rxh;
    i = RXSZ - h;               /* (up to the ring's end, then from its start) */
    if (i > plen)
        i = plen;
    memcpy(r + h, STAGE, i);
    memcpy(r, STAGE + i, plen - i);
    s->rxh = (h + plen) & (RXSZ - 1);
}

static void feed(unsigned char n)
{
    unsigned char *p = raw, c;
    unsigned int t;
    while (n) {
        if (pst) {
            t = pwant < n ? pwant : n;
            memcpy(STAGE + plen, p, t);
            plen += t;
            pwant -= t;
            p += t;
            n -= t;
            if (!pwant)
                packet();
            continue;
        }
        c = *p++;
        --n;
        if (c == 10) {
            if (trunc) {
                trunc = llen = 0;
                continue;
            }
            if (!llen)
                continue;
            line[llen] = 0;
            llen = 0;
            if (line[0] == '[' && gst == NET_READY && header())
                continue;
            on_line();
        } else if (c == 13) {
        } else if (llen < sizeof line - 1)
            line[llen++] = c;
        else
            trunc = 1;
    }
}

/*---------------------------------------------------------------
  what is sent: the command line, then ATT's payload
 ---------------------------------------------------------------*/
static void push(void)
{
    unsigned char *t;
    struct sock *s;
    while (cmdp < cmdl && ser_txroom())
        ser_byte(cmd[cmdp++]);
    if (op != OP_SEND || cmdp < cmdl)
        return;
    s = &sk[osk];
    t = TXBUF(osk);
    while (sendp < sendn && ser_txroom()) {
        ser_byte(t[(unsigned char)(s->txt + sendp)]);
        ++sendp;
    }
}

/*---------------------------------------------------------------
  what to do next (nothing under way)
 ---------------------------------------------------------------*/
static void schedule(void)
{
    unsigned char i, pull = 0, room = 1;
    signed char snd = -1;
    struct sock *s;
    char *p;
    if (orphan) {
        cmd_id("ATH", orphan, K_ORPHAN);
        return;
    }
    for (i = 0; i < NET_SOCKS; ++i) {
        s = &sk[i];
        osk = i;
        if (s->st == NET_CLOSING && s->txh == s->txt) {
            cmd_id("ATH", s->id, K_HANGUP);
            return;
        }
        if (s->st == NET_OPENING) {
            p = cmd;
            *p++ = 'A';
            *p++ = 'T';
            *p++ = 'C';
            strcpy(p, HOST(i));         /* (its '"', after V114's S if TLS) */
            p += strlen(p);
            *p++ = ':';
            p = put_num(p, s->port);
            *p++ = '"';
            cmdl = p - cmd;
            s->st = NET_DIAL;
            start(OP_CONNECT, 0, T_CONNECT);
            return;
        }
        if (s->st == NET_OPEN || s->st == NET_CLOSING) {
            pull = 1;
            if (s->txh != s->txt && snd < 0)
                snd = i;
            if (s->st == NET_OPEN && RXSZ - 1 - rx_used(s) < PKT)
                room = 0;
        }
    }
    if (snd >= 0 && (flip || !pull || !room)) {
        flip = 0;
        s = &sk[osk = snd];
        if (cur != s->id) {
            cmd_id("ATC", s->id, K_SELECT);
            return;
        }
        sendn = s->txh - s->txt;
        if (sendn > PKT)
            sendn = PKT;
        sendp = 0;
        cmdl = put_num(strcpy(cmd, "ATT") + 3, sendn) - cmd;
        start(OP_SEND, 0, T_CMD);
        return;
    }
    if (pull && room && !hold && (!lastempty || ser_frames != idle_t)) {
        flip = 1;
        cmd[0] = XON;
        cmdl = 1;
        cmdp = 0;
        op = OP_PULL;
        ot = ser_frames;
        olen = T_PULL;
        ++net_stats.pulls;
    }
}

static void step(void)
{
    unsigned char b = RAMBANK, i, n;
    RAMBANK = nbank;
    for (i = 0; i < 8; ++i) {
        n = ser_get(raw, sizeof raw);
        if (!n)
            break;
        feed(n);
    }
    if (gst == NET_SYNC) {
        n = ser_sync_tick(reply);
        reply = 0;
        if (ser_sync_new) {
            ser_sync_new = 0;
            llen = 0;
        }
        if (n == 1) {
            gst = NET_SETUP;
            setup_i = 0;
        } else if (n == 2)
            fault(NET_ENOMODEM);
    }
    if (op != OP_NONE && ser_frames - ot > olen)
        timeout();
    if (op == OP_NONE && !draining && gst == NET_SETUP)
        command(profile[setup_i], K_SETUP);
    else if (op == OP_NONE && !draining && gst == NET_READY)
        schedule();
    push();
    RAMBANK = b;
}

/* asideVector: the switcher is about to put the program aside. SerIrq
   stops being called next, and a packet that is arriving would overrun
   the FIFO: what is under way that brings more than the FIFO holds (an
   XON's packet, the rest of a payload to send) is finished first, at
   most 0.75 s; nothing new is started. */
static void net_aside(void)
{
    unsigned int t = ser_frames;
    draining = 1;
    while ((op == OP_PULL || (op == OP_SEND && sendp < sendn) || cmdp < cmdl) && ser_frames - t < 45)
        step();
    draining = 0;
    ser_aside();
}

/*---------------------------------------------------------------
  the API
 ---------------------------------------------------------------*/
signed char __fastcall__ net_start(unsigned char port, unsigned int baud100)
{
    unsigned char b;
    if (gst != NET_OFF)
        net_stop();
    if (!port)
        port = ser_probe();
    if (!port || !ser_at(port))
        return NET_ENOCARD;
    rbank = BankAlloc(2);
    if (!rbank)
        return NET_ENOBANKS;
    nbank = rbank + 1;
    ser_rxbank = rbank;
    b = RAMBANK;
    RAMBANK = nbank;
    crc_table();
    RAMBANK = b;
    memset(sk, 0, sizeof sk);
    memset(&net_stats, 0, sizeof net_stats);
    op = OP_NONE;
    cur = 0xFF;
    orphan = pst = llen = trunc = cmdl = cmdp = lastempty = draining = nxt = 0;
    gerr = 0;
    want = baud100 ? baud100 : 576;
    ser_fast = 1;
    intFirstVector = VR_FN(SerIrq);
    asideVector = VR_FN(net_aside);
    ser_open(port, ser_div(net_xtal, want), 0);
    ser_sync(net_xtal, want);
    gst = NET_SYNC;
    return NET_OK;
}

void net_stop(void)
{
    unsigned int t;
    if (gst == NET_OFF)
        return;
    t = ser_frames;
    if (ser_on == 1 && gst != NET_SYNC) {
        /* the payload under way first (else ATH0 would be part of it) */
        if (gst == NET_READY) {
            while ((cmdp < cmdl || (op == OP_SEND && sendp < sendn)) && ser_frames - t < 30) {
                unsigned char b = RAMBANK;
                RAMBANK = nbank;
                push();
                RAMBANK = b;
            }
        }
        ser_byte('A');
        ser_byte('T');
        ser_byte('H');
        ser_byte('0');
        ser_byte(13);
        while (!ser_sent() && ser_frames - t < 30)
            ;
    }
    ser_stop();
    asm("sei");
    intFirstVector = 0;
    asideVector = 0;
    asm("cli");
    ser_asleep = 0;
    BankFree(rbank);
    memset(sk, 0, sizeof sk);
    op = OP_NONE;
    gst = NET_OFF;
}

void net_poll(void)
{
    if (gst == NET_OFF || gst == NET_FAULT)
        return;
    if (ser_wake()) {           /* (back from the switcher: V91) */
        hold = 1;
        hold_t = ser_frames;
    }
    if (hold && ser_frames - hold_t > HOLD)
        hold = 0;
    step();
}

unsigned char net_state(void)
{
    return gst;
}

signed char net_error(void)
{
    return gerr;
}

signed char __fastcall__ net_open(const char *host, unsigned int port)
{
    unsigned char i, n, c, b;
    char *p;
    struct sock *k;
    if (gst == NET_OFF || gst == NET_FAULT)
        return NET_ESTATE;
    for (n = 0; (c = host[n]); ++n)
        if (n >= 61 || !((c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') || c == '.' || c == '-'))
            return NET_EBADARG; /* (x16net's rule: no AT command can be smuggled in) */
    if (!n || !port)
        return NET_EBADARG;
    for (i = 0, k = sk; i < NET_SOCKS && k->st != NET_FREE; ++i, ++k)
        ;
    if (i == NET_SOCKS)
        return NET_ENOSOCK;
    memset(k, 0, sizeof *k);
    k->port = port;
    b = RAMBANK;
    RAMBANK = nbank;
    p = HOST(i);                /* (what follows ATC: V114's S for TLS, '"', the host) */
    if (net_tls)
        *p++ = 'S';
    *p++ = '"';
    strcpy(p, host);
    RAMBANK = b;
    k->st = NET_OPENING;
    return i;
}

unsigned char __fastcall__ net_sock(signed char s)
{
    return (unsigned char)s < NET_SOCKS ? sk[s].st : NET_FREE;
}

signed char __fastcall__ net_sockerr(signed char s)
{
    return (unsigned char)s < NET_SOCKS ? sk[s].err : NET_ENOSOCK;
}

unsigned int __fastcall__ net_avail(signed char s)
{
    return (unsigned char)s < NET_SOCKS ? rx_used(&sk[s]) : 0;
}

unsigned int __fastcall__ net_room(signed char s)
{
    return (unsigned char)s < NET_SOCKS ? (unsigned char)(sk[s].txt - sk[s].txh - 1) : 0;
}

int __fastcall__ net_read(signed char s, void *buf, unsigned int n)
{
    struct sock *k;
    unsigned int a, i, t;
    unsigned char *r, *d = buf, b;
    if ((unsigned char)s >= NET_SOCKS || sk[s].st == NET_FREE)
        return NET_ENOSOCK;
    k = &sk[s];
    a = rx_used(k);
    if (!a) {
        if (k->st == NET_FAILED)
            return k->err;
        return k->st == NET_EOF ? NET_ECLOSED : 0;
    }
    if (n > a)
        n = a;
    r = RXBUF(s);
    t = k->rxt;
    i = RXSZ - t;
    if (i > n)
        i = n;
    b = RAMBANK;
    RAMBANK = nbank;
    memcpy(d, r + t, i);
    memcpy(d + i, r, n - i);
    RAMBANK = b;
    k->rxt = (t + n) & (RXSZ - 1);
    return n;
}

int __fastcall__ net_write(signed char s, const void *buf, unsigned int n)
{
    struct sock *k;
    unsigned int i, room;
    unsigned char *w;
    const unsigned char *p = buf;
    unsigned char b;
    if ((unsigned char)s >= NET_SOCKS || sk[s].st == NET_FREE)
        return NET_ENOSOCK;
    k = &sk[s];
    if (k->st == NET_FAILED)
        return k->err;
    if (k->st > NET_OPEN)
        return NET_ECLOSED;
    room = (unsigned char)(k->txt - k->txh - 1);
    if (n > room)
        n = room;
    w = TXBUF(s);
    b = RAMBANK;
    RAMBANK = nbank;
    for (i = 0; i < n; ++i)
        w[k->txh++] = p[i];
    RAMBANK = b;
    return n;
}

void __fastcall__ net_close(signed char s)
{
    struct sock *k;
    if ((unsigned char)s >= NET_SOCKS)
        return;
    k = &sk[s];
    if (k->st == NET_OPEN || k->st == NET_DIAL)
        k->st = NET_CLOSING;    /* (its data out first, or its CONNECT; then ATH) */
    else if ((k->st == NET_FAILED || k->st == NET_EOF) && k->id) {
        /* (the channel may still be there: ATH. After NO CARRIER too
           (V138): Zimodem keeps a client's node, with its
           WiFiClientSecure, until ATH<id> deletes it (zcommand.ino's
           doHangupCommand; sendNextPacket deletes only a server's
           clients), so every connection the far end closed stayed on the
           ESP32's heap. The emulator has freed it: ERROR, also FREE) */
        k->txt = k->txh;
        k->st = NET_CLOSING;
    } else if (k->st != NET_CLOSING)
        k->st = NET_FREE;       /* (opening: never sent) */
}
