/* gate canvas (DECISIONS V166): a test desk accessory over CanvApp. It
   logs "CANVDA L0 <L0_CONFIG> TB <L0_TILEBASE> VID <DC_VIDEO>" (the
   canvas hidden while it runs: the 1 bpp screen on layer 0), draws a
   frame and ends itself (RstrAppl) after 30 main loop passes.

   MIT licence (see LICENSE). */
#include <veranda.h>
#include <vr.h>

#define VCTRL  (*(volatile unsigned char *)0x9F25)
#define VDCV   (*(volatile unsigned char *)0x9F29)
#define L0CFG  (*(volatile unsigned char *)0x9F2D)
#define L0TB   (*(volatile unsigned char *)0x9F2F)

static unsigned char passes;
static char line[40];
static const char hx[] = "0123456789ABCDEF";

static char *hex(char *p, unsigned char v)
{
    *p++ = hx[v >> 4];
    *p++ = hx[v & 15];
    return p;
}

static void loop(void)
{
    if (++passes == 30)
        RstrAppl();
}

int main(void)
{
    char *p = line;
    VCTRL = 0;
    *p++ = 10;
    *p++ = 'C', *p++ = 'A', *p++ = 'N', *p++ = 'V', *p++ = 'D', *p++ = 'A';
    *p++ = ' ', *p++ = 'L', *p++ = '0', *p++ = ' ';
    p = hex(p, L0CFG);
    *p++ = ' ', *p++ = 'T', *p++ = 'B', *p++ = ' ';
    p = hex(p, L0TB);
    *p++ = ' ', *p++ = 'V', *p++ = 'I', *p++ = 'D', *p++ = ' ';
    p = hex(p, VDCV);
    *p = 0;
    LogText(line);
    dispBufferOn = ST_WR_FORE;
    SetPattern(0);
    Rectangle(60, 140, 60, 180);
    FrameRectangle(0xFF, 60, 140, 60, 180);
    appMain = VR_FN(loop);
    return 0;
}
