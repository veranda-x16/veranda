/* Disk Tools: Clean up (DECISIONS V119).

   The trash: the shell's (shell/files.c, V61, V71): /VERANDA/.SYSTEM/TRASH
   (the data folder's TRASH: vrpath.h's VR_DATA, /TRASH on a card with no
   /VERANDA). Its top-level items are listed; "Empty the trash..." asks
   (OK or Cancel) and then deletes everything in it as the shell's disk >
   empty trash does: files with FDelete, folders emptied from the deepest
   up and removed with RmDir; the TRASH folder itself stays; the trash's
   sound (SND_TRASH).

   Leftovers: the files Veranda's own programs leave behind when a save is
   cut short, looked for on the whole card (walk.c, a folder a pass; the
   trash is left out):
     ~VEDIT.TMP   Veranda Edit's save (textkit: the text written there,
                  then renamed over the document): may hold the text that
                  was being saved
     ~VBASIC.TMP  VeraBASIC's, the same
     NAME.tmp     beside NAME.cvt: the Font Editor's save of NAME (without
                  the .cvt beside it, it is the only copy: not offered)
     ASK.TMP      beside ASK.CFG in the data folder: Veranda Ask's
                  credentials being written (without ASK.CFG it holds the
                  sign-in: not offered)
   Each kind is listed with its files and deleted only after its own OK;
   nothing else on the card is ever deleted.

   Its code is overlay 1 (mapped for good, as appBank), its texts and
   buffers in main RAM; its RAM banks' contents go through bget and bput
   (BankCopy: code at $A000 cannot map another bank there).
   MIT licence (see LICENSE). */
#include <veranda.h>
#include <string.h>
#include <vrpath.h>
#include "dt.h"
#pragma code-name ("OVERLAY1")

#define MAXI   12               /* the trash's items shown */
#define MAXC   48               /* leftovers kept: 128 bytes each (folder, name) */
#define Y0     (BODY_TOP + 8)

enum { K_EDIT, K_VB, K_FONT, K_ASK, K_N };
static const char *const kname[K_N] = {
    "Veranda Edit's unfinished saves (~VEDIT.TMP)",
    "VeraBASIC's unfinished saves (~VBASIC.TMP)",
    "The Font Editor's unfinished saves (NAME.tmp beside NAME.cvt)",
    "Veranda Ask's unfinished settings (ASK.TMP beside ASK.CFG)"
};
static const char *const kshort[K_N] = {
    "as ~VEDIT.TMP?", "as ~VBASIC.TMP?", "as NAME.tmp?", "as ASK.TMP?"
};
static const char *const knote[K_N] = {
    "(each may hold the text that was being saved: open it first if a text is missing)",
    "(each may hold the program that was being saved)",
    "(the font itself is NAME.cvt)",
    "(ASK.CFG holds the settings)"
};

static char trash[64], datap[64];
static unsigned char tn, tfold, tlisted;
static unsigned long tsize;
static char tnames[MAXI][24];

static unsigned char cbank, nc, kcount[K_N], scanned;
static unsigned char ckind[MAXC];

/* a folder's candidates waiting for their sibling's check */
static char pend[4][64];
static unsigned char pkind[4], npend;

static unsigned char __fastcall__ same(const char *a, const char *b)
{
    unsigned char c, d;
    for (;; ++a, ++b) {
        c = *a;
        d = *b;
        if (c >= 'a' && c <= 'z')
            c -= 32;
        if (d >= 'a' && d <= 'z')
            d -= 32;
        if (c != d)
            return 0;
        if (!c)
            return 1;
    }
}

static void paths(void)
{
    const char *d = vr_cd(VR_DATA);
    strcpy(datap, d);
    strcpy(trash, d[1] ? d : "");
    strcat(trash, "/TRASH");
}

/*---------------------------------------------------------------- the trash */
static void tentry(void)
{
    char *p;
    if (!went.name[0])
        return;
    if (tn < MAXI) {
        strncpy(tnames[tn], went.name, 20);
        tnames[tn][20] = 0;
        if (strlen(went.name) > 20)
            strcpy(tnames[tn] + 17, "...");
        if (went.dir) {
            p = tnames[tn] + strlen(tnames[tn]);
            *p++ = '/';
            *p = 0;
        }
    }
    ++tn;
    if (went.dir)
        ++tfold;
    tsize += went.size;
}

