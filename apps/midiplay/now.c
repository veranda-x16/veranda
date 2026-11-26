/*
 * now.c -- MIDI Player (DECISIONS V206), overlay 6: now playing (vis.c
 * calls it through far_call): the song's title (its first track's name,
 * else the file's), its text (copyright), its form and size; a display
 * (the Calculator's sunk look, its big digits) with the time and the
 * length, the bar and a light a beat (the beat now lit, the bar's first
 * beat orange), the tempo and the time signature (ZSM: the times round,
 * the tick rate); the progress bar (by the time when the length is known,
 * else by the bytes played); the lyrics, the newest syllable bold on the
 * highlight. Drawn again only where a value changed; the bitmap not while
 * a menu is open (the menus hang over it), the progress bar's colours
 * always.
 *
 * MIT licence (see LICENSE).
 */
#include "mp.h"
#include <theme.h>
#include "../sysui/sysui.h"

#pragma code-name ("OVERLAY6")
#pragma rodata-name ("OVL6RO")
#pragma data-name ("OVL6DATA")
#pragma bss-name ("OVL6BSS")
#include "digits.h"
                     /* (after the pragmas: its tables in the overlay) */

/* (V208) one layout whatever the song has: the title, the second line and
   the form always at their rows (a line the song has not stays blank);
   the display's frame clear of the text, its small lines clear of the big
   digits, the progress bar well apart from the display */
#define RX       288            /* now playing: card 36 to the window's right */
#define RR       631
#define TOP_Y    72             /* the song's lines: 14 lines each */
#define SONG_H   14
#define LCD_T    120            /* the display: card rows 15-21 */
#define LCD_B    175
#define COL_A    38             /* its columns (cards): the time */
#define COL_B    52             /* the bar, the beats' lights (card row 20) */
#define COL_C    70             /* the tempo */
#define LABEL_Y  123
#define BIG_Y    137
#define SMALL_Y  158
#define DOT_ROW  20
#define PROG_COL 36             /* the progress bar: card row 24 */
#define PROG_W   43
#define PROG_ROW 24
#define LYR_Y    208            /* the lyrics: card rows 26-27 */
#define LYR_X    344

static unsigned int c_time, c_bar, c_tempo, c_loop;
static unsigned char c_beat, c_beats, c_sig;
static unsigned char prog_n;
static char lyr[33];
static unsigned char lyr_k = 32;        /* (the newest part's length) */
static unsigned char hl_l, hl_n;        /* the lyrics' highlight: cards */

static void clear(unsigned int l, unsigned int t, unsigned int r, unsigned int b)
{
    SetPattern(0);
    WRectangle(l, t, r, b);
}

/* s cut to w pixels ("..." at its end if cut) into t (64 bytes) */
static char *fitw(char *t, const char *s, unsigned int w, unsigned char bold)
{
    unsigned char i;
    strncpy(t, s, 60);
    t[60] = 0;
    if (ui_width(t, bold) <= w)
        return t;
    i = (unsigned char)strlen(t);
    while (i && ui_width(t, bold) + 3 * (GetCharWidth('.') + bold) > w)
        t[--i] = 0;
    strcpy(t + i, "...");
    return t;
}

/* a band of h lines at y from x, w pixels: cleared, s in it */
static void band(unsigned int x, unsigned int y, unsigned int w, unsigned char h, const char *s, unsigned char bold)
{
    char t[64];
    clear(x, y, x + w - 1, y + h - 1);
    ui_text(x, y, fitw(t, s, w, bold), bold);
}

#define field(x, y, w, s, bold) band(x, y, w, 16, s, bold)
/* the song's line n (0 the title, 1 the second, 2 the form) */
#define line(n, s, bold) band(RX, TOP_Y + (n) * SONG_H, RR - RX, SONG_H, s, bold)

static char *mmss(char *p, unsigned int s)
{
    p = ui_num(p, s / 60);
    *p++ = ':';
    return ui_dd(p, (unsigned char)(s % 60));
}

/* the display's big digits: s (digits and colons) at card cx, nb bytes
   across (the rest of them cleared), one raw WBitmapUp */
