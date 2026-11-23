/* Veranda shell: reading a folder, the status line, the desk file
   (overlay 3; DECISIONS V70).

   A folder is read with CMDR-DOS's long listing, "$=L" (DirOpen "=L":
   the kernel gives its lines raw, DECISIONS V70), on the SD card and on
   the emulator's host folder alike:
       header   <rvs>"VOLUME NAME     " FAT32       (host: "<folder>" HOST)
       a line   n KB  "NAME"   PRG  2026-11-16 10:42:07 20 0000ABCD
       footer   n KB FREE.                          (host: 65535 BLOCKS FREE.)
   (n: the size in KB; the type PRG or DIR, then '<' if write protected;
   the date and time of the last change, when the file has one; the FAT
   attributes and the size in bytes, in hex). So each entry has its size
   and date, and the footer gives the free space: the status line's
   numbers come from that one listing. The header's volume name is the
   card's name. GEOS files' info blocks (icons, types) are read after the
   listing (CMDR-DOS stops a listing when a file is opened, V16).

   The desk file, SHELL.DSK in the system's data folder (/VERANDA/.SYSTEM,
   DECISIONS V71; else the top folder): the windows' places for a video mode, the second window
   (open, its view and folder) and the pins (folder, name); written only
   when one of them changes (deskDirty), when a program is about to start
   or a pin is added or removed. Window 0's folder and view are kept in
   the kernel (DESK_SET, main.c).

   The Mods place's folder (V84): MODS.CFG next to it, one line, the
   folder's path (docs/APPFORMAT.md, "MODS.CFG"), written by File > Set as
   Mods folder and read when the shell starts; none: /MODS. A file of its
   own rather than more of the desk file: shells before V84 read the desk
   file as before, and other programs (the MOD Player) can read it. */
#include <veranda.h>
#include <string.h>
#include "shell.h"
#include "tiles.h"
#pragma code-name ("OVERLAY3")
static unsigned char iconDef;    /* (V176) the gates (test_hook): the icons when nothing chose the list (resident BSS: 0) */

static unsigned char de[128];

static unsigned char hex(unsigned char c)
{
    return c <= '9' ? c - '0' : (c & 0x0F) + 9;
}

static unsigned char dec2(const char *p)
{
    return (p[0] - '0') * 10 + p[1] - '0';
}

static unsigned char isDigit(char c)
{
    return c >= '0' && c <= '9';
}

/* the footer's free space: n KB, MB, GB or BLOCKS */
static void freeSpace(unsigned int n, const char *t)
{
    while (*t == ' ')
        ++t;
    cardFree = (unsigned long)n << (*t == 'K' ? 10 : *t == 'M' ? 20 : *t == 'G' ? 30 : 8);
    if (*t == 'G' && n > 3)
        cardFree = 0xFFFFFFFFUL;
}

/* the header: the card's name */
static void header(const char *t)
{
    const char *q = strchr(t, '"');
    unsigned char l = 0;
    if (!q)
        return;
    if (strstr(t, "HOST")) {
        strcpy(cardName, "Host folder");
        return;
    }
    for (++q; *q && *q != '"' && l < sizeof cardName - 1; ++q)
        cardName[l++] = *q;
    while (l && cardName[l - 1] == ' ')
        --l;
    cardName[l] = 0;
}

