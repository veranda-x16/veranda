/* Veranda Update: Check, Update and Undo (DECISIONS V130).

   Check     the manifest fetched (GitHub: the latest release's
             UPDATE.LST; the PC: /UPDATE.LST) to .SYSTEM/UPD/NEW.LST,
             read (man.c), then the card compared, a file a pass of the
             main loop: missing (new), another size (changed), or the same
             size and its CRC-32 read whole (crc.s): the same or changed.
             An asset fetched before and kept in UPD (its name its CRC-32)
             is read the same way: whole and right, it is not fetched
             again (a cut-short update goes on where it stopped).
   Update    each file still missing fetched to UPD/DL.TMP, its CRC-32
             computed as it comes, its size and CRC checked, then named
             after its asset; the system's files last. A connection that
             drops, Esc, a CRC that does not match, a file the release
             does not have: the update stops and the card is as it was
             (only UPD has files). When every file is in UPD and
             verified: the swap, in one pass of the main loop (so the
             switcher cannot put the program aside in the middle of it):
               1. OLD/<installed build>/UNDO.LST written: every step, the
                  system's last, the manifest after them; OLD/LAST.UPD
                  names that folder; UPD/SWAP.ON says a swap is running
               2. each file: the card's version moved into the OLD folder
                  (FRename; copied and deleted when the command would be
                  longer than the DOS takes), the new one moved from UPD
                  into place (copied when two files share it); the same
                  for /VERANDA/UPDATE.LST
               3. SWAP.ON and UPD removed; the backup of the update before
                  deleted (one undo is kept)
             then "Restart to finish" when a system file changed.
             Each step looks before it moves, so a swap cut short (the
             power) is finished when Veranda Update starts again
             (job_resume_swap).
   Undo      OLD/LAST.UPD's folder: UNDO.LST's steps backwards (a new
             file deleted, a replaced one moved back), the folder removed.

   Nothing else is written: /DOCUMENTS (doc-sample files are listed, never
   written), the settings in /VERANDA/.SYSTEM and every file the manifest
   does not name stay as they are; a file no longer in the manifest is not
   deleted.

   The paths here are from the card's top without the first "/"
   ("VERANDA/APPS/Paint.cvt"). pa is the folder the file calls change to
   (cd_of, mv, mkdirs write it): no path handed to them is pa.

   MIT licence (see LICENSE). */
#include <veranda.h>
#include <string.h>
#include "up.h"

#pragma code-name ("OVERLAY1")
#pragma rodata-name ("OVL1RO")      /* (a string the kernel reads goes through K(): main RAM) */

unsigned char job, checked, nchanged, nnew, nready, nsys, nskip, cur, slept, refused;
unsigned long tchanged, tfetch, tdone;
unsigned char ifetch, nfetch;

static unsigned char fh;                /* the file being written (NEW.LST, DL.TMP), 0 none */
static unsigned long dlgot;
static unsigned char dlpass;            /* 0: the other files, 1: the system's */
static unsigned char lastkb;
static char ps[72];                     /* an asset's path in UPD */
#pragma bss-name ("OVL1BSS")
char hurl[URLMAX];                      /* (overlay 1's: only http.c and this read it, overlay 1 mapped) */
#pragma bss-name ("BSS")

static const char *__fastcall__ base_(const char *p)
{
    const char *s = strrchr(p, '/');
    return s ? s + 1 : p;
}

static unsigned char __fastcall__ h_ok(unsigned char h)
{
    return h >= 2 && h <= 9 && dosStatus < 20;
}

/* why a request failed (http.c's H_ codes), in words */
static const char *const whys[] = {
    "", "", "no network card (TexElec's, at $9FE0) was found",
    "the Wi-Fi modem does not answer", "the connection could not be made",
    "the connection dropped", "nothing came for 30 seconds", "the file is not there (404)",
    "the server said no", "too many redirects", "an address Veranda Update cannot follow",
    "the card could not be written", "stopped", "the reply was not HTTP"
};

