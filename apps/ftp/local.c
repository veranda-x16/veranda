/* Veranda FTP: the card's folder into the local pane (overlay 1, called
   from ui.c; DECISIONS V100): CMDR-DOS's long listing, "$=L" (DirOpen
   "=L", shell/dir.c's way): long names, sizes in bytes, dates.

   MIT licence (see LICENSE). */
#include <veranda.h>
#include <string.h>
#include "ftp.h"
#pragma code-name ("OVERLAY1")

void __fastcall__ up_entry(struct ent *e);
unsigned char __fastcall__ dec2(const char *p);
unsigned char __fastcall__ is_digit(char c);
void __fastcall__ add(unsigned char p, struct ent *e);

static unsigned char hex(unsigned char c)
{
    return c <= '9' ? c - '0' : (c & 0x0F) + 9;
}

static unsigned char de[128];

/* a line of the long listing into E (shell/dir.c's): 0 not an entry
       n KB  "NAME"   PRG  2026-11-16 10:42:07 20 0000ABCD */
static unsigned char local_line(char *t)
{
    char *q = strchr(t, '"'), *n;
    unsigned char l, i;
    if (!q)
        return 0;
    n = ++q;
    q = strchr(q, '"');
    if (!q)
        return 0;
    *q++ = 0;
    l = strlen(n);
    if (!l || l >= NAMEMAX || n[0] == '.')
        return 0;                       /* (., .. and hidden names: .SYSTEM) */
    memset(&E, 0, sizeof E);
    E.h = 0xFF;
    strcpy(E.name, n);
    while (*q == ' ')
        ++q;
    if (q[0] == 'D' && q[1] == 'I' && q[2] == 'R')
        E.flags = E_DIR;
    if (*q)
        q += 3;
    while (*q == ' ' || *q == '<')
        ++q;
    if (is_digit(q[0]) && q[4] == '-' && q[7] == '-' && q[13] == ':') {
        E.y = (unsigned char)((q[0] - '0') * 1000u + dec2(q + 1) * 10u + (q[3] - '0') - 1900u);
        E.mo = dec2(q + 5);
        E.d = dec2(q + 8);
        E.h = dec2(q + 11);
        E.mi = dec2(q + 14);
        q += 19;
        while (*q == ' ')
            ++q;
    }
    if (q[0] && q[1] && q[2] == ' ') {  /* the attributes, the size in hex */
        q += 3;
        for (i = 0; i < 8 && q[i] > ' '; ++i)
            E.size = E.size << 4 | hex(q[i]);
    } else
        E.size = (unsigned long)(de[1] | de[2] << 8) << (t[0] == 'M' ? 20 : 10);
    if (E.flags & E_DIR)
        E.size = 0;
    return 1;
}

/* the current folder (curDirName's) into the local pane */
unsigned char local_read(void)
{
    unsigned char first = 1, ok = 0;
    pane_clear(LOCAL);
    if (curDirName[1]) {
        up_entry(&E);
        add(LOCAL, &E);
    }
    if (DirOpen("=L") == 0) {
        ok = 1;
        de[125] = 0;
        while (DirNext(de) == 0) {
            if (first) {
                first = 0;              /* (the header: the card's name) */
                continue;
            }
            if (local_line((char *)de + 3))
                add(LOCAL, &E);
        }
    }
    return ok;
}

