/*
 * ui.c -- MIDI Player's window (overlay 1, mapped for good as appBank: mp.h):
 * Veranda Look 3 "Sunroom", as Disk Tools and About this X16 (apps/sysui):
 * the menu bar, a window with its title band (the song) and close glyph,
 * a toolbar (Previous, Play or Pause, Stop, Next, Volume - and +, Play next,
 * Repeat: the two last highlighted while on), the playlist (folders and
 * songs, the SDK's scroll bar) at the left, now playing at the right (the
 * song, its form, tempo or tick rate, bar and beat, the time, the size, the
 * volume, a progress bar, the YM2151's eight channels and the PSG's sixteen
 * voices lit while they sound, a MIDI file's text), and the status bar.
 *
 * Drawing is on the foreground only (dispBufferOn = ST_WR_FORE): menus and
 * dialog boxes keep what they cover. While a menu is open nothing is drawn
 * in the bitmap (it would draw over the menu): the fields catch up after;
 * the colour map (the voices, the progress bar) is drawn on, Veranda keeps
 * a covered card's colour.
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
static const struct vrwin win = { 0, 2, 80, 58, 2, 2, VW_CLOSE };
#define TOOL_Y     32           /* the toolbar: card rows 4-5 */
#define HEAD_Y     48           /* the panels' heads: card rows 6-7 */
#define LIST_Y     64           /* the playlist's first row (card row 8) */
#define ROW_H      16
#define LIST_N     25           /* rows (card rows 8-57) */
#define LIST_W     40           /* its cards (the scroll bar: 40-41) */
#define LIST_XR    316
#define RX         352          /* now playing: the labels */
#define VX         440          /* the values */
#define VW         192
#define PROG_COL   44           /* the progress bar: card row 26 */
#define PROG_W     34
#define PROG_ROW   26
#define YM_ROW     30           /* the YM2151's channels: card rows 30-31 */
#define PSG_ROW    35           /* the PSG's voices: card row 35 */

static struct vrscroll sbar = { 40, 8, 50, 1, 0, LIST_N, 0 };
static unsigned char hilite;

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

/* a field: the band at y cleared from x for w pixels, s in it */
static void field(unsigned int x, unsigned int y, unsigned int w, const char *s, unsigned char bold)
{
    clear(x, y, x + w - 1, y + 15);
    fit(s, w, bold);
    ui_text(x, y, sb, bold);
}

static char *bcd(char *p, unsigned char v, unsigned char lead)
{
    if (!lead || v >> 4)
        *p++ = '0' + (v >> 4);
    *p++ = '0' + (v & 15);
    *p = 0;
    return p;
}

static char *mmss(char *p, unsigned int s)
{
    p = ui_num(p, s / 60);
    *p++ = ':';
    return ui_dd(p, (unsigned char)(s % 60));
}

/*---------------------------------------------------------------
  the toolbar: buttons of its own (a toggle highlighted while on)
 ---------------------------------------------------------------*/
struct tbtn { unsigned char x, w; const char *t; };
enum { T_PREV, T_PLAY, T_STOP, T_NEXT, T_SOFT, T_LOUD, T_AUTO, T_REP, NT };
static const struct tbtn tbtns[NT] = {
    { 1, 9, "Previous" }, { 11, 8, "Play" }, { 20, 7, "Stop" }, { 28, 7, "Next" },
    { 37, 10, "Volume -" }, { 48, 10, "Volume +" }, { 61, 11, "Play next" }, { 73, 7, "Repeat" } };

static void tool(unsigned char i)
{
    const struct tbtn *b = &tbtns[i];
    unsigned int l = (unsigned int)b->x << 3, r = l + ((unsigned int)b->w << 3) - 1, w;
    unsigned char on = (i == T_AUTO && play_next) || (i == T_REP && repeat);
    const char *t = b->t;
    if (i == T_PLAY && loaded && !paused)
        t = "Pause";
    clear(l, TOOL_Y, r, TOOL_Y + 14);
    theme_rect(b->x, b->w, TOOL_Y >> 3, 2, on ? hilite : PAPER);
    w = ui_width(t, on);
    ui_text(l + ((r - l + 1 - w) >> 1), TOOL_Y + 1, t, on);
    ui_rframe(l, TOOL_Y + 1, r, TOOL_Y + 14);
}

static void toolbar(void)
{
    unsigned char i;
    clear(0, TOOL_Y, 639, TOOL_Y + 14);
    theme_rect(0, 80, TOOL_Y >> 3, 2, CHROME);
    for (i = 0; i < NT; ++i)
        tool(i);
}

