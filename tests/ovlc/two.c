/* overlay 2: at $A000 in another bank */
#pragma code-name ("OVERLAY2")
#pragma rodata-name ("OVL2RO")
#pragma data-name ("OVL2DATA")
#pragma bss-name ("OVL2BSS")
#include <veranda.h>
void log_any(const char *s);
int two(int x)
{
    log_any("OVLC TWO");
    return x + 100;
}
