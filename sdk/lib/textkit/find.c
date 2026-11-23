/* textkit (Veranda Edit, VeraBASIC): find and replace, go to line.

   Find/Replace is one dialog box: two fields (find, replace with), a
   "match case" box and four buttons (Find, Replace, Replace all,
   Cancel), all drawn here (a DB_USR_ROUT with its own key and pointer
   vectors, as the SDK's file chooser). Tab goes from one field to the
   other, Return is Find, Esc Cancel; Alt+R Replace, Alt+A Replace all,
   Alt+M the box. Find selects the next match after the cursor (from the
   start again after the end); Replace replaces the selection if it is a
   match and finds the next; Replace all goes through the whole text, one
   undo step. F3 finds again, Ctrl+R replaces and finds again. (Veranda
   Edit: overlay 2.)

   MIT licence (see LICENSE). */
#include <string.h>
#include <vrchoose.h>
#include "tkapp.h"

static char what[41], with[41];
static unsigned char matchcase, field, result;

#define DL 120                  /* the box */
#define DT 150
#define DR 519
#define DB 301
#define FX (DL + 88)            /* the fields */
#define FR (DR - 12)
#define F1 (DT + 26)
#define F2 (DT + 50)
#define FH 16
#define CBY (DT + 80)           /* the box "match case" */
#define BY (DT + 112)           /* the buttons */
#define BH 22

struct button { unsigned int l, r; const char *t; unsigned char code; };
static const struct button buttons[4] = {
    { DL + 12, DL + 92, "Find", 1 },
    { DL + 104, DL + 196, "Replace", 2 },
    { DL + 208, DL + 312, "Replace all", 3 },
    { DL + 324, DL + 388, "Cancel", 0 },
};

static char row[48];
static unsigned int rmargin;

static void text(const char *s, unsigned int x, unsigned int y, unsigned int right, unsigned char bold)
{
    row[0] = bold ? BOLDON : PLAINTEXT;
    strncpy(row + 1, s, sizeof row - 2);
    rmargin = rightMargin;
    rightMargin = right;
    WPutString(row, x, y);
    rightMargin = rmargin;
}

static void draw_field(unsigned char f)
{
    unsigned int y = f ? F2 : F1;
    SetPattern(0);
    WRectangle(FX + 1, y + 1, FR - 1, y + FH - 1);
    WFrameRectangle(0xFF, FX, y, FR, y + FH);
    if (f == field)
        WFrameRectangle(0xFF, FX + 1, y + 1, FR - 1, y + FH - 1);
    text(f ? with : what, FX + 4, y + 11, FR - 4, 0);
    if (f == field && r11 < FR - 3)
        WVerticalLine(0xFF, r11 + 1, y + 3, y + FH - 3);
}

static void draw_check(void)
{
    SetPattern(0);
    WRectangle(DL + 13, CBY + 1, DL + 21, CBY + 9);
    WFrameRectangle(0xFF, DL + 12, CBY, DL + 22, CBY + 10);
    if (matchcase) {
        WDrawLine(DRAW_INK, DL + 14, CBY + 2, DL + 20, CBY + 8);
        WDrawLine(DRAW_INK, DL + 20, CBY + 2, DL + 14, CBY + 8);
    }
}

static void fdraw(void)
{
    unsigned char i;
    const struct button *b;
    text("Find and replace", DL + 12, DT + 15, DR - 8, 1);
    text("Find:", DL + 12, F1 + 11, FX - 4, 0);
    text("Replace with:", DL + 12, F2 + 11, FX - 4, 0);
    draw_field(0);
    draw_field(1);
    draw_check();
    text("Match case", DL + 28, CBY + 9, DR - 8, 0);
    for (i = 0; i < 4; ++i) {
        b = &buttons[i];
        WFrameRectangle(0xFF, b->l, BY, b->r, BY + BH);
        WFrameRectangle(0xFF, b->l + 1, BY + 1, b->r - 1, BY + BH - 1);
        text(b->t, b->l + 8, BY + 15, b->r - 4, i == 0);
    }
}

static void fclose_(unsigned char r)
{
    result = r;
    sysDBData = OK;
    RstrFrmDialogue();
}

static void fkey(void)
{
    unsigned char k = keyData, l;
    char *s = field ? with : what;
    if (keyDataMods & KEYM_ARROW)
        return;
    if (k == KEY_TAB || k == KEY_UP || k == KEY_DOWN) {
        field ^= 1;
        draw_field(0);
        draw_field(1);
        return;
    }
    if (k == CR) {
        fclose_(1);
        return;
    }
    if (k == KEY_ESC) {
        fclose_(0);
        return;
    }
    if (k >= 0x80 && (keyDataMods & 4)) {       /* Alt + a letter */
        switch (k & 0x7F) {
        case 'r': fclose_(2); return;
        case 'a': fclose_(3); return;
        case 'm': matchcase ^= 1; draw_check(); return;
        }
        return;
    }
    l = strlen(s);
    if (k == 8) {
        if (l)
            s[l - 1] = 0;
    } else if ((k >= 32 && k < 127) || k >= 160) {
        if (l < 40) {
            s[l] = k;
            s[l + 1] = 0;
        } else
            Beep();
    } else
        return;
    draw_field(field);
}

