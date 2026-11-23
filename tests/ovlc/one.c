/* overlay 1: at $A000 in its bank */
#pragma code-name ("OVERLAY1")
#pragma rodata-name ("OVL1RO")
#pragma data-name ("OVL1DATA")
#pragma bss-name ("OVL1BSS")
#include <veranda.h>
unsigned char heap_get(unsigned off);
void log_any(const char *s);
static int calls;                       /* the overlay's own data */
int one(int x)
{
    log_any(calls ? "OVLC ONE AGAIN" : "OVLC ONE");
    ++calls;
    return x * 3 + heap_get(5);
}
