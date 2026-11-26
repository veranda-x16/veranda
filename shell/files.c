/* Veranda shell: the file utilities (DECISIONS V61).

   Find: file names matching a pattern (* and ?, case ignored; without
   either, any name holding it) from the current folder down, listed in
   the window; a result opens (a double click, or open) or is shown in its
   folder, selected (reveal).

   Copy and move, whole folders too: file/copy or file/move picks the
   selection up, file/put here puts it into the folder shown (a copy into
   its own folder is named "Copy of ..."). A folder is walked: its folders
   made at the destination, its files copied through 'w' streams (8 KB a
   read, in a RAM bank), or moved by a rename from the top folder (the
   DOS's R command with the paths, when it fits the kernel's 70
   characters; else a copy and a delete), then the folders left empty
   removed (RD), the deepest first. A progress box counts the files and
   has a cancel button, read between files and between blocks (a copy
   stopped in a file deletes that file).

   Dragging an icon onto another window or a folder (Shell 2, V70) is a
   copy or a move the same way (files_drop), from its window's folder.

   The trash: /VERANDA/.SYSTEM/TRASH (DECISIONS V71; /TRASH without a
   /VERANDA). Delete moves
   a file or a folder there (after a YES, or dropped on the trash's icon;
   a name taken there gets ~2, ~3 ...); in the trash itself, delete
   deletes. disk/empty trash deletes everything in it (with its sound,
   SND_TRASH: DECISIONS V69); disk/trash or a double click on its icon
   shows it.

   Get info: a GEOS file's info block (its icon, name, type, class,
   author, date, size) with its description in a text field; OK writes the
   description back in place (96 bytes at offset 412 of the CVT file: one
   sector, DECISIONS V55).

   Folders' directory commands (MD, RD, R) are sent from the top folder
   with paths relative to it: the emulator's host folder takes those
   wherever they come from. */
#include <veranda.h>
#include <string.h>
#include "shell.h"
#pragma code-name ("OVERLAY4")

#define RAMBANK (*(volatile unsigned char *)0)
#define BANKMEM ((unsigned char *)0xA000)
#define BACK()  (RAMBANK = appBank)

#define MAXSTACK 120            /* folders a walk keeps (64 bytes each) */
#define MAXNAMES 170            /* entries of a folder (48 bytes each) */
#define MAXFOUND 30             /* results (128 bytes: folder, name) */
#define ROWH     14

enum { W_COUNT, W_COPY, W_MOVE, W_DELETE, W_FIND };
enum { E_NONE, E_LONG, E_MANY, E_READ, E_WRITE, E_DIR };
static const char *const emsg[] = {
    "", "A path is too long.", "There are too many files or folders.",
    "A folder cannot be read.", "A file cannot be written.", "A folder cannot be made or removed."
};

static unsigned char bStack, bSeen, bNames, bFound, bCopy;
static char src[64], dst[64], rel[64], pa[64], pb[64], nm[48], ra[72], rb[72];
static char sparent[64], sname[48], dname[48];
char trash[24];
static unsigned char stype, picked, pmove;
static unsigned char wop, stop, werr, keep, nstack, nseen, nnames, nfound, fsel, showbox;
static unsigned int total, done;
static char pat[24];
static char line[100];

unsigned char found_on;

/* (V209) the walks' 4 banks (the folders' stack, those seen, a folder's
   names, the copy's buffer) taken while an operation runs and given back
   after it; the find's results' bank while they are shown (files_lend
   gives it back before a desk accessory, a find takes it again). Taken
   at the start before V209 (5 banks held while the shell runs: a desk
   accessory beside the desktop, the shell packed, then found too few at
   512 KB, NO_BANKS); none now: copy, move, delete and find say so */
static unsigned char take(void)
{
    unsigned char b;
    if (!bStack) {
        if (!(b = BankAlloc(4))) {
            shell_warn("No RAM banks for this.");
            return 0;
        }
        bStack = b;
        bSeen = b + 1;
        bNames = b + 2;
        bCopy = b + 3;
    }
    return 1;
}

static void give(void)
{
    if (bStack)
        BankFree(bStack);
    bStack = 0;
}

void files_lend(void)
{
    if (bFound && !found_on) {
        BankFree(bFound);
        bFound = 0;
    }
}

