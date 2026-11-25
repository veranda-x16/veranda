/* Veranda Update: the Veranda installation on the SD card brought up to
   date online, from GitHub releases or from a PC on the home network
   (C, MIT; DECISIONS V130).

   One Look 2 window (sysui, as Disk Tools and About this X16): Check,
   Update, Undo last update, Source... in the toolbar and the menus; the
   source, the installed and the available builds, what's new, the files
   that changed, the progress.

   Sources (UPDATE.CFG in /VERANDA/.SYSTEM, lines key=value):
     source=github   repo=owner/repo (veranda-x16/veranda; the old
                     sandlbn/veranda-x16 is read as it): the latest release's UPDATE.LST,
                     https://github.com/<repo>/releases/latest/download/
                     UPDATE.LST, then each file from its tag's assets; the
                     modem makes the TLS connection (ATCS) and GitHub's
                     302 to its asset host is followed
     source=pc       pc=host:port: PC/update_server.py on a PC of the home
                     network, plain HTTP (http://host:port/UPDATE.LST)
     github=host     (GitHub's host, github.com; a gate's stand-in)
   The work is job.c's (Check, Update, Undo), the network http.c's, the
   list man.c's, the CRC-32 crc.s's; this file has the settings, the
   menus, the keys and the switcher.

   Memory: main RAM (this file, http.c, crc.s, vrnet, sysui), overlay 1 as
   appBank (job.c), overlay 2 (man.c, ui.c), overlay 3 (swap.c); RAM banks:
   the overlays' 3, vrnet's 2 while the modem is on, 4 of the program's
   (the list's two, a text's, the CRC's table): 9 at most of the 512 KB
   machine's 44. Alt+Tab puts it aside at any time but
   while the files are swapped (one pass of the main loop: the switcher
   acts only between passes): a file being fetched is closed, and fetched
   again from its start when it is back.

   MIT licence (see LICENSE). */
#include <veranda.h>
#include <vr.h>
#include <string.h>
#include <theme.h>
#include <vrnet.h>
#include <vrser.h>
#include "up.h"


struct cfg C;
unsigned char xmode;
char back[18];
char line[128];
unsigned char iobuf[IOBUF];
unsigned char net_on;

/*---------------------------------------------------------------- overlays */
unsigned char bOv2, bOv3;

char *__fastcall__ K(const char *s)
{
    static char kb[2][72];
    static unsigned char ki;
    char *d = kb[ki ^= 1];
    strncpy(d, s, sizeof kb[0] - 1);
    d[sizeof kb[0] - 1] = 0;
    return d;
}

#define OVX(b, call) { unsigned char k_ = RAMBANK; RAMBANK = b; call; RAMBANK = k_; }
void ui_all(void) OVX(bOv2, ui_all_o())
void ui_head(void) OVX(bOv2, ui_head_o())
void ui_list(void) OVX(bOv2, ui_list_o())
void __fastcall__ ui_progress(const char *name) OVX(bOv2, ui_progress_o(name))
void ui_source(void) OVX(bOv2, ui_source_o())
void man_installed(void) OVX(bOv2, man_installed_o())
const char *__fastcall__ man_load(const char *dir, const char *name)
{
    const char *r;
    OVX(bOv2, r = man_load_o(dir, name));
    return r;
}
unsigned char job_resume_swap(void)
{
    unsigned char r;
    OVX(bOv3, r = job_resume_swap_o());
    return r;
}
unsigned char undo_ready(void)
{
    unsigned char r;
    OVX(bOv3, r = undo_ready_o());
    return r;
}
void job_undo(void) OVX(bOv3, job_undo_o())
unsigned char req_load(void)
{
    unsigned char r;
    OVX(bOv3, r = req_load_o());
    return r;
}
void swap_go(void) OVX(bOv3, swap_go_o())
unsigned char __fastcall__ exists(const char *p)
{
    unsigned char r;
    OVX(bOv3, r = exists_o(p));
    return r;
}
void __fastcall__ del(const char *p) OVX(bOv3, del_o(p))
void __fastcall__ mkdirs(const char *p) OVX(bOv3, mkdirs_o(p))
unsigned char __fastcall__ fcheck(const char *p, unsigned long size, unsigned long crc)
{
    unsigned char r;
    OVX(bOv3, r = fcheck_o(p, size, crc));
    return r;
}

/* the list's entries in their RAM banks */
void __fastcall__ ent_get(unsigned char i)
{
    BankCopy(BANKMEM + (unsigned int)(i % ENT_PER_BANK) * ENT_SIZE, &E, ENT_SIZE, tbank + i / ENT_PER_BANK, 0);
}

