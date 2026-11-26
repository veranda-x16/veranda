/* Veranda shell: the desktop (docs/PLAN.md phase 6; Shell 2, DECISIONS V70).

   A GEOS deskTop: one or two folder windows over a patterned desktop
   (win.c), the card, the printer, the trash and pinned applications on
   the desktop, a menu bar with the date and time. This is the resident
   part: the entries' and icons' banks, the dialogs, the menus and their
   actions, starting programs, the test hook; the rest is in overlays
   (shell.h).

   A double click opens: an application starts (GetFile), a folder is
   shown in its window, ".." goes up, and a plain file starts the
   application that opens its extension (its info block's documents,
   144-159: one in this folder, in /VERANDA or in the top folder) with the
   file as its document (GetFile, ST_LD_DATA; the file's folder stays in
   curDirName: DECISIONS V48).
   Menus: geos (about, desk accessories), file (open, duplicate, rename,
   delete, get info, view, copy, move, put here, print, find), view (by
   icon, by small icon, by name, size, date, type: the list sorted;
   refresh, up a folder), disk (open the card, a new window, close the
   window, the trash, empty trash), select, page, options (the video
   modes, Preferences (V180: was the desktop's pattern), pin and unpin, BASIC with Veranda kept,
   quit Veranda: DECISIONS V64).

   The front window's path is curDirName (the kernel's current folder);
   window 0's path, its view and the video mode are the shell's own
   folder in the kernel (SysPrefs DESK_SET just before a program starts,
   DESK_GET at start: DECISIONS V63; byte 62 the view, the sort and the
   desktop's pattern, byte 63 the mode + 1); the second window, the
   windows' places and the pins in the desk file (dir.c), written only
   when they change.

   The test hook: if SHELL.TST exists (in the top folder) it holds a script
   of parts (see play.s); SHELL.STP counts the shell's starts, and start n
   plays part n. */
#include <vrcs.h>
#include <veranda.h>
#include <string.h>
#include <stdlib.h>
#include <vr.h>
#include "shell.h"

void __fastcall__ play_start(const void *part);
static unsigned char start(unsigned char opts, const char *doc);

struct win wins[NWIN];
unsigned char front = 0xFF;
unsigned char bIcons, bDesk, bTiles, bWin, bView, bDir, bFiles, bPrint, bMouse, bOps, bChrome, bBars, bTile, bWall, bDock, bLook3, bIc2, bPrg;
unsigned char wallMode = W_PATTERN, wallBank, guiOn;
unsigned char vCols, vRows, ic3On, ic3Want, ic3Now, ic3Next, deskFresh;          /* (V151) view.c's geometry; look3.c: the plain tile desktop */
unsigned char tileBuf[132];
char k3buf[13];                            /* (look3.c: a window's class from bInk) */
unsigned char pinTile[MAXPINS];
struct ent E, E2;
unsigned char pic[64];
char cardName[18];
unsigned long cardFree;
unsigned char deskPat;
char tmp[NAMELEN + 24];
char str[NAMELEN + 24];
char msg[160];
unsigned char buf[1024];                   /* copies; FindFTypes */
struct pin P;
unsigned char npins, deskDirty, testing, dockMin;

unsigned char script[2048];                /* SHELL.TST */
unsigned char *part;
unsigned char tstep;                       /* the part played */

/*---------------------------------------------------------------- banks */

void ent_get(unsigned char w, unsigned char i)
{
    unsigned char s = RAMBANK;
    RAMBANK = wins[w].bank;
    memcpy(&E, (char *)0xA000 + ((unsigned int)i << 6), sizeof E);
    RAMBANK = s;
}

void ent_get2(unsigned char w, unsigned char i)
{
    unsigned char s = RAMBANK;
    RAMBANK = wins[w].bank;
    memcpy(&E2, (char *)0xA000 + ((unsigned int)i << 6), sizeof E2);
    RAMBANK = s;
}

void ent_put(unsigned char w, unsigned char i)
{
    unsigned char s = RAMBANK;
    RAMBANK = wins[w].bank;
    memcpy((char *)0xA000 + ((unsigned int)i << 6), &E, sizeof E);
    RAMBANK = s;
}

/* n bytes to and from offset off of RAM bank b, a file read into or
   written from bank b ($A000): for the overlays, which cannot map another
   bank over themselves */
void bput(unsigned char b, unsigned int off, const void *src, unsigned int n)
{
    unsigned char s = RAMBANK;
    RAMBANK = b;
    memcpy((char *)0xA000 + off, src, n);
    RAMBANK = s;
}

void bget(unsigned char b, unsigned int off, void *dst, unsigned int n)
{
    unsigned char s = RAMBANK;
    RAMBANK = b;
    memcpy(dst, (char *)0xA000 + off, n);
    RAMBANK = s;
}

/* (V163) the pins live in the desk bank: P = pin i, pin i = P */
void pin_get(unsigned char i)
{
    bget(bDesk, PIN_AT + i * sizeof(struct pin), &P, sizeof P);
}

void pin_put(unsigned char i)
{
    bput(bDesk, PIN_AT + i * sizeof(struct pin), &P, sizeof P);
}

unsigned int bfread(unsigned char b, unsigned char h, unsigned int n)
{
    unsigned char s = RAMBANK;
    RAMBANK = b;
    n = FRead(h, (void *)0xA000, n);
    RAMBANK = s;
    return n;
}

unsigned char bfwrite(unsigned char b, unsigned char h, unsigned int n)
{
    unsigned char s = RAMBANK, e;
    RAMBANK = b;
    e = FWrite(h, (void *)0xA000, n);
    RAMBANK = s;
    return e;
}

/* window w's icon n (or its documents, 16 bytes); w 2: a pin's icon */
static unsigned char *iconAt(unsigned char w, unsigned char n, unsigned char docs)
{
    if (w == 2) {
        RAMBANK = bDesk;
        return (unsigned char *)0xA000 + DI_AT + n * 64;
    }
    RAMBANK = bIcons;
    return (unsigned char *)0xA000 + (w ? 4096 : 0) + (docs ? 3072 + n * 16 : n * 64);
}

const unsigned char *icon_get(unsigned char w, unsigned char n, unsigned char docs)
{
    unsigned char s = RAMBANK;
    memcpy(pic, iconAt(w, n, docs), docs ? 16 : 64);
    RAMBANK = s;
    return pic;
}

void icon_put(unsigned char w, unsigned char n, const unsigned char *icon, const unsigned char *docs)
{
    unsigned char s = RAMBANK;
    memcpy(iconAt(w, n, 0), icon, 64);
    if (docs)
        memcpy(iconAt(w, n, 1), docs, 16);
    RAMBANK = s;
}

/*---------------------------------------------------------------- names */

static unsigned char lower(unsigned char c)
{
    return (c >= 'A' && c <= 'Z') ? c + 32 : c;
}

/* "Name.cvt" -> 1 (a long name too: LONG_MAX characters and ".cvt",
   DECISIONS V82) */
unsigned char shell_is_cvt(const char *n)
{
    unsigned char l = strlen(n);
    return l > 4 && l <= LONG_MAX + 4 && n[l - 4] == '.' && lower(n[l - 3]) == 'c'
        && lower(n[l - 2]) == 'v' && lower(n[l - 1]) == 't';
}