const char *__fastcall__ http_why(unsigned char e)
{
    return e < sizeof whys / sizeof whys[0] ? whys[e] : "?";
}

/*---------------------------------------------------------------- the sinks */
static unsigned char __fastcall__ sink_file(const unsigned char *b, unsigned int n)
{
    return fh && !FWrite(fh, (void *)b, n);
}

static unsigned char toolong;

static unsigned char __fastcall__ sink_dl(const unsigned char *b, unsigned int n)
{
    if (dlgot + n > E.size) {
        toolong = 1;
        return 0;
    }
    if (!fh || FWrite(fh, (void *)b, n))
        return 0;
    crc_add(b, n);
    dlgot += n;
    tdone += n;
    return 1;
}

static void close_fh(void)
{
    if (fh)
        FClose(fh);
    fh = 0;
}

/*---------------------------------------------------------------- the addresses */
static void __fastcall__ url_of(const char *file, unsigned char latest)
{
    if (C.src == SRC_PC) {
        strcpy(hurl, "http://");
        strcat(hurl, C.pc);
        strcat(hurl, "/");
    } else {
        strcpy(hurl, "https://");
        strcat(hurl, C.gh);
        strcat(hurl, "/");
        strcat(hurl, C.repo);
        if (latest || !ntag[0])
            /* (Test: the release tagged "test", a pre-release whose assets
               each test build replaces; never JSON from GitHub's API) */
            strcat(hurl, C.test ? "/releases/download/test/" : "/releases/latest/download/");
        else {
            strcat(hurl, "/releases/download/");
            strcat(hurl, ntag);
            strcat(hurl, "/");
        }
    }
    strcat(hurl, file);
}

/*---------------------------------------------------------------- Check */
static void man_start(void)
{
    mkdirs(K(SYS_UPD));
    ChDir(K(UPD_DIR));
    fh = FOpen(K("NEW.LST"), 'w');
    if (!h_ok(fh)) {
        fh = 0;
        job_stop("The card could not be written (/VERANDA/.SYSTEM/UPD).");
        return;
    }
    url_of("UPDATE.LST", 1);
    hsink = sink_file;
    http_get();
    job = J_MAN;
    say("Asking for the list of files ...");
    up_log("UP GET ", hurl);
}

void job_check(void)
{
    if (job || !tbank)
        return;
    checked = 0;
    refused = 0;
    nchanged = nnew = nready = nsys = nskip = 0;
    tchanged = 0;
    nents = 0;
    nbuild[0] = 0;
    nnotes = 0;
    ui_all();
    man_start();
}

static void __fastcall__ man_done(unsigned char r)
{
    const char *w;
    close_fh();
    job = J_NONE;
    if (r != H_OK) {
        del(K(SYS_UPD "NEW.LST"));
        strcpy(line, "No list of files: ");
        if (r == H_E404)
            strcat(line, C.src == SRC_PC ? "the PC has none (UPDATE.LST)" : "the repository has no release with UPDATE.LST");
        else
            strcat(line, http_why(r));
        strcat(line, ".");
        up_log("UP NOMANIFEST ", line);
        job_stop(line);
        return;
    }
    w = man_load(K(UPD_DIR), K("NEW.LST"));
    if (w) {
        strcpy(line, "The list of files was refused: ");
        strncat(line, w, 90);
        up_log("UP BADMANIFEST ", line);
        job_stop(line);
        return;
    }
    up_log("UP MANIFEST ", nbuild);
    cur = 0;
    job = J_SCAN;
    ui_head();
}