void __fastcall__ ent_put(unsigned char i)
{
    BankCopy(&E, BANKMEM + (unsigned int)(i % ENT_PER_BANK) * ENT_SIZE, ENT_SIZE, 0, tbank + i / ENT_PER_BANK);
}

/*---------------------------------------------------------------- the settings */
/* (ui.c's, overlay 2, since V198: main RAM) */
static void cfg_load(void) OVX(bOv2, cfg_load_o())
void cfg_save(void) OVX(bOv2, cfg_save_o())

/*---------------------------------------------------------------- boxes, the log */
#ifdef UP_TEST
unsigned char t_no;                     /* bit 0: the next box's answer is Cancel, bit 1 the one after ... */
#endif

unsigned char __fastcall__ up_confirm(const char *a, const char *b)
{
#ifdef UP_TEST
    unsigned char r = !(t_no & 1);      /* (bit n: the box n after this one) */
    t_no >>= 1;
    up_log("BOX ", a);
    return r;
#else
    return ui_confirm(a, b);
#endif
}

void __fastcall__ up_message(const char *a, const char *b)
{
#ifdef UP_TEST
    up_log("BOX ", a);
    up_log("BOX2 ", b);
#else
    ui_message(a, b);
#endif
}

void __fastcall__ up_log(const char *a, const char *b)
{
#ifdef UP_TEST
    static char t[150];
    strcpy(t, a);
    strncat(t, b, sizeof t - 1 - strlen(t));
    LogText(t);
#else
    (void)a;
    (void)b;
#endif
}

void __fastcall__ say(const char *s)
{
    static char t[100];                 /* (s may be an overlay's: copied below $A000) */
    strncpy(t, s, sizeof t - 1);
    ui_status(t, "Veranda Update");
}

#ifdef UP_TEST
unsigned char t_restarted;
#endif

/* Restart to finish: Veranda quits to BASIC (all of it freed) and BASIC
   types BOOT in /VERANDA, which starts the new AUTOBOOT.X16 */
void up_restart(void)
{
#ifdef UP_TEST
    up_log("UP RESTART", "");
    t_restarted = 1;
#else
    ui_message("Restart to finish:", "Veranda starts again with its new system files.");
    net_stop();
    r1 = 0;
    ToBASIC("BOOT");
#endif
}

/*---------------------------------------------------------------- the network */
static unsigned int net_aside;

static void aside(void)
{
    if (net_aside)
        ((void (*)(void))net_aside)();
    job_aside();
#ifdef UP_TEST
    LogText("UP ASIDE");
#endif
}

void net_restart(void)
{
    net_stop();
    net_on = net_start(0, 576) == NET_OK;
    net_aside = net_on ? asideVector : 0;
    asideVector = VR_FN(aside);
}

/*---------------------------------------------------------------- menus */
static void m_about(void), m_quit(void), m_check(void), m_update(void), m_undo(void), m_dict(void), m_source(void);

struct item { const char *text; unsigned char type; void *p; };
struct menu1 { unsigned char top, bottom; unsigned int left, right; unsigned char flags; struct item i[1]; };
struct menu2 { unsigned char top, bottom; unsigned int left, right; unsigned char flags; struct item i[2]; };
struct menu3 { unsigned char top, bottom; unsigned int left, right; unsigned char flags; struct item i[3]; };
struct menu4 { unsigned char top, bottom; unsigned int left, right; unsigned char flags; struct item i[4]; };

#define IH 14
static struct menu2 mapp = { 14, 14 + 2 * IH, 0, 0, VERTICAL | 2, {
    { "About Veranda Update...", MENU_ACTION, m_about }, { "\x1f" "Quit\tCtrl Q", MENU_ACTION, m_quit } } };
static struct menu4 mupd = { 14, 14 + 4 * IH, 0, 0, VERTICAL | 4, {
    { "Check\tC", MENU_ACTION, m_check }, { "Update\tU", MENU_ACTION, m_update },
    { "\x1f" "Undo last update", MENU_ACTION, m_undo },
    { "\x1f" "Dictionaries for Write\tD", MENU_ACTION, m_dict } } };
static struct menu1 mset = { 14, 14 + IH, 0, 0, VERTICAL | 1, {
    { "Source...", MENU_ACTION, m_source } } };
static struct menu3 mbar = { 0, 14, 0, 0, HORIZONTAL | UN_CONSTRAINED | 3, {
    { "Veranda Update", SUB_MENU, &mapp }, { "Update", SUB_MENU, &mupd }, { "Settings", SUB_MENU, &mset } } };
