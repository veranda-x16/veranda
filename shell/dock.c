/* Veranda shell: the dock (overlay 10, with the tiles: a bank of its own
   would cost a desk accessory its room at 512 KB; Veranda Look 2, step E, DECISIONS
   V83).

   A strip at the bottom of the desktop, over its picture and the windows,
   centred: card rows SH / 8 - 7 to SH / 8 - 2 (53-58 at 480
   lines). Look 3 "Sunroom" (stage E, DECISIONS V152: the proposal's
   A-desktop.png): a white plate (the paper) in a rounded frame
   (radius 6) with a 2-pixel shadow right and below (light mode: an ink
   dither), an item every 6 cards from 2 cards in: the pinned
   applications, the applications put aside that are not pinned (the
   switcher, TaskCtl: from the path the shell gives each program it
   starts as its note, V84; a document when it has none), the windows
   minimised (a folder); a dot under each application that is aside;
   then a line and the trash (a click opens it, a file dropped on it is
   deleted: mouse.c). Each item is its colour icon where the shell has
   one (look3.c's cache: the program's own from its file, or the
   library's by its class; the info block's class kept by pins_icons),
   else its Look 2 tile.

   (V163) The dock is the launcher: up to MAXPINS (10) pins, from the
   desk bank (pins.c); an item every 6 cards, 5 or 4 when that is too
   wide for them all. A pin's press is mouse.c's: let go on it, a click;
   dragged, it moves along the dock (dock_at_pin: the place among the
   pins), or off it or onto the trash it is unpinned (pin_drop); a
   program dropped on the dock from a window is pinned there.

   A click: a pinned application starts, or comes back if it is aside
   (TaskCtl TASK_RESUME: the shell ends, the application goes on where it
   was); a minimised window opens again. A right click: a small menu over
   the item, Quit (an application aside: dropped, after a question) and
   Unpin, or Restore for a window; the next press chooses (anywhere else:
   nothing). The minimised windows are kept in the desk file (SHELL.DSK
   version 3, byte 15: dockMin), as the shell starts again after every
   program. Console: SHELL DOCK <items>, SHELL DOCK RESUME/QUIT/UNPIN/
   MIN/RESTORE ... */
#include <veranda.h>
#include <string.h>
#include <theme.h>
#include "shell.h"
#include "winp.h"
#include "tiles.h"
#pragma code-name ("OVERLAY10")
#pragma rodata-name ("OVL10RO")
#pragma bss-name ("OVL10BSS")

#define DOCKMAX (MAXPINS + TASK_MAX + NWIN)
enum { D_PIN, D_TASK, D_WIN };

/* (V152) an item every 6 cards, the first 2 in; (V163) 5 or 4 when that
   is too wide for them all */
static unsigned char st;

static unsigned char n, np, x0, top, tasks;
static unsigned char kind[DOCKMAX], idx[DOCKMAX], slot[DOCKMAX];
static unsigned char ttile[TASK_MAX];                   /* the tasks' tiles (dir.c: the desk bank's TT_AT) */
static char tname[TASK_MAX][17];
static unsigned char pop = 0xFF, popN, popX, popY;     /* the menu: its item, its lines, card, row */
static unsigned char popAct[2];
enum { P_QUIT, P_UNPIN, P_RESTORE };
static const char *const popText[3] = { "Quit", "Unpin", "Restore" };

static void say(const char *what, const char *name)
{
    strcpy(msg, "SHELL DOCK ");
    strcat(msg, what);
    strcat(msg, name);
    LogText(msg);
}

/* a pin's name without ".cvt" to str */
static void pinName(unsigned char p)
{
    pin_get(p);
    strcpy(str, P.name);
    if (shell_is_cvt(str))
        str[strlen(str) - 4] = 0;
}

/* item i's name to str */
static void itemName(unsigned char i)
{
    if (kind[i] == D_PIN)
        pinName(idx[i]);
    else if (kind[i] == D_TASK)
        strcpy(str, tname[idx[i]]);
    else
        strcpy(str, wins[idx[i]].path);
}

/* the items: the pins, the tasks (a pin's when its first 16 characters
   are the task's name), the minimised windows; as many as fit an item
   every 4 cards (V163: 18 at 640, 8 at 320), every 6 when they fit so */
