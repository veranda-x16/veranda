/* Veranda Claude: files, the clipboard (overlay 2; DECISIONS V114).

   A conversation saved as text (UTF-8, CR LF) to /DOCUMENTS, the
   clipboard's text (Ctrl+V), and vrwin (the chrome). The settings and
   the Settings page are page.c's (overlay 4); the menus sbar.c's (V149).

   MIT licence (see LICENSE). */
#include <veranda.h>
#include <string.h>
#include <theme.h>
#include <vrpath.h>
#include <vrwin.h>
#include "claude.h"
#pragma code-name ("OVERLAY2")
#pragma bss-name ("OVL2BSS")
#pragma rodata-name ("OVL2RO")

/* (the clipboard's paste is code.c's now, with the scrap library in its bank: V123) */

/*---------------------------------------------------------------- a conversation saved */

static unsigned char sh;
#define obuf rbuf                       /* (main RAM: FWrite reads it; free while no turn runs) */
static unsigned char on;

static void flush(void)
{
    if (on && sh) {
        if (FWrite(sh, obuf, on))
            sv_err = 1;
    }
    on = 0;
}

static void __fastcall__ ob(unsigned char c)
{
    obuf[on++] = c;
    if (on >= 200)
        flush();
}

static void __fastcall__ obs(const char *s)
{
    while (*s)
        ob(*s++);
}

/* a CP437 byte as UTF-8 (a line feed as CR LF) */
static void __fastcall__ utf8(unsigned char c)
{
    unsigned int u;
    if (c == '\n') {
        ob('\r');
        ob('\n');
        return;
    }
    u = cp_u(c);
    if (u < 0x80)
        ob(u);
    else if (u < 0x800) {
        ob(0xC0 | (u >> 6));
        ob(0x80 | (u & 0x3F));
    } else {
        ob(0xE0 | (u >> 12));
        ob(0x80 | ((u >> 6) & 0x3F));
        ob(0x80 | (u & 0x3F));
    }
}

static const char *__fastcall__ who(unsigned char k)
{
    switch (k) {
    case K_USER: return "You:";
#ifdef ASK
    case K_CLAUDE: return "Reply:";
#else
    case K_CLAUDE: return "Claude:";
#endif
    case K_UNSENT: return "You (not sent):";
#ifdef ASK
    case K_DECLINED: return "Reply (declined):";
#else
    case K_DECLINED: return "Claude (declined):";
#endif
    }
    return "Note:";
}

void conv_save(void)
{
    unsigned int a = 0, nx, i, k;
    unsigned char h, j;
    sv_err = 0;
    vr_cd(VR_DOCS);
    h = FOpen((void *)sv_name, 'r');
    if (h >= 2 && h <= 4) {
        j = dosStatus < 20;
        FClose(h);
        if (j) {
            strcpy(line, sv_name);
            strcat(line, " is in /DOCUMENTS already.");
            if (!yesno(line, "Replace it?")) {
                sv_err = 2;
                return;
            }
        }
    }
    vr_cd(VR_DOCS);
    h = FOpen((void *)sv_name, 'w');
    if (h < 2 || h > 4) {
        sv_err = 1;
        return;
    }
    sh = h;
    on = 0;
#ifdef ASK
    obs("Veranda Ask: a conversation with ");
    obs(C.mname);
#else
    obs("Veranda Claude: a conversation with ");
    obs(model_name[C.model]);
#endif
    obs("\r\n\r\n");
    while (a < st_used) {
        nx = st_msg(a);
        obs(who(st_k));
        obs("\r\n");
        for (i = 0; i < st_n; i += k) {
            k = st_n - i > 100 ? 100 : st_n - i;
            st_copy(a + 3 + i, dtext, k);
            for (j = 0; j < k; ++j)
                utf8(dtext[j]);
        }
        obs("\r\n\r\n");
        a = nx;
    }
    flush();
    FClose(h);
    sh = 0;
}
