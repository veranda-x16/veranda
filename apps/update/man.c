/* Veranda Update: the manifest, UPDATE.LST (DECISIONS V130; the format:
   tools/mkmanifest.py). Read line by line into the table, an entry of
   101 bytes for each file in two RAM banks (struct ent: its size, CRC-32,
   kind, the oldest build it may go over, its asset's name, its path).
   What may be named is checked as it is read: a path under VERANDA/
   (not in a folder whose name starts with ".", so never .SYSTEM, where
   the settings are), PC/ or DOCUMENTS/ (doc-sample: listed, never
   written), at most 63 characters, no ".." and no "//", not the manifest
   itself, not a *.CFG; an asset of letters, digits and "."; a build id of
   letters, digits and "._+-". A manifest with anything else, or without
   its end line (cut short), is refused whole.

   MIT licence (see LICENSE). */
#include <veranda.h>
#include <string.h>
#include "up.h"

#pragma code-name ("OVERLAY2")      /* (its strings and data in main RAM: the kernel reads them) */

struct ent E;
unsigned char nents, tbank;
char nbuild[16], ndate[11], ntag[48];
char nver[16], iver[16];
#pragma bss-name ("OVL2BSS")
char notes[NOTES][77];             /* (overlay 2's: only ui.c reads them) */
#pragma bss-name ("BSS")
unsigned char nnotes;
char ibuild[16], idate[11];

#define ib iobuf                 /* (FRead's buffer, main RAM) */
static unsigned char ibn, ibp, ih;
#pragma bss-name ("OVL2BSS")
static char ln[128];
#pragma bss-name ("BSS")

/* the next line of the open file ih into ln (CR dropped): 0 at its end */
static unsigned char getline_(void)
{
    unsigned char n = 0, c, any = 0;
    for (;;) {
        if (ibp == ibn) {
            ibn = FRead(ih, ib, 128);
            ibp = 0;
            if (!ibn) {
                ln[n] = 0;
                return any;
            }
        }
        c = ib[ibp++];
        any = 1;
        if (c == '\n') {
            ln[n] = 0;
            return 1;
        }
        if (c == '\r')
            continue;
        if (n < sizeof ln - 1)
            ln[n++] = c;
        else
            ln[0] = 1;                  /* (too long: no valid line) */
    }
}

static const char *const kinds[] = { "system", "app", "font", "help", "wallpaper", "pc", "doc-sample" };

