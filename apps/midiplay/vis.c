/*
 * vis.c -- MIDI Player (DECISIONS V206), overlay 4: what the music does,
 * drawn as it plays (called through far_call(), mp.h; now playing above
 * it is now.c's, overlay 6):
 *   - the YM2151's eight voices: each a colour of its own, its instrument
 *     (the General MIDI program's name, Drums) and its note, a meter of 24
 *     segments that jumps at a key-on by its loudness and falls back while
 *     the note is held and fast when it is released;
 *   - at the right, MIDI: the 16 MIDI channels, each with its program's
 *     name once it plays, its number lit at its notes; ZSM: the PSG's 16
 *     voices, their notes and meters (their volume);
 *   - a keyboard of 61 keys (C2-C7, 36 white keys of 2 cards, the black
 *     keys a card each): a key sounding takes its voice's colour (the
 *     colour map: a paper colour a card); a note outside the keys is shown
 *     an octave or more in. Drums are not keys.
 * One ink for the whole screen: in dark mode (ink light) the white keys are
 * ink and the black ones paper, so the keyboard looks the same way round;
 * a lit key is paper in its colour either way.
 * Everything is drawn again only where it changed (the keys, the meters'
 * segments, a note's name, a number); the bitmap above the voices is not
 * drawn while a menu is open (the menus hang there), the colours are.
 *
 * MIT licence (see LICENSE).
 */
#include "mp.h"
#include <theme.h>
#include "../sysui/sysui.h"

#pragma code-name ("OVERLAY4")
#pragma rodata-name ("OVL4RO")
#pragma data-name ("OVL4DATA")
#pragma bss-name ("OVL4BSS")
#include "notes.h"
                      /* (after the pragmas: its tables in the overlay) */

/*---------------------------------------------------------------
  the layout (pixels; cards for the colours)
 ---------------------------------------------------------------*/
#define VH_Y     232            /* the voices' heads: card rows 29-30 */
#define V_ROW    31             /* the voices: card rows 31-46, 16 pixels a voice */
#define V_Y      248
#define FM_M     23             /* an FM voice's meter: cards 23-46 */
#define FM_N     24
#define RC0      49             /* the right part: two columns of 15 cards */
#define PS_N     9              /* a PSG voice's meter: 9 segments */
#define KL_Y     376            /* the octaves' names: card rows 47-48 */
#define KB_ROW   49             /* the keyboard: card rows 49-56 */
#define KB_T     392
#define KB_B     455
#define KB_C0    4              /* its first card */
#define KB_LO    36             /* C2 .. C7 */
#define KB_N     61

static const unsigned char vcol[8] = { GREEN, SKY2, ORANGE, PURPLE, YELLOW, CYAN, RED, DUSK };

/*---------------------------------------------------------------
  helpers
 ---------------------------------------------------------------*/
static void clear(unsigned int l, unsigned int t, unsigned int r, unsigned int b)
{
    SetPattern(0);
    WRectangle(l, t, r, b);
}