void dock_layout(void)
{
    unsigned char i, s, max = (SW / 8 - 8) / 4;
    n = 0;
    tasks = 0;
    top = SH / 8 - 7;                  /* (V152: the mockup's rows 53-58 at 480 lines; 52-57 before) */
    bget(bDesk, TT_AT, pic, TASK_MAX);     /* (through main RAM: bget maps the bank at $A000) */
    memcpy(ttile, pic, TASK_MAX);
    for (i = 0; i < npins && n < max; ++i) {
        kind[n] = D_PIN;
        idx[n] = i;
        slot[n++] = 0xFF;
    }
    np = n;
    for (s = 0; s < TASK_MAX; ++s) {
        TaskCtl(TASK_INFO, s, buf);
        tname[s][0] = 0;
        if (!buf[TR_STATE])
            continue;
        ++tasks;
        memcpy(tname[s], buf + TR_NAME, 17);
        for (i = 0; i < n; ++i) {
            if (kind[i] != D_PIN)
                continue;
            pinName(idx[i]);
            str[16] = 0;
            if (!strcmp(str, tname[s]))
                break;
        }
        if (i < n) {
            slot[i] = s;
        } else if (n < max) {
            kind[n] = D_TASK;
            idx[n] = s;
            slot[n++] = s;
        }
    }
    for (i = 0; i < NWIN && n < max; ++i)
        if ((dockMin >> i & 1) && !wins[i].open) {
            kind[n] = D_WIN;
            idx[n] = i;
            slot[n++] = 0xFF;
        }
    for (st = 6; n * st + 8 > SW / 8; --st)
        ;
    x0 = (SW / 8 - (n * st + 8)) / 2;
    if (!testing)
        return;
    strcpy(msg, "SHELL DOCK");
    for (i = 0; i < n; ++i) {
        itemName(i);
        strcat(msg, i ? ", " : " ");
        strcat(msg, str);
        if (slot[i] != 0xFF)
            strcat(msg, " *");
    }
    LogText(msg);
}

static unsigned int L0(void) { return x0 * 8; }
static unsigned int R0(void) { return (x0 + n * st + 8) * 8 - 1; }
static unsigned int T0(void) { return top * 8; }
static unsigned int B0(void) { return (top + 6) * 8 - 1; }
static unsigned char CX(unsigned char i) { return x0 + 2 + i * st; }   /* item i's card (n: the trash) */

static unsigned char tileOf(unsigned char i)
{
    if (i == n)
        return TL_BUILT + T_TRASH;
    if (kind[i] == D_PIN)
        return pinTile[idx[i]];
    if (kind[i] == D_TASK && ttile[idx[i]])
        return ttile[idx[i]];
    return TL_BUILT + (kind[i] == D_WIN ? T_FOLDER : T_DOCUMENT);
}

/* item i's icon in the desk bank (look3.c: its class, V152) */
static unsigned char iconOf(unsigned char i)
{
    return kind[i] == D_TASK ? MAXPINS + idx[i] : idx[i];
}

/* the dock where it meets l, t, r, b (the scene: the kernel's clip is on) */
void dock_draw(unsigned int l, unsigned int t, unsigned int r, unsigned int b)
{
    unsigned char i, cx;
    unsigned int y = (top + 5) * 8 + 3;
    if (!n || l > R0() + 2 || r < L0() || t > B0() + 2 || b + (pop != 0xFF ? 48 : 0) < T0())
        return;
    SetPattern(0);
    WRectangle(L0(), T0(), R0(), B0());
    shell_rframe(L0(), T0(), R0(), B0(), 6);
    if (!theme.dark && guiOn == ic3On) {        /* the shadow (V152; dark mode's ink is light;
                                                   V180: the soft one below 640 x 480) */
        SetPattern(2);
        WRectangle(R0() + 1, T0() + 4, R0() + 2, B0() + 2);
        WRectangle(L0() + 4, B0() + 1, R0(), B0() + 2);
    }
    SetPattern(1);                              /* the line before the trash */
    WRectangle(CX(n) * 8 - 9, T0() + 8, CX(n) * 8 - 9, T0() + 39);
    for (i = 0; i <= n; ++i) {
        cx = CX(i);
        XCALL(bLook3, ic3_draw, unsigned char (*)(unsigned char, unsigned int, unsigned char, unsigned char, unsigned char))
            (cx, T0() + 8, 2, tileOf(i), i < n ? iconOf(i) : 0);
        if (i < n && slot[i] != 0xFF) {
            SetPattern(1);
            WRectangle(cx * 8 + 15, y, cx * 8 + 17, y + 2);
        }
    }
    if (pop != 0xFF) {                          /* the right click's menu */
        SetPattern(0);
        WRectangle(popX * 8, popY * 8, popX * 8 + 63, (popY + popN * 2) * 8 - 1);
        WFrameRectangle(0xFF, popX * 8, popY * 8, popX * 8 + 63, (popY + popN * 2) * 8 - 1);
        UseFont(FONT_UI);
        for (i = 0; i < popN; ++i) {
            strcpy(str, popText[popAct[i]]);    /* (below $A000 for the kernel) */
            WPutString(str, popX * 8 + 8, (popY + i * 2) * 8 + 3 + baselineOffset);
        }
        UseSystemFont();
    }
}

