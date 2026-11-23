/* Veranda's clipboard: the Text Scrap: its start (scrap.h). MIT licence (see LICENSE). */
#include <veranda.h>
#include <string.h>
#include "scrap.h"

unsigned char __fastcall__ scrap_text_begin(unsigned int n)
{
    unsigned char e = scrap_create(SCRAP_TEXT, n + 2);
    if (e)
        return e;
    return scrap_write(&n, 2);
}
