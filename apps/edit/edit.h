/* Veranda Edit: shared declarations (MIT licence, see LICENSE). The text,
   the view, editing, undo, find, the clipboard and the files are textkit's
   (the SDK's src/textkit: textkit.h, DECISIONS V93); this is the rest. */
#ifndef EDIT_H
#define EDIT_H

#include <veranda.h>
#include <vr.h>

#ifdef EDIT_TEST
void test_clock_reset(void);
void test_clock_log(const char *what);
#define T_RESET() test_clock_reset()
#define T_LOG(s) test_clock_log(s)
#endif

#define TK_UTF8                         /* (V143: UTF-8 files, textkit's u8.c) */
#include <textkit.h>

extern unsigned char iobuf[TK_IOBUF];   /* file and scrap transfers */
extern unsigned char font[2048];
extern const unsigned char vr_icon[128];  /* (V148) the alerts' icon: alerticon.c, from icon.txt */

/* misc.c (main RAM) */
void menus_off(void);
void __fastcall__ call2(void (*f)(void));
extern unsigned char edit_idle, need_fix, bank1, bank2;
extern char status_msg[48];
void font_load(void);
void sys_dir(void);
unsigned char __fastcall__ alert(unsigned char kind, const char *head, const char *text);  /* (V148) vr_alert (overlay 1) */                     /* the desk accessories' folder (/VERANDA/APPS) */

/* main.c (overlay 1) */
void __fastcall__ a_main(unsigned char opts);
void quit(void), m_about(void), m_undo(void), m_selall(void), m_desk(void);
void c_new(void), c_open(void), c_save(void), c_saveas(void), c_find(void), c_findnext(void);
void c_replnext(void), c_goto(void), mc_cut(void), mc_copy(void), mc_paste(void), c_enc(void);

/* menus.c (overlay 2: call2(layout)) */
void layout(void);
extern void *const menubar;
extern unsigned int barx[4];

#ifdef EDIT_TEST
void test_start(void);
void test_mark(const char *what);
void test_log_state(void);
void __fastcall__ play_slow(unsigned char cur);
extern unsigned char test_log;
void __fastcall__ test_key(unsigned char k);
void test_drawn(void);
#endif

#endif
