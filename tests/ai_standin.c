/* gate ask, session handoff (DECISIONS V199): a stand-in for Veranda
   Write's "AI help on the selected text", started by the desktop (from a
   START.REQ of the gate's) as /VERANDA/APPS/Veranda Write, the name a
   program put aside is known by. It writes the requests as Write does
   (docs/AIREQ.md):
     /VERANDA/.SYSTEM/AI.IN      the text (ISO-8859-16, Polish letters,
                                 CR at each paragraph's end)
     /VERANDA/.SYSTEM/AI.REQ     "AIREQ 1", "action translate-pl",
                                 "back Veranda Write"
     /VERANDA/.SYSTEM/START.REQ  "/VERANDA/APPS/Veranda Ask" (the desktop
                                 starts it: shell/prg.c prg_req)
   (AI.OUT and AI.RES of an earlier request deleted first) and puts itself
   aside (TaskCtl TASK_ASIDE). The real desktop starts, reads START.REQ
   and starts Veranda Ask (its test build: ASK.TST says Send, then Use
   this). When it is back it logs "STANDIN BACK", AI.RES's lines
   ("STANDIN RES ...") and AI.OUT in hexadecimal ("STANDIN OUT ..."), and
   stops the emulator.
   (V201) Built with -DHOG=n it first takes RAM banks until n are free
   ("STANDIN FREE n"), as a big Veranda Write holds them while aside.
   MIT licence (see LICENSE). */
#include <veranda.h>
#include <string.h>

static unsigned char st;
static char nm[16], txt[96], lg[120];

static const char text[] = "Za\xbf\xf3\xb3\xe5 g\xfd\xf7l\xa2 ja\xae\xf1.\rDrugi akapit: \xaf\xd3\xa3TA \xc5MA.\r";

static void __fastcall__ put(const char *name, const char *t, unsigned char n)
{
    unsigned char h;
    strcpy(nm, name);
    memcpy(txt, t, n);
    h = FOpen(nm, 'w');
    if (h < 2 || h > 9)
        return;
    FWrite(h, txt, n);
    FClose(h);
}

static void aside(void)
{
    st = 2;                             /* (put aside now: the next pass is after it is back) */
}

static const char hex[] = "0123456789ABCDEF";

static void __fastcall__ show(const char *name, unsigned char out)
{
    unsigned char h, n, i, k;
    char *p;
    strcpy(nm, name);
    h = FOpen(nm, 'r');
    if (h < 2 || h > 9 || dosStatus >= 20) {
        strcpy(lg, "STANDIN NO ");
        strcat(lg, name);
        LogText(lg);
        return;
    }
    n = FRead(h, txt, sizeof txt - 1);
    FClose(h);
    txt[n] = 0;
    if (out) {
        strcpy(lg, "STANDIN OUT ");
        p = lg + 12;
        for (i = 0; i < n && i < 50; ++i) {
            *p++ = hex[(unsigned char)txt[i] >> 4];
            *p++ = hex[txt[i] & 15];
        }
        *p = 0;
        LogText(lg);
        return;
    }
    for (p = txt; *p; p += k) {         /* AI.RES: a line at a time */
        for (k = 0; p[k] && p[k] != '\r' && p[k] != '\n'; ++k)
            ;
        strcpy(lg, "STANDIN RES ");
        strncat(lg, p, k);
        if (k)
            LogText(lg);
        while (p[k] == '\r' || p[k] == '\n')
            ++k;
    }
}

#ifdef HOG
static unsigned char sum[TASK_SUM];
#endif

static void tick(void)
{
#ifdef HOG
    unsigned char n;
#endif
    if (st == 0) {
        st = 1;
#ifdef HOG
        for (n = 0; n < 22; ++n) {
            TaskCtl(TASK_INFO, 0xFF, sum);
            if (sum[TS_FREE] <= HOG || !BankAlloc(sum[TS_FREE] - HOG > 4 ? 4 : 1))
                break;
        }
        TaskCtl(TASK_INFO, 0xFF, sum);
        strcpy(lg, "STANDIN FREE ");
        lg[13] = '0' + sum[TS_FREE] / 10;
        lg[14] = '0' + sum[TS_FREE] % 10;
        lg[15] = 0;
        LogText(lg);
#endif
        ChDir(VR_DATADIR);
        strcpy(nm, "AI.OUT");
        FDelete(nm);
        strcpy(nm, "AI.RES");
        FDelete(nm);
        put("AI.IN", text, sizeof text - 1);
        put("AI.REQ", "AIREQ 1\r\naction translate-pl\r\nback Veranda Write\r\n", 50);
        put("START.REQ", "/VERANDA/APPS/Veranda Ask\r\n", 27);
        LogText("STANDIN ASIDE");
        asideVector = (unsigned int)aside;
        TaskCtl(TASK_ASIDE, 0, 0);
    } else if (st == 2) {
        st = 3;
        LogText("STANDIN BACK");
        ChDir(VR_DATADIR);
        show("AI.RES", 0);
        show("AI.OUT", 1);
        *(volatile unsigned char *)0x9FB4 = 1;  /* (EMU_SAVE_ON_EXIT: dump.bin) */
        __asm__("jmp $FFFF");
    }
}

int main(void)
{
    LogText("STANDIN STARTED");
    appMain = (unsigned int)tick;
    return 0;
}
