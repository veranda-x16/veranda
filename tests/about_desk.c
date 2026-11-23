/* gate about (DECISIONS V119): a test desktop (SHELL.cvt). With one
   program aside (About this X16's test build) it starts AbHelper
   (tests/about_helper.c), which puts itself aside at once; with two it
   brings back the one that is not AbHelper (TaskCtl TASK_RESUME: About
   this X16, started as AUTOSTART), so that About lists
   a program aside other than itself. MIT licence (see LICENSE). */
#include <veranda.h>
#include <string.h>

static unsigned char rec[TASK_REC];
static char helper[] = "AbHelper";

int main(void)
{
    unsigned char i, n = 0, about = 0xFF;
    LogText("ABDESK");
    for (i = 0; i < TASK_MAX; ++i) {
        TaskCtl(TASK_INFO, i, rec);
        if (rec[TR_STATE] != TASK_ASIDE)
            continue;
        ++n;
        if (memcmp(rec + TR_NAME, "AbHelper", 8))
            about = i;
    }
    if (n == 1) {
        LogText("ABDESK HELPER");
        ChDir("/");
        GetFile(helper, 0, 0, 0, 0);
        LogText("ABDESK NO HELPER");
    } else if (about != 0xFF) {
        LogText("ABDESK RESUME");
        TaskCtl(TASK_RESUME, about, rec);
        LogText("ABDESK NO RESUME");
    }
    *(volatile unsigned char *)0x9FB4 = 1;
    asm("jmp $FFFF");
    return 0;
}
