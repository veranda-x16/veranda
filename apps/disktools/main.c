/* Disk Tools: the SD card looked after, in one window (C, MIT; DECISIONS
   V119). Four tabs:

     Card       its name (Rename...: CMDR-DOS's R-H on the kernel's command
                channel), FAT32 and its partition, its size, the free space
                (FSInfo's count, and the DOS's rounded figure), the cluster
                size, the FATs; read from the card's own sectors (sysui's
                card.c and sd.s, read only). On the emulator's host folder
                only its name and that it has no FAT.
     Space use  space.c: the folders under a folder, largest first, a bar
                each; drill down and up.
     Check      check.c: the FAT and the folders, read only; it reports and
                repairs nothing.
     Clean up   clean.c: the trash emptied; leftovers of Veranda's own
                programs' cut-short saves, each kind after its own OK.

   No formatting: the X16 starts Veranda from this card, the only one.

   The long jobs (counting, looking for leftovers, the check) are steps of
   the main loop: the window stays live, Esc stops them, and nothing is
   open between two steps, so Alt+Tab puts Disk Tools aside at any time;
   a job running then stops (the card may change while it is aside) and
   says so when Disk Tools comes back.

   MIT licence (see LICENSE). */
#include <veranda.h>
#include <vr.h>
#include <string.h>
#include <theme.h>
#include "dt.h"

char line[128];
unsigned char tab, job, put_aside;

void __fastcall__ dt_log(const char *a, const char *b)
{
#ifdef DT_TEST
    static char t[140];
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
    ui_status(s, "Disk Tools");
}

void __fastcall__ progress(const char *s)
{
    ui_status(s, 0);
}

/*---------------------------------------------------------------- overlays */
unsigned char bOv2;

void __fastcall__ bget(unsigned char bank, unsigned int off, void *dst, unsigned int n)
{
    BankCopy(BANKMEM + off, dst, n, bank, (unsigned int)dst >= 0xA000 ? RAMBANK : 0);
}

void __fastcall__ bput(unsigned char bank, unsigned int off, const void *src, unsigned int n)
{
    BankCopy((void *)src, BANKMEM + off, n, (unsigned int)src >= 0xA000 ? RAMBANK : 0, bank);
}

#define OV2(call) { unsigned char k_ = RAMBANK; RAMBANK = bOv2; call; RAMBANK = k_; }
void space_draw(void) OV2(space_draw_o())
void space_start(void) OV2(space_start_o())
void space_tick(void) OV2(space_tick_o())
void space_stop(const char *why) OV2(space_stop_o(why))
void __fastcall__ space_open(unsigned char row) OV2(space_open_o(row))
void space_up(void) OV2(space_up_o())
void __fastcall__ space_key(unsigned char k) OV2(space_key_o(k))
void card_draw(void) OV2(card_draw_o())
void card_rename(void) OV2(card_rename_o())
void card_log(void) OV2(card_log_o())
void check_draw(void) OV2(check_draw_o())
void card_read(void) OV2(card_read_o())
void card_dos(void) OV2(card_dos_o())

/*---------------------------------------------------------------- the window */
static const struct btn tools[T_N] = {
    { 1, 8, "Card" }, { 10, 12, "Space use" }, { 23, 9, "Check" }, { 33, 11, "Clean up" }
};

void draw_tab(void)
{
    switch (tab) {
    case T_CARD: card_draw(); break;
    case T_SPACE: space_draw(); break;
    case T_CHECK: check_draw(); break;
    case T_CLEAN: clean_draw(); break;
    }
}

void __fastcall__ dt_tab(unsigned char t)
{
    if (t >= T_N)
        return;
    tab = t;
    ui_toolbar(tools, T_N, tab);
    if (t == T_CARD && !job)
        card_read();
    if (t == T_CLEAN && !job)
        clean_trash();
    draw_tab();
    if (t == T_SPACE && !sp_done)
        space_start();
}

static void stop(const char *why)
{
    switch (job) {
    case J_SPACE: space_stop(why); break;
    case J_SCAN: clean_stop(why); break;
    case J_CHECK: check_stop(why); break;
    }
}

/*---------------------------------------------------------------- menus */
static void m_about(void), m_quit(void), m_t0(void), m_t1(void), m_t2(void), m_t3(void), m_rename(void), m_refresh(void);

struct item { const char *text; unsigned char type; void *p; };
struct menu2 { unsigned char top, bottom; unsigned int left, right; unsigned char flags; struct item i[2]; };
struct menu3 { unsigned char top, bottom; unsigned int left, right; unsigned char flags; struct item i[3]; };
struct menu4 { unsigned char top, bottom; unsigned int left, right; unsigned char flags; struct item i[4]; };

#define IH 14
static struct menu2 mapp = { 14, 14 + 2 * IH, 0, 0, VERTICAL | 2, {
    { "About Disk Tools...", MENU_ACTION, m_about }, { "\x1f" "Quit\tCtrl Q", MENU_ACTION, m_quit } } };
static struct menu4 mtools = { 14, 14 + 4 * IH, 0, 0, VERTICAL | 4, {
    { "Card\t1", MENU_ACTION, m_t0 }, { "Space use\t2", MENU_ACTION, m_t1 },
    { "Check (read only)\t3", MENU_ACTION, m_t2 }, { "Clean up\t4", MENU_ACTION, m_t3 } } };