/* the name as shown: a GEOS file's without ".cvt" */
void shown(const struct ent *e, char *out)
{
    strcpy(out, e->name);
    if (e->geos || (e->type == 'F' && shell_is_cvt(out)))
        out[strlen(out) - 4] = 0;
}

static int cmpName(const char *a, const char *b)
{
    unsigned char x, y;
    for (;;) {
        x = lower(*a++);
        y = lower(*b++);
        if (x != y)
            return x < y ? -1 : 1;
        if (!x)
            return 0;
    }
}

/* num(n, out): clip.s (powers of ten subtracted: V81) */

static const char *const tname[] = {
    "not GEOS", "BASIC", "assembly", "data", "system", "desk accessory", "application",
    "document", "font", "printer driver", "input driver", "disk driver", "boot",
    "temporary", "auto-exec", "input 128"
};

/* the list's type column: "folder", a GEOS type, "TXT file", "file" */
void type_str(const struct ent *e, char *out)
{
    const char *d;
    unsigned char i;
    if (e->type != 'F') {
        strcpy(out, "folder");
        return;
    }
    if (e->geos) {
        strcpy(out, e->geos < 16 ? tname[e->geos] : "GEOS file");
        return;
    }
    d = strrchr(e->name, '.');
    if (!d || !d[1] || strlen(d) > 5) {
        strcpy(out, "file");
        return;
    }
    for (i = 0; d[1 + i]; ++i)
        out[i] = lower(d[1 + i]) - (lower(d[1 + i]) >= 'a' && lower(d[1 + i]) <= 'z' ? 32 : 0);
    strcpy(out + i, " file");
}

/*---------------------------------------------------------------- the sort */

/* A binary insertion sort of the order (DECISIONS V80; cc65's qsort took
   593 ms for 60 entries): about n log n comparisons, none through a
   pointer, the names compared in place (the entries' bank mapped for the
   whole sort). The order is the one before: the parent first, then the
   folders, then the files; within them the key, then the name, case
   ignored; entries equal in all that keep the folder's order. */
static unsigned char sortKey;
static char ta[24], tb[24];
static const struct ent *sx, *sy;
static const unsigned char *pa, *pb;

#define ENT(i) ((const struct ent *)(0xA000 + ((unsigned int)(i) << 6)))

/* the emulator's cycle counter (a read of $9FB8 latches it); only in the
   gates (V101: real hardware's expansion cards answer at $9FB0-$9FBF) */
static unsigned long cycles(void)
{
    unsigned long c = 0;
    unsigned char *q = (unsigned char *)&c;
    if (!testing)
        return 0;
    q[0] = *(volatile unsigned char *)0x9FB8;
    q[1] = *(volatile unsigned char *)0x9FB9;
    q[2] = *(volatile unsigned char *)0x9FBA;
    q[3] = *(volatile unsigned char *)0x9FBB;
    return c;
}

/* the strings at pa and pb, case ignored: -1, 0, 1 */
static signed char cmpLow(void)
{
    static unsigned char x, y;
    for (;;) {
        x = *pa++;
        if ((unsigned char)(x - 'A') < 26)
            x += 32;
        y = *pb++;
        if ((unsigned char)(y - 'A') < 26)
            y += 32;
        if (x != y)
            return x > y ? 1 : -1;
        if (!x)
            return 0;
    }
}

/* 1 if sx goes after sy */
static unsigned char after(void)
{
    static unsigned char i, t, u;
    t = sx->type;
    u = sy->type;
    if (t != u)
        return !(t == 'U' || (t == 'D' && u == 'F'));
    if (sortKey == S_SIZE) {
        if (sx->size != sy->size)
            return sx->size < sy->size;             /* the largest first */
    } else if (sortKey == S_DATE) {
        for (i = 0; i < 5; ++i)
            if (sx->date[i] != sy->date[i])
                return sx->date[i] < sy->date[i];   /* the newest first */
    } else if (sortKey == S_TYPE) {
        type_str(sx, ta);
        type_str(sy, tb);
        pa = (const unsigned char *)ta;
        pb = (const unsigned char *)tb;
        t = cmpLow();
        if (t)
            return t == 1;
    }
    pa = (const unsigned char *)sx->name;
    pb = (const unsigned char *)sy->name;
    return cmpLow() == 1;
}

/* window w's order: by name, or (the list) its sort */
void sort_win(unsigned char w)
{
    struct win *p = &wins[w];
    unsigned char i, lo, hi, mid, s = RAMBANK;
    unsigned char *o = p->order;
    unsigned long c = cycles();                 /* (the time: the gates) */
    sortKey = p->view == V_LIST ? p->sort : S_NAME;
    RAMBANK = p->bank;
    for (i = 0; i < p->n; ++i) {
        sy = ENT(i);            /* entry i into order[0 .. i-1] (sorted), */
        lo = 0;                 /* after the ones it does not go before */
        hi = i;
        while (lo < hi) {
            mid = (lo + hi) >> 1;
            sx = ENT(o[mid]);
            if (after())
                hi = mid;
            else
                lo = mid + 1;
        }
        memmove(o + lo + 1, o + lo, i - lo);
        o[lo] = i;
    }
    RAMBANK = s;
    if (testing) {
        c = cycles() - c;
        strcpy(msg, "TIME SORT ");
        num(p->n, msg + 10);
        strcat(msg, " ");
        num(c, msg + strlen(msg));
        LogText(msg);
    }
}

/*---------------------------------------------------------------- dialogs */

/* the message boxes' colour chrome on the tile desktop (V102): boxBand,
   boxPlain, dlg (clip.s) */
void boxBand(void);
void boxPlain(void);
unsigned char __fastcall__ dlg(const void *b);

struct box1 {                   /* text, a line through r5, OK */
    unsigned char pos;
    unsigned char t1, x1, y1; const char *s1;
    unsigned char t2, x2, y2, reg2;
    unsigned char usr; void (*fn)(void);
    unsigned char ok, okx, oky;
    unsigned char end;
};
static const struct box1 msgBox = {
    DEF_DB_POS | 1,
    DBTXTSTR, TXT_LN_X, TXT_LN_1_Y, "Veranda shell",
    DBVARSTR, TXT_LN_X, TXT_LN_3_Y, 0x0C,
    DB_USR_ROUT, boxBand,
    OK, DBI_X_0, DBI_Y_2,
    0
};

struct box3 {                   /* text, an input through r5, OK, CANCEL */
    unsigned char pos;
    unsigned char t1, x1, y1; const char *s1;
    unsigned char t2, x2, y2, reg2, max2;
    unsigned char usr; void (*fn)(void);
    unsigned char ok, okx, oky;
    unsigned char cn, cnx, cny;
    unsigned char end;
};
static struct box3 nameBox = {
    DEF_DB_POS | 1,
    DBTXTSTR, TXT_LN_X, TXT_LN_1_Y, "New name:",
    DBGETSTRING, TXT_LN_X, TXT_LN_2_Y, 0x0C, 16,
    DB_USR_ROUT, boxPlain,
    OK, DBI_X_0, DBI_Y_2,
    CANCEL, DBI_X_2, DBI_Y_2,
    0
};

