/* Veranda Ask: the credentials' RAM banks, bytes in and out of a bank
   (main RAM; DECISIONS V116).

   An access token is about 2 KB and the token endpoint's reply several:
   they are never held in main RAM. Two banks, a slot each (ask.h): the
   live one and the one a sign-in or a renewal fills, kept only when it
   came whole. Only main RAM's code can map a bank (the overlays run at
   $A000 too), so the overlays and net.c's parts go through bk_get and
   bk_put, which put back the bank they found.

   MIT licence (see LICENSE). */
#include <veranda.h>
#include <string.h>
#include "claude.h"

unsigned char tbank, tlive, tgo, kv_ok, t_retry, notice, sv_fail, kv_ovf, r_why, lg_rb, t_due, lg_ch, lg_keep;
unsigned char lg_tkn, lg_tkx, lg_clkbad;   /* (log.c's: its overlay's BSS is not cleared) */
unsigned int lg_n, lg_rn;
unsigned int lg_b, lg_h0;               /* (V131) the log: where the body's lines began, the headers' */
unsigned char lg_ap, lg_hcut, t_ok;     /* (V131) the secret's part (0: none); the headers cut; tok_due's clock trusted */
unsigned long t_exp;
char r_txt[52];
unsigned char rqm, rqa;                 /* (V199) a request (rq.c) */
unsigned int rq_sn;

unsigned int klen, slen;
char sg_code[8], sg_addr[HOSTMAX + 8];
struct slot sl;

unsigned char tok_start(void)
{
    unsigned char k = RAMBANK;
    tbank = BankAlloc(2);
    if (!tbank)
        return 0;
    RAMBANK = tbank;                    /* (both slots empty) */
    memset((char *)0xA000 + TB_INFO, 0, sizeof sl);
    RAMBANK = tbank + 1;
    memset((char *)0xA000 + TB_INFO, 0, sizeof sl);
    RAMBANK = k;
    return 1;
}

void __fastcall__ bk_get(unsigned char b, unsigned int a, void *buf, unsigned int n)
{
    unsigned char k = RAMBANK;
    if (b)
        RAMBANK = b;
    memcpy(buf, (char *)(b ? 0xA000 + a : a), n);
    RAMBANK = k;
}

void __fastcall__ bk_put(unsigned char b, unsigned int a, const void *buf, unsigned int n)
{
    unsigned char k = RAMBANK;
    if (b)
        RAMBANK = b;
    memcpy((char *)(b ? 0xA000 + a : a), buf, n);
    RAMBANK = k;
}

/* (V131) the 16-bit sum of n bytes of bank b at a (ASK.LOG's, the PC's check's) */
unsigned int __fastcall__ bk_sum(unsigned char b, unsigned int a, unsigned int n)
{
    unsigned char k = RAMBANK;
    unsigned int s = 0;
    const unsigned char *q = (const unsigned char *)0xA000 + a;
    RAMBANK = b;
    while (n--)
        s += *q++;
    RAMBANK = k;
    return s;
}

/* (V129) the log's lines (ask.h): a byte, a string, a number */
void __fastcall__ lg_c(unsigned char c)
{
    unsigned char k = RAMBANK;
    if (lg_n >= LGMAX)
        return;
    RAMBANK = tbank + 1;
    ((char *)0xA000 + LG0)[lg_n++] = c;
    RAMBANK = k;
}

void __fastcall__ lg_s(const char *s)
{
    while (*s)
        lg_c(*s++);
}

void __fastcall__ lg_u(unsigned long v)
{
    static char b[12];
    unum(b, v);
    lg_s(b);
}

/* (V131) a header line (h in the caller's bank, n bytes; n 55: cut, its
   last a '~') into the log: a Set-Cookie's value never; the ones that say
   nothing about a failure left out; LGH bytes of them a request at most,
   none in the log's last 300 bytes but the status line (then "~"), so the
   error's body always has its room */
static const char hskip[] = "date\0server\0alt-svc\0strict-transport-security\0x-content-type-options\0"
    "cf-cache-status\0vary\0connection\0";
#define LGH 260

void __fastcall__ lg_hdr(const char *h, unsigned char n)
{
    const char *s;
    unsigned char i;
    if (lg_n != lg_h0 && (lg_n - lg_h0 >= LGH || lg_n >= LGMAX - 300)) {
        if (!lg_hcut)
            lg_s("~\n");
        lg_hcut = 1;
        return;
    }
    for (s = hskip; *s; s += i + 1) {
        i = strlen(s);
        if (!strncmp(h, s, i) && h[i] == ':')
            return;
    }
    if (!strncmp(h, "set-cookie:", 11)) {
        lg_s("set-cookie: (not kept)\n");
        return;
    }
    for (i = 0; i < n; ++i)
        lg_c(i == 54 ? '~' : h[i]);
    lg_c('\n');
}

static const unsigned int cum[12] = { 0, 31, 59, 90, 120, 151, 181, 212, 243, 273, 304, 334 };

/* the X16's clock: minutes since 2000 (0: not set; V129: nor before 2026,
   as an unset clock reads 1 January 2000) */
unsigned long now_min(void)
{
    unsigned char y = year, m = month;
    unsigned long d;
    if (!m || m > 12 || !day || y < 26)
        return 0;
    d = (unsigned long)y * 365 + (y + 3) / 4 + cum[m - 1] + day - 1;
    if (m > 2 && !(y & 3))
        ++d;
    return d * 1440 + hour * 60 + minutes;
}
