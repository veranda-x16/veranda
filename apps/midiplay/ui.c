/*
 * ui.c -- MIDI Player's window (overlay 1, mapped for good as appBank: mp.h):
 * Veranda Look 3 "Sunroom", as Disk Tools and About this X16 (apps/sysui):
 * the menu bar, a window with its title band (the song) and close glyph,
 * a toolbar (V206: Previous, Play or Pause, Stop, Next as keys with signs,
 * the volume as a slider, Play next and Repeat as keys lit while on), the
 * playlist (folders and songs, the SDK's scroll bar) at the left, now
 * playing at the right, the voices and the keyboard below (vis.c, overlay
 * 4), and the status bar.
 *
 * Drawing is on the foreground only (dispBufferOn = ST_WR_FORE): menus and
 * dialog boxes keep what they cover. While a menu is open nothing is drawn
 * in the bitmap where a menu hangs (it would draw over the menu): the
 * fields catch up after; the colour map is drawn on, Veranda keeps a
 * covered card's colour.
 *
 * The playlist's rows and the way the selection, the scrolling and the
 * next and previous song go follow the MOD Player's (x16-mod,
 * examples/veranda/vmp_ui.c: MIT, Copyright (c) 2026 Marcin Spoczynski).
 *
 * MIT licence (see LICENSE).
 */
#include "mp.h"
#include <vrwin.h>
#include <theme.h>
#include "../sysui/sysui.h"

#pragma code-name ("OVERLAY1")

/*---------------------------------------------------------------
  the layout (pixels; cards where the colour map is used)
 ---------------------------------------------------------------*/
static const struct vrwin win = { 0, 2, 80, 58, 3, 2, VW_CLOSE };
#define TOOL_Y     32           /* the toolbar: card rows 4-6 */
#define KEY_T      33           /* its keys' top and bottom lines */
#define KEY_B      53
#define PIC_Y      38
#define HEAD_Y     56           /* the panels' heads: card rows 7-8 */
#define LIST_Y     72           /* the playlist's first row (card row 9) */
#define ROW_H      16
#define LIST_N     10           /* rows (card rows 9-28) */
#define LIST_W     32           /* its cards (the scroll bar: 32-33) */
#define LIST_XR    252
#define DIV_X      275          /* the line between the playlist and now playing */
#define PANEL_B    231          /* the panels' bottom (the voices below: vis.c) */
#define PROG_Y     192          /* the progress bar (now.c): card row 24, cards 36-78 */

static struct vrscroll sbar = { 32, 9, 20, 1, 0, LIST_N, 0 };

/*---------------------------------------------------------------
  helpers
 ---------------------------------------------------------------*/
static void clear(unsigned int l, unsigned int t, unsigned int r, unsigned int b)
{
    SetPattern(0);
    WRectangle(l, t, r, b);
}

/* s into sb, cut to w pixels in the UI font ("..." at its end if cut) */
static void fit(const char *s, unsigned int w, unsigned char bold)
{
    unsigned char i = 0, j;
    unsigned int x = 0, dots;
    UseFont(FONT_UI);
    dots = 3 * (GetCharWidth('.') + bold);
    while (s[i] && i < 70) {
        sb[i] = s[i];
        x += GetCharWidth(s[i]) + bold;
        ++i;
    }
    sb[i] = 0;
    if (x > w) {
        while (i && x + dots > w) {
            --i;
            x -= GetCharWidth(sb[i]) + bold;
        }
        for (j = 0; j < 3; ++j)
            sb[i++] = '.';
        sb[i] = 0;
    }
    UseSystemFont();
}

/*---------------------------------------------------------------
  the toolbar (V206): keys with signs (the Calculator's: cut corners, the
  bottom edge two lines deep, a paper colour by role: Play on the
  highlight, a toggle on it while on), the volume as a slider
 ---------------------------------------------------------------*/
#include "pics.h"
struct tkey { unsigned char x, w, pic; const char *t; };
enum { T_PREV, T_PLAY, T_STOP, T_NEXT, T_AUTO, T_REP, NT };
static const struct tkey tkeys[NT] = {
    { 1, 4, PIC_PREV, 0 }, { 6, 4, PIC_PLAY, 0 }, { 11, 4, PIC_STOP, 0 }, { 16, 4, PIC_NEXT, 0 },
    { 56, 11, PIC_ONWARD, "Play next" }, { 68, 11, PIC_REPEAT, "Repeat" } };
