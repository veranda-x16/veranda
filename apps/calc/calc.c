/* Calculator: a Veranda desk accessory in C, a scientific calculator.

   A window in the middle of the screen, over the application that opened
   it (GetFile on a DESK_ACC file: docs/APPFORMAT.md); the close box or
   Escape ends it with RstrAppl, which gives the application back exactly
   as it was.

   The numbers are the X16 ROM's floats (its maths library in ROM bank 4,
   called through its jump table: fp.s; 40 bits, shown to 9 significant
   digits, in scientific notation from 1E+10 and below 1E-05), the
   expression as written: x and / before + and -, ^ before both (from the
   right), brackets 8 deep (DECISIONS V186). Functions work on the number
   shown (sin, cos, tan and their inverses in degrees or radians, ln, log,
   e^x, 10^x, x squared, the root, 1/x, n!, %, +/-), with a memory (MC MR
   M+ M-), the last result (Ans), the exponent key (EE) and 2nd, which
   turns sin cos tan ln log into their inverses for one key.

   Keys (the window's keys, and typed):
     0-9 . + - * (or x) / ^ ( ) % ! = (or Return)
     Backspace (or Delete): the last digit, else the entry; c: clear all
     s o t: sin cos tan, S O T: their inverses; l L: ln, e^x;
     g G: log, 10^x; q: x squared; r: root; i: 1/x; p: pi; a: Ans;
     e: EE; n: +/-; d: degrees/radians; f: 2nd; m M: M+ M-; k K: MR MC;
     Escape: close.

   Veranda Look 3 "Sunroom" (DECISIONS V148): the SDK's window (vrwin.h),
   Veranda's palette light or dark (theme.h); a sunk display (its own big
   digits: glyphs.h, written by mkglyphs.py), the expression above the
   number, DEG or RAD, 2nd and M as small badges; 6 x 7 keys with rounded
   corners and a deeper bottom edge, by role on the colour map: digits on
   the paper, + - x / on the theme's accent, the functions on the chrome,
   the memory row on the sidebar's tint, C and erase on orange, = (two
   rows tall) on the selection colour; a key shows pressed (inverted) for
   a few frames when clicked or typed. On a screen under 320 lines (the
   640 x 240 and 320 x 240 modes) the keys are 16 lines tall instead of
   24 and the window fits in 240 lines.

   MIT licence (see LICENSE). */
#include <veranda.h>
#include <vr.h>
#include <stdlib.h>
#include <string.h>
#include <theme.h>
#include <vrwin.h>
#include "glyphs.h"

/* the ROM's maths (fp.s) */
extern unsigned char fa[5], fb[5];
unsigned char __fastcall__ fp_run(unsigned int op);
#define F_ADD  0x11B
#define F_SUB  0x115
#define F_MUL  0x121
#define F_DIV  0x127
#define F_POW  0x139
#define F_LOG  0x02A
#define F_SQR  0x030
#define F_EXP  0x03C
#define F_COS  0x03F
#define F_SIN  0x042
#define F_TAN  0x045
#define F_ATN  0x048

typedef unsigned char fnum[5];

/* the window */
#define W       296             /* 37 cards */
#define KX      8               /* the keys' left in the window */
#define BW      40              /* a key: 5 cards across */
#define GAP     8
#define DY      24              /* the display's top */
#define COLS    6
#define ROWS    7
#define NB      33              /* the number's bitmap: 33 bytes across */

static unsigned int x0, y0;     /* the window's top left */
static unsigned char bh;        /* a key's height: 24 (16 on a short screen) */
static unsigned char dh;        /* the display's: 48 (40) */
static unsigned int ky;         /* the keys' top in the window */
static unsigned int wh;         /* the window's height */
static struct vrwin win;

/* the keys' actions: the characters, or these */
#define A_CLEAR  0x80
#define A_BACK   0x81
#define A_NEG    0x82
#define A_EE     0x83
#define A_ANS    0x84
#define A_PI     0x85
#define A_2ND    0x86
#define A_DRG    0x87
#define A_MC     0x88
#define A_MR     0x89
#define A_MPLUS  0x8A
#define A_MMINUS 0x8B
#define A_SIN    0x90           /* the functions: A_SIN .. A_FACT */
#define A_COS    0x91
#define A_TAN    0x92
#define A_ASIN   0x93
#define A_ACOS   0x94
#define A_ATAN   0x95
#define A_LN     0x96
#define A_LOG    0x97
#define A_EXP    0x98
#define A_POW10  0x99
#define A_SQUARE 0x9A
#define A_ROOT   0x9B
#define A_INV    0x9C
#define A_FACT   0x9D
#define A_PCT    0x9E

static const unsigned char keys[COLS * ROWS] = {
    A_2ND, A_DRG, A_MC, A_MR, A_MPLUS, A_MMINUS,
    A_SIN, A_COS, A_TAN, A_CLEAR, A_BACK, '/',
    A_LN, A_LOG, '(', ')', A_PCT, '*',
    A_SQUARE, A_ROOT, '7', '8', '9', '-',
    '^', A_INV, '4', '5', '6', '+',
    A_FACT, A_PI, '1', '2', '3', '=',
    A_EE, A_ANS, A_NEG, '0', '.', '=' };
#define K_EQ    35              /* = : this key and the one under it */
#define K_2ND   0

/* typed keys -> actions (the rest: themselves when a key has them) */
static const unsigned char typed_in[] = {
    'x', 'X', 13, '=', 8, 0x1D, 'c', 'C', 's', 'S', 'o', 'O', 't', 'T', 'l', 'L', 'g', 'G', 'q', 'r', 'i', 'p',
    'a', 'e', 'n', 'd', 'f', 'm', 'M', 'k', 'K', '%', '!' };
static const unsigned char typed_out[] = {
    '*', '*', '=', '=', A_BACK, A_BACK, A_CLEAR, A_CLEAR, A_SIN, A_ASIN, A_COS, A_ACOS, A_TAN, A_ATAN, A_LN, A_EXP,
    A_LOG, A_POW10, A_SQUARE, A_ROOT, A_INV, A_PI, A_ANS, A_EE, A_NEG, A_DRG, A_2ND, A_MPLUS, A_MMINUS, A_MR,
    A_MC, A_PCT, A_FACT };

