/* Veranda shell: the dock's pins (overlay 5, with print.c, and pin_add in
   overlay 9, with bars.c, for the room: DECISIONS V163; dir.c's until then).

   Up to MAXPINS programs, kept in the desk bank (PIN_AT, out of main
   RAM: main.c's pin_get and pin_put copy one to P) and in the desk file
   (dir.c, version 4) in their order. A program is pinned by a drop on
   the desktop (at the end) or on the dock (where it is dropped; one
   pinned already moves there), or with Options > Pin; a pin dragged
   along the dock moves, dragged off it or onto its trash it is unpinned
   (the program stays). A first start (nothing ever pinned) pins the
   default programs that are in /VERANDA/APPS. */
#include <veranda.h>
#include <string.h>
#include <vrpath.h>
#include "shell.h"
#pragma code-name ("OVERLAY5")
#pragma bss-name ("OVL5BSS")

#define PSZ (sizeof(struct pin))

/* pins i and i + 1 swapped (through buf: i + 1, i) */
static void swap(unsigned char i)
{
    bget(bDesk, PIN_AT + i * PSZ, buf + PSZ, 2 * PSZ);
    memcpy(buf, buf + 2 * PSZ, PSZ);
    bput(bDesk, PIN_AT + i * PSZ, buf, 2 * PSZ);
}

/* pin i to place to, the others moved up or down */
static void move(unsigned char i, unsigned char to)
{
    while (i < to)
        swap(i++);
    while (i > to)
        swap(--i);
}

/* what changed said (what, str: the program), the icons read again, the
   desk file written */
static void done(const char *what)
{
    strcpy(msg, what);
    strcat(msg, str);
    LogText(msg);
    XCALL(bDir, pins_icons, FV)();
    XCALL(bDir, desk_save, FV)();
}

/* pin i moved before pin at (a place among the pins, i's own counted):
   1 if it moved */
unsigned char pin_move(unsigned char i, unsigned char at)
{
    if (at > i)
        --at;                           /* (its place among the others) */
    if (at >= npins)
        at = npins - 1;
    if (at == i)
        return 0;
    move(i, at);
    return 1;
}

void pin_remove(unsigned char i)
{
    if (i >= npins)
        return;
    pin_get(i);
    strcpy(str, P.name);
    move(i, npins - 1);
    --npins;
    done("SHELL UNPINNED ");
}

/* pin i dragged on the dock and let go before pin at (a place among the
   pins), or off the dock or on its trash (at $FF): unpinned */
void pin_drop(unsigned char i, unsigned char at)
{
    if (at == 0xFF) {
        pin_remove(i);
        return;
    }
    pin_get(i);
    strcpy(str, P.name);
    if (pin_move(i, at))
        done("SHELL DOCK MOVED ");
}

/* (overlay 3, with dir.c, for the room) the programs pinned on a first
   start, those that are in /VERANDA/APPS (the gates': only with PINS.DEF
   in the top folder) */
#pragma code-name (push, "OVERLAY3")
#pragma rodata-name (push, "OVL3RO")
static const char defs[] = "Veranda Write\0Veranda Edit\0Paint\0Veranda Gemini\0Veranda Ask\0Term\0";
#pragma rodata-name (pop)

void pins_default(void)
{
    const char *d;
    unsigned char h;
    if (testing) {
        ChDir("/");
        h = FOpen("PINS.DEF", 'r');
        if (h < 2)
            return;
        FClose(h);
    }
    if (ChDir(VR_APPSDIR))
        return;
    for (d = defs; *d && npins < MAXPINS; d += strlen(d) + 1) {
        strcpy(tmp, d);                 /* (below $A000 for the kernel) */
        if (FindFile(tmp))
            continue;
        strcpy(P.dir, VR_APPSDIR);
        strcpy(P.name, tmp);
        strcat(P.name, ".cvt");
        pin_put(npins++);
    }
    deskDirty = 1;
    strcpy(msg, "SHELL PINS DEFAULT ");
    num(npins, msg + 19);
    LogText(msg);
}
#pragma code-name (pop)

/* (overlay 9, with bars.c, for the room) E, an application in the front
   window's folder, pinned before pin at (a place among the pins; $FF: the
   end); one pinned already moves there */
#pragma code-name (push, "OVERLAY9")
void pin_add(unsigned char at)
{
    unsigned char i;
    for (i = 0; i < npins; ++i) {
        pin_get(i);
        if (!strcmp(P.dir, (char *)curDirName) && !strcmp(P.name, E.name))
            break;
    }
    if (i == npins) {
        if (npins >= MAXPINS) {
            LogText("SHELL DOCK FULL");
            shell_warn("The dock is full: unpin a program first.");
            return;
        }
        if (strlen((char *)curDirName) >= PINDIR || strlen(E.name) >= PINNAME) {
            shell_warn("Its name or its folder's is too long.");
            return;
        }
        strcpy(P.dir, (char *)curDirName);
        strcpy(P.name, E.name);
        pin_put(npins++);
    } else if (at == 0xFF) {
        shell_say("It is pinned already.");
        return;
    }
    if (at != 0xFF)
        XCALL(bPrint, pin_move, unsigned char (*)(unsigned char, unsigned char))(i, at);
    strcpy(msg, "SHELL PINNED ");
    strcat(msg, E.name);
    LogText(msg);
    XCALL(bDir, pins_icons, FV)();
    XCALL(bDir, desk_save, FV)();
}
#pragma code-name (pop)
