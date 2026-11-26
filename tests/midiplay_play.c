/* gate midiplay (DECISIONS V205, V206): MIDI Player's test build (apps/midiplay,
   make test: MP_TEST). MP.TST in the top folder names the session:
     host   the folder MUSIC listed (LIST.RAW); BAD.MID refused; FMT0.MID
            (format 0) played to its end, Play next on: FMT1.MID follows
            (format 1: three tracks, a tempo change, drums on channel 10,
            running status, a long note, pitch bend) (MIDI.RAW), paused
            for a second (the voices silent, the time held) and resumed;
            at its end SONG.ZSM (ZSM.RAW): it ends, and Play next stops
            after the last song; the volume down and up; Repeat: FMT0.MID
            twice; More/LOOP.ZSM (a loop): once round, faded out, stopped
            (the folder's last song); More/DEMO.MID (V206: frame 50 and
            two window updates on, DEMO.RAW: the keys, the meters, the
            lyrics; then in dark mode, DARK.RAW); Play next: DESERT.MID
            (V208: no title, no text, no lyrics; NEXTDK.RAW, the now-playing
            panel after DEMO.MID's), light again, DEMO.MID and by Play next
            DESERT.MID (NEXT.RAW); stopped; FMT1.MID again and
            Alt+Tab (TaskCtl TASK_ASIDE: the test desktop tests/term_desk.s
            brings it back after 3 s): the music paused aside and going on
            after; a redraw stress while it plays (the window's body drawn
            40 times); quit (the tick's cycles logged)
     wav    real time, for the emulator's recording (-wav ...,wait: the
            recording starts with the song, $9FB6): FMT1.MID 1.25 s, paused
            2 s, resumed 2 s, stopped 1.5 s; SONG.ZSM to its end; quit
     doc    started with /MUSIC/FMT0.MID as its document by the test
            desktop tests/midiplay_desk.c (as the shell opens one): it
            plays, its folder the playlist; quit
     dock   started as the dock starts it (the test desktop: no document,
            /VERANDA/APPS current and in curDirName): the folder it shows,
            then ".." twice (/VERANDA, the card's top "/", no ".." there)
            and once more (still "/"); quit
     soak   (by hand) MUSIC's first song, 20 s at most, then quit: the
            tick's cycles with a real song
   Every engine event is logged ("MP EV kind channel note frame", the frame
   in 4 hexadecimal digits: 1 a note,
   2 a drum, 3 a release (MIDI, the engine's ROM calls); 4 a key-on
   shadow's change, 5 PSG voice 0's volume (ZSM)), and the steps. The
   session ends with "MP END" and dump.bin (the screen).
   MIT licence (see LICENSE). */
#include <veranda.h>
#include <string.h>
#include "../apps/midiplay/mp.h"

extern char t_session[];
void __fastcall__ t_read(const char *name);
void __fastcall__ snap(const char *name);
void __fastcall__ t_end(const char *pfx);

extern unsigned long t_cyc_max, t_cyc_sum, t_ticks, t_gap_max;
extern unsigned char t_log[], t_log_head;
void t_pause_toggle(void);
void t_stop(void);
void t_step(signed char d);
void t_volume(signed char d);
void t_toggle_next(void);
void t_toggle_repeat(void);
void t_enter(const char *name);
void t_quit(void);
void t_select(unsigned char e);
void t_scroll(int t);
void t_redraw(void);
void t_dark(unsigned char on);

static unsigned char step, tail, wav, redraws, recording;
static unsigned long mark;              /* (the window's updates counted at a step) */
static unsigned char ui_off;            /* (the window's updates not counted) */
static unsigned int t0;
static char ln[64];

static unsigned int now(void) { return eng_ticks; }

void __fastcall__ mp_log(const char *a, const char *b)
{
    if (!b)
        t_say(a);
    else {
        strcpy(ln, a);
        strcat(ln, " ");
        t_say2(ln, b);
    }
}

static char *hex2(char *p, unsigned char v)
{
    static const char hx[] = "0123456789ABCDEF";
    *p++ = hx[v >> 4];
    *p++ = hx[v & 15];
    *p = 0;
    return p;
}

