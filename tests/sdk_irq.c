/* gate sdk: C callbacks. tick() runs in the interrupt (vr_set_irq: its own
   C stack, cc65's zero page kept); poll() is appMain, called by the main
   loop, which uses the C stack itself (a local array, a division) while the
   interrupt keeps coming. After 60 ticks: "SDK IRQ OK" if poll's work was
   never disturbed. */
#include <veranda.h>
#include <vr.h>

static volatile unsigned int ticks;
static unsigned char bad;

static void tick(void)
{
    unsigned char a[4];
    a[0] = 1; a[3] = 2;
    ticks += a[3] - a[0];
}

static void poll(void)
{
    unsigned char i, v[16];
    unsigned int s = 0;
    for (i = 0; i < 16; ++i)
        v[i] = i * 3;
    for (i = 0; i < 16; ++i)
        s += v[i] / 3;
    if (s != 120)
        bad = 1;
    if (ticks >= 60) {
        appMain = 0;
        vr_set_irq(0);
        LogText(bad ? "SDK IRQ BAD" : "SDK IRQ OK");
    }
}

int main(void)
{
    vr_set_irq(tick);
    appMain = VR_FN(poll);
    return 0;
}