#define VOL_C      24           /* the speaker's card */
#define VOL_X0     224          /* the slider: volume 0 at this pixel, 11 pixels a step */
#define VOL_STEP   11
#define VOL_END    (VOL_X0 + 10 * VOL_STEP)
static unsigned char flash_k = 0xFF, flash_n, dragging;

static void key_inv(unsigned char i)
{
    unsigned int l = (unsigned int)tkeys[i].x << 3, r = l + ((unsigned int)tkeys[i].w << 3) - 1;
    WInvertRectangle(l + 2, KEY_T + 2, r - 2, KEY_B - 3);
}

static void tool(unsigned char i)
{
    const struct tkey *k = &tkeys[i];
    unsigned int l = (unsigned int)k->x << 3, r = l + ((unsigned int)k->w << 3) - 1;
    unsigned char on = (i == T_AUTO && play_next) || (i == T_REP && repeat), pic = k->pic;
    if (i == T_PLAY && loaded && !paused)
        pic = PIC_PAUSE;
    clear(l, TOOL_Y, r, TOOL_Y + 22);
    theme_rect(k->x, k->w, TOOL_Y >> 3, 3, on || i == T_PLAY ? hilite : PAPER);
    WHorizontalLine(0xFF, l + 2, r - 2, KEY_T);
    WHorizontalLine(0xFF, l + 2, r - 2, KEY_B);
    WHorizontalLine(0xFF, l + 1, r - 1, KEY_B - 1);
    WVerticalLine(0xFF, l, KEY_T + 2, KEY_B - 2);
    WVerticalLine(0xFF, r, KEY_T + 2, KEY_B - 2);
    WDrawPoint(DRAW_INK, l + 1, KEY_T + 1);
    WDrawPoint(DRAW_INK, r - 1, KEY_T + 1);
    WBitmapUp((void *)pics[pic], k->x + 1, 2, PIC_Y, PIC_H | 0x8000);
    if (k->t)
        ui_text(l + 28, KEY_T + 2, k->t, on);
    if (i == flash_k)
        key_inv(i);
}

static void slider(void)
{
    unsigned int k = VOL_X0 + VOL_STEP * volume;
    char t[8];
    clear(VOL_C * 8, TOOL_Y, VOL_END + 40, TOOL_Y + 22);
    WBitmapUp((void *)pics[volume ? PIC_SPEAKER : PIC_MUTE], VOL_C, 2, PIC_Y, PIC_H | 0x8000);
    WFrameRectangle(0xFF, VOL_X0 - 3, 41, VOL_END + 3, 45);
    SetPattern(1);
    WRectangle(VOL_X0 - 3, 42, k, 44);
    clear(k - 4, 35, k + 4, 51);
    ui_rframe(k - 5, 35, k + 5, 51);
    WVerticalLine(0xFF, k - 2, 40, 46);
    WVerticalLine(0xFF, k, 40, 46);
    WVerticalLine(0xFF, k + 2, 40, 46);
    ui_num(t, volume);
    ui_text(VOL_END + 14, KEY_T + 2, t, 1);
}

static void toolbar(void)
{
    unsigned char i;
    clear(0, TOOL_Y, 638, TOOL_Y + 22);  /* (not whole rows: see vis.c's keyboard) */
    theme_rect(0, 80, TOOL_Y >> 3, 3, CHROME);
    for (i = 0; i < NT; ++i)
        tool(i);
    slider();
}

static unsigned char tool_at(unsigned int x)
{
    unsigned char i;
    x >>= 3;
    for (i = 0; i < NT; ++i)
        if (x >= tkeys[i].x && x < tkeys[i].x + tkeys[i].w)
            return i;
    return 0xFF;
}

/* a key clicked or typed: shown inverted for a moment (update puts it back) */
static void flash(unsigned char i)
{
    if (flash_k != 0xFF)
        key_inv(flash_k);
    flash_k = i;
    flash_n = 3;
    key_inv(i);
}

