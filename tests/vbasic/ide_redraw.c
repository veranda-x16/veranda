/* gate vb_ide (V215): the redraw check in VeraBASIC's test build (B_FILE,
   with tests/tk_hash.s): 'L' $80 + n, the window as the steps drew it
   against a full drawing (keys.c's state_log draws it: view_all),
   each text row's bitmap and colour map hashed: "IDE REDRAW n rows first"
   (the rows unlike, the first of them; 255: none).

   MIT licence (LICENSE). */
#include "ide.h"

void __fastcall__ test_hash(unsigned char which);
extern unsigned char test_hbad, test_hfirst;

void test_redraw_a(void)
{
    test_hash(0);
}

void test_redraw_b(void)
{
    test_hash(1);
    ide_logn("IDE REDRAW ", test_log & 0x7F);
    ide_logn(" ", test_hbad);
    ide_logn(" ", test_hfirst);
    ide_log("\n");
    test_log = 0;
}
