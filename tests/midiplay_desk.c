/* gate midiplay (DECISIONS V205): a test desktop (SHELL.cvt) that opens a
   song as the shell opens a document: the application's folder made
   current (/VERANDA/APPS), the document's folder in curDirName (/MUSIC),
   GetFile with ST_LD_DATA and the document's name (FMT0.MID). Once: the
   second time (after MIDI Player quits; DOC.DONE in the top folder) it
   stops the emulator (dump.bin).
   MIT licence (see LICENSE). */
#include <veranda.h>
#include <string.h>

static char app[] = "MIDI Player";
static char doc[] = "FMT0.MID";

int main(void)
{
    unsigned char h;
    LogText("MPDESK");
    h = FOpen(VR_ROOTPATH "DOC.DONE", 'r');
    if (h >= 2 && h <= 4) {
        FClose(h);
        LogText("MPDESK DONE");
        *(volatile unsigned char *)0x9FB4 = 1;
        asm("jmp $FFFF");
    }
    h = FOpen(VR_ROOTPATH "DOC.DONE", 'w');
    if (h >= 2 && h <= 4)
        FClose(h);
    longNames = LONG_NAMES;
    ChDir("/VERANDA/APPS");
    strcpy((char *)curDirName, "/MUSIC");
    LogText("MPDESK OPEN FMT0.MID");
    GetFile(app, ST_LD_DATA, 0, doc, 0);
    LogText("MPDESK NOT STARTED");
    *(volatile unsigned char *)0x9FB4 = 1;
    asm("jmp $FFFF");
    return 0;
}