/* (this code runs in its own bank at $A000: the other banks are reached
   through the resident part's copies, bput and bget) */
static void bputs(unsigned char b, unsigned int off, const char *s)
{
    bput(b, off, s, strlen(s) + 1);
}

/* (V182) the console's words, in this overlay's bank (main RAM had no
   room): only copied into line here, never given to the kernel */
#pragma rodata-name (push, "OVL4RO")
static const char tHit[] = "SHELL HIT ";
static const char tStopped[] = "SHELL STOPPED ";
static const char tDeleted[] = "SHELL DELETED ";
static const char tKept[] = "SHELL KEPT ";
static const char tTrashed[] = "SHELL TRASHED ";
static const char tAs[] = " AS ";
static const char tEmptied[] = "SHELL EMPTIED ";
#pragma rodata-name (pop)

static void logs(const char *a, const char *b)
{
    strcpy(line, a);
    strcat(line, b);
    LogText(line);
}

static void numi(unsigned int n, char *out)
{
    char t[6];
    unsigned char i = 0;
    do
        t[i++] = '0' + n % 10;
    while (n /= 10);
    while (i)
        *out++ = t[--i];
    *out = 0;
}

/* out = a "/" b (b empty: a); 0 if too long */
static unsigned char join(char *out, const char *a, const char *b)
{
    unsigned char la = strlen(a);
    if (!*b) {
        strcpy(out, a);
        return 1;
    }
    if (la + strlen(b) + 1 > PATHMAX)
        return 0;
    strcpy(out, a);
    if (la && a[la - 1] != '/')
        out[la++] = '/';
    strcpy(out + la, b);
    return 1;
}

/* out = path relative to the top folder, then "/" name */
static void rootrel(char *out, const char *path, const char *name)
{
    strcpy(out, path + 1);
    if (*out)
        strcat(out, "/");
    strcat(out, name);
}

/* a name in the folder dir (a file or a folder) */
static unsigned char exists(const char *dir, const char *name)
{
    unsigned char h, r = 0;
    if (ChDir(dir))
        return 0;
    h = FOpen((void *)name, 'r');
    if (h >= 2) {
        FClose(h);
        r = 1;
    } else if (ChDir(name) == 0)
        r = 1;
    ChDir(curDirName);
    return r;
}

/*---------------------------------------------------------------
  the progress box (the foreground; the window is drawn again after)
 ---------------------------------------------------------------*/
#define PBL 160
#define PBT 190
#define PBR 479
#define PBB 279
#define CBL (PBR - 76)
#define CBT (PBB - 24)
#define CBR (PBR - 12)
#define CBB (PBB - 10)

static void box_draw(const char *title)
{
    dispBufferOn = ST_WR_FORE;
    SetPattern(0);
    WRectangle(PBL, PBT, PBR, PBB);
    WFrameRectangle(0xFF, PBL, PBT, PBR, PBB);
    WFrameRectangle(0xFF, PBL + 2, PBT + 2, PBR - 2, PBB - 2);
    WPutString((void *)title, PBL + 12, PBT + 8 + baselineOffset);
    WFrameRectangle(0xFF, PBL + 12, PBT + 42, PBR - 12, PBT + 52);
    WFrameRectangle(0xFF, CBL, CBT, CBR, CBB);
    WPutString("Cancel", CBL + 14, CBT + 3 + baselineOffset);
    dispBufferOn = ST_WR_FORE | ST_WR_BACK;
}

static void box_update(const char *name)
{
    unsigned int w;
    unsigned char x;
    if (!showbox)
        return;
    dispBufferOn = ST_WR_FORE;
    numi(done + 1, line);
    strcat(line, " of ");
    numi(total, line + strlen(line));
    strcat(line, ": ");
    strcat(line, name);
    /* the text over the last, then the rest of the line cleared (no
       moment without it) */
    for (w = 0, x = 0; line[x] && w < PBR - PBL - 40; ++x)
        w += GetCharWidth(line[x]);
    line[x] = 0;
    WPutString(line, PBL + 12, PBT + 26 + baselineOffset);
    SetPattern(0);
    WRectangle(PBL + 12 + w, PBT + 22, PBR - 12, PBT + 38);
    w = total ? (unsigned long)(PBR - PBL - 28) * done / total : 0;
    SetPattern(1);
    if (w)
        WRectangle(PBL + 14, PBT + 44, PBL + 13 + w, PBT + 50);
    dispBufferOn = ST_WR_FORE | ST_WR_BACK;
}