/*---------------------------------------------------------------
  the title band and the status bar
 ---------------------------------------------------------------*/
static const char *const errs[] = { "", "Cannot open the file", "The file is empty",
    "Too big for the free memory", "The file could not be read",
    "Not a MIDI file it can play (type 0 or 1, up to 32 tracks)", "Not a ZSM file (version 1)" };
static char st_left[80];

/* (V206) The title band's and the status bar's texts drawn again as the
   SDK's vr_win_title and vr_win_status draw them, but the bands cleared
   short of the screen's last column: the kernel fills whole rows with the
   interrupt off (up to 5,400 cycles, its FX fills, V68), which would make
   the music's tick late while a song plays (these are drawn as one starts
   and at every change of state); a narrower fill goes row by row. */
static void title(void)
{
    unsigned int w;
    fit(loaded ? playing_name : "MIDI Player", 400, 1);
    clear(0, 16, 638, 30);
    WFrameRectangle(0xFF, 622, 19, 632, 29);   /* (the close box) */
    WDrawLine(DRAW_INK, 624, 21, 630, 27);
    WDrawLine(DRAW_INK, 630, 21, 624, 27);
    w = ui_width(sb, 1);
    ui_text((639 - w) >> 1, 16, sb, 1);
}

static void status(const char *s)
{
    static char right[40];
    unsigned int w;
    if (s)
        strncpy(st_left, s, sizeof st_left - 1);
    strcpy(right, play_next ? "Play next on" : "Play next off");
    strcat(right, repeat ? ", repeat on" : ", repeat off");
    clear(0, 465, 638, 479);
    w = ui_width(right, 0);
    ui_text(631 - w, 464, right, 0);
    fit(st_left, 631 - w - 22, 0);
    ui_text(6, 464, sb, 0);
}

static void status_state(void)
{
    status(loaded ? (paused ? "Paused" : "Playing") : "Stopped");
}

/*---------------------------------------------------------------
  the playlist: rows of 16 pixels, a picture and the name; the selection
  in the highlight; the song playing bold, with a mark
 ---------------------------------------------------------------*/
/* 8 x 8 pictures (GEOS compacted bitmaps), the MOD Player's (x16-mod);
   a ZSM's note has two flags (V206) */
static const unsigned char pic_folder[9] = { 0x83, 0x00, 0x70, 0x8F, 0x03, 0x81, 0x82, 0xFF, 0x00 };
static const unsigned char pic_note[9] = { 0x88, 0x0C, 0x0A, 0x09, 0x08, 0x38, 0x78, 0x30, 0x00 };
static const unsigned char pic_zsm[9] = { 0x88, 0x1F, 0x11, 0x1F, 0x11, 0x33, 0x77, 0x22, 0x00 };
static const unsigned char pic_up[9] = { 0x88, 0x10, 0x38, 0x54, 0x10, 0x10, 0x1E, 0x00, 0x00 };
static const unsigned char pic_playing[9] = { 0x88, 0x40, 0x60, 0x70, 0x78, 0x70, 0x60, 0x40, 0x00 };

static void heads(void)
{
    clear(0, HEAD_Y, 638, HEAD_Y + 15);
    theme_rect(0, 34, HEAD_Y >> 3, 2, CHROME);
    theme_rect(35, 45, HEAD_Y >> 3, 2, CHROME);
    theme_rect(34, 1, HEAD_Y >> 3, 22, PAPER);
    WVerticalLine(0xFF, DIV_X, HEAD_Y, PANEL_B);
    ui_text(288, HEAD_Y, "Now playing", 1);
}

static void list_head(void)
{
    char *p;
    clear(0, HEAD_Y, DIV_X - 1, HEAD_Y + 15);
    ui_text(8, HEAD_Y, "Playlist", 1);
    fit((const char *)curDirName, 120, 0);
    ui_text(76, HEAD_Y, sb, 0);
    p = ui_num(sb + 40, n_songs);
    strcpy(p, n_songs == 1 ? " song" : " songs");
    ui_text(LIST_XR + 16 - ui_width(sb + 40, 0), HEAD_Y, sb + 40, 0);
}

static void list_mark(unsigned char r, unsigned char on)
{
    theme_rect(0, LIST_W, (LIST_Y >> 3) + 2 * r, 2, on ? hilite : PAPER);
}