/* the engine's events since the last call */
static void drain(void)
{
    unsigned char i, *e;
    char *p;
    while (tail != t_log_head) {
        i = tail;
        tail = (unsigned char)((tail + 1) & 31);
        e = t_log + (i << 3);
        strcpy(ln, "MP EV ");
        p = hex2(ln + 6, e[0]);
        *p++ = ' ';
        p = hex2(p, e[1]);
        *p++ = ' ';
        p = hex2(p, e[2]);
        *p++ = ' ';
        p = hex2(p, e[4]);
        hex2(p, e[3]);
        t_say(ln);
    }
}

static void play(const char *name)
{
    unsigned char e = find_entry(name);
    if (e == 0xFF) {
        t_say2("MP NO ENTRY ", name);
        return;
    }
    t_select(e);
    if (wav && !recording) {            /* (the recording starts; once: each 1 starts the file again) */
        *(volatile unsigned char *)0x9FB6 = 1;
        recording = 1;
    }
    ui_play(e);
}

static void silent(void)
{
    unsigned char v[24], i, n = 0;
    eng_voices(v);
    for (i = 0; i < 24; ++i)
        n += v[i];
    t_saynum("MP VOICES ON ", n);
}

unsigned long t_cycles(void);

void mp_test_start(void)
{
    t_read("MP.TST");
    t_say2("MP SESSION ", t_session);
    wav = !strcmp(t_session, "wav");
    tail = t_log_head;
    t0 = now();
}

/* (V206) the window's work in the main loop (update's 20 a second: the
   meters, the keyboard, the display): its cycles, by the emulator's
   counter ($9FB8: the first read latches all four bytes) */
static unsigned long ui_c0, ui_sum, ui_max, ui_n, ui_from;

unsigned long t_cycles(void)
{
    unsigned long v;
    unsigned char *p = (unsigned char *)&v;
    p[0] = *(volatile unsigned char *)0x9FB8;
    p[1] = *(volatile unsigned char *)0x9FB9;
    p[2] = *(volatile unsigned char *)0x9FBA;
    p[3] = *(volatile unsigned char *)0x9FBB;
    return v;
}

void t_ui_begin(void)
{
    ui_c0 = t_cycles();
    if (!ui_from)
        ui_from = ui_c0;
}

void t_ui_end(void)
{
    unsigned long d = t_cycles() - ui_c0;
    if (!loaded || paused || ui_off)
        return;
    ui_sum += d;
    ++ui_n;
    if (d > ui_max)
        ui_max = d;
}

void mp_test_quit(void)
{
    t_saynum("MP UI MAX ", ui_max);
    t_saynum("MP UI SUM ", ui_sum);
    t_saynum("MP UI N ", ui_n);
    t_saynum("MP UI SPAN ", t_cycles() - ui_from);
    drain();
    t_saynum("MP CYC MAX ", t_cyc_max);
    t_saynum("MP CYC SUM ", t_cyc_sum);
    t_saynum("MP CYC TICKS ", t_ticks);
    t_saynum("MP GAP MAX ", t_gap_max);
}

/* the window updated twice since the mark (what it shows has caught up) */
static unsigned char settled(void)
{
    return ui_n >= mark + 2;
}

static unsigned char after(unsigned int t)
{
    return (unsigned int)(now() - t0) >= t;
}

static void next(unsigned char s)
{
    step = s;
    t0 = now();
}

/* the window drawn whole in dark mode or light while a song plays: its
   ticks' lateness logged apart ("MP DARK REDRAW GAP"), not in "MP GAP
   MAX": the whole window's fills (vr_win's bands: whole rows) keep the
   interrupt off up to 5,400 cycles at a time (the kernel's FX fills, V68);
   the program draws it whole only at its start and when it comes back
   from Alt+Tab with the theme changed, the music paused then */
static void dark(unsigned char on)
{
    unsigned long g0 = t_gap_max;
    t_gap_max = 0;
    t_dark(on);
    t_saynum("MP DARK REDRAW GAP ", t_gap_max);
    t_gap_max = g0;
}