static void scan_step(void)
{
    unsigned char r;
    ent_get(cur);
    if (E.st != S_SKIP) {
        r = fcheck(E.path, E.size, E.crc);
        E.st = r == 0 ? S_NEW : r == 1 ? S_SAME : S_CHANGED;
        E.ready = 0;
        if (E.st != S_SAME) {
            strcpy(ps, SYS_UPD);
            strcat(ps, E.asset);
            r = fcheck(ps, E.size, E.crc);
            if (r == 1)
                E.ready = 1;
            else if (r == 2)
                del(ps);                /* (a stale or broken one) */
        }
        ent_put(cur);
    } else
        ++nskip;
    if (E.st == S_CHANGED || E.st == S_NEW) {
        if (E.st == S_CHANGED)
            ++nchanged;
        else
            ++nnew;
        if (E.kind == K_SYSTEM)
            ++nsys;
        if (E.ready)
            ++nready;
        tchanged += E.size;
    }
    if (++cur == nents) {
        job = J_NONE;
        checked = 1;
        ui_all();
        if (!nchanged && !nnew) {
            say("Up to date: the card has every file of this build.");
            up_log("UP UPTODATE", "");
        } else {
            strcpy(line, "To update: ");
            ui_num(line + strlen(line), nchanged);
            strcat(line, " changed, ");
            ui_num(line + strlen(line), nnew);
            strcat(line, " new (");
            ui_size(line + strlen(line), tchanged);
            strcat(line, "). Update brings them.");
            say(line);
            up_log("UP CHANGES ", line);
        }
        return;
    }
    strcpy(line, "Comparing the card: ");
    ui_num(line + strlen(line), cur + 1);
    strcat(line, " of ");
    ui_num(line + strlen(line), nents);
    say(line);
}

/*---------------------------------------------------------------- Update */
static unsigned char __fastcall__ todo(unsigned char pass)
{
    return (E.st == S_CHANGED || E.st == S_NEW) && (E.kind == K_SYSTEM) == pass;
}

/* (swap.c, overlay 3: swap_go) */

/* the next file to fetch (cur on), or the swap */
static void dl_next(void)
{
    for (;;) {
        for (; cur < nents; ++cur) {
            ent_get(cur);
            if (todo(dlpass) && !E.ready)
                break;
        }
        if (cur < nents)
            break;
        if (dlpass) {
            job = J_NONE;
            swap_go();
            return;
        }
        dlpass = 1;
        cur = 0;
    }
    ++ifetch;
    ChDir(K(UPD_DIR));
    fh = FOpen(K("DL.TMP"), 'w');
    if (!h_ok(fh)) {
        fh = 0;
        job_stop("The card could not be written (/VERANDA/.SYSTEM/UPD).");
        return;
    }
    dlgot = 0;
    toolong = 0;
    crc_start();
    url_of(E.asset, 0);
    hsink = sink_dl;
    http_get();
    up_log("UP FETCH ", E.path);
    ui_progress(base_(E.path));
}

void job_update(void)
{
    unsigned char i;
    if (job)
        return;
    if (!checked) {
        up_message("Check first:", "it fetches the list of files and compares the card.");
        return;
    }
    if (!nchanged && !nnew) {
        up_message("Up to date:", "the card has every file of this build.");
        return;
    }
    tfetch = 0;
    nfetch = 0;
    for (i = 0; i < nents; ++i) {
        ent_get(i);
        if ((E.st == S_CHANGED || E.st == S_NEW) && strcmp(E.min, "-") && (!idate[0] || strcmp(idate, E.min) < 0)) {
            strcpy(line, "it needs Veranda of ");
            strcat(line, E.min);
            strcat(line, " or later: copy the package by hand.");
            up_log("UP TOOOLD ", E.path);
            up_message("This update cannot go over this card:", line);
            return;
        }
        if ((E.st == S_CHANGED || E.st == S_NEW) && !E.ready) {
            tfetch += E.size;
            ++nfetch;
        }
    }
    strcpy(line, "Update ");
    ui_num(line + strlen(line), nchanged + nnew);
    strcat(line, " files (");
    ui_size(line + strlen(line), tfetch);
    strcat(line, " to fetch)?");
    if (!up_confirm(line, nsys ? "Veranda restarts at the end (its system files change)." : "Your documents and settings are not touched."))
        return;
    refused = 0;
    tdone = 0;
    ifetch = 0;
    dlpass = 0;
    cur = 0;
    lastkb = 0xFF;
    job = J_DL;
    ui_all();
    say("Fetching: the card changes when every file passed its CRC-32.");
    dl_next();
}

