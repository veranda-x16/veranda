/* Veranda Update (DECISIONS V130): what its files share. MIT licence (see
   LICENSE). */
#ifndef UP_H
#define UP_H

#include "../sysui/sysui.h"

/*---------------------------------------------------------------- the settings (main.c) */
#define SRC_GITHUB 0
#define SRC_PC     1
struct cfg {
    unsigned char src;
    char repo[48];              /* owner/repo */
    char pc[40];                /* host:port */
    char gh[40];                /* GitHub's host[:port] (github.com; a gate's stand-in) */
    unsigned char test;         /* GitHub's channel: 0 Stable (the latest release), 1 Test (the release "test") */
};
extern struct cfg C;
void cfg_save(void);
void cfg_load_o(void), cfg_save_o(void);   /* (ui.c, overlay 2: V198) */
void back_o(void);              /* (swap.c, overlay 3: V198) */

/*---------------------------------------------------------------- the dictionaries (V198) */
/* Veranda Write's spelling dictionaries are not in Veranda's releases:
   they are the assets of one release of Write's repository, tagged by
   their format (dict-1: the format Write reads now; a later format gets
   a new tag, so an older Write never fetches what it cannot read), with
   their list DICT.LST (UPDATE.LST's format: every file under
   VERANDA/DICT/). Dictionaries for Write (D) checks that list instead of
   Veranda's; Update then asks which to get. Always from GitHub (C.gh),
   whatever the source */
#define X_REPO  "veranda-x16/veranda-write"
#define X_TAG   "dict-1"
#define X_LIST  "DICT.LST"
#define X_DIR   "VERANDA/DICT/"
extern unsigned char xmode;     /* 1: the dictionaries' list is the one checked (job_dict) */
extern char back[18];           /* UPDATE.REQ's "back": the program put aside that asked (Quit brings it back) */
unsigned char req_load(void);   /* UPDATE.REQ read and deleted: 1 if it asks for the dictionaries */
unsigned char req_load_o(void);

/*---------------------------------------------------------------- the network (http.c) */
#define URLMAX 1100             /* GitHub's signed asset addresses are near 1 KB */
extern char hurl[URLMAX];       /* the address asked for (then a redirect's): overlay 1's BSS */
extern unsigned int hstatus;    /* the last reply's status */
extern unsigned long hgot;      /* body bytes delivered */
extern unsigned long hlen;      /* Content-Length, 0xFFFFFFFF none (chunked or until closed) */
extern unsigned char hredir, hchunked;
extern signed char hnet;        /* vrnet's error */
extern unsigned char net_on;
/* the body's bytes go here (main RAM): 0 = a local error, the request stops */
extern unsigned char __fastcall__ (*hsink)(const unsigned char *b, unsigned int n);
enum { H_RUN, H_OK, H_ENOCARD, H_EMODEM, H_ECONN, H_EDROP, H_ETIMEOUT, H_E404, H_ESTATUS,
       H_EREDIR, H_EURL, H_ELOCAL, H_ECANCEL, H_EHDR };
void http_get(void);            /* hurl, already set */
unsigned char http_poll(void);  /* H_RUN, else the result (once) */
void http_cancel(void);
void net_restart(void);
const char *__fastcall__ http_why(unsigned char e);   /* (job.c: overlay 1) */

/*---------------------------------------------------------------- CRC-32 (crc.s) */
extern unsigned long crcv;      /* the running value: crc_start, crc_add..., then crc_end */
extern unsigned char crcbank;   /* the table's RAM bank (crc_init makes it there) */
void crc_init(void);            /* the tables (once) */
void crc_start(void);
void __fastcall__ crc_add(const void *buf, unsigned int n);
unsigned long crc_end(void);

/*---------------------------------------------------------------- the manifest (man.c) */
#define K_SYSTEM 0
#define K_APP    1
#define K_FONT   2
#define K_HELP   3
#define K_WALL   4
#define K_PC     5
#define K_DOC    6              /* doc-sample: never written (the user's /DOCUMENTS) */
#define K_OTHER  7

/* an entry: 101 bytes in the table's RAM banks */
#define S_UNKNOWN 0
#define S_SAME    1
#define S_CHANGED 2
#define S_NEW     3
#define S_SKIP    4
struct ent {
    unsigned long size, crc;
    unsigned char kind, st, ready, shared;
    char min[11];               /* "-" or YYYY-MM-DD */
    char asset[14];
    char path[64];
};
#define ENT_SIZE 101
#define ENT_PER_BANK 81
#define ENT_MAX 162
extern struct ent E;            /* the one being looked at */
extern unsigned char nents;
extern unsigned char tbank;     /* the table's two banks (tbank, tbank + 1), the text's (tbank + 2), the CRC's (tbank + 3) */
void __fastcall__ ent_get(unsigned char i);
void __fastcall__ ent_put(unsigned char i);

