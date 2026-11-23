/* Veranda Edit: the start, the dialog boxes, the banks of code.

   The program is larger than $0801-$87FF, so it is in three parts
   (sdk/cfg/app-c-ovl.cfg, overlays = banked): main RAM holds the text's
   code (buf.s, text.c, ops.c, undo.c), this file and every variable;
   overlay 1 (main.c, view.c: keys, the pointer, drawing) is mapped at
   $A000 for good, as appBank, so the kernel's calls to the program (its
   vectors, menus, dialog boxes) find it there; overlay 2 (file.c, find.c,
   scrap.c: files, find and replace, the clipboard) is mapped by call2()
   for one command at a time (and is appBank meanwhile, for its dialog
   boxes); overlay 3 is the SDK's Open and Save dialog (vrchoose.c,
   DECISIONS V79), mapped by file_dlg() while it is open (the kernel
   calls its routines through vr_tramp). (V148) The SDK's alert (vralert.c)
   is in overlay 1 too, and menus.c's layout() in overlay 2 (call2). The overlays hold code only: their strings and tables are in
   main RAM (below $A000, where the kernel reads them). Code in overlay 2
   calls main RAM only; buf.s and the SDK's file chooser map other banks
   and put the caller's back.

   MIT licence (see LICENSE). */
#include <string.h>
#include <vrchoose.h>
#include <vrpath.h>
#include <vralert.h>
#include "edit.h"

unsigned char edit_idle, need_fix;
unsigned char bank1, bank2, bank3;
char status_msg[48];
unsigned char iobuf[TK_IOBUF];

/*---------------------------------------------------------------
  dialog boxes (their tables and texts in main RAM)
 ---------------------------------------------------------------*/
struct askdlg {
    unsigned char pos;
    unsigned char t1, x1, y1, reg1;
    unsigned char t2, x2, y2, reg2, max;
    unsigned char ok, okx, oky;
    unsigned char cn, cnx, cny;
    unsigned char end;
};
static struct askdlg askbox = {
    DEF_DB_POS | 1,
    DBVARSTR, TXT_LN_X, TXT_LN_2_Y, 0x0E,
    DBGETSTRING, TXT_LN_X, TXT_LN_3_Y, 0x0C, 20,
    OK, DBI_X_0, DBI_Y_2,
    CANCEL, DBI_X_2, DBI_Y_2,
    0
};
/* (V148, Sunroom) alerts: vr_alert (vralert.h) with Veranda Edit's icon
   (alerticon.c, made from icon.txt); textkit's two texts (one sentence in
   two halves) make the headline; its two questions get an explanation */
static char msga[88];

/* vr_alert, in overlay 1 (the SDK's source compiled there: main RAM had
   no room for it; its BSS is here), mapped while it is open (textkit's
   boxes come from overlay 2; the kernel calls its routines through
   vr_tramp, which maps overlay 1 again) */
unsigned char __fastcall__ alert(unsigned char kind, const char *head, const char *text)
{
    unsigned char r, b = *(volatile unsigned char *)0;
    MAPBANK(bank1);
    r = vr_alert(kind, head, text);
    MAPBANK(b);
    return r;
}

static const char *texts(const char *a, const char *b)
{
    strncpy(msga, a, 40);
    msga[40] = 0;
    if (b[0]) {
        strcat(msga, " ");
        strncat(msga, b, 46);
    }
    return msga;
}

void message(const char *a, const char *b)
{
    Beep();
    alert(VA_OK, texts(a, b), 0);
    need_fix = 1;
}

/* (textkit's only question of two answers: Save as onto a file there) */
unsigned char yesno(const char *a, const char *b)
{
    unsigned char r;
    texts(a, b);
    strcat(msga, "?");
    r = alert(VA_YESNO, msga, "A file of that name is in this folder: saving replaces it.");
    need_fix = 1;
    return r == YES;
}

/* YES, NO or CANCEL (textkit's: the changes, before another text) */
unsigned char yesnocancel(const char *a, const char *b)
{
    unsigned char r = alert(VA_YNC, texts(a, b), "If you don't save them, the changes are lost.");
    need_fix = 1;
    return r;
}

/* buf (in main RAM) edited; 1: OK */
unsigned char ask(const char *prompt, char *buf, unsigned char max)
{
    unsigned char r;
    askbox.max = max;
    r6 = (unsigned int)prompt;          /* (DBVARSTR 0x0E: r6) */
    r5 = (unsigned int)buf;
    r = DoDlgBox((void *)&askbox);
    need_fix = 1;
    return r == OK || r == DBGETSTRING;
}

void menus_off(void)
{
    GotoFirstMenu();
    need_fix = 1;
}

void view_status_msg(const char *s)
{
    strncpy(status_msg, s, sizeof status_msg - 1);
    bars_dirty |= B_STATUS;
}

char scrap_path[40];            /* the scrap library's path (it is in overlay 2) */

void sys_dir(void)
{
    vr_cd(VR_APPS);                     /* (vrpath.h: DECISIONS V71) */
}

void doc_dir(void)
{
    ChDir((char *)curDirName);
}

/* f, in overlay 2 */
void __fastcall__ call2(void (*f)(void))
{
    appBank = bank2;
    MAPBANK(bank2);
    f();
    appBank = bank1;
    MAPBANK(bank1);
}

/* the Open and Save dialog (vrchoose.h), in overlay 3: from overlay 2 */
static const char types[] = TK_TYPES;

unsigned char __fastcall__ file_dlg(unsigned char mode, const char *title, char *name)
{
    unsigned char r, b = *(volatile unsigned char *)0;
    vr_file_types = types;
    MAPBANK(bank3);
    r = vr_file(mode, title, name);
    MAPBANK(b);
    return r;
}

static void idle(void)
{
    edit_idle = 1;
}

int main(void)
{
    unsigned char opts = r0L;
    LoadOverlay(1, 0);
    bank1 = r1L;
    LoadOverlay(2, 0);
    bank2 = r1L;
    LoadOverlay(3, 0);
    bank3 = r1L;
    appBank = bank1;
    MAPBANK(bank1);
    vr_file_hook = idle;
    a_main(opts);
    return 0;
}