static void list_row(unsigned char r)
{
    unsigned char e = (unsigned char)(top + r), pl;
    unsigned int y = LIST_Y + r * ROW_H;
    const unsigned char *pic;
    clear(0, y, LIST_W * 8 - 1, y + ROW_H - 1);
    list_mark(r, e == sel && e < n_ent);
    if (e >= n_ent)
        return;
    ent_get(e);
    pl = e == playing_ent && loaded;
    pic = cur[0] == E_UP ? pic_up : cur[0] == E_DIR ? pic_folder : cur[0] == E_ZSM ? pic_zsm : pic_note;
    if (pl)
        WBitmapUp((void *)pic_playing, 0, 1, y + 4, 8);
    WBitmapUp((void *)pic, 1, 1, y + 4, 8);
    fit(cur[0] == E_UP ? ".." : cur + 1, LIST_XR - 20, pl);
    ui_text(20, y, sb, pl);
}

static void list_bar(void)
{
    sbar.first = top;
    sbar.total = n_ent;
    vr_scroll(&sbar);
}

static void list_draw(void)
{
    unsigned char r;
    for (r = 0; r < LIST_N; ++r)
        list_row(r);
    list_bar();
}

static void row_of(unsigned char e)
{
    if (e != 0xFF && e >= top && e < top + LIST_N)
        list_row(e - top);
}

/* the list scrolled so that its first row is t */
static void scroll_to(int t)
{
    int most = n_ent > LIST_N ? n_ent - LIST_N : 0;
    if (t > most)
        t = most;
    if (t < 0)
        t = 0;
    if ((unsigned char)t == top)
        return;
    top = (unsigned char)t;
    list_draw();
}

static void select_entry(int e)
{
    unsigned char old = sel, t = top;
    if (!n_ent)
        return;
    if (e < 0)
        e = 0;
    if (e >= n_ent)
        e = n_ent - 1;
    sel = (unsigned char)e;
    if (sel < top)
        top = sel;
    else if (sel >= top + LIST_N)
        top = sel - LIST_N + 1;
    if (top != t)
        list_draw();
    else {
        if (old >= top && old < top + LIST_N)
            list_mark(old - top, 0);
        list_mark(sel - top, 1);
    }
}

/*---------------------------------------------------------------
  playing
 ---------------------------------------------------------------*/
/* everything that shows the song */
static void track(void)
{
    title();
    VIS(vis_song);
    tool(T_PLAY);
    status_state();
}

/* The playlist's place: the entry last played or tried (0xFF none), in
   the folder playing_dir: next and previous go on from it. */
static unsigned char q_pos = 0xFF;
static unsigned char fade;

void ui_play(unsigned char e)
{
    unsigned char was = playing_ent, r;
    ent_get(e);
    if (cur[0] == E_LONG) {
        status("The name is too long to open");
        Beep();
        return;
    }
    if (strcmp(playing_dir, (const char *)curDirName))
        strcpy(playing_dir, (const char *)curDirName);
    q_pos = e;
    fade = 0;
    status("Loading...");
    SetPointer(PTR_BUSY);
    r = play_entry(e);
    if (!r)
        INFO(info_scan);                /* (the music plays meanwhile) */
    SetPointer(PTR_ARROW);
    row_of(was);
    if (r) {
        track();
        status(errs[r]);
        Beep();
        return;
    }
    row_of(e);
    select_entry(e);
    track();
}

/* the next or previous song, wrapping at the list's ends (wrap 0: none
   after the last: stopped); a song that does not load is passed over */
static void stop_cmd(void);
static void step(signed char d, unsigned char wrap)
{
    unsigned char e, k, n;
    if (music_dir())
        ui_list();
    if (!n_songs)
        return;
    e = q_pos < n_ent ? q_pos : (d > 0 ? n_ent - 1 : 0);
    for (n = 0; n < n_songs; ++n) {
        for (k = 0; k < n_ent; ++k) {
            e = (unsigned char)(e + d);
            if (e >= n_ent) {
                if (!wrap) {
                    stop_cmd();
                    return;
                }
                e = d > 0 ? 0 : n_ent - 1;
            }
            ent_get(e);
            if (cur[0] == E_MIDI || cur[0] == E_ZSM)
                break;
        }
        if (cur[0] != E_MIDI && cur[0] != E_ZSM)
            return;
        ui_play(e);
        if (loaded)
            return;
    }
}

