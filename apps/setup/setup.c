/* Veranda Setup: a card from before DECISIONS V71 moved into its layout,
   once (MIT licence, see LICENSE).

   Before V71 everything lived in /VERANDA: the system, the applications,
   the settings and the scraps, the trash, and the documents saved there.
   Now (vrpath.h):
       /VERANDA            VERANDA.PRG, VERANDA.SYS, RBOOT, SHELL.cvt
       /VERANDA/APPS       the applications and desk accessories
       /VERANDA/FONTS      the fonts
       /VERANDA/.SYSTEM    the system's data, the trash (hidden)
       /DOCUMENTS          the user's files
   The shell starts Setup (it lives in /VERANDA) at its first start after
   Veranda starts when .SYSTEM has no LAYOUT.LOG. Setup reads /VERANDA's
   listing whole and moves:
     - the system's files by name (Veranda Prefs, Veranda Alarms, the
       scraps, Note File, the albums, Dex Cards, Appointments, SHELL.DSK,
       Veranda Solitaire Stats, TERM.CFG, TERM.BOOK, DEX.TEL) to .SYSTEM;
     - the trash's contents (TRASH, folders too) to .SYSTEM/TRASH;
     - GEOS files (.cvt) by their type: applications, desk accessories and
       auto-exec files to APPS (one APPS already has, a newer copy put
       there by hand, to .SYSTEM/OLD instead); fonts to FONTS; other
       SYSTEM files to .SYSTEM; drivers stay; the rest (documents) to
       /DOCUMENTS;
     - other files: programs (.PRG, or no extension) stay; the rest
       (documents: .TXT, .BMP, .MOD ...) to /DOCUMENTS.
   Folders other than APPS, FONTS and TRASH stay where they are, as do
   VERANDA.PRG, AUTOBOOT.X16 (its copy, for BOOT), VERANDA.SYS, RBOOT,
   README.txt (the package's),
   SHELL.cvt, DESKTOP.cvt, AUTOSTART.cvt
   and Setup itself. Nothing is deleted: a file is renamed into its new
   folder (from the root, relative paths: DECISIONS V61), or, with a path
   too long for a rename, copied, its size checked, and only then the old
   one deleted; a name already taken in the new folder gets ~2 ... ~9
   (name~2.ext: both kept), and with all of those taken the file stays.
   A folder that is left empty (TRASH) is removed.

   Then it writes LAYOUT.LOG in .SYSTEM (what moved where: the mark that
   it ran), keeps /DOCUMENTS as the shell's folder (SysPrefs DESK_SET, so
   the shell does not start it again before the next start of Veranda)
   and quits to the shell. Each move is also on the emulator's console
   ("SETUP MOVED ..."), for the gate (tools/gate_layout.sh). */
#include <veranda.h>
#include <string.h>
#include <vrpath.h>
#include <vrwin.h>
#include <theme.h>

#define LOGMAX  6144
#define POOL    6144
#define NAMEMAX 40

static char logbuf[LOGMAX];
static unsigned int loglen;
static char pool[POOL];                 /* the listings: 'D' or 'F', the name, 0 */
static unsigned int ptop;
static unsigned char buf[4096];         /* a copy's blocks */
static unsigned char de[128];
static char ra[72], rb[72], tname[NAMEMAX + 4], line[160];
static unsigned char moved, kept, failed;
static unsigned int texty = 64;         /* the next line's band (UI font, 14 lines a line) */
/* (Sunroom, V149) the window: the screen, a title band, a status bar */
static const struct vrwin win = { 0, 0, 80, 60, 0, 2, VW_FRAME };

/* s in the UI font at x, its 16-line band from y */
static void text(const char *s, unsigned int x, unsigned int y, unsigned char bold)
{
    UseFont(FONT_UI);
    currentMode = bold ? SET_BOLD : 0;
    WPutString((void *)s, x, y + 2 + baselineOffset);
    currentMode = 0;
    UseSystemFont();
}

/*---------------------------------------------------------------- names */

static unsigned char lower(unsigned char c)
{
    return c >= 'A' && c <= 'Z' ? c + 32 : c;
}

