/* Disk Tools: Space use (DECISIONS V119). The folders in a chosen folder
   (the card's top first), each with the total size of everything under
   it, largest first, a bar each against the largest; the folder's own
   files as a line of their own. A click on a folder (or Return on the
   selected one) counts inside it; Up (Backspace) goes back. Counting is
   walk.c's, a folder a pass of the main loop, the progress in the status
   bar; Esc stops it (what was counted stays, marked as stopped).

   Its code is overlay 2 (mapped by main.c's wrappers around each call:
   the functions here end in _o), its data in main RAM; the folders' names
   in a RAM bank through bget and bput. MIT licence (see LICENSE). */
#include <veranda.h>
#include <string.h>
#include <theme.h>
#include "dt.h"
#pragma code-name ("OVERLAY2")

#define MAXCH 40                /* folders listed; more go to "other folders" */
#define ROWS  20
#define Y0    (BODY_TOP + 8)    /* the heading */
#define YR    (BODY_TOP + 56)   /* the first row (card-aligned) */
#define BARX  360
#define BARW  256

static char sp_path[64] = "/";
static unsigned char nbank;     /* the folders' names: 64 bytes each */
static unsigned long ctot[MAXCH + 1], own;
static unsigned int cfiles[MAXCH + 1], ownfiles;
static unsigned char nch, order[MAXCH + 1], nrows, sel;
unsigned char sp_done;          /* 0 never counted, 1 counting, 2 counted, 3 stopped */
static char why[48];

static void get_name(unsigned char i, char *out)
{
    if (i == MAXCH)
        strcpy(out, "(other folders)");
    else
        bget(nbank, (unsigned int)i << 6, out, 64);
}

static void entry(void)
{
    unsigned char t;
    if (!went.name[0])
        return;
    if (w_tag == 0xFF) {                /* the chosen folder itself */
        if (!went.dir) {
            own += went.size;
            ++ownfiles;
            return;
        }
        t = nch < MAXCH ? nch++ : MAXCH;
        if (t < MAXCH) {
            bput(nbank, (unsigned int)t << 6, went.name, 64);
            ctot[t] = 0;
            cfiles[t] = 0;
        }
        walk_push(went.name, t);
        return;
    }
    if (went.dir)
        walk_push(went.name, w_tag);
    else {
        ctot[w_tag] += went.size;
        ++cfiles[w_tag];
    }
}

static void sort(void)
{
    unsigned char i, j, k, n = nch + (ctot[MAXCH] || cfiles[MAXCH] ? 1 : 0), t;
    for (i = 0; i < nch; ++i)
        order[i] = i;
    if (n > nch)
        order[nch] = MAXCH;
    for (i = 0; i + 1 < n; ++i) {
        k = i;
        for (j = i + 1; j < n; ++j)
            if (ctot[order[j]] > ctot[order[k]])
                k = j;
        t = order[i];
        order[i] = order[k];
        order[k] = t;
    }
    nrows = n < ROWS ? n : ROWS;
}

static unsigned long total(void)
{
    unsigned long t = own;
    unsigned char i;
    for (i = 0; i <= MAXCH; ++i)
        t += ctot[i];
    return t;
}

static void tlog(void)
{
#ifdef DT_TEST
    unsigned char i;
    static char n[64], b[90];
    char *p;
    for (i = 0; i < nrows; ++i) {
        get_name(order[i], n);
        p = ui_num(b, ctot[order[i]]);
        *p++ = ' ';
        p = ui_num(p, cfiles[order[i]]);
        *p++ = ' ';
        strcpy(p, n);
        dt_log("DT SPACE ", b);
    }
    p = ui_num(b, own);
    *p++ = ' ';
    p = ui_num(p, ownfiles);
    strcpy(p, " (files here)");
    dt_log("DT SPACE ", b);
    p = ui_num(b, total());
    *p++ = ' ';
    p = ui_num(p, w_folders);
    *p++ = ' ';
    ui_num(p, w_skipped);
    dt_log("DT SPACE TOTAL ", b);
#endif
}

static void row(unsigned char r)
{
    static char n[64];
    unsigned int y = YR + (r << 4);
    unsigned long v, m = nrows && ctot[order[0]] > own ? ctot[order[0]] : own;
    unsigned int w;
    char *p;
    SetPattern(0);
    WRectangle(0, y, 639, y + 15);
    if (r < nrows) {
        get_name(order[r], n);
        v = ctot[order[r]];
    } else {
        strcpy(n, "(files in this folder)");
        v = own;
    }
    theme_rect(0, 80, y >> 3, 2, r == sel ? (theme.hilite ? theme.hilite : SELECT) : 0);
    if (strlen(n) > 34)
        strcpy(n + 31, "...");
    ui_text(16, y, n, r < nrows && order[r] < MAXCH);
    p = ui_size(line, v);
    if (r < nrows) {
        strcpy(p, ", ");
        p = ui_num(p + 2, cfiles[order[r]]);
        strcpy(p, " files");
    }
    ui_text(BARX - 130, y, line, 0);
    WFrameRectangle(0xFF, BARX, y + 4, BARX + BARW, y + 11);
    w = m ? (unsigned int)((v >> 12) * BARW / ((m >> 12) + 1)) : 0;
    if (!w && v)
        w = 1;
    if (w) {
        SetPattern(1);
        WRectangle(BARX + 1, y + 5, BARX + w, y + 10);
    }
    if (r < nrows && order[r] < MAXCH)
        ui_hot_add(0, y, 639, y + 15, H_ROW0 + r);
}