/* its colours (win_colours: the colour clip) */
void dock_colours(void)
{
    unsigned char i, ei = E.icon;
    if (!n)
        return;
    look_rect(x0, n * st + 8, top, 6, ic3On ? PAPER : SIDEBAR);  /* (the paper with the colour chrome: V102;
                                                                      V180: with the colour icons) */
    if (ic3On && !guiOn)                /* (V180: below 640 x 480, the soft shadow) */
        XCALL(bOps, sh_rect, void (*)(unsigned char, unsigned char, unsigned char, unsigned char))(x0, x0 + n * st + 8, top, top + 6);
    for (i = 0; i <= n; ++i) {
        E.icon = I_OWN + (i < n ? iconOf(i) : 0);  /* (look3.c's ic3_colour: the item's class) */
        XCALL(bLook3, ic3_colour, FICON)(CX(i), top + 1, 2, tileOf(i), 0xFF);
    }
    E.icon = ei;
    XCALL(bWall, gui_plate, void (*)(unsigned char, unsigned char, unsigned char, unsigned char))(x0, x0 + n * st + 7, top, top + 5);
    if (pop != 0xFF)
        look_rect(popX, 8, popY, popN * 2, CHROME);
}

/* the dock (and its menu) drawn again after a change of its items, laid
   out again already: it was n = was items from l to r (V117) */
static void redock(unsigned int l, unsigned int r, unsigned char was)
{
    if (!was) {
        l = L0();
        r = R0() + 2;
    } else if (n) {
        if (L0() < l)
            l = L0();
        if (R0() + 2 > r)
            r = R0() + 2;
    }
    if (!was && !n)
        return;
    if (r < CX(n ? n - 1 : 0) * 8 + 63)         /* (the menu, over the last item) */
        r = CX(n ? n - 1 : 0) * 8 + 63;
    XCALL(bWin, win_repaint, void (*)(unsigned int, unsigned int, unsigned int, unsigned int))(l, T0() - 48, r, B0() + 2);
}

/* the dock (and its menu) drawn again, after a change of its items */
static void again(void)
{
    unsigned int l = L0(), r = R0() + 2;
    unsigned char was = n;
    dock_layout();
    redock(l, r, was);
}

/* (these two in overlay 1, with win.c, for the room: V163; their callers
   name bWin) the program tmp (its GEOS name) about to start from folder
   dir: its path, dir/tmp, the switcher's note for it (V84: the dock's
   tile when it is put aside); none when it does not fit */
#pragma code-name (push, "OVERLAY1")
#pragma rodata-name (push, "OVL1RO")
/* (their texts as arrays here: cc65 puts string literals in the file's
   rodata, overlay 10's) */
static const char tNoMem[] = "Not enough memory for ";
static const char tNoBanks[] = "SHELL DOCK NO BANKS";
static const char tQuitOne[] = "Quit a program in the dock first.";
void dock_note(const char *dir)
{
    unsigned char l = strlen(dir);
    msg[0] = 0;
    if (l + strlen(tmp) + 2 <= TASK_NOTE_LEN) {
        strcpy(msg, dir);
        if (l > 1) {
            msg[l] = '/';
            msg[l + 1] = 0;
        }
        strcat(msg, tmp);
    }
    TaskCtl(TASK_NOTE, 0, msg);
}

/* the shell starts: the dock laid out; a start that failed for want of
   banks said (the switcher's summary: the desktop came instead) */
void dock_init(void)
{
    TaskCtl(TASK_INFO, 0xFF, buf);
    if (buf[TS_ERR] == NO_BANKS) {
        strcpy(msg, tNoBanks);
        LogText(msg);
        strcpy(msg, tNoMem);
        strcat(msg, (char *)buf + TS_NAME);
        strcpy(tmp, tQuitOne);
        shell_yes(msg, tmp);
    }
}
#pragma rodata-name (pop)
#pragma code-name (pop)

/* window w minimised: closed, kept in the dock */
void dock_min(unsigned char w)
{
    dockMin |= 1 << w;
    deskDirty = 1;
    XCALL(bOps, win_close, FB)(w);
    say("MIN ", wins[w].path);
    again();
}

