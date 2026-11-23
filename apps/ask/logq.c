/* Veranda Ask: ASK.LOG, a request's own lines (DECISIONS V131): after
   logclk.c's lg_req0 (overlay 4: a 401's turn kept, the request line, the
   Host), this (overlay 6, code.c's bank: room): the length and the byte
   sum (16 bits) of the secret the request carries (a turn: the
   Authorization's token; a renewal: the refresh token), never the value,
   and the body's length. The PC's check (tools/chatgpt_signin.py --check) prints the same length and sum
   of the card's token: when they agree, the X16 read it whole from
   ASK.CFG and put all of it in the header.

   A turn refused with a 401 is kept for the renewal it asks for (lg_keep):
   its first 800 bytes (V129 kept 480: its headers filled them and its body
   was lost). Its headers are fewer now and 260 bytes at most (tok.c's
   lg_hdr), so its body comes well before; the renewal's headers stop 300
   bytes before the log's end (its status line always kept), so its body
   has room too.

   MIT licence (see LICENSE). */
#include <veranda.h>
#include <string.h>
#include "claude.h"
#pragma code-name ("OVERLAY6")
#pragma rodata-name ("OVL6RO")
#pragma bss-name ("OVL6BSS")

void lg_req(void)
{
    struct part *p = parts + lg_ap;
    if (lg_ap) {
        lg_s(rq == RQ_CHAT ? "\nauthorization: Bearer + " : "\nrefresh_token: ");
        lg_u(p->n);
        lg_s(" bytes, sum ");
        lg_u(bk_sum(p->bank, p->a, p->n));
    }
    lg_s("\ncontent-length: ");
    lg_s(hlen_s);
    lg_c('\n');
    lg_h0 = lg_n;
    lg_hcut = 0;
}