/* s cut to w pixels ("..." at its end if cut) into t (64 bytes) */
static char *fitw(char *t, const char *s, unsigned int w, unsigned char bold)
{
    unsigned char i = 0;
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

/* a band of 16 lines at y from x, w pixels: cleared, s in it */
static void field(unsigned int x, unsigned int y, unsigned int w, const char *s, unsigned char bold)
{
    char t[64];
    clear(x, y, x + w - 1, y + 15);
    ui_text(x, y, fitw(t, s, w, bold), bold);
}

static const char names[] = "C C#D D#E F F#G G#A A#B ";

/* a MIDI note's name ("C#4"; 60 is C4) at p */
static char *note_name(char *p, unsigned char n)
{
    const char *q = names + 2 * (n % 12);
    *p++ = q[0];
    if (q[1] != ' ')
        *p++ = q[1];
    n = n / 12;
    if (!n)
        *p++ = '-';
    *p++ = '0' + (n ? n - 1 : 1);
    *p = 0;
    return p;
}

/*---------------------------------------------------------------
  the state shown
 ---------------------------------------------------------------*/
static unsigned char k_on[KB_N], want[KB_N];   /* each key's colour (0 none) */
static unsigned char lv[24];            /* a voice's level, eighths of a segment */
static unsigned char seg[24];           /* its segments shown */
static unsigned char vnote[24];         /* its note's name shown (0 none) */
static unsigned char vlast[8], vcc[8];  /* an FM voice's last note, its calls since */
static unsigned char vname[8];          /* its instrument shown ($FE none) */
static unsigned char cprog[16], cact[16], cshow[16];   /* MIDI channels */
static unsigned char view;              /* the right part: E_MIDI or E_ZSM */
static unsigned char nbudget;           /* names still to draw in this update */
static unsigned char unseen = 1;        /* (OVL4DATA, loaded with the record: the BSS is not cleared) */
static unsigned char last_song = 0xFF;  /* (song_no when vis_song last ran) */

/*---------------------------------------------------------------
  the keyboard
 ---------------------------------------------------------------*/
/* s (notes.h's letters, digits, sharp, minus) in the small letters at card
   c, nb cards across, the band of 16 lines from y (cleared), centred if
   mid: one raw WBitmapUp (the kernel's text takes some 7,000 cycles a
   character; this some 2,000 for the lot) */
static void small(unsigned char c, unsigned char nb, unsigned int y, const char *s, unsigned char mid)
{
    unsigned char b[3 * 16], x = 1, g, r, *q;
    const char *p;
    unsigned int w;
    memset(b, 0, sizeof b);
    if (mid) {
        for (w = 0, p = s; *p; ++p)
            w += note_w[strchr(NOTE_CHARS, *p) - NOTE_CHARS] + 1;
        x = (unsigned char)((nb * 8 - w + 2) >> 1);
    }
    for (p = s; *p; ++p) {
        g = (unsigned char)(strchr(NOTE_CHARS, *p) - NOTE_CHARS);
        if (x + note_w[g] > nb * 8)
            break;
        q = b + nb * 5 + (x >> 3);
        for (r = 0; r < 7; ++r, q += nb) {
            w = (unsigned int)note_rows[g][r] << (8 - (x & 7));
            q[0] |= (unsigned char)(w >> 8);
            if ((x >> 3) + 1 < nb)
                q[1] |= (unsigned char)w;
        }
        x += note_w[g] + 1;
    }
    WBitmapUp(b, c, nb, y, 16 | 0x8000);
}

static const unsigned char k_black[12] = { 0, 1, 0, 1, 0, 0, 1, 0, 1, 0, 1, 0 };
static const unsigned char k_col[12] = { 0, 1, 2, 4, 4, 6, 7, 8, 9, 10, 12, 12 };
static const unsigned char k_topl[12] = { 0, 0, 2, 0, 5, 6, 0, 8, 0, 10, 0, 13 };
static const unsigned char k_topw[12] = { 1, 0, 2, 0, 1, 1, 0, 1, 0, 2, 0, 1 };

static unsigned char kb_base(void) { return theme.dark ? CHROME : PAPER; }

/* key i (0 = C2) in colour col (0: not sounding) */
static void key_draw(unsigned char i, unsigned char col)
{
    unsigned char s = i % 12, ob = KB_C0 + 14 * (i / 12), c = ob + k_col[s], tl, tw;
    unsigned int x = (unsigned int)c << 3, tx;
    unsigned char pc = col ? col : kb_base();
    if (k_black[s]) {
        if (!theme.dark) {              /* (dark: a black key is paper anyway) */
            SetPattern(col ? 0 : 1);
            WRectangle(x + 1, KB_T + 2, x + 6, KB_T + 30);
        }
        theme_rect(c, 1, KB_ROW, 4, pc);
        return;
    }
    tl = k_topl[s];
    tw = k_topw[s];
    if (i == KB_N - 1) {                /* (the last C: nothing above it) */
        tl = 0;
        tw = 2;
    }
    if (theme.dark) {                   /* (a white key is ink: lit, paper) */
        tx = (unsigned int)(ob + tl) << 3;
        SetPattern(col ? 0 : 1);
        WRectangle(tx > x ? tx : x + 1, KB_T + 2, tx + 8 * tw - 1, KB_T + 31);
        WRectangle(x + 1, KB_T + 32, x + 15, KB_B - 1);
    }
    theme_rect(ob + tl, tw, KB_ROW, 4, pc);
    theme_rect(c, 2, KB_ROW + 4, 4, pc);
}

static void keyboard(void)
{
    unsigned char i, s, o, line = theme.dark ? 0 : 1;
    unsigned int x;
    clear(0, KL_Y, 638, KB_B + 8);     /* (not whole rows: the kernel fills whole rows in blocks with the
                                           interrupt off up to 5,400 cycles, V68; a narrower fill row by row) */
    for (o = 0; o < 6; ++o) {
        char t[4];
        t[0] = 'C';
        t[1] = '2' + o;
        t[2] = 0;
        small(KB_C0 + 14 * o, 2, KL_Y, t, 0);
    }
    SetPattern(!line);
    WRectangle(KB_C0 * 8, KB_T, KB_C0 * 8 + 576, KB_B);
    SetPattern(line);
    WRectangle(KB_C0 * 8, KB_T, KB_C0 * 8 + 576, KB_T + 1);
    WRectangle(KB_C0 * 8, KB_B, KB_C0 * 8 + 576, KB_B);
    for (x = KB_C0 * 8; x <= KB_C0 * 8 + 576; x += 16)
        WRectangle(x, KB_T, x, KB_B);
    for (o = 0; o < 5; ++o)
        for (s = 0; s < 12; ++s)
            if (k_black[s]) {
                x = (KB_C0 + 14 * o + k_col[s]) << 3;
                WRectangle(x, KB_T, x + 7, KB_T + 31);
            }
    theme_rect(0, 80, KB_ROW - 2, 2, PAPER);
    theme_rect(KB_C0, 73, KB_ROW, 8, kb_base());
    /* the cheeks */
    theme_rect(1, 2, KB_ROW, 8, CHROME);
    theme_rect(77, 2, KB_ROW, 8, CHROME);
    ui_rframe(8, KB_T, 23, KB_B);
    ui_rframe(616, KB_T, 631, KB_B);
    for (i = 0; i < KB_N; ++i)
        k_on[i] = 0;
}

static void key_want(unsigned char n, unsigned char col)
{
    while (n < KB_LO)
        n += 12;
    while (n >= KB_LO + KB_N)
        n -= 12;
    want[n - KB_LO] = col;
}

/*---------------------------------------------------------------
  the voices
 ---------------------------------------------------------------*/
/* a meter's frame: n segments from card c0 at card row r */
static void grid(unsigned char c0, unsigned char n, unsigned char r)
{
    unsigned char b[(FM_N + 1) * 8], i, j, h, *q;  /* (raw WBitmapUp, 8 rows at a time: a line at each card's */
    for (h = 0; h < 16; h += 8) {                   /* right, the top and the bottom; the card before: its last column) */
        q = b;
        for (j = h; j < h + 8; ++j)
            for (i = 0; i <= n; ++i)
                *q++ = i && (j == 0 || j == 15) ? 0xFF : 0x01;
        WBitmapUp(b, c0 - 1, n + 1, ((unsigned int)r << 3) + h, 8 | 0x8000);
    }
    theme_rect(c0, n, r, 2, CHROME);
}

/* a voice's place: its meter's first card and segments, its card row, its
   note's first card */
static unsigned char m_c0, m_n, m_row;
static unsigned char m_nc;

static void place(unsigned char v)
{
    if (v < 8) {
        m_c0 = FM_M;
        m_n = FM_N;
        m_row = V_ROW + 2 * v;
        m_nc = 18;
    } else {
        v -= 8;
        m_c0 = RC0 + 16 * (v >> 3) + 6;
        m_n = PS_N;
        m_row = V_ROW + 2 * (v & 7);
        m_nc = m_c0 - 4;
    }
}

/* a swatch: n (1-16) on w cards at card c, row r, in colour col */
static void swatch(unsigned char c, unsigned char w, unsigned char r, unsigned char n, unsigned char col)
{
    char t[4];
    ui_num(t, n);
    small(c, w, (unsigned int)r << 3, t, 1);
    theme_rect(c, w, r, 2, col);
}

static void level_show(unsigned char v)
{
    unsigned char n;
    place(v);
    n = (unsigned char)((lv[v] + 7) >> 3);
    if (n > m_n)
        n = m_n;
    if (n == seg[v])
        return;
    if (n > seg[v])
        theme_rect(m_c0 + seg[v], n - seg[v], m_row, 2, vcol[v & 7]);
    else
        theme_rect(m_c0 + n, seg[v] - n, m_row, 2, CHROME);
    seg[v] = n;
}

/* a voice's note's name (0: none) in its 3 cards */
static void note_show(unsigned char v, unsigned char n)
{
    char t[6];
    if (n == vnote[v])
        return;
    vnote[v] = n;
    place(v);
    t[0] = 0;
    if (n)
        note_name(t, n);
    small(m_nc, 3, (unsigned int)m_row << 3, t, 0);
}

/* ZSM: an FM voice's sides (its register $20's bits 6 and 7) */
static const char *const pans[4] = { "FM, silent", "FM, left", "FM, right", "FM, both sides" };

/* an FM voice's name: a General MIDI program (0-127), Drums ($FF), a ZSM's
   voice by its sides ($F8-$FB), none ($FE) */
static void fm_name(unsigned char v, unsigned char prog)
{
    if (prog == vname[v])
        return;
    vname[v] = prog;
    gm[0] = 0;
    if (prog >= 0xF8 && prog <= 0xFB)
        strcpy(gm, pans[prog & 3]);
    else if (prog != 0xFE) {
        gm_prog = prog;
        INFO(gm_name);
    }
    field(28, V_Y + 16 * v, 116, gm, 0);
}

static void chan_name(unsigned char ch, unsigned char prog)
{
    unsigned char c0 = RC0 + 16 * (ch >> 3);
    cprog[ch] = prog;
    gm_prog = prog;
    INFO(gm_name);
    field(((unsigned int)(c0 + 2) << 3) + 4, V_Y + 16 * (ch & 7), 13 * 8 - 6, gm, 0);
}

/* the right part: MIDI's channels or the PSG's voices */
static void right_part(void)
{
    unsigned char i, c0, p;
    clear(RC0 * 8 - 4, VH_Y, 639, V_Y + 127);
    theme_rect(RC0, 31, V_ROW, 16, PAPER);
    ui_text(RC0 * 8 + 4, VH_Y, view == E_ZSM ? "PSG: 16 voices" : "MIDI channels", 1);
    for (i = 0; i < 16; ++i) {
        c0 = RC0 + 16 * (i >> 3);
        swatch(c0, 2, V_ROW + 2 * (i & 7), i + 1, view == E_ZSM ? vcol[i & 7] : PAPER);
        if (view == E_ZSM) {
            place(i + 8);
            grid(m_c0, m_n, m_row);
        }
        seg[i + 8] = 0;
        lv[i + 8] = 0;
        vnote[i + 8] = 0;
        cact[i] = 0;
        cshow[i] = 0;
        p = cprog[i];                   /* (drawn again: the channels named before keep their names) */
        cprog[i] = 0xFE;
        if (view == E_MIDI && p != 0xFE)
            chan_name(i, p);
    }
}

/*---------------------------------------------------------------
  the panels drawn whole
 ---------------------------------------------------------------*/

void vis_frame(void)
{
    unsigned char v, p;
    if (unseen) {                       /* (the first time: nothing named yet) */
        unseen = 0;
        memset(vname, 0xFE, sizeof vname);
        memset(cprog, 0xFE, sizeof cprog);
    }
    /* the voices' heads */
    clear(0, VH_Y, 638, KB_B + 8);
    theme_rect(0, 80, VH_Y >> 3, 2, CHROME);
    WHorizontalLine(0xFF, 0, 639, VH_Y - 1);
    WVerticalLine(0xFF, RC0 * 8 - 12, VH_Y, V_Y + 127);
    ui_text(8, VH_Y, "YM2151: 8 FM voices", 1);
    for (v = 0; v < 8; ++v) {
        swatch(1, 2, V_ROW + 2 * v, v + 1, vcol[v]);
        place(v);
        grid(m_c0, m_n, m_row);
        seg[v] = lv[v] = vnote[v] = vlast[v] = vcc[v] = 0;
        p = vname[v];                   /* (drawn again: the names as they were) */
        vname[v] = 0xFE;
        fm_name(v, p);
    }
    view = 0;
    keyboard();
}

/* the song's lines: a song started or stopped */
void vis_song(void)
{
    unsigned char v, k = loaded ? kind : E_MIDI, fresh = song_no != last_song;
    unsigned int y;
    last_song = song_no;
    NOW(now_song);
    /* the voices: a song started or stopped (not the window drawn again)
       forgets the names */
    for (v = 0; v < 8; ++v) {
        vlast[v] = vcc[v] = 0;
        if (fresh)
            fm_name(v, 0xFE);
    }
    if (k != view) {
        if (fresh)
            memset(cprog, 0xFE, sizeof cprog);
        view = k;
        right_part();
    } else if (view == E_MIDI && fresh)
        for (v = 0; v < 16; ++v) {
            if (cprog[v] != 0xFE) {
                y = V_Y + 16 * (v & 7);
                clear(((unsigned int)(RC0 + 16 * (v >> 3) + 2) << 3) + 4, y, ((unsigned int)(RC0 + 16 * (v >> 3) + 15) << 3) - 1, y + 15);
            }
            cprog[v] = 0xFE;
            cact[v] = 0;
            if (cshow[v]) {
                cshow[v] = 0;
                theme_rect(RC0 + 16 * (v >> 3), 2, V_ROW + 2 * (v & 7), 2, PAPER);
            }
        }
}

/*---------------------------------------------------------------
  20 times a second
 ---------------------------------------------------------------*/
static const unsigned int psg_th[85] = {        /* (VERA's PSG: the word at which each note from 24 starts, half a semitone below it) */
    85, 90, 96, 101, 107, 114, 121, 128, 135, 143, 152, 161, 171, 181, 191, 203, 215, 228, 241, 256, 271, 287,
    304, 322, 341, 361, 383, 406, 430, 455, 482, 511, 542, 574, 608, 644, 682, 723, 766, 811, 860, 911, 965,
    1022, 1083, 1147, 1216, 1288, 1365, 1446, 1532, 1623, 1719, 1822, 1930, 2045, 2166, 2295, 2431, 2576,
    2729, 2891, 3063, 3246, 3439, 3643, 3860, 4089, 4332, 4590, 4863, 5152, 5458, 5783, 6127, 6491, 6877,
    7286, 7719, 8178, 8665, 9180, 9726, 10304, 10917 };

static unsigned char psg_note(unsigned int w)
{
    unsigned char lo = 0, hi = 85, m;
    while (lo < hi) {                   /* (the first threshold above w) */
        m = (lo + hi) >> 1;
        if (psg_th[m] <= w)
            lo = m + 1;
        else
            hi = m;
    }
    return lo ? 23 + lo : 24;
}

/* the YM2151's key code (octave, note: 0-14 without 3, 7, 11) as a MIDI note */
static unsigned char kc_note(unsigned char kc)
{
    unsigned char c = kc & 15;
    return 12 * (kc >> 4) + c - (c >> 2) + 13;
}

static void fm_level(unsigned char v, unsigned char on, unsigned char strike, unsigned char peak)
{
    if (strike)
        lv[v] = peak;
    else if (on) {
        if (lv[v] > 72)
            lv[v] -= 2;
    } else
        lv[v] = lv[v] > 14 ? lv[v] - 14 : 0;
    level_show(v);
}

static void voices(void)
{
    unsigned char v, n, on, strike, play = loaded && !paused;
    unsigned char zbuf[24], regs[64];   /* (on the C stack: below $A000, eng_zsm_ym maps another bank) */
    unsigned int w;
    memset(want, 0, KB_N);
    nbudget = 2;                        /* (the names: two an update, a song's start spread out) */
    if (play && kind == E_MIDI) {
        for (v = 0; v < 8; ++v) {
            n = ymnote[v];
            on = n != 0;
            strike = on && (n != vlast[v] || midi_ym_callcnt[v] < vcc[v]);
            vlast[v] = n;
            vcc[v] = midi_ym_callcnt[v];
            if (on && yminst[v] != 0xFF)
                key_want(n, vcol[v]);
            fm_level(v, on, strike, (unsigned char)(ymatten[v] > 48 ? 48 : 192 - 3 * ymatten[v]));
            if (on) {
                note_show(v, yminst[v] == 0xFF ? 0 : n);
                if (nbudget && yminst[v] != vname[v]) {
                    --nbudget;
                    fm_name(v, yminst[v]);
                }
            } else
                note_show(v, 0);
        }
        for (v = 0; v < 16; ++v) {
            if (midi_msg_sent[v]) {         /* (bit 7: it has played; bits 0-6: lit, updates) */
                midi_msg_sent[v] = 0;
                cact[v] = 0x83;
            }
            n = v == 9 ? 0xFF : midiinst[v];
            if ((cact[v] & 0x80) && n != cprog[v] && nbudget) {
                --nbudget;
                chan_name(v, n);
            }
            if (cact[v] & 0x7F)
                n = hilite;
            else if (cprog[v] != 0xFE || cact[v])
                n = CHROME;
            else
                n = PAPER;
            if (n != cshow[v]) {
                cshow[v] = n;
                theme_rect(RC0 + 16 * (v >> 3), 2, V_ROW + 2 * (v & 7), 2, n);
            }
            if (cact[v] & 0x7F)
                --cact[v];
        }
    } else if (play && kind == E_ZSM) {
        eng_zsm_ym(zbuf);
        for (v = 0; v < 8; ++v) {
            on = (zbuf[v] & 0x78) != 0;
            n = kc_note(zbuf[16 + v]);
            strike = on && (!vlast[v] || n != vlast[v]);
            vlast[v] = on ? n : 0;
            if (on)
                key_want(n, vcol[v]);
            fm_level(v, on, strike, 176);
            note_show(v, on ? n : 0);
            if (on && names && (0xF8 | zbuf[8 + v] >> 6) != vname[v]) {
                --nbudget;
                fm_name(v, 0xF8 | zbuf[8 + v] >> 6);
            }
        }
        eng_psg(regs);                  /* (the PSG's registers: VERA's $1F9C0, 4 bytes a voice) */
        for (v = 8; v < 24; ++v) {
            w = regs[4 * (v - 8)] | regs[4 * (v - 8) + 1] << 8;
            on = regs[4 * (v - 8) + 2] & 0x3F;
            n = 0;
            if (on && w) {
                n = psg_note(w);
                key_want(n, vcol[v & 7]);
            }
            on = (unsigned char)((on * 9 + 6) >> 3);    /* (0-63: eighths of 9 segments) */
            if (on >= lv[v] || lv[v] <= 8)     /* (not as ?: : cc65's optimizer loaded */
                lv[v] = on;                     /* the wrong local for that one) */
            else
                lv[v] -= 8;
            level_show(v);
            note_show(v, n);
        }
    } else {
        for (v = 0; v < 8; ++v) {
            vlast[v] = 0;
            fm_level(v, 0, 0, 0);
            note_show(v, 0);
        }
        for (v = 8; v < 24; ++v) {
            if (view == E_ZSM) {
                lv[v] = lv[v] > 8 ? lv[v] - 8 : 0;
                level_show(v);
                note_show(v, 0);
            }
        }
        if (view == E_MIDI)
            for (v = 0; v < 16; ++v) {
                n = cprog[v] != 0xFE ? CHROME : PAPER;
                if (n != cshow[v]) {
                    cshow[v] = n;
                    theme_rect(RC0 + 16 * (v >> 3), 2, V_ROW + 2 * (v & 7), 2, n);
                }
                cact[v] = 0;
            }
    }
    for (v = 0; v < KB_N; ++v)
        if (want[v] != k_on[v]) {
            k_on[v] = want[v];
            key_draw(v, want[v]);
        }
}

void vis_tick(void)
{
    voices();
    NOW(now_tick);
}
