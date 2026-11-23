/* Veranda's clipboard: the scrap files (scrap.h). MIT licence (see LICENSE).

   A scrap is a CVT file (docs/APPFORMAT.md): the 30-byte directory
   entry, the signature padded to 254 bytes, the info block (254 bytes),
   the data from byte 508. It is opened by a path in the system's data
   folder, "//VERANDA/.SYSTEM/:Name.cvt" (the shell makes it), else in the
   root (no /VERANDA; DECISIONS V71: veranda.h's VR_DATAPATH, VR_ROOTPATH),
   so the application's directory stays as it is (FOpen writes such a
   name with "@" in front: DECISIONS V54).

   A program short of room compiles these sources (the SDK's src/) into an
   overlay of its own (cc65's --code-name, --rodata-name, --bss-name) with
   -DSCRAP_PATH=<a 40-byte buffer of its own below $A000>: nothing here
   relies on a zeroed BSS. */
#include <veranda.h>
#include <string.h>
#include "scrap.h"

static const char *const names[2] = { "Text  Scrap", "Photo Scrap" };
#define NDIRS 2
static const char *const dirs[NDIRS] = { VR_DATAPATH, VR_ROOTPATH };
#ifdef SCRAP_PATH                       /* compiled into an overlay: the name below $A000 */
extern char SCRAP_PATH[40];             /* (FOpen reads it with a kernel bank at $A000) */
#define path SCRAP_PATH
#else
static char path[40];
#endif
static unsigned char h;                 /* the open scrap, 0 none */
static unsigned char ent[30];

/* path = folder d + the scrap's name + ".cvt" */
static char *put(char *p, const char *s)
{
    while (*s)
        *p++ = *s++;
    return p;
}

static void make_path(unsigned char d, unsigned char kind)
{
    *put(put(put(path, dirs[d]), names[kind]), ".cvt") = 0;
}

/* FOpen on path: the handle, 0 on an error (ferr). The C binding drops
   x, the error; a failed open leaves the DOS's status in dosStatus (20 or
   more), a refused one a handle that is not 2-9. (Not vr_fopen: a copy
   compiled into an overlay then needs nothing more resident.) */
static unsigned char ferr;

static unsigned char open_path(unsigned char mode)
{
    unsigned char k = FOpen(path, mode);
    if (k >= 2 && k <= 9 && dosStatus < 20)
        return k;
    ferr = dosStatus >= 20 ? DOS_ERROR : FILE_NOT_FOUND;
    return 0;
}

/* the scrap for reading: the first of the folders that has it */
static unsigned char open_read(unsigned char kind)
{
    unsigned char d;
    for (d = 0; d < NDIRS; ++d) {
        make_path(d, kind);
        if ((h = open_path('r')) != 0)
            return 0;
    }
    return FILE_NOT_FOUND;
}

unsigned char scrap_close(void)
{
    unsigned char e = 0;
    if (h)
        e = FClose(h);
    h = 0;
    return e;
}

unsigned int __fastcall__ scrap_read(void *p, unsigned int n)
{
    return h ? FRead(h, p, n) : 0;
}

unsigned char __fastcall__ scrap_write(const void *p, unsigned int n)
{
    return h ? FWrite(h, (void *)p, n) : FILE_NOT_FOUND;
}

/* the entry (30 bytes) and the serial (info block bytes 158-159) */
static unsigned int serial;

/* n bytes read past (into path: its name is no longer needed), no seek:
   the DOS's commands (seek, tell) are echoed on the emulator's console,
   in the middle of a test's log lines */
static unsigned char skip(unsigned int n)
{
    unsigned char k;
    while (n) {
        k = n > sizeof path ? sizeof path : n;
        if (FRead(h, path, k) != k)
            return INCOMPATIBLE;
        n -= k;
    }
    return 0;
}

static unsigned char read_head(void)
{
    if (FRead(h, ent, 30) != 30 || ent[21] != 0 || skip(252 + 158 - 30) || FRead(h, &serial, 2) != 2)
        return INCOMPATIBLE;
    return 0;
}

unsigned char __fastcall__ scrap_stamp(unsigned char kind, unsigned char *st)
{
    unsigned char e;
    memset(st, 0, 8);
    if ((e = open_read(kind)) != 0)
        return e;
    if ((e = read_head()) == 0) {
        memcpy(st, ent + 23, 5);        /* the date */
        memcpy(st + 5, &serial, 2);
        st[7] = ent[28];                /* the size in blocks */
    }
    scrap_close();
    return e;
}

