/* Disk Tools: the Check tab drawn (DECISIONS V119): check.c's results,
   its fault lines from their RAM bank (bget). Its code is overlay 2
   (main.c's wrappers map it). MIT licence (see LICENSE). */
#include <veranda.h>
#include <string.h>
#include "dt.h"
#include "check.h"
#pragma code-name ("OVERLAY2")

#define ROWS    18
#define Y0      (BODY_TOP + 8)
void check_draw_o(void)
{
    unsigned int y, x;
    unsigned char i;
    char *p;
    static char fl[128];
    ui_clear(BODY_TOP, BODY_BOT);
    x = 16 + ui_text(16, Y0, "Check the card (read only)", 1) + 24;
    if (job != J_CHECK)
        ui_button(x, Y0 + 1, "Start the check", H_CHECK);
    ui_text(16, Y0 + 20, "It reads the FAT and every folder and reports what it finds.", 0);
    ui_text(16, Y0 + 36, "It never writes to the card and repairs nothing.", 1);
    y = Y0 + 60;
    if (job == J_CHECK) {
        ui_text(16, y, "Checking... (Esc stops)", 0);
        return;
    }
    if (st != S_DONE)
        return;
    p = ui_num(line, n_dirs);
    strcpy(p, " folders and ");
    p = ui_num(p + strlen(p), n_files);
    strcpy(p, " files checked: ");
    p += strlen(p);
    if (!nfault)
        strcpy(p, "no problems found.");
    else {
        p = ui_num(p, nfault);
        strcpy(p, nfault == 1 ? " problem found:" : " problems found:");
    }
    ui_text(16, y, line, 1);
    y += LINE_H;
    p = ui_num(line, n_free);
    strcpy(p, " free clusters of ");
    p = ui_num(p + strlen(p), card.nclus);
    if (card.fsi_free != 0xFFFFFFFFUL && card.fsi_free != n_free) {
        strcpy(p, "; FSInfo says ");
        p = ui_num(p + strlen(p), card.fsi_free);
        strcpy(p, " (a count the DOS keeps; not an error)");
    }
    ui_text(16, y, line, 0);
    y += LINE_H;
    if (nobits) {
        ui_text(16, y, "Crossing chains and lost clusters were not looked for (not enough RAM banks).", 0);
        y += LINE_H;
    }
    if (n_toomany) {
        p = ui_num(line, n_toomany);
        strcpy(p, " folders not checked (more than 256 waiting at once)");
        ui_text(16, y, line, 0);
        y += LINE_H;
    }
    y += 4;
    nshown = nfault < MAXF ? nfault : MAXF;
    for (i = 0; i < nshown && i < ROWS; ++i, y += LINE_H) {
        bget(fbank, (unsigned int)i << 7, fl, 128);
        ui_text(24, y, fl, 0);
    }
    if (nfault > ROWS) {
        p = ui_num(line, nfault - ROWS);
        strcpy(p, " more (not shown)");
        ui_text(24, y, line, 0);
    }
}
