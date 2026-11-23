/* Veranda FTP: the FTP client (main RAM; DECISIONS V100).

   Packet16's ftp.c (Marcin Spoczynski's FTP client for the X16, used
   here under the MIT licence with his permission), rewritten so that
   nothing waits: ftp_start begins an operation, ftp_poll (every pass of
   the main loop) moves it on a step at a time over vrnet (sdk vrnet.h,
   docs/NET.md), and returns the operation when it has ended (ferr says
   how). Kept from Packet16:
     - the reply parser: "NNN text", or "NNN-" up to "NNN " (a line that
       is too long keeps its code); FEAT's body read for MLSD;
     - PASV, its address ignored: the data connection goes to the control
       connection's host on the port it names (Packet16's D40: a server
       behind NAT names the wrong address);
     - the transfer's two ends tracked apart (the data's close and the
       final reply race; a 5xx comes with no data at all);
     - the data connection closed whatever happened (a socket left open
       stops the next transfer);
     - after a transfer that went wrong, NOOP until its 200 (the control
       connection back in step: Packet16's ftp_resync);
     - MLSD when FEAT names it, LIST when the server refuses it.
   Every open socket is read on every pass (vrnet pulls a packet only when
   each has room for one).

   MIT licence (see LICENSE). */
#include <veranda.h>
#include <string.h>
#include <vrnet.h>
#include <vrser.h>
#include "ftp.h"

#define FS_IDLE  0
#define FS_OPEN  1              /* the control connection being made */
#define FS_WAIT  2              /* a command sent, its reply awaited */
#define FS_DOPEN 3              /* the data connection being made */
#define FS_XFER  4              /* a transfer: the data and the final reply */

#define T_REPLY  1800           /* frames: a reply (30 s) */
#define T_IDLE   3600           /* a transfer with nothing moving (60 s) */
#define T_QUIT   300

#define X_LIST   0
#define X_RETR   1
#define X_STOR   2
#define S_PASV   100            /* fstep of the transfer's PASV */

unsigned char fop, ferr, logged, use_mlsd, xfer_data;
signed char fnet;
unsigned int fcode;
char ftext[FTP_LINE];
char rpath[NAMEMAX + 16];
char fa[NAMEMAX], fb[NAMEMAX];
struct site cur;

static signed char ctl = -1, dsk = -1;
static unsigned char fst, fstep, fdone, xkind;
static unsigned int t0, tlen;
static unsigned char has_mlsd, syncing, perr;
static unsigned char got_prelim, got_final, data_done;

/* the control connection's bytes not parsed yet: a packet may hold two
   replies (Packet16) */
static unsigned char rx[128];
static unsigned char rx_len, rx_off;
static char rline[FTP_LINE];
static unsigned char rline_len, in_multi;
static char multi[3];

static char cmdb[NAMEMAX + 12];
static unsigned char cmd_n, cmd_p;

/* a transfer's buffer (below $A000: net_read, FRead) */
static unsigned char xb[512];
static unsigned int xb_n, xb_p;
static unsigned char xb_eof;

static unsigned char is_digit(char c)
{
    return c >= '0' && c <= '9';
}

/* a byte of the control connection; 1: a whole reply (fcode, ftext) */
static unsigned char reply_byte(char c)
{
    if (c != '\n') {
        if (rline_len < FTP_LINE - 1)
            rline[rline_len++] = c;     /* (a longer line keeps its start: the code) */
        return 0;
    }
    if (rline_len && rline[rline_len - 1] == '\r')
        --rline_len;
    rline[rline_len] = 0;
    if (in_multi) {
        if (rline_len >= 5 && (!memcmp(rline + 1, "MLSD", 4) || !memcmp(rline + 1, "MLST", 4)))
            has_mlsd = 1;
        rline_len = 0;
        if (rline[3] == ' ' && !memcmp(rline, multi, 3)) {
            in_multi = 0;
            return 1;
        }
        return 0;
    }
    if (rline_len >= 3 && is_digit(rline[0]) && is_digit(rline[1]) && is_digit(rline[2])) {
        fcode = (rline[0] - '0') * 100 + (rline[1] - '0') * 10 + (rline[2] - '0');
        strcpy(ftext, rline);
        rline_len = 0;
        if (rline[3] == '-') {
            memcpy(multi, rline, 3);
            in_multi = 1;
            return 0;
        }
        return 1;
    }
    rline_len = 0;                      /* not a reply's line */
    return 0;
}