/* a press on the cancel button stops the walk */
static unsigned char cancelled(void)
{
    unsigned int x, y;
    if (stop || !showbox || mouseData & 0x80)
        return stop;
    x = mouseXPos;
    y = mouseYPosW;
    if (x >= CBL && x <= CBR && y >= CBT && y <= CBB) {
        stop = 1;
        dispBufferOn = ST_WR_FORE;
        WInvertRectangle(CBL + 1, CBT + 1, CBR - 1, CBB - 1);
        dispBufferOn = ST_WR_FORE | ST_WR_BACK;
    }
    return stop;
}

/*---------------------------------------------------------------
  files: the current folder is pa; the destination folder pb
 ---------------------------------------------------------------*/
static unsigned char copy_file(const char *from, const char *to)
{
    unsigned char h1, h2, e = 0;
    unsigned int n;
    h1 = FOpen((void *)from, 'r');
    if (h1 < 2)
        return E_READ;
    if (ChDir(pb) || (h2 = FOpen((void *)to, 'w')) < 2) {
        FClose(h1);
        ChDir(pa);
        return E_WRITE;
    }
    do {
        n = bfread(bCopy, h1, 8192);
        if (n)
            e = bfwrite(bCopy, h2, n);
    } while (!e && n == 8192 && !cancelled());
    FClose(h2);
    FClose(h1);
    if (stop)
        FDelete((void *)to);            /* (stopped in the middle) */
    ChDir(pa);
    return e ? E_WRITE : 0;
}

static unsigned char move_file(const char *from, const char *to)
{
    unsigned char e;
    rootrel(ra, pa, from);
    rootrel(rb, pb, to);
    if (strlen(ra) + strlen(rb) + 3 <= 70) {
        ChDir("/");
        e = FRename(ra, rb);
        ChDir(pa);
        return e ? E_WRITE : 0;
    }
    if ((e = copy_file(from, to)) || stop)
        return e;
    return FDelete((void *)from) ? E_WRITE : 0;
}

/* name (in the folder pa) kept if it matches pat, or a GEOS file's name
   without ".cvt" does */
static void found(const char *name)
{
    static char shown[48];
    char *p;
    strcpy(shown, name);
    if (shell_is_cvt(name))
        shown[strlen(shown) - 4] = 0;
    if (!XCALL(bIc2, files_match, unsigned char (*)(const char *, const char *, const char *))(pat, name, shown))
        return;                         /* (info.c, overlay 16: room, V182) */
    if (nfound >= MAXFOUND) {
        werr = E_MANY;
        return;
    }
    bputs(bFound, nfound * 128, pa);
    bputs(bFound, nfound * 128 + 64, name);
    ++nfound;
    strcpy(line, tHit);
    strcat(line, pa[1] ? pa : "");
    strcat(line, "/");
    strcat(line, name);
    LogText(line);
}

