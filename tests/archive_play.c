/* gate archive: the test build's hooks (apps/archive built with
   ARCHIVE_TEST and tests/sdk_play.s). archive_test_dialog types into the
   Open dialog (vrchoose.h; DECISIONS V82) from its main loop's hook:
   Return (into the folder D64, the root's first), 't' (the long-named
   image, the first name with a t after ".."), Return. With ARCHIVE_SHOT
   the run ends in the dialog instead of the last Return (its
   screenshot). From there the application's own test sequence runs
   (archive.c, archive_test_listed) and ends the run with
   archive_test_end: a VRAM dump, the emulator stops. With ARCHIVE_DOC
   (the shell starts Archive with an image) the dialog is not shown. */
#include <veranda.h>
#include <string.h>
#include <vrchoose.h>

/* (no pointer script: tests/sdk_play.s's player, a fixed pointer from
   mouseSource, kept the dialog's main loop from running; the gate's
   timeout ends a hung run) */
void archive_test_start(void)
{
}

#ifdef ARCHIVE_SHOT
static const char keys[] = "\rt\1";
#else
static const char keys[] = "\rt\r";
#endif
static const char *tk;
static unsigned char tpass;

static void tkey(void)
{
    unsigned char k;
    if (++tpass < 30 || !tk || !*tk)
        return;
    tpass = 0;
    k = *tk++;
    if (k == 1) {
        *(volatile unsigned char *)0x9FB4 = 1;      /* (the screenshot: as archive_test_end) */
        asm("jmp $FFFF");
    }
    __A__ = k;
    asm("jsr $FEC3");                   /* kbdbuf_put */
}

/* the first dialog only */
void archive_test_dialog(void)
{
    static unsigned char done;
    if (done++)
        return;
    tk = keys;
    tpass = 0;
    vr_file_hook = tkey;
}

void archive_test_end(void)
{
    *(volatile unsigned char *)0x9FB4 = 1;  /* EMU_SAVE_ON_EXIT: dump.bin */
    asm("jmp $FFFF");
}

/* the emulator's cycle counter ($9FB8: a write resets it, a read of
   $9FB8 latches it, then $9FB9-$9FBB): "TIME <what> <cycles, hex>" */
void archive_test_clock_reset(void)
{
    *(volatile unsigned char *)0x9FB8 = 0;
}

void archive_test_clock_log(const char *what)
{
    static char line[48];
    static const char hex[] = "0123456789ABCDEF";
    unsigned char c[4], i, n = 5;
    c[0] = *(volatile unsigned char *)0x9FB8;
    c[1] = *(volatile unsigned char *)0x9FB9;
    c[2] = *(volatile unsigned char *)0x9FBA;
    c[3] = *(volatile unsigned char *)0x9FBB;
    memcpy(line, "TIME ", 5);
    while (*what && n < 36)
        line[n++] = *what++;
    line[n++] = ' ';
    for (i = 4; i-- > 0;) {
        line[n++] = hex[c[i] >> 4];
        line[n++] = hex[c[i] & 15];
    }
    line[n] = 0;
    LogText(line);
}