/* a line into E; 0 if it is not an entry */
static unsigned char line(char *t)
{
    char *q = strchr(t, '"'), *n;
    unsigned char l, i;
    if (!q) {
        freeSpace(de[1] | de[2] << 8, t);
        return 0;
    }
    n = ++q;
    q = strchr(q, '"');
    if (!q)
        return 0;
    *q++ = 0;
    l = strlen(n);
    if (!l || l > NAMELEN || n[0] == '.')
        return 0;                       /* (., .. and hidden names: .SYSTEM) */
    memset(&E, 0, sizeof E);
    strcpy(E.name, n);
    while (*q == ' ')
        ++q;
    E.type = q[0] == 'D' && q[1] == 'I' && q[2] == 'R' ? 'D' : 'F';
    E.icon = E.type == 'D' ? I_FOLDER : I_DOC;
    if (*q)
        q += 3;
    while (*q == ' ' || *q == '<')
        ++q;
    /* 2026-11-16 10:42:07 */
    if (isDigit(q[0]) && q[4] == '-' && q[7] == '-' && q[13] == ':') {
        E.date[0] = (unsigned char)((q[0] - '0') * 1000u + dec2(q + 1) * 10u + (q[3] - '0') - 1900u);
        E.date[1] = dec2(q + 5);
        E.date[2] = dec2(q + 8);
        E.date[3] = dec2(q + 11);
        E.date[4] = dec2(q + 14);
        q += 19;
        while (*q == ' ')
            ++q;
    }
    /* the attributes (2 hex digits), the size (8); without them (a file
       with no date: R49 leaves both out) the size in KB, as listed */
    if (q[0] && q[1] && q[2] == ' ') {
        q += 3;
        for (i = 0; i < 8 && q[i] > ' '; ++i)
            E.size = E.size << 4 | hex(q[i]);
    } else
        E.size = (unsigned long)(de[1] | de[2] << 8) << (t[0] == 'M' ? 20 : 10);
    if (E.type == 'D')
        E.size = 0;                     /* (a folder: by name among the folders) */
    return 1;
}

static unsigned char lower(unsigned char c)
{
    return c >= 'A' && c <= 'Z' ? c + 32 : c;
}

/* does name n hold f (case ignored)? */
static unsigned char holds(const char *n, const char *f)
{
    unsigned char i;
    for (; *n; ++n) {
        for (i = 0; f[i] && lower(n[i]) == lower(f[i]); ++i)
            ;
        if (!f[i])
            return 1;
    }
    return 0;
}

/* the tile of the GEOS file name (its info block in fileHeader; DECISIONS
   V77): a Veranda application's own (its file's tile block read to
   offset off of bank b: TL_OWN, the caller adds the slot), the shell's
   for its class, else its icon on a chrome tile */
static unsigned char tileFor(const char *name, unsigned char b, unsigned int off)
{
    unsigned char h, t;
    if (b && !memcmp(fileHeader + 137, "VRND", 4) && (fileHeader[143] & 2)) {
        h = FOpen((void *)name, 'r');
        if (h >= 2) {
            t = FRead(h, buf, 225) == 225;
            FClose(h);
            if (t) {
                bput(b, off, buf + 96, TILELEN);
                return TL_OWN;
            }
        }
    }
    t = XCALL(bTile, tile_class, unsigned char (*)(const unsigned char *))(fileHeader + 77);
    return t ? t : TL_ICON;
}

/* window w's folder (its path) read: entries, icons, order, numbers;
   (V165) w + $80 (wops.c's win_open: a folder shown): sorted by the
   listing (not by kind) only the page shown first, dir_rest the others
   after it is drawn */