/* the folder src (and dst) walked: wop on every file, then the folders */
static void walk(void)
{
    static unsigned char de[3 + 64];
    unsigned char i, l;
    char *p;
    nstack = nseen = 0;
    bputs(bStack, nstack++ * 64, "");
    while (nstack && !stop && !werr) {
        bget(bStack, --nstack * 64, rel, 64);
        if (nseen >= MAXSTACK) {
            werr = E_MANY;
            break;
        }
        bputs(bSeen, nseen++ * 64, rel);
        if (!join(pa, src, rel) || ((wop == W_COPY || wop == W_MOVE) && !join(pb, dst, rel))) {
            werr = E_LONG;
            break;
        }
        if (wop == W_COPY || wop == W_MOVE) {
            ChDir("/");
            if (MkDir(pb + 1)) {
                werr = E_DIR;
                break;
            }
        }
        if (ChDir(pa)) {
            werr = E_READ;
            break;
        }
        nnames = 0;                     /* the listing first, whole */
        if (DirOpen("*") == 0)
            while (DirNext(de) == 0) {
                p = (char *)de + 3;
                if (!strcmp(p, ".") || !strcmp(p, ".."))
                    continue;
                if (nnames >= MAXNAMES || strlen(p) > NAMELEN) {
                    werr = E_MANY;
                    continue;
                }
                de[2] = de[0];
                bputs(bNames, nnames++ * 48, (char *)de + 2);
            }
        for (i = 0; i < nnames && !werr && !cancelled(); ++i) {
            bget(bNames, i * 48, nm, 48);
            if (nm[0] == 'D') {
                if (wop == W_FIND)
                    found(nm + 1);
                l = strlen(rel);
                if (l + strlen(nm + 1) + 2 > PATHMAX || nstack >= MAXSTACK) {
                    werr = l ? E_LONG : E_MANY;
                    break;
                }
                strcpy(ra, rel);
                if (l)
                    ra[l++] = '/';
                strcpy(ra + l, nm + 1);
                bputs(bStack, nstack++ * 64, ra);
                continue;
            }
            if (wop == W_COUNT) {
                ++total;
                continue;
            }
            if (wop == W_FIND) {
                found(nm + 1);
                continue;
            }
            box_update(nm + 1);
            werr = wop == W_COPY ? copy_file(nm + 1, nm + 1) : wop == W_MOVE ? move_file(nm + 1, nm + 1)
                   : FDelete(nm + 1) ? E_WRITE : 0;
            if (!stop && !werr)
                ++done;
        }
    }
    if ((wop == W_MOVE || wop == W_DELETE) && !stop && !werr) {
        ChDir("/");
        for (i = nseen; i-- > keep;) {              /* the deepest first */
            bget(bSeen, i * 64, rel, 64);
            join(pa, src, rel);
            if (RmDir(pa + 1)) {
                werr = E_DIR;
                break;
            }
        }
    }
}

/* wop on the item sname (stype) of sparent, into dname of the folder in
   dst's place (copy, move); the number of files done */
static unsigned char run(unsigned char op, const char *title)
{
    if (!take())
        return 0;
    play_busy = 1;
    stop = werr = 0;
    total = done = 0;
    showbox = 0;
    strcpy(pa, sparent);
    if (stype == 'D') {
        if (!join(src, sparent, sname) || (op != W_DELETE && !join(dst, pb, dname))) {
            werr = E_LONG;
            goto out;
        }
        wop = W_COUNT;                  /* the files counted first */
        walk();
        if (werr)
            goto out;
    } else
        total = 1;
    showbox = 1;
    box_draw(title);
    wop = op;
    if (stype == 'D')
        walk();
    else {
        ChDir(pa);
        box_update(sname);
        werr = op == W_COPY ? copy_file(sname, dname) : op == W_MOVE ? move_file(sname, dname)
               : FDelete(sname) ? E_WRITE : 0;
        if (!werr && !stop)
            ++done;
    }
out:
    give();
    ChDir(curDirName);
    showbox = 0;
    play_busy = 0;
    numi(done, line + 80);
    if (stop) {
        strcpy(line, tStopped);
        strcat(line, line + 80);
        LogText(line);
    } else if (werr) {
        shell_warn(emsg[werr]);
    }
    return done;
}

/*---------------------------------------------------------------
  copy and move
 ---------------------------------------------------------------*/
void files_pick(const char *name, char type, unsigned char move)
{
    strcpy(sparent, (char *)curDirName);
    strcpy(sname, name);
    stype = type;
    pmove = move;
    picked = 1;
    logs(move ? "SHELL PICKED TO MOVE " : "SHELL PICKED TO COPY ", name);
    shell_redraw();
}

void files_title(unsigned int x, unsigned int y)
{
    if (!picked)
        return;
    strcpy(line, pmove ? "to move: " : "to copy: ");
    strcat(line, sname);
    line[24] = 0;
    WPutString(line, x, y + baselineOffset);
}