static unsigned char tool_at(unsigned int x)
{
    unsigned char i;
    x >>= 3;
    for (i = 0; i < NT; ++i)
        if (x >= tbtns[i].x && x < tbtns[i].x + tbtns[i].w)
            return i;
    return 0xFF;
}

/*---------------------------------------------------------------
  the title band and the status bar
 ---------------------------------------------------------------*/
static const char *const errs[] = { "", "Cannot open the file", "The file is empty",
    "Too big for the free memory", "The file could not be read",
    "Not a MIDI file it can play (type 0 or 1, up to 32 tracks)", "Not a ZSM file (version 1)" };
static char st_left[64];

static void title(void)
{
    fit(loaded ? playing_name : "MIDI Player", 400, 1);
    vr_win_title(&win, sb);
}

static void status(const char *s)
{
    static char right[40];
    if (s)
        strcpy(st_left, s);
    strcpy(right, play_next ? "Play next on" : "Play next off");
    strcat(right, repeat ? ", repeat on" : ", repeat off");
    vr_win_status(&win, st_left, right);
}

static void status_state(void)
{
    status(loaded ? (paused ? "Paused" : "Playing") : "Stopped");
}

/*---------------------------------------------------------------
  the playlist: rows of 16 pixels, a picture and the name; the selection
  in the highlight; the song playing bold, with a mark
 ---------------------------------------------------------------*/
/* 8 x 8 pictures (GEOS compacted bitmaps), the MOD Player's (x16-mod) */
static const unsigned char pic_folder[9] = { 0x83, 0x00, 0x70, 0x8F, 0x03, 0x81, 0x82, 0xFF, 0x00 };
static const unsigned char pic_note[9] = { 0x88, 0x0C, 0x0A, 0x09, 0x08, 0x38, 0x78, 0x30, 0x00 };
static const unsigned char pic_up[9] = { 0x88, 0x10, 0x38, 0x54, 0x10, 0x10, 0x1E, 0x00, 0x00 };
static const unsigned char pic_playing[9] = { 0x88, 0x40, 0x60, 0x70, 0x78, 0x70, 0x60, 0x40, 0x00 };

