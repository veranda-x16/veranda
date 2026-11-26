/* Veranda shell: an X16 program (a plain .PRG) run from the desktop
   (overlay 17, its own: no other had the room; DECISIONS V197).

   A double click on (or Open of) a file ending in ".PRG" that is not a
   Veranda program: the shell asks, then goes to BASIC with Veranda kept
   (ToBASIC with TOBASIC_KEEP, DECISIONS V64) and has BASIC's EXEC type
   the rest:

     the keyboard queue  EXEC<a>          (a: msg's address, in decimal)
     msg (main RAM)      EXEC$BF00,<RB>   (the next hop, read at once)
     bank RB, $BF00      DOS"CD:<the program's folder>"
                         LOAD"<the program>",8
                         RUN
                         DOS"CD:/VERANDA"   (or "/" without it)
                         LOAD"RBOOT",8
                         RUN

   ToBASIC types at most 9 characters and RETURN (the ROM's queue holds
   10), and BASIC's warm start clears EXEC's state, so the first hop is
   typed; a line read by EXEC is copied out before it runs, so msg may be
   overwritten by the LOAD after it. EXEC is suspended while the program
   runs and goes on when BASIC is back at READY (its END, an error, RUN
   STOP): the last three lines are read then, from bank RB, the bank
   under the kernel banks' copy that holds Veranda's resident core while
   BASIC runs (BASIC's banks end below it: MEMTOP). RBOOT puts Veranda
   back from its copy in RAM, or loads it from the card if a program
   overwrote the copy.

   RB is kBankBase - RB_BELOW (kernel/kernel.inc): while Veranda runs,
   MEMTOP's bank count is kBankBase - KCOPY_BANKS (the loader), so RB is
   that count less one.

   MIT licence (see LICENSE). */
#include <veranda.h>
#include <string.h>
#include <vrpath.h>
#include "shell.h"
#include "winp.h"
#pragma code-name ("OVERLAY17")
#pragma rodata-name ("OVL17RO")
#pragma bss-name ("OVL17BSS")

void boxPlain(void);
unsigned char __fastcall__ dlg(const void *b);

#define SCRIPT  0x1F00          /* in bank RB: $BF00 (RB_IMAGE's core ends at $BA00) */
#define MAXPRG  (0x9F00 - 0x0801 + 2)   /* $0801 up to $9EFF, with its 2-byte address */

/* The kernel reads a dialog box, its texts and a path with another bank
   mapped at $A000 (a font's, its own), so all of them are copied below
   $A000 first: the box to buf, its texts to buf and msg */
struct boxr {                   /* three lines (r5, r6, r7), OK, CANCEL */
    unsigned char pos;
    unsigned char t1, x1, y1, reg1;
    unsigned char t2, x2, y2, reg2;
    unsigned char t3, x3, y3, reg3;
    unsigned char usr; void (*fn)(void);
    unsigned char ok, okx, oky;
    unsigned char cn, cnx, cny;
    unsigned char end;
};
static const struct boxr runBox = {
    DEF_DB_POS | 1,
    DBVARSTR, TXT_LN_X, TXT_LN_1_Y, 0x0C,
    DBVARSTR, TXT_LN_X, TXT_LN_2_Y, 0x0E,
    DBVARSTR, TXT_LN_X, TXT_LN_3_Y, 0x10,
    DB_USR_ROUT, boxPlain,
    OK, DBI_X_0, DBI_Y_2,
    CANCEL, DBI_X_2, DBI_Y_2,
    0
};
#define L2      64              /* in buf: the box's second and third lines */
#define L3      112
static const char tGoes[] = "BASIC runs it, and Veranda";     /* (28 characters at most a line) */
static const char tBack[] = "comes back when it ends.";
static const char tLost[] = "Programs put aside are lost;";
static const char tAfter[] = "Veranda comes back after it.";
static const char tOnly[] = "Only GEOS applications open.";
static const char tBig[] = "It is too big to run beside Veranda.";
static const char tNotAt[] = "BASIC cannot RUN this: it loads elsewhere.";
static const char tSelf[] = "Veranda is running already.";
static const char tCd[] = "DOS\"CD:";
static const char tLoad[] = "\"\x0dLOAD\"";
static const char tRun[] = "\",8\x0dRUN\x0d";
static const char tBoot[] = "\"\x0dLOAD\"RBOOT\",8\x0dRUN\x0d";
static const char tExec[] = "EXEC$BF00,";
static unsigned char rb;