/* the state */
#define ST_ENTRY 0              /* a number being typed (ent) */
#define ST_VALUE 1              /* cur: an operand (a function's result, pi, MR, Ans, a bracket's) */
#define ST_OP    2              /* after an operator or "(": cur shows the value so far */
#define ST_DONE  3              /* after =: cur the result; a digit starts afresh */
#define ST_ERR   4
static unsigned char st;
static fnum cur, mem, ans;
static char ent[20];            /* [-]digits[.digits][E[-]digits] */
static unsigned char second, rad, memset_;
#define NVAL 26
#define NOPS 26
static fnum vs[NVAL];
static unsigned char nv;
static unsigned char os[NOPS];
static unsigned char no, depth;
static unsigned char err;       /* the maths failed (the ROM's error, or a domain) */

/* the expression line: expr, then the operand's text (otext) */
#define EXMAX 96
static char expr[EXMAX];
static char otext[48];
static unsigned char otype;     /* 0 a number, 1 a bracket's group, 2 a function's result */
static unsigned char gpos[8];   /* where each open bracket starts in expr */

static char line[40];           /* the display's number */
static char tmp[48];

/* a key shown pressed */
static unsigned char pk = 0xFF, ptime, plast;

static const fnum ONE = { 0x81, 0, 0, 0, 0 };
static const fnum PI = { 0x82, 0x49, 0x0F, 0xDA, 0xA2 };
static const fnum HALFPI = { 0x81, 0x49, 0x0F, 0xDA, 0xA2 };
static const fnum D2R = { 0x7B, 0x0E, 0xFA, 0x35, 0x12 };      /* pi / 180 */
static const fnum R2D = { 0x86, 0x65, 0x2E, 0xE0, 0xD3 };      /* 180 / pi */
static const fnum LN10 = { 0x82, 0x13, 0x5D, 0x8D, 0xDE };

#ifdef CALC_TEST
void calc_test_start(void);
void calc_test_clock_reset(void);
void calc_test_clock_log(const char *what);
#endif

/*---------------------------------------------------------------
  numbers
  ---------------------------------------------------------------*/
static void f2(unsigned int op, unsigned char *r, const unsigned char *a, const unsigned char *b)
{
    if (err)
        return;
    memcpy(fa, a, 5);
    memcpy(fb, b, 5);
    if (fp_run(op))
        err = 1;
    else
        memcpy(r, fa, 5);
}

static void f1(unsigned int op, unsigned char *r, const unsigned char *a)
{
    if (err)
        return;
    memcpy(fa, a, 5);
    if (fp_run(op))
        err = 1;
    else
        memcpy(r, fa, 5);
}

static void f_ul(unsigned char *r, unsigned long v)
{
    unsigned char e = 0xA0;
    if (!v) {
        memset(r, 0, 5);
        return;
    }
    while (!(v & 0x80000000UL)) {
        v <<= 1;
        --e;
    }
    r[0] = e;
    r[1] = (unsigned char)(v >> 24) & 0x7F;
    r[2] = (unsigned char)(v >> 16);
    r[3] = (unsigned char)(v >> 8);
    r[4] = (unsigned char)v;
}

#define f_neg(r) ((r)[0] ? ((r)[1] ^= 0x80) : 0)
#define f_minus(r) ((r)[0] && ((r)[1] & 0x80))

/* a whole number below 2^31? its value to *v */
static unsigned char f_whole(const unsigned char *a, long *v)
{
    unsigned char b;
    unsigned long m;
    if (!a[0]) {
        *v = 0;
        return 1;
    }
    if (a[0] <= 0x80 || a[0] > 0x80 + 31)
        return 0;
    b = a[0] - 0x80;
    m = ((unsigned long)(a[1] | 0x80) << 24) | ((unsigned long)a[2] << 16) | ((unsigned int)a[3] << 8) | a[4];
    if (m << b)
        return 0;
    *v = m >> (32 - b);
    if (a[1] & 0x80)
        *v = -*v;
    return 1;
}

/* r = m * 10^k, negative if neg: m * 5^k (5^13 and below are exact
   in the mantissa: up to 13 places, one rounding), then 2^k added to the
   exponent */
static void f_make(unsigned char *r, unsigned long m, signed char k, unsigned char neg)
{
    fnum t;
    unsigned char s, i;
    signed char j = k;
    int e;
    unsigned long p;
    f_ul(r, m);
    if (!m)
        return;
    while (j) {
        s = j > 0 ? j : -j;
        if (s > 13)
            s = 13;
        for (p = 1, i = 0; i < s; ++i)
            p *= 5;
        f_ul(t, p);
        f2(j > 0 ? F_MUL : F_DIV, r, r, t);
        j += j > 0 ? -(signed char)s : s;
    }
    e = r[0] + k;
    if (e > 255)
        err = 1;
    else if (e < 1)
        memset(r, 0, 5);
    else {
        r[0] = e;
        if (neg)
            f_neg(r);
    }
}

/* v's first 9 significant digits, rounded, worked out from its binary
   value, the mantissa M times 2^E: M's decimal digits doubled E times,
   or halved -E times, 22 significant digits kept (the ROM's fout is a
   hair off in the last digit: pi as 3.14159266, 1E+25 as
   9.99999999E+24). Out: dneg, dd (dn of them, no zeros at either end),
   dip the digits before the point (may be <= 0). */
