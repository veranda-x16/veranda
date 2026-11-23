/* Veranda Update: the card's files, the swap and Undo (overlay 3;
   DECISIONS V130; what they do: job.c's comment).

   The paths are from the card's top without the first "/"
   ("VERANDA/APPS/Paint.cvt"). The file calls change to the file's folder
   (pa) and take its name (pn), both copied to main RAM, where the kernel
   reads them; a string of this overlay handed to the kernel goes through
   K() (main.c) for the same reason. Overlay 1 (job.c) and main.c call
   the _o functions through main.c's wrappers.

   MIT licence (see LICENSE). */
#include <veranda.h>
#include <string.h>
#include "up.h"

#pragma code-name ("OVERLAY3")
#pragma rodata-name ("OVL3RO")      /* (a string the kernel reads goes through K(): main RAM) */

static char pa[72];                     /* the folder a file call works in */
static char pn[64];                     /* the file's name there */
#pragma bss-name ("OVL3BSS")
static char pb[72], po[72], ps[72];     /* paths: scratch, a backup's, a source's (overlay 3's own) */
#pragma bss-name ("BSS")
static char oldb[16];                   /* the backup's folder (the build replaced) */

/* the system's files (Undo: a restart after them) */
static const char *const sysfiles[] = {
    "VERANDA/VERANDA.PRG", "VERANDA/AUTOBOOT.X16", "VERANDA/VERANDA.SYS", "VERANDA/RBOOT", "VERANDA/SHELL.cvt"
};

/*---------------------------------------------------------------- files */
static const char *__fastcall__ base_(const char *p)
{
    const char *s = strrchr(p, '/');
    return s ? s + 1 : p;
}

/* "/" and p's first n characters less their "/" into pa */
static void __fastcall__ dir_n(const char *p, unsigned char n)
{
    pa[0] = '/';
    pa[1] = 0;
    if (n > 1) {
        memcpy(pa + 1, p, n - 1);
        pa[n] = 0;
    }
}

/* p's folder into pa ("/VERANDA/APPS"), its name into pn (returned) */
static const char *__fastcall__ cd_of(const char *p)
{
    const char *b = base_(p);
    dir_n(p, b - p);
    strncpy(pn, b, sizeof pn - 1);
    pn[sizeof pn - 1] = 0;
    return pn;
}

static unsigned char __fastcall__ h_ok(unsigned char h)
{
    return h >= 2 && h <= 9 && dosStatus < 20;
}

/* a file at p */
unsigned char __fastcall__ exists_o(const char *p)
{
    unsigned char h;
    const char *n = cd_of(p);
    if (ChDir(pa))
        return 0;
    h = FOpen((char *)n, 'r');
    if (!h_ok(h))
        return 0;
    FClose(h);
    return 1;
}

void __fastcall__ del_o(const char *p)
{
    const char *n = cd_of(p);
    if (!ChDir(pa))
        FDelete((char *)n);
}

/* p's folders made (they may be there) */
void __fastcall__ mkdirs_o(const char *p)
{
    unsigned char i;
    ChDir(K("/"));
    for (i = 0; p[i]; ++i)
        if (p[i] == '/') {
            memcpy(pa, p, i);
            pa[i] = 0;
            MkDir(pa);
        }
}

/* file p, whose size must be size, against crc: 0 not there, 1 equal, 2 not */
unsigned char __fastcall__ fcheck_o(const char *p, unsigned long size, unsigned long crc)
{
    unsigned char h;
    unsigned int n;
    unsigned long got = 0;
    const char *nm = cd_of(p);
    if (ChDir(pa))
        return 0;
    h = FOpen((char *)nm, 'r');
    if (!h_ok(h))
        return 0;
    FSize(h);
    if (((unsigned long)r1 << 16 | r0) != size) {
        FClose(h);
        return 2;
    }
    crc_start();
    while ((n = FRead(h, iobuf, sizeof iobuf)) != 0) {
        crc_add(iobuf, n);
        got += n;
    }
    FClose(h);
    return got == size && crc_end() == crc ? 1 : 2;
}

/* a copied to b: 1 if done */
static unsigned char __fastcall__ cp(const char *a, const char *b)
{
    unsigned char ha, hb, e = 0;
    unsigned int n;
    unsigned long want, got = 0;
    const char *nm = cd_of(a);
    if (ChDir(pa))
        return 0;
    ha = FOpen((char *)nm, 'r');
    if (!h_ok(ha))
        return 0;
    FSize(ha);
    want = (unsigned long)r1 << 16 | r0;
    nm = cd_of(b);
    if (ChDir(pa)) {
        FClose(ha);
        return 0;
    }
    hb = FOpen((char *)nm, 'w');
    if (!h_ok(hb)) {
        FClose(ha);
        return 0;
    }
    while (!e && (n = FRead(ha, iobuf, sizeof iobuf)) != 0) {
        e = FWrite(hb, iobuf, n);
        got += n;
    }
    FClose(ha);
    if (FClose(hb))
        e = 1;
    if (e || got != want) {
        FDelete((char *)nm);
        return 0;
    }
    return 1;
}

