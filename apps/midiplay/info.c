/*
 * info.c -- MIDI Player (DECISIONS V206), overlay 5: a song read through
 * once when it starts, for what the engines do not say (info, mp.h):
 *   MIDI: the first track's name (meta event 3) as its title, the
 *         copyright (meta 2) or else the first text (meta 1) at its start,
 *         and its length: every track walked to its end, the tempo changes
 *         collected (48 at most: later ones are left out of the sum), the
 *         last track's end through them in milliseconds;
 *   ZSM:  the length once round (its delays to the end mark, at its tick
 *         rate).
 * The song is in RAM banks from song_bank; it is read through eng_peek
 * (main RAM) 64 bytes at a time into buf (below $A000). A song longer
 * than SCAN_MAX bytes is not walked for its length (the time it takes:
 * the music plays meanwhile, the window waits).
 * And the General MIDI programs' names (gm_name), short enough for the
 * voices' column.
 *
 * MIT licence (see LICENSE).
 */
#include "mp.h"

#pragma code-name ("OVERLAY5")
#pragma rodata-name ("OVL5RO")
#pragma data-name ("OVL5DATA")
#pragma bss-name ("OVL5BSS")

#define SCAN_MAX 98304UL
#define NTEMPO   48

/*---------------------------------------------------------------
  the reader
 ---------------------------------------------------------------*/
static unsigned long off, lim;          /* the next byte's place; the end */
static unsigned char bp, bl;            /* buf's next, its length */
extern unsigned char info_buf[64];      /* (main.c: below $A000) */
#define buf info_buf

static void seek(unsigned long o)
{
    off = o;
    bp = bl = 0;
}

static unsigned char get(void)
{
    unsigned int in;
    unsigned char n;
    if (bp == bl) {
        if (off >= lim)
            return 0;
        in = (unsigned int)off & 8191;
        n = sizeof info_buf;
        if (8192 - in < n)
            n = (unsigned char)(8192 - in);
        if (lim - off < n)
            n = (unsigned char)(lim - off);
        peek_bank = (unsigned char)(song_bank + (unsigned char)(off >> 13));
        peek_src = 0xA000 + in;
        peek_n = n;
        eng_peek(buf);
        off += n;
        bp = 0;
        bl = n;
    }
    return buf[bp++];
}

/* the place of the next byte */
static unsigned long here(void) { return off - bl + bp; }

static void skip(unsigned long n)
{
    if (n <= (unsigned char)(bl - bp))
        bp += (unsigned char)n;
    else
        seek(here() + n);
}

static unsigned long vlq(void)
{
    unsigned long v = 0;
    unsigned char b, i;
    for (i = 0; i < 4; ++i) {
        b = get();
        v = (v << 7) | (b & 0x7F);
        if (!(b & 0x80))
            break;
    }
    return v;
}

static unsigned long be32(void)
{
    unsigned long v = (unsigned long)get() << 24;
    v |= (unsigned long)get() << 16;
    v |= (unsigned int)get() << 8;
    return v | get();
}

/* n bytes of text into d (max bytes with its 0), the rest skipped;
   characters outside the printable ASCII as spaces */
static void text(char *d, unsigned long n, unsigned char max)
{
    unsigned char i = 0, c;
    while (n) {
        c = get();
        --n;
        if (i < max - 1)
            d[i++] = c >= 32 && c < 127 ? c : ' ';
    }
    while (i && d[i - 1] == ' ')
        --i;
    d[i] = 0;
}

/*---------------------------------------------------------------
  MIDI
 ---------------------------------------------------------------*/
static unsigned long t_tick[NTEMPO];
static unsigned long t_us[NTEMPO];
static unsigned char nt;

static void tempo_add(unsigned long tick, unsigned long us)
{
    unsigned char i;
    if (nt == NTEMPO)
        return;
    for (i = nt; i && t_tick[i - 1] > tick; --i) {
        t_tick[i] = t_tick[i - 1];
        t_us[i] = t_us[i - 1];
    }
    t_tick[i] = tick;
    t_us[i] = us;
    ++nt;
}

/* ticks at us microseconds a quarter note, div ticks a quarter: in ms */
static unsigned long ms(unsigned long ticks, unsigned long us, unsigned int div)
{
    unsigned long r = 0, part;
    us = (us + 500) / 1000;             /* (ms a quarter note: at most 16777) */
    while (ticks) {
        part = ticks > 200000UL ? 200000UL : ticks;
        r += part * us / div;
        ticks -= part;
    }
    return r;
}