static void warnT(const char *t)
{
    strcpy(msg, t);
    shell_warn(msg);
}

/* (main.c's openDoc) E, a plain file of window w: 0 if its name ends in
   an extension other than ".PRG"; else 1: it was run, or the user was
   told why not (no extension: only GEOS applications open, main.c's
   message before V197) */
unsigned char prg_run(unsigned char w)
{
    struct win *p = &wins[w];
    unsigned char h;
    const char *e = strrchr(E.name, '.');

    if (!e || !e[1] || strlen(e + 1) > 4) {     /* (main.c's extOf fails) */
        warnT(tOnly);
        return 1;
    }
    if ((e[1] | 32) != 'p' || (e[2] | 32) != 'r' || (e[3] | 32) != 'g' || e[4])
        return 0;
    if (!strcmp(E.name, "VERANDA.PRG") && vr_insys(p->path)) {
        warnT(tSelf);
        return 1;
    }
    if (E.size > MAXPRG) {
        warnT(tBig);
        return 1;
    }
    ChDir(p->path);
    h = FOpen(E.name, 'r');
    buf[0] = 0;
    if (h >= 2) {
        FRead(h, buf, 2);
        FClose(h);
    }
    if (buf[0] != 0x01 || buf[1] != 0x08) {
        warnT(tNotAt);
        return 1;
    }
    TaskCtl(TASK_INFO, 0xFF, buf);
    h = buf[TS_COUNT];
    strcpy((char *)buf + L2, h ? tLost : tGoes);
    strcpy((char *)buf + L3, h ? tAfter : tBack);
    memcpy(buf, &runBox, sizeof runBox);
    strcpy(msg, "Run ");
    strcat(msg, E.name);
    strcat(msg, "?");
    if (testing)
        LogText(msg);
    r5 = (unsigned int)msg;
    r6 = (unsigned int)(buf + L2);
    r7 = (unsigned int)(buf + L3);
    if (dlg(buf) != OK)
        return 1;
    /* the script: BASIC's text (crunched by BASIC as it is typed) */
    strcpy(tmp, VR_SYSDIR);
    if (ChDir(tmp))
        strcpy(tmp, "/");               /* (no /VERANDA: RBOOT in the top folder) */
    strcpy((char *)buf, tCd);
    strcat((char *)buf, p->path);
    strcat((char *)buf, tLoad);
    strcat((char *)buf, E.name);
    strcat((char *)buf, tRun);
    strcat((char *)buf, tCd);
    strcat((char *)buf, tmp);
    strcat((char *)buf, tBoot);
    if (testing)
        LogText((char *)buf);
    __asm__("sec");
    __asm__("jsr $FF99");       /* MEMTOP: a = the RAM banks BASIC may use */
    __asm__("sta %v", rb);
    --rb;
    /* the folder to come back to: window 0 shows the program's */
    if (w) {
        strcpy(wins[0].path, p->path);
        wins[0].open = 1;
    }
    shell_keep();
    bput(rb, SCRIPT, buf, strlen((char *)buf) + 1);
    strcpy(msg, tExec);
    num(rb, msg + sizeof tExec - 1);
    strcpy(tmp, "EXEC");
    num((unsigned int)msg, tmp + 4);
    r1 = TOBASIC_KEEP;
    ToBASIC(tmp);
    return 1;
}

/* (V198) a program's request that the desktop start another program
   while it waits aside: /VERANDA/.SYSTEM/START.REQ, one line, the
   program's folder and GEOS name ("/VERANDA/APPS/Veranda Update"),
   deleted before anything is started (so a program that cannot start is
   not tried again at every start of the desktop). Veranda Write's Tools >
   Get dictionaries writes one (and Veranda Update's own request,
   UPDATE.REQ), then puts itself aside. 1: the folder in str, the name in
   tmp; 0: none */
static const char tReq[] = "START.REQ";
static unsigned char req(void);
unsigned char prg_req(unsigned char u)
{
    (void)u;
    u = req();
    ChDir((char *)curDirName);          /* (the shell works in its window's folder) */
    return u;
}