static void fpress(void)
{
    unsigned int x, y;
    unsigned char i;
    if (mouseData & 0x80)
        return;
    do {
        x = mouseXPos;
        y = mouseYPosW;
    } while (x != mouseXPos || y != mouseYPosW);
    if (x >= FX && x <= FR && y >= F1 && y <= F2 + FH) {
        field = y >= F2;
        draw_field(0);
        draw_field(1);
        return;
    }
    if (x >= DL + 10 && x <= DL + 110 && y >= CBY - 2 && y <= CBY + 12) {
        matchcase ^= 1;
        draw_check();
        return;
    }
    if (y >= BY && y <= BY + BH)
        for (i = 0; i < 4; ++i)
            if (x >= buttons[i].l && x <= buttons[i].r) {
                fclose_(buttons[i].code);
                return;
            }
}

static void fmain(void)
{
    edit_idle = 1;
}

static void fopen_(void)
{
    fdraw();
    keyVector = VR_FN(fkey);
    otherPressVec = VR_FN(fpress);
    appMain = VR_FN(fmain);
}

static unsigned char dialog(void)
{
    static unsigned char tab[] = {
        SET_DB_POS | WIDE_DB | 1,
        DT & 255, DT >> 8, DB & 255, DB >> 8, DL & 255, DL >> 8, DR & 255, DR >> 8,
        DB_USR_ROUT, 0, 0,
        0
    };
    tab[10] = VR_FN(fopen_) & 255;
    tab[11] = VR_FN(fopen_) >> 8;
    result = 0;
    vr_dlgbox(tab);
    return result;
}

/*---------------------------------------------------------------
  finding
 ---------------------------------------------------------------*/
static unsigned char fold(unsigned char c)
{
    if ((c >= 'A' && c <= 'Z') || (c >= 0xC0 && c <= 0xDE && c != 0xD7))
        return c + 32;
    return c;
}

/* the pattern into gb_pat: 0 if there is none */
static unsigned char prep(void)
{
    unsigned int i;
    unsigned char k;
    gb_plen = strlen(what);
    if (!gb_plen)
        return 0;
    for (i = 0; i < 256; ++i)
        gb_ftab[i] = matchcase ? i : fold(i);
    for (k = 0; k < gb_plen; ++k)
        gb_pat[k] = gb_ftab[(unsigned char)what[k]];
    return 1;
}

static unsigned long search(unsigned long from)
{
    gb_a = from;
    gb_find();
    return gb_a;
}

static void select(unsigned long p)
{
    move_to(p, 0);
    move_to(p + gb_plen, 1);
}

static unsigned char find_next(void)
{
    unsigned long p;
    if (!prep())
        return 0;
    p = search(cur);
    if (p == NOWHERE) {
        p = search(0);
        if (p == NOWHERE) {
            Beep();
            view_status_msg("Not found");
            return 0;
        }
        view_status_msg("From the start again");
    }
    select(p);
    return 1;
}

/* the selection is a match */
static unsigned char sel_match(void)
{
    static char t[41];
    unsigned char k;
    if (!prep() || sel_hi() - sel_lo() != gb_plen || !ed_text(sel_lo(), gb_plen, t))
        return 0;
    for (k = 0; k < gb_plen; ++k)
        if (gb_ftab[(unsigned char)t[k]] != gb_pat[k])
            return 0;
    return 1;
}

static void replace_sel(void)
{
    unsigned char n = strlen(with);
    if (n)
        ed_insert(with, n);
    else
        ed_delete_sel();
}

/* every match from the start, on the text itself (no LF in either
   string: the lines stay as they are), one undo step; the cursor after
   the last; "n replaced" */
static void replace_all(void)
{
    unsigned long p = 0, count = 0, last = NOWHERE;
    static char msg[24];
    char *q;
    unsigned char plen, rlen = strlen(with);
    if (!prep())
        return;
    plen = gb_plen;
    undo_step();
    T_RESET();
    for (;;) {
        gb_plen = plen;                 /* (prep's pattern stays in gb_pat) */
        p = search(p);
        if (p == NOWHERE)
            break;
        undo_push(U_REP, p, plen | (unsigned long)rlen << 16);
        tx_delete(p, plen);
        if (rlen && tx_insert(p, with, rlen)) {
            message("There is not enough memory", "to replace them all.");
            break;
        }
        p += rlen;
        last = p;
        ++count;
    }
    if (last != NOWHERE) {
        cur = last;
        ed_recount();
    }
    T_LOG("replaceall");
    q = msg;
    {
        char t[11];
        unsigned char n = 0;
        do {
            t[n++] = '0' + (unsigned char)(count % 10);
            count /= 10;
        } while (count);
        while (n)
            *q++ = t[--n];
    }
    strcpy(q, " replaced");
    view_status_msg(msg);
}

void m_find(void)
{
    unsigned char r;
    field = 0;
    r = dialog();
    switch (r) {
    case 1:
        find_next();
        break;
    case 2:
        undo_step();
        if (sel_match())
            replace_sel();
        find_next();
        break;
    case 3:
        replace_all();
        break;
    }
}

void m_findnext(void)
{
    if (!what[0])
        m_find();
    else
        find_next();
}

void m_replnext(void)
{
    undo_step();
    if (sel_match())
        replace_sel();
    find_next();
}

void m_goto(void)
{
    static char buf[8];
    unsigned long n = 0, p;
    unsigned int k;
    char *s;
    buf[0] = 0;
    if (!ask("Go to line:", buf, 7))
        return;
    for (s = buf; *s >= '0' && *s <= '9'; ++s)
        n = n * 10 + (*s - '0');
    if (!n)
        return;
    --n;
    p = 0;
    while (n) {
        k = n > 60000UL ? 60000U : (unsigned int)n;
        gb_a = p;
        gb_n = k;
        if (gb_fwd_lines() < k)
            n = k;                      /* past the end: the last line */
        p = gb_a;
        n -= k;
    }
    move_to(p, 0);
    goal = 0;
}