/* sname (stype) of sparent copied or moved (pmove) into the folder pb */
static void doPut(void)
{
    unsigned char l, n;
    strcpy(dname, sname);
    if (!strcmp(pb, sparent)) {
        if (pmove) {
            shell_warn("It is in this folder already.");
            return;
        }
        strcpy(dname, "Copy of ");
        strcat(dname, sname);
        if (shell_is_cvt(sname) && strlen(dname) > 20)
            strcpy(dname + 16, ".cvt");
    }
    if (stype == 'D') {
        join(src, sparent, sname);
        l = strlen(src);
        if (!strncmp(pb, src, l) && (pb[l] == 0 || pb[l] == '/')) {
            shell_warn("A folder cannot go into itself.");
            return;
        }
    }
    if (exists(pb, dname)) {
        shell_warn("That name is taken in this folder.");
        return;
    }
    keep = 0;
    n = run(pmove ? W_MOVE : W_COPY, pmove ? "Moving" : "Copying");
    if (!stop && !werr) {
        numi(n, line + 80);
        logs(pmove ? "SHELL MOVED " : "SHELL COPIED ", line + 80);
        picked = 0;
    }
    shell_reload();
}

void files_put(void)
{
    if (!picked) {
        shell_warn("Choose File > Copy or Move first.");
        return;
    }
    strcpy(pb, (char *)curDirName);
    doPut();
}

/* an icon dropped: name (type) of the folder from into the folder to */
void files_drop(const char *from, const char *name, char type, const char *to, unsigned char move)
{
    unsigned char p = picked, pm = pmove;
    static char ks[48], kp[64];
    char kt = stype;
    strcpy(ks, sname);
    strcpy(kp, sparent);
    strcpy(sparent, from);
    strcpy(sname, name);
    stype = type;
    pmove = move;
    strcpy(line, move ? "SHELL DROP MOVE " : "SHELL DROP COPY ");
    strcat(line, name);
    strcat(line, " TO ");
    strcat(line, to);
    LogText(line);
    strcpy(pb, to);
    picked = 1;
    doPut();
    /* what file/copy or move picked up before stays picked */
    if (p) {
        strcpy(sname, ks);
        strcpy(sparent, kp);
        stype = kt;
        pmove = pm;
    }
    picked = p;
}

/*---------------------------------------------------------------
  the trash
 ---------------------------------------------------------------*/
void trash_path(void)
{
    const char *d = vr_cd(VR_DATA);     /* (made: the trash is made in it) */
    strcpy(trash, d[1] ? d : "");
    strcat(trash, "/TRASH");
    ChDir(curDirName);
}

static unsigned char in_trash(void)
{
    unsigned char l = strlen(trash);
    return !strncmp((char *)curDirName, trash, l) && (curDirName[l] == 0 || curDirName[l] == '/');
}

static void make_trash(void)
{
    ChDir("/");
    MkDir(trash + 1);                   /* (there already: an error, ignored) */
    ChDir(curDirName);
}

/* dname = name, or name~2 ... (before a .ext) when taken in the trash */
static unsigned char trash_name(const char *name)
{
    const char *dot = strrchr(name, '.');
    unsigned char b, k;
    strcpy(dname, name);
    for (k = '2'; exists(trash, dname); ++k) {
        if (k > '9')
            return 0;
        b = dot && dot != name ? dot - name : strlen(name);
        if (b > 14)
            b = 14;
        memcpy(dname, name, b);
        dname[b] = '~';
        dname[b + 1] = k;
        strcpy(dname + b + 2, dot && dot != name ? dot : "");
    }
    return 1;
}

void files_delete(const char *name, char type, unsigned char ask)
{
    trash_path();
    strcpy(sparent, (char *)curDirName);
    strcpy(sname, name);
    stype = type;
    if (in_trash()) {
        if (!shell_yes("Delete this for good?", name))
            return;
        keep = 0;
        run(W_DELETE, "Deleting");
        logs(tDeleted, name);
        shell_reload();
        return;
    }
    strcpy(src, sparent);
    join(src, sparent, name);
    /* (V182) the trash itself, and what Veranda needs, stay: /VERANDA,
       what is right in it (VERANDA.PRG, SHELL.cvt, APPS ...), all in its
       dot folders (.SYSTEM). What is inside APPS, FONTS, WALLPAPERS, HELP
       goes to the trash (V71's vr_insys(src) refused all of /VERANDA, so
       a document in APPS could not be deleted: "Use file > empty trash.",
       the wrong menu too). 8, 9: VR_SYSDIR's length, past its "/" */
    if (!strcmp(src, trash) || (vr_insys(src) && (!src[8] || src[9] == '.' || !strchr(src + 9, '/')))) {
        shell_warn(strcmp(src, trash) ? "Veranda needs this: it stays." : "Use Disk > Empty trash.");
        logs(tKept, name);
        return;
    }
    if (ask && !shell_yes(type == 'D' ? "Move this folder and all in it to the trash?" : "Move this to the trash?", name))
        return;
    make_trash();
    if (!trash_name(name)) {
        shell_warn("The trash has too many of that name.");
        return;
    }
    strcpy(pb, trash);
    keep = 0;
    run(W_MOVE, "Moving to the trash");
    if (!stop && !werr) {
        strcpy(line, tTrashed);
        strcat(line, name);
        strcat(line, tAs);
        strcat(line, dname);
        LogText(line);
    }
    shell_reload();
}