static void stop_cmd(void)
{
    unsigned char was = playing_ent;
    stop();
    playing_ent = 0xFF;
    fade = 0;
    row_of(was);
    track();
    LOG("MP STOP", 0);
}

static void pause_toggle(void)
{
    if (!loaded) {
        if (n_ent && sel < n_ent) {
            ent_get(sel);
            if (cur[0] == E_MIDI || cur[0] == E_ZSM) {
                ui_play(sel);
                return;
            }
        }
        step(1, 1);
        return;
    }
    pause_set(!paused);
    tool(T_PLAY);
    status_state();
    LOG(paused ? "MP PAUSE" : "MP RESUME", 0);
}

/* the song ended by itself */
static void song_end(void)
{
    fade = 0;
    if (repeat) {
        LOG("MP REPEAT", 0);
        restart();
    } else if (play_next) {
        LOG("MP SONG END", 0);
        step(1, 0);
    } else {
        LOG("MP SONG END", 0);
        stop_cmd();
    }
}

static void volume_to(signed char v)
{
    if (v < 0)
        v = 0;
    if (v > 10)
        v = 10;
    if ((unsigned char)v == volume)
        return;
    set_volume((unsigned char)v);
    slider();
}

static void volume_by(signed char d)
{
    volume_to((signed char)volume + d);
}

static void m_quit(void);
static void menu_marks(void);

static void toggle_next(void)
{
    play_next = !play_next;
    tool(T_AUTO);
    menu_marks();
    status(0);
}

static void toggle_repeat(void)
{
    repeat = !repeat;
    if (repeat && fade) {               /* (a ZSM fading out: it goes on looping) */
        fade = 0;
        eng_volume(volume);
    }
    tool(T_REP);
    menu_marks();
    status(0);
}

/*---------------------------------------------------------------
  folders
 ---------------------------------------------------------------*/
void ui_list(void)
{
    SetPointer(PTR_BUSY);
    list_read();
    SetPointer(PTR_ARROW);
    q_pos = playing_dir[0] && !strcmp(playing_dir, (const char *)curDirName) ? find_entry(playing_name) : 0xFF;
    playing_ent = loaded ? q_pos : 0xFF;
    list_head();
    list_draw();
}

static void enter(const char *name)
{
    unsigned char l;
    if (name[0] == '.' && name[1] == '.') {
        if (at_root())
            return;
        /* (the parent by its whole path, not "..": the DOS's folder and
           curDirName stay the same one) */
        l = (unsigned char)strlen((char *)curDirName);
        while (l > 1 && curDirName[--l] != '/')
            ;
        {
            char keep = curDirName[l ? l : 1];
            curDirName[l ? l : 1] = 0;
            if (ChDir((void *)curDirName)) {
                curDirName[l ? l : 1] = keep;
                status("Cannot open the folder");
                return;
            }
        }
    } else {
        l = (unsigned char)strlen((char *)curDirName);
        if (l + strlen(name) + 2 > 61 || ChDir((void *)name)) {
            status("Cannot open the folder");
            Beep();
            return;
        }
        if (l > 1)
            curDirName[l++] = '/';
        strcpy((char *)curDirName + l, name);
    }
    ui_list();
    LOG("MP FOLDER", (const char *)curDirName);
}

static void open_entry(unsigned char e)
{
    static char name[64];
    ent_get(e);
    if (cur[0] == E_DIR || cur[0] == E_UP) {
        strcpy(name, cur + 1);
        enter(name);
    } else
        ui_play(e);
}

/*---------------------------------------------------------------
  the menus
 ---------------------------------------------------------------*/
struct item { const char *text; unsigned char type; void *p; };
struct menu2 { unsigned char top, bottom; unsigned int left, right; unsigned char flags; struct item i[2]; };
struct menu8 { unsigned char top, bottom; unsigned int left, right; unsigned char flags; struct item i[8]; };