static void list_head(void)
{
    char *p;
    clear(0, HEAD_Y, 335, HEAD_Y + 15);
    ui_text(8, HEAD_Y, "Playlist", 1);
    fit((const char *)curDirName, 170, 0);
    ui_text(76, HEAD_Y, sb, 0);
    p = ui_num(sb + 40, n_songs);
    strcpy(p, n_songs == 1 ? " song" : " songs");
    ui_text(LIST_XR + 12 - ui_width(sb + 40, 0), HEAD_Y, sb + 40, 0);
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
    pic = cur[0] == E_UP ? pic_up : cur[0] == E_DIR ? pic_folder : pic_note;
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
  now playing: the fields, each drawn again when its value changes
 ---------------------------------------------------------------*/
enum { F_TEMPO, F_BAR, F_TIME, F_VOL, F_N };
static const unsigned int f_y[F_N] = { 108, 124, 140, 172 };
static unsigned int f_last[F_N];
static unsigned char prog_n, voices[24], v_last[24], lyr[33];
static unsigned int zsm_rate;
static unsigned char zsm_loop;
static unsigned long midi_total;

static void labels(void)
{
    unsigned char i;
    clear(344, HEAD_Y, 639, 463);
    ui_text(352, HEAD_Y, "Now playing", 1);
    ColorRect(PROG_COL, PROG_W, PROG_ROW, 1, CHROME);
    WFrameRectangle(0xFF, PROG_COL * 8 - 1, PROG_ROW * 8 - 1, (PROG_COL + PROG_W) * 8, PROG_ROW * 8 + 8);
    ui_text(RX, 172, "Volume", 0);
    ui_text(RX, 188, "Progress", 0);
    ui_text(RX, 222, "YM2151", 0);
    ui_text(RX, 258, "PSG", 0);
    for (i = 0; i < 8; ++i)
        WFrameRectangle(0xFF, (PROG_COL + 4 * i) * 8 - 1, YM_ROW * 8 - 1, (PROG_COL + 4 * i + 3) * 8, YM_ROW * 8 + 16);
    for (i = 0; i < 16; ++i)
        WFrameRectangle(0xFF, (PROG_COL + 2 * i) * 8 - 1, PSG_ROW * 8 - 1, (PROG_COL + 2 * i + 1) * 8, PSG_ROW * 8 + 8);
    ui_text(RX, 312, "Keys", 1);
    ui_text(RX, 330, "Space play or pause, Esc stop", 0);
    ui_text(RX, 346, "Left and Right: the previous, the next", 0);
    ui_text(RX, 362, "+ and -: the volume", 0);
    ui_text(RX, 378, "N play next, R repeat", 0);
    ui_text(RX, 394, "Return play, Backspace up a folder", 0);
    prog_n = 0;
}

/* the song's own lines: its name, its form, the size */
static void now_static(void)
{
    char s[48], *p;
    unsigned char i;
    clear(RX, 64, 639, 101);
    clear(RX, 108, 639, 171);
    for (i = 0; i < F_N; ++i)
        f_last[i] = 0xFFFF;
    lyr[0] = 0xFF;
    if (!loaded) {
        field(RX, 68, 280, "Nothing is playing.", 1);
        clear(RX, 296, 639, 311);
        return;
    }
    field(RX, 68, 280, playing_name, 1);
    if (kind == E_MIDI) {
        strcpy(s, "MIDI file, type ");
        p = ui_num(s + 16, midi_format);
        strcpy(p, ", ");
        p = ui_num(p + 2, midi_ntracks);
        strcpy(p, midi_ntracks == 1 ? " track" : " tracks");
        midi_total = song_size - 14 - 8 * (unsigned long)midi_ntracks;
        ui_text(RX, 124, "Bar", 0);
        ui_text(RX, 108, "Tempo", 0);
    } else {
        unsigned char h[16];
        strcpy(s, "ZSM file");
        song_peek(h, 16);               /* (the header: the tick rate, the loop point) */
        zsm_rate = h[12] | (unsigned int)h[13] << 8;
        zsm_loop = (h[3] | h[4] | h[5]) != 0;
        strcat(s, zsm_loop ? ", loops" : ", plays once");
        ui_text(RX, 124, "Played", 0);
        ui_text(RX, 108, "Tick rate", 0);
    }
    field(RX, 86, 280, s, 0);
    ui_text(RX, 140, "Time", 0);
    ui_text(RX, 156, "Size", 0);
    ui_size(s, song_size);
    field(VX, 156, VW, s, 0);
    if (kind == E_MIDI)
        ui_text(RX, 296, "Text", 0);
    else
        clear(RX, 296, 639, 311);
}

static void progress(void)
{
    unsigned char n = 0;
    unsigned long a, t;
    if (loaded) {
        if (kind == E_MIDI) {
            a = eng_midi_pos();
            t = midi_total;
        } else {
            a = eng_zsm_pos();
            t = song_size;
        }
        if (t) {
            while (t > 0xFFFFFUL) {     /* (the product in 32 bits) */
                t >>= 4;
                a >>= 4;
            }
            n = a >= t ? PROG_W : (unsigned char)((a * PROG_W) / t);
        }
    }
    if (n > prog_n)
        ColorRect(PROG_COL + prog_n, n - prog_n, PROG_ROW, 1, hilite);
    else if (n < prog_n)
        ColorRect(PROG_COL + n, prog_n - n, PROG_ROW, 1, CHROME);
    prog_n = n;
}

static void voices_draw(void)
{
    unsigned char i;
    eng_voices(voices);
    if (!loaded || paused)
        memset(voices, 0, sizeof voices);
    for (i = 0; i < 24; ++i)
        if (voices[i] != v_last[i]) {
            v_last[i] = voices[i];
            if (i < 8)
                ColorRect(PROG_COL + 4 * i, 3, YM_ROW, 2, voices[i] ? GREEN : PAPER);
            else
                ColorRect(PROG_COL + 2 * (i - 8), 1, PSG_ROW, 1, voices[i] ? YELLOW : PAPER);
        }
}

static void fields(void)
{
    char s[40], *p;
    unsigned int v;
    unsigned char i;
    if (volume != f_last[F_VOL]) {
        f_last[F_VOL] = volume;
        p = ui_num(s, volume);
        strcpy(p, volume ? " of 10" : " of 10 (silent)");
        field(VX, f_y[F_VOL], VW, s, 0);
    }
    if (!loaded) {
        if (f_last[F_TIME] != 0xFFFD) {
            for (i = 0; i < F_VOL; ++i)
                f_last[i] = 0xFFFD;
            clear(VX, 108, 639, 151);
            clear(RX, 296, 639, 311);
        }
        return;
    }
    /* the tempo (MIDI: Melodius's BPM, a digit a byte: hundreds, tens,
       ones, tenths; and the time signature) */
    v = kind == E_MIDI ? ((midi_tempo[0] * 10 + midi_tempo[1]) * 10 + midi_tempo[2]) * 10 + midi_tempo[3]
                         + (midi_timesig_numerator << 13) : zsm_rate;
    if (v != f_last[F_TEMPO]) {
        f_last[F_TEMPO] = v;
        if (kind == E_MIDI) {
            p = s;
            if (midi_tempo[0])
                *p++ = '0' + midi_tempo[0];
            if (midi_tempo[0] || midi_tempo[1])
                *p++ = '0' + midi_tempo[1];
            *p++ = '0' + midi_tempo[2];
            *p++ = '.';
            *p++ = '0' + midi_tempo[3];
            strcpy(p, " BPM, ");
            p = ui_num(p + 6, midi_timesig_numerator);
            *p++ = '/';
            ui_num(p, midi_timesig_denominator);
        } else {
            p = ui_num(s, zsm_rate);
            strcpy(p, " Hz");
        }
        field(VX, f_y[F_TEMPO], VW, s, 0);
    }
    v = kind == E_MIDI ? midimeasure << 4 ^ midibeat : eng_loops;
    if (v != f_last[F_BAR]) {
        f_last[F_BAR] = v;
        if (kind == E_MIDI) {
            p = s;
            if (midimeasure >> 8)
                p = bcd(p, (unsigned char)(midimeasure >> 8), 1);
            p = bcd(p, (unsigned char)midimeasure, p == s);
            strcpy(p, ", beat ");
            bcd(p + 7, midibeat, 1);
        } else {
            p = ui_num(s, eng_loops + 1);
            strcpy(p, eng_loops ? " times" : " time");
            if (!eng_loops)
                strcpy(s, "the first time");
        }
        field(VX, f_y[F_BAR], VW, s, 0);
    }
    v = eng_frames / 60;
    if (v != f_last[F_TIME]) {
        f_last[F_TIME] = v;
        mmss(s, v);
        field(VX, f_y[F_TIME], VW, s, 1);
    }
    if (kind == E_MIDI && memcmp(lyr, lyrics, 32)) {
        memcpy(lyr, lyrics, 32);
        lyr[32] = 0;
        field(VX, 296, VW, (const char *)lyr, 0);
    }
}

/*---------------------------------------------------------------
  playing
 ---------------------------------------------------------------*/
/* everything that shows the song */
static void track(void)
{
    title();
    now_static();
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
        f_last[F_TIME] = 0xFFFF;
    } else if (play_next) {
        LOG("MP SONG END", 0);
        step(1, 0);
    } else {
        LOG("MP SONG END", 0);
        stop_cmd();
    }
}