static struct menu2 mcard = { 14, 14 + 2 * IH, 0, 0, VERTICAL | 2, {
    { "Rename...", MENU_ACTION, m_rename }, { "\x1f" "Read again", MENU_ACTION, m_refresh } } };
static struct menu3 mbar = { 0, 14, 0, 0, HORIZONTAL | UN_CONSTRAINED | 3, {
    { "Disk Tools", SUB_MENU, &mapp }, { "Tools", SUB_MENU, &mtools }, { "Card", SUB_MENU, &mcard } } };
static const char *const barnames[3] = { "Disk Tools", "Tools", "Card" };
static const char *const longest[3] = { "About Disk Tools...", "Check (read only)\t3", "Read again" };
static unsigned int *const lefts[3] = { &mapp.left, &mtools.left, &mcard.left };
static unsigned int *const rights[3] = { &mapp.right, &mtools.right, &mcard.right };
unsigned int barx[3], barl[3];

static void m_about(void)
{
    GotoFirstMenu();
    ui_message("Disk Tools 1.0, MIT licence.", "The SD card looked after.");
}

void dt_quit(void)
{
    stop("quit");
    EnterDeskTop();
}

static void m_quit(void) { GotoFirstMenu(); dt_quit(); }
static void m_t0(void) { GotoFirstMenu(); dt_tab(T_CARD); }
static void m_t1(void) { GotoFirstMenu(); dt_tab(T_SPACE); }
static void m_t2(void) { GotoFirstMenu(); dt_tab(T_CHECK); }
static void m_t3(void) { GotoFirstMenu(); dt_tab(T_CLEAN); }
static void m_rename(void) { GotoFirstMenu(); dt_tab(T_CARD); card_rename(); }
static void m_refresh(void) { GotoFirstMenu(); if (!job) card_read(); dt_tab(T_CARD); }

/*---------------------------------------------------------------- input */
void __fastcall__ dt_hot(unsigned char h)
{
    if (h == 0xFF)
        return;
    if (h >= H_ROW0) {
        space_open(h - H_ROW0);
        return;
    }
    if (h >= H_DEL0 && h < H_DEL0 + 8) {
        clean_delete(h - H_DEL0);
        return;
    }
    switch (h) {
    case H_RENAME: card_rename(); break;
    case H_COUNT: if (!job) space_start(); break;
    case H_UP: space_up(); break;
    case H_CHECK: check_start(); break;
    case H_EMPTY: clean_empty(); break;
    case H_SCAN: clean_scan(); break;
    }
}

static void press(void)
{
    unsigned int x = mouseXPos, y = mouseYPosW;
    if (mouseData & 0x80)
        return;
    if (y >= TOOL_TOP && y < BODY_TOP)
        dt_tab(ui_tool_at(tools, T_N, x));
    else if (y >= BODY_TOP && y <= BODY_BOT)
        dt_hot(ui_hot(x, y));
}

static void key(void)
{
    unsigned char k = keyData;
    if (k == KEY_ESC) {
        if (job) {
            stop("Esc");
            return;
        }
    } else if (k >= '1' && k <= '4')
        dt_tab(k - '1');
    else if (k == KEY_TAB)
        dt_tab((tab + 1) & 3);
    else if (k == 'q' - 96 && (keyDataMods & (2 | KEYM_ARROW)) == 2)
        dt_quit();                      /* Ctrl Q (KEY_DOWN is 17 too) */
    else if (tab == T_SPACE)
        space_key(k);
}

/* the switcher: a job stops when the program comes back */
static void aside(void)
{
    if (job)
        put_aside = 1;
    dt_log("DT ASIDE", "");
}

static void tick(void)
{
    switch (job) {
    case J_SPACE: space_tick(); break;
    case J_SCAN: clean_tick(); break;
    case J_CHECK: check_tick(); break;
    }
#ifdef DT_TEST
    dt_test_tick();
#endif
}

int main(void)
{
    LoadOverlay(1, 0);                  /* (overlay 1: clean.c, vrwin; mapped for good, as appBank) */
    appBank = r1L;
    LoadOverlay(2, 0);
    bOv2 = r1L;
    RAMBANK = appBank;
    dispBufferOn = ST_WR_FORE;          /* (the foreground only: menus and boxes save what they cover) */
    SetPattern(0);
    WRectangle(0, 0, 639, 15);
    theme_load();
    theme_palette();
    ui_window("Disk Tools");
    theme_menus();
    ui_menus(barnames, 3, (unsigned int **)lefts, (unsigned int **)rights, longest, &mbar.right, barx, barl);
    DoMenu((void *)&mbar, 0);
    card_read();
    card_log();
    tab = T_CARD;
    ui_toolbar(tools, T_N, tab);
    draw_tab();
    say("1-4 or Tab: the tabs; Esc stops a count or a check.");
    otherPressVec = VR_FN(press);
    keyVector = VR_FN(key);
    asideVector = VR_FN(aside);
    appMain = VR_FN(tick);
#ifdef DT_TEST
    dt_test_start();
#endif
    return 0;
}