struct box4 {                   /* the desk accessories: a file list, OPEN, CANCEL */
    unsigned char pos;
    unsigned char f, fx, fy;
    unsigned char op, opx, opy;
    unsigned char cn, cnx, cny;
    unsigned char end;
};
static const struct box4 deskBox = {
    DEF_DB_POS | 1,
    DBGETFILES, 4, 4,
    OPEN, DBI_X_2, DBI_Y_0,
    CANCEL, DBI_X_2, DBI_Y_2,
    0
};

struct box5 {                   /* two lines through r5 and r6, YES, NO */
    unsigned char pos;
    unsigned char t1, x1, y1, reg1;
    unsigned char t2, x2, y2, reg2;
    unsigned char usr; void (*fn)(void);
    unsigned char yes, yesx, yesy;
    unsigned char no, nox, noy;
    unsigned char end;
};
static const struct box5 yesBox = {
    DEF_DB_POS | 1,
    DBVARSTR, TXT_LN_X, TXT_LN_1_Y, 0x0C,
    DBVARSTR, TXT_LN_X, TXT_LN_2_Y, 0x0E,
    DB_USR_ROUT, boxPlain,
    YES, DBI_X_0, DBI_Y_2,
    NO, DBI_X_2, DBI_Y_2,
    0
};

unsigned char shell_yes(const char *line1, const char *line2)
{
    r5 = (unsigned int)line1;
    r6 = (unsigned int)line2;
    return dlg(&yesBox) == YES;
}

static void say(const char *m)
{
    r5 = (unsigned int)m;
    dlg(&msgBox);
}

/* About: its text on two lines (V132: "A desktop for the Commander
   X16." on one ran past the box's right edge) */
struct box2 {                   /* three lines of text, OK */
    unsigned char pos;
    unsigned char t1, x1, y1; const char *s1;
    unsigned char t2, x2, y2; const char *s2;
    unsigned char t3, x3, y3; const char *s3;
    unsigned char usr; void (*fn)(void);
    unsigned char ok, okx, oky;
    unsigned char end;
};
static const struct box2 aboutBox = {
    DEF_DB_POS | 1,
    DBTXTSTR, TXT_LN_X, TXT_LN_1_Y, "Veranda shell",
    DBTXTSTR, TXT_LN_X, TXT_LN_2_Y + 2, "A desktop for the",
    DBTXTSTR, TXT_LN_X, TXT_LN_3_Y + 2, "Commander X16.",
    DB_USR_ROUT, boxBand,
    OK, DBI_X_0, DBI_Y_2,
    0
};

/* an error: the system beep, then the message (DECISIONS V51) */
static void warn(const char *m)
{
    Beep();
    say(m);
}

void shell_say(const char *m)
{
    say(m);
}

void shell_warn(const char *m)
{
    warn(m);
}

static void sayErr(const char *what, unsigned char e)
{
    unsigned char l;
    strcpy(msg, what);
    l = strlen(msg);
    msg[l++] = ' ';
    msg[l++] = '0' + dosStatus / 10;
    msg[l++] = '0' + dosStatus % 10;
    msg[l++] = '/';
    msg[l++] = '0' + e / 10;
    msg[l++] = '0' + e % 10;
    msg[l] = 0;
    warn(msg);
}

void shell_err(const char *what, unsigned char e)
{
    sayErr(what, e);
}

/*---------------------------------------------------------------- windows */

static unsigned char atRoot(const char *p)
{
    return p[1] == 0;
}

/* curDirName = window w's path, w in front */
void shell_front(unsigned char w)
{
    front = w;
    if (w == 0xFF)
        return;
    strcpy((char *)curDirName, wins[w].path);
    ChDir(curDirName);
}

static void drawAll(void)
{
    XCALL(bWin, win_all, FV)();
}

/* window w read again (its path) and drawn (V165: the page shown first,
   its other files after it is drawn) */
static void reread(unsigned char w)
{
    XCALL(bDir, dir_read, FB)(w | 0x80);
    XCALL(bWin, win_redraw, FB)(w);
    XCALL(bIc2, dir_rest, FB)(w);
}

void shell_reload(void)
{
    unsigned char w;
    for (w = 0; w < NWIN; ++w)
        if (wins[w].open)
            XCALL(bDir, dir_read, FB)(w);
    if (front != 0xFF)
        ChDir(wins[front].path);
    drawAll();
}

void shell_redraw(void)
{
    if (front != 0xFF)
        XCALL(bWin, win_content, FB)(front);
}

/*---------------------------------------------------------------- the history (Look 2) */

static unsigned char navving;   /* back or forward: the history stays */

/* window w's path as the newest in its history (the ones after the one
   shown forgotten); 8 paths in the window's bank, at HISTAT */
void shell_hist(unsigned char w)
{
    struct win *p = &wins[w];
    if (navving)
        return;
    if (p->hn) {
        bget(p->bank, HISTAT + p->hc * 64, tmp, PATHMAX + 1);
        if (!strcmp(tmp, p->path))
            return;
        p->hn = p->hc + 1;
    }
    if (p->hn >= HISTN) {
        bget(p->bank, HISTAT + 64, buf, (HISTN - 1) * 64);
        bput(p->bank, HISTAT, buf, (HISTN - 1) * 64);
        p->hn = HISTN - 1;
    }
    bput(p->bank, HISTAT + p->hn * 64, p->path, PATHMAX + 1);
    p->hc = p->hn++;
}

/* window w shows the folder p (made current); 0 if it does not open */
unsigned char shell_goto(unsigned char w, const char *p)
{
    if (ChDir((void *)p)) {
        if (front != 0xFF)
            ChDir(wins[front].path);
        return 0;
    }
    if (strcmp(wins[w].path, p))
        wins[w].find[0] = 0;
    strcpy(wins[w].path, p);
    if (w)
        deskDirty = 1;
    shell_hist(w);
    shell_front(w);
    reread(w);
    return 1;
}

/* the toolbar's back (d -1) and forward (+1) */
void shell_nav(unsigned char w, signed char d)
{
    struct win *p = &wins[w];
    static char hp[PATHMAX + 1];
    unsigned char i = p->hc + d;
    if ((d < 0 && !p->hc) || i >= p->hn)
        return;
    bget(p->bank, HISTAT + i * 64, hp, PATHMAX + 1);
    navving = 1;
    if (shell_goto(w, hp))
        p->hc = i;
    else
        sayErr("Cannot open the folder:", 0);
    navving = 0;
}

/* a crumb of the toolbar's path: its first len characters */
void shell_crumb(unsigned char w, unsigned char len)
{
    static char cp[PATHMAX + 1];
    strcpy(cp, wins[w].path);
    cp[len ? len : 1] = 0;
    if (strcmp(cp, wins[w].path) && !shell_goto(w, cp))
        sayErr("Cannot open the folder:", 0);
}

/* the search field: the names that hold a text, typed into a box */
void shell_search(unsigned char w)
{
    struct win *p = &wins[w];
    unsigned char r;
    strcpy(tmp, p->find);
    nameBox.s1 = "Show the names holding:";
    nameBox.max2 = FINDLEN;
    r5 = (unsigned int)tmp;
    r = dlg(&nameBox);
    nameBox.s1 = "New name:";
    if (r != OK && r != DBGETSTRING)
        return;
    tmp[FINDLEN] = 0;
    strcpy(p->find, tmp);
    p->first = 0;
    strcpy(msg, "SHELL SEARCH ");
    strcat(msg, tmp);
    LogText(msg);
    reread(w);
}

