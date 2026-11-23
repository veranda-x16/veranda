/* Veranda Chat: the scroll bars and the menus (overlay 5; DECISIONS V111,
   V149).

   The scroll bars are Sunroom's (vrwin.h's vr_scroll: the SDK's
   vrscroll.c compiled into this overlay): ui.c fills sbar (main RAM, so
   that vrscroll reads it with this bank mapped) and asks for it drawn
   (sb_draw) or for the place of a click on it (sb_hit: sb_r).

   The menus: their structures and texts in main RAM (the kernel reads
   them), Look 3's lists (V146): a group's first item after "\x1f" (a
   dotted line over it), a key the program handles right-aligned after
   "\t"; each list under its bar item (vr_bar_end), as wide as its widest
   item in the UI font ('\t' 24 pixels, as the shell's) and 16 pixels.

   Also here, from ui.c for its room (V149): the status bar's right
   (the connection), the tabs, the topic line.

   MIT licence (see LICENSE). */
#include <veranda.h>
#include <string.h>
#include <theme.h>
#include <vrnet.h>
#include <vrwin.h>
#include "chat.h"
#pragma code-name ("OVERLAY5")
#pragma rodata-name ("OVL5RO")
#pragma bss-name ("OVL5BSS")

/* sb_r: the bar (0 the text's, 1 the nick list's), $80: drawn even when
   its thumb is where it was drawn last (else only when it moved: a line
   in does not draw the bar again) */
static unsigned int l_at[2], l_n[2];
static unsigned char l_cx[2];

void sb_draw(void)
{
    unsigned char b = sb_r & 1;
    unsigned int at, n = vr_scroll_len(&sbar, &at);
    if (sbar.total <= sbar.shown)
        n = 0;
    if (!(sb_r & 0x80) && at == l_at[b] && n == l_n[b] && sbar.cx == l_cx[b])
        return;
    l_at[b] = at;
    l_n[b] = n;
    l_cx[b] = sbar.cx;
    dispBufferOn = ST_WR_FORE;
    vr_scroll(&sbar);
}

void sb_hit(void)
{
    sb_r = vr_scroll_hit(&sbar, mouseXPos, mouseYPosW);
}

/*---------------------------------------------------------------- ui.c's (V149: moved here) */
#define TOOLY   32
#define TABW    11              /* a tab's cards */
#define TOPY    48
#define BODYY   64
extern char right[64];
extern unsigned char hl;

void ui_where(void)
{
    unsigned char s = net_on ? net_state() : NET_OFF;
    char *p;
    right[0] = 0;
    if (W[cw].scroll)
        strcpy(right, "Scrolled back (End: newest)   ");
    p = right + strlen(right);
    switch (cstate) {
    case C_OFF:
        strcpy(p, !net_on ? "No network card" : s == NET_FAULT ? "The modem does not answer" : "Not connected");
        break;
    case C_WAIT:
        strcpy(p, "Looking for the modem ...");
        break;
    case C_OPEN:
        strcpy(p, "Connecting ...");
        break;
    case C_REG:
        strcpy(p, "Registering ...");
        break;
    case C_QUIT:
        strcpy(p, "Quitting ...");
        break;
    default:
        if (W[cw].kind == W_CHAN) {     /* (V178: all of them, not the nicks kept) */
            p = unum(p, W[cw].people);
            strcpy(p, W[cw].people == 1 ? " person, as " : " people, as ");
        } else
            strcpy(p, "Connected as ");
        strcat(right, me);
    }
}


/* the tabs (V149, Sunroom: each framed on its own cards, its name centred
   in the UI font (through line: the kernel reads it), the one shown bold
   on the theme's highlight; a name too wide loses letters, not its mark) */
static unsigned int __fastcall__ tabw(unsigned char bold)
{
    unsigned int w = 0;
    unsigned char c;
    const char *t = line;
    while ((c = *t++) != 0)
        w += GetCharWidth(c) + bold;
    return w;
}

void ui_tabs(void)
{
    unsigned char i, x, n, on, mark;
    unsigned int l, w;
    struct win *wp;
    dispBufferOn = ST_WR_FORE;
    SetPattern(0);
    WRectangle(0, TOOLY, 639, TOOLY + 14);
    theme_rect(0, 80, TOOLY >> 3, 2, CHROME);
    UseFont(FONT_UI);
    for (i = 0; i < WMAX; ++i) {
        x = 1 + i * TABW;
        l = x * 8;
        wp = &W[i];
        if (wp->kind == W_FREE)
            continue;
        on = i == cw;
        strncpy(line, i ? wp->name : (S.name[0] ? S.name : "Server"), 12);
        line[12] = 0;
        for (n = 0; line[n]; ++n)
            if (line[n] < 32 || line[n] > 126)
                line[n] = '?';
        if (wp->kind == W_CHAN && !wp->joined && cstate == C_UP)
            line[0] = '(';
        mark = wp->unread == U_MENTION ? '!' : wp->unread ? '*' : 0;
        for (;;) {
            line[n] = mark;
            line[n + 1] = 0;
            w = tabw(on);
            if (w <= (TABW - 1) * 8 - 8 || n < 2)
                break;
            --n;
        }
        if (on && hl)
            theme_rect(x, TABW - 1, TOOLY >> 3, 2, hl);
        WFrameRectangle(0xFF, l, TOOLY + 1, l + (TABW - 1) * 8 - 1, TOOLY + 14);
        currentMode = on ? SET_BOLD : 0;
        WPutString(line, l + (((TABW - 1) * 8 - w) >> 1), TOOLY + 2 + baselineOffset);
        currentMode = 0;
    }
    UseSystemFont();
}

