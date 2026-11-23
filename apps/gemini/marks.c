/* Veranda Gemini: the bookmarks (overlay 2; DECISIONS V118).

   GEMINI.MARKS in the system's data folder (/VERANDA/.SYSTEM, vrpath.h's
   VR_DATA): gemtext, one link a line, as a capsule writes them:

       => gemini://host/path A name

   Plain text, so it can be written on a PC too (CR LF or LF); lines that
   are not links are skipped. When the file is not there, a few
   well-known capsules are the bookmarks (written when one is added or
   removed). The bookmarks page (Home) is a gemtext page: a heading, a
   line of help, the links.

   The table is in this overlay's bank; what goes to the kernel or to the
   document (the file's bytes, its name, the lines) through main RAM's
   line.

   Also here: the clipboard's text for the address line (Ctrl+V).

   MIT licence (see LICENSE). */
#include <veranda.h>
#include <string.h>
#include <vrpath.h>
#include <scrap.h>
#include "gemini.h"
#pragma code-name ("OVERLAY2")
#pragma rodata-name ("OVL2RO")
#pragma bss-name ("OVL2BSS")

#define MKMAX 16
#define MKLEN 192

static char mk[MKMAX][MKLEN];

/* (not verified against the live capsules when written: V118) */
static const char *const defaults[] = {
    "=> gemini://geminiprotocol.net/ Project Gemini",
    "=> gemini://kennedy.gemi.dev/ Kennedy: search Geminispace",
    "=> gemini://geminispace.info/ geminispace.info: search",
    "=> gemini://antenna.flounder.online/ Antenna: what is new in Geminispace",
    "=> gemini://gemi.dev/ gemi.dev",
    "=> gemini://gemi.dev/cgi-bin/waffle.cgi NewsWaffle: web pages as gemtext",
    "=> gemini://gemi.dev/cgi-bin/wp.cgi/ Gemipedia: Wikipedia",            /* (V128: Gemipedia's Program.cs) */
    "=> gemini://gemi.dev/cgi-bin/wp.cgi/featured Wikipedia: featured articles",
};

static unsigned char __fastcall__ fopen_n(const char *name, unsigned char mode)
{
    unsigned char h;
    vr_cd(VR_DATA);
    strcpy(line + 186, name);           /* (the kernel reads the name below $A000; GEMINI.CFG's text before it) */
    h = FOpen(line + 186, mode);
    if (h < 2 || h > 4)
        h = 0;
    else if (mode == 'r' && dosStatus >= 20) {
        FClose(h);
        h = 0;
    }
    return h;
}
#define fopen_marks(m) fopen_n("GEMINI.MARKS", m)

/* GEMINI.CFG (url.c's web settings, V124) into line, and back */
void cfg_read(void)
{
    unsigned char h = fopen_n("GEMINI.CFG", 'r'), n = 0;
    if (h) {
        n = FRead(h, line, 185);
        FClose(h);
    }
    line[n] = 0;
    ChDir((char *)curDirName);
}

void cfg_write(void)
{
    unsigned char h = fopen_n("GEMINI.CFG", 'w');
    if (h) {
        FWrite(h, line, strlen(line));
        FClose(h);
    }
    ChDir((char *)curDirName);
}

/* line[0 .. n - 1] kept if it is a link */
static void __fastcall__ keep(unsigned char n)
{
    if (n < 4 || line[0] != '=' || line[1] != '>' || marks_n >= MKMAX)
        return;
    if (n >= MKLEN)
        n = MKLEN - 1;
    memcpy(mk[marks_n], line, n);
    mk[marks_n][n] = 0;
    ++marks_n;
}

void marks_load(void)
{
    static unsigned char buf[32];
    unsigned char h = fopen_marks('r'), n = 0, i, c, k;
    marks_n = 0;
    if (h) {
        for (;;) {
            k = FRead(h, line + 160, 32);
            if (!k)
                break;
            memcpy(buf, line + 160, k);
            for (i = 0; i < k; ++i) {
                c = buf[i];
                if (c == '\r' || c == '\n') {
                    keep(n);
                    n = 0;
                } else if (n < 159)
                    line[n++] = c;
            }
            if (k < 32)
                break;
        }
        keep(n);
        FClose(h);
    } else
        for (i = 0; i < sizeof defaults / sizeof defaults[0]; ++i) {
            strcpy(mk[i], defaults[i]);
            ++marks_n;
        }
    ChDir((char *)curDirName);
}

static void save(void)
{
    unsigned char h, i;
    marks_err = 0;
    h = fopen_marks('w');
    if (!h) {
        marks_err = 1;
    } else {
        for (i = 0; i < marks_n; ++i) {
            strcpy(line, mk[i]);
            strcat(line, "\r\n");
            if (FWrite(h, line, strlen(line)))
                marks_err = 1;
        }
        FClose(h);
    }
    ChDir((char *)curDirName);
}

static void __fastcall__ feed(const char *s)
{
    strcpy(line, s);
    strcat(line, "\n");
    doc_feed((unsigned char *)line, strlen(line));
}

void marks_page(void)
{
    unsigned char i;
    feed("# Bookmarks");
    feed("Click one, or move to it with Tab and press Return. Bookmarks > Add this page adds the page shown.");
    feed("");
    for (i = 0; i < marks_n; ++i)
        feed(mk[i]);
    if (!marks_n)
        feed("(none)");
}

/* the page shown (cur, title) as a link */
void marks_add(void)
{
    char *p = line;
    unsigned char i;
    marks_err = 2;
    marks_i = 0xFF;
    if (marks_n >= MKMAX)
        return;
    strcpy(p, "=> ");
    strncat(p, cur, MKLEN - 40);
    p += strlen(p);
    *p++ = ' ';
    for (i = 0; title[i]; ++i)
        *p++ = title[i] < 32 ? ' ' : title[i];
    *p = 0;
    strcpy(mk[marks_n++], line);
    save();
}

void marks_del(void)
{
    unsigned char i;
    if (marks_i >= marks_n)
        return;
    for (i = marks_i; i + 1 < marks_n; ++i)
        strcpy(mk[i], mk[i + 1]);
    --marks_n;
    save();
}

void marks_paste(void)
{
    if (!scrap_get_text(line, sizeof line))
        line[0] = 0;
}
