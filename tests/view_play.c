/* gate view: the test build's hooks (apps/view built with VIEW_TEST).
   view_test_snap writes the screen as the gate reads it:
     38,400 bytes  the foreground's 480 rows of 80 bytes
      4,800 bytes  every card's paper colour (GetCardColor: 0 when the
                   colour map is hidden), 60 rows of 80
          4 bytes  palette entries 0 and 1 (the paper, the ink: $0RGB,
                   low byte first), read from VERA
   view_test_end: a VRAM dump, the emulator stops. */
#include <veranda.h>
#include <string.h>

/* (in View's test build, overlay 1, appBank: View's main RAM is full;
   only the dialog's hook, called with the dialog's bank mapped, is in
   main RAM; the scene links this file without overlays) */
#ifdef VIEW_TEST
#pragma code-name ("OVERLAY1")
#endif

static unsigned char wrow[80];

void view_test_snap(const char *name)
{
    unsigned char h, keep = dispBufferOn, x, y, i;
    unsigned int r;
    h = FOpen((void *)name, 'w');
    if (h < 2) {
        LogText("VIEW SNAP FAILED");
        return;
    }
    dispBufferOn = ST_WR_FORE;
    for (r = 0; r < 480; ++r) {
        ReadRow(wrow, 0, 80, r);
        FWrite(h, wrow, 80);
    }
    for (y = 0; y < 60; ++y) {
        for (x = 0; x < 80; ++x)
            wrow[x] = GetCardColor(x, y);
        FWrite(h, wrow, 80);
    }
    asm("sei");
    *(volatile unsigned char *)0x9F25 &= 0xFE;      /* ADDRSEL 0 */
    *(volatile unsigned char *)0x9F20 = 0x00;       /* $1FA00, step 1 */
    *(volatile unsigned char *)0x9F21 = 0xFA;
    *(volatile unsigned char *)0x9F22 = 0x11;
    for (i = 0; i < 4; ++i)
        wrow[i] = *(volatile unsigned char *)0x9F23;
    asm("cli");
    FWrite(h, wrow, 4);
    FClose(h);
    dispBufferOn = keep;
}

void view_test_end(void)
{
    *(volatile unsigned char *)0x9FB4 = 1;  /* EMU_SAVE_ON_EXIT: dump.bin */
    asm("jmp $FFFF");
}

/* view_test_keys (DECISIONS V82): keys for the Open dialog (vrchoose.h),
   typed one at a time into the ROM's key queue from its main loop's hook
   (vr_file_hook), every 30 passes once it has listed its folder; key 1
   ends the run there (a VRAM dump: the dialog's screenshot) */
#include <vrchoose.h>
static const char *tkeys;
static unsigned char tpass;

#pragma code-name ("CODE")
static void tkey(void)
{
    static unsigned char k;
    if (++tpass < 30 || !tkeys || !*tkeys)
        return;
    tpass = 0;
    k = *tkeys++;
    if (k == 1) {
        *(volatile unsigned char *)0x9FB4 = 1;      /* (as view_test_end: here, not in overlay 1) */
        asm("jmp $FFFF");
    }
    __A__ = k;
    asm("jsr $FEC3");               /* kbdbuf_put */
}

#ifdef VIEW_TEST
#pragma code-name ("OVERLAY1")
#endif
void view_test_keys(const char *keys)
{
    tkeys = keys;
    tpass = 0;
    vr_file_hook = tkey;
}