static void up(unsigned char w)
{
    unsigned char l;
    if (atRoot(wins[w].path))
        return;
    strcpy(str, wins[w].path);
    l = strlen(str);
    while (l > 1 && str[--l] != '/')
        ;
    str[l ? l : 1] = 0;
    if (!shell_goto(w, str))
        sayErr("Cannot go up:", 0);
}

/* the folder dir shown in the front window, name in it selected (on its
   page), opened if open */
void shell_go(const char *dir, const char *name, unsigned char doOpen)
{
    unsigned char s, w = front == 0xFF ? 0 : front;
    struct win *p = &wins[w];
    found_on = 0;
    if (ChDir((void *)dir)) {
        ChDir(curDirName);
        sayErr("Cannot open the folder:", 0);
        shell_reload();
        return;
    }
    strcpy(p->path, dir);
    p->open = 1;
    p->find[0] = 0;
    shell_hist(w);
    shell_front(w);
    XCALL(bDir, dir_read, FB)(w);
    for (s = 0; s < p->n; ++s) {
        ent_get(w, p->order[s]);
        if (!strcmp(E.name, name))
            break;
    }
    if (s < p->n) {
        p->sel = s;
        p->first = s - s % XCALL(bView, view_per, RB)(w);
    }
    XCALL(bWin, win_redraw, FB)(w);
    if (s < p->n && doOpen)
        shell_open(w, p->order[s]);
}

/*---------------------------------------------------------------- the menus */

struct item { const char *text; unsigned char type; void *ptr; };
struct vmenu { unsigned char top, bottom; unsigned int left, right; unsigned char flags; struct item items[1]; };
#define VMENU(n) struct { unsigned char top, bottom; unsigned int left, right; unsigned char flags; struct item items[n]; }

static void about(void);
static void desk(void);
static void help(void);
static void openSel(void);
static void dupSel(void);
static void renSel(void);
static void delSel(void);
static void infoSel(void);
static void viewSel(void);
static void copySel(void);
static void moveSel(void);
static void putHere(void);
static void printSel(void);
static void findFiles(void);
static void setMods(void);
static void byIcon(void);
static void bySmall(void);
static void byName(void);
static void bySize(void);
static void byDate(void);
static void byType(void);
static void refresh(void);
static void goUp(void);
static void openCard(void);
static void openDocs(void);
static void newWin(void);
static void closeWin(void);
static void showTrash(void);
static void emptyTrash(void);
static void selFirst(void);
static void selNext(void);
static void selPrev(void);
static void selNone(void);
static void nextPage(void);
static void prevPage(void);
static void mode0(void);
static void mode1(void);
static void mode2(void);
static void prefs(void);
static void pinSel(void);
static void unpin(void);
static void basic(void);
static void quit(void);

#define V VERTICAL | UN_CONSTRAINED
/* (V146, Sunroom) "\x1f": a separator above the item (a group starts);
   "\t": the item's key, right-aligned (the kernel's lists, bank T) */
static VMENU(3) geosMenu = { 15, 0, 0, 0, V | 3, {
    { "About the shell", MENU_ACTION, about },
    { "Desk accessory", MENU_ACTION, desk },
    { "\x1f" "Help\tF1", MENU_ACTION, help } } };
static VMENU(12) fileMenu = { 15, 0, 0, 0, V | 12, {
    { "Open\tCtrl O", MENU_ACTION, openSel },
    { "Duplicate\tCtrl D", MENU_ACTION, dupSel },
    { "Rename", MENU_ACTION, renSel },
    { "Delete\tDel", MENU_ACTION, delSel },
    { "Get info\tCtrl I", MENU_ACTION, infoSel },
    { "View", MENU_ACTION, viewSel },
    { "\x1f" "Copy", MENU_ACTION, copySel },
    { "Move", MENU_ACTION, moveSel },
    { "Put here", MENU_ACTION, putHere },
    { "\x1f" "Print\tCtrl P", MENU_ACTION, printSel },
    { "Find\tCtrl F", MENU_ACTION, findFiles },
    { "\x1f" "Set as Mods folder", MENU_ACTION, setMods } } };
static VMENU(8) viewMenu = { 15, 0, 0, 0, V | 8, {
    { "By icon", MENU_ACTION, byIcon },
    { "By small icon", MENU_ACTION, bySmall },
    { "\x1f" "By name", MENU_ACTION, byName },
    { "By size", MENU_ACTION, bySize },
    { "By date", MENU_ACTION, byDate },
    { "By type", MENU_ACTION, byType },
    { "\x1f" "Refresh\tCtrl R", MENU_ACTION, refresh },
    { "Up a folder\tCtrl Up", MENU_ACTION, goUp } } };
static VMENU(6) diskMenu = { 15, 0, 0, 0, V | 6, {
    { "Open the card", MENU_ACTION, openCard },
    { "\x1f" "New window\tCtrl N", MENU_ACTION, newWin },
    { "Close window\tCtrl W", MENU_ACTION, closeWin },
    { "\x1f" "Trash", MENU_ACTION, showTrash },
    { "Empty trash", MENU_ACTION, emptyTrash },
    { "\x1f" "Documents", MENU_ACTION, openDocs } } };
static VMENU(4) selectMenu = { 15, 0, 0, 0, V | 4, {
    { "First\tHome", MENU_ACTION, selFirst },
    { "Next\tTab", MENU_ACTION, selNext },
    { "Previous\tShift Tab", MENU_ACTION, selPrev },
    { "\x1f" "None\tEsc", MENU_ACTION, selNone } } };
static VMENU(2) pageMenu = { 15, 0, 0, 0, V | 2, {
    { "Next page\tPgDn", MENU_ACTION, nextPage },
    { "Previous page\tPgUp", MENU_ACTION, prevPage } } };
static VMENU(8) optMenu = { 15, 0, 0, 0, V | 8, {
    { "640 x 480", MENU_ACTION, mode0 },
    { "640 x 240", MENU_ACTION, mode1 },
    { "320 x 240", MENU_ACTION, mode2 },
    { "\x1f" "Preferences...", MENU_ACTION, prefs },
    { "\x1f" "Pin to the dock", MENU_ACTION, pinSel },
    { "Unpin", MENU_ACTION, unpin },
    { "\x1f" "BASIC (keep Veranda)", MENU_ACTION, basic },
    { "Quit Veranda\tCtrl Q", MENU_ACTION, quit } } };
#define NMAIN 7
static VMENU(NMAIN) mainMenu = { 0, 14, 0, 0, HORIZONTAL | UN_CONSTRAINED | NMAIN, {
    { "Veranda", SUB_MENU, &geosMenu },
    { "File", SUB_MENU, &fileMenu },
    { "View", SUB_MENU, &viewMenu },
    { "Disk", SUB_MENU, &diskMenu },
    { "Select", SUB_MENU, &selectMenu },
    { "Page", SUB_MENU, &pageMenu },
    { "Options", SUB_MENU, &optMenu } } };

/* (V146) the menus' sizes (look3.c: overlay 12, for room) */
static void menus(void)
{
    XCALL(bMouse, look3_menus, void (*)(void *))(&mainMenu);
}