static void host(void)
{
    unsigned char i;
    switch (step) {
    case 0:
        if (!after(20))
            return;
        t_enter("MUSIC");
        for (i = 0; i < n_ent; ++i) {
            ent_get(i);
            t_say2("MP LIST ", cur);
        }
        snap("LIST.RAW");
        play("BAD.MID");
        t_saynum("MP ERR ", err);
        play("FMT0.MID");               /* (Play next is on: FMT1.MID follows) */
        next(1);
        return;
    case 1:                             /* FMT1.MID plays: 1.7 s in, the picture */
        if (!loaded || strcmp(playing_name, "FMT1.MID") || eng_frames < 100)
            return;
        t_saynum("MP MIDI SNAP AT ", eng_frames);
        snap("MIDI.RAW");
        next(2);
        return;
    case 2:
        if (eng_frames < 150)
            return;
        t_saynum("MP PAUSE AT ", eng_frames);
        t_pause_toggle();
        next(3);
        return;
    case 3:
        if (!after(10))
            return;
        silent();
        next(4);
        return;
    case 4:
        if (!after(60))
            return;
        t_saynum("MP RESUME AT ", eng_frames);
        t_pause_toggle();
        next(5);
        return;
    case 5:                             /* FMT1.MID to its end: SONG.ZSM follows */
        if (!loaded || strcmp(playing_name, "SONG.ZSM") || eng_frames < 12)
            return;
        mark = ui_n;
        next(50);
        return;
    case 50:
        if (!settled())
            return;
        t_saynum("MP ZSM SNAP AT ", eng_frames);
        snap("ZSM.RAW");
        next(6);
        return;
    case 6:                             /* the last song: Play next stops after it */
        if (loaded)
            return;
        silent();
        t_volume(-1);
        t_volume(-1);
        t_volume(1);
        t_saynum("MP VOLUME ", volume);
        t_toggle_repeat();              /* Repeat on: FMT0.MID twice */
        play("FMT0.MID");
        next(20);
        return;
    case 20:
        if (!after(200))
            return;
        t_saynum("MP REPEAT FRAMES ", eng_frames);
        t_toggle_repeat();
        t_stop();
        t_enter("More");                /* LOOP.ZSM: once round, faded, then (the last) stopped */
        play("LOOP.ZSM");
        next(21);
        return;
    case 21:
        if (loaded)
            return;
        t_saynum("MP LOOP TICKS ", now() - t0);
        play("DEMO.MID");               /* (V206) what the window shows of a song */
        next(30);
        return;
    case 30:
        if (!loaded || eng_frames < 50)
            return;
        mark = ui_n;
        next(31);
        return;
    case 31:
        if (!settled())
            return;
        t_saynum("MP DEMO SNAP AT ", eng_frames);
        t_say2("MP DEMO TITLE ", info.title);
        t_say2("MP DEMO TEXT ", info.text);
        t_saynum("MP DEMO SECS ", info.known ? info.secs : 9999);
        snap("DEMO.RAW");
        dark(1);
        mark = ui_n;
        next(32);
        return;
    case 32:
        if (!settled())
            return;
        t_saynum("MP DARK SNAP AT ", eng_frames);
        snap("DARK.RAW");
        next(33);                       /* (V208) DEMO.MID to its end: DESERT.MID follows (dark mode) */
        return;
    case 33:
    case 35:
        if (!loaded || strcmp(playing_name, "DESERT.MID") || eng_frames < 60)
            return;
        mark = ui_n;
        next(step + 1);
        return;
    case 34:
        if (!settled())
            return;
        t_saynum("MP NEXTDK SNAP AT ", eng_frames);
        t_say2("MP NEXT TITLE ", info.title);
        t_say2("MP NEXT TEXT ", info.text);
        t_saynum("MP NEXT SECS ", info.known ? info.secs : 9999);
        snap("NEXTDK.RAW");
        dark(0);
        play("DEMO.MID");               /* (and again in light mode) */
        next(35);
        return;
    case 36:
        if (!settled())
            return;
        t_saynum("MP NEXT SNAP AT ", eng_frames);
        snap("NEXT.RAW");
        t_stop();
        t_enter("..");
        play("FMT1.MID");
        next(7);
        return;
    case 7:
        if (eng_frames < 60)
            return;
        t_saynum("MP ASIDE AT ", eng_frames);
        TaskCtl(TASK_ASIDE, 0, 0);
        next(8);
        return;
    case 8:                             /* back: the music goes on */
        if (eng_frames < 120)
            return;
        t_saynum("MP ON AFTER ", eng_frames);
        next(9);
        t_saynum("MP STRESS FROM ", now());
        ui_off = 1;                     /* (the redraws' updates not in the window's figures) */
        return;
    case 9:                             /* the window's body drawn again and again while it plays */
        t_redraw();
        ++redraws;
        if (redraws < 40)
            return;
        t_saynum("MP REDRAWS ", redraws);
        t_saynum("MP STRESS TO ", now());
        ui_off = 0;
        t_quit();
        return;
    }
}