void files_empty_trash(void)
{
    unsigned char n;
    trash_path();
    if (ChDir(trash)) {
        shell_say("The trash is empty.");
        return;
    }
    ChDir(curDirName);
    if (!shell_yes("Empty the trash?", "What is in it is deleted for good."))
        return;
    strcpy(sparent, trash);
    *strrchr(sparent, '/') = 0;
    if (!sparent[0])
        strcpy(sparent, "/");
    strcpy(sname, "TRASH");
    stype = 'D';
    keep = 1;                           /* the TRASH folder stays */
    n = run(W_DELETE, "Emptying the trash");
    keep = 0;
    PlaySound(SND_TRASH);                /* (DECISIONS V69: the crunch) */
    numi(n, line + 80);
    logs(tEmptied, line + 80);
    shell_reload();
}

/* anything in the trash? */
unsigned char trash_full(void)
{
    static unsigned char de[3 + 64];
    unsigned char r = 0;
    trash_path();
    if (ChDir(trash) == 0 && DirOpen("*") == 0)
        while (DirNext(de) == 0)
            if (strcmp((char *)de + 3, ".") && strcmp((char *)de + 3, ".."))
                r = 1;
    ChDir(curDirName);
    return r;
}

/*---------------------------------------------------------------
  find
 ---------------------------------------------------------------*/
struct box3 {                   /* text, an input through r5, OK, CANCEL */
    unsigned char pos;
    unsigned char t1, x1, y1; const char *s1;
    unsigned char t2, x2, y2, reg2, max2;
    unsigned char ok, okx, oky;
    unsigned char cn, cnx, cny;
    unsigned char end;
};
static const struct box3 findBox = {
    DEF_DB_POS | 1,
    DBTXTSTR, TXT_LN_X, TXT_LN_1_Y, "Find names like (* ?):",
    DBGETSTRING, TXT_LN_X, TXT_LN_2_Y, 0x0C, 20,
    OK, DBI_X_0, DBI_Y_2,
    CANCEL, DBI_X_2, DBI_Y_2,
    0
};

static char froot[64];

void files_find(void)
{
    unsigned char r;
    char *p;
    r5 = (unsigned int)pat;
    r = DoDlgBox((void *)&findBox);
    if ((r != OK && r != DBGETSTRING) || !pat[0])
        return;
    if (!strchr(pat, '*') && !strchr(pat, '?') && strlen(pat) < sizeof pat - 2) {
        memmove(pat + 1, pat, strlen(pat) + 1);
        pat[0] = '*';
        strcat(pat, "*");
    }
    if (!bFound && !(bFound = BankAlloc(1))) {  /* (V209: the results' bank, the walk's) */
        shell_warn("No RAM banks for this.");
        return;
    }
    if (!take())
        return;
    play_busy = 1;
    strcpy(froot, (char *)curDirName);
    strcpy(src, froot);
    nfound = 0;
    stop = werr = 0;
    showbox = 0;
    wop = W_FIND;
    walk();
    give();
    ChDir(curDirName);
    p = line + 80;
    numi(nfound, p);
    logs("SHELL FOUND ", p);
    found_on = 1;
    fsel = nfound ? 0 : 0xFF;
    play_busy = 0;
    shell_redraw();
}

/* the results in the front window's contents (cx0-cx1, cy0-cy1): a
   line with the count and three buttons, then a row a result */
