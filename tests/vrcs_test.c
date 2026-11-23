/* the SDK's character set library (sdk/lib/vrcs.s, DECISIONS V140) on the
   host, through cc65's sim65: every byte's Unicode, its UTF-8 and the
   byte back, then strings decoded; tests/check_vrcs.py checks the lines
   against Python's iso8859_16 codec. MIT licence (see LICENSE). */
#include <stdio.h>
#include "vrcs.h"

static char s1[] = "Za\xc5\xbc\xc3\xb3\xc5\x82\xc4\x87 g\xc4\x99\xc5\x9bl\xc4\x85 ja\xc5\xba\xc5\x84";
static char s2[] = "ZA\xc5\xbb\xc3\x93\xc5\x81\xc4\x86 G\xc4\x98\xc5\x9aL\xc4\x84 JA\xc5\xb9\xc5\x83";
static char s3[] = "\xf0\x9f\x98\x80|\xc3\xb1|\xe2\x82\xac|\x80|\xc3|\xe2\x82|\xc0\xaf|\xc8\x9b";

static void str(char *s)
{
    unsigned int n = cs_from8(s), i;
    printf("S %u", n);
    for (i = 0; i < n; ++i)
        printf(" %02X", (unsigned char)s[i]);
    printf("\n");
}

int main(void)
{
    unsigned int c;
    unsigned char n, i;
    char o[4];
    for (c = 0; c < 256; ++c) {
        n = cs_utf8(c, o);
        printf("%02X %04X", c, cs_uni(c));
        for (i = 0; i < n; ++i)
            printf(" %02X", (unsigned char)o[i]);
        printf(" / %02X\n", cs_byte(cs_uni(c)));
    }
    printf("B %02X %02X %02X %02X\n", cs_byte(0xF1), cs_byte(0x159), cs_byte(0x2014), cs_byte(0xE9));
    str(s1);
    str(s2);
    str(s3);
    return 0;
}