/* 1: a reply came; 0: none yet; -1: the connection is gone */
static signed char ctl_read(void)
{
    int n;
    for (;;) {
        if (rx_off == rx_len) {
            n = net_read(ctl, rx, sizeof rx);
            if (n == 0)
                return 0;
            if (n < 0)
                return -1;
            rx_len = n;
            rx_off = 0;
        }
        while (rx_off < rx_len)
            if (reply_byte(rx[rx_off++]))
                return 1;
    }
}

static void push_cmd(void)
{
    int k;
    if (cmd_p < cmd_n) {
        k = net_write(ctl, cmdb + cmd_p, cmd_n - cmd_p);
        if (k > 0)
            cmd_p += k;
    }
}

/* "VERB arg" CR LF sent; its reply awaited */
static void __fastcall__ cmd2(const char *verb, const char *arg)
{
    unsigned char n = 0;
    while (*verb)
        cmdb[n++] = *verb++;
    if (arg && *arg) {
        cmdb[n++] = ' ';
        while (*arg && n < sizeof cmdb - 2)
            cmdb[n++] = *arg++;
    }
    cmdb[n++] = '\r';
    cmdb[n++] = '\n';
    cmd_n = n;
    cmd_p = 0;
    fst = FS_WAIT;
    t0 = ser_frames;
    tlen = T_REPLY;
    push_cmd();
}

static void __fastcall__ cmd(const char *verb)
{
    cmd2(verb, 0);
}

static void drop(void)
{
    if (dsk >= 0)
        net_close(dsk);
    if (ctl >= 0)
        net_close(ctl);
    ctl = dsk = -1;
    logged = 0;
    fst = FS_IDLE;
}

void ftp_drop(void)
{
    if (fop == OP_RETR || fop == OP_STOR)
        xf_close(0);
    drop();
    fop = OP_NONE;
    syncing = 0;
    xfer_data = 0;
}

static void close_data(void)
{
    if (dsk >= 0) {
        net_close(dsk);
        dsk = -1;
    }
}

/* the op ends with e */
static void __fastcall__ end(unsigned char e)
{
    unsigned char quit = fop == OP_QUIT;
    close_data();
    if (fop == OP_RETR || fop == OP_STOR)
        xf_close(e == FE_OK);
    ferr = e;
    fdone = fop;
    fop = OP_NONE;
    fst = FS_IDLE;
    syncing = 0;
    xfer_data = 0;
    if (!logged || e == FE_TIMEOUT || e == FE_CLOSED || e == FE_MODEM || quit)
        drop();
}

/* after a transfer that went wrong: NOOP until its 200, then end with e */
static void __fastcall__ resync(unsigned char e)
{
    close_data();
    perr = e;
    xfer_data = 0;
    cmd("NOOP");
    syncing = 1;
}

/* the port of "227 Entering Passive Mode (h1,h2,h3,h4,p1,p2)": six
   numbers in a row, wherever they are (Packet16's ftp_parse_pasv); 0 none */
static unsigned int pasv_port(const char *s)
{
    unsigned int v[6], acc;
    unsigned char n = 0, digits;
    s += 3;                             /* (past the code) */
    while (*s && n < 6) {
        if (is_digit(*s)) {
            acc = 0;
            digits = 0;
            while (is_digit(*s)) {
                if (++digits > 3)
                    return 0;
                acc = acc * 10 + (*s++ - '0');
            }
            v[n++] = acc;
            if (*s == ',')
                ++s;
            else if (n < 6)
                n = 0;
        } else
            ++s;
    }
    if (n != 6 || v[4] > 255 || v[5] > 255)
        return 0;
    return v[4] * 256 + v[5];
}

/* "257 "/the/folder" is the current directory" */
static void pwd_path(void)
{
    const char *s = strchr(ftext, '"');
    unsigned char n = 0;
    if (!s)
        return;
    for (++s; *s && n < sizeof rpath - 1; ++s) {
        if (*s == '"') {
            if (s[1] != '"')
                break;
            ++s;                        /* ("" is a quote) */
        }
        rpath[n++] = *s;
    }
    rpath[n] = 0;
}

static void __fastcall__ xfer(unsigned char kind)
{
    xkind = kind;
    fstep = S_PASV + 1;
    cmd("PASV");
}

static void xfer_end(void)
{
    if (xkind == X_LIST)
        rlist_end();
    end(FE_OK);
}

