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
 *   overlay 4  vis.c: the voices' meters, the keyboard
 *              (V206); called through far_call() (engine.s) with far_bank
 *              vis_bank, its strings handed to sysui's ui_text (which
 *              copies them below $A000 for the kernel)
 *   overlay 5  info.c: a song read through at its start (its name, its
 *              text, its length), the General MIDI programs' names
 *   overlay 6  now.c: now playing (vis.c and ui.c call it)
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
/* (V206) another overlay's routine: f called with bank far_bank mapped */
extern unsigned char far_bank;
void __fastcall__ far_call(void (*f)(void));
/* peek_n bytes (1-255) from peek_src in bank peek_bank to dst (below $A000) */
extern unsigned char peek_bank, peek_n;
extern unsigned int peek_src;
void __fastcall__ eng_peek(unsigned char *dst);
/* ZSM: the key-on shadow (8) and YM2151 registers $20-$2F (16) */
void __fastcall__ eng_zsm_ym(unsigned char *buf);
/* the PSG's 64 registers (4 a voice: frequency low, high; volume and sides; wave) */
void __fastcall__ eng_psg(unsigned char *buf);
/* Melodius's voices (V206): each YM channel's note (0 released), patch
   ($FF a drum), MIDI channel, attenuation, calls since its note changed;
   each MIDI channel's program and note-on mark (6 at a note-on; the
   window clears it) */
extern unsigned char ymnote[8], yminst[8], ymmidi[8], ymatten[8], midi_ym_callcnt[8];
extern unsigned char midiinst[16], midi_msg_sent[16];
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
extern unsigned char song_bank;         /* the song's first RAM bank */
extern unsigned char song_no;           /* (V206) changes when a song starts or stops */
extern unsigned char hilite;            /* the theme's selection colour */
extern unsigned char vis_bank, info_bank, now_bank;
/* (V206) what info.c read from the song at its start */
struct songinfo {
    char title[48];             /* MIDI: the first track's name (meta 3) */
    char text[56];              /* MIDI: the copyright (meta 2), else the first text at its start */
    unsigned int secs;          /* the length in seconds (ZSM: once round) */
    unsigned char known;        /* secs is known */
};
extern struct songinfo info;
extern char gm[24];             /* gm_name's answer */
extern unsigned char gm_prog;   /* its question: a program 0-127, $FF drums */
#define VIS(f) (far_bank = vis_bank, far_call(f))
#define INFO(f) (far_bank = info_bank, far_call(f))
#define NOW(f) (far_bank = now_bank, far_call(f))
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

/*---------------------------------------------------------------- vis.c (overlay 4), info.c (5), now.c (6) */
void vis_frame(void);                   /* the panels' fixed parts, drawn whole */
void vis_song(void);                    /* a song started or stopped: its lines */
void vis_tick(void);                    /* 20 times a second: what changed */
extern unsigned int vis_x;              /* now_where's question: a pixel ... */
void now_where(void);                   /* ... on the progress bar: its time into sb */
void now_song(void);                    /* now playing: the song's lines */
void now_tick(void);                    /* the display, the progress, the lyrics */
void info_scan(void);                   /* the song read through: info */
void gm_name(void);                     /* gm_prog's name into gm */

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