/* a moved to b (b's folder there): a rename from their common folder, or
   a copy and a delete when the command would be longer than CMDR-DOS's
   "R:new=old" takes (70 characters): 1 if done */
static unsigned char __fastcall__ mv(const char *a, const char *b)
{
    unsigned char i, k = 0;
    for (i = 0; a[i] && a[i] == b[i]; ++i)
        if (a[i] == '/')
            k = i + 1;
    if (strlen(a + k) + strlen(b + k) + 3 <= 70) {
        dir_n(a, k);
        if (!ChDir(pa) && !FRename(K(a + k), K(b + k)) && dosStatus < 20 && exists_o(b))
            return 1;
    }
    if (!cp(a, b))
        return 0;
    del_o(a);
    return 1;
}

/* text into file p */
static unsigned char __fastcall__ fput(const char *p, const char *text)
{
    unsigned char h, e;
    const char *nm = cd_of(p);
    if (ChDir(pa))
        return 0;
    h = FOpen((char *)nm, 'w');
    if (!h_ok(h))
        return 0;
    e = FWrite(h, (char *)text, strlen(text));
    if (FClose(h))
        e = 1;
    return !e;
}


/*---------------------------------------------------------------- the swap */
/* (an error: the job ends, the window says why) */
static void __fastcall__ stop(const char *why)
{
    job = J_NONE;
    ui_all();
    say(why);
}

/* a text file into the RAM bank tbank + 2 (8000 bytes at most): its length */
static unsigned int __fastcall__ bload(const char *p)
{
    unsigned char h;
    unsigned int n, at = 0;
    const char *nm = cd_of(p);
    if (ChDir(pa))
        return 0;
    h = FOpen((char *)nm, 'r');
    if (!h_ok(h))
        return 0;
    while (at < 8000 && (n = FRead(h, iobuf, at + sizeof iobuf > 8000 ? 8000 - at : sizeof iobuf)) != 0) {
        BankCopy(iobuf, BANKMEM + at, n, 0, tbank + 2);
        at += n;
    }
    FClose(h);
    return at;
}

/* the line at *at of the text in the bank (len bytes) into line: 0 at the end */
static unsigned char __fastcall__ bline(unsigned int *at, unsigned int len)
{
    unsigned int k;
    unsigned char i;
    if (*at >= len)
        return 0;
    k = len - *at;
    if (k > 100)
        k = 100;
    BankCopy(BANKMEM + *at, iobuf, k, tbank + 2, 0);
    for (i = 0; i < k && iobuf[i] != '\n'; ++i)
        line[i] = iobuf[i];
    line[i] = 0;
    if (i && line[i - 1] == '\r')
        line[i - 1] = 0;
    *at += i + 1;
    return 1;
}

/* the backup of p in OLD/<b> into po */
static void __fastcall__ old_path(const char *b, const char *p)
{
    strcpy(po, SYS_OLD);
    strcat(po, b);
    strcat(po, "/");
    strcat(po, base_(p));
}

/* OLD/<b>/<name> into pb */
static void __fastcall__ old_file(const char *b, const char *name)
{
    strcpy(pb, SYS_OLD);
    strcat(pb, b);
    strcat(pb, "/");
    strcat(pb, name);
}

static unsigned char __fastcall__ find(const char *p)
{
    unsigned char i;
    for (i = 0; i < nents; ++i) {
        ent_get(i);
        if (!strcmp(E.path, p))
            return i;
    }
    return 0xFF;
}

static unsigned char __fastcall__ is_sys(const char *p)
{
    unsigned char i;
    for (i = 0; i < sizeof sysfiles / sizeof sysfiles[0]; ++i)
        if (!strcmp(p, sysfiles[i]))
            return 1;
    return 0;
}

static unsigned char sys_touched;

/* E is to be put in place in this pass (0: the other files, 1: the system's) */
static unsigned char __fastcall__ todo(unsigned char pass)
{
    return (E.st == S_CHANGED || E.st == S_NEW) && (E.kind == K_SYSTEM) == pass;
}

/* the first line of file p into oldb ("" none) */
static void __fastcall__ fline(const char *p)
{
    unsigned int at = 0, n = bload(p);
    oldb[0] = 0;
    if (n && bline(&at, n) && strlen(line) < sizeof oldb)
        strcpy(oldb, line);
}