#define FBW  52
#define RTOP (cy0 + 16)
static const char *const fbt[3] = { "open", "reveal", "close" };

static unsigned int fbx(unsigned char i)
{
    return cx1 - 4 - (3 - i) * (FBW + 4);
}

static void found_row(unsigned char i)
{
    unsigned char l;
    unsigned int w;
    bget(bFound, i * 128, line, 64);
    if (line[1])
        strcat(line, "/");
    bget(bFound, i * 128 + 64, line + strlen(line), 48);
    for (l = 0, w = 0; line[l] && w < cx1 - cx0 - 20; ++l)
        w += GetCharWidth(line[l]);
    line[l] = 0;
    WPutString(line, cx0 + 8, RTOP + 1 + i * ROWH + baselineOffset);
}

static void found_mark(void)
{
    if (fsel != 0xFF)
        WInvertRectangle(cx0 + 3, RTOP + fsel * ROWH, cx1 - 3, RTOP + fsel * ROWH + ROWH - 2);
}

void found_draw(void)
{
    unsigned char i;
    strcpy(line, "Found in ");
    strcat(line, froot);
    strcat(line, ": ");
    numi(nfound, line + strlen(line));
    strcat(line, werr == E_MANY ? " (the first ones)" : "");
    line[30] = 0;
    WPutString(line, cx0 + 8, cy0 + 1 + baselineOffset);
    for (i = 0; i < 3; ++i) {
        WFrameRectangle(0xFF, fbx(i), cy0 - 1, fbx(i) + FBW, cy0 + 12);
        WPutString((void *)fbt[i], fbx(i) + 8, cy0 + baselineOffset);
    }
    WHorizontalLine(0xFF, cx0, cx1, cy0 + 14);
    for (i = 0; i < nfound && RTOP + i * ROWH + ROWH <= cy1; ++i)
        found_row(i);
    if (!nfound)
        WPutString("Nothing has that name.", cx0 + 8, RTOP + 1 + baselineOffset);
    found_mark();
}

static void found_go(unsigned char open)
{
    static char d[64], n[48];
    char *p;
    if (fsel == 0xFF)
        return;
    bget(bFound, fsel * 128, d, 64);
    bget(bFound, fsel * 128 + 64, n, 48);
    found_on = 0;
    strcpy(line, open ? "SHELL OPEN " : "SHELL REVEAL ");
    strcat(line, d);
    strcat(line, " ");
    strcat(line, n);
    LogText(line);
    shell_go(d, n, open);
}

void found_press(unsigned int x, unsigned int y)
{
    unsigned char i;
    if (y < cy0 + 14) {
        for (i = 0; i < 3; ++i)
            if (x >= fbx(i) && x <= fbx(i) + FBW) {
                if (i == 2) {
                    found_on = 0;
                    shell_redraw();
                } else
                    found_go(i == 0);
                return;
            }
        return;
    }
    if (y < RTOP)
        return;
    i = (y - RTOP) / ROWH;
    if (i >= nfound)
        return;
    if (i == fsel && dblClickCount) {
        dblClickCount = 0;
        found_go(1);
        return;
    }
    found_mark();
    fsel = i;
    found_mark();
    dblClickCount = CLICK_COUNT;
}

/*---------------------------------------------------------------
  get info
 ---------------------------------------------------------------*/
#pragma bss-name ("OVL4BSS")            /* (in this overlay's bank: FRead writes there, the
                                           rest is copied out: V101 needed the room) */
static unsigned char ib[284];           /* the CVT's entry (0-29) and info block (file 254-507) */
#pragma bss-name ("BSS")
#define INF(k) (ib[28 + (k)])
static char desc[97];

static const char *const tname[] = {
    "not GEOS", "BASIC", "assembly", "data", "system", "desk accessory", "application",
    "document", "font", "printer driver", "input driver", "disk driver", "boot",
    "temporary", "auto-exec", "input 128"
};

#define IBT 90                          /* the box */
#define IBB 300
#define IBL 40
#define IBR 599