static unsigned char __fastcall__ okname(const char *s, unsigned char max, unsigned char build)
{
    unsigned char n = 0, c;
    while ((c = *s++) != 0) {
        if (++n > max)
            return 0;
        if ((c >= '0' && c <= '9') || (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || c == '.')
            continue;
        if (build && (c == '-' || c == '_' || c == '+'))
            continue;
        return 0;
    }
    return n != 0;
}

/* a path Veranda Update may write */
static unsigned char __fastcall__ okpath(const char *p, unsigned char kind)
{
    unsigned char n = strlen(p);
    const char *q;
    if (n == 0 || n > 63 || p[n - 1] == '/' || strstr(p, "//") || strstr(p, "/.") || strstr(p, ".."))
        return 0;
    if (!strcmp(p, "VERANDA/UPDATE.LST"))
        return 0;
    if (n > 4 && !strcmp(p + n - 4, ".CFG"))
        return 0;
    if (!memcmp(p, "DOCUMENTS/", 10))
        return kind == K_DOC;
    if (kind == K_DOC)
        return 0;
    if (memcmp(p, "VERANDA/", 8) && memcmp(p, "PC/", 3))
        return 0;
    for (q = p; *q; ++q)
        if ((unsigned char)*q < 32 || *q == '"' || *q == '*' || *q == '?' || *q == ':' || *q == '=' || *q == ',')
            return 0;
    return 1;
}

/* "file <size> <crc> <kind> <min> <asset> <path>" into E: 0 if bad */
static unsigned char file_line(char *p)
{
    unsigned long v;
    unsigned char i, c;
    char *w;
    memset(&E, 0, sizeof E);
    for (v = 0; *p >= '0' && *p <= '9'; ++p)
        v = v * 10 + (*p - '0');
    if (*p++ != ' ')
        return 0;
    E.size = v;
    for (v = 0, i = 0; i < 8; ++i, ++p) {
        c = *p;
        if (c >= '0' && c <= '9')
            c -= '0';
        else if (c >= 'a' && c <= 'f')
            c -= 'a' - 10;
        else
            return 0;
        v = v << 4 | c;
    }
    if (*p++ != ' ')
        return 0;
    E.crc = v;
    w = strchr(p, ' ');
    if (!w)
        return 0;
    *w = 0;
    for (E.kind = 0; E.kind < sizeof kinds / sizeof kinds[0] && strcmp(p, kinds[E.kind]); ++E.kind)
        ;
    if (E.kind == sizeof kinds / sizeof kinds[0])
        E.kind = K_OTHER;               /* (a kind of a later format: as an application's file) */
    p = w + 1;
    w = strchr(p, ' ');
    if (!w || w - p > 10)
        return 0;
    *w = 0;
    strcpy(E.min, p);
    if (strcmp(E.min, "-") && strlen(E.min) != 10)
        return 0;
    p = w + 1;
    w = strchr(p, ' ');
    if (!w)
        return 0;
    *w = 0;
    if (!okname(p, 13, 0))
        return 0;
    strcpy(E.asset, p);
    p = w + 1;
    if (!okpath(p, E.kind))
        return 0;
    strcpy(E.path, p);
    E.st = E.kind == K_DOC ? S_SKIP : S_UNKNOWN;
    return 1;
}

static char why[72];

static const char *__fastcall__ bad(const char *s)
{
    FClose(ih);
    strcpy(why, s);
    return why;
}

const char *__fastcall__ man_load_o(const char *dir, const char *name)
{
    unsigned char ended = 0, i, j;
    char *p;
    unsigned int k;
    nents = nnotes = 0;
    nbuild[0] = ndate[0] = ntag[0] = nver[0] = 0;
    if (ChDir((char *)dir))
        return "no manifest";
    ih = FOpen((char *)name, 'r');
    if (ih < 2 || ih > 9 || dosStatus >= 20)
        return "no manifest";
    ibn = ibp = 0;
    if (!getline_() || strcmp(ln, "VERANDA-UPDATE 1"))
        return bad("not a Veranda Update manifest (VERANDA-UPDATE 1)");
    while (getline_()) {
        if (!ln[0])
            continue;
        if (ended)
            return bad("lines after its end");
        if (!memcmp(ln, "build ", 6)) {
            p = strchr(ln + 6, ' ');
            if (!p || strlen(p + 1) != 10)
                return bad("a bad build line");
            *p = 0;
            if (!okname(ln + 6, 15, 1))
                return bad("a bad build id");
            strcpy(nbuild, ln + 6);
            strcpy(ndate, p + 1);
        } else if (!memcmp(ln, "version ", 8)) {
            if (okname(ln + 8, 15, 1))
                strcpy(nver, ln + 8);
        } else if (!memcmp(ln, "tag ", 4)) {
            if (!okname(ln + 4, sizeof ntag - 1, 1))
                return bad("a bad tag");
            strcpy(ntag, ln + 4);
        } else if (!memcmp(ln, "note ", 5)) {
            if (nnotes < NOTES) {
                strncpy(notes[nnotes], ln + 5, 76);
                notes[nnotes++][76] = 0;
            }
        } else if (!memcmp(ln, "file ", 5)) {
            if (nents == ENT_MAX)
                return bad("too many files");
            strcpy(why, "a file it may not write: ");
            k = strlen(ln);
            strncat(why, ln + (k > 40 ? k - 40 : 5), 44);
            if (!file_line(ln + 5)) {
                FClose(ih);
                return why;
            }
            ent_put(nents++);
        } else if (!memcmp(ln, "end ", 4)) {
            for (k = 0, p = ln + 4; *p >= '0' && *p <= '9'; ++p)
                k = k * 10 + (*p - '0');
            if (k != nents)
                return bad("its end line does not count its files");
            ended = 1;
        }
        /* (other words: a later format's, skipped) */
    }
    FClose(ih);
    if (!ended)
        return "cut short (no end line)";
    if (!nbuild[0])
        return "no build line";
    /* the files that share an asset (VERANDA.PRG and AUTOBOOT.X16): copied
       into place, not moved */
    for (i = 0; i < nents; ++i) {
        ent_get(i);
        strcpy(ln, E.asset);
        for (j = 0; j < nents; ++j) {
            if (j == i)
                continue;
            ent_get(j);
            if (!strcmp(ln, E.asset)) {
                ent_get(i);
                E.shared = 1;
                ent_put(i);
                break;
            }
        }
    }
    return 0;
}

/* the card's build: VERANDA/UPDATE.LST's build line */
void man_installed_o(void)
{
    char *p;
    ibuild[0] = idate[0] = iver[0] = 0;
    if (ChDir(VR_SYSDIR))
        return;
    ih = FOpen("UPDATE.LST", 'r');
    if (ih < 2 || ih > 9 || dosStatus >= 20)
        return;
    ibn = ibp = 0;
    if (getline_() && !strcmp(ln, "VERANDA-UPDATE 1") && getline_() && !memcmp(ln, "build ", 6)) {
        p = strchr(ln + 6, ' ');
        if (p && strlen(p + 1) == 10) {
            *p = 0;
            if (okname(ln + 6, 15, 1)) {
                strcpy(ibuild, ln + 6);
                strcpy(idate, p + 1);
            }
        }
        /* (the version line, when the list has one, comes next) */
        if (getline_() && !memcmp(ln, "version ", 8) && okname(ln + 8, 15, 1))
            strcpy(iver, ln + 8);
    }
    FClose(ih);
}