void dir_read(unsigned char w)
{
    struct win *p;
    unsigned char n = 0, first = 1, lazy = w & 0x80;
    w &= 0x7F;
    p = &wins[w];
    if (p->sort == S_TYPE)              /* (the kinds are the info blocks') */
        lazy = 0;
    if (lazy)                           /* (the gates' times: look3b.c) */
        XCALL(bIc2, ic3_clock, FB)(0);

    play_busy = 1;
    p->nfiles = 0;
    p->used = 0;
    p->sel = 0xFF;
    if (ChDir(p->path) == 0) {
        if (p->path[1]) {
            memset(&E, 0, sizeof E);
            E.type = 'U';
            E.icon = I_UP;
            strcpy(E.name, "..");
            ent_put(w, n++);
        }
        /* the whole listing first (DECISIONS V16), then the info blocks */
        if (DirOpen("=L") == 0) {
#ifdef RAWLOG
#endif
            de[125] = 0;
            while (DirNext(de) == 0) {
#ifdef RAWLOG
                LogText(de + 3);
#endif
                if (first) {
                    first = 0;
                    header((char *)de + 3);
                    continue;
                }
                if (!line((char *)de + 3) || n >= MAXE || (p->find[0] && !holds(E.name, p->find)))
                    continue;
                ent_put(w, n++);
                ++p->nfiles;
                if (E.type == 'F')
                    p->used += E.size;
            }
        }
        p->n = n;
        if (p->first >= n)
            p->first = 0;
        if (lazy)
            sort_win(w);
        /* (V165) the info blocks (look3b.c: each file opened once), with
           lazy those of the page shown first (dir_rest the others) */
        XCALL(bIc2, dir_infos, FBB)(w, lazy);
    }
    p->n = n;
    if (p->first >= n)
        p->first = 0;
    if (!lazy)
        sort_win(w);
    if (front != 0xFF)
        ChDir(wins[front].path);
    play_busy = 0;
    if (testing) {
        strcpy(msg, "SHELL STATUS ");
        num(w, msg + 13);
        strcat(msg, " ");
        strcat(msg, p->path);
        strcat(msg, ": ");
        dir_status(w, msg + strlen(msg));
        LogText(msg);
    }
}

/* "31 files, 0 selected, 398 Kbytes used, 392 Kbytes free" */
void dir_status(unsigned char w, char *out)
{
    struct win *p = &wins[w];
    num(p->nfiles, out);
    strcat(out, p->nfiles == 1 ? " file, " : " files, ");
    out += strlen(out);
    *out++ = p->sel != 0xFF && !(p->sel == 0 && p->path[1]) ? '1' : '0';
    strcpy(out, " selected, ");
    num((p->used + 1023) >> 10, out + 11);
    strcat(out, " Kbytes used, ");
    num(cardFree >> 10, out + strlen(out));
    strcat(out, " Kbytes free");
}

/*---------------------------------------------------------------- the desk file */

#define MAGIC0 'V'
#define HDR (16 + PATHMAX + 2)  /* the windows' part; its last byte the pins' number, the pins after it */
#define PSZ (sizeof(struct pin))
#define PINNAME1 22             /* version 1 (before V82): pins' names of 21 characters */
static const char deskName[] = "SHELL.DSK";
static const char modsName[] = "MODS.CFG";

/* the system's data folder: /VERANDA/.SYSTEM, else the top folder */
static void sysDir(void)
{
    vr_cd(VR_DATA);
}

/* the desk file read (pinsOnly: its pins alone, after a desk accessory:
   Preferences' Dock page, V163); 1 if the pins changed. Versions 1-3
   hold four pins (names of 22 bytes in version 1), version 4 (V163)
   npins, up to MAXPINS; none ever saved (no file, or one before version
   4 with none): the default pins (pins.c) */