static void volume_by(signed char d)
{
    signed char v = (signed char)volume + d;
    if (v < 0 || v > 10)
        return;
    set_volume((unsigned char)v);
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
    ui_message("MIDI Player 1.0: MIDI and ZSM on the YM2151 and PSG.",
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
    switch (t) {
    case T_PREV: step(-1, 1); break;
    case T_PLAY: pause_toggle(); break;
    case T_STOP: stop_cmd(); break;
    case T_NEXT: step(1, 1); break;
    case T_SOFT: volume_by(-1); break;
    case T_LOUD: volume_by(1); break;
    case T_AUTO: toggle_next(); break;
    case T_REP: toggle_repeat(); break;
    }
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
    if (y >= TOOL_Y && y < TOOL_Y + 16) {
        do_tool(tool_at(x));
        return;
    }
    if (y < LIST_Y || y >= LIST_Y + LIST_N * ROW_H)
        return;
    if (x >= 320 && x < 336) {
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
        pause_toggle();
    else if (k == KEY_RIGHT)
        step(1, 1);
    else if (k == KEY_LEFT && (keyDataMods & KEYM_ARROW))
        step(-1, 1);
    else if (k == KEY_ESC)
        stop_cmd();
    else if (k == '+' || k == '=')
        volume_by(1);
    else if (k == '-')
        volume_by(-1);
    else if (k == 'n' || k == 'N')
        toggle_next();
    else if (k == 'r' || k == 'R')
        toggle_repeat();
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
    if ((unsigned int)(eng_ticks - last_tick) < 3)
        return;
    last_tick = eng_ticks;
    asm("sei");
    w = (signed char)mouseWheel;
    mouseWheel = 0;
    asm("cli");
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
    voices_draw();
    progress();
    if (!menuNumber)
        fields();
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
    theme_palette();
    hilite = theme.hilite ? theme.hilite : SELECT;
    vr_win(&win, "MIDI Player");
    theme_menus();
    ui_menus(barnames, 2, (unsigned int **)lefts, (unsigned int **)rights, longest, &mbar.right, barx, barl);
    menu_marks();
    DoMenu((void *)&mbar, 0);
    toolbar();
    theme_rect(0, 42, HEAD_Y >> 3, 2, CHROME);
    theme_rect(43, 37, HEAD_Y >> 3, 2, CHROME);
    WVerticalLine(0xFF, 339, HEAD_Y, 463);
    labels();
    list_head();
    list_draw();
    track();
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
    labels();
    now_static();
}
#endif