static unsigned char same(const char *a, const char *b)
{
    while (*a && lower(*a) == lower(*b))
        ++a, ++b;
    return lower(*a) == lower(*b);
}

/* the extension (after the last dot), "" without one */
static const char *ext(const char *n)
{
    const char *d = strrchr(n, '.');
    return d && d != n ? d + 1 : "";
}

static unsigned char inlist(const char *n, const char *const *l)
{
    for (; *l; ++l)
        if (same(n, *l))
            return 1;
    return 0;
}

static const char *const stays[] = {
    "VERANDA.PRG", "VERANDA.SYS", "RBOOT", "SHELL.cvt", "DESKTOP.cvt",
    "AUTOSTART.cvt", "AUTOBOOT.X16", "README.txt", VR_SETUP ".cvt", 0
};
static const char *const sysfiles[] = {
    "Veranda Prefs.cvt", "Veranda Alarms.cvt", "Text  Scrap.cvt", "Photo Scrap.cvt",
    "Note File.cvt", "Photo Album.cvt", "Text Album.cvt", "Dex Cards.cvt",
    "Appointments.cvt", "SHELL.DSK", "Veranda Solitaire Stats", "TERM.CFG",
    "TERM.BOOK", "DEX.TEL", 0
};

/*---------------------------------------------------------------- the log */

static void say(const char *s)
{
    static char word[9];
    unsigned int l = strlen(s);
    LogText((void *)s);
    if (loglen + l + 1 < LOGMAX) {
        memcpy(logbuf + loglen, s, l);
        loglen += l;
        logbuf[loglen++] = 13;
    }
    if (texty < 446) {                  /* on the screen, as far as it goes: */
        if (l > 8 && s[7] == ' ' && (s[0] >= 'a' || s[0] == 'F' || s[0] == ' ')) {
            memcpy(word, s, 8);         /* "moved   ...": the word, the rest in a column */
            text(word, 16, texty, 0);
            text(s + 8, 76, texty, 0);
        } else
            text(s, 16, texty, 0);
        texty += 14;
    }
}

/* line = a b c d */
static void say4(const char *a, const char *b, const char *c, const char *d)
{
    strcpy(line, a);
    strcat(line, b);
    strcat(line, c);
    strcat(line, d);
    say(line);
}

/*---------------------------------------------------------------- files */

/* out = "/" rel (the root: "/") */
static char *absp(char *out, const char *rel)
{
    out[0] = '/';
    strcpy(out + 1, rel);
    return out;
}

/* rel "/" name, into out; 0 if too long */
static unsigned char join(char *out, const char *rel, const char *name)
{
    if (strlen(rel) + strlen(name) + 2 > 61)
        return 0;
    strcpy(out, rel);
    strcat(out, "/");
    strcat(out, name);
    return 1;
}

/* a name in folder rel (relative to the root) */
static unsigned char exists(const char *rel, const char *name)
{
    static char p[64];
    unsigned char h, r = 0;
    if (ChDir(absp(p, rel)))
        return 0;
    h = FOpen((void *)name, 'r');
    if (h >= 2 && h <= 9) {
        FClose(h);
        r = dosStatus < 20;
    }
    if (!r && ChDir((void *)name) == 0)
        r = 1;
    return r;
}

/* tname = name, or name~2 ... name~9 (before the extension) when taken in
   folder rel; 0 if all are taken */
static unsigned char free_name(const char *rel, const char *name)
{
    const char *dot = strrchr(name, '.');
    unsigned char b, k;
    strcpy(tname, name);
    for (k = '2'; exists(rel, tname); ++k) {
        if (k > '9')
            return 0;
        b = dot && dot != name ? dot - name : strlen(name);
        if (b > 14)
            b = 14;
        memcpy(tname, name, b);
        tname[b] = '~';
        tname[b + 1] = k;
        strcpy(tname + b + 2, dot && dot != name ? dot : "");
    }
    return 1;
}

/* the size of an open file */
static unsigned long size_of(unsigned char h)
{
    FSize(h);
    return (unsigned long)r1 << 16 | r0;
}

/* name in folder s copied to tname in folder d, its size checked, then
   deleted: 0 if done (both are there if it failed) */