static void big(unsigned char cx, unsigned char nb, const char *s)
{
    unsigned char b[8 * BIG_H];
    unsigned char g, r, sh, hi, lo, c, *q;
    unsigned int x = 0;
    memset(b, 0, sizeof b);
    for (; *s; ++s) {
        g = *s == ':' ? BIG_COLON : (unsigned char)(*s - '0');
        if (g > BIG_COLON || x + big_w[g] > (unsigned int)nb * 8)
            continue;
        sh = x & 7;
        c = (unsigned char)(x >> 3);
        q = b + c;
        for (r = 0; r < BIG_H; ++r, q += nb) {  /* (a row's 16 bits shifted into 3 bytes, 8 bits at a time) */
            hi = (unsigned char)(big_rows[g][r] >> 8);
            lo = (unsigned char)big_rows[g][r];
            q[0] |= hi >> sh;
            if (c + 1 < nb)
                q[1] |= (unsigned char)(hi << (8 - sh)) | (lo >> sh);
            if (c + 2 < nb && sh)
                q[2] |= (unsigned char)(lo << (8 - sh));
        }
        x += big_w[g];
    }
    WBitmapUp(b, cx, nb, BIG_Y, BIG_H | 0x8000);
}

static void lcd(void)
{
    unsigned int l = RX, r = RR, t = LCD_T, b = LCD_B;
    clear(l, t, r, b);
    theme_rect(l >> 3, (r - l + 1) >> 3, t >> 3, 7, SIDEBAR);
    ui_rframe(l, t, r, b);
    WHorizontalLine(0xAA, l + 2, r - 2, t + 1);    /* (a dotted line: the shade) */
    WVerticalLine(0xAA, l + 1, t + 2, b - 2);
}