unsigned char desk_load(unsigned char pinsOnly)
{
    unsigned char h, i, v = 0, n, ch = 0;
    unsigned char *b = buf, *q = buf + 128;
    unsigned int len;
    sysDir();
    if (!pinsOnly) {
        h = FOpen((void *)modsName, 'r');   /* the Mods place's folder (V84) */
        if (h >= 2) {
            n = FRead(h, buf, PATHMAX + 2);
            FClose(h);
            for (i = 0; i < n && b[i] != '\n' && b[i] != '\r' && b[i]; ++i)
                ;
            if (b[0] == '/' && i <= PATHMAX) {
                memcpy(modsDir, buf, i);
                modsDir[i] = 0;
            }
        }
    }
    h = FOpen((void *)deskName, 'r');
    if (h >= 2) {
        if (FRead(h, buf, HDR) == HDR && b[0] == MAGIC0 && b[1] == 'S' && b[2] == 'D' && b[3] >= 1 && b[3] <= 4)
            v = b[3];
        if (v && !pinsOnly) {
            if (b[4] == graphMode + 1) {
                wins[0].x = b[5];
                wins[0].w = b[6];
                wins[0].y = b[7] << 3;
                wins[0].h = b[8] << 3;
                wins[1].x = b[9];
                wins[1].w = b[10];
                wins[1].y = b[11] << 3;
                wins[1].h = b[12] << 3;
            }
            wins[1].open = b[13] & 1;
            wins[1].view = b[14] & 3;
            wins[1].sort = b[14] >> 2 & 3;
            if (wins[1].view >= VIEWS)
                wins[1].view = V_ICON;
            memcpy(wins[1].path, b + 16, PATHMAX + 1);
            wins[1].path[PATHMAX] = 0;
            if (wins[1].path[0] != '/' || ChDir(wins[1].path))
                strcpy(wins[1].path, "/");
            dockMin = v >= 3 ? b[15] & 3 : 0;   /* (V83: windows in the dock) */
        }
        n = v ? b[HDR - 1] : 0;
        if (n > (v < 4 ? 4 : MAXPINS))
            n = 0;
        len = v == 1 ? PINDIR + PINNAME1 : PSZ;
        for (i = 0; i < n; ++i) {
            memset(q, 0, PSZ);
            if (FRead(h, q, len) != len)
                break;
            q[PINDIR - 1] = 0;
            q[len - 1] = 0;
            bget(bDesk, PIN_AT + i * PSZ, buf + 384, PSZ);
            if (i >= npins || memcmp(q, buf + 384, PSZ)) {
                ch = 1;
                bput(bDesk, PIN_AT + i * PSZ, q, PSZ);
            }
        }
        FClose(h);
        if (v) {
            if (i != npins)
                ch = 1;
            npins = i;
        }
    }
    if (!pinsOnly) {
        if (!wins[1].path[0])
            strcpy(wins[1].path, "/");
        if (!v)                         /* (V176: no desk file, the list; the gates: test_hook) */
            wins[1].view = iconDef ? V_ICON : V_LIST;
        if (v < 4 && !npins)            /* (V163) nothing pinned ever: the defaults */
            XCALL(bDir, pins_default, FV)();
    } else if (ch)
        pins_icons();
    ChDir(curDirName);
    return ch;
}

void desk_save(void)
{
    unsigned char h, e = 1, i;
    unsigned char *b = buf;
    memset(buf, 0, HDR);
    b[0] = MAGIC0;
    b[1] = 'S';
    b[2] = 'D';
    b[3] = 4;                           /* (V82: pins' names of 67 characters; V83:
                                           byte 15 the windows in the dock; V163:
                                           npins pins, up to MAXPINS) */
    b[15] = dockMin;
    b[4] = graphMode + 1;
    b[5] = wins[0].x;
    b[6] = wins[0].w;
    b[7] = wins[0].y >> 3;
    b[8] = wins[0].h >> 3;
    b[9] = wins[1].x;
    b[10] = wins[1].w;
    b[11] = wins[1].y >> 3;
    b[12] = wins[1].h >> 3;
    b[13] = wins[1].open;
    b[14] = wins[1].view | wins[1].sort << 2;
    memcpy(b + 16, wins[1].path, PATHMAX + 1);
    b[HDR - 1] = npins;
    sysDir();
    h = FOpen((void *)deskName, 'w');
    if (h >= 2) {
        e = FWrite(h, buf, HDR);
        for (i = 0; i < npins && !e; ++i) {
            pin_get(i);
            e = FWrite(h, &P, PSZ);
        }
        FClose(h);
    }
    ChDir(curDirName);
    deskDirty = 0;
    LogText(e ? "SHELL DESK NOT SAVED" : "SHELL DESK SAVED");
}

/*---------------------------------------------------------------- the test hook */

/* (main.c's until V101: the resident part needed the room) */
#pragma rodata-name (push, "OVL3RO")
static const char tTst[] = "SHELL.TST";
static const char tStp[] = "SHELL.STP";
static const char tReady[] = "\nSHELL READY 0 IN ";
static const char tList[] = "LIST.DEF";
#pragma rodata-name (pop)


