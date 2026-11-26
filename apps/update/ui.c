/* Veranda Update: the window's body (DECISIONS V130; sysui's Look 2
   window, as Disk Tools and About this X16):

     Source        GitHub releases: owner/repo, or a PC on my network
     Installed     the card's build (VERANDA/UPDATE.LST)
     Available     the manifest's build, its tag
     What's new    its notes (4 lines)
     the files     changed and new, each with its size and "fetched"
                   when it waits verified in UPD; the count and the total
     the progress  a bar, the file, KB of KB, the file's number

   MIT licence (see LICENSE). */
#include <veranda.h>
#include <string.h>
#include <theme.h>
#include "up.h"

#pragma code-name ("OVERLAY2")
#pragma rodata-name ("OVL2RO")      /* (its strings go to sysui, which copies them) */
#pragma bss-name ("OVL2BSS")

#define Y_SRC   (BODY_TOP + 4)
#define Y_INST  (Y_SRC + 16)
#define Y_AVAIL (Y_INST + 16)
#define Y_NOTES (Y_AVAIL + 16)
#define NNOTES  4
#define Y_FILES (Y_NOTES + NNOTES * 16 + 8)
#define Y_ROW0  (Y_FILES + 18)
#define ROWS    13
#define Y_BAR   (Y_ROW0 + ROWS * 16 + 8)
#define Y_PTXT  (Y_BAR + 16)

static char v[100];

static void source_line(void)
{
    if (xmode)                          /* (V198) */
        strcpy(v, "GitHub releases of " X_REPO ": Veranda Write's dictionaries");
    else if (C.src == SRC_PC) {
        strcpy(v, "a PC on my network, ");
        strcat(v, C.pc[0] ? C.pc : "(no address: Source...)");
    } else {
        strcpy(v, "GitHub releases of ");
        strcat(v, C.repo);
        strcat(v, C.test ? ", Test channel" : ", Stable channel");
    }
    ui_pair(Y_SRC, "Source", v);
}

static void __fastcall__ build_text(const char *ver, const char *b, const char *d)
{
    v[0] = 0;
    if (ver[0]) {
        strcpy(v, "Veranda ");
        strcat(v, ver);
        strcat(v, ", ");
    }
    strcat(v, "build ");
    strcat(v, b);
    strcat(v, " of ");
    strcat(v, d);
}

void ui_head_o(void)
{
    unsigned char i;
    source_line();
    if (xmode)
        strcpy(v, "the dictionaries in /VERANDA/DICT (Veranda's build stays as it is)");
    else if (ibuild[0])
        build_text(iver, ibuild, idate);
    else
        strcpy(v, "not known (no /VERANDA/UPDATE.LST: a card from before Veranda Update)");
    ui_pair(Y_INST, "Installed", v);
    if (nbuild[0] && xmode) {
        strcpy(v, "dictionaries ");
        strcat(v, nver[0] ? nver : nbuild);
        strcat(v, " of ");
        strcat(v, ndate);
        strcat(v, ", release " X_TAG);
    } else if (nbuild[0]) {
        build_text(nver, nbuild, ndate);
        if (ntag[0]) {
            strcat(v, ", release ");
            strcat(v, ntag);
        }
    } else
        strcpy(v, job == J_MAN ? "asking ..." : "(Check asks)");
    ui_pair(Y_AVAIL, "Available", v);
    for (i = 0; i < NNOTES; ++i)
        ui_pair(Y_NOTES + i * 16, i ? "" : "What's new", i < nnotes ? notes[i] : "");
}

void ui_list_o(void)
{
    unsigned char i, row = 0, more = 0;
    unsigned int y;
    const char *p;
    SetPattern(0);
    WRectangle(0, Y_FILES, 639, Y_BAR - 1);
    if (!checked && job != J_DL) {
        ui_text(16, Y_FILES, job == J_SCAN ? "Comparing the card with the list ..." : xmode ? "Dictionaries fetches their list and compares the card." : "Check fetches the list of files and compares the card.", 0);
        return;
    }
    strcpy(v, "Changed ");
    ui_num(v + strlen(v), nchanged);
    strcat(v, ", new ");
    ui_num(v + strlen(v), nnew);
    strcat(v, ", the same ");
    ui_num(v + strlen(v), nents - nchanged - nnew - nskip);
    if (nready) {
        strcat(v, "; fetched already ");
        ui_num(v + strlen(v), nready);
    }
    strcat(v, ": ");
    ui_size(v + strlen(v), tchanged);
    ui_text(16, Y_FILES, v, 1);
    WHorizontalLine(0xFF, 16, 623, Y_FILES + 16);
    if (!nchanged && !nnew) {
        ui_text(16, Y_ROW0, "Up to date: nothing to fetch.", 0);
        return;
    }
    for (i = 0; i < nents; ++i) {
        ent_get(i);
        if (E.st != S_CHANGED && E.st != S_NEW)
            continue;
        if (row == ROWS - 1 && (unsigned char)(nchanged + nnew) > ROWS) {
            ++more;
            continue;
        }
        y = Y_ROW0 + row * 16;
        ui_text(16, y, E.st == S_NEW ? "new" : "changed", 0);
        p = E.path;
        if (!memcmp(p, "VERANDA/", 8))
            p += 8;
        ui_text(88, y, p, 0);
        ui_size(v, E.size);
        ui_text(456, y, v, 0);
        ui_text(536, y, E.ready ? "fetched" : E.kind == K_SYSTEM ? "system" : "", 0);
        ++row;
    }
    if (more) {
        strcpy(v, "... and ");
        ui_num(v + strlen(v), more);
        strcat(v, " more");
        ui_text(88, Y_ROW0 + (ROWS - 1) * 16, v, 0);
    }
}