void dock_click(unsigned char i)
{
    unsigned char r, was = n;
    unsigned int l = L0(), rr = R0() + 2;
    itemName(i);
    if (kind[i] == D_WIN) {
        dockMin &= ~(1 << idx[i]);
        deskDirty = 1;
        say("RESTORE ", str);
        dock_layout();                  /* (the window drawn without its item) */
        /* (V117) in front first, as every other opening does (main.c's
           openOn, mouse.c's deskOpen): win_open reads curDirName, the
           front window's path, and draws the window whole only when it
           is the front one */
        XCALL(bWin, win_behind, FB)(front);
        shell_front(idx[i]);
        XCALL(bOps, win_open, FB)(idx[i]);
        redock(l, rr, was);             /* (where its item was: again() would see none) */
        return;
    }
    if (slot[i] == 0xFF) {
        say("START ", str);
        shell_pin_start(idx[i]);
        return;
    }
    say("RESUME ", str);
    shell_keep();
    mouseSource = 0;                    /* (the player is overwritten) */
    if (wallMode == W_PICTURE)          /* (the picture's banks lent, as for a program */
        XCALL(bWall, wall_drop, FV)();  /* started: main.c's lend; V151) */
    r = TaskCtl(TASK_RESUME, slot[i], 0);
    shell_err("Cannot bring it back:", r);
}

static void choose(unsigned char a, unsigned char i)
{
    itemName(i);
    if (a == P_RESTORE) {
        dock_click(i);
    } else if (a == P_UNPIN) {
        say("UNPIN ", str);
        XCALL(bPrint, pin_remove, FB)(idx[i]);
        again();
    } else {
        strcpy(tmp, "Quit ");
        strcat(tmp, str);
        strcat(tmp, "?");
        strcpy(msg, "What it did not save is lost.");   /* (below $A000) */
        if (shell_yes(tmp, msg)) {
            say("QUIT ", str);
            TaskCtl(TASK_END, slot[i], 0);
            again();
        }
    }
}

/* the item at x (n: the trash; $FF between them), y on the dock */
static unsigned char dock_at(unsigned int x)
{
    x -= L0();
    if (x < 16 || (x - 16) % (st * 8) >= 32)
        return 0xFF;
    return (x - 16) / (st * 8);
}

static unsigned char on(unsigned int x, unsigned int y)
{
    return n && x >= L0() && x <= R0() && y >= T0() && y <= B0();
}

/* (V193, mouse.c's ghost) item i's tile's corner: vx, vy */
void dock_tile(unsigned char i)
{
    vx = CX(i) * 8;
    vy = (top + 1) * 8;
}

/* (V163, mouse.c) a drop at x, y: off the dock $FF; on its trash $FE (V152:
   a file dropped there is deleted, a pin unpinned); else the place among
   the pins before the first whose middle is right of x */
unsigned char dock_at_pin(unsigned int x, unsigned int y)
{
    unsigned char i;
    if (!on(x, y))
        return 0xFF;
    if (dock_at(x) == n)
        return 0xFE;
    x -= L0();
    i = x <= 32 ? 0 : (x - 33) / (st * 8) + 1;
    return i < np ? i : np;
}

/* a press at x, y (w: the window there, $FF none): 1 if the dock took it */
unsigned char dock_press(unsigned int x, unsigned int y, unsigned char w)
{
    unsigned char i, a;
    if (pop != 0xFF) {                          /* the menu's choice, or none */
        i = pop;
        a = 0xFF;
        if (x >= popX * 8 && x < popX * 8 + 64 && y >= popY * 8 && y < (popY + popN * 2) * 8)
            a = popAct[(y / 8 - popY) / 2];
        pop = 0xFF;
        again();
        if (a != 0xFF)
            choose(a, i);
        return 1;
    }
    if (w != 0xFF || !on(x, y))
        return 0;
    i = dock_at(x);
    if (i > n)
        return 1;
    if (i == n) {                               /* the trash (V152) */
        if (!(mouseButtons & 2)) {
            say("TRASH", "");
            shell_trash();
        }
        return 1;
    }
    if (!(mouseButtons & 2)) {
        if (kind[i] == D_PIN)           /* (V163) a click or a drag: mouse.c's */
            return DOCK_PIN + i;
        dock_click(i);
        return 1;
    }
    popN = 0;                                   /* the right button: the menu */
    if (kind[i] == D_WIN)
        popAct[popN++] = P_RESTORE;
    if (slot[i] != 0xFF)
        popAct[popN++] = P_QUIT;
    if (kind[i] == D_PIN)
        popAct[popN++] = P_UNPIN;
    popX = CX(i);
    popY = top - popN * 2;
    pop = i;
    itemName(i);
    say("MENU ", str);
    again();
    return 1;
}