#define DMAX 22
static unsigned char dneg, dn;
static signed char dip;
static char dd[12];
static unsigned char dig[DMAX + 2];     /* the digits, the highest first */
static void digits(const unsigned char *v)
{
    unsigned char n = 0, i, c, k, r;
    signed char e;
    unsigned long m;
    dn = 0;
    dip = 0;
    dneg = 0;
    if (!v[0])
        return;
    dneg = v[1] >> 7;
    m = ((unsigned long)(v[1] | 0x80) << 24) | ((unsigned long)v[2] << 16) | ((unsigned int)v[3] << 8) | v[4];
    for (i = 10; i-- > 0;) {            /* (M has 10 digits) */
        dig[i] = m % 10;
        m /= 10;
    }
    n = 10;
    dip = 10;
    e = v[0] - 0xA0;                    /* the value: M * 2^e */
    for (k = e < 0 ? -e : e; k; --k) {
        if (e > 0) {                    /* doubled, from the lowest digit */
            c = 0;
            for (i = n; i-- > 0;) {
                r = (dig[i] << 1) + c;
                c = r >= 10;
                dig[i] = c ? r - 10 : r;
            }
            if (c) {
                memmove(dig + 1, dig, n);
                dig[0] = 1;
                ++dip;
                if (n < DMAX)
                    ++n;
            }
        } else {                        /* halved, from the highest */
            c = 0;
            for (i = 0; i < n; ++i) {
                r = dig[i] + (c ? 10 : 0);
                c = r & 1;
                dig[i] = r >> 1;
            }
            if (c && n < DMAX)
                dig[n++] = 5;
        }
        if (!dig[0]) {                  /* (a leading zero goes) */
            memmove(dig, dig + 1, --n);
            --dip;
        }
    }
    for (i = n; i < 10; ++i)
        dig[i] = 0;
    /* the top 9, rounded half up */
    for (i = 0; i < 9; ++i)
        dd[i] = '0' + dig[i];
    dn = 9;
    if (dig[9] >= 5) {
        for (i = 9; i-- > 0;) {
            if (dd[i] != '9') {
                ++dd[i];
                break;
            }
            dd[i] = '0';
        }
        if (i == 0xFF) {
            dd[0] = '1';
            ++dip;
        }
    }
    while (dn && dd[dn - 1] == '0')
        --dn;
}

/* the number as the display shows it: 9 digits at most, plain from 1E-05
   up to 1E+10, scientific beyond */
static void fmt(const unsigned char *v, char *out)
{
    signed char s, i;
    char *o = out;
    digits(v);
    if (!dn) {
        strcpy(out, "0");
        return;
    }
    if (dneg)
        *o++ = '-';
    s = dip - 1;
    if (s < -5 || s > 9) {
        *o++ = dd[0];
        if (dn > 1) {
            *o++ = '.';
            memcpy(o, dd + 1, dn - 1);
            o += dn - 1;
        }
        *o++ = 'E';
        *o++ = s < 0 ? '-' : '+';
        if (s < 0)
            s = -s;
        *o++ = '0' + s / 10;
        *o++ = '0' + s % 10;
    } else if (dip <= 0) {
        *o++ = '0';
        *o++ = '.';
        for (i = dip; i < 0; ++i)
            *o++ = '0';
        memcpy(o, dd, dn);
        o += dn;
    } else {
        for (i = 0; i < dip; ++i)
            *o++ = i < dn ? dd[i] : '0';
        if (dn > dip) {
            *o++ = '.';
            memcpy(o, dd + dip, dn - dip);
            o += dn - dip;
        }
    }
    *o = 0;
}

/* a function's result a hair from a short number (tan 45 = .999999999,
   10 ^ 0.5 ^ 2): rounded to 8 digits it has 4 or fewer, so it is that */
static void snap(unsigned char *v)
{
    unsigned char i;
    unsigned long m = 0;
    if (err)
        return;
    digits(v);
    if (dn < 9)
        return;
    if (dd[8] >= '5') {
        for (i = 8; i-- > 0;) {
            if (dd[i] != '9') {
                ++dd[i];
                break;
            }
            dd[i] = '0';
        }
        if (i == 0xFF) {
            dd[0] = '1';
            ++dip;
        }
    }
    dn = 8;
    while (dn && dd[dn - 1] == '0')
        --dn;
    if (dn > 4)
        return;
    for (i = 0; i < dn; ++i)
        m = m * 10 + (dd[i] - '0');
    f_make(v, m, dip - dn, dneg);
}

/* the entry's value */
static void ent_value(unsigned char *r)
{
    const char *p = ent;
    unsigned long m = 0;
    signed char k = 0, e = 0;
    unsigned char pt = 0, neg = 0, eneg = 0;
    if (*p == '-') {
        neg = 1;
        ++p;
    }
    for (; *p && *p != 'E'; ++p) {
        if (*p == '.')
            pt = 1;
        else {
            m = m * 10 + (*p - '0');
            if (pt)
                --k;
        }
    }
    if (*p == 'E') {
        if (*++p == '-') {
            eneg = 1;
            ++p;
        }
        while (*p)
            e = e * 10 + (*p++ - '0');
        if (eneg)
            e = -e;
    }
    f_make(r, m, k + e, neg);
}

/* r = a ^ n, n whole: by squaring (exact where the ROM's fpwr is a hair
   off: 7 ^ 2 = 49.0000001) */
static void f_ipow(unsigned char *r, const unsigned char *a, long n)
{
    fnum b, x;
    unsigned char inv = n < 0;
    if (inv)
        n = -n;
    memcpy(b, a, 5);
    memcpy(x, ONE, 5);
    while (n && !err) {
        if (n & 1)
            f2(F_MUL, x, x, b);
        n >>= 1;
        if (n)
            f2(F_MUL, b, b, b);
    }
    if (inv)
        f2(F_DIV, x, ONE, x);
    memcpy(r, x, 5);
}

static void f_pow(unsigned char *r, const unsigned char *a, const unsigned char *b)
{
    long n;
    if (f_whole(b, &n) && n > -1000 && n < 1000) {
        if (!a[0] && n < 0)
            err = 1;
        else
            f_ipow(r, a, n);
    } else if (f_minus(a))
        err = 1;
    else if (!a[0])
        memset(r, 0, 5);
    else {
        f2(F_POW, r, a, b);
        snap(r);
    }
}

static void apply(unsigned char op, unsigned char *r, const unsigned char *a, const unsigned char *b)
{
    switch (op) {
    case '+': f2(F_ADD, r, a, b); break;
    case '-': f2(F_SUB, r, a, b); break;
    case '*': f2(F_MUL, r, a, b); break;
    case '/':
        if (!b[0])
            err = 1;
        else
            f2(F_DIV, r, a, b);
        break;
    case '^': f_pow(r, a, b); break;
    }
}

