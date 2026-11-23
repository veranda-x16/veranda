/* gate sdk: a C application whose overlays run in place in RAM banks
 * (sdk/cfg/app-c-ovl.cfg; app.hdr: overlays = banked, api = 2).
 *
 * Records 1 and 2 are linked at $A000; the loader puts each at $A000 of a
 * bank of its own, LoadOverlay(n, 0) names the bank, and a store to $00
 * maps it. Each overlay calls the kernel (LogText, through a copy of its
 * text below $A000: the bank gate maps a kernel bank there) and a
 * resident "heap accessor" that maps another bank and puts the caller's
 * back. */
#include <veranda.h>
#include <string.h>

#define RAM_BANK (*(volatile unsigned char *)0x00)

int one(int x);                         /* OVERLAY1 */
int two(int x);                         /* OVERLAY2 */

unsigned char heap;                     /* a bank of data */
static char low[40];

/* a byte of the heap bank; the caller's bank (an overlay's) put back */
unsigned char heap_get(unsigned off)
{
    unsigned char b = RAM_BANK, v;
    RAM_BANK = heap;
    v = *(unsigned char *)(0xA000 + off);
    RAM_BANK = b;
    return v;
}

/* LogText of a text anywhere (an overlay's included): copied below $A000 */
void log_any(const char *s)
{
    strcpy(low, s);
    LogText(low);
}

static char hex[] = "OVLC 0000 0000 XX";
static void put4(char *p, unsigned v)
{
    static const char d[] = "0123456789ABCDEF";
    p[0] = d[v >> 12]; p[1] = d[(v >> 8) & 15]; p[2] = d[(v >> 4) & 15]; p[3] = d[v & 15];
}

int main(void)
{
    unsigned char b1, b2;
    int r;

    heap = BankAlloc(1);
    RAM_BANK = heap;
    *(unsigned char *)0xA005 = 7;
    if (LoadOverlay(1, 0) != 0) { LogText("OVLC BAD 1"); return 0; }
    b1 = r1L;
    if (r0 != 0xA000) { LogText("OVLC BAD ADDR"); return 0; }
    if (LoadOverlay(2, 0) != 0) { LogText("OVLC BAD 2"); return 0; }
    b2 = r1L;
    RAM_BANK = b1;
    r = one(5);                         /* 5 * 3 + 7 */
    RAM_BANK = b2;
    r = two(r);                         /* + 100 */
    RAM_BANK = b1;
    r = one(r);                         /* again: the bank still holds it */
    put4(hex + 5, (unsigned)r);
    put4(hex + 10, b1 << 8 | b2);
    if (b2 == b1 + 1 && b1 != heap) {
        hex[15] = 'O';
        hex[16] = 'K';
    }
    RAM_BANK = heap;
    LogText(hex);
    return 0;
}
