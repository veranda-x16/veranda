/* Veranda Gemini: boxes and small things for the interface (overlay 2,
   with the bookmarks; DECISIONS V118): the status bar's right, the page's
   name, Find's match, About, the bookmarks' boxes.
   Here for overlay 1's room; they work on main RAM's buffers.

   MIT licence (see LICENSE). */
#include <veranda.h>
#include <string.h>
#include <vrnet.h>
#include "gemini.h"
#pragma code-name ("OVERLAY2")
#pragma rodata-name ("OVL2RO")
#pragma bss-name ("OVL2BSS")

/* the status bar's right: the modem, or the rows shown */
void u_lines(void)
{
    unsigned char s = net_on ? net_state() : NET_OFF;
    unsigned int all = doc_lines + (doc_full && doc_done ? 2 : 0), b;
    lastnet = s;
    if (!net_on)
        strcpy(right, "No network card");
    else if (s == NET_FAULT)
        strcpy(right, "The modem does not answer");
    else if (s != NET_READY)
        strcpy(right, "Looking for the modem ...");
    else if (!all)
        right[0] = 0;
    else {
        b = v_top + rows < all ? v_top + rows : all;
        strcpy(right, "Lines ");
        unum(right + strlen(right), v_top + 1);
        strcat(right, "-");
        unum(right + strlen(right), b);
        strcat(right, " of ");
        unum(right + strlen(right), all);
    }
}

static unsigned char __fastcall__ lower(unsigned char c)
{
    return c >= 'A' && c <= 'Z' ? c + 32 : c;
}

/* the page's name: its first heading (among its first rows), else the
   link's label, else the host; the title bar, the history's entry */
void u_named(void)
{
    unsigned int i;
    unsigned char n, k;
    for (i = 0; i < doc_lines && i < 40; ++i) {
        k = doc_kind(i);
        if (k >= K_H1 && k <= K_H3) {
            render(i);
            for (n = 0; n < TITLEMAX - 1 && row[3 + n]; ++n)
                title[n] = row[3 + n];
            while (n && title[n - 1] == ' ')
                --n;
            title[n] = 0;
            break;
        }
    }
    if (!title[0])
        strcpy(title, ghost);
    hist_get(hpos, &H);
    memcpy(H.title, title, TITLEMAX);
    hist_put(hpos, &H);
    strcpy(line, appname);
    strcat(line, ": ");
    strcat(line, title);
    win_title(line);
}

/* Find's search: fq in row (case aside); u_ret 1 found */
void u_hit(void)
{
    unsigned char n = strlen(fq), i, j;
    u_ret = 1;
    for (i = 0; i + n <= ROWW; ++i) {
        for (j = 0; j < n && lower(row[i + j]) == lower(fq[j]); ++j)
            ;
        if (j == n)
            return;
    }
    u_ret = 0;
}

void u_about(void)
{
    message("Veranda Gemini 1.0, MIT licence. Gemini through", "the modem's TLS (it does not check certificates).");
}

/* after marks_add, marks_del: their boxes; u_ret 1: msg says it was added */
void u_marked(void)
{
    u_ret = 0;
    if (marks_err == 2)
        message("There are 16 bookmarks already:", "remove one first (Bookmarks > Remove...).");
    else if (marks_err)
        message("GEMINI.MARKS cannot be written.", "(the bookmarks are in /VERANDA/.SYSTEM)");
    else if (marks_i == 0xFF) {
        strcpy(msg, "Bookmark added: ");
        strcat(msg, title);
        u_ret = 1;
    }
}
