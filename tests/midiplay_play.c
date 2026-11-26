/* gate midiplay (DECISIONS V205): MIDI Player's test build (apps/midiplay,
   make test: MP_TEST). MP.TST in the top folder names the session:
     host   the folder MUSIC listed (LIST.RAW); BAD.MID refused; FMT0.MID
            (format 0) played to its end, Play next on: FMT1.MID follows
            (format 1: three tracks, a tempo change, drums on channel 10,
            running status, a long note, pitch bend) (MIDI.RAW), paused
            for a second (the voices silent, the time held) and resumed;
            at its end SONG.ZSM (ZSM.RAW): it ends, and Play next stops
            after the last song; the volume down and up; Repeat: FMT0.MID
            twice; More/LOOP.ZSM (a loop): once round, faded out, stopped
            (the folder's last song); FMT1.MID again and
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

static unsigned char step, tail, wav, redraws, recording;
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

void mp_test_start(void)
{
    t_read("MP.TST");
    t_say2("MP SESSION ", t_session);
    wav = !strcmp(t_session, "wav");
    tail = t_log_head;
    t0 = now();
}

void mp_test_quit(void)
{
    drain();
    t_saynum("MP CYC MAX ", t_cyc_max);
    t_saynum("MP CYC SUM ", t_cyc_sum);
    t_saynum("MP CYC TICKS ", t_ticks);
    t_saynum("MP GAP MAX ", t_gap_max);
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
        if (!loaded || strcmp(playing_name, "SONG.ZSM") || eng_frames < 15)
            return;
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
        return;
    case 9:                             /* the window's body drawn again and again while it plays */
        t_redraw();
        ++redraws;
        if (redraws < 40)
            return;
        t_saynum("MP REDRAWS ", redraws);
        t_saynum("MP STRESS TO ", now());
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