/* (V181) a field of the info block as text: it ends at its length, a 0,
   the padding ($A0) or any other control byte (geoWrite leaves memory's
   leftovers in fields it does not use; WPutString would take a control
   byte as a code: ESC_GRAPHICS drew a GraphicsString of junk over the
   box, REVON blocks), a byte past '~' shown as '?' (the box's font has
   none) */
static unsigned char text(char *d, const unsigned char *s, unsigned char n)
{
    unsigned char l = 0, c;
    while (l < n && (c = s[l]) >= ' ' && c != 0xA0) {
        d[l] = c < 0x7F ? c : '?';
        ++l;
    }
    d[l] = 0;
    return l;
}

static void put(const char *label, const unsigned char *s, unsigned char n, unsigned int y)
{
    strcpy(line, label);
    text(line + strlen(line), s, n);
    WPutString(line, IBL + 72, y + baselineOffset);
}

static void info_draw(void)
{
    static unsigned char ico[64];
    unsigned char t = INF(69), l;
    if (!XCALL(bIc2, info_icon, unsigned char (*)(unsigned char, unsigned char))((IBL + 24) >> 3, (IBT + 14) >> 3)) {   /* (V181: in colour, info.c) */
        memcpy(ico, &INF(4), 64);
        ico[0] = 0xBF;
        WBitmapUp(ico, (IBL + 24) >> 3, 3, IBT + 14, 21);
    }
    put("", ib + 3, 16, IBT + 12);
    strcpy(line, t < 16 ? tname[t] : "other");
    strcat(line, ib[21] == 1 ? ", VLIR, " : ", sequential, ");
    l = strlen(line);
    numi(ib[28] | ib[29] << 8, line + l);
    strcat(line, " blocks");
    WPutString(line, IBL + 72, IBT + 26 + baselineOffset);
    put("class: ", &INF(77), 20, IBT + 40);
    put("author: ", &INF(97), 20, IBT + 52);
    put("application: ", &INF(117), 20, IBT + 64);
}

struct ibox {
    unsigned char pos;
    unsigned int top, bottom, left, right;
    unsigned char u; void (*rout)(void);
    unsigned char t1, x1, y1; const char *s1;
    unsigned char t2, x2, y2, reg2, max2;
    unsigned char ok, okx, oky;
    unsigned char cn, cnx, cny;
    unsigned char end;
};
static const struct ibox infoBox = {
    SET_DB_POS | WIDE_DB | 1, IBT, IBB, IBL, IBR,
    DB_USR_ROUT, info_draw,
    DBTXTSTR, 16, 96, "Description:",
    DBGETSTRING, 16, 112, 0x0C, 95,
    OK, 1, 168,
    CANCEL, 60, 168,
    0
};

void files_info(const char *name, char type)
{
    unsigned char h, r;
    static char old[97];
    if (type != 'F') {
        shell_say("A folder has no info block.");
        return;
    }
    if (!shell_is_cvt(name)) {
        shell_say("A plain file has no info block.");
        return;
    }
    play_busy = 1;
    h = FOpen((void *)name, 'r');
    r = h >= 2 && FRead(h, ib, 30) == 30 && FRead(h, line, 96) == 96
        && !memcmp(line + 3, " formatted GEOS file", 20) && FRead(h, line, 96) == 96
        && FRead(h, line, 32) == 32 && FRead(h, ib + 30, 254) == 254;
    if (h >= 2)
        FClose(h);
    play_busy = 0;
    if (!r) {
        shell_warn("Its info block cannot be read.");
        return;
    }
    text(desc, &INF(160), 95);
    strcpy(old, desc);
    r5 = (unsigned int)desc;
    r = DoDlgBox((void *)&infoBox);
    XCALL(bIc2, info_unicon, FV)();
    if ((r != OK && r != DBGETSTRING) || !strcmp(old, desc))
        return;
    memset(line, 0, 96);
    strcpy(line, desc);
    play_busy = 1;
    h = FOpen((void *)name, 'm');
    r = h < 2 || FSeek(h, 412, 0) || FWrite(h, line, 96);
    if (h >= 2)
        FClose(h);
    play_busy = 0;
    if (r) {
        shell_err("Cannot write it:", r);
        return;
    }
    strcpy(line, "SHELL INFO ");
    strcat(line, name);
    strcat(line, ": ");
    strcat(line, desc);
    LogText(line);
}