static void m_about(void), m_play(void), m_stop(void), m_next(void), m_prev(void);
static void m_loud(void), m_soft(void), m_auto(void), m_rep(void);
#define IH 14
static const char t_auto0[] = "\x1f" "Play next: off\tN", t_auto1[] = "\x1f" "Play next: on\tN";
static const char t_rep0[] = "Repeat: off\tR", t_rep1[] = "Repeat: on\tR";
static struct menu2 mapp = { 14, 14 + 2 * IH, 0, 0, VERTICAL | 2, {
    { "About MIDI Player...", MENU_ACTION, m_about }, { "\x1f" "Quit\tCtrl Q", MENU_ACTION, m_quit } } };
static struct menu8 mplay = { 14, 14 + 8 * IH, 0, 0, VERTICAL | 8, {
    { "Play or pause\tSpace", MENU_ACTION, m_play }, { "Stop\tEsc", MENU_ACTION, m_stop },
    { "Next\tRight", MENU_ACTION, m_next }, { "Previous\tLeft", MENU_ACTION, m_prev },
    { "\x1f" "Volume up\t+", MENU_ACTION, m_loud }, { "Volume down\t-", MENU_ACTION, m_soft },
    { t_auto1, MENU_ACTION, m_auto }, { t_rep0, MENU_ACTION, m_rep } } };
static struct { unsigned char top, bottom; unsigned int left, right; unsigned char flags; struct item i[2]; } mbar = {
    0, 14, 0, 0, HORIZONTAL | UN_CONSTRAINED | 2, {
    { "MIDI Player", SUB_MENU, &mapp }, { "Play", SUB_MENU, &mplay } } };
static const char *const barnames[2] = { "MIDI Player", "Play" };
static const char *const longest[2] = { "About MIDI Player...", "Play or pause\tSpace" };
static unsigned int *const lefts[2] = { &mapp.left, &mplay.left };
static unsigned int *const rights[2] = { &mapp.right, &mplay.right };
unsigned int barx[2], barl[2];

static void menu_marks(void)
{
    mplay.i[6].text = play_next ? t_auto1 : t_auto0;
    mplay.i[7].text = repeat ? t_rep1 : t_rep0;
}

static void m_about(void)
{
    GotoFirstMenu();
    ui_message("MIDI Player 1.1: MIDI and ZSM on the YM2151 and PSG.",
               "Melodius, ZSMKit (c) 2023 MooingLemur. MIT licence.");
}

static void m_quit(void)
{
    GotoFirstMenu();
    LOG("MP QUIT", 0);
#ifdef MP_TEST
    {
        extern void mp_test_quit(void);
        mp_test_quit();
    }
#endif
    stop();
    eng_silence();
    eng_irq_off();
    EnterDeskTop();
}

static void m_play(void) { GotoFirstMenu(); pause_toggle(); }
static void m_stop(void) { GotoFirstMenu(); stop_cmd(); }
static void m_next(void) { GotoFirstMenu(); step(1, 1); }
static void m_prev(void) { GotoFirstMenu(); step(-1, 1); }
static void m_loud(void) { GotoFirstMenu(); volume_by(1); }
static void m_soft(void) { GotoFirstMenu(); volume_by(-1); }
static void m_auto(void) { GotoFirstMenu(); toggle_next(); }
static void m_rep(void) { GotoFirstMenu(); toggle_repeat(); }

/*---------------------------------------------------------------
  the pointer and the keys
 ---------------------------------------------------------------*/
static void do_tool(unsigned char t)
{
    if (t == 0xFF)
        return;
    flash(t);
    switch (t) {
    case T_PREV: step(-1, 1); break;
    case T_PLAY: pause_toggle(); break;
    case T_STOP: stop_cmd(); break;
    case T_NEXT: step(1, 1); break;
    case T_AUTO: toggle_next(); break;
    case T_REP: toggle_repeat(); break;
    }
}

static signed char vol_at(unsigned int x)
{
    return (signed char)(((int)x - VOL_X0 + VOL_STEP / 2 + VOL_STEP) / VOL_STEP - 1);
}