extern char nbuild[16], ndate[11], ntag[48];
extern char nver[16], iver[16];  /* the manifest's and the card's "version" line (0.N.M), "" none */
#define NOTES 8
extern char notes[NOTES][77];
extern unsigned char nnotes;
extern char ibuild[16], idate[11];      /* the card's (VERANDA/UPDATE.LST) */
/* the manifest file (in folder dir, name) read into the table: 0 or why not */
const char *__fastcall__ man_load(const char *dir, const char *name);
void man_installed(void);       /* ibuild, idate from the card */
const char *__fastcall__ man_load_o(const char *dir, const char *name);
void man_installed_o(void);

/*---------------------------------------------------------------- the jobs (job.c) */
enum { J_NONE, J_MAN, J_SCAN, J_DL };
extern unsigned char job;
extern unsigned char checked;   /* a manifest is loaded and the card compared */
extern unsigned char nchanged, nnew, nready, nsys, nskip;
extern unsigned long tchanged;  /* bytes of what is to come */
extern unsigned long tfetch, tdone;     /* bytes to fetch, fetched so far */
extern unsigned char ifetch, nfetch;    /* the file being fetched (1-based), of */
extern unsigned char cur;       /* the entry being worked on */
extern unsigned char slept;     /* put aside while a file was open */
extern unsigned char refused;   /* (why the last update stopped: test builds) */
void job_check(void);
void job_dict(void);            /* (V198) Check, the dictionaries' list */
void job_update(void);
void job_undo(void);
void job_tick(void);
void __fastcall__ job_stop(const char *why);
void job_wake(void);            /* back from the switcher */
void job_aside(void);           /* the switcher puts us aside */
#define UPD_DIR "/VERANDA/.SYSTEM/UPD"
#define OLD_DIR "/VERANDA/.SYSTEM/OLD"
/* the paths job.c and swap.c take: from the card's top, no leading "/" */
#define SYS_UPD "VERANDA/.SYSTEM/UPD/"
#define SYS_OLD "VERANDA/.SYSTEM/OLD/"

/*---------------------------------------------------------------- the card (swap.c, overlay 3) */
unsigned char job_resume_swap(void);    /* a swap cut short finished: 1 if there was one */
unsigned char undo_ready(void); /* an update to undo */
void swap_go(void);             /* every file verified in UPD: the swap */
unsigned char __fastcall__ exists(const char *p);
void __fastcall__ del(const char *p);
void __fastcall__ mkdirs(const char *p);
/* file p of size bytes against crc: 0 not there, 1 equal, 2 not */
unsigned char __fastcall__ fcheck(const char *p, unsigned long size, unsigned long crc);
unsigned char job_resume_swap_o(void);
unsigned char undo_ready_o(void);
void job_undo_o(void);
void swap_go_o(void);
unsigned char __fastcall__ exists_o(const char *p);
void __fastcall__ del_o(const char *p);
void __fastcall__ mkdirs_o(const char *p);
unsigned char __fastcall__ fcheck_o(const char *p, unsigned long size, unsigned long crc);

/*---------------------------------------------------------------- overlays (main.c) */
/* overlay 1 (job.c) is appBank, mapped whenever Veranda calls the program;
   overlay 2 (man.c, ui.c) and 3 (swap.c) are mapped by main.c's wrappers
   around each call (their functions end in _o) and the bank before
   mapped again after. A pointer handed from one overlay to another, or to
   the kernel, must be below $A000: K(s) copies a string there (two
   buffers in turn) */
extern unsigned char bOv2, bOv3;
char *__fastcall__ K(const char *s);

/*---------------------------------------------------------------- the window (ui.c) */
void ui_all(void);
void ui_head(void);
void ui_list(void);
void __fastcall__ ui_progress(const char *name);
void __fastcall__ say(const char *s);
void ui_source(void);           /* Source...: the boxes */
void ui_all_o(void);
void ui_head_o(void);
void ui_list_o(void);
void __fastcall__ ui_progress_o(const char *name);
void ui_source_o(void);
extern char line[128];
#define IOBUF 512
extern unsigned char iobuf[IOBUF];      /* (main RAM: the file calls' buffer, shared) */
unsigned char __fastcall__ up_confirm(const char *a, const char *b);
void __fastcall__ up_message(const char *a, const char *b);
void __fastcall__ up_log(const char *a, const char *b);
void up_restart(void);

#ifdef UP_TEST
extern unsigned int t_free;             /* the card's free KB as the test says (0: CalcBlksFree's) */
extern unsigned char t_aside_at;        /* put aside at this many KB of a file (0: no) */
void up_test_start(void);
void up_test_tick(void);
#endif

#endif