/* sin, cos, tan of v (in degrees: whole multiples of 90 exact) */
static void trig(unsigned char f, unsigned char *v)
{
    long n;
    if (!rad && f_whole(v, &n)) {
        n %= 360;
        if (n < 0)
            n += 360;
        if (n % 90 == 0) {
            n /= 90;
            if (f == A_COS)
                n = (n + 1) & 3;
            if (f == A_TAN && (n & 1)) {
                err = 1;
                return;
            }
            /* sin: 0 1 0 -1 */
            f_ul(v, (n & 1) ? 1 : 0);
            if (n == 3)
                f_neg(v);
            if (f == A_TAN)
                memset(v, 0, 5);
            return;
        }
    }
    if (!rad)
        f2(F_MUL, v, v, D2R);
    f1(f == A_SIN ? F_SIN : f == A_COS ? F_COS : F_TAN, v, v);
    if (v[0] && v[0] < 0x80 - 29)       /* (below 1E-9: sin pi) */
        memset(v, 0, 5);
    snap(v);
}

/* asin, acos, atan of v */
static void atrig(unsigned char f, unsigned char *v)
{
    fnum t;
    unsigned char neg = f_minus(v);
    if (f != A_ATAN) {
        f2(F_MUL, t, v, v);
        f2(F_SUB, t, ONE, t);           /* 1 - v^2 */
        if (f_minus(t)) {
            err = 1;
            return;
        }
        if (!t[0]) {
            memcpy(v, HALFPI, 5);
            if (neg)
                f_neg(v);
        } else {
            f1(F_SQR, t, t);
            f2(F_DIV, v, v, t);
            f1(F_ATN, v, v);
        }
        if (f == A_ACOS)
            f2(F_SUB, v, HALFPI, v);
    } else
        f1(F_ATN, v, v);
    if (!rad)
        f2(F_MUL, v, v, R2D);
    snap(v);
}

static void fn(unsigned char f, unsigned char *v)
{
    long n;
    fnum t;
    switch (f) {
    case A_SIN: case A_COS: case A_TAN:
        trig(f, v);
        break;
    case A_ASIN: case A_ACOS: case A_ATAN:
        atrig(f, v);
        break;
    case A_LN: case A_LOG:
        if (!v[0] || f_minus(v)) {
            err = 1;
            break;
        }
        f1(F_LOG, v, v);
        if (f == A_LOG)
            f2(F_DIV, v, v, LN10);
        snap(v);
        break;
    case A_EXP:
        f1(F_EXP, v, v);
        snap(v);
        break;
    case A_POW10:
        f_ul(t, 10);
        f_pow(v, t, v);
        break;
    case A_SQUARE:
        f2(F_MUL, v, v, v);
        break;
    case A_ROOT:
        f1(F_SQR, v, v);
        snap(v);
        break;
    case A_INV:
        apply('/', v, ONE, v);
        break;
    case A_FACT:
        if (!f_whole(v, &n) || n < 0 || n > 33) {
            err = 1;
            break;
        }
        memcpy(v, ONE, 5);
        while (n > 1) {                 /* (whole products while they fit in 32 bits: fewer roundings) */
            unsigned long p = n--;
            while (n > 1 && p <= 0xFFFFFFFFUL / n)
                p *= n--;
            f_ul(t, p);
            f2(F_MUL, v, v, t);
        }
        break;
    }
}

/*---------------------------------------------------------------
  drawing
  ---------------------------------------------------------------*/
static unsigned char nbuf[NB * BIG_H];

/* a small sign (glyphs.h) at x, its rows from the baseline y */
static void glyph(unsigned char g, unsigned int x, unsigned int y)
{
    unsigned char r, c, w, h, s;
    unsigned int bits;
    const unsigned int *p;
    g -= 0x80;
    w = small_w[g];
    h = small_h[g];
    p = small_rows + small_at[g];
    y += small_top[g];
    for (r = 0; r < h; ++r, ++y) {
        bits = p[r];
        for (c = 0; c < w;) {
            if (bits & (0x8000 >> c)) {
                s = c;
                while (c < w && (bits & (0x8000 >> c)))
                    ++c;
                WHorizontalLine(0xFF, x + s, x + c - 1, y);
            } else
                ++c;
        }
    }
}

/* text with signs: its width in the font now */
static unsigned char cw(unsigned char c)
{
    return c >= 0x80 && c < 0x80 + G_COUNT ? small_w[c - 0x80] + 1 : GetCharWidth(c);
}

static unsigned int rich_w(const char *s)
{
    unsigned int w = 0;
    while (*s)
        w += cw(*s++);
    return w;
}

static void rich(const char *s, unsigned int x, unsigned int y)
{
    unsigned char c;
    while ((c = *s++) != 0) {
        if (c >= 0x80 && c < 0x80 + G_COUNT) {
            glyph(c, x, y);
            x += small_w[c - 0x80] + 1;
        } else {
            WPutChar(c, x, y);
            x += GetCharWidth(c);
        }
    }
}

/* a key's label (with 2nd: the inverse's) */
static const char *label(unsigned char a)
{
    static char s[8];
    if (second) {
        if (a == A_SIN) a = A_ASIN;
        else if (a == A_COS) a = A_ACOS;
        else if (a == A_TAN) a = A_ATAN;
        else if (a == A_LN) a = A_EXP;
        else if (a == A_LOG) a = A_POW10;
    }
    s[1] = 0;
    switch (a) {
    case A_CLEAR: return "C";
    case A_BACK: s[0] = G_BACK; break;
    case A_NEG: s[0] = G_PM; break;
    case A_EE: return "EE";
    case A_ANS: return "Ans";
    case A_PI: s[0] = G_PI; break;
    case A_2ND: return "2nd";
    case A_DRG: return "DRG";
    case A_MC: return "MC";
    case A_MR: return "MR";
    case A_MPLUS: return "M+";
    case A_MMINUS: s[0] = 'M'; s[1] = G_MINUS; s[2] = 0; break;
    case A_SIN: return "sin";
    case A_COS: return "cos";
    case A_TAN: return "tan";
    case A_ASIN: strcpy(s, "sin?"); s[3] = G_SUPM1; break;
    case A_ACOS: strcpy(s, "cos?"); s[3] = G_SUPM1; break;
    case A_ATAN: strcpy(s, "tan?"); s[3] = G_SUPM1; break;
    case A_LN: return "ln";
    case A_LOG: return "log";
    case A_EXP: s[0] = 'e'; s[1] = G_SUPX; s[2] = 0; break;
    case A_POW10: strcpy(s, "10?"); s[2] = G_SUPX; break;
    case A_SQUARE: s[0] = 'x'; s[1] = G_SUP2; s[2] = 0; break;
    case A_ROOT: s[0] = G_ROOT; s[1] = 'x'; s[2] = 0; break;
    case '^': s[0] = 'x'; s[1] = G_SUPY; s[2] = 0; break;
    case A_INV: return "1/x";
    case A_FACT: return "n!";
    case A_PCT: return "%";
    case '*': s[0] = G_TIMES; break;
    case '/': s[0] = G_DIV; break;
    case '-': s[0] = G_MINUS; break;
    case '+': s[0] = G_PLUS; break;
    case '=': s[0] = G_EQ; break;
    default: s[0] = a;
    }
    return s;
}