static const char *const barnames[3] = { "Veranda Update", "Update", "Settings" };
static const char *const longest[3] = { "About Veranda Update...", "Dictionaries for Write\tD", "Source..." };
static unsigned int *const lefts[3] = { &mapp.left, &mupd.left, &mset.left };
static unsigned int *const rights[3] = { &mapp.right, &mupd.right, &mset.right };
unsigned int barx[3], barl[3];

static void m_about(void)
{
    GotoFirstMenu();
    ui_message("Veranda Update 1.0, MIT licence.", "Veranda brought up to date from GitHub or your PC.");
}

void up_quit(void)
{
    if (job)
        job_stop("");
    net_stop();
    if (tbank)
        BankFree(tbank);
    /* (V198) started for a program put aside (UPDATE.REQ's back): it comes
       back, else the desktop */
    if (back[0])
        OVX(bOv3, back_o())
    EnterDeskTop();
}

static void m_quit(void) { GotoFirstMenu(); up_quit(); }
static void m_check(void) { GotoFirstMenu(); job_check(); }
static void m_update(void) { GotoFirstMenu(); job_update(); }
static void m_undo(void) { GotoFirstMenu(); job_undo(); }
static void m_dict(void) { GotoFirstMenu(); job_dict(); }
static void m_source(void) { GotoFirstMenu(); ui_source(); }

static const struct btn tools[] = {
    { 1, 9, "Check" }, { 11, 10, "Update" }, { 22, 19, "Undo last update" }, { 42, 12, "Source..." },
    { 55, 15, "Dictionaries" }
};
#define NTOOLS 5

static void press(void)
{
    if (mouseData & 0x80)
        return;
    if (mouseYPosW >= TOOL_TOP && mouseYPosW < BODY_TOP)
        switch (ui_tool_at(tools, NTOOLS, mouseXPos)) {
        case 0: job_check(); break;
        case 1: job_update(); break;
        case 2: job_undo(); break;
        case 3: ui_source(); break;
        case 4: job_dict(); break;
        }
}

static void key(void)
{
    unsigned char k = keyData;
    if (k == KEY_ESC) {
        if (job)
            job_stop("Stopped: nothing on the card was changed.");
    } else if (k == 'c' || k == 'C')
        job_check();
    else if (k == 'u' || k == 'U')
        job_update();
    else if (k == 'd' || k == 'D')
        job_dict();
    else if (k == 'q' - 96 && (keyDataMods & (2 | KEYM_ARROW)) == 2)
        up_quit();                      /* Ctrl Q (KEY_DOWN is 17 too) */
}

static void tick(void)
{
    job_tick();
#ifdef UP_TEST
    up_test_tick();
#endif
}

int main(void)
{
    LoadOverlay(1, 0);                  /* (overlay 1: job.c; mapped for good, as appBank) */
    appBank = r1L;
    LoadOverlay(2, 0);                  /* (overlay 2: man.c, ui.c) */
    bOv2 = r1L;
    LoadOverlay(3, 0);                  /* (overlay 3: swap.c) */
    bOv3 = r1L;
    RAMBANK = appBank;
    dispBufferOn = ST_WR_FORE;          /* (the foreground only: menus and boxes save what they cover) */
    SetPattern(0);
    WRectangle(0, 0, 639, 15);
    theme_load();
    theme_palette();
    ui_window("Veranda Update");
    theme_menus();
    ui_menus(barnames, 3, (unsigned int **)lefts, (unsigned int **)rights, longest, &mbar.right, barx, barl);
    DoMenu((void *)&mbar, 0);
    ui_toolbar(tools, NTOOLS, 0xFF);
    tbank = BankAlloc(4);
    crcbank = tbank + 3;
    if (tbank)
        crc_init();
    cfg_load();
    man_installed();
    ui_all();
    if (!tbank) {
        say("Not enough memory (4 RAM banks): quit a program put aside.");
    } else if (!job_resume_swap()) {
        if (req_load())                 /* (V198: a program asked for the dictionaries) */
            job_dict();
        else
            say(C.src == SRC_PC ? "Check asks your PC what changed." : "Check asks GitHub what changed.");
    }
    otherPressVec = VR_FN(press);
    keyVector = VR_FN(key);
    asideVector = VR_FN(aside);
    appMain = VR_FN(tick);
#ifdef UP_TEST
    up_test_start();
#endif
    return 0;
}