void ui_topic(void)
{
    const char *t = tbuf;
    char *p;
    switch (W[cw].kind) {
    case W_SERV:
        strcpy(tbuf, S.name[0] ? S.name : "No server");
        if (S.host[0]) {
            strcat(tbuf, " (");
            strcat(tbuf, S.host);
            strcat(tbuf, ":");
            p = unum(tbuf + strlen(tbuf), S.port);
            strcpy(p, ")");
        }
        strcat(tbuf, ": the server's messages. Server > Servers... connects.");
        break;
    case W_QUERY:
        strcpy(tbuf, "A private conversation with ");
        strcat(tbuf, W[cw].name);
        break;
    default:
        topic_get(cw, ln, TOPICMAX);
        t = ln;
        if (!ln[0])
            t = W[cw].joined ? "(no topic)" : "(not in this channel: /join it again)";
    }
    put(1, TOPY + 4, t, 78, 0);
    WHorizontalLine(0xFF, 0, 639, BODYY - 2);
}


/*---------------------------------------------------------------- the menus (ui.c's actions) */
void m_about(void), m_quit(void), m_servers(void), m_disc(void);
void m_next(void), m_prev(void), m_close(void), m_pane(void), m_stamps(void), m_clear(void);

struct item { const char *text; unsigned char type; void *p; };
struct menu { unsigned char top, bottom; unsigned int left, right; unsigned char flags; struct item i[1]; };
struct menu2 { unsigned char top, bottom; unsigned int left, right; unsigned char flags; struct item i[2]; };
struct menu3 { unsigned char top, bottom; unsigned int left, right; unsigned char flags; struct item i[3]; };
struct menu6 { unsigned char top, bottom; unsigned int left, right; unsigned char flags; struct item i[6]; };

/* (the texts as arrays: DATA, main RAM; a literal would go to OVL5RO) */
static char t_about[] = "About Veranda Chat";
static char t_quit[] = "\x1f" "Quit\tCtrl Q";
static char t_servers[] = "Servers...";
static char t_disc[] = "Disconnect";
static char t_next[] = "Next\tCtrl N";
static char t_prev[] = "Previous\tCtrl P";
static char t_close[] = "Close\tCtrl W";
static char t_pane[] = "\x1f" "Nick list on/off";
static char t_times[] = "Times on/off";
static char t_clear[] = "\x1f" "Clear";
static char t_app[] = "Veranda Chat";
static char t_server[] = "Server";
static char t_window[] = "Window";
#define IH 14
static struct menu2 mapp = { 14, 14 + 2 * IH, 0, 0, VERTICAL | 2, {
    { t_about, MENU_ACTION, m_about }, { t_quit, MENU_ACTION, m_quit } } };
static struct menu2 mserv = { 14, 14 + 2 * IH, 0, 0, VERTICAL | 2, {
    { t_servers, MENU_ACTION, m_servers }, { t_disc, MENU_ACTION, m_disc } } };
static struct menu6 mwin = { 14, 14 + 6 * IH, 0, 0, VERTICAL | 6, {
    { t_next, MENU_ACTION, m_next }, { t_prev, MENU_ACTION, m_prev },
    { t_close, MENU_ACTION, m_close }, { t_pane, MENU_ACTION, m_pane },
    { t_times, MENU_ACTION, m_stamps }, { t_clear, MENU_ACTION, m_clear } } };
struct menu3 mbar = { 0, 14, 0, 0, HORIZONTAL | UN_CONSTRAINED | 3, {
    { t_app, SUB_MENU, &mapp }, { t_server, SUB_MENU, &mserv }, { t_window, SUB_MENU, &mwin } } };
static const char *const barnames[3] = { t_app, t_server, t_window };

void sv_menus(void)
{
    static struct menu *const lists[3] = { (struct menu *)&mapp, (struct menu *)&mserv, (struct menu *)&mwin };
    unsigned int b, w, wmax;
    unsigned char i, j, c;
    const char *p;
    struct menu *m;
    struct item *t;
    UseFont(FONT_UI);
    for (i = 0; i < 3; ++i) {
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
    mbar.right = vr_bar_end(barnames, 3);
    UseSystemFont();
}
