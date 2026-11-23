/* tests/audio/chk.c -- gate audio's desktop (DESKTOP.cvt, V46): what the
   quit left. AFLOW off in IEN, the FIFO empty and not refilled; it then
   waits a second (no interrupt storm: the main loop runs) and says so. */
#include <veranda.h>
#include <vr.h>
#define IEN (*(volatile unsigned char *)0x9F26)
#define ACTRL (*(volatile unsigned char *)0x9F3B)
static unsigned char n;
static void later(void)
{
    if (++n == 200) LogText("AUDCHK MAINLOOP");
}
int main(void)
{
    LogText((IEN & 8) ? "AUDCHK AFLOW ON" : "AUDCHK AFLOW OFF");
    LogText((ACTRL & 0x40) ? "AUDCHK FIFO EMPTY" : "AUDCHK FIFO DATA");
    LogText(intFirstVector ? "AUDCHK VECTOR SET" : "AUDCHK VECTOR CLEAR");
    appMain = VR_FN(later);
    return 0;
}