static unsigned char copy_move(const char *s, const char *d, const char *name)
{
    static char p[64];
    unsigned char a, b, e = 0;
    unsigned int n;
    unsigned long want, got = 0;
    ChDir(absp(p, s));
    a = FOpen((void *)name, 'r');
    if (a < 2 || a > 9 || dosStatus >= 20)
        return 1;
    want = size_of(a);
    ChDir(absp(p, d));
    b = FOpen(tname, 'w');
    if (b < 2 || b > 9 || dosStatus >= 20) {
        FClose(a);
        return 1;
    }
    while (!e && (n = FRead(a, buf, sizeof buf)) != 0) {
        e = FWrite(b, buf, n);
        got += n;
    }
    FClose(a);
    if (FClose(b))
        e = 1;
    if (e || got != want) {
        FDelete(tname);                 /* (the copy; the file stays) */
        return 1;
    }
    ChDir(absp(p, s));
    return FDelete((void *)name) ? 2 : 0;
}

/* file name of folder s (relative to the root) moved into folder d */
static void move_file(const char *s, const char *d, const char *name)
{
    unsigned char e;
    if (!free_name(d, name)) {
        ++kept;
        say4("left    ", s, "/", name);
        say("        (its name is taken in the new folder)");
        return;
    }
    if (!join(ra, s, name) || !join(rb, d, tname))
        e = 1;
    else if (strlen(ra) + strlen(rb) + 3 <= 70) {
        ChDir("/");
        e = FRename(ra, rb);
        if (!e && !exists(d, tname))
            e = 1;
    } else
        e = copy_move(s, d, name);
    if (e) {
        ++failed;
        say4("FAILED  ", s, "/", name);
        return;
    }
    ++moved;
    strcpy(line, "moved   ");
    strcat(line, ra);
    strcat(line, " to ");
    strcat(line, rb);
    say(line);
}

/* folder s's listing into the pool: its first entry's offset (ptop
   after the last); 0xFFFF if it does not open */
static unsigned int list(const char *s)
{
    static char p[64];
    unsigned int first = ptop, l;
    if (ChDir(absp(p, s)) || DirOpen("*"))
        return 0xFFFF;
    while (DirNext(de) == 0) {
        char *n = (char *)de + 3;
        l = strlen(n);
        if (!l || l > NAMEMAX || (n[0] == '.' && (l == 1 || (l == 2 && n[1] == '.'))))
            continue;
        if (ptop + l + 2 > POOL)
            continue;                   /* (no room: it stays) */
        pool[ptop++] = de[0];
        memcpy(pool + ptop, n, l + 1);
        ptop += l + 1;
    }
    return first;
}

/* folder s's contents moved into folder d (made), folders too; s
   removed if it is empty after */
static void move_dir(const char *s, const char *d, unsigned char depth)
{
    static char p[64];
    char ss[64], dd[64];
    unsigned int i, top, first;
    ChDir("/");
    MkDir((void *)d);
    i = first = list(s);
    if (i == 0xFFFF)
        return;
    top = ptop;
    while (i < top) {
        char t = pool[i];
        const char *n = pool + i + 1;
        i += strlen(n) + 2;
        if (t == 'D') {
            if (depth < 6 && join(ss, s, n) && join(dd, d, n))
                move_dir(ss, dd, depth + 1);
            else {
                ++kept;
                say4("left    ", s, "/", n);
            }
        } else
            move_file(s, d, n);
    }
    ptop = first;                       /* (this listing's room back) */
    ChDir("/");
    if (RmDir((void *)s) == 0)
        say4("removed ", s, " (empty)", "");
    (void)p;
}

/*---------------------------------------------------------------- the card */

/* a GEOS file's type (its CVT entry's byte 22); 0xFF if it does not open */
static unsigned char geos_type(const char *name)
{
    unsigned char h, t = 0xFF;
    ChDir(VR_SYSDIR);
    h = FOpen((void *)name, 'r');
    if (h >= 2 && h <= 9) {
        if (dosStatus < 20 && FRead(h, buf, 30) == 30)
            t = buf[22];
        FClose(h);
    }
    return t;
}