/* a backup folder (OLD/<b>) emptied by its UNDO.LST and removed */
static void __fastcall__ old_clear(const char *b)
{
    unsigned int at = 0, n;
    static char keep[16];
    strcpy(keep, b);
    old_file(keep, "UNDO.LST");
    n = bload(pb);
    while (bline(&at, n))
        if ((line[0] == 'R' || line[0] == 'N') && line[1] == ' ') {
            old_path(keep, line + 2);
            del_o(po);
        }
    old_file(keep, "UNDO.LST");
    del_o(pb);
    ChDir(K(OLD_DIR));
    RmDir(keep);
}

/* UPD emptied and removed */
static void upd_clear(void)
{
    static unsigned char de[128];
    static char names[8][16];
    unsigned char k, n, i;
    for (k = 0; k < 24; ++k) {          /* (no listing open while deleting: a few names read, deleted, again) */
        n = 0;
        if (ChDir(K(UPD_DIR)) || DirOpen(K("*")))
            return;
        while (!DirNext(de))
            if (de[0] == 'F' && n < 8 && strlen((char *)de + 3) < 16)
                strcpy(names[n++], (char *)de + 3);
        for (i = 0; i < n; ++i)
            FDelete(names[i]);
        if (n < 8)
            break;
    }
    ChDir(K(VR_DATADIR));
    RmDir(K("UPD"));
}

/* UNDO.LST's steps done (oldb: the backup's folder); each looks before it
   moves, so it may run again after a cut-short one */
static unsigned char swap_run(void)
{
    unsigned int at = 0, n;
    unsigned char i, ok = 1, isman;
    static char p[64];
    old_file(oldb, "UNDO.LST");
    n = bload(pb);
    sys_touched = 0;
    while (bline(&at, n)) {
        if ((line[0] != 'R' && line[0] != 'N') || line[1] != ' ')
            continue;
        strcpy(p, line + 2);
        isman = !strcmp(p, "VERANDA/UPDATE.LST");
        i = isman ? 0xFF : find(p);
        if (!isman && i == 0xFF)
            continue;
        if (is_sys(p))
            sys_touched = 1;
        if (line[0] == 'R') {
            old_path(oldb, p);
            if (!exists_o(po) && exists_o(p) && !mv(p, po)) {
                ok = 0;
                up_log("UP MOVE FAILED ", p);
                continue;
            }
        }
        if (isman)
            strcpy(ps, SYS_UPD "NEW.LST");
        else {
            strcpy(ps, SYS_UPD);
            strcat(ps, E.asset);
        }
        if (!exists_o(ps))
            continue;                   /* (done before the cut) */
        mkdirs_o(p);
        if (exists_o(p))
            del_o(p);
        if (!(i != 0xFF && E.shared ? cp(ps, p) : mv(ps, p))) {
            ok = 0;
            up_log("UP PUT FAILED ", p);
            continue;
        }
        up_log(is_sys(p) ? "UP SWAP SYSTEM " : "UP SWAP ", p);
    }
    return ok;
}

/* the swap's end: b its backup's folder */
static void __fastcall__ swap_end(const char *b, unsigned char ok)
{
    static char prev[16], cur_[16];
    strcpy(cur_, b);
    del_o(SYS_UPD "SWAP.ON");
    /* the backup before this one deleted: one undo is kept */
    fline(SYS_OLD "LAST.UPD");
    strcpy(prev, oldb);
    if (!fput(SYS_OLD "LAST.UPD", cur_))
        ok = 0;
    if (prev[0] && strcmp(prev, cur_))
        old_clear(prev);
    upd_clear();
    man_installed();
    checked = 0;
    ui_all();
    if (!ok) {
        up_log("UP SWAP INCOMPLETE", "");
        up_message("Some files could not be put in place.", "Undo last update puts the card back.");
        return;
    }
    strcpy(line, "Updated to build ");
    strcat(line, ibuild);
    strcat(line, " (");
    strcat(line, idate);
    strcat(line, ").");
    say(line);
    up_log("UP DONE ", ibuild);
    if (sys_touched)
        up_restart();
    else
        up_message(line, "The new versions start the next time they are opened.");
}

