/*
 * mp.h -- MIDI Player (apps/midiplay; DECISIONS V205): MIDI and ZSM
 * music on the YM2151 and VERA's PSG, a native Veranda program.
 *
 * Where the code lives (app.hdr: overlays = banked):
 *   main RAM   main.c: the start, the folder's entries (in RAM banks), a
 *              song loaded into RAM banks, playing, everything that maps
 *              another bank; engine.s: the interrupt's tick, the engines'
 *              calls; vendor/melodius: Melodius's MIDI engine (midi.s,
 *              math.s); the strings and tables the kernel reads
 *   overlay 1  ui.c: the window, the playlist, now playing, the toolbar,
 *              the menus' routines, the keys and the pointer; mapped for
 *              good as appBank, so Veranda's calls to the program find it
 *   overlay 2  ZSMKit's first bank ($A000: its jump table, code, data)
 *   overlay 3  ZSMKit's second bank (the overlays' banks are one run:
 *              record n in bank first + n, so 2 and 3 are adjacent, as
 *              ZSMKit v3 needs)
 *
 * MIT licence (see LICENSE). Melodius and ZSMKit: MIT, Copyright (c) 2023
 * MooingLemur (vendor/).
 */
#ifndef MP_H
#define MP_H
#include <veranda.h>
#include <vr.h>
#include <string.h>

#define MAPBANK(b) (*(volatile unsigned char *)0 = (b))
#define BANK       (*(volatile unsigned char *)0)

/*---------------------------------------------------------------- engine.s */
extern unsigned char eng_mode;          /* 0 nothing, 1 MIDI, 2 ZSM */
extern volatile unsigned char eng_run;  /* the interrupt ticks the song */
extern volatile unsigned int eng_frames;        /* ticks played (60 a second) */
extern volatile unsigned int eng_ticks; /* every interrupt's */
extern unsigned char zsm_bank;          /* ZSMKit's first bank */
extern unsigned int eng_loops;          /* ZSM: times it looped (eng_zsm_state) */
void eng_init(void);
void eng_irq_on(void);
void eng_irq_off(void);
unsigned char __fastcall__ eng_midi_load(unsigned char bank);   /* 0 ok */
unsigned char __fastcall__ eng_zsm_load(unsigned char bank);    /* 0 ok */
void eng_go(void);                      /* start or go on */
void eng_pause(void);                   /* the voices released */
void eng_stop(void);                    /* the song closed, everything silent */
void eng_rewind(void);                  /* the song from its start (stopped) */
void eng_silence(void);                 /* the YM2151 reset, PSG voices 0-13 silent */
unsigned char eng_zsm_state(void);      /* bit 0 playing, bit 7 not playable; eng_loops */
unsigned char eng_midi_playing(void);
void __fastcall__ eng_volume(unsigned char v);  /* 0-10 */
void __fastcall__ eng_voices(unsigned char *buf);       /* 8 YM, 16 PSG: 1 sounding */
unsigned long eng_zsm_pos(void);        /* ZSM: the cursor's offset in the file */
unsigned long eng_midi_pos(void);       /* MIDI: the tracks' bytes played */
/* Melodius's state (vendor/melodius/midi.s) */
extern unsigned char midi_format, midi_ntracks;
extern unsigned char midi_tempo[4];     /* BPM, a digit a byte: hundreds, tens, ones, tenths */
extern unsigned char midibeat;          /* BCD */
extern unsigned int midimeasure;        /* BCD */
extern unsigned char midi_timesig_numerator, midi_timesig_denominator;
extern char lyrics[32];

/*---------------------------------------------------------------- main.c */
#define ENT_MAX    255
extern unsigned char n_ent, n_songs, top, sel;
extern char cur[64];                    /* an entry read back: type, name */
void ent_get(unsigned char i);
unsigned char at_root(void);
void list_read(void);
unsigned char find_entry(const char *name);
/* entry types */
#define E_UP     'U'
#define E_DIR    'D'
#define E_MIDI   'M'
#define E_ZSM    'Z'
#define E_LONG   'L'                    /* a song whose name is too long to open */

extern char playing_name[64];
extern char playing_dir[64];
extern unsigned char playing_ent, loaded, paused, kind, volume, repeat, play_next;
extern unsigned long song_size;
extern unsigned char err;
/* errors (play_entry) */
#define ERR_OPEN   1
#define ERR_EMPTY  2
#define ERR_MEM    3
#define ERR_READ   4
#define ERR_MIDI   5
#define ERR_ZSM    6
unsigned char play_entry(unsigned char e);
void stop(void);
void pause_set(unsigned char p);
void restart(void);
unsigned char music_dir(void);
void __fastcall__ song_peek(unsigned char *buf, unsigned char n);      /* the song's first n bytes */
void set_volume(unsigned char v);
extern unsigned char ui_bank;
extern char sb[80];                     /* a string for the kernel */

/*---------------------------------------------------------------- ui.c */
void ui_start(void);
void ui_list(void);
void ui_play(unsigned char e);

/*---------------------------------------------------------------- the test build */
#ifdef MP_TEST
void mp_test_start(void);
void mp_test_tick(void);
void __fastcall__ t_say(const char *s);
void __fastcall__ t_say2(const char *a, const char *b);
void __fastcall__ t_saynum(const char *a, unsigned long v);
void __fastcall__ mp_log(const char *a, const char *b);     /* a, and b after a space */
#define LOG(a, b) mp_log(a, b)
#else
#define LOG(a, b)
#endif

#endif