/* a reply while the transfer runs */
static void xfer_reply(void)
{
    t0 = ser_frames;
    if (fcode < 200)
        got_prelim = 1;
    else if (fcode < 300)
        got_final = 1;
    else {
        close_data();
        if (xkind == X_LIST && use_mlsd && fcode >= 500) {
            use_mlsd = 0;               /* (named in FEAT, refused: LIST from now on) */
            xfer(X_LIST);
            return;
        }
        end(FE_REPLY);
    }
}

/* the data connection's step */
static void xfer_data_step(void)
{
    int n;
    if (xkind != X_STOR) {
        if (dsk < 0)
            return;
        n = net_read(dsk, xb, sizeof xb);
        if (n > 0) {
            t0 = ser_frames;
            if (xkind == X_LIST)
                rlist_feed(xb, n);
            else if (!xf_write(xb, n)) {
                resync(FE_LOCAL);
                return;
            } else
                xf_pos += n;
        } else if (n == NET_ECLOSED) {
            close_data();
            data_done = 1;
        } else if (n < 0) {
            fnet = n;
            resync(FE_NET);
        }
        return;
    }
    if (!got_prelim || data_done)
        return;
    if (xb_p == xb_n && !xb_eof) {
        xb_n = xf_read(xb, sizeof xb);
        xb_p = 0;
        if (!xb_n)
            xb_eof = 1;
    }
    if (xb_p < xb_n) {
        n = net_write(dsk, xb + xb_p, xb_n - xb_p);
        if (n > 0) {
            xb_p += n;
            xf_pos += n;
            t0 = ser_frames;
        } else if (n < 0) {
            fnet = n;
            resync(FE_NET);
            return;
        }
    }
    if (xb_eof && xb_p == xb_n) {
        close_data();                   /* (its close is the file's end for the server) */
        data_done = 1;
    }
}

static void refused(void)
{
    end(FE_REPLY);
}

#define OK2 (fcode / 100 == 2)

/* a command's final reply */
static void advance(void)
{
    unsigned char s = fstep++;
    unsigned int port;
    if (s == S_PASV + 1) {
        if (fcode != 227 || (port = pasv_port(ftext)) == 0) {
            if (fcode != 227)
                refused();
            else
                end(FE_PROTO);
            return;
        }
        dsk = net_open(cur.host, port);
        if (dsk < 0) {
            fnet = dsk;
            dsk = -1;
            end(FE_NET);
            return;
        }
        fst = FS_DOPEN;
        return;
    }
    switch (fop) {
    case OP_CONNECT:
        switch (s) {
        case 0:                         /* the banner */
            if (fcode != 220)
                break;
            cmd2("USER", cur.user[0] ? cur.user : "anonymous");
            return;
        case 1:                         /* USER */
            if (fcode == 331 || fcode == 332) {
                cmd2("PASS", cur.pass[0] || cur.user[0] ? cur.pass : "veranda@x16");
                return;
            }
            /* (fall through: logged in without a password) */
        case 2:                         /* PASS */
            if (!OK2)
                break;
            logged = 1;
            fstep = 3;
            cmd2("TYPE", "I");
            return;
        case 3:                         /* TYPE I: binary, for every transfer */
            if (!OK2)
                break;
            has_mlsd = 0;
            cmd("FEAT");
            return;
        case 4:                         /* FEAT (refused: LIST) */
            use_mlsd = has_mlsd;
            if (cur.dir[0]) {
                cmd2("CWD", cur.dir);
                return;
            }
            ++fstep;
            /* (fall through) */
        case 5:                         /* the start folder (refused: where the login put us) */
            cmd("PWD");
            return;
        case 6:
            pwd_path();
            xfer(X_LIST);
            return;
        }
        refused();
        return;
    case OP_CWD:
        if (s == 0) {
            if (!OK2)
                break;
            cmd("PWD");
            return;
        }
        pwd_path();
        xfer(X_LIST);
        return;
    case OP_RENAME:
        if (s == 0) {
            if (fcode != 350)
                break;
            cmd2("RNTO", fb);
            return;
        }
        /* (fall through) */
    case OP_MKD:
    case OP_DELE:
    case OP_RMD:
        if (!OK2)
            break;
        end(FE_OK);
        return;
    case OP_QUIT:
        end(FE_OK);
        return;
    }
    refused();
}

static void reply(void)
{
    if (syncing) {
        if (fcode == 200)
            end(perr);
        return;
    }
    if (fst == FS_XFER) {
        xfer_reply();
        return;
    }
    if (fst != FS_WAIT || fcode < 200)
        return;                         /* (a 1xx: the final reply follows) */
    advance();
}