/* (V146) a key: look3.c finds its menu item (0: none), run as if chosen */
static void key(void)
{
    unsigned char k = XCALL(bMouse, look3_key, unsigned char (*)(void))();
    if (k)
        ((FV)((struct vmenu *)mainMenu.items[k >> 4 & 7].ptr)->items[k & 15].ptr)();
}

/* the menu bar (the Veranda look, DECISIONS V74: the kernel draws it
   full width, its colours, the mark, the clock), the rest */
static void redraw(void)
{
    look_off();
    UseSystemFont();
    DoMenu((void *)&mainMenu, 0);
    drawAll();
}

/*---------------------------------------------------------------- actions */

static void about(void)
{
    GotoFirstMenu();
    dlg(&aboutBox);
}

/* the folder to come back to (window 0's, its view, the mode), the desk
   file if it changed */
void shell_keep(void)
{
    static unsigned char dk[64];
    struct win *p = &wins[0];
    memset(dk, 0, sizeof dk);
    strcpy((char *)dk, p->path);
    dk[VIEWBYTE] = p->view | p->sort << 2 | deskPat << 4 | (p->open ? 0 : 0x80);
    dk[MODEBYTE] = curDirName[MODEBYTE];
    SysPrefs(DESK_SET, dk);
    if (deskDirty)
        XCALL(bDir, desk_save, FV)();   /* (back in curDirName after) */
}

void shell_desk_save(void)
{
    XCALL(bDir, desk_save, FV)();
}

/* after a desk accessory (r: GetFile's error): Preferences may have
   changed the theme or the desktop (V78: the picture read again if its
   banks were given back for it) */
static void afterDesk(unsigned char r)
{
    if (r)
        sayErr("Cannot start it:", r);
    if ((r ? 0 : look_load()) | XCALL(bWall, wall_load, unsigned char (*)(void))()
        | (r ? 0 : XCALL(bDir, desk_load, RB)(1)))      /* (V163: Preferences' Dock page) */
        redraw();
}

/* a desk accessory, chosen from a list of those in the applications'
   folder (/VERANDA/APPS: DECISIONS V71); it runs over the shell, which
   comes back as it was (RstrAppl) */
static void desk(void)
{
    unsigned char r;
    GotoFirstMenu();
    shell_keep();                     /* (before the folder changes) */
    vr_cd(VR_APPS);
    if (testing) {              /* (the gates: how many the list has) */
        strcpy(msg, "SHELL DESK ACCESSORIES ");
        num(60 - FindFTypes(buf, DESK_ACC, 60, 0), msg + 23);
        LogText(msg);
    }
    tmp[0] = 0;
    r5 = (unsigned int)tmp;
    r7L = DESK_ACC;
    r10 = 0;
    r = DoDlgBox((void *)&deskBox);
    if (r == DBGETFILES) {
        ChDir(curDirName);
        say("There are no desk accessories.");
        return;
    }
    if (r != OPEN || !tmp[0]) {
        ChDir(curDirName);
        return;
    }
    r = start(ST_DA_ROOM, 0);         /* (V168: room left for it, or the desktop's lent) */
    ChDir(curDirName);
    afterDesk(r);
}

static void setMode(unsigned char m)
{
    GotoFirstMenu();
    if (SetVideoMode(m))
        return;
    curDirName[MODEBYTE] = m + 1;
    wins[0].w = wins[1].w = 0;          /* (their default places) */
    wins[0].first = wins[1].first = 0;
    if (wins[1].open)
        deskDirty = 1;
    XCALL(bWin, win_init, FV)();
    XCALL(bWall, wall_load, unsigned char (*)(void))();     /* (640 x 240: every other row; 320: none) */
    redraw();
}

static void mode0(void) { setMode(MODE_640x480); }
static void mode1(void) { setMode(MODE_640x240); }
static void mode2(void) { setMode(MODE_320x240); }

/* (V180) Options > Preferences...: the control panel (a desk accessory in
   /VERANDA/APPS) without going through the Apps folder; it took the place
   of "Desktop pattern" (GEOS's: the desktop is chosen in Preferences now,
   a pattern kept in WALL_CFG still shows) */
static void prefs(void)
{
    unsigned char r;
    GotoFirstMenu();
    shell_keep();                       /* (before the folder changes) */
    vr_cd(VR_APPS);
    strcpy(tmp, "Preferences");
    r = start(ST_DA_ROOM, 0);
    ChDir(curDirName);
    afterDesk(r);
}

/* BASIC with Veranda kept in memory: SYS 35328 or RBOOT comes back to
   this folder (DECISIONS V64); quit: Veranda gone. While a test script
   plays, BASIC is given the test's command (gate basic: tests/basic_gate.py):
   PRINT 6*7, then the BASIC program Gn (n: this start's part) */
static char gateCmd[] = "?6*7\x0d\x5eG0";

static char *testCmd(void)
{
    if (!part)
        return 0;
    gateCmd[7] = '0' + tstep;
    return gateCmd;
}

static void basic(void)
{
    char *c = testCmd();
    shell_keep();                     /* (the folder to come back to) */
    r1 = TOBASIC_KEEP;
    ToBASIC(c);
}

static void quit(void)
{
    char *c = testCmd();
    r1 = 0;
    ToBASIC(c);
}

static void refresh(void)
{
    GotoFirstMenu();
    found_on = 0;
    shell_reload();
}

static unsigned char need(void)
{
    if (front == 0xFF) {
        warn("Open a window first.");
        return 0;
    }
    return 1;
}

static void goUp(void)
{
    GotoFirstMenu();
    if (need())
        up(front);
}

static void page(signed char d)
{
    GotoFirstMenu();
    if (need())
        XCALL(bView, view_page, FBB)(front, d);
}

static void nextPage(void) { page(1); }
static void prevPage(void) { page(-1); }

static void setView_(unsigned char v, unsigned char s)
{
    struct win *p;
    if (!need())
        return;
    p = &wins[front];
    p->view = v;
    p->sort = s;
    p->first = 0;
    p->sel = 0xFF;
    if (front)
        deskDirty = 1;
    sort_win(front);
    found_on = 0;
    XCALL(bWin, win_view, FB)(front);           /* (the toolbar's toggle too) */
    if (v == V_LIST)
        XCALL(bDir, view_log, FB)(front);
}

static void setView(unsigned char v, unsigned char s)
{
    GotoFirstMenu();
    setView_(v, s);
}

/* the toolbar's icons and list toggle */
void shell_setview(unsigned char v)
{
    if (front != 0xFF && wins[front].view != v)
        setView_(v, v == V_LIST ? wins[front].sort : S_NAME);
}

static void byIcon(void) { setView(V_ICON, S_NAME); }
static void bySmall(void) { setView(V_SMALL, S_NAME); }
static void byName(void) { setView(V_LIST, S_NAME); }
static void bySize(void) { setView(V_LIST, S_SIZE); }
static void byDate(void) { setView(V_LIST, S_DATE); }
static void byType(void) { setView(V_LIST, S_TYPE); }

static void selMove(unsigned char how)
{
    struct win *p;
    unsigned char s;
    GotoFirstMenu();
    if (!need())
        return;
    p = &wins[front];
    s = p->sel;
    if (how == 0)
        s = p->n ? 0 : 0xFF;
    else if (how == 1)
        s = s == 0xFF ? 0 : s + 1 < p->n ? s + 1 : s;
    else if (how == 2)
        s = s == 0xFF || !s ? 0 : s - 1;
    else
        s = 0xFF;
    if (s != 0xFF && s >= p->n)
        s = 0xFF;
    XCALL(bView, view_select, FBB)(front, s);
}