void clean_trash(void)
{
    paths();
    tn = tfold = 0;
    tsize = 0;
    strcpy(wpath, trash);
    tlisted = walk_list(tentry);
    if (!tlisted)
        tn = 0;
#ifdef DT_TEST
    ui_num(line, tn);
    dt_log("DT TRASH ITEMS ", line);
#endif
}

/* everything in folder top deleted (the folder stays); the names of a
   folder are read into a RAM bank first (no file is deleted while its
   folder is listed); 0 if something could not be deleted */
static char cur[64];
static unsigned char nn, ndir, dbank;
static unsigned int ndel;

static char rec[128];

static void dentry(void)
{
    if (!went.name[0] || nn >= 120)
        return;
    rec[0] = went.dir;
    strncpy(rec + 1, went.name, 62);
    rec[63] = 0;
    bput(dbank, (unsigned int)nn << 6, rec, 64);
    ++nn;
    if (went.dir)
        ++ndir;
}

static unsigned char __fastcall__ delete_tree(const char *top)
{
    static char nm[64];
    unsigned char i, did, isdir;
    unsigned int guard = 0;
    char *p;
    if (!(dbank = BankAlloc(1)))
        return 0;
    strcpy(cur, top);
    for (;;) {
        if (++guard > 2000)
            break;
        nn = ndir = 0;
        strcpy(wpath, cur);
        if (!walk_list(dentry))
            break;
        did = 0;
        for (i = 0; i < nn; ++i) {
            bget(dbank, (unsigned int)i << 6, rec, 64);
            isdir = rec[0];
            strcpy(nm, rec + 1);
            if (isdir) {
                if (join(line, cur, nm)) {      /* into the first folder */
                    strcpy(cur, line);
                    did = 2;
                    break;
                }
                continue;
            }
            ChDir(cur);
            if (FDelete(nm) == 0) {
                ++ndel;
                did = 1;
            }
        }
        if (did == 2)
            continue;
        if (nn && !did)
            break;                      /* (nothing could be deleted here) */
        if (nn >= 120)
            continue;                   /* (more names than one reading took) */
        if (!strcmp(cur, top)) {
            BankFree(dbank);
            return 1;
        }
        p = strrchr(cur, '/');          /* up, and the empty folder removed */
        strcpy(nm, p + 1);
        if (p == cur)
            p[1] = 0;
        else
            *p = 0;
        ChDir(cur);
        if (RmDir(nm))
            break;
        ++ndel;
    }
    BankFree(dbank);
    return 0;
}

void clean_empty(void)
{
    unsigned char ok;
    char *p;
    if (job)
        return;
    clean_trash();
    if (!tn) {
        ui_message("The trash is empty.", "");
        return;
    }
    p = ui_num(line, tn);
    strcpy(p, tn == 1 ? " item: deleted for good." : " items: deleted for good.");
    if (!ui_confirm("Empty the trash?", line)) {
        say("The trash was left as it was.");
        dt_log("DT TRASH KEPT", "");
        return;
    }
    SetPointer(PTR_BUSY);
    ndel = 0;
    ok = delete_tree(trash);
    SetPointer(PTR_ARROW);
    PlaySound(SND_TRASH);
    ui_num(line, ndel);
    dt_log(ok ? "DT TRASH EMPTIED " : "DT TRASH FAILED ", line);
    if (!ok)
        ui_message("Not everything was deleted:", "the rest of the trash is gone.");
    clean_trash();
    say(ok ? "The trash is empty." : "The trash could not be emptied.");
    if (tab == T_CLEAN)
        clean_draw();
}