static void midi(void)
{
    unsigned int div, ntrk, t;
    unsigned long len, end, tick, last = 0, n, total;
    unsigned char st = 0, b, type, walk;
    seek(8);
    get();                              /* (the format) */
    get();
    ntrk = get() << 8;
    ntrk |= get();
    div = get() << 8;
    div |= get();
    walk = song_size <= SCAN_MAX && !(div & 0x8000) && div;
    nt = 0;
    seek(14);
    for (t = 0; t < ntrk && t < 32; ++t) {
        if (get() != 'M' || get() != 'T' || get() != 'r' || get() != 'k')
            return;
        len = be32();
        end = here() + len;
        if (end > lim)
            end = lim;
        tick = 0;
        st = 0;
        while (here() < end) {
            n = vlq();
            tick += n;
            if (!walk && (t || n))
                break;                  /* (not walked: the first track's start only) */
            b = get();
            if (b == 0xFF) {
                type = get();
                len = vlq();
                if (type == 0x51 && len == 3) {
                    n = (unsigned long)get() << 16;
                    n |= (unsigned int)get() << 8;
                    n |= get();
                    tempo_add(tick, n);
                } else if (type == 3 && !t && !info.title[0])
                    text(info.title, len, sizeof info.title);
                else if (type == 2 && !info.text[0])
                    text(info.text, len, sizeof info.text);
                else if (type == 1 && !tick && !info.text[0])
                    text(info.text, len, sizeof info.text);
                else
                    skip(len);
                if (type == 0x2F)
                    break;
            } else if (b == 0xF0 || b == 0xF7)
                skip(vlq());
            else {
                if (b & 0x80) {
                    st = b;
                    get();
                }
                if ((st & 0xE0) != 0xC0)
                    get();
            }
        }
        if (tick > last)
            last = tick;
        seek(end);
    }
    if (!walk)
        return;
    /* the length: the last end through the tempo map */
    total = 0;
    tick = 0;
    n = 500000;
    for (b = 0; b < nt && t_tick[b] < last; ++b) {
        total += ms(t_tick[b] - tick, n, div);
        tick = t_tick[b];
        n = t_us[b];
    }
    total += ms(last - tick, n, div);
    info.secs = (unsigned int)((total + 500) / 1000);
    info.known = 1;
}

/*---------------------------------------------------------------
  ZSM: its commands (0x00-0x3F a PSG register and its value; 0x40 an
  extension, its next byte's low 6 bits the bytes after; 0x41-0x7F that
  many YM2151 register pairs; 0x80 the end; 0x81-0xFF a delay)
 ---------------------------------------------------------------*/
static void zsm(void)
{
    unsigned long ticks = 0;
    unsigned int rate;
    unsigned char c;
    seek(12);
    rate = get();
    rate |= get() << 8;
    if (!rate)
        rate = 60;
    seek(16);
    while (here() < lim) {
        c = get();
        if (c < 0x40)
            get();
        else if (c == 0x40)
            skip(get() & 0x3F);
        else if (c < 0x80)
            skip(2 * (c & 0x3F));
        else if (c == 0x80)
            break;
        else
            ticks += c & 0x7F;
    }
    info.secs = (unsigned int)((ticks + rate / 2) / rate);
    info.known = 1;
}

void info_scan(void)
{
    memset(&info, 0, sizeof info);
    if (!loaded)
        return;
    lim = song_size;
    if (kind == E_MIDI)
        midi();
    else
        zsm();
}

/*---------------------------------------------------------------
  the General MIDI programs' names (1-128 as 0-127), short
 ---------------------------------------------------------------*/
static const char gm_names[] =
    "Grand Piano\0Bright Piano\0Electric Grand\0Honky-tonk\0Electric Piano 1\0Electric Piano 2\0"
    "Harpsichord\0Clavinet\0Celesta\0Glockenspiel\0Music Box\0Vibraphone\0Marimba\0Xylophone\0"
    "Tubular Bells\0Dulcimer\0Drawbar Organ\0Percussive Organ\0Rock Organ\0Church Organ\0"
    "Reed Organ\0Accordion\0Harmonica\0Tango Accordion\0Nylon Guitar\0Steel Guitar\0Jazz Guitar\0"
    "Clean Guitar\0Muted Guitar\0Overdrive Guitar\0Distortion Guitar\0Guitar Harmonics\0"
    "Acoustic Bass\0Finger Bass\0Pick Bass\0Fretless Bass\0Slap Bass 1\0Slap Bass 2\0Synth Bass 1\0"
    "Synth Bass 2\0Violin\0Viola\0Cello\0Contrabass\0Tremolo Strings\0Pizzicato Strings\0"
    "Orchestral Harp\0Timpani\0Strings\0Slow Strings\0Synth Strings 1\0Synth Strings 2\0Choir Aahs\0"
    "Voice Oohs\0Synth Voice\0Orchestra Hit\0Trumpet\0Trombone\0Tuba\0Muted Trumpet\0French Horn\0"
    "Brass Section\0Synth Brass 1\0Synth Brass 2\0Soprano Sax\0Alto Sax\0Tenor Sax\0Baritone Sax\0"
    "Oboe\0English Horn\0Bassoon\0Clarinet\0Piccolo\0Flute\0Recorder\0Pan Flute\0Blown Bottle\0"
    "Shakuhachi\0Whistle\0Ocarina\0Square Lead\0Saw Lead\0Calliope Lead\0Chiff Lead\0Charang\0"
    "Voice Lead\0Fifths Lead\0Bass and Lead\0New Age Pad\0Warm Pad\0Polysynth Pad\0Choir Pad\0"
    "Bowed Pad\0Metallic Pad\0Halo Pad\0Sweep Pad\0Rain\0Soundtrack\0Crystal\0Atmosphere\0"
    "Brightness\0Goblins\0Echoes\0Sci-fi\0Sitar\0Banjo\0Shamisen\0Koto\0Kalimba\0Bagpipe\0Fiddle\0"
    "Shanai\0Tinkle Bell\0Agogo\0Steel Drums\0Woodblock\0Taiko Drum\0Melodic Tom\0Synth Drum\0"
    "Reverse Cymbal\0Guitar Fret Noise\0Breath Noise\0Seashore\0Bird Tweet\0Telephone\0"
    "Helicopter\0Applause\0Gunshot";

void gm_name(void)
{
    const char *p = gm_names;
    unsigned char i;
    if (gm_prog == 0xFF) {
        strcpy(gm, "Drums");
        return;
    }
    for (i = gm_prog & 127; i; --i)
        p += strlen(p) + 1;
    strcpy(gm, p);
}