static unsigned char colour(unsigned char i)
{
    unsigned char a = keys[i];
    if ((a >= '0' && a <= '9') || a == '.' || a == A_NEG)
        return 0;
    if (a == '=')
        return theme.hilite ? theme.hilite : SELECT;
    if (a == '+' || a == '-' || a == '*' || a == '/')
        return CHROME;
    if (a == A_CLEAR || a == A_BACK)
        return ORANGE;
    if (i == K_2ND && second)
        return YELLOW;
    return SIDEBAR;                     /* (the functions, the memory: quieter) */
}

static void key_at(unsigned char i, unsigned int *x, unsigned int *y, unsigned char *h)
{
    unsigned char c = i % COLS, r = i / COLS;
    *x = x0 + KX + c * (BW + GAP);
    *y = y0 + ky + r * (bh + GAP);
    *h = i == K_EQ ? bh + bh + GAP : bh;
}

/* the inside of key i inverted (pressed, or back) */
static void key_invert(unsigned char i)
{
    unsigned int x, y;
    unsigned char h;
    key_at(i, &x, &y, &h);
    WInvertRectangle(x + 1, y + 1, x + BW - 2, y + h - 3);
}

static void draw_key(unsigned char i)
{
    unsigned int x, y, r, b;
    unsigned char h, c;
    const char *s;
    key_at(i, &x, &y, &h);
    r = x + BW - 1;
    b = y + h - 1;
    SetPattern(0);
    WRectangle(x, y, r, b);
    theme_rect(x >> 3, BW >> 3, y >> 3, h >> 3, colour(i));
    /* the edge: rounded corners, the bottom two lines deep */
    WHorizontalLine(0xFF, x + 2, r - 2, y);
    WHorizontalLine(0xFF, x + 2, r - 2, b);
    WHorizontalLine(0xFF, x + 1, r - 1, b - 1);
    WVerticalLine(0xFF, x, y + 2, b - 2);
    WVerticalLine(0xFF, r, y + 2, b - 2);
    WDrawPoint(DRAW_INK, x + 1, y + 1);
    WDrawPoint(DRAW_INK, r - 1, y + 1);
    s = label(keys[i]);
    c = (keys[i] >= '0' && keys[i] <= '9') || keys[i] == '.';
    currentMode = c ? SET_BOLD : 0;     /* (the digits bold) */
    rich(s, x + (BW + 1 - rich_w(s) - c) / 2, y + (h - 1) / 2 + 4);
    currentMode = 0;
    if (i == pk)
        key_invert(i);
}

/* the big number at the display's right */
static void show_number(const char *s)
{
    unsigned int x, w = 0;
    const char *p;
    unsigned char r, g, b;
    unsigned long v;
    unsigned char *q;
    for (p = s; *p; ++p) {
        const char *f = strchr(BIG_CHARS, *p);
        if (f)
            w += big_w[f - BIG_CHARS];
    }
    memset(nbuf, 0, sizeof nbuf);
    x = NB * 8 - 6 - w;
    for (p = s; *p; ++p) {
        const char *f = strchr(BIG_CHARS, *p);
        if (!f)
            continue;
        g = f - BIG_CHARS;
        b = x & 7;
        q = nbuf + (x >> 3);
        for (r = 0; r < BIG_H; ++r, q += NB) {
            v = (unsigned long)big_rows[g][r] << (8 - b);
            q[0] |= (unsigned char)(v >> 16);
            q[1] |= (unsigned char)(v >> 8);
            q[2] |= (unsigned char)v;
        }
        x += big_w[g];
    }
    WBitmapUp(nbuf, ((x0 + KX) >> 3) + 1, NB, y0 + DY + dh - (dh > 40 ? 26 : 23), BIG_H | 0x8000);
}

/* a badge: the text reversed in a box, at x on the top line; its width */
static unsigned int badge(const char *s, unsigned int x)
{
    unsigned int w = rich_w(s), t = y0 + DY + 4;
    SetPattern(1);
    WRectangle(x, t, x + w + 3, t + 9);
    WDrawPoint(DRAW_ERASE, x, t);
    WDrawPoint(DRAW_ERASE, x + w + 3, t);
    WDrawPoint(DRAW_ERASE, x, t + 9);
    WDrawPoint(DRAW_ERASE, x + w + 3, t + 9);
    currentMode = SET_REVERSE;
    WPutString((char *)s, x + 2, t + 7);
    currentMode = 0;
    return w + 8;
}