#define S_ "VERANDA"
static void migrate(void)
{
    unsigned int i, top;
    unsigned char t;
    ChDir("/");
    MkDir(S_ "/APPS");
    MkDir(S_ "/.SYSTEM");
    MkDir(S_ "/FONTS");
    MkDir((void *)(VR_DOCSDIR + 1));
    ptop = 0;
    i = list(S_);
    if (i == 0xFFFF)
        return;
    top = ptop;
    while (i < top) {
        char k = pool[i];
        const char *n = pool + i + 1;
        const char *x = ext(n);
        i += strlen(n) + 2;
        if (n[0] == '.')
            continue;                   /* (.SYSTEM; hidden files) */
        if (k == 'D') {
            if (same(n, "TRASH"))
                move_dir(S_ "/TRASH", S_ "/.SYSTEM/TRASH", 0);
            else if (!same(n, "APPS") && !same(n, "FONTS")) {
                ++kept;
                say4("left    " S_ "/", n, " (a folder)", "");
            }
            continue;
        }
        if (inlist(n, stays))
            continue;
        if (inlist(n, sysfiles)) {
            move_file(S_, S_ "/.SYSTEM", n);
            continue;
        }
        if (same(x, "cvt")) {
            t = geos_type(n);
            if (t == APPLICATION || t == DESK_ACC || t == AUTO_EXEC) {
                if (exists(S_ "/APPS", n)) {    /* (APPS has a newer copy) */
                    ChDir("/");
                    MkDir(S_ "/.SYSTEM/OLD");
                    move_file(S_, S_ "/.SYSTEM/OLD", n);
                } else
                    move_file(S_, S_ "/APPS", n);
            }
            else if (t == FONT)
                move_file(S_, S_ "/FONTS", n);
            else if (t == SYSTEM)
                move_file(S_, S_ "/.SYSTEM", n);
            else if (t == 0xFF || (t >= 9 && t <= 13) || t == 15) {
                ++kept;                 /* (unreadable; drivers, boot files) */
                say4("left    " S_ "/", n, "", "");
            } else
                move_file(S_, VR_DOCSDIR + 1, n);
            continue;
        }
        if (!x[0] || same(x, "prg"))
            continue;                   /* programs stay */
        move_file(S_, VR_DOCSDIR + 1, n);
    }
}

static void numtxt(char *p, unsigned char n)
{
    if (n >= 100)
        *p++ = '0' + n / 100;
    if (n >= 10)
        *p++ = '0' + n / 10 % 10;
    *p++ = '0' + n % 10;
    *p = 0;
}

int main(void)
{
    static unsigned char dk[64];
    static char nb[3][4];
    unsigned char h;
    dispBufferOn = ST_WR_FORE | ST_WR_BACK;
    theme_load();
    theme_palette();
    vr_win(&win, "Veranda Setup");
    text("Your files go into their new folders.", 16, 22, 1);
    text("Applications: /VERANDA/APPS.  Documents: /DOCUMENTS.  Settings: hidden.", 16, 40, 0);
    LogText("SETUP RUNNING");
    if (ChDir(VR_SYSDIR)) {
        EnterDeskTop();
        return 0;
    }
    say("Veranda Setup: the card's new folders");
    migrate();
    numtxt(nb[0], moved);
    numtxt(nb[1], kept);
    numtxt(nb[2], failed);
    strcpy(line, "SETUP DONE: ");
    strcat(line, nb[0]);
    strcat(line, " moved, ");
    strcat(line, nb[1]);
    strcat(line, " left, ");
    strcat(line, nb[2]);
    strcat(line, " failed");
    say(line);
    vr_win_status(&win, line + 12, "Done");  /* (the counts) */
    vr_cd(VR_DATA);
    h = FOpen(VR_SETUP_LOG, 'w');
    if (h >= 2 && h <= 9) {
        FWrite(h, logbuf, loglen);
        FClose(h);
    }
    /* the shell's folder: /DOCUMENTS (and no second start of Setup) */
    SysPrefs(DESK_GET, dk);
    memset(dk, 0, 62);
    strcpy((char *)dk, vr_cd(VR_DOCS));
    SysPrefs(DESK_SET, dk);
    EnterDeskTop();
    return 0;
}
