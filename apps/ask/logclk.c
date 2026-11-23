/* Veranda Ask: the access token's time by the X16's clock, when the clock
   is to be trusted (overlay 10 with log.c; its exp read in overlay 4,
   page.c's bank; DECISIONS V129).

   MIT licence (see LICENSE). */
#include <veranda.h>
#include <string.h>
#include "claude.h"

/*---------------------------------------------------------------- the clock */

#pragma code-name ("OVERLAY10")         /* (log.c's bank) */
#pragma rodata-name ("OVL10RO")
#pragma bss-name ("OVL10BSS")

#pragma static-locals (on)              /* (smaller; nothing here is called again from inside) */

static unsigned char t_past;
static unsigned long tnow;
#define clk_bad lg_clkbad               /* (main RAM: cleared at the start) */

/* (V129: auth.c's) the access token's time is up, by a clock to trust
   (t_due): its exp (the JWT's, Unix seconds) against the X16's clock less
   its time zone, 2 minutes early (a token without one: the 401 renews
   it; V129: got and expires_in no longer used for this). An unset clock, one before 2026, a token come "later" than
   now, a fresh token already expired by it: not trusted (0: the turn
   goes, a 401 renews) */
void tok_due(void)
{
    t_due = t_past = t_ok = 0;
    tnow = now_min();
    if (!tnow || clk_bad || !sl.acc)
        return;
    ov4(tok_exp);
    if (t_exp) {
        t_ok = 1;                       /* (V131: a 401 with a fresh token by it renews nothing) */
        SysPrefs(PREFS_GET, line);
        tnow -= (signed char)line[8] * 15;
        tnow = tnow * 60 + 946684800ul;
        t_past = tnow > t_exp;
        tnow += 120;
        t_due = tnow >= t_exp;
    }
}

/* after a renewal or a sign-in: a fresh token expired already says the
   clock is wrong (or its time zone not set) */
void clk_check(void)
{
    tok_due();
    clk_bad |= t_past;
}

#pragma code-name ("OVERLAY4")          /* (page.c's bank: room) */
#pragma rodata-name ("OVL4RO")
#pragma bss-name ("OVL4BSS")

static const char pexp[] = "\"exp\"";

/* the live access token's exp, from its JWT's payload
   (base64url; only that claim read, nothing verified) into t_exp (0: none) */
void tok_exp(void)
{
    unsigned int a, k, bits;
    unsigned char i, c, v, d, seg, nb, mt;
    t_exp = 0;
    bits = seg = nb = mt = 0;
    for (a = 0; a < sl.acc; a += k) {
        k = sl.acc - a > 128 ? 128 : sl.acc - a;
        bk_get(tbank + tlive, TB_ACC + a, line, k);
        for (i = 0; i < k; ++i) {
            c = line[i];
            if (c == '.') {
                if (seg++)
                    return;
                continue;
            }
            if (!seg)
                continue;
            if (c >= 'a')
                v = c - 'a' + 26;
            else if (c >= 'A')
                v = c == '_' ? 63 : c - 'A';
            else if (c >= '0')
                v = c - '0' + 52;
            else
                v = c == '/' ? 63 : 62;     /* ('-', '+') */
            bits = (bits << 6) | v;
            nb += 6;
            if (nb < 8)
                continue;
            nb -= 8;
            d = bits >> nb;
            if (mt < 5)                 /* "exp" */
                mt = d == pexp[mt] ? mt + 1 : d == '"';
            else if (d >= '0' && d <= '9') {
                t_exp = t_exp * 10 + d - '0';
                mt = 7;
            } else if (mt == 7)
                return;
            else if (d == ':')
                mt = 6;
            else if (d != ' ')
                mt = 0;
        }
    }
    t_exp = 0;                          /* (not ended: not one) */
}

/* (V131, parse.c's p_begin) a request's log begun: a 401's turn kept for
   its renewal (lg_keep) cut to LGKEEP (its body comes before: logq.c);
   the request line (the first part's text up to its CR), the Host; then
   logq.c's lg_req */
#define LGKEEP 800

void lg_req0(void)
{
    unsigned char i;
    if (!lg_keep)
        lg_n = 0;
    else if (lg_n > LGKEEP) {
        lg_n = LGKEEP;
        lg_s("~\n");
    }
    lg_keep = 0;
    bk_get(parts[0].bank, parts[0].a, line, parts[0].n);
    for (i = 0; line[i] != '\r'; ++i)
        lg_c(line[i]);
    lg_s("\nhost: ");
    lg_s(C.host);
    lg_s(hport);
}