/* the progress: name the file's (all of it drawn, before its connection
   opens), or 0: the bar's new part and the numbers over the old ones,
   while bytes come. (Gate update found that clearing the whole band, 640
   by 34 pixels, while a packet came overran the UART's FIFO now and then:
   a byte lost, the connection failed. So nothing wide is cleared then.) */
static unsigned int barw;
static char pname[40];

void __fastcall__ ui_progress_o(const char *name)
{
    unsigned long t = tfetch ? tfetch : 1;
    unsigned int w = (unsigned int)((tdone > t ? t : tdone) * 604UL / t);
    char *p;
    if (name) {
        SetPattern(0);
        WRectangle(0, Y_BAR - 2, 639, Y_PTXT + 15);
        if (job != J_DL)
            return;
        ui_rframe(16, Y_BAR, 623, Y_BAR + 11);
        barw = 0;
        strncpy(pname, name, sizeof pname - 1);
    }
    if (w > barw) {
        SetPattern(1);
        WRectangle(18 + barw, Y_BAR + 2, 18 + w - 1, Y_BAR + 9);
        barw = w;
    }
#ifdef UP_BARONLY
    if (!name)
        return;
#endif
    strcpy(v, "Fetching ");
    strcat(v, pname);
    strcat(v, ": ");
    p = ui_size(v + strlen(v), tdone);
    strcpy(p, " of ");
    p = ui_size(p + 4, tfetch);
    strcpy(p, " (file ");
    p = ui_num(p + 7, ifetch);
    strcpy(p, " of ");
    p = ui_num(p + 4, nfetch);
    strcpy(p, "); Esc stops  ");
    ui_text(16, Y_PTXT, v, 0);
}

void ui_all_o(void)
{
    ui_clear(BODY_TOP, BODY_BOT);
    ui_head_o();
    ui_list_o();
    ui_progress_o("");
}

/* Source...: GitHub's owner/repo or the PC's host:port */
void ui_source_o(void)
{
    if (job)
        return;
    if (up_confirm("Update from GitHub releases?", "OK: GitHub. Cancel: from a PC on my network.")) {
        C.src = SRC_GITHUB;
        ui_ask("The GitHub repository (owner/repo):", C.repo, sizeof C.repo - 1);
        C.test = !up_confirm("Stable releases?", "OK: Stable (the latest release). Cancel: Test builds.");
    } else {
        C.src = SRC_PC;
        ui_ask("The PC's address and port (192.168.1.20:8644):", C.pc, sizeof C.pc - 1);
    }
    cfg_save();
    checked = 0;
    nbuild[0] = 0;
    nnotes = 0;
    ui_all_o();
    say("Saved in /VERANDA/.SYSTEM/UPDATE.CFG; Check asks it.");
}

/*---------------------------------------------------------------- the settings */
/* (main.c's until V198; overlay 2's) UPDATE.CFG in /VERANDA/.SYSTEM. The public
   repository (DECISIONS V139): the organisation's; a card that saved the
   one before (sandlbn/veranda-x16, before the organisation) reads the new
   one, and the next save writes it */
#define DEF_REPO "veranda-x16/veranda"
static const char oldRepo[] = "sandlbn/veranda-x16";
static unsigned char cfh;

void cfg_load_o(void)
{
    char *b = (char *)iobuf;
    unsigned char n, k;
    char *p, *e;
    C.src = SRC_GITHUB;
    strcpy(C.repo, DEF_REPO);
    C.pc[0] = 0;
    strcpy(C.gh, "github.com");
    if (ChDir(K(VR_DATADIR)))
        return;
    cfh = FOpen(K("UPDATE.CFG"), 'r');
    if (cfh < 2 || cfh > 9 || dosStatus >= 20)
        return;
    n = FRead(cfh, b, 200);
    FClose(cfh);
    b[n] = 0;
    for (p = b; *p; p = e) {
        for (e = p; *e && *e != '\n' && *e != '\r'; ++e)
            ;
        k = e - p;
        if (*e)
            *e++ = 0;
        if (!memcmp(p, "source=", 7))
            C.src = !strcmp(p + 7, "pc") ? SRC_PC : SRC_GITHUB;
        else if (!memcmp(p, "repo=", 5) && k - 5 < sizeof C.repo && k > 5 && strcmp(p + 5, oldRepo))
            strcpy(C.repo, p + 5);
        else if (!memcmp(p, "pc=", 3) && k - 3 < sizeof C.pc)
            strcpy(C.pc, p + 3);
        else if (!memcmp(p, "github=", 7) && k - 7 < sizeof C.gh && k > 7)
            strcpy(C.gh, p + 7);
        else if (!memcmp(p, "channel=", 8))
            C.test = !strcmp(p + 8, "test");
    }
}

void cfg_save_o(void)
{
    char *b = (char *)iobuf;
    strcpy(b, "source=");
    strcat(b, C.src == SRC_PC ? "pc" : "github");
    strcat(b, "\r\nrepo=");
    strcat(b, C.repo);
    strcat(b, "\r\npc=");
    strcat(b, C.pc);
    strcat(b, C.test ? "\r\nchannel=test\r\n" : "\r\nchannel=stable\r\n");
    if (strcmp(C.gh, "github.com")) {
        strcat(b, "github=");
        strcat(b, C.gh);
        strcat(b, "\r\n");
    }
    ChDir(K("/VERANDA"));
    MkDir(K(".SYSTEM"));
    if (ChDir(K(VR_DATADIR)))
        return;
    cfh = FOpen(K("UPDATE.CFG"), 'w');
    if (cfh < 2 || cfh > 9 || dosStatus >= 20)
        return;
    FWrite(cfh, b, strlen(b));
    FClose(cfh);
}
