/* Veranda Ask: ASK.LOG, what the last renewal and the last turn were
   (overlay 10; DECISIONS V129); the access token's time by the X16's
   clock, when the clock is to be trusted (overlay 4); why a renewal was
   not kept (overlay 8); an error's body cut (overlay 9). Spread where
   there is room: Ask's banks are counted (Alt+Tab at 512 KB), and in the
   test build overlay 10 holds tests/ask_play.c too.

   /VERANDA/.SYSTEM/ASK.LOG is written again at every request's end
   (turn.c's lg_end): plain text, LF, 2.5 KB at most:
     == renewal (or sign-in), then the turn: the status line and the
        headers as they came (lower case, each cut at 55 characters; a
        Set-Cookie's value never); a renewal's 200: its JSON keys with
        their values' lengths (never the values); an error's body, every
        token-like run in it (more than 20 characters with a digit or a
        capital) cut to its first 6 (tok.c's lg_red); the result (what was
        kept, or which check failed); the host, the X16's clock, the bytes
        sent and received, the status and how the connection ended (end:
        0 complete, 1 network error, 2 not connected, 3 2 minutes silent,
        6 stopped, 7 closed by the server)
   A request's lines are made as the reply comes (tok.c's lg_c: in the
   second credentials bank above its slot, LG0, LGMAX bytes; a turn
   refused with a 401 and the renewal it asks for in one, the turn's first
   480: lg_keep); a renewal's are kept, when it ends, in the slot not in
   use (its access token's room), so that the next turn's file has them
   too.

   MIT licence (see LICENSE). */
#include <veranda.h>
#include <string.h>
#include <vrpath.h>
#include "claude.h"
#pragma code-name ("OVERLAY10")
#pragma rodata-name ("OVL10RO")
#pragma bss-name ("OVL10BSS")

#pragma data-name (push, "DATA")
static char f_log[] = "ASK.LOG";       /* (main RAM: the kernel reads it) */
#pragma data-name (pop)

static unsigned char h;

/* n bytes of bank b at a: to the file (d 0) or to bank d at o */
static void __fastcall__ copy(unsigned char b, unsigned int a, unsigned int len, unsigned char d, unsigned int o)
{
    unsigned int i, k;
    for (i = 0; i < len; i += k) {
        k = len - i > 128 ? 128 : len - i;
        bk_get(b, a + i, line, k);
        if (d)
            bk_put(d, o + i, line, k);
        else
            FWrite(h, line, k);
    }
}

static void __fastcall__ wz(const char *s)
{
    strcpy(line, s);
    FWrite(h, line, strlen(line));
}

static void __fastcall__ two(unsigned char c, unsigned char v)
{
    if (c)
        lg_c(c);
    if (v < 10)
        lg_c('0');
    lg_u(v);
}

void lg_save(void)
{
#ifndef CODE_SESSION                    /* (the code session's test build: no room beside its player; ASK.LOG is
                                           tested by the main and renew sessions) */
    unsigned char ob = tbank + (tlive ^ 1), lb = tbank + 1;
    lg_s("to ");                        /* (the request's facts, after its lines) */
    lg_s(C.host);
    lg_c(':');
    lg_u(C.port);
    lg_s(C.tls ? " TLS, clock 20" : " plain, clock 20");
    two(0, year);
    two('-', month);
    two('-', day);
    two(' ', hour);
    two(':', minutes);
    lg_s(year < 26 ? " (not set)\nsent " : "\nsent ");
    lg_u(ttx);
    lg_s(" (body ");
    lg_u(tbody);
    lg_s("), received ");
    lg_u(trx);
    lg_s(" (body ");
    lg_u(p_body);
    lg_s("), status ");
    lg_u(p_status);
    lg_s(", end ");
    lg_u(tend);
    lg_s(p_jok ? ", the JSON whole\n" : "\n");
    if (rq != RQ_CHAT) {                /* (the renewal's lines kept: the slot not in use) */
        copy(lb, LG0, lg_n, ob, TB_ACC);
        lg_rb = ob;
        lg_rn = lg_n;
    }
    vr_cd(VR_DATA);
    h = FOpen(f_log, 'w');
    if (h < 2 || h > 4)
        return;
    wz("Veranda Ask's log (no tokens, no cookies)\n\n== renewal\n");
    if (lg_rb == ob)
        copy(ob, TB_ACC, lg_rn, 0, 0);
    else
        wz("(none since Veranda Ask started)\n");
    wz("\n== turn\n");
    if (rq == RQ_CHAT)
        copy(lb, LG0, lg_n, 0, 0);
    else
        wz("(none since)\n");
    FClose(h);
#endif
}