static unsigned char req(void)
{
    unsigned char h, n;
    char *s;
    strcpy(msg, VR_DATADIR);
    if (ChDir(msg))
        return 0;
    strcpy(msg, tReq);
    h = FOpen(msg, 'r');
    if (h < 2 || h > 9)
        return 0;
    n = 0;
    if (dosStatus < 20)
        n = FRead(h, str, sizeof str - 1);
    FClose(h);
    if (!n)
        return 0;
    FDelete(msg);
    str[n] = 0;
    for (s = str; *s && *s != '\r' && *s != '\n'; ++s)
        ;
    *s = 0;
    s = strrchr(str, '/');
    if (str[0] != '/' || !s || !s[1])
        return 0;
    strcpy(tmp, s + 1);
    if (s == str)
        ++s;                            /* (a program in the top folder) */
    *s = 0;
    if (testing) {
        strcpy(msg, "SHELL START.REQ ");
        strcat(msg, str);
        LogText(msg);
    }
    return 1;
}

/* (gates; main.c's until V198, for main RAM) each window the shell kept,
   logged at its start */
void prg_log(void)
{
    unsigned char w;
    for (w = 0; w < NWIN; ++w)
        if (wins[w].open) {
            strcpy(msg, "SHELL WINDOW 0 KEPT AT ");
            msg[13] += w;
            num(wins[w].x * 8, msg + 23);
            strcat(msg, " ");
            num(wins[w].y, msg + strlen(msg));
            strcat(msg, " VIEW ");
            num(wins[w].view, msg + strlen(msg));
            strcat(msg, " ");
            strcat(msg, wins[w].path);
            LogText(msg);
        }
}

/* (V207) the colour icon of a window's plain file by its extension (here
   for overlay 12's room; look3.c's cwr): kind 0: E's (window w's entry),
   by its name; else that kind. Its library key (tools/mkicons3.py) into
   k3buf; the kind: 1 ".cwr" (Veranda Write's documents, V156), 2 ".prg"
   (an X16 program, V197), 3 music and sound (".mid", ".midi", ".zsm",
   ".zcm", ".wav", ".mod", ".sid"), 4 video (".spv"); 0 none (not a
   window's plain file, another extension) */
extern char k3buf[13];
static const char extKey[4][13] = { "Write Image ", "*Prg        ", "*Music      ", "*Video      " };
static const char exts[] = "cwrprgmidzsmzcmwavmodsidspv";
static const unsigned char extK[] = { 1, 2, 3, 3, 3, 3, 3, 3, 4 };

unsigned char ic3_ext(unsigned char w, unsigned char kind)
{
    char x[5];
    const char *e;
    unsigned char i, n;
    if (!kind) {
        if (w >= 2 || E.geos || (e = strrchr(E.name, '.')) == 0)
            return 0;
        n = strlen(++e);
        if (n < 3 || n > 4)
            return 0;
        for (i = 0; i <= n; ++i)
            x[i] = e[i] | (e[i] >= 'A' && e[i] <= 'Z' ? 32 : 0);
        if (n == 4)
            kind = memcmp(x, "midi", 4) ? 0 : 3;
        else
            for (i = 0; i < sizeof extK; ++i)
                if (!memcmp(x, exts + 3 * i, 3)) {
                    kind = extK[i];
                    break;
                }
        if (!kind)
            return 0;
    }
    memcpy(k3buf, extKey[kind - 1], 12);
    return kind;
}

/* (V207) key k in the shell's library of colour icons (look3.c's inLib,
   here for overlay 12's room): records 13 and 14 (banks bLook3 + 1 and
   + 2), then the icons past them after this overlay's code (OVF_BIG,
   tools/mkicons3.py ovf); its icon's offset in its bank (0: none), the
   bank in k3buf[12] */
#define OVF_BIG 0x1600
#define IC_LEN  658

unsigned int ic3_lib(const char *k)
{
    unsigned char i, c, n;
    unsigned int o;
    for (n = 0; n < 3; ++n) {
        o = 0;
        k3buf[12] = bLook3 + 1 + n;
        if (n == 2) {
            k3buf[12] = bPrg;
            o = OVF_BIG;
        }
        bget(k3buf[12], o, buf, 1 + 12 * 12);
        c = buf[0] > 12 ? 0 : buf[0];
        for (i = 0; i < c; ++i)
            if (!memcmp(buf + 1 + 12 * i, k, 12))
                return o + 160 + i * IC_LEN;
    }
    return 0;
}