/* SHELL.TST: the script; SHELL.STP: the start count (part n at start n) */
void test_hook(void)
{
    unsigned char h, step = 0, n;
    unsigned int len, i;

    strcpy(str, "/");
    ChDir(str);                 /* the script is in the top folder */
    strcpy(str, tTst);
    h = FOpen(str, 'r');
    if (h < 2) {
        ChDir(curDirName);
        return;
    }
    len = FRead(h, script, sizeof script);
    FClose(h);
    strcpy(str, tStp);
    h = FOpen(str, 'r');
    if (h >= 2) {
        FRead(h, tmp, 1);
        step = tmp[0];
        FClose(h);
    }
    tmp[0] = step + 1;
    h = FOpen(str, 'w');
    if (h >= 2) {
        FWrite(h, tmp, 1);
        FClose(h);
    }
    /* (V176) a window with no saved choice opens in the list; the gates'
       scripts, written for the icons, keep them unless LIST.DEF is in
       the top folder (as V163's PINS.DEF) */
    strcpy(str, tList);
    h = FOpen(str, 'r');
    if (h >= 2)
        FClose(h);
    else {
        iconDef = 1;
        if (deskFresh)
            wins[0].view = V_ICON;
    }
    ChDir(curDirName);
    /* part "step": past that many end records */
    for (i = 0, n = 0; n < step && i + 8 <= len; i += 8)
        if (script[i + 6] & 0x40)
            ++n;
    if (i + 8 > len)
        return;
    part = script + i;
    tstep = step;
    testing = 1;
    strcpy((char *)buf, tReady);        /* and the shell's folder */
    buf[13] = '0' + step;
    strcat((char *)buf, (char *)curDirName);
    LogText(buf);
}

/* (V84: these texts in the overlay, copied below $A000 for the kernel) */
#pragma rodata-name (push, "OVL3RO")
static const char tNoWin[] = "Open the folder's window first.";
static const char tNoSave[] = "Cannot save the Mods folder.";
static const char tMods[] = "SHELL MODS ";
static const char tModsNo[] = "SHELL MODS NOT SAVED ";
static const char tTile[] = "SHELL DOCK TILE ";
static const char tBuilt[] = " BUILT";
static const char tOwn[] = " OWN";
static const char tIcon[] = " ICON";
static const char tCvt[] = ".cvt";
#pragma rodata-name (pop)

static void warnTo(const char *m)
{
    strcpy(msg, m);
    shell_warn(msg);
}

/* File > Set as Mods folder: the front window's folder is the Mods
   place's, kept in MODS.CFG (V84) */
void mods_set(void)
{
    unsigned char h, l, e = 1;
    if (front == 0xFF) {
        warnTo(tNoWin);
        return;
    }
    strcpy(modsDir, wins[front].path);
    l = strlen(modsDir);
    memcpy(buf, modsDir, l);
    buf[l] = '\n';
    sysDir();
    h = FOpen((void *)modsName, 'w');
    if (h >= 2) {
        e = FWrite(h, buf, l + 1);
        FClose(h);
    }
    ChDir(curDirName);
    strcpy(msg, e ? tModsNo : tMods);
    strcat(msg, modsDir);
    LogText(msg);
    XCALL(bWin, win_redraw, FB)(front);
    if (e)
        warnTo(tNoSave);
}

/* the pins' icons (their info blocks) into the desk bank; the tiles of
   the programs put aside (V84: from the paths they were started by, the
   switcher's notes, dock_note) */