static void selFirst(void) { selMove(0); }
static void selNext(void) { selMove(1); }
static void selPrev(void) { selMove(2); }
static void selNone(void) { selMove(3); }

/* a window opened on path p: a closed one, else the one behind */
static void openOn(const char *p)
{
    unsigned char w = !wins[0].open ? 0 : !wins[1].open ? 1 : front ^ 1;
    if (ChDir((void *)p)) {
        if (front != 0xFF)
            ChDir(wins[front].path);
        sayErr("Cannot open the folder:", 0);
        return;
    }
    strcpy(wins[w].path, p);
    if (w)
        deskDirty = 1;
    wins[w].first = 0;
    wins[w].sel = 0xFF;
    wins[w].find[0] = 0;
    shell_hist(w);
    XCALL(bWin, win_behind, FB)(front);
    shell_front(w);
    XCALL(bOps, win_open, FB)(w);
}

static void openCard(void)
{
    GotoFirstMenu();
    openOn("/");
}

/* disk/documents: a window on /DOCUMENTS (V71) */
static void openDocs(void)
{
    GotoFirstMenu();
    openOn(vr_cd(VR_DOCS));
}

static void newWin(void)
{
    GotoFirstMenu();
    openOn(front == 0xFF ? "/" : wins[front].path);
}

static void closeWin(void)
{
    GotoFirstMenu();
    if (need())
        XCALL(bOps, win_close, FB)(front);
}

/* the desk icons' actions */
void shell_trash(void)
{
    XCALL(bFiles, trash_path, FV)();
    ChDir("/");
    MkDir(trash + 1);                   /* (there already: an error, ignored) */
    openOn(trash);
}

/* file/set as Mods folder: the front window's folder (V84) */
static void setMods(void)
{
    GotoFirstMenu();
    XCALL(bDir, mods_set, FV)();
}

static void showTrash(void)
{
    GotoFirstMenu();
    shell_trash();
}

static void emptyTrash(void)
{
    GotoFirstMenu();
    XCALL(bFiles, files_empty_trash, FV)();
}

/*---------------------------------------------------------------- documents */

static char ext[4];

/* the extension of n into ext, upper case, space padded; 0: none */
static unsigned char extOf(const char *n)
{
    const char *d = strrchr(n, '.');
    unsigned char i;

    if (!d || !d[1] || strlen(d + 1) > 4)
        return 0;
    memset(ext, ' ', 4);
    for (i = 0; d[1 + i]; ++i)
        ext[i] = (d[1 + i] >= 'a' && d[1 + i] <= 'z') ? d[1 + i] - 32 : d[1 + i];
    return 1;
}

/* does an info block's documents (16 bytes) name ext? */
static unsigned char opensExt(const unsigned char *d)
{
    unsigned char i;

    for (i = 0; i < 16; i += 4)
        if (d[i] && memcmp(d + i, ext, 4) == 0)
            return 1;
    return 0;
}

/* (V151) a program (not a desk accessory, which comes back over the shell)
   starting: the desktop picture's 4 banks given back first, as V78 does
   on NO_BANKS (the shell starts again after the program and makes it
   again: the plain desktop in 51 ms, a picture read in ~10 ms); its small
   icons' library took a bank, and VeraBASIC's Make application at 512 KB
   needs it (gate vb_app) */
static void lend(void)
{
    if (wallMode == W_PICTURE)
        XCALL(bWall, wall_drop, FV)();
}

/* start the program tmp (a document: ST_LD_DATA and its name), the
   shell's path kept first (the program may change curDirName) */
static unsigned char start(unsigned char opts, const char *doc)
{
    unsigned char r;
    shell_keep();
    if (opts & ST_LD_DATA)              /* (a program, not a desk accessory: lend) */
        lend();
    r = GetFile(tmp, opts, 0, (void *)doc, 0);
    if (r == NO_BANKS && XCALL(bWall, wall_drop, unsigned char (*)(void))())
        r = GetFile(tmp, opts, 0, (void *)doc, 0);      /* (the picture's banks lent: V78) */
    return r;
}

/* the application tmp, in folder dir, started without a document: one
   started from the top folder or the system's folders works in /DOCUMENTS
   (curDirName, the working folder applications keep: their first Open
   and Save go there; the shell's own folder is kept apart, V63), one
   from a folder of the user's in that folder (DECISIONS V71) */
static unsigned char startApp(const char *dir)
{
    static char ad[PATHMAX + 1];
    unsigned char r;
    const char *d;
    strcpy(ad, dir);
    XCALL(bWin, dock_note, FP)(ad);
    shell_keep();
    if ((atRoot(ad) || vr_insys(ad)) && ChDir(VR_SYSDIR) == 0) {
        d = vr_cd(VR_DOCS);
        if (d[1])
            strcpy((char *)curDirName, d);
    }
    ChDir(ad);
    lend();
    r = GetFile(tmp, 0, 0, 0, 0);
    strcpy((char *)curDirName, wins[front == 0xFF ? 0 : front].path);   /* (it did not start) */
    ChDir(curDirName);
    return r;
}

static unsigned char selFile(void);

/* the application tmp in folder dir, the document str's */
void startDoc(const char *dir)
{
    unsigned char r;

    mouseSource = 0;            /* (the player is overwritten by the load) */
    XCALL(bWin, dock_note, FP)(dir);
    r = start(ST_LD_DATA, str);  /* r3: the document */
    ChDir(curDirName);          /* (it did not start: back to the folder) */
    sayErr("Cannot start it:", r);
}

/* in folder dir: an application whose documents name the file's extension
   (the name in tmp, the folder made current); 0 if none (back in
   curDirName) */
static unsigned char appIn(const char *dir)
{
    unsigned char i, n;

    if (ChDir((void *)dir))
        return 0;
    n = 60 - FindFTypes(buf, APPLICATION, 60, 0);       /* names, 17 bytes each */
    for (i = 0; i < n; ++i) {
        if (FindFile(buf + 17 * i) == 0 && GetFHdrInfo((void *)dirEntryBuf) == 0
            && opensExt(fileHeader + 144)) {
            strcpy(tmp, (char *)buf + 17 * i);
            return 1;
        }
    }
    ChDir(curDirName);
    return 0;
}

/* where applications are looked for after the folder shown: the
   applications' folder, the system folder (a card not set up), the top
   folder (DECISIONS V71) */
const char *const homes[3] = { VR_APPSDIR, VR_SYSDIR, "/" };

/* a plain file (E, of window w): the application that opens it, here, in
   /VERANDA/APPS, /VERANDA or the top folder */