/*---------------------------------------------------------------- leftovers */
static void add(unsigned char k, const char *name)
{
    if (nc >= MAXC)
        return;
    strcpy(rec, wpath);
    strcpy(rec + 64, name);
    bput(cbank, (unsigned int)nc << 7, rec, 128);
    ckind[nc++] = k;
    ++kcount[k];
#ifdef DT_TEST
    strcpy(line, wpath);
    strcat(line, "|");
    strcat(line, name);
    dt_log(k == K_EDIT ? "DT LEFT EDIT " : k == K_VB ? "DT LEFT VB " : k == K_FONT ? "DT LEFT FONT " : "DT LEFT ASK ", line);
#endif
}

/* is name in the current folder? (CMDR-DOS opens a name that is not
   there: its status says so) */
static unsigned char __fastcall__ there(const char *name)
{
    unsigned char h = FOpen((char *)name, 'r'), r;
    if (h < 2 || h > 4)
        return 0;
    r = dosStatus < 20;
    FClose(h);
    return r;
}

static void sentry(void)
{
    static char sib[64];
    unsigned char i, l;
    if (!went.name[0]) {                /* the folder's end: the siblings looked for */
        for (i = 0; i < npend; ++i) {
            strcpy(sib, pend[i]);
            l = strlen(sib);
            if (pkind[i] == K_FONT)
                strcpy(sib + l - 4, ".cvt");
            else
                strcpy(sib, "ASK.CFG");
            ChDir(wpath);
            if (there(sib))
                add(pkind[i], pend[i]);
        }
        npend = 0;
        return;
    }
    if (went.dir) {
        if (join(line, wpath, went.name) && strcmp(line, trash))
            walk_push(went.name, 0);
        return;
    }
    if (same(went.name, "~VEDIT.TMP"))
        add(K_EDIT, went.name);
    else if (same(went.name, "~VBASIC.TMP"))
        add(K_VB, went.name);
    else if (npend < 4) {
        l = strlen(went.name);
        if (same(went.name, "ASK.TMP") && !strcmp(wpath, datap)) {
            strcpy(pend[npend], went.name);
            pkind[npend++] = K_ASK;
        } else if (l > 4 && same(went.name + l - 4, ".tmp")) {
            strcpy(pend[npend], went.name);
            pkind[npend++] = K_FONT;
        }
    }
}

void clean_scan(void)
{
    if (job)
        return;
    paths();
    if (!cbank && !(cbank = BankAlloc(1))) {
        ui_message("Not enough memory:", "this needs 3 RAM banks.");
        return;
    }
    if (!walk_start("/")) {
        ui_message("Not enough memory:", "this needs 3 RAM banks.");
        return;
    }
    nc = npend = 0;
    memset(kcount, 0, sizeof kcount);
    scanned = 1;
    put_aside = 0;
    job = J_SCAN;
    dt_log("DT SCAN START", "");
    if (tab == T_CLEAN)
        clean_draw();
}

void clean_stop(const char *why)
{
    if (job != J_SCAN)
        return;
    walk_end();
    job = J_NONE;
    scanned = 3;
    dt_log("DT SCAN STOPPED ", why);
    strcpy(line, "Stopped: ");
    strcat(line, why);
    say(line);
    if (tab == T_CLEAN)
        clean_draw();
}

void clean_tick(void)
{
    char *p;
    if (put_aside) {
        clean_stop("put aside; the card may have changed");
        return;
    }
    if (walk_step(sentry)) {
        p = ui_num(line, w_folders);
        strcpy(p, " folders looked at (Esc stops)");
        progress(line);
        return;
    }
    walk_end();
    job = J_NONE;
    scanned = 2;
    ui_num(line, nc);
    dt_log("DT SCAN DONE ", line);
    say(nc ? "Leftovers found: each kind is deleted only after its own OK." : "No leftovers found.");
    if (tab == T_CLEAN)
        clean_draw();
}