void pins_icons(void)
{
    unsigned char i, t;
    unsigned char tt[TASK_MAX];
    char *p;
    XCALL(bLook3, ic3_file, FIC3)(2, 0xFF, 0);     /* (V152: the dock's classes forgotten) */
    for (i = 0; i < npins; ++i) {
        memset(pic, 0, 64);
        pic[0] = 0xBF;
        pin_get(i);
        strcpy(tmp, P.name);
        if (shell_is_cvt(tmp))
            tmp[strlen(tmp) - 4] = 0;
        if (ChDir(P.dir) || FindFile(tmp)) {
            /* a pin from before V71, in /VERANDA: its application moved
               to /VERANDA/APPS */
            if (strcmp(P.dir, VR_SYSDIR) || ChDir(VR_APPSDIR) || FindFile(tmp))
                goto none;
            strcpy(P.dir, VR_APPSDIR);
            pin_put(i);
            deskDirty = 1;
        }
        if (GetFHdrInfo((void *)dirEntryBuf) == 0) {
            memcpy(pic, (void *)(fileHeader + 4), 64);
            pic[0] = 0xBF;
            pinTile[i] = tileFor(P.name, bDesk, DT_AT + i * TILELEN);
            if (pinTile[i] == TL_OWN)
                pinTile[i] += i;
            XCALL(bLook3, ic3_file, FIC3)(2, i, P.name);
        } else {
    none:
            pinTile[i] = TL_ICON;
        }
        icon_put(2, i, pic, 0);
    }
    for (i = 0; i < TASK_MAX; ++i) {
        t = TL_BUILT + T_DOCUMENT;
        TaskCtl(TASK_INFO, i, buf);
        if (buf[TR_STATE] && buf[TR_NOTE] == '/') {
            strcpy(msg, (char *)buf + TR_NOTE);
            p = strrchr(msg, '/');
            strcpy(tmp, p + 1);
            p[p == msg] = 0;            /* (the top folder: "/") */
            if (ChDir(msg) == 0 && FindFile(tmp) == 0 && GetFHdrInfo((void *)dirEntryBuf) == 0) {
                memcpy(pic, (void *)(fileHeader + 4), 64);
                pic[0] = 0xBF;
                icon_put(2, MAXPINS + i, pic, 0);
                strcat(tmp, tCvt);
                t = tileFor(tmp, bDesk, DT_AT + (MAXPINS + i) * TILELEN);
                XCALL(bLook3, ic3_file, FIC3)(2, MAXPINS + i, tmp);
                tmp[strlen(tmp) - 4] = 0;
                if (t == TL_OWN)
                    t += MAXPINS + i;
            }
            if (testing) {
                strcpy(msg, tTile);
                strcat(msg, tmp);
                strcat(msg, t & TL_BUILT ? tBuilt : t & TL_OWN ? tOwn : tIcon);
                LogText(msg);
            }
        }
        tt[i] = t;
    }
    bput(bDesk, TT_AT, tt, TASK_MAX);
    ChDir(curDirName);
}

/*---------------------------------------------------------------- the list's header */

/* a click on the list's header at x: sorted by that column (the columns
   view.c draws: C_SIZE 212, C_DATE 224, C_TYPE 300 from the contents'
   left; moved here from view.c, V81) */
void view_header(unsigned char w, unsigned int x)
{
    struct win *p = &wins[w];
    unsigned char k;
    x -= (p->x + (p->w >= 40 ? 12 : 0)) * 8;
    k = x < 212 - 40 ? S_NAME : x < 224 - 4 ? S_SIZE : x < 300 - 4 ? S_DATE : S_TYPE;
    p->sort = k;
    p->sel = 0xFF;
    p->first = 0;
    if (w)
        deskDirty = 1;
    sort_win(w);
    XCALL(bWin, win_content, FB)(w);
    view_log(w);
}

/*---------------------------------------------------------------- the list on the console */

static void two(char *p, unsigned char n)
{
    p[0] = '0' + n / 10;
    p[1] = '0' + n % 10;
}

/* the date for the log: "2026-11-16 10:42", "-" if there is none */
static void dateStr(char *out)
{
    if (!E.date[1]) {
        strcpy(out, "-");
        return;
    }
    num(1900u + E.date[0], out);
    out[4] = '-';
    two(out + 5, E.date[1]);
    out[7] = '-';
    two(out + 8, E.date[2]);
    out[10] = ' ';
    two(out + 11, E.date[3]);
    out[13] = ':';
    two(out + 14, E.date[4]);
    out[16] = 0;
}

