/* Veranda Claude and Veranda Ask: the conversation's scroll bar and the
   menus (V149, Look 3 "Sunroom": vrwin.h's vr_scroll, the SDK's
   vrscroll.c compiled beside this file into an overlay with room:
   Claude's 3, the parser's; Ask's 10, ASK.LOG's; the Makefiles give the
   segment names; the menus were prefs.c's, overlay 2).

   ui.c fills sbar (main RAM, so that vrscroll reads it with this bank
   mapped) and asks for it drawn (sb_draw: only when its thumb moved, or
   sb_r is SB_FORCE) or for the place of a click on it (sb_hit: sb_r).

   MIT licence (see LICENSE). */
#include <veranda.h>
#include <vrwin.h>
#include "claude.h"


static unsigned int l_at, l_n;

void sb_draw(void)
{
    unsigned int at, n = vr_scroll_len(&sbar, &at);
    if (sbar.total <= sbar.shown)
        n = 0;
    if (sb_r != SB_FORCE && at == l_at && n == l_n)
        return;
    l_at = at;
    l_n = n;
    dispBufferOn = ST_WR_FORE;
    vr_scroll(&sbar);
}

void sb_hit(void)
{
    sb_r = vr_scroll_hit(&sbar, mouseXPos, mouseYPosW);
}

/*---------------------------------------------------------------- the menus (ui.c's actions)

   Their structures and texts in main RAM (the kernel reads them); the
   lists' widths in the UI font, each under its bar item (vr_bar_end;
   Veranda FTP's layout). */
struct item { const char *text; unsigned char type; void *p; };
struct menu2 { unsigned char top, bottom; unsigned int left, right; unsigned char flags; struct item i[2]; };
struct menu3 { unsigned char top, bottom; unsigned int left, right; unsigned char flags; struct item i[3]; };
struct menu4 { unsigned char top, bottom; unsigned int left, right; unsigned char flags; struct item i[4]; };
struct menu1 { unsigned char top, bottom; unsigned int left, right; unsigned char flags; struct item i[1]; };

/* (the texts as arrays: DATA, main RAM; a literal would go to the overlay) */
/* (V149, Look 3's lists, V146: a group's first item after "\x1f", a key
   the program handles right-aligned after "\t"; the app's name the end
   of About's) */
#ifdef ASK
static char t_about[] = "About Veranda Ask";
static char t_keys[] = "Sign-in, key and model...";
#else
static char t_about[] = "About Veranda Claude";
static char t_keys[] = "Server, key and model...";
static char t_opus[] = "\x1f  Claude Opus 5.5";
static char t_sonnet[] = "  Claude Sonnet 5.5";
static char t_haiku[] = "  Claude Haiku 5.5";
#endif
#define t_app (t_about + 6)
static char t_quit[] = "\x1fQuit\tCtrl Q";
static char t_new[] = "New conversation\tCtrl N";
static char t_save[] = "\x1f" "Export as text...\tCtrl S";
static char t_file[] = "File";
static char t_set[] = "Settings";
static char t_code[] = "Code";          /* (V123) */
static char t_ccopy[] = "Copy last code block\tCtrl K";
static char t_csave[] = "Save last code block...\tCtrl E";
static char t_cgo[] = "Go to code block...";
static char t_crep[] = "\x1f" "Copy last reply";
static char t_catt[] = "\x1f" "Attach a file...\tCtrl Shift A";
static char t_cmp[] = "Compact conversation";
static char t_conv[] = "\x1f" "Conversation...";
static char t_chats[] = "Chats...\tCtrl L";
#define IH 14
static struct menu2 mapp = { 14, 14 + 2 * IH, 0, 0, VERTICAL | 2, {
    { t_about, MENU_ACTION, m_about }, { t_quit, MENU_ACTION, m_quit } } };
static struct menu4 mfile = { 14, 14 + 4 * IH, 0, 0, VERTICAL | 4, {
    { t_new, MENU_ACTION, m_new }, { t_chats, MENU_ACTION, m_chats }, { t_save, MENU_ACTION, m_save },
    { t_quit, MENU_ACTION, m_quit } } };
struct menu5 { unsigned char top, bottom; unsigned int left, right; unsigned char flags; struct item i[5]; };
struct menu6 { unsigned char top, bottom; unsigned int left, right; unsigned char flags; struct item i[6]; };
#ifdef ASK
static struct menu3 mset = { 14, 14 + 3 * IH, 0, 0, VERTICAL | 3, {
    { t_keys, MENU_ACTION, m_settings }, { t_conv, MENU_ACTION, m_conv }, { t_cmp, MENU_ACTION, m_compact } } };
#else
static struct menu6 mset = { 14, 14 + 6 * IH, 0, 0, VERTICAL | 6, {
    { t_keys, MENU_ACTION, m_settings }, { t_opus, MENU_ACTION, m_opus },
    { t_sonnet, MENU_ACTION, m_sonnet }, { t_haiku, MENU_ACTION, m_haiku },
    { t_conv, MENU_ACTION, m_conv }, { t_cmp, MENU_ACTION, m_compact } } };
#endif
static struct menu5 mcode = { 14, 14 + 5 * IH, 0, 0, VERTICAL | 5, {
    { t_ccopy, MENU_ACTION, m_ccopy }, { t_csave, MENU_ACTION, m_csave }, { t_cgo, MENU_ACTION, m_cgo },
    { t_crep, MENU_ACTION, m_crep }, { t_catt, MENU_ACTION, m_catt } } };
struct menu4 mbar = { 0, 14, 0, 0, HORIZONTAL | UN_CONSTRAINED | 4, {
    { t_app, SUB_MENU, &mapp }, { t_file, SUB_MENU, &mfile }, { t_set, SUB_MENU, &mset },
    { t_code, SUB_MENU, &mcode } } };
static const char *const barnames[4] = { t_app, t_file, t_set, t_code };

/* each list under its bar item, as wide as its widest item in the UI
   font ('\t' 24 pixels, as the shell's; V149) and 16 pixels */
static struct menu1 *const lists[4] = { (struct menu1 *)&mapp, (struct menu1 *)&mfile, (struct menu1 *)&mset, (struct menu1 *)&mcode };

void menus(void)
{
    unsigned int b, w, wmax;
    unsigned char i, j, c;
    const char *p;
    struct menu1 *m;
    struct item *t;
    for (i = 0; i < 4; ++i) {
        b = vr_bar_end(barnames, i);
        barx[i] = (b + vr_bar_end(barnames, i + 1)) >> 1;
        barl[i] = b;
        UseFont(FONT_UI);
        m = lists[i];
        for (wmax = j = 0, t = m->i; j < (m->flags & 31); ++j, ++t) {
            for (w = 0, p = t->text; (c = *p) != 0; ++p)
                w += c == 9 ? 24 : c == 0x1F ? 0 : GetCharWidth(c);
            if (w > wmax)
                wmax = w;
        }
        m->left = b;
        m->right = b + wmax + 16;
    }
    mbar.right = vr_bar_end(barnames, 4);
    UseSystemFont();
}

void model_marks(void)
{
#ifndef ASK
    t_opus[1] = C.model == M_OPUS ? '*' : ' ';      /* (after the group's "\x1f") */
    t_sonnet[0] = C.model == M_SONNET ? '*' : ' ';
    t_haiku[0] = C.model == M_HAIKU ? '*' : ' ';
#endif
}