static void progress(void)
{
    unsigned char n = 0;
    unsigned long a, t;
    if (loaded) {
        if (info.known && info.secs) {
            a = eng_frames;
            t = info.secs * 60UL;
        } else if (kind == E_MIDI) {
            a = eng_midi_pos();
            t = song_size - 14 - 8 * (unsigned long)midi_ntracks;
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
        theme_rect(PROG_COL + prog_n, n - prog_n, PROG_ROW, 1, hilite);
    else if (n < prog_n)
        theme_rect(PROG_COL + n, prog_n - n, PROG_ROW, 1, CHROME);
    prog_n = n;
}

static unsigned int bcd16(unsigned int v)
{
    return (v >> 12) * 1000 + ((v >> 8) & 15) * 100 + ((v >> 4) & 15) * 10 + (v & 15);
}

/* the beats' lights: n of them (8 at most) on the display's last card row */
static void beats(unsigned char n)
{
    unsigned char i;
    unsigned int x;
    clear(COL_B * 8, DOT_ROW * 8, COL_B * 8 + 127, DOT_ROW * 8 + 7);
    theme_rect(COL_B, 16, DOT_ROW, 1, SIDEBAR);
    for (i = 0; i < n; ++i) {
        x = (COL_B + 2 * i) << 3;
        WFrameRectangle(0xFF, x + 1, DOT_ROW * 8 + 1, x + 6, DOT_ROW * 8 + 6);
    }
    c_beats = n;
    c_beat = 0xFF;
}

static void display(void)
{
    char s[24], *p;
    unsigned int v;
    unsigned char b, n;
    v = loaded ? eng_frames / 60 : 0;
    if (v != c_time) {
        c_time = v;
        mmss(s, v);
        big(COL_A, 7, s);
    }
    if (!loaded) {
        if (c_bar != 0xFFFE) {
            c_bar = c_tempo = c_loop = 0xFFFE;
            big(COL_B, 6, "");
            big(COL_C, 5, "");
            clear(COL_C * 8, SMALL_Y, RR - 4, SMALL_Y + 13);
            if (c_beats)
                beats(0);
        }
        return;
    }
    if (kind == E_MIDI) {
        v = bcd16(midimeasure);
        if (v != c_bar) {
            c_bar = v;
            ui_num(s, v);
            big(COL_B, 6, s);
        }
        n = midi_timesig_numerator > 8 ? 8 : midi_timesig_numerator;
        if (n != c_beats)
            beats(n);
        b = (midibeat >> 4) * 10 + (midibeat & 15);
        if (b != c_beat) {
            if (c_beat && c_beat <= c_beats)
                theme_rect(COL_B + 2 * (c_beat - 1), 1, DOT_ROW, 1, SIDEBAR);
            c_beat = b;
            if (b && b <= c_beats)
                theme_rect(COL_B + 2 * (b - 1), 1, DOT_ROW, 1, b == 1 ? ORANGE : YELLOW);
        }
        v = ((midi_tempo[0] * 10 + midi_tempo[1]) * 10 + midi_tempo[2]);
        b = midi_timesig_numerator ^ (midi_timesig_denominator << 4);
        if (v != c_tempo || b != c_sig) {
            c_tempo = v;
            c_sig = b;
            ui_num(s, v);
            big(COL_C, 5, s);
            strcpy(s, "BPM, ");
            p = ui_num(s + 5, midi_timesig_numerator);
            *p++ = '/';
            ui_num(p, midi_timesig_denominator);
            band(COL_C * 8, SMALL_Y, RR - 4 - COL_C * 8, 14, s, 0);
        }
    } else {
        if (eng_loops + 1 != c_loop) {
            c_loop = eng_loops + 1;
            ui_num(s, c_loop);
            big(COL_B, 6, s);
        }
        if (c_tempo == 0xFFFF) {
            unsigned char h[16];
            song_peek(h, 16);
            c_tempo = h[12] | (unsigned int)h[13] << 8;
            ui_num(s, c_tempo);
            big(COL_C, 5, s);
            band(COL_C * 8, SMALL_Y, RR - 4 - COL_C * 8, 14, "Hz", 0);
        }
    }
}

/* the lyrics (Melodius's last 32 characters of text, the newest at the
   right): the newest part bold on the highlight */
static void lyrics_show(void)
{
    char t[34], *s;
    unsigned char k, i, a;
    unsigned int x, w;
    if (!loaded || kind != E_MIDI || !memcmp(lyr, lyrics, 32))
        return;
    /* the newest part: what was shifted in */
    for (k = 1; k < 32; ++k)
        if (!memcmp(lyr + k, lyrics, 32 - k))
            break;
    if (lyr[0] == 0x7F)                 /* (drawn again: the newest part as it was) */
        k = lyr_k;
    lyr_k = k;
    memcpy(lyr, lyrics, 32);
    lyr[32] = 0;
    for (i = 0; i < 32; ++i)
        t[i] = lyr[i] == '/' || lyr[i] == '\\' || lyr[i] < 32 ? ' ' : lyr[i];
    t[32] = 0;
    for (a = 0; a < 32 && t[a] == ' '; ++a)
        ;
    s = t + a;
    clear(LYR_X, LYR_Y, RR, LYR_Y + 15);
    if (hl_n)
        theme_rect(hl_l, hl_n, LYR_Y >> 3, 2, PAPER);
    hl_n = 0;
    if (!*s)
        return;
    ui_text(RX, LYR_Y, "Lyrics", 0);       /* (the label once there are words) */
    i = 32 - k;                         /* (the newest part starts at t + i) */
    if (i < a)
        i = a;
    t[i] = 0;
    x = LYR_X + ui_text(LYR_X, LYR_Y, s, 0);
    t[i] = lyr[i] == '/' || lyr[i] == '\\' || lyr[i] < 32 ? ' ' : lyr[i];
    w = ui_text(x, LYR_Y, t + i, 1);
    if (w) {
        hl_l = (unsigned char)((x - 2) >> 3);
        hl_n = (unsigned char)(((x + w + 1) >> 3) - hl_l + 1);
        if (hl_l + hl_n > (RR >> 3) + 1)
            hl_n = (RR >> 3) + 1 - hl_l;
        theme_rect(hl_l, hl_n, LYR_Y >> 3, 2, hilite);
    }
}

/* the song's lines, the display's labels, the bars cleared: a song
   started or stopped. (V208) The whole of now playing cleared first, in
   bands of 16 lines (not whole rows: V68), the colours back to the paper:
   nothing of the song before stays, whichever lines it had */
void now_song(void)
{
    char s[64], *p;
    unsigned char k = loaded ? kind : E_MIDI;
    unsigned int y;
    for (y = TOP_Y; y < LCD_T; y += 16)         /* (the lines: 72-119) */
        clear(RX, y, RR, y + 15);
    for (y = LCD_B + 1; y < LYR_Y + 16; y += 16)        /* (below the display: 176-223) */
        clear(RX, y, RR, y + 15);
    theme_rect(RX >> 3, (RR - RX + 1) >> 3, TOP_Y >> 3, (LCD_T - TOP_Y) >> 3, PAPER);
    theme_rect(RX >> 3, (RR - RX + 1) >> 3, (LCD_B + 1) >> 3, (LYR_Y - LCD_B - 1) >> 3, PAPER);
    /* the title, the text, the form: always these three rows */
    if (!loaded) {
        line(0, "Nothing is playing", 1);
        line(1, "Double-click a song in the playlist, or press Return.", 0);
    } else {
        line(0, info.title[0] ? info.title : playing_name, 1);
        if (info.title[0]) {
            strcpy(s, playing_name);
            if (info.text[0]) {
                strcat(s, ": ");
                strncat(s, info.text, 60 - strlen(s));
            }
            line(1, s, 0);
        } else
            line(1, info.text, 0);
        if (kind == E_MIDI) {
            strcpy(s, "MIDI file, type ");
            p = ui_num(s + 16, midi_format);
            strcpy(p, ", ");
            p = ui_num(p + 2, midi_ntracks);
            strcpy(p, midi_ntracks == 1 ? " track, " : " tracks, ");
        } else {
            unsigned char h[16];
            song_peek(h, 16);
            strcpy(s, "ZSM file, ");
            p = ui_num(s + 10, h[12] | (unsigned int)h[13] << 8);
            strcpy(p, (h[3] | h[4] | h[5]) ? " Hz, loops, " : " Hz, plays once, ");
        }
        ui_size(s + strlen(s), song_size);
        line(2, s, 0);
    }
    /* the display */
    lcd();
    ui_text(COL_A * 8, LABEL_Y, "Time", 0);
    ui_text(COL_B * 8, LABEL_Y, k == E_MIDI ? "Bar" : "Round", 0);
    ui_text(COL_C * 8, LABEL_Y, k == E_MIDI ? "Tempo" : "Rate", 0);
    if (loaded && info.known) {
        strcpy(s, "of ");
        mmss(s + 3, info.secs);
        ui_text(COL_A * 8, SMALL_Y, s, 0);
    }
    c_time = c_bar = c_tempo = c_loop = 0xFFFF;
    c_beat = 0xFF;
    c_beats = 0;
    c_sig = 0;
    /* the progress bar */
    theme_rect(PROG_COL, PROG_W, PROG_ROW, 1, CHROME);
    WFrameRectangle(0xFF, PROG_COL * 8 - 1, PROG_ROW * 8 - 1, (PROG_COL + PROG_W) * 8, PROG_ROW * 8 + 8);
    prog_n = 0;
    /* the lyrics (their band cleared above) */
    theme_rect(RX >> 3, (RR - RX + 1) >> 3, LYR_Y >> 3, 2, PAPER);
    lyr[0] = 0x7F;
    lyr[1] = 0;
    hl_n = 0;
}

void now_tick(void)
{
    progress();
    if (!menuNumber) {
        display();
        lyrics_show();
    }
}

/* where vis_x is on the progress bar: the time there, into sb */
unsigned int vis_x;

void now_where(void)
{
    unsigned long a = vis_x < PROG_COL * 8 ? 0 : vis_x - PROG_COL * 8;
    char *p;
    if (a > PROG_W * 8)
        a = PROG_W * 8;
    if (!loaded) {
        strcpy(sb, "Nothing is playing");
        return;
    }
    if (info.known && info.secs) {
        p = mmss(sb, (unsigned int)(a * info.secs / (PROG_W * 8)));
        strcpy(p, " of ");
        p = mmss(p + 4, info.secs);
        strcpy(p, " there; ");
    } else {
        p = ui_num(sb, a * 100 / (PROG_W * 8));
        strcpy(p, " % of the song there; ");
    }
    p = mmss(sb + strlen(sb), eng_frames / 60);
    strcpy(p, " played (a song plays from its start)");
}