/* the list on the console: SHELL LIST w BY key, then a row an entry */
void view_log(unsigned char w)
{
    static const char *const keys[4] = { "NAME", "SIZE", "DATE", "TYPE" };
    struct win *p = &wins[w];
    unsigned char i;
    char *q;
    if (!testing)
        return;
    strcpy(msg, "SHELL LIST ");
    num(w, msg + 11);
    strcat(msg, " BY ");
    strcat(msg, keys[p->sort & 3]);
    LogText(msg);
    for (i = 0; i < p->n; ++i) {
        ent_get(w, p->order[i]);
        strcpy(msg, "SHELL ROW ");
        strcat(msg, E.name);
        strcat(msg, "|");
        q = msg + strlen(msg);
        if (E.type == 'F')
            num(E.size, q);
        else
            strcpy(q, "-");
        strcat(msg, "|");
        dateStr(msg + strlen(msg));
        strcat(msg, "|");
        type_str(&E, msg + strlen(msg));
        LogText(msg);
    }
}

/* a double click on a GEOS document (E, the front window's; V87): the
   application of its parent class (the info block's bytes 117-136,
   GEOS's "parent application" permanent name: its first 12 characters,
   so a later version opens it too) in the folder shown, in
   /VERANDA/APPS, /VERANDA or the top folder, started with it as its
   document (GetFile, ST_LD_DATA, the whole name: dataLongName).
   None there (V135): the document's own class (bytes 77-96) in tSubst,
   a substitute application's class searched for the same way */
#pragma rodata-name (push, "OVL3RO")
static const char tNoRead[] = "Cannot read the document.";
static const char tNoApp[] = "This document has no application.";
static const char tNoOpen[] = "No application opens this document.";
/* the substitutes (V135), a line a pair: a document class (its start,
   compared up to its length) and the class of the application that opens
   it when its own is missing (12 characters, padded with spaces as the
   parent class is: any version); the first that matches is taken; the
   list ends with "" */
static const char tSubst[] =
    "Write Image V\0" "CmdrWrite   "       /* geoWrite's: Veranda Write */
    "";
#pragma rodata-name (pop)
#pragma bss-name (push, "OVL3BSS")
static const char *sub;
static unsigned char n;
#pragma bss-name (pop)

void dir_open_data(void)
{
#define cls (msg + 140)                 /* (msg: free until a warning) */
    unsigned char i;
    const char *d;
    shown(&E, str);
    if (FindFile(str) || GetFHdrInfo((void *)dirEntryBuf)) {
        warnTo(tNoRead);
        return;
    }
    memcpy(cls, fileHeader + 117, 12);
    cls[12] = 0;
    if (cls[0] < '0') {
        warnTo(tNoApp);
        return;
    }
    /* the substitute (V135), before FindFTypes (it reads other info
       blocks): sub its class, else 0 */
    sub = 0;
    for (d = tSubst; (n = strlen(d)) != 0; d += n + 13)
        if (!memcmp(fileHeader + 77, d, n)) {
            sub = d + n + 1;
            break;
        }
    shell_keep();
    for (;;) {
        for (i = 0; i < 4; ++i) {
            d = i ? homes[i - 1] : (const char *)curDirName;
            if (i && !strcmp((char *)curDirName, d))
                continue;
            if (ChDir((void *)d) == 0 && FindFTypes(buf, APPLICATION, 1, cls) == 0) {
                strcpy(tmp, (char *)buf);
                startDoc(d);
                return;
            }
        }
        if (!sub)
            break;
        memcpy(cls, sub, 12);           /* (the second pass: the substitute) */
        sub = 0;
    }
    ChDir((char *)curDirName);
    warnTo(tNoOpen);
    if (testing)                        /* (the gates, V135: after its OK) */
        LogText(msg);
#undef cls
}