void swap_go_o(void)
{
    unsigned char i, pass, h;
    static char b[16];
    strcpy(b, ibuild[0] ? ibuild : "unknown");
    strcpy(oldb, b);
    say("Putting the new files in place ...");
    up_log("UP SWAP START", "");
    old_file(b, "UNDO.LST");
    mkdirs_o(pb);
    if (exists_o(pb))
        old_clear(b);                   /* (a backup of the same build, from before) */
    old_file(b, "UNDO.LST");
    mkdirs_o(pb);
    /* (the manifest's step last; looked at before UNDO.LST is open) */
    strcpy(ps, exists_o("VERANDA/UPDATE.LST") ? "R VERANDA/UPDATE.LST\n" : "N VERANDA/UPDATE.LST\n");
    cd_of(pb);
    ChDir(pa);
    h = FOpen(K("UNDO.LST"), 'w');
    if (!h_ok(h)) {
        stop("The card could not be written (/VERANDA/.SYSTEM/OLD).");
        return;
    }
    strcpy(line, "VERANDA-UNDO 1\nfrom ");
    strcat(line, b);
    strcat(line, "\nto ");
    strcat(line, nbuild);
    strcat(line, "\n");
    FWrite(h, line, strlen(line));
    for (pass = 0; pass < 2; ++pass)
        for (i = 0; i < nents; ++i) {
            ent_get(i);
            if (!todo(pass))
                continue;
            line[0] = E.st == S_CHANGED ? 'R' : 'N';
            line[1] = ' ';
            strcpy(line + 2, E.path);
            strcat(line, "\n");
            FWrite(h, line, strlen(line));
        }
    FWrite(h, K(ps), strlen(ps));
    if (FClose(h)) {
        stop("The card could not be written (/VERANDA/.SYSTEM/OLD).");
        return;
    }
    fput(SYS_OLD "LAST.UPD", b);        /* (Undo can put a cut-short swap back) */
    fput(SYS_UPD "SWAP.ON", b);
    strcpy(oldb, b);
    i = swap_run();
    swap_end(b, i);
}

unsigned char job_resume_swap_o(void)
{
    static char b[16];
    if (!exists_o(SYS_UPD "SWAP.ON"))
        return 0;
    fline(SYS_UPD "SWAP.ON");
    if (!oldb[0])
        return 0;
    strcpy(b, oldb);
    if (!up_confirm("An update was cut short while its files", "were put in place. Finish it now?"))
        return 1;
    if (man_load(K(UPD_DIR), K("NEW.LST")))
        nents = 0;                      /* (its manifest already in place: the rest is cleaning up) */
    up_log("UP RESUME SWAP ", b);
    strcpy(oldb, b);
    swap_end(b, swap_run());
    return 1;
}

/*---------------------------------------------------------------- Undo */
unsigned char undo_ready_o(void)
{
    fline(SYS_OLD "LAST.UPD");
    return oldb[0] != 0;
}

void job_undo_o(void)
{
#pragma bss-name ("OVL3BSS")
    static unsigned int at[ENT_MAX + 2];   /* (overlay 3's: 328 bytes) */
#pragma bss-name ("BSS")
    static char b[16], p[64], to[16];
    unsigned int pos = 0, here, n;
    unsigned char k = 0;
    if (job)
        return;
    if (!undo_ready_o()) {
        up_message("Nothing to undo:", "no update was made on this card (or it was undone).");
        return;
    }
    strcpy(b, oldb);
    old_file(b, "UNDO.LST");
    n = bload(pb);
    to[0] = 0;
    while (k < ENT_MAX + 2) {
        here = pos;
        if (!bline(&pos, n))
            break;
        if (!memcmp(line, "to ", 3) && strlen(line) < 19)
            strcpy(to, line + 3);
        if ((line[0] == 'R' || line[0] == 'N') && line[1] == ' ')
            at[k++] = here;
    }
    if (!k) {
        up_message("The last update's backup is not complete:", "it cannot be undone.");
        return;
    }
    strcpy(line, "Undo the update to build ");
    strcat(line, to);
    strcat(line, "?");
    strcpy(p, "Back to build ");
    strcat(p, b);
    strcat(p, ": the files it replaced come back.");
    if (!up_confirm(line, p))
        return;
    say("Putting the old files back ...");
    sys_touched = 0;
    while (k--) {
        pos = at[k];
        bline(&pos, n);
        strcpy(p, line + 2);
        if (is_sys(p))
            sys_touched = 1;
        if (line[0] == 'N') {
            if (exists_o(p))
                del_o(p);
            up_log("UP UNDO NEW ", p);
            continue;
        }
        old_path(b, p);
        if (!exists_o(po))
            continue;
        if (exists_o(p))
            del_o(p);
        mkdirs_o(p);
        if (!mv(po, p)) {
            up_log("UP UNDO FAILED ", p);
            continue;
        }
        up_log("UP UNDO ", p);
    }
    old_clear(b);
    del_o(SYS_OLD "LAST.UPD");
    if (exists_o(SYS_UPD "SWAP.ON"))
        upd_clear();
    man_installed();
    checked = 0;
    ui_all();
    strcpy(line, "Undone: back to build ");
    strcat(line, ibuild[0] ? ibuild : b);
    strcat(line, ".");
    say(line);
    up_log("UP UNDONE ", b);
    if (sys_touched)
        up_restart();
    else
        up_message(line, "The old versions start the next time they are opened.");
}