unsigned char __fastcall__ ftp_start(unsigned char op)
{
    if (fop != OP_NONE)
        return 0;
    ferr = FE_OK;
    fnet = 0;
    if (op != OP_CONNECT && (!logged || ctl < 0)) {
        fop = op;
        end(FE_CLOSED);
        return 1;
    }
    fop = op;
    fstep = 0;
    syncing = 0;
    switch (op) {
    case OP_CONNECT:
        drop();
        logged = has_mlsd = use_mlsd = 0;
        rpath[0] = 0;
        rx_len = rx_off = rline_len = in_multi = 0;
        fst = FS_OPEN;
        t0 = ser_frames;
        if (!net_on)
            end(FE_MODEM);
        break;
    case OP_LIST:
        xfer(X_LIST);
        break;
    case OP_CWD:
        if (fa[0] == '.' && fa[1] == '.' && !fa[2])
            cmd("CDUP");
        else
            cmd2("CWD", fa);
        break;
    case OP_RETR:
    case OP_STOR:
        xfer(op == OP_RETR ? X_RETR : X_STOR);
        break;
    case OP_MKD:
        cmd2("MKD", fa);
        break;
    case OP_DELE:
        cmd2("DELE", fa);
        break;
    case OP_RMD:
        cmd2("RMD", fa);
        break;
    case OP_RENAME:
        cmd2("RNFR", fa);
        break;
    case OP_QUIT:
        cmd("QUIT");
        tlen = T_QUIT;
        break;
    }
    return 1;
}

/* Esc: the transfer stopped (the control connection put back in step) */
void ftp_cancel(void)
{
    if (fst == FS_XFER || fst == FS_DOPEN) {
        resync(FE_CANCEL);
        return;
    }
    if (fst == FS_OPEN && fop == OP_CONNECT)
        end(FE_CANCEL);
}

unsigned char ftp_poll(void)
{
    signed char r;
    unsigned char d;
    net_poll();
    if (fst == FS_OPEN) {               /* the control connection */
        if (net_state() == NET_FAULT) {
            end(FE_MODEM);
        } else if (ctl < 0) {
            if (net_state() == NET_READY) {
                ctl = net_open(cur.host, cur.port ? cur.port : 21);
                if (ctl < 0) {
                    fnet = ctl;
                    ctl = -1;
                    end(FE_NET);
                }
            }
        } else if (net_sock(ctl) == NET_OPEN) {
            fst = FS_WAIT;              /* the banner awaited */
            t0 = ser_frames;
            tlen = T_REPLY;
            cmd_n = cmd_p = 0;
        } else if (net_sock(ctl) == NET_FAILED) {
            fnet = net_sockerr(ctl);
            end(FE_NET);
        }
    }
    if (ctl >= 0 && fst != FS_OPEN) {
        push_cmd();
        r = ctl_read();
        if (r < 0) {                    /* the server closed it */
            if (fop == OP_QUIT) {
                end(FE_OK);
            } else if (fop != OP_NONE) {
                end(FE_CLOSED);
            } else {
                ftp_drop();
                ferr = FE_CLOSED;
                fdone = OP_QUIT;
            }
        } else if (r)
            reply();
    }
    if (fst == FS_DOPEN) {
        d = net_sock(dsk);
        if (d == NET_OPEN) {
            got_prelim = got_final = data_done = 0;
            xb_n = xb_p = 0;
            xb_eof = 0;
            if (xkind == X_LIST) {
                rlist_begin(use_mlsd);
                cmd(use_mlsd ? "MLSD" : "LIST");
            } else
                cmd2(xkind == X_RETR ? "RETR" : "STOR", fa);
            fst = FS_XFER;
            xfer_data = xkind != X_LIST;
        } else if (d == NET_FAILED || d == NET_FREE) {
            fnet = net_sockerr(dsk);
            end(FE_NET);
        }
    }
    if (fst == FS_XFER) {
        xfer_data_step();
        if (fst == FS_XFER && got_final && data_done)
            xfer_end();
        else if (fst == FS_XFER && ser_frames - t0 > T_IDLE)
            end(FE_TIMEOUT);
    } else if (fst == FS_WAIT && ser_frames - t0 > tlen) {
        if (fop == OP_QUIT)
            end(FE_OK);
        else
            end(FE_TIMEOUT);
    }
    d = fdone;
    fdone = 0;
    return d;
}