static void pressed(void)
{
    unsigned int x, y;
    unsigned char e;
    if (mouseData & 0x80)
        return;                         /* a release */
    do {
        x = mouseXPos;
        y = mouseYPosW;
    } while (x != mouseXPos || y != mouseYPosW);
    if (vr_win_hit(&win, x, y) == VW_XCLOSE) {
        m_quit();
        return;
    }
    if (y >= TOOL_Y && y < HEAD_Y) {
        if (x >= VOL_C * 8 && x < VOL_END + 12) {
            volume_to(vol_at(x));
            dragging = 1;
        } else
            do_tool(tool_at(x));
        return;
    }
    if (y >= PROG_Y - 4 && y < PROG_Y + 12 && x >= 284 && x < 636) {
        vis_x = x;
        NOW(now_where);
        status(sb);
        return;
    }
    if (y < LIST_Y || y >= LIST_Y + LIST_N * ROW_H)
        return;
    if (x >= LIST_W * 8 && x < LIST_W * 8 + 16) {
        switch (vr_scroll_hit(&sbar, x, y)) {
        case VS_BACK: scroll_to((int)top - 1); break;
        case VS_FWD: scroll_to((int)top + 1); break;
        case VS_PGBACK: scroll_to((int)top - (LIST_N - 1)); break;
        case VS_PGFWD: scroll_to((int)top + (LIST_N - 1)); break;
        }
        return;
    }
    if (x >= LIST_W * 8)
        return;
    e = (unsigned char)(top + (y - LIST_Y) / ROW_H);
    if (e >= n_ent)
        return;
    if (e == sel && dblClickCount) {
        dblClickCount = 0;
        open_entry(e);
        return;
    }
    select_entry(e);
    dblClickCount = CLICK_COUNT;
}

static void key(void)
{
    unsigned char k = keyData;
    if (menuNumber)
        return;                         /* (a menu is open: it would be drawn over) */
    if (k == ' ')
        do_tool(T_PLAY);
    else if (k == KEY_RIGHT)
        do_tool(T_NEXT);
    else if (k == KEY_LEFT && (keyDataMods & KEYM_ARROW))
        do_tool(T_PREV);
    else if (k == KEY_ESC)
        do_tool(T_STOP);
    else if (k == '+' || k == '=')
        volume_by(1);
    else if (k == '-')
        volume_by(-1);
    else if (k == 'n' || k == 'N')
        do_tool(T_AUTO);
    else if (k == 'r' || k == 'R')
        do_tool(T_REP);
    else if (k == (SHORTCUT | 'q') || (k == 'q' - 96 && (keyDataMods & (2 | KEYM_ARROW)) == 2))
        m_quit();                       /* Alt Q, Ctrl Q (KEY_DOWN is 17 too) */
    else if (k == KEY_UP)
        select_entry((int)sel - 1);
    else if (k == KEY_DOWN)
        select_entry((int)sel + 1);
    else if (k == KEY_PGUP)
        select_entry((int)sel - (LIST_N - 1));
    else if (k == KEY_PGDN)
        select_entry((int)sel + (LIST_N - 1));
    else if (k == KEY_HOME)
        select_entry(0);
    else if (k == KEY_END)
        select_entry(255);
    else if (k == KEY_LEFT)             /* Backspace: up a folder */
        enter("..");
    else if (k == CR && n_ent)
        open_entry(sel);
}

/*---------------------------------------------------------------
  the window drawn whole (at the start; again when the theme changed while
  the program was aside)
 ---------------------------------------------------------------*/
static struct theme seen;

static void draw_all(void)
{
    theme_palette();
    hilite = theme.hilite ? theme.hilite : SELECT;
    memcpy(&seen, &theme, sizeof seen);
    vr_win(&win, "MIDI Player");
    theme_menus();
    DoMenu((void *)&mbar, 0);
    toolbar();
    heads();
    list_head();
    list_draw();
    VIS(vis_frame);
    track();
}

/*---------------------------------------------------------------
  Alt+Tab: Veranda calls nothing of a program put aside, so the music
  pauses (asideVector) and goes on when the main loop runs again here
 ---------------------------------------------------------------*/
static unsigned char asided, aside_play;

static void aside(void)
{
    aside_play = loaded && !paused;
    if (aside_play)
        pause_set(1);
    asided = 1;
    LOG("MP ASIDE", 0);
}

