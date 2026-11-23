/* Disk Tools: the folder walker (DECISIONS V119), for Space use and the
   search for leftovers.

   A step reads one folder: ChDir to it, its long listing ("$=L", DirOpen
   "=L": each line raw, V70) read to its end, so that no listing is open
   between two passes of the main loop (the switcher may put the program
   aside then; V83: a listing open would make it ask to quit). Each line
   is parsed as the shell's dir.c parses it: the name between the quotes,
   PRG or DIR, the date, the FAT attributes and the size in bytes (8 hex
   digits; R49 leaves those out for a file with no date: then the size in
   KB as listed). Each entry goes to the caller's function, then an empty
   one marks the folder's end. Folders to read wait on a stack in two RAM
   banks (256 paths of up to 62 characters with a byte of the caller's,
   its tag); a longer path, or more folders waiting, is counted as
   skipped. MIT licence (see LICENSE). */
#include <veranda.h>
#include <string.h>
#include "dt.h"

#define SLOTS 256               /* 64 bytes each, 128 a bank */

struct wentry went;
char wpath[64];
unsigned int w_folders, w_files, w_skipped;
unsigned char w_tag;
static unsigned char wbank;
static unsigned int nstack;
static unsigned char de[128];

unsigned char __fastcall__ join(char *out, const char *a, const char *b)
{
    unsigned char la = strlen(a);
    if (la + strlen(b) + 1 > PATHMAX)
        return 0;
    strcpy(out, a);
    if (!la || a[la - 1] != '/')
        out[la++] = '/';
    strcpy(out + la, b);
    return 1;
}

static char *slot(unsigned int i)
{
    RAMBANK = wbank + (i >> 7);
    return (char *)BANKMEM + ((i & 127) << 6);
}

static unsigned char __fastcall__ push(const char *path, unsigned char tag)
{
    unsigned char keep = RAMBANK;
    char *p;
    if (nstack >= SLOTS || strlen(path) > 62) {
        ++w_skipped;
        return 0;
    }
    p = slot(nstack++);
    strcpy(p, path);
    p[63] = tag;
    RAMBANK = keep;
    return 1;
}

unsigned char __fastcall__ walk_start(const char *path)
{
    if (!wbank && !(wbank = BankAlloc(2)))
        return 0;
    nstack = 0;
    w_folders = w_files = w_skipped = 0;
    return push(path, 0xFF);
}

void walk_end(void)
{
    if (wbank)
        BankFree(wbank);
    wbank = 0;
    nstack = 0;
}

unsigned char __fastcall__ walk_push(const char *name, unsigned char tag)
{
    static char p[64];
    if (!join(p, wpath, name)) {
        ++w_skipped;
        return 0;
    }
    return push(p, tag);
}

static unsigned char hex(unsigned char c)
{
    return c <= '9' ? c - '0' : (c & 0x0F) + 9;
}

/* a listing's line into went; 0 if it is not an entry */
static unsigned char entry(void)
{
    char *t = (char *)de + 3, *q, *n;
    unsigned char i;
    q = strchr(t, '"');
    if (!q)
        return 0;                       /* (the footer) */
    n = ++q;
    q = strchr(q, '"');
    if (!q)
        return 0;
    *q++ = 0;
    if (!n[0] || (n[0] == '.' && (!n[1] || (n[1] == '.' && !n[2]))))
        return 0;
    strncpy(went.name, n, 63);
    went.name[63] = 0;
    while (*q == ' ')
        ++q;
    went.dir = q[0] == 'D' && q[1] == 'I' && q[2] == 'R';
    if (*q)
        q += 3;
    while (*q == ' ' || *q == '<')
        ++q;
    if (q[0] >= '0' && q[0] <= '9' && q[4] == '-' && q[7] == '-' && q[13] == ':') {
        q += 19;
        while (*q == ' ')
            ++q;
    }
    went.size = 0;
    if (q[0] && q[1] && q[2] == ' ') {
        q += 3;
        for (i = 0; i < 8 && q[i] > ' '; ++i)
            went.size = went.size << 4 | hex(q[i]);
    } else
        went.size = (unsigned long)(de[1] | de[2] << 8) << (t[0] == 'M' ? 20 : 10);
    if (went.dir)
        went.size = 0;
    return 1;
}

/* the folder wpath listed: each entry to f, then an empty one; 0 if it
   cannot be read */
unsigned char __fastcall__ walk_list(void (*f)(void))
{
    unsigned char first = 1;
    if (ChDir(wpath) || DirOpen("=L"))
        return 0;
    de[125] = 0;
    while (DirNext(de) == 0) {
        if (first) {
            first = 0;                  /* (the header) */
            continue;
        }
        if (!entry())
            continue;
        if (!went.dir)
            ++w_files;
        f();
    }
    went.name[0] = 0;                   /* the folder's end */
    went.dir = 0;
    f();
    return 1;
}

unsigned char __fastcall__ walk_step(void (*f)(void))
{
    unsigned char keep = RAMBANK;
    char *p;
    if (!nstack)
        return 0;
    p = slot(--nstack);
    strcpy(wpath, p);
    w_tag = p[63];
    RAMBANK = keep;
    ++w_folders;
    if (!walk_list(f))
        ++w_skipped;
    return 1;
}