static void openDoc(unsigned char w)
{
    unsigned char i;
    struct win *p = &wins[w];

    shell_keep();                     /* (before the folders change) */
    /* (V197) prg.c: an X16 program (.PRG) run by BASIC; no extension
       (the warning there: main RAM's room) */
    if (XCALL(bPrg, prg_run, RB)(w) || !extOf(E.name))
        return;
    strcpy(str, E.name);                /* (a long name: dataLongName, V82) */
    for (i = 0; i < p->n; ++i) {
        ent_get2(w, i);
        if (E2.geos == APPLICATION && E2.icon >= I_OWN && opensExt(icon_get(w, E2.icon - I_OWN, 1))) {
            shown(&E2, tmp);
            startDoc((char *)curDirName);
            return;
        }
    }
    for (i = 0; i < 3; ++i)
        if (strcmp((char *)curDirName, homes[i]) && appIn(homes[i])) {
            startDoc(homes[i]);
            return;
        }
    warn("No application opens this file.");
}

/* file/view: the selected file with View (here, in /VERANDA/APPS,
   /VERANDA or the top folder) as its document */
static void viewStr(void);
static void viewSel(void)
{
    GotoFirstMenu();
    if (selFile() == 0xFF)
        return;
    strcpy(str, E.name);
    shell_keep();
    viewStr();
}

/* View with the document str (in curDirName): here, in /VERANDA/APPS,
   /VERANDA or the top folder; returns only when it did not start */
static void viewStr(void)
{
    unsigned char i;
    strcpy(tmp, "View");
    for (i = 0; i < 4; ++i)
        if ((i == 0 || ChDir((void *)homes[i - 1]) == 0) && FindFile(tmp) == 0) {
            startDoc(i ? homes[i - 1] : (char *)curDirName);
            return;
        }
    ChDir(curDirName);
    warn("View is not with the applications.");
}

/* veranda/help: the manual's first page (docs/manual, tools/mkhelp.py:
   plain text in /VERANDA/HELP, DECISIONS V134) in View; Esc there lists
   the manual's other parts */
static void help(void)
{
    GotoFirstMenu();
    shell_keep();
    strcpy(str, "Veranda manual.txt");
    strcpy((char *)curDirName, VR_HELPDIR);
    viewStr();
    strcpy((char *)curDirName, wins[front == 0xFF ? 0 : front].path);   /* (it did not start) */
    ChDir(curDirName);
}

/* a double click on entry idx of window w (it is in front) */
void shell_open(unsigned char w, unsigned char idx)
{
    unsigned char r, l;

    ent_get(w, idx);
    if (E.type == 'U') {
        up(w);
        return;
    }
    if (E.type == 'D') {
        strcpy(str, wins[w].path);
        l = strlen(str);
        if (l + strlen(E.name) + 2 > MODEBYTE - 1) {
            warn("The path is too long.");
            return;
        }
        if (l > 1)
            str[l++] = '/';
        strcpy(str + l, E.name);
        wins[w].first = 0;
        if (!shell_goto(w, str))
            sayErr("Cannot open the folder:", 0);
        return;
    }
    if (E.geos == DESK_ACC) {           /* over the shell, which comes back */
        shown(&E, tmp);
        afterDesk(start(ST_DA_ROOM, 0));
        return;
    }
    if (E.geos != APPLICATION) {
        if (E.geos == APPL_DATA)        /* a document: its parent application (V87) */
            XCALL(bDir, dir_open_data, FV)();
        else if (E.geos)
            warn("This is not an application.");
        else
            openDoc(w);
        return;
    }
    shown(&E, tmp);
    mouseSource = 0;            /* (the player is overwritten by the load) */
    r = startApp((char *)curDirName);
    sayErr("Cannot start it:", r);
}

/* a pinned application started from its folder */
void shell_pin_start(unsigned char p)
{
    unsigned char r;
    shell_keep();
    pin_get(p);
    if (ChDir(P.dir)) {
        ChDir(curDirName);
        warn("Its folder is gone.");
        return;
    }
    strcpy(tmp, P.name);
    if (shell_is_cvt(tmp))
        tmp[strlen(tmp) - 4] = 0;
    mouseSource = 0;
    r = startApp(P.dir);
    sayErr("Cannot start it:", r);
}

/* the selection (an entry index, E it), or $FF */
static unsigned char selIdx(void)
{
    struct win *p;
    unsigned char i;
    if (found_on) {
        warn("Close the find results first.");
        return 0xFF;
    }
    if (front == 0xFF || wins[front].sel == 0xFF) {
        warn("Select a file first.");
        return 0xFF;
    }
    p = &wins[front];
    i = p->order[p->sel];
    ent_get(front, i);
    return i;
}

static unsigned char selFile(void)
{
    unsigned char i = selIdx();
    if (i != 0xFF && E.type != 'F') {
        warn("Select a file first.");
        return 0xFF;
    }
    return i;
}

static void openSel(void)
{
    unsigned char i;
    GotoFirstMenu();
    if ((i = selIdx()) != 0xFF)
        shell_open(front, i);
}

/* str = "Copy of " the name (a GEOS name: at most 16 characters) */
static void copyName(void)
{
    unsigned char cvt = shell_is_cvt(E.name), l;
    strcpy(str, "Copy of ");
    shown(&E, str + 8);
    l = strlen(str);
    if (cvt) {
        if (l > 16)
            l = 16;
        strcpy(str + l, ".cvt");
    } else if (l > NAMELEN) {
        str[NAMELEN] = 0;
    }
}

static unsigned char exists(const char *n)
{
    unsigned char h = FOpen((void *)n, 'r');
    if (h < 2)
        return 0;
    FClose(h);
    return 1;
}

static void dupSel(void)
{
    unsigned char h1, h2, e;
    unsigned int n;

    GotoFirstMenu();
    if (selFile() == 0xFF)
        return;
    copyName();
    play_busy = 1;
    if (exists(str)) {
        play_busy = 0;
        warn("The copy's name is taken.");
        return;
    }
    e = 0;
    h1 = FOpen(E.name, 'r');
    if (h1 < 2) {
        play_busy = 0;
        sayErr("Cannot read it:", 0);
        return;
    }
    h2 = FOpen(str, 'w');
    if (h2 < 2) {
        FClose(h1);
        play_busy = 0;
        sayErr("Cannot write the copy:", 0);
        return;
    }
    do {
        n = FRead(h1, buf, sizeof buf);
        if (n && (e = FWrite(h2, buf, n)) != 0)
            break;
    } while (n == sizeof buf);
    FClose(h2);
    FClose(h1);
    play_busy = 0;
    if (e)
        sayErr("Writing failed:", e);
    shell_reload();
}

static void renSel(void)
{
    unsigned char r, e, cvt, l;

    GotoFirstMenu();
    if (selFile() == 0xFF)
        return;
    cvt = shell_is_cvt(E.name);
    shown(&E, tmp);
    nameBox.max2 = cvt ? 16 : 24;
    tmp[nameBox.max2] = 0;
    r5 = (unsigned int)tmp;
    r = dlg(&nameBox);
    if ((r != OK && r != DBGETSTRING) || !tmp[0])
        return;
    l = strlen(tmp);
    if (cvt)
        strcpy(tmp + l, ".cvt");
    if (strcmp(tmp, E.name) == 0)
        return;
    play_busy = 1;
    e = FRename(E.name, tmp);
    play_busy = 0;
    if (e)
        sayErr("Cannot rename it:", e);
    shell_reload();
}

/* to the trash (or, in the trash, for good): files.c */
static void delSel(void)
{
    GotoFirstMenu();
    if (selIdx() == 0xFF || E.type == 'U')
        return;
    strcpy(str, E.name);
    XCALL(bFiles, files_delete, void (*)(const char *, char, unsigned char))(str, E.type, 1);
}