/* the display: badges, the expression, the number */
static void show(void)
{
    unsigned int l = x0 + KX, r = x0 + W - KX - 1, t = y0 + DY, x, w, avail;
    char *p;
    SetPattern(0);
    WRectangle(l + 2, t + 2, r - 2, t + dh - 3);
    UseSystemFont();
    x = l + 6;
    x += badge(rad ? "RAD" : "DEG", x);
    if (second)
        x += badge("2nd", x);
    if (memset_)
        x += badge("M", x);
    UseFont(FONT_UI);
    /* the expression: its end, as much as fits */
    strcpy(tmp, "");
    if (st != ST_DONE && otype)
        strcpy(tmp, otext);
    p = expr;
    avail = r - 8 - x;
    w = rich_w(p) + rich_w(tmp);
    while (*p && w > avail)
        w -= cw(*p++);
    rich(p, r - 7 - w, t + (dh > 40 ? 14 : 13));
    rich(tmp, r - 7 - rich_w(tmp), t + (dh > 40 ? 14 : 13));
    if (st == ST_ERR)
        strcpy(line, "Error");
    else if (st == ST_ENTRY)
        strcpy(line, !ent[0] ? "0" : strcmp(ent, "-") ? ent : "-0");
    else
        fmt(cur, line);
    show_number(line);
}

static void draw(void)
{
    unsigned char i;
    unsigned int l, r, t, b;
    dispBufferOn = ST_WR_FORE;          /* the application's screen is put aside whole */
    theme_load();
    theme_palette();
    theme_menus();                      /* (the UI font) */
    win.x = x0 >> 3;
    win.y = y0 >> 3;
    win.w = W >> 3;
    win.h = wh >> 3;
    win.flags = VW_CLOSE | VW_FRAME | (theme.dark ? 0 : VW_SHADOW);
    vr_win(&win, "Calculator");
    UseFont(FONT_UI);
    /* the display, sunk: a rounded frame, a second line along its top and left */
    l = x0 + KX;
    r = x0 + W - KX - 1;
    t = y0 + DY;
    b = t + dh - 1;
    theme_rect(l >> 3, (r - l + 1) >> 3, t >> 3, dh >> 3, SIDEBAR);
    WHorizontalLine(0xFF, l + 2, r - 2, t);
    WHorizontalLine(0xFF, l + 2, r - 2, b);
    WVerticalLine(0xFF, l, t + 2, b - 2);
    WVerticalLine(0xFF, r, t + 2, b - 2);
    WDrawPoint(DRAW_INK, l + 1, t + 1);
    WDrawPoint(DRAW_INK, r - 1, t + 1);
    WDrawPoint(DRAW_INK, l + 1, b - 1);
    WDrawPoint(DRAW_INK, r - 1, b - 1);
    WHorizontalLine(0xAA, l + 2, r - 2, t + 1);    /* (a dotted line: the shade) */
    WVerticalLine(0xAA, l + 1, t + 2, b - 2);
    for (i = 0; i < COLS * ROWS; ++i)
        if (i != K_EQ + COLS)
            draw_key(i);
    show();
}

static void calc_close(void)
{
    LogText("CALC CLOSED");
#ifdef CALC_TEST
    calc_test_clock_reset();
#endif
    RstrAppl();
}

/*---------------------------------------------------------------
  the expression
  ---------------------------------------------------------------*/
static void ex_add(const char *s)
{
    unsigned char n = strlen(s), l = strlen(expr), i, d;
    if (l + n >= EXMAX) {               /* the front goes */
        d = l + n - EXMAX + 1;
        memmove(expr, expr + d, l - d + 1);
        for (i = 0; i < depth; ++i)
            gpos[i] = gpos[i] > d ? gpos[i] - d : 0;
    }
    strcat(expr, s);
}

static void ot_num(void)
{
    fmt(cur, otext);
    otype = 0;
}

/* otext as f's argument: pre + "(" + otext + ")" + post (a bracket's
   group without its own brackets; a number without any when bare) */
static void ot_wrap(const char *pre, const char *post, unsigned char bare)
{
    unsigned char n = strlen(otext);
    if (otype == 1) {                   /* "(...)": its inside */
        memmove(otext, otext + 1, n);
        otext[n - 2] = 0;
    }
    if (bare && !otype) {
        strcpy(tmp, pre);
    } else {
        strcpy(tmp, pre);
        strcat(tmp, "(");
    }
    if (strlen(tmp) + strlen(otext) + strlen(post) + 2 >= sizeof otext) {
        ot_num();                       /* (too long: the number it is) */
    }
    strcat(tmp, otext);
    if (!(bare && !otype))
        strcat(tmp, ")");
    strcat(tmp, post);
    strcpy(otext, tmp);
    otype = 2;
}

static void push(const unsigned char *v)
{
    if (nv < NVAL)
        memcpy(vs[nv++], v, 5);
    else
        err = 1;
}

static unsigned char prec(unsigned char o)
{
    return o == '+' || o == '-' ? 1 : o == '*' || o == '/' ? 2 : o == '^' ? 3 : 0;
}

/* the top operator applied */
static void reduce(void)
{
    --no;
    --nv;
    apply(os[no], vs[nv - 1], vs[nv - 1], vs[nv]);
}

/* the operand (cur) taken: the entry's value */
static void commit(void)
{
    if (st == ST_ENTRY) {
        ent_value(cur);
        strcpy(otext, ent[0] && strcmp(ent, "-") ? ent : "0");
        otype = 0;
    }
}

static void fresh(void)
{
    nv = no = depth = 0;
    expr[0] = 0;
    otext[0] = 0;
    otype = 0;
}

static void clear(void)
{
    fresh();
    memset(cur, 0, 5);
    ent[0] = 0;
    st = ST_ENTRY;
}

static char opsym(unsigned char o)
{
    return o == '-' ? G_MINUS : o == '*' ? G_TIMES : o == '/' ? G_DIV : o == '+' ? G_PLUS : o;
}

static void binop(unsigned char o)
{
    static char s[4] = " + ";
    if (st == ST_OP && no && os[no - 1] != '(') {
        os[no - 1] = o;                 /* another operator instead */
        expr[strlen(expr) - 2] = opsym(o);
        return;
    }
    if (st == ST_OP)                    /* "(" then an operator: nothing */
        return;
    if (no >= NOPS - 1) {               /* (2^2^2^ ... deeper than the stack) */
        err = 1;
        return;
    }
    commit();
    if (st == ST_DONE) {
        fresh();
        ot_num();
    }
    ex_add(otext);
    s[1] = opsym(o);
    ex_add(s);
    push(cur);
    while (no && !err && os[no - 1] != '(' && prec(os[no - 1]) >= prec(o) && !(o == '^' && os[no - 1] == '^'))
        reduce();
    os[no++] = o;
    memcpy(cur, vs[nv - 1], 5);
    st = ST_OP;
}

