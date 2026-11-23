/* Veranda Gopher: the bookmarks (overlay 2; DECISIONS V109).

   GOPHER.MARKS in the system's data folder (/VERANDA/.SYSTEM, vrpath.h's
   VR_DATA): a Gopher menu, one item a line, as a server sends it:

       Tname<TAB>selector<TAB>host<TAB>port

   (T the item's kind: 1 a menu, 0 a text, 7 a search ...). Plain text,
   so it can be written on a PC too (CR LF or LF); lines that are not
   items are skipped. When the file is not there, a few well-known
   public Gopher servers are the bookmarks (written when one is added
   or removed). The bookmarks page (Home) is that menu with a line of
   help over it (MARKS_HEAD lines), shown like any other.

   The table is in this overlay's bank; what goes to the kernel or to
   the document (the file's bytes, the lines) through main RAM's line.

   Also here: the clipboard's text for the address line (Ctrl+V).

   MIT licence (see LICENSE). */
#include <veranda.h>
#include <string.h>
#include <vrpath.h>
#include <scrap.h>
#include "gopher.h"
#pragma code-name ("OVERLAY2")
#pragma bss-name ("OVL2BSS")

#define MKMAX 16
#define MKLEN 192

static char mk[MKMAX][MKLEN];
static const char fname[] = "GOPHER.MARKS";

static const char *const defaults[] = {
    "1Floodgap Systems\t\tgopher.floodgap.com\t70",
    "7Veronica-2: search Gopherspace\t/v2/vs\tgopher.floodgap.com\t70",
    "1Quux.org\t\tgopher.quux.org\t70",
    "1SDF Public Access UNIX System\t\tsdf.org\t70",
    "1Bitreich\t\tbitreich.org\t70",
};

static unsigned char __fastcall__ fopen_marks(unsigned char mode)
{
    unsigned char h;
    vr_cd(VR_DATA);
    h = FOpen((void *)fname, mode);
    if (h < 2 || h > 4)
        h = 0;
    else if (mode == 'r' && dosStatus >= 20) {
        FClose(h);                      /* (CMDR-DOS opens a file that is not there) */
        h = 0;
    }
    return h;
}

/* line[0 .. n - 1] kept if it is an item */
static void __fastcall__ keep(unsigned char n)
{
    if (n < 4 || line[0] == 'i' || !memchr(line, '\t', n) || marks_n >= MKMAX)
        return;
    if (n >= MKLEN)
        n = MKLEN - 1;
    memcpy(mk[marks_n], line, n);
    mk[marks_n][n] = 0;
    ++marks_n;
}

void marks_load(void)
{
    static unsigned char buf[64];       /* (OVL2BSS: the file's bytes come through line) */
    unsigned char h = fopen_marks('r'), n = 0, i, c, k;
    marks_n = 0;
    if (h) {
        for (;;) {
            k = FRead(h, line + 128, 64);
            if (!k)
                break;
            memcpy(buf, line + 128, k);
            for (i = 0; i < k; ++i) {
                c = buf[i];
                if (c == '\r' || c == '\n') {
                    keep(n);
                    n = 0;
                } else if (n < 127)
                    line[n++] = c;
            }
            if (k < 64)
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
    strcat(line, "\r\n");
    doc_feed((unsigned char *)line, strlen(line));
}

void marks_page(void)
{
    unsigned char i;
    feed("iYour bookmarks: click one. Bookmarks > Add this page adds one.");
    feed("i");
    for (i = 0; i < marks_n; ++i)
        feed(mk[i]);
    if (!marks_n)
        feed("i(none)");
}

/* the page shown (cur, title) as an item; a search without its query */
void marks_add(void)
{
    char *p = line, *q;
    unsigned char i;
    marks_err = 2;
    if (marks_n >= MKMAX)
        return;
    *p++ = cur.type;
    for (i = 0; title[i]; ++i)
        *p++ = title[i] == '\t' ? ' ' : title[i];
    *p++ = '\t';
    for (q = cur.sel; *q && *q != '\t' && p < line + MKLEN - HOSTMAX - 10; ++q)
        *p++ = *q;
    *p++ = '\t';
    strcpy(p, cur.host);
    strcat(p, "\t");
    unum(p + strlen(p), cur.port);
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