static void infoSel(void)
{
    GotoFirstMenu();
    if (selIdx() == 0xFF)
        return;
    strcpy(str, E.name);
    XCALL(bFiles, files_info, void (*)(const char *, char))(str, E.type);
}

static void pick(unsigned char move)
{
    GotoFirstMenu();
    if (selIdx() == 0xFF || E.type == 'U')
        return;
    strcpy(str, E.name);
    XCALL(bFiles, files_pick, void (*)(const char *, char, unsigned char))(str, E.type, move);
}

static void copySel(void) { pick(0); }
static void moveSel(void) { pick(1); }

static void putHere(void)
{
    GotoFirstMenu();
    if (!need())
        return;
    found_on = 0;
    XCALL(bFiles, files_put, FV)();
}

static void printSel(void)
{
    GotoFirstMenu();
    if (selFile() == 0xFF)
        return;
    strcpy(str, E.name);
    XCALL(bPrint, print_drop, void (*)(const char *))(str);
}

static void findFiles(void)
{
    GotoFirstMenu();
    if (need())
        XCALL(bFiles, files_find, FV)();
}

/* options/pin: the selected application on the desktop */
static void pinSel(void)
{
    GotoFirstMenu();
    if (selFile() == 0xFF)
        return;
    if (E.geos != APPLICATION) {
        warn("Only applications are pinned.");
        return;
    }
    XCALL(bBars, pin_add, FB)(0xFF);
    drawAll();
}

static void unpin(void)
{
    GotoFirstMenu();
    if (!npins) {
        say("Nothing is pinned.");
        return;
    }
    XCALL(bMouse, win_unpin, FV)();
}

/*---------------------------------------------------------------- the mouse */

static void press(void)
{
    XCALL(bMouse, win_press, FV)();
}

static void idle(void)
{
    if (play_shot)              /* (the gates: the screen as a BMP file, DECISIONS V101) */
        XCALL(bWall, wall_shot, FV)();
    if (ic3Want)                /* (V161) the colour icons: tiles ran out, or the cache
                                   started again (bars.c) */
        XCALL(bBars, ic3_idle, FV)();
    else if (ic3Next)           /* (V165) the next page's icons, while nothing happens */
        XCALL(bIc2, ic3_ahead, FV)();
    XCALL(bMouse, win_idle, FV)();
}

/*---------------------------------------------------------------- the test hook */

/* SHELL.TST: the script; SHELL.STP: the start count (part n at start n):
   dir.c's test_hook (overlay 3: V101 needed the resident part's room) */

static unsigned char ovl(unsigned char n)
{
    LoadOverlay(n, 0);
    return r1L;
}

/* the first start since Veranda started, on a card in the layout before
   V71 (a /VERANDA without .SYSTEM/LAYOUT.LOG): Veranda Setup (in
   /VERANDA) moves the files into the new folders, once, and quits to the
   shell (DECISIONS V71); no Setup there, nothing happens */
static void setup(void)
{
    unsigned char h;
    if (ChDir(VR_SYSDIR))
        return;
    h = FOpen(VR_DATAPATH VR_SETUP_LOG, 'r');
    if (h >= 2 && h <= 9) {
        FClose(h);
        if (dosStatus < 20)
            return;
    }
    ChDir(VR_SYSDIR);
    if (FindFile(VR_SETUP) == 0)
        GetFile(VR_SETUP, 0, 0, 0, 0);
}

int main(void)
{
    unsigned char m, vb, w;

    /* GEOS files by their long FAT names: programs and documents of up
       to LONG_MAX characters (DECISIONS V82) */
    longNames = LONG_NAMES;
    /* the path and the mode the shell kept (start), else /DOCUMENTS
       (made when missing: DECISIONS V71), or the root without /VERANDA */
    SysPrefs(DESK_GET, (void *)curDirName);
    if (curDirName[0] != '/')
        setup();
    vb = curDirName[VIEWBYTE];
    curDirName[VIEWBYTE] = 0;
    if (curDirName[0] != '/' || ChDir(curDirName)) {
        strcpy((char *)curDirName, vr_cd(VR_DOCS));
        vb = (vb & 0x70) | V_LIST;      /* (V176: no saved choice, the list) */
        deskFresh = 1;
    }
    m = curDirName[MODEBYTE];
    if (m && m - 1 != graphMode)
        SetVideoMode(m - 1);
    LogText("\nSHELL STARTED");
    SysPrefs(PREFS_GET, buf);   /* the settings' Polish keyboard: the ROM's PL-PL (V142; */
    if (buf[6] & PREFS_POLISH)  /* vr_kbd's work, in buf: main RAM is full) */
        vr_keymap("PL-PL");
    bWin = ovl(1);
    bView = ovl(2);
    bDir = ovl(3);
    bFiles = ovl(4);
    bPrint = ovl(5);
    bMouse = ovl(6);
    bOps = ovl(7);
    bChrome = ovl(8);
    bBars = ovl(9);
    bTile = ovl(10);
    bWall = ovl(11);
    bLook3 = ovl(12);
    bIc2 = ovl(16);             /* (V165: records 13-15 are look3.c's libraries) */
    bPrg = ovl(17);             /* (V197) */
    bDock = bTile;              /* (the dock is in the tiles' overlay: V83) */
    appBank = bWin;
    RAMBANK = bWin;
    w = BankAlloc(5);
    bIcons = w;
    bDesk = w + 1;
    wins[0].bank = w + 2;
    wins[1].bank = w + 3;
    bTiles = w + 4;
    strcpy(wins[0].path, (char *)curDirName);
    wins[0].open = !(vb & 0x80);
    wins[0].view = vb & 3;
    wins[0].sort = vb >> 2 & 3;
    if (wins[0].view >= VIEWS)
        wins[0].view = V_ICON;
    deskPat = vb >> 4 & 7;
    XCALL(bFiles, files_init, FV)();
    XCALL(bDir, test_hook, FV)();
    menus();
    XCALL(bDir, desk_load, RB)(0);
    XCALL(bWin, win_init, FV)();
    look_load();                        /* (before the folders: the colour icons are */
    XCALL(bWall, wall_load, unsigned char (*)(void))();     /* read with them, V133) */
    XCALL(bDir, pins_icons, FV)();      /* (after: the dock's colour icons too, V152) */
    for (w = 0; w < NWIN; ++w)
        if (wins[w].open) {
            wins[w].sel = 0xFF;
            XCALL(bDir, dir_read, FB)(w);
            if (front == 0xFF || w == 0)
                front = w;
        }
    shell_front(front);
    for (w = 0; w < NWIN; ++w)
        if (wins[w].open)
            shell_hist(w);
    if (testing)
        XCALL(bPrg, prg_log, FV)();     /* (the windows kept: V198 moved it there) */
    redraw();
    XCALL(bWin, dock_init, FV)();
    otherPressVec = VR_FN(press);
    appMain = VR_FN(idle);
    keyVector = VR_FN(key);
    if (part)
        play_start(part);
    if (XCALL(bPrg, prg_req, RB)(0)) {  /* (V198: a program's START.REQ) */
        mouseSource = 0;
        sayErr("Cannot start it:", startApp(str));
    }
    return 0;
}
