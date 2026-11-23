/* gate pic (DECISIONS V105): a program's full-colour picture through the
   SDK's vr_pic (vrpic.h) and mkwall.py --tiles's records.

   It logs "PICAPP <what> L0 <L0_CONFIG> TB <L0_TILEBASE> PAL <sum> VRAM
   <sum>" (PAL: palette entries 32-255's bytes added; VRAM: the tiles
   $13200-$16BFF and the map's rows 2-59 added, 16 bits) when it starts
   (START), after vr_pic_on and its records (ON: tile mode, $62 / $98, its
   rows), with a line of ink on both screens ("PICAPP" at card 2, 30).
   Built -D DUMP: ten main loop passes later the emulator's dump (the
   picture as it shows). Built -D ASIDE: it asks to be put aside (TaskCtl
   TASK_ASIDE, as Alt + Tab); back, vr_pic_back() is 1: its rows from
   record 1 again (BACK: as ON), then vr_pic_off (OFF: tile mode off, the
   rows as at START) and it quits.

   MIT licence (see LICENSE). */
#include <veranda.h>
#include <vr.h>
#include <vrpic.h>

#define VCTRL  (*(volatile unsigned char *)0x9F25)
#define VADDRL (*(volatile unsigned char *)0x9F20)
#define VADDRM (*(volatile unsigned char *)0x9F21)
#define VADDRH (*(volatile unsigned char *)0x9F22)
#define VDATA0 (*(volatile unsigned char *)0x9F23)
#define L0CFG  (*(volatile unsigned char *)0x9F2D)
#define L0TB   (*(volatile unsigned char *)0x9F2F)

static char line[64];
static unsigned char passes;
#ifdef ASIDE
static unsigned char state;
#endif
static const char hx[] = "0123456789ABCDEF";

static void vat(unsigned long a)
{
    VCTRL = 0;
    VADDRL = (unsigned char)a;
    VADDRM = (unsigned char)(a >> 8);
    VADDRH = (unsigned char)((a >> 16) & 1) | 0x10;
}

static unsigned int vsum(unsigned long a, unsigned int n)
{
    unsigned int s = 0;
    vat(a);
    while (n--)
        s += VDATA0;
    return s;
}

static char *hex(char *p, unsigned int v, unsigned char d)
{
    while (d--)
        *p++ = hx[(v >> (4 * d)) & 15];
    return p;
}

static void say(const char *what)
{
    char *p = line;
    unsigned int m = 0;
    unsigned char y;
    *p++ = 10;
    while (*what)
        *p++ = *what++;
    *p++ = ' ', *p++ = 'L', *p++ = '0', *p++ = ' ';
    p = hex(p, L0CFG, 2);
    *p++ = ' ', *p++ = 'T', *p++ = 'B', *p++ = ' ';
    p = hex(p, L0TB, 2);
    *p++ = ' ', *p++ = 'P', *p++ = 'A', *p++ = 'L', *p++ = ' ';
    p = hex(p, vsum(0x1FA40UL, 448), 4);

    for (y = 2; y < 60; ++y)
        m += vsum(VR_PIC_MAP + 256UL * y, 160);
    *p++ = ' ', *p++ = 'V', *p++ = 'R', *p++ = 'A', *p++ = 'M', *p++ = ' ';
    p = hex(p, vsum(VR_PIC_TILES + 512, 0x16C00UL - 0x13200UL) + m, 4);
    *p = 0;
    LogText(line);
}

static unsigned char rec(unsigned char n)
{
    return LoadOverlay(n, 0) == 0 ? r1L : 0;
}

static void load(void)
{
    unsigned char n;
    for (n = 1; n <= PIC_RECORDS; ++n)
        vr_vram_load(rec(n));
}

static void loop(void)
{
#ifdef ASIDE
    if (vr_pic_back()) {
        vr_vram_load(rec(1));           /* the rows */
        say("PICAPP BACK");
        state = 2;
        passes = 0;
    }
#endif
    if (++passes < 10)
        return;
    passes = 0;
#ifdef DUMP
    *(volatile unsigned char *)0x9FB4 = 1;      /* EMU_SAVE_ON_EXIT */
    asm("jmp $FFFF");
#endif
#ifdef ASIDE
    if (state == 0) {
        state = 1;
        TaskCtl(TASK_ASIDE, 0, 0);
        return;
    }
    if (state == 2) {
        vr_pic_off();
        say("PICAPP OFF");
        LogText("\nPICAPP QUIT");
        EnterDeskTop();
    }
#endif
}

static const char ink[] = "PICAPP";

int main(void)
{
    say("PICAPP START");
    vr_pic_on();
    load();
    dispBufferOn = ST_WR_FORE | ST_WR_BACK;
    UseSystemFont();
    PutString((char *)ink, 16, 240);
    say("PICAPP ON");
    appMain = VR_FN(loop);
    return 0;
}
