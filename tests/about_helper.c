/* gate about (DECISIONS V119): AbHelper, a program that puts itself aside
   at its first pass of the main loop (tests/about_desk.c starts it).
   MIT licence (see LICENSE). */
#include <veranda.h>
#include <vr.h>

static unsigned char done;

static void tick(void)
{
    if (done)
        return;
    done = 1;
    LogText("ABHELPER ASIDE");
    TaskCtl(TASK_ASIDE, 0, 0);
}

int main(void)
{
    appMain = VR_FN(tick);
    return 0;
}
