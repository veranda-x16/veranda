/* Veranda FTP: names shown in Veranda's set (DECISIONS V140, V143), in
   overlay 1 (appBank, mapped for u8_cells by main.c's put()) with the
   SDK's vrcs table (src/vrcs.s, VRCS_BYTE).

   MIT licence (see LICENSE). */
#include <veranda.h>
#include <vrcs.h>
#include "ftp.h"
#pragma code-name ("OVERLAY1")

/* (V143) put()'s cell[] (raw bytes, 0-terminated) decoded in place from
   UTF-8 into Veranda's set, as PutCards' codes in main.c's font: ASCII,
   the set's $C0-$FF as $80-$BF, the Polish letters of $A0-$BF (font_pl)
   as $C0-$C7 (the rest of $A0-$BF has no room in main RAM: '?'); at most
   w cells, padded with spaces to w; a byte that is not UTF-8 (a sequence
   of four: each byte), a character the set lacks: '?' */
static unsigned char ui, un, uk, uc;
static unsigned int uu;

void __fastcall__ u8_cells(unsigned char w)
{
    ui = un = 0;
    while (un < w && (uc = cell[ui++]) != 0) {
        if (uc & 0x80) {
            uu = uk = 0;
            if (uc >= 0xC2 && uc < 0xE0) {
                uk = 1;
                uu = uc & 0x1F;
            } else if (uc >= 0xE0 && uc < 0xF0) {
                uk = 2;
                uu = uc & 0x0F;
            }
            while (uk && (cell[ui] & 0xC0) == 0x80) {
                uu = uu << 6 | (cell[ui++] & 0x3F);
                --uk;
            }
            uc = uk ? 0 : cs_byte(uu);
            if (uc >= 0xC0)
                uc -= 0x40;
            else if (uc >= 0xA0) {
                for (uk = 0; uk < 8 && font_pl[uk] != uc; ++uk)
                    ;
                uc = uk < 8 ? 0xC0 + uk : 0;
            }
        }
        cell[un++] = uc >= 32 && uc < 0xC8 && uc != 127 ? uc : '?';
    }
    while (un < w)
        cell[un++] = ' ';
}
