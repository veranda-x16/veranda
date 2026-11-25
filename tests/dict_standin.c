/* gate update, session handoff (DECISIONS V198): a stand-in for Veranda
   Write's Tools > Get dictionaries, started by the desktop (from a
   START.REQ of the gate's) as /VERANDA/APPS/Veranda Write, the name a
   program put aside is known by. It writes the two requests as Write
   does:
     /VERANDA/.SYSTEM/START.REQ   "/VERANDA/APPS/Veranda Update" (the
                                  desktop starts it: shell/prg.c prg_req)
     /VERANDA/.SYSTEM/UPDATE.REQ  "dict", "back Veranda Write" (Veranda
                                  Update checks the dictionaries' list at
                                  once; its Quit brings this back)
   and puts itself aside (TaskCtl TASK_ASIDE). The real desktop starts,
   reads START.REQ and starts Veranda Update (its test build: UPDATE.TST
   says what it does, then Quit). When it is back, it logs "STANDIN BACK"
   and stops the emulator.
   MIT licence (see LICENSE). */
#include <veranda.h>
#include <string.h>

static unsigned char st;
static char nm[16], txt[64];

static void __fastcall__ put(const char *name, const char *text)
{
    unsigned char h;
    strcpy(nm, name);
    strcpy(txt, text);
    h = FOpen(nm, 'w');
    if (h < 2 || h > 9)
        return;
    FWrite(h, txt, strlen(txt));
    FClose(h);
}

static void aside(void)
{
    st = 2;                             /* (put aside now: the next pass is after it is back) */
}

static void tick(void)
{
    if (st == 0) {
        st = 1;
        ChDir(VR_DATADIR);
        put("UPDATE.REQ", "dict\r\nback Veranda Write\r\n");
        put("START.REQ", "/VERANDA/APPS/Veranda Update\r\n");
        LogText("STANDIN ASIDE");
        asideVector = (unsigned int)aside;
        TaskCtl(TASK_ASIDE, 0, 0);
    } else if (st == 2) {
        st = 3;
        LogText("STANDIN BACK");
        *(volatile unsigned char *)0x9FB4 = 1;  /* (EMU_SAVE_ON_EXIT: dump.bin) */
        __asm__("jmp $FFFF");
    }
}

int main(void)
{
    LogText("STANDIN STARTED");
    appMain = (unsigned int)tick;
    return 0;
}
