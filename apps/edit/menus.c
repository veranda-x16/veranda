/* Veranda Edit: the menus (their tables in main RAM; layout() in
   overlay 2 since V148, called through call2: misc.c). Veranda Look 3 "Sunroom" (DECISIONS
   V146, V148): an item starting with $1F has a dotted line above it (a
   group starts there), a shortcut after a tab is drawn by the kernel
   right-aligned; a list is as wide as its longest name + 24 + its key.

   MIT licence (see LICENSE). */
#include <string.h>
#include "edit.h"
#pragma code-name ("OVERLAY2")

struct item { const char *text; unsigned char type; void *p; };
struct menu2 { unsigned char top, bottom; unsigned int left, right; unsigned char flags; struct item i[2]; };
struct menu4 { unsigned char top, bottom; unsigned int left, right; unsigned char flags; struct item i[4]; };
struct menu5 { unsigned char top, bottom; unsigned int left, right; unsigned char flags; struct item i[5]; };
struct menu6 { unsigned char top, bottom; unsigned int left, right; unsigned char flags; struct item i[6]; };

#define IH 14
static struct menu2 mgeos = { 14, 14 + 2 * IH, 0, 0, VERTICAL | 2, {
    { "About Veranda Edit", MENU_ACTION, m_about }, { "\x1f" "Desk accessory...", MENU_ACTION, m_desk } } };
static struct menu6 mfile = { 14, 14 + 6 * IH, 0, 0, VERTICAL | 6, {
    { "New\tCtrl N", MENU_ACTION, c_new }, { "Open...\tCtrl O", MENU_ACTION, c_open },
    { "\x1f" "Save\tCtrl S", MENU_ACTION, c_save }, { "Save as...\tShift Ctrl S", MENU_ACTION, c_saveas },
    { 0, MENU_ACTION, c_enc }, { "\x1f" "Quit\tCtrl Q", MENU_ACTION, quit } } };
static struct menu5 medit = { 14, 14 + 5 * IH, 0, 0, VERTICAL | 5, {
    { "Undo\tCtrl Z", MENU_ACTION, m_undo }, { "\x1f" "Cut\tCtrl X", MENU_ACTION, mc_cut },
    { "Copy\tCtrl C", MENU_ACTION, mc_copy }, { "Paste\tCtrl V", MENU_ACTION, mc_paste },
    { "\x1f" "Select all\tCtrl A", MENU_ACTION, m_selall } } };
static struct menu4 msearch = { 14, 14 + 4 * IH, 0, 0, VERTICAL | 4, {
    { "Find and replace...\tCtrl F", MENU_ACTION, c_find }, { "Find next\tF3", MENU_ACTION, c_findnext },
    { "Replace, find next\tCtrl R", MENU_ACTION, c_replnext },
    { "\x1f" "Go to line...\tCtrl L", MENU_ACTION, c_goto } } };
static struct menu4 mbar = { 0, 14, 0, 0, HORIZONTAL | UN_CONSTRAINED | 4, {
    { "Veranda Edit", SUB_MENU, &mgeos }, { "File", SUB_MENU, &mfile }, { "Edit", SUB_MENU, &medit },
    { "Search", SUB_MENU, &msearch } } };

/* a name's width, its key 24 pixels after it */
static unsigned int itemw(const char *s)
{
    unsigned int w = 0, t = 0;
    if (*s == 0x1F)
        ++s;
    for (; *s; ++s)
        if (*s == '\t') {
            t = w + 24;
            w = 0;
        } else
            w += GetCharWidth(*s);
    return t + w;
}

unsigned int barx[4];            /* the bar's items (the test's player) */

void layout(void)
{
    static struct menu6 *const subs[4] = { (void *)&mgeos, (void *)&mfile, (void *)&medit, (void *)&msearch };
    unsigned int x = 0, w, m;
    unsigned char i, j;
    UseFont(FONT_UI);                   /* (the menus' font: theme_menus, V79) */
    mfile.i[4].text = tk_enc ? "\x1f" "Encoding: UTF-8\tCtrl E"     /* (V143: c_enc) */
                             : "\x1f" "Encoding: ISO-8859-16\tCtrl E";
    for (i = 0; i < 4; ++i) {
        for (m = 0, j = 0; j < (subs[i]->flags & 0x1F); ++j)
            if ((w = itemw(subs[i]->i[j].text)) > m)
                m = w;
        subs[i]->left = x;
        subs[i]->right = x + m + 16;
        barx[i] = x + 4;
        x += itemw(mbar.i[i].text) + 8;
    }
    mbar.right = x + 64;                /* (past the kernel's bar end, V74) */
    UseSystemFont();
}


void *const menubar = &mbar;
