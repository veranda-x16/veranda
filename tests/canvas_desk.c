/* gate canvas (DECISIONS V166): a test desktop (SHELL.cvt) for CanvApp's
   trip through the switcher, one step each time it starts (the step in
   the desktop's path's byte 60, as tests/switch_desk.s keeps it):
     0  start CanvApp
     1  CanvApp is aside: "CANVD ASIDE <banks it holds> CARD <the task
        file's bytes, or 0>" (Roomy: on the card); bring it back
     2  it quit: "CANVD PAL <the sum of palette entries 16-255>", the end
        (the emulator's dump)
   Each start logs "CANVD <step> FREE <banks> OF <banks> MODE <graphMode>".
   (V177) Built with mode "keep" and -D DESKMODE=m, step 0 sets mode m
   itself first and logs "CANVD SET <m>": the desktop's mode must come
   back at steps 1 and 2 (after Alt + Tab, after CanvApp quit), not
   CanvApp's 320 x 240.
   -D ANYTASK: any program put aside is brought back (gate cpaint: Colour
   Paint's CP_DESK build as CanvApp.cvt).

   MIT licence (see LICENSE). */
#include <veranda.h>
#include <vr.h>
#include <string.h>

#define VCTRL  (*(volatile unsigned char *)0x9F25)
#define VADDRL (*(volatile unsigned char *)0x9F20)
#define VADDRM (*(volatile unsigned char *)0x9F21)
#define VADDRH (*(volatile unsigned char *)0x9F22)
#define VDATA0 (*(volatile unsigned char *)0x9F23)

static unsigned char desk[DESK_SIZE], sum[TASK_SUM], rec[TASK_REC];
static unsigned char buf[256];
static char line[64];
static char fname[] = "/VERANDA/.SYSTEM/TASKS/T0";

static char *num(char *p, unsigned long v)
{
    char t[10];
    unsigned char n = 0;
    do {
        t[n++] = '0' + v % 10;
        v /= 10;
    } while (v);
    while (n)
        *p++ = t[--n];
    return p;
}

static char *cat(char *p, const char *s)
{
    while (*s)
        *p++ = *s++;
    return p;
}

static void out(char *p)
{
    *p = 0;
    LogText(line);
}

int main(void)
{
    unsigned char step, i, h, slot = 0xFF;
    unsigned long size = 0;
    unsigned int n, s;
    char *p;
    SysPrefs(DESK_GET, desk);
    step = desk[60];
    ++desk[60];
    SysPrefs(DESK_SET, desk);
    TaskCtl(TASK_INFO, 0xFF, sum);
    p = cat(line, "\nCANVD ");
    p = num(p, step);
    p = cat(p, " FREE ");
    p = num(p, sum[TS_FREE]);
    p = cat(p, " OF ");
    p = num(p, sum[TS_BANKS]);
    p = cat(p, " MODE ");
    p = num(p, graphMode);
    out(p);
#ifdef DESKMODE
    if (step == 0) {
        SetVideoMode(DESKMODE);
        p = cat(line, "\nCANVD SET ");
        p = num(p, graphMode);
        out(p);
    }
#endif
    if (step == 0) {
        longNames = LONG_NAMES;
        GetFile("CanvApp", 0, 0, 0, 0);
        LogText("\nCANVD NO CANVAPP");
    } else if (step == 1) {
        for (i = 0; i < TASK_MAX; ++i) {
            memset(rec, 0, sizeof rec);
            TaskCtl(TASK_INFO, i, rec);
#ifdef ANYTASK
            if (rec[TR_STATE])              /* (gate cpaint: Colour Paint) */
#else
            if (rec[TR_STATE] && !memcmp(rec + TR_NAME, "CanvApp", 7))
#endif
                slot = i;
        }
        if (slot != 0xFF)
            TaskCtl(TASK_INFO, slot, rec);
        for (i = 0; i < TASK_MAX; ++i) {    /* (Roomy: its file on the card) */
            fname[24] = '0' + i;
            h = vr_fopen(fname, 'r');
            if (!h)
                continue;
            while ((n = FRead(h, buf, sizeof buf)) != 0)
                size += n;
            FClose(h);
        }
        p = cat(line, "\nCANVD ASIDE ");
        p = num(p, slot == 0xFF ? 0 : rec[TR_BANKS]);
        p = cat(p, " CARD ");
        p = num(p, size);
        out(p);
        if (slot != 0xFF)
            TaskCtl(TASK_RESUME, slot, 0);
        LogText("\nCANVD NO TASK");
    }
    VCTRL = 0;                              /* palette entries 16-255 */
    VADDRL = 0x20;
    VADDRM = 0xFA;
    VADDRH = 0x11;
    for (s = 0, n = 0; n < 480; ++n)
        s += VDATA0;
    p = cat(line, "\nCANVD PAL ");
    p = num(p, s);
    out(p);
    LogText("\nCANVD DONE");
    *(volatile unsigned char *)0x9FB4 = 1;  /* EMU_SAVE_ON_EXIT */
    asm("jmp $FFFF");
    return 0;
}