unsigned char __fastcall__ scrap_open(unsigned char kind)
{
    if (open_read(kind))
        return 0;
    if (read_head() || skip(508 - 412)) {
        scrap_close();
        return 0;
    }
    return 1;
}

/* the info block: the icon (a clipboard with a page on it) */
static const unsigned char icon[64] = {
    0xBF,
    0x00, 0x7E, 0x00,  0x03, 0xC3, 0xC0,  0x7F, 0xFF, 0xFE,  0x40, 0x00, 0x02,
    0x47, 0xFF, 0xE2,  0x44, 0x00, 0x22,  0x45, 0xF7, 0xA2,  0x44, 0x00, 0x22,
    0x45, 0xEF, 0x22,  0x44, 0x00, 0x22,  0x45, 0xFB, 0xA2,  0x44, 0x00, 0x22,
    0x45, 0xDE, 0x22,  0x44, 0x00, 0x22,  0x45, 0xF7, 0xA2,  0x44, 0x00, 0x22,
    0x44, 0x00, 0x22,  0x47, 0xFF, 0xE2,  0x40, 0x00, 0x02,  0x40, 0x00, 0x02,
    0x7F, 0xFF, 0xFE
};
static const char *const classes[2] = { "Text  Scrap V2.0", "Photo Scrap V2.0" };
static const char *const descs[2] = { "Text cut or copied, for pasting.", "A picture cut or copied, for pasting." };
static const unsigned char zero[32] = { 0 };    /* (initialised: RODATA, not BSS; a copy compiled
                                                   into an overlay has no zeroed BSS) */

static void zeros(unsigned int n)
{
    unsigned int k;
    while (n) {
        k = n > 32 ? 32 : n;
        FWrite(h, (void *)zero, k);
        n -= k;
    }
}

/* s, padded with zeros to n bytes */
static void field(const char *s, unsigned char n)
{
    unsigned char k = strlen(s);
    FWrite(h, (void *)s, k);
    zeros(n - k);
}

unsigned char __fastcall__ scrap_create(unsigned char kind, unsigned int len)
{
    static unsigned char head[11];
    unsigned char d, e;
    unsigned int b;
    unsigned char st[8];
    scrap_stamp(kind, st);              /* the serial before, counted up */
    serial = (st[5] | st[6] << 8) + 1;
    scrap_close();
    for (d = 0; d < NDIRS; ++d) {
        make_path(d, kind);
        if ((h = open_path('w')) != 0)
            break;
    }
    if (!h)
        return ferr ? ferr : FILE_NOT_FOUND;
    /* the entry: USR, the name padded with $A0, sequential, SYSTEM, the
       date, the size in blocks of 254 (+ 1: the info block) */
    memset(ent, 0, sizeof ent);
    ent[0] = 0x83;
    memset(ent + 3, 0xA0, 16);
    memcpy(ent + 3, names[kind], strlen(names[kind]));
    ent[21] = 0;                       /* sequential */
    ent[22] = SYSTEM;
    memcpy(ent + 23, (void *)0x054F, 5);        /* year ... minutes */
    b = len / 254 + (len % 254 != 0) + 1;
    ent[28] = b;
    ent[29] = b >> 8;
    FWrite(h, ent, 30);
    field("PRG formatted GEOS file V1.0", 224);
    /* the info block from its byte 2 */
    head[0] = 3;
    head[1] = 21;
    FWrite(h, head, 2);
    FWrite(h, (void *)icon, 64);
    memset(head, 0, sizeof head);
    head[0] = 0x83;                     /* 68: USR, SYSTEM, sequential */
    head[1] = SYSTEM;
    head[5] = len;                      /* 73-74: the end (the start 0) */
    head[6] = len >> 8;
    FWrite(h, head, 9);
    field(classes[kind], 20);           /* 77 */
    field("Veranda", 20);               /* 97 */
    zeros(20 + 21);                     /* 117 the parent, 137 the data */
    e = FWrite(h, &serial, 2);          /* 158-159 */
    field(descs[kind], 96);             /* 160 */
    if (e) {
        scrap_close();
        return e;
    }
    return 0;
}