static void dl_tick(void)
{
    unsigned char r = http_poll(), kb;
    unsigned long c;
    if (r == H_RUN) {
        kb = (unsigned char)(tdone >> 10);
        if (kb != lastkb) {
            lastkb = kb;
            ui_progress(0);
        }
#ifdef UP_TEST
        if (t_aside_at && dlgot >= (unsigned long)t_aside_at << 10) {
            t_aside_at = 0;
            up_log("UP ALT+TAB", "");
            TaskCtl(TASK_ASIDE, 0, 0);
        }
#endif
        return;
    }
    close_fh();
    if (r == H_OK) {
        c = crc_end();
        if (dlgot != E.size || c != E.crc) {
            del(K(SYS_UPD "DL.TMP"));
            refused = 1;
            strcpy(line, "Refused: ");
            strcat(line, base_(E.path));
            strcat(line, dlgot != E.size ? " came with the wrong size" : " failed its CRC-32 check");
            up_log("UP REFUSED ", E.path);
            job_stop(line);
            up_message(line, "Nothing on the card was changed.");
            return;
        }
        ChDir(K(UPD_DIR));
        FDelete(E.asset);
        FRename(K("DL.TMP"), E.asset);
        E.ready = 1;
        ent_put(cur);
        ++nready;
        up_log("UP VERIFIED ", E.path);
        ++cur;
        dl_next();
        return;
    }
    del(K(SYS_UPD "DL.TMP"));
    if (toolong)
        r = 0xFE;
    refused = r;
    if (r == H_ECANCEL) {
        job_stop("Stopped: nothing on the card was changed; Update goes on from here.");
        return;
    }
    strcpy(line, base_(E.path));
    if (r == H_E404)
        strcat(line, ": the release does not have it");
    else if (r == 0xFE)
        strcat(line, ": more bytes than the list says");
    else {
        strcat(line, ": ");
        strcat(line, http_why(r));
    }
    up_log("UP FAILED ", line);
#ifdef UP_TEST
    {
        static char t[48];
        extern volatile unsigned int ser_lost, ser_oe;
        strcpy(t, "UP NET ");
        ui_num(t + 7, (unsigned char)-hnet);
        strcat(t, " GOT ");
        ui_num(t + strlen(t), dlgot);
        strcat(t, " OE ");
        ui_num(t + strlen(t), ser_oe);
        strcat(t, " LOST ");
        ui_num(t + strlen(t), ser_lost);
        up_log(t, "");
    }
#endif
    job_stop(line);
    up_message(line, r == H_E404 || r == 0xFE ? "Refused: nothing on the card was changed."
               : "Nothing on the card was changed; Update again goes on from here.");
}

/*---------------------------------------------------------------- the loop */
void job_tick(void)
{
    unsigned char r;
    if (slept) {
        slept = 0;
        job_wake();
    }
    switch (job) {
    case J_MAN:
        r = http_poll();
        if (r != H_RUN)
            man_done(r);
        break;
    case J_SCAN:
        scan_step();
        break;
    case J_DL:
        dl_tick();
        break;
    }
}

void __fastcall__ job_stop(const char *why)
{
    http_cancel();
    close_fh();
    if (job == J_DL)
        del(K(SYS_UPD "DL.TMP"));
    job = J_NONE;
    ui_all();
    say(why);
}

/* the switcher: a file open now is closed (and fetched again from its
   start when the program is back) */
void job_aside(void)
{
    if (fh) {
        close_fh();
        slept = 1;
    }
}

void job_wake(void)
{
    http_cancel();
    up_log("UP BACK", "");
    if (job == J_MAN)
        man_start();
    else if (job == J_DL) {
        tdone -= dlgot;
        --ifetch;
        dl_next();
    }
}