static void open_br(void)
{
    if (depth == 8 || no >= NOPS - 1)
        return;
    if (st == ST_DONE)
        fresh();
    else if ((st == ST_ENTRY && ent[0]) || st == ST_VALUE)
        binop('*');                     /* "2(" is 2 x ( */
    gpos[depth++] = strlen(expr);
    ex_add("(");
    os[no++] = '(';
    st = ST_OP;
}

static void close_br(void)
{
    unsigned char g;
    if (!depth)
        return;
    commit();
    if (st == ST_OP)
        ot_num();
    ex_add(otext);
    ex_add(")");
    push(cur);
    while (no && !err && os[no - 1] != '(')
        reduce();
    --no;
    g = gpos[--depth];
    strncpy(otext, expr + g, sizeof otext - 1);
    otext[sizeof otext - 1] = 0;
    expr[g] = 0;
    otype = 1;
    memcpy(cur, vs[--nv], 5);
    st = ST_VALUE;
}

static void equals(void)
{
    if (st == ST_DONE)
        return;
    commit();
    if (st == ST_OP)
        ot_num();
    ex_add(otext);
    while (depth) {
        ex_add(")");
        --depth;
    }
    ex_add(" =");
    push(cur);
    while (no && !err) {
        if (os[no - 1] == '(')
            --no;
        else
            reduce();
    }
    memcpy(cur, vs[0], 5);
    nv = 0;
    memcpy(ans, cur, 5);
    st = ST_DONE;
    otype = 0;
}

/* a value (pi, Ans, MR) as the operand */
static void value(const unsigned char *v, const char *text)
{
    if (st == ST_DONE)
        fresh();
    memcpy(cur, v, 5);
    if (text) {
        strcpy(otext, text);
        otype = 2;
    } else
        ot_num();
    st = ST_VALUE;
}

static void function(unsigned char a)
{
    static const char *const names[] = { "sin", "cos", "tan", "sin\x88", "cos\x88", "tan\x88", "ln", "log",
                                         "exp", "10^" };
    commit();
    if (st == ST_DONE) {
        fresh();
        ot_num();
    } else if (st == ST_OP)
        ot_num();
    fn(a, cur);
    if (a < A_SQUARE)
        ot_wrap(names[a - A_SIN], "", 0);
    else if (a == A_SQUARE)
        ot_wrap("", "\x85", 1);
    else if (a == A_ROOT)
        ot_wrap("\x83", "", 1);
    else if (a == A_INV)
        ot_wrap("1/", "", 1);
    else
        ot_wrap("", "!", 1);
    st = ST_VALUE;
}

static void digit(unsigned char c)
{
    unsigned char n = strlen(ent), i, d = 0, pt = 0, ex = 0;
    if (st != ST_ENTRY) {
        if (st == ST_DONE)
            fresh();
        ent[0] = 0;
        n = 0;
        st = ST_ENTRY;
    }
    for (i = 0; i < n; ++i) {
        if (ent[i] == 'E')
            ex = i + 1;
        else if (ent[i] == '.')
            pt = 1;
        else if (ent[i] >= '0' && ent[i] <= '9' && !ex)
            ++d;
    }
    if (c == A_EE) {
        if (ex || n > 14)
            return;
        if (!d)
            strcpy(ent + n, "1"), ++n;  /* "EE 5": 1E5 */
        strcpy(ent + n, "E");
        return;
    }
    if (ex) {
        if (strlen(ent + ex) - (ent[ex] == '-') >= 2 || c == '.')
            return;
    } else if (c == '.') {
        if (pt)
            return;
        if (!d)
            ent[n++] = '0';
    } else {
        if (d >= 9)
            return;
        if (d == 1 && !pt && ent[n - 1] == '0') {
            ent[n - 1] = c;             /* (no leading zero) */
            return;
        }
    }
    ent[n] = c;
    ent[n + 1] = 0;
}

/* +/- : the entry's sign (its exponent's after EE), else the value's */
static void negate(void)
{
    char *e;
    if (st == ST_ENTRY) {
        e = strchr(ent, 'E');
        if (!e)
            e = ent - 1;
        if (e[1] == '-')
            memmove(e + 1, e + 2, strlen(e + 1));
        else if (strlen(ent) < 18) {
            memmove(e + 2, e + 1, strlen(e + 1) + 1);
            e[1] = '-';
        }
        return;
    }
    if (st == ST_DONE) {
        fresh();
        ot_num();
    } else if (st == ST_OP)
        ot_num();
    f_neg(cur);
    if (otype || cur[0])
        ot_wrap("-", "", 1);
    st = ST_VALUE;
}

static void percent(void)
{
    fnum h;
    commit();
    if (st == ST_DONE) {
        fresh();
        ot_num();
    } else if (st == ST_OP)
        ot_num();
    f_ul(h, 100);
    f2(F_DIV, cur, cur, h);
    if (no && (os[no - 1] == '+' || os[no - 1] == '-'))
        f2(F_MUL, cur, cur, vs[nv - 1]);        /* 200 + 10% = 220 */
    ot_wrap("", "%", 1);
    st = ST_VALUE;
}

static void back(void)
{
    unsigned char n = strlen(ent);
    if (st == ST_ENTRY && n) {
        ent[n - 1] = 0;
        if (n >= 2 && ent[n - 2] == '-' && n == 2)
            ent[0] = 0;
        return;
    }
    ent[0] = 0;                         /* the entry cleared */
    if (st == ST_DONE)
        fresh();
    st = ST_ENTRY;
}

static void memory(unsigned char a)
{
    commit();
    if (st == ST_ENTRY)
        st = ST_VALUE;
    if (a == A_MC)
        memset(mem, 0, 5);
    else
        f2(a == A_MPLUS ? F_ADD : F_SUB, mem, mem, cur);
    memset_ = mem[0] != 0;
}

static void redraw_second(void)
{
    static const unsigned char k[] = { K_2ND, 6, 7, 8, 12, 13 };
    unsigned char i;
    for (i = 0; i < sizeof k; ++i)
        draw_key(k[i]);
}

