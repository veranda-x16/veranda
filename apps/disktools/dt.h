/* Disk Tools (DECISIONS V119): what its files share. MIT licence (see
   LICENSE). */
#ifndef DT_H
#define DT_H

#include "../sysui/sysui.h"

/* the tabs */
enum { T_CARD, T_SPACE, T_CHECK, T_CLEAN, T_N };
extern unsigned char tab;

/* the body's hot spots (sysui's ui_hot ids) */
enum {
    H_RENAME = 1, H_COUNT, H_UP, H_CHECK, H_EMPTY, H_SCAN,
    H_DEL0,                     /* H_DEL0 + kind: delete that kind */
    H_ROW0 = 32                 /* H_ROW0 + row: a folder of Space use */
};

extern char line[128];          /* scratch text */
void __fastcall__ say(const char *s);           /* the status bar's left */
void __fastcall__ dt_log(const char *a, const char *b);  /* the console (test builds) */
void draw_tab(void);            /* the body of the tab shown */
void __fastcall__ progress(const char *s);      /* the progress line (the status bar) */

/* a job stepped from the main loop: one is running at a time */
enum { J_NONE, J_SPACE, J_SCAN, J_CHECK };
extern unsigned char job;
extern unsigned char put_aside; /* the switcher put us aside during the job */

/*---------------------------------------------------------------- walk.c */
/* the folder walker: a folder a step (its long listing read whole, so
   nothing is open between two steps); folders on a stack in RAM banks */
#define PATHMAX 63
struct wentry { char name[64]; unsigned long size; unsigned char dir; };
extern struct wentry went;      /* the entry being handed over */
extern char wpath[64];          /* the folder being read */
extern unsigned int w_folders, w_files, w_skipped;
extern unsigned char w_tag;     /* the tag of the folder being read */
/* start at path; 0: no RAM bank */
unsigned char __fastcall__ walk_start(const char *path);
/* push a folder (path + "/" + name) with a tag; 0 if too long or full */
unsigned char __fastcall__ walk_push(const char *name, unsigned char tag);
/* one folder: each entry to f (went; w_tag, wpath its folder's);
   0 when there are none left */
unsigned char __fastcall__ walk_step(void (*f)(void));
void walk_end(void);
/* the folder wpath alone listed, as walk_step lists one; 0 if it cannot
   be read */
unsigned char __fastcall__ walk_list(void (*f)(void));
/* path a "/" b into out (64 bytes); 0 if too long */
unsigned char __fastcall__ join(char *out, const char *a, const char *b);

/*---------------------------------------------------------------- space.c */
void space_draw(void);
void space_start(void);
void space_tick(void);
void space_stop(const char *why);
void __fastcall__ space_open(unsigned char row);
void space_up(void);
void __fastcall__ space_key(unsigned char k);
extern unsigned char sp_done;

/*---------------------------------------------------------------- check.c */
void check_draw(void);
void check_start(void);
void check_tick(void);
void check_stop(const char *why);

/*---------------------------------------------------------------- clean.c */
void clean_draw(void);
void clean_trash(void);         /* the trash looked at */
void clean_empty(void);
void clean_scan(void);
void clean_tick(void);
void clean_stop(const char *why);
void __fastcall__ clean_delete(unsigned char kind);

/*---------------------------------------------------------------- the card tab */
void card_draw(void);
void card_rename(void);
void card_log(void);

/*---------------------------------------------------------------- overlays */
/* overlay 1 (clean.c, the window's chrome: vrwin) is appBank, mapped
   whenever Veranda calls the program; overlay 2 (space.c, cardtab.c,
   checkui.c) is mapped by the wrappers in main.c around each call (its
   functions end in _o; code in overlay 2 calls its own _o functions, never
   the wrappers). Neither may map another bank at $A000: their RAM banks'
   contents go through these (BankCopy) */
extern unsigned char bOv2;
void __fastcall__ bget(unsigned char bank, unsigned int off, void *dst, unsigned int n);
void __fastcall__ bput(unsigned char bank, unsigned int off, const void *src, unsigned int n);
void space_draw_o(void);
void space_start_o(void);
void space_tick_o(void);
void space_stop_o(const char *why);
void __fastcall__ space_open_o(unsigned char row);
void space_up_o(void);
void __fastcall__ space_key_o(unsigned char k);
void card_draw_o(void);
void card_rename_o(void);
void card_log_o(void);
void check_draw_o(void);
void card_read_o(void);
void card_dos_o(void);

#ifdef DT_TEST
void dt_test_start(void);
void dt_test_tick(void);
#endif

#endif
