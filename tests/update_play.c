/* gate update (DECISIONS V130): Veranda Update's test build (apps/update,
   make test: UP_TEST). UPDATE.TST in the top folder: "run" and the steps
   (48 characters at most: sysui_test.c's t_arg),
   each waiting for the one before to end (the job idle):
     check           Check (the manifest, the card compared)
     update          Update (its box answered OK)
     undo            Undo last update
     no              the next box answered Cancel
     nos:N           (V198) the boxes to come answered by N's bits: bit 0
                     the next, bit 1 the one after ...: 1 Cancel, 0 OK
     dict            Dictionaries for Write (V198: the dictionaries' list)
     free:KB         (V198) the card's free space taken as KB
     quit            Quit (UPDATE.REQ's back: that program brought back)
     snap:NAME       the screen to NAME.RAW
     aside:KB        Alt+Tab (TaskCtl TASK_ASIDE) when a file has KB
                     kilobytes (the test desktop brings it back)
     prog:KB         the screen to PROG.RAW once KB kilobytes have come
   Boxes are logged ("BOX ...") and answered at once (up_confirm,
   up_message); Restart to finish logs "UP RESTART". The session ends with
   "UP END" and dump.bin (the screen).
   MIT licence (see LICENSE). */
#include <veranda.h>
#include <string.h>
#include "../apps/update/up.h"

extern char t_session[];
extern char t_arg[];
void __fastcall__ t_read(const char *name);
void __fastcall__ t_say(const char *s);
void __fastcall__ t_saynum(const char *a, unsigned long v);
void __fastcall__ snap(const char *name);
void __fastcall__ t_end(const char *pfx);

extern unsigned char t_no, t_restarted;
void up_quit(void);
unsigned char t_aside_at;
unsigned int t_free;
static unsigned int t_prog;
static unsigned char pos, wait_;
static char w[24];

void up_test_start(void)
{
    t_read("UPDATE.TST");
    t_say(t_session);
    t_say(t_arg);
}

/* the next word of t_arg into w: 0 at the end */
static unsigned char word(void)
{
    unsigned char n = 0;
    while (t_arg[pos] == ' ')
        ++pos;
    while (t_arg[pos] && t_arg[pos] != ' ' && n < sizeof w - 1)
        w[n++] = t_arg[pos++];
    w[n] = 0;
    return n;
}

static unsigned int __fastcall__ num(const char *s)
{
    unsigned int v = 0;
    while (*s >= '0' && *s <= '9')
        v = v * 10 + (*s++ - '0');
    return v;
}

static void counts(void)
{
    t_saynum("UP N ENTS ", nents);
    t_saynum("UP N CHANGED ", nchanged);
    t_saynum("UP N NEW ", nnew);
    t_saynum("UP N READY ", nready);
    t_saynum("UP N SKIP ", nskip);
    t_saynum("UP N BYTES ", tchanged);
}

void up_test_tick(void)
{
    if (t_prog && job == J_DL && tdone >= (unsigned long)t_prog << 10) {
        t_prog = 0;
        snap("PROG.RAW");
    }
    if (job)
        return;
    if (wait_) {                        /* (a step ended) */
        wait_ = 0;
        counts();
    }
    if (!word()) {
        t_say(t_restarted ? "UP RESTARTED" : "UP NO RESTART");
        t_end("UP");
        return;
    }
    t_say(w);
    if (!strcmp(w, "check")) {
        job_check();
        wait_ = 1;
    } else if (!strcmp(w, "update")) {
        job_update();
        wait_ = 1;
    } else if (!strcmp(w, "undo")) {
        job_undo();
        wait_ = 1;
    } else if (!strcmp(w, "no"))
        t_no = 1;
    else if (!memcmp(w, "nos:", 4))
        t_no = (unsigned char)num(w + 4);
    else if (!strcmp(w, "dict")) {
        job_dict();
        wait_ = 1;
    } else if (!memcmp(w, "free:", 5))
        t_free = num(w + 5);
    else if (!strcmp(w, "quit")) {
        t_say("UP END");                /* (the session's log ends here: the program it goes back to goes on) */
        up_quit();
    }
    else if (!memcmp(w, "snap:", 5)) {
        strcat(w, ".RAW");
        snap(w + 5);
    } else if (!memcmp(w, "aside:", 6))
        t_aside_at = num(w + 6);
    else if (!memcmp(w, "prog:", 5))
        t_prog = num(w + 5);
}