static void act(unsigned char a)
{
    unsigned char was2 = second;
#ifdef CALC_TEST
    calc_test_clock_reset();
#endif
    if (st == ST_ERR) {
        clear();
        if (a == A_CLEAR || a == A_BACK)
            goto out;
    }
    if (second && a >= A_SIN && a <= A_LOG) {
        if (a == A_SIN) a = A_ASIN;
        else if (a == A_COS) a = A_ACOS;
        else if (a == A_TAN) a = A_ATAN;
        else if (a == A_LN) a = A_EXP;
        else if (a == A_LOG) a = A_POW10;
    }
    err = 0;
    if ((a >= '0' && a <= '9') || a == '.' || a == A_EE)
        digit(a);
    else if (a == '+' || a == '-' || a == '*' || a == '/' || a == '^')
        binop(a);
    else if (a == '(')
        open_br();
    else if (a == ')')
        close_br();
    else if (a == '=')
        equals();
    else if (a == A_CLEAR)
        clear();
    else if (a == A_BACK)
        back();
    else if (a == A_NEG)
        negate();
    else if (a == A_PCT)
        percent();
    else if (a == A_PI)
        value(PI, "\x84");
    else if (a == A_ANS)
        value(ans, "Ans");
    else if (a == A_MR)
        value(mem, 0);
    else if (a == A_MC || a == A_MPLUS || a == A_MMINUS)
        memory(a);
    else if (a == A_DRG)
        rad ^= 1;
    else if (a == A_2ND) {
        second ^= 1;
        was2 = 2;
    } else if (a >= A_SIN && a <= A_FACT)
        function(a);
    if (a != A_2ND)
        second = 0;
    if (err) {
        st = ST_ERR;
        nv = no = depth = 0;            /* (the expression stays on show) */
    }
out:
    if (was2 != second)
        redraw_second();
    show();
    if (a == '=' || st == ST_ERR) {
        strcpy(tmp, "CALC = ");
        strcat(tmp, line);
        LogText(tmp);
    }
#ifdef CALC_TEST
    calc_test_clock_log("key");         /* (the key's work and the display) */
#endif
}

/* key i pressed: shown so for a few frames (track) */
static void flash(unsigned char i)
{
    if (pk != 0xFF)
        key_invert(pk);
    pk = i == K_EQ + COLS ? K_EQ : i;
    key_invert(pk);
    ptime = 6;
    plast = random;
}

/*---------------------------------------------------------------
  input
  ---------------------------------------------------------------*/
/* otherPressVec: a press on a key or the close box */
static void press(void)
{
    unsigned int x = mouseXPos, y = mouseYPosW, kx, kyy;
    unsigned char col, row, i;
    if (mouseData & 0x80)
        return;
    if (vr_win_hit(&win, x, y) == VW_XCLOSE) {
        calc_close();
        return;
    }
    if (x < x0 + KX || y < y0 + ky)
        return;
    kx = x - x0 - KX;
    kyy = y - y0 - ky;
    col = kx / (BW + GAP);
    row = kyy / (bh + GAP);
    if (col >= COLS || row >= ROWS || kx % (BW + GAP) >= BW)
        return;
    i = row * COLS + col;
    if (kyy % (bh + GAP) >= bh && i != K_EQ)
        return;
    flash(i);
    act(keys[i]);
}

static void typed(void)
{
    unsigned char c = keyData, i;
    if (c == KEY_ESC) {
        calc_close();
        return;
    }
    for (i = 0; i < sizeof typed_in; ++i)
        if (typed_in[i] == c) {
            c = typed_out[i];
            break;
        }
    if (i == sizeof typed_in && c >= 0x80)
        return;                         /* (PgUp, F9 ...: not the actions' codes) */
    for (i = 0; i < COLS * ROWS; ++i)
        if (keys[i] == c)
            break;
    if (i == COLS * ROWS) {             /* (an inverse: on its function's key) */
        static const unsigned char inv[] = { A_ASIN, A_ACOS, A_ATAN, A_EXP, A_POW10 };
        static const unsigned char on[] = { 6, 7, 8, 12, 13 };
        for (i = 0; i < sizeof inv && inv[i] != c; ++i)
            ;
        if (i == sizeof inv)
            return;
        flash(on[i]);
    } else
        flash(i);
    act(c);
}

/* appMain: the pressed key back after its frames; the I-beam over the
   display (it takes typed digits), the arrow elsewhere (DECISIONS V51) */
static void track(void)
{
    unsigned int x, y;
    unsigned char r = random;
    if (pk != 0xFF && r != plast) {
        plast = r;
        if (!--ptime) {
            key_invert(pk);
            pk = 0xFF;
        }
    }
    do {
        x = mouseXPos;
        y = mouseYPosW;
    } while (x != mouseXPos || y != mouseYPosW);
    SetPointer(x >= x0 + KX && x < x0 + W - KX && y >= y0 + DY && y < y0 + DY + dh ? PTR_IBEAM : PTR_ARROW);
}

int main(void)
{
#ifdef CALC_TEST
    calc_test_clock_log("open");        /* since Paint's GetFile */
#endif
#ifdef CALC_LOWRES
    SetVideoMode(MODE_320x240);
#endif
#ifdef CALC_DARK
    {
        static unsigned char p[PREFS_SIZE];
        SysPrefs(PREFS_GET, p);
        p[PREFS_LOOK] |= LOOK_DARK;
        SysPrefs(PREFS_SET, p);
    }
#endif
    if (screenHeight >= 320) {
        bh = 24;
        dh = 48;
    } else {
        bh = 16;
        dh = 40;
    }
    ky = DY + dh + 8;
    wh = ky + ROWS * bh + (ROWS - 1) * GAP + 8;
    x0 = ((screenWidth - W) / 2) & ~7;  /* (card aligned: the colours) */
    y0 = ((screenHeight - wh) / 2) & ~7;
    clear();
    draw();
    otherPressVec = VR_FN(press);
    keyVector = VR_FN(typed);
    appMain = VR_FN(track);
    LogText("CALC RUNNING");
#ifdef CALC_TEST
    calc_test_start();
#endif
    return 0;
}