void __fastcall__ clean_delete(unsigned char k)
{
    unsigned char i, j, n = 0, bad = 0;
    char *p;
    if (job || k >= K_N || !kcount[k])
        return;
    strcpy(line, "Delete the ");
    p = ui_num(line + 11, kcount[k]);
    strcpy(p, kcount[k] == 1 ? " file listed" : " files listed");
    if (!ui_confirm(line, kshort[k])) {
        say("Nothing was deleted.");
        dt_log("DT KEPT ", kname[k]);
        return;
    }
    for (i = j = 0; i < nc; ++i) {
        bget(cbank, (unsigned int)i << 7, rec, 128);
        if (ckind[i] == k && ChDir(rec) == 0 && FDelete(rec + 64) == 0) {
            ++n;
            dt_log("DT DELETED ", rec + 64);
            continue;
        }
        if (ckind[i] == k)
            ++bad;
        if (i != j)                     /* (kept: moved down) */
            bput(cbank, (unsigned int)j << 7, rec, 128);
        ckind[j++] = ckind[i];
    }
    nc = j;
    kcount[k] = bad;
    if (bad)
        ui_message("Some were not deleted:", "they are still listed.");
    p = ui_num(line, n);
    strcpy(p, n == 1 ? " file deleted." : " files deleted.");
    say(line);
    if (tab == T_CLEAN)
        clean_draw();
}

/*---------------------------------------------------------------- drawing */
void clean_draw(void)
{
    unsigned int y = Y0, x;
    unsigned char i, k, shown;
    char *p;
    ui_clear(BODY_TOP, BODY_BOT);
    if (!tlisted && !tn && !job)
        clean_trash();                  /* (not while a walk runs: it lists folders too) */
    x = 16 + ui_text(16, y, "The trash", 1) + 24;
    if (tn)
        ui_button(x, y + 1, "Empty the trash...", H_EMPTY);
    y += 20;
    if (!tn)
        strcpy(line, tlisted ? "The trash is empty." : "There is no trash folder yet.");
    else {
        p = ui_num(line, tn);
        strcpy(p, tn == 1 ? " item, " : " items, ");
        p = ui_size(p + strlen(p), tsize);
        strcpy(p, tfold ? " in its files (and its folders' contents):" : ":");
    }
    ui_text(16, y, line, 0);
    y += LINE_H;
    line[0] = 0;
    for (i = 0; i < tn && i < MAXI; ++i) {
        if (i)
            strcat(line, ", ");
        strcat(line, tnames[i]);
        if (strlen(line) > 70 || i + 1 == tn || i + 1 == MAXI) {
            if (i + 1 == MAXI && tn > MAXI)
                strcat(line, " ...");
            ui_text(24, y, line, 0);
            y += LINE_H;
            line[0] = 0;
        }
    }
    y += 10;
    x = 16 + ui_text(16, y, "Leftover files", 1) + 24;
    if (job != J_SCAN)
        ui_button(x, y + 1, scanned ? "Look again" : "Look for leftovers", H_SCAN);
    y += 20;
    ui_text(16, y, "Files Veranda's own programs leave when a save is cut short. Nothing else is touched.", 0);
    y += LINE_H + 4;
    if (job == J_SCAN) {
        ui_text(16, y, "Looking... (Esc stops)", 0);
        return;
    }
    if (!scanned)
        return;
    if (!nc) {
        ui_text(16, y, scanned == 3 ? "Stopped before the end: none found so far." : "None found.", 0);
        return;
    }
    for (k = 0; k < K_N; ++k) {
        if (!kcount[k] || y > BODY_BOT - 40)
            continue;
        x = 16 + ui_text(16, y, kname[k], 1) + 16;
        ui_button(x, y + 1, "Delete these...", H_DEL0 + k);
        y += LINE_H + 2;
        ui_text(24, y, knote[k], 0);
        y += LINE_H;
        for (i = 0, shown = 0; i < nc && y < BODY_BOT - 16; ++i) {
            if (ckind[i] != k)
                continue;
            if (shown == 4) {
                p = ui_num(line, kcount[k] - 4);
                strcpy(p, " more");
                ui_text(32, y, line, 0);
                y += LINE_H;
                break;
            }
            bget(cbank, (unsigned int)i << 7, rec, 128);
            if (!join(line, rec, rec + 64))
                strcpy(line, rec + 64);
            ui_text(32, y, line, 0);
            y += LINE_H;
            ++shown;
        }
        y += 6;
    }
}