/*---------------------------------------------------------------
  the main loop's work: at most 20 updates a second
 ---------------------------------------------------------------*/
static unsigned int last_tick;

static void update(void)
{
    signed char w;
    unsigned char st;
    if (asided) {                       /* (back, or the switcher's box cancelled) */
        asided = 0;
        eng_irq_on();
        theme_load();                   /* (the theme changed meanwhile: drawn again) */
        if (memcmp(&seen, &theme, sizeof seen))
            draw_all();
        if (aside_play) {
            pause_set(0);
            tool(T_PLAY);
            status_state();
        }
        LOG("MP BACK", 0);
    }
#ifdef MP_TEST
    mp_test_tick();
#endif
    if (dragging) {                     /* (the volume's knob follows the pointer while held) */
        if (mouseData & 0x80)
            dragging = 0;
        else
            volume_to(vol_at(mouseXPos));
    }
    if ((unsigned int)(eng_ticks - last_tick) < 3)
        return;
    last_tick = eng_ticks;
    asm("sei");
    w = (signed char)mouseWheel;
    mouseWheel = 0;
    asm("cli");
    if (flash_n && !--flash_n) {
        key_inv(flash_k);
        flash_k = 0xFF;
    }
    if (loaded && !paused) {
        if (kind == E_MIDI) {
            if (!eng_midi_playing()) {
                song_end();
                return;
            }
        } else {
            st = eng_zsm_state();
            if (!(st & 1)) {
                song_end();
                return;
            }
            /* a ZSM that loops: once round, then faded out (Repeat: it goes on) */
            if (eng_loops && !repeat && !fade)
                fade = 1;
            if (fade) {
                if (++fade >= 30) {
                    song_end();
                    set_volume(volume);
                    return;
                }
                if (!(fade & 3) && volume > fade / 4)
                    eng_volume((unsigned char)(volume - fade / 4));
            }
        }
    }
#ifdef MP_TEST
    {
        extern void t_ui_begin(void), t_ui_end(void);
        t_ui_begin();                   /* (the window's work measured: the meters, the keys, the display) */
        VIS(vis_tick);
        t_ui_end();
    }
#else
    VIS(vis_tick);
#endif
    if (w && !menuNumber)
        scroll_to((int)top + 3 * w);
}

/*---------------------------------------------------------------
  the start
 ---------------------------------------------------------------*/
void ui_start(void)
{
    dispBufferOn = ST_WR_FORE;
    SetPattern(0);
    WRectangle(0, 0, 639, 15);
    theme_load();
    ui_menus(barnames, 2, (unsigned int **)lefts, (unsigned int **)rights, longest, &mbar.right, barx, barl);
    menu_marks();
    draw_all();
    otherPressVec = VR_FN(pressed);
    keyVector = VR_FN(key);
    asideVector = VR_FN(aside);
    appMain = VR_FN(update);
#ifdef MP_TEST
    mp_test_start();
#endif
}

#ifdef MP_TEST
/* (the test build's driver, tests/midiplay_play.c, works the program
   through these) */
void t_pause_toggle(void) { pause_toggle(); }
void t_stop(void) { stop_cmd(); }
void t_step(signed char d) { step(d, 1); }
void t_volume(signed char d) { volume_by(d); }
void t_toggle_next(void) { toggle_next(); }
void t_toggle_repeat(void) { toggle_repeat(); }
void t_enter(const char *name) { enter(name); }
void t_quit(void) { m_quit(); }
void t_select(unsigned char e) { select_entry(e); }
void t_scroll(int t) { scroll_to(t); }
void t_redraw(void)                     /* the window's body drawn again whole */
{
    list_head();
    list_draw();
    VIS(vis_frame);
    VIS(vis_song);
}
void t_dark(unsigned char on)           /* dark mode or light (the system's setting, as
                                           Preferences sets it), the window drawn again */
{
    unsigned char p[PREFS_SIZE];
    SysPrefs(PREFS_GET, p);
    p[PREFS_LOOK] = on ? p[PREFS_LOOK] | LOOK_DARK : p[PREFS_LOOK] & ~LOOK_DARK;
    SysPrefs(PREFS_SET, p);
    theme_load();
    draw_all();
}
#endif