void space_draw_o(void)
{
    unsigned int x;
    unsigned char r;
    char *p;
    ui_clear(BODY_TOP, BODY_BOT);
    strcpy(line, "Space used in ");
    strncat(line, sp_path, 60);
    x = 16 + ui_text(16, Y0, line, 1) + 32;
    if (sp_path[1])
        x = ui_button(x, Y0 + 1, "Up", H_UP) + 12;
    ui_button(x, Y0 + 1, sp_done == 1 ? "Counting..." : "Count again", H_COUNT);
    p = line;
    if (sp_done == 0)
        strcpy(p, "Not counted yet: Count again counts.");
    else {
        p = ui_size(p, total());
        strcpy(p, " in ");
        p = ui_num(p + 4, w_files);
        strcpy(p, " files and ");
        p = ui_num(p + 11, w_folders - 1);
        strcpy(p, " folders");
        if (w_skipped) {
            strcat(p, "; skipped ");
            ui_num(p + strlen(p), w_skipped);
        }
        if (sp_done == 1)
            strcat(line, " so far");
        if (sp_done == 3) {
            strcat(line, " (stopped: ");
            strcat(line, why);
            strcat(line, ")");
        }
    }
    ui_text(16, Y0 + 22, line, 0);
    if (sp_done < 2)
        return;
    for (r = 0; r <= nrows; ++r)
        row(r);
}

void space_start_o(void)
{
    if (job)
        return;
    if (!nbank && !(nbank = BankAlloc(1))) {
        ui_message("Not enough memory:", "Space use needs 3 RAM banks.");
        return;
    }
    if (!walk_start(sp_path)) {
        ui_message("Not enough memory:", "Space use needs 3 RAM banks.");
        return;
    }
    memset(ctot, 0, sizeof ctot);
    memset(cfiles, 0, sizeof cfiles);
    own = 0;
    ownfiles = 0;
    nch = nrows = 0;
    sel = 0xFF;
    put_aside = 0;
    job = J_SPACE;
    sp_done = 1;
    if (tab == T_SPACE)
        space_draw_o();
    dt_log("DT SPACE START ", sp_path);
}

void space_stop_o(const char *w)
{
    if (job != J_SPACE)
        return;
    walk_end();
    job = J_NONE;
    sp_done = 3;
    strcpy(why, w);
    sort();
    if (tab == T_SPACE)
        space_draw_o();
    say("Stopped.");
    dt_log("DT SPACE STOPPED ", w);
}

void space_tick_o(void)
{
    static unsigned char n;
    char *p;
    if (put_aside) {
        space_stop_o("put aside; the card may have changed");
        return;
    }
    if (walk_step(entry)) {
        if (!(++n & 7)) {
            p = ui_num(line, w_folders);
            strcpy(p, " folders, ");
            p = ui_num(p + 10, w_files);
            strcpy(p, " files, ");
            p = ui_size(p + 8, total());
            strcpy(p, " so far (Esc stops)");
            progress(line);
        }
        return;
    }
    walk_end();
    job = J_NONE;
    sp_done = 2;
    sort();
    tlog();
    if (tab == T_SPACE)
        space_draw_o();
    say("Counted.");
}

void __fastcall__ space_open_o(unsigned char r)
{
    static char n[64];
    if (job || r >= nrows || order[r] >= MAXCH)
        return;
    get_name(order[r], n);
    if (!join(line, sp_path, n)) {
        ui_message("That folder's path is too long", "(63 characters at most).");
        return;
    }
    strcpy(sp_path, line);
    space_start_o();
}

void space_up_o(void)
{
    char *p;
    if (job || !sp_path[1])
        return;
    p = strrchr(sp_path, '/');
    if (p == sp_path)
        p[1] = 0;
    else
        *p = 0;
    space_start_o();
}

void __fastcall__ space_key_o(unsigned char k)
{
    unsigned char old = sel;
    if (sp_done < 2)
        return;
    if (k == KEY_DOWN)
        sel = sel == 0xFF ? 0 : sel + 1 < nrows ? sel + 1 : sel;
    else if (k == KEY_UP)
        sel = sel == 0xFF || !sel ? 0 : sel - 1;
    else if (k == 13 && sel != 0xFF)
        space_open_o(sel);
    else if (k == KEY_LEFT)
        space_up_o();
    if (tab == T_SPACE && old != sel && job == J_NONE) {
        if (old != 0xFF)
            row(old);
        row(sel);
    }
}