static void wavrun(void)
{
    switch (step) {
    case 0:
        if (!after(20))
            return;
        t_enter("MUSIC");
        t_toggle_next();                /* (off: each song as the script says) */
        play("FMT1.MID");
        t_saynum("MP T PLAY ", now());
        next(1);
        return;
    case 1:                             /* (1.25 s: the next notes at 1.5 s, the long one at 2) */
        if (!after(75))
            return;
        t_pause_toggle();
        t_saynum("MP T PAUSE ", now());
        next(2);
        return;
    case 2:
        if (!after(120))
            return;
        t_pause_toggle();
        t_saynum("MP T RESUME ", now());
        next(3);
        return;
    case 3:
        if (!after(120))
            return;
        t_stop();
        t_saynum("MP T STOP ", now());
        next(4);
        return;
    case 4:
        if (!after(90))
            return;
        play("SONG.ZSM");
        t_saynum("MP T ZSM ", now());
        next(5);
        return;
    case 5:
        if (loaded)
            return;
        t_saynum("MP T ZSM END ", now());
        next(6);
        return;
    case 6:
        if (!after(30))
            return;
        t_saynum("MP T QUIT ", now());
        t_quit();
        return;
    }
}

/* soak: the folder MUSIC's first song, 20 s at most, then quit: the
   tick's cycles with a real song (by hand: the gate's songs are small) */
static char soak_name[64];
static void soak(void)
{
    unsigned char i;
    switch (step) {
    case 0:
        if (!after(20))
            return;
        t_enter("MUSIC");
        for (i = 0; i < n_ent; ++i) {
            ent_get(i);
            if (cur[0] == E_MIDI || cur[0] == E_ZSM)
                break;
        }
        t_select(i);
        ui_play(i);
        strcpy(soak_name, playing_name);
        next(1);
        return;
    case 1:
        if (loaded && !strcmp(playing_name, soak_name) && eng_frames < 1200)
            return;
        t_saynum("MP SOAK FRAMES ", eng_frames);
        t_quit();
        return;
    }
}

/* dock: started by tests/midiplay_desk.c as the dock starts a program
   (V206): the folder shown, then up to the card's top */
static void dockrun(void)
{
    unsigned char i, k;
    if (step || !after(30))
        return;
    step = 1;
    t_say2("MP DOCK FOLDER ", (const char *)curDirName);
    for (k = 0; k < 3; ++k) {
        t_enter("..");
        t_say2("MP DOCK UP ", (const char *)curDirName);
        if (k == 1)
            for (i = 0; i < n_ent; ++i) {
                ent_get(i);
                t_say2("MP DOCK LIST ", cur);
            }
    }
    t_quit();
}

/* doc: started by tests/midiplay_desk.c with /MUSIC/FMT0.MID as its
   document (as the shell opens one) */
static void docrun(void)
{
    if (step || !after(30))
        return;
    step = 1;
    t_say2("MP DOC FOLDER ", (const char *)curDirName);
    t_say2("MP DOC PLAYING ", loaded ? playing_name : "nothing");
    t_saynum("MP DOC SELECTED ", sel == playing_ent);
    t_quit();
}

void mp_test_tick(void)
{
    if (!strcmp(t_session, "dock")) {
        drain();
        dockrun();
        return;
    }
    if (!strcmp(t_session, "doc")) {
        drain();
        docrun();
        return;
    }
    if (!strcmp(t_session, "soak")) {
        tail = t_log_head;              /* (the events not logged) */
        soak();
        return;
    }
    drain();
    if (wav)
        wavrun();
    else
        host();
}
