/* Veranda Ask: ASK.LOG's helpers where there is room (DECISIONS V129):
   an error's body into the log with its tokens cut (overlay 9, hist.c's
   bank: no string literal here, cc65 puts them all in the file's last
   rodata segment), why a renewal was not (all) kept (overlay 8, conv.c's).

   MIT licence (see LICENSE). */
#include <veranda.h>
#include <string.h>
#include "claude.h"

/*---------------------------------------------------------------- an error's body */

#pragma code-name ("OVERLAY9")          /* (hist.c's bank: room) */
#pragma rodata-name ("OVL9RO")
#pragma bss-name ("OVL9BSS")

static char tk[48];                     /* lg_red: a run of a token's characters held */
#define tkn lg_tkn                      /* its length (0xFF: a long one skipped), a digit or a capital in it */
#define tkx lg_tkx                      /* (main RAM: an overlay's BSS is not cleared; p_begin sets them) */

/* (V129) an error's body into the log as it comes, a token's characters
   (a run of more than 20 with a digit or a capital, or of more than 48)
   cut to their first 6 (lg_ch, from parse.c) */
static void tk_out(void)
{
    unsigned char i, n = tkn;
    if (n > 20 && tkx)
        n = 6;
    for (i = 0; i < n; ++i)
        lg_c(tk[i]);
    if (n != tkn)
        lg_c('.'), lg_c('.'), lg_c('.');
    tkn = tkx = 0;
}

void lg_red(void)
{
    unsigned char c = lg_ch;
    if ((c >= '0' && c <= '9') || ((c | 32) >= 'a' && (c | 32) <= 'z') || c == '_' || c == '-' || c == '.'
        || c == '~' || c == '+' || c == '/' || c == '=') {
        if (tkn == 0xFF)
            return;
        if ((c >= '0' && c <= '9') || (c >= 'A' && c <= 'Z'))
            tkx = 1;
        if (tkn < sizeof tk) {
            tk[tkn++] = c;
            return;
        }
        tkx = 1;
        tk_out();
        tkn = 0xFF;
        return;
    }
    if (tkn == 0xFF)
        tkn = 0;
    else
        tk_out();
    if ((c >= 32 && c < 127) || c == '\n')
        lg_c(c);
}

#pragma code-name ("OVERLAY8")          /* (conv.c's bank: room) */
#pragma rodata-name ("OVL8RO")
#pragma bss-name ("OVL8BSS")

/* (turn.c's) why a renewal's reply was not (all) kept, into r_txt */
void lg_why(void)
{
    const char *s = "the reply was cut at ";
    switch (r_why) {
    case R_ACCLONG: s = "the reply's access_token is longer than 5119"; break;
    case R_NOACC: s = "no access_token in the reply"; break;
    case R_GZ: s = "the reply is compressed"; break;
    case R_REFLONG: s = "its refresh_token is longer than 1023"; break;
    case R_NOREF: s = "no refresh_token in the reply"; break;
    }
    strcpy(r_txt, s);
    if (r_why == R_CUT || r_why == R_REFCUT)
        strcpy(unum(r_txt + 21, p_body), " bytes");
}
