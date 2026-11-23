/* VeraBASIC, the editor (DECISIONS V93): B_HELP, the help viewer, F1 and
   the status bar's syntax lines.

   The help is plain Latin-1 text in /VERANDA/HELP (VR_HELPDIR; the top
   folder when there is none): KEYWORDS.HLP (tools/vbgen.py, from
   vbasic/keywords.tbl), TUTORIAL.HLP, ERRORS.HLP, EDITOR.HLP, MANUAL.HLP (V99). Its markup
   (docs/vbasic/FORMAT.md): "= Name" starts a page, "@Word" and "@{A few
   words}" are links to pages, lines indented are code. A file is read
   into RAM banks the first time it is wanted (and given back before a
   program runs); a page is found by its name (any case), in its own file
   first, then in the others.

   The viewer takes the text's place: the page's lines in 8 x 8 cards,
   headings and links bold, the chosen link reversed; Up, Down, PgUp,
   PgDn scroll, Tab and Shift+Tab choose a link, Return (or a click)
   follows it, Backspace goes back, Esc closes. The status bar shows the
   keys and the page.

   MIT licence (LICENSE). */
#include <string.h>
#include <theme.h>
#include <vrwin.h>
#include "ide.h"

static const char *const files[HF_N] = { "KEYWORDS.HLP", "TUTORIAL.HLP", "ERRORS.HLP", "EDITOR.HLP",
    "MANUAL.HLP" };
static unsigned char fbank[HF_N];       /* a file's run of banks (0: not read) */
static unsigned int flen[HF_N];
static unsigned char cur_f;             /* the page's file */
static unsigned int pg_at, pg_end;      /* the page in its file: its first line ("= ..."), its end */
#pragma bss-name (push, "B4BSS")        /* (this bank's own: the kernel reads none of it) */
#define MAXL 320                        /* (tools/vbgen.py HLP_MAXL: no page is longer) */
static unsigned int lofs[MAXL];         /* each line's offset (from pg_at) */
static unsigned int nl, ptop;           /* the page's lines, the first shown */
#define MAXK 48
static unsigned int k_line[MAXK];       /* the links: their line, column, length, target */
static unsigned char k_col[MAXK], k_len[MAXK];
static unsigned int k_tat[MAXK];        /* (the target's text: its offset in the page) */
static unsigned char k_tlen[MAXK];
static unsigned char nk, ksel;
static char hist[8][40];                /* Backspace: the pages before */
static unsigned char histf[8], nh;
#pragma bss-name (pop)
static char line[82];
static char name[40];
#define HW SB_X                         /* the page's columns (the scroll bar after them) */
static const unsigned char sbk[6] = { 0, KEY_UP, KEY_PGUP, 0, KEY_PGDN, KEY_DOWN };

/*---------------------------------------------------------------
  the files
 ---------------------------------------------------------------*/
/* n bytes of file f at offset o into main RAM */
static void fget(unsigned char f, unsigned int o, void *to, unsigned int n)
{
    unsigned int k;
    unsigned char *p = to;
    while (n) {
        k = 8192 - (o & 0x1FFF);
        if (k > n)
            k = n;
        BankCopy((void *)(0xA000 + (o & 0x1FFF)), p, k, fbank[f] + (unsigned char)(o >> 13), 0);
        p += k;
        o += k;
        n -= k;
    }
}

static unsigned char fload(unsigned char f)
{
    unsigned char h, n, i;
    unsigned int got;
    if (fbank[f])
        return 1;
    strcpy(line, VR_HELPDIR);           /* (the kernel reads names below $A000) */
    if (ChDir(line)) {                  /* (a card without the layout: the top folder) */
        line[0] = '/';
        line[1] = 0;
        ChDir(line);
    }
    strcpy(line, files[f]);
    h = FOpen(line, 'r');
    if (h < 2) {
        doc_dir();
        return 0;
    }
    n = (unsigned char)(FSize(h) >> 13) + 1;    /* (the banks it needs, no more: DECISIONS V99, */
    if (n > 8)                          /* MANUAL.HLP beside KEYWORDS.HLP at rest) */
        n = 8;
    for (; n && !(fbank[f] = BankAlloc(n)); --n)
        ;
    flen[f] = 0;
    if (fbank[f])
        for (i = 0; i < n; ++i) {
            fr_bank = fbank[f] + i;
            fr_at = (void *)0xA000;
            fr_n = i == 7 ? 8191 : 8192;    /* (64 KB less one) */
            got = ide_fread(h);
            flen[f] += got;
            if (got < fr_n)
                break;
        }
    FClose(h);
    doc_dir();
    return fbank[f] != 0;
}

/* the help's banks back (a program will run: VeraBASIC's memory is its) */
void help_free(void)
{
    unsigned char f;
    for (f = 0; f < HF_N; ++f)
        if (fbank[f]) {
            BankFree(fbank[f]);
            fbank[f] = 0;
        }
}

/* the letters of a and b equal, any case? (b: n characters) */
static unsigned char same(const char *a, const char *b, unsigned char n)
{
    unsigned char i, x, y;
    for (i = 0; i < n; ++i) {
        x = a[i];
        y = b[i];
        if (x >= 'a' && x <= 'z')
            x -= 32;
        if (y >= 'a' && y <= 'z')
            y -= 32;
        if (x != y)
            return 0;
    }
    return a[n] == 0;
}

/* page `name` in file f: pg_at, pg_end; 0 if not there */
static unsigned char find_page(unsigned char f)
{
    unsigned int o = 0, i;
    unsigned char n = strlen(name), k;
    if (!fload(f))
        return 0;
    while (o < flen[f]) {
        k = flen[f] - o > 80 ? 80 : flen[f] - o;
        fget(f, o, line, k);
        if (line[0] == '=' && line[1] == ' ' && k >= n + 2 && (k == n + 2 || line[n + 2] == 10)
            && same(name, line + 2, n)) {
            pg_at = o;
            /* its end: the next "\n= " */
            for (o += n + 2; o < flen[f]; o += i) {
                k = flen[f] - o > 80 ? 80 : flen[f] - o;
                fget(f, o, line, k);
                for (i = 0; i + 2 < k; ++i)
                    if (line[i] == 10 && line[i + 1] == '=' && line[i + 2] == ' ') {
                        pg_end = o + i + 1;
                        return 1;
                    }
                if (!i)
                    i = 1;
            }
            pg_end = flen[f];
            return 1;
        }
        for (i = 0; i < k && line[i] != 10; ++i)    /* the next line */
            ;
        o += i + 1;
    }
    return 0;
}

/*---------------------------------------------------------------
  the page
 ---------------------------------------------------------------*/
/* line i of the page into line[] (0-ended, LF gone); its length */
static unsigned char get_line(unsigned int i)
{
    unsigned int a = lofs[i], b = i + 1 < nl ? lofs[i + 1] : pg_end - pg_at;
    unsigned char n = b - a > 81 ? 81 : b - a;
    fget(cur_f, pg_at + a, line, n);
    if (n && line[n - 1] == 10)
        --n;
    line[n] = 0;
    return n;
}

/* a page line (line[], n bytes) as shown, into out (from column 1, 77 at
   most): the markup's @ and braces gone; with mark, the links found: their
   line (li), shown column and length, their target's place in the page */
static unsigned char shown(unsigned char n, char *out, unsigned int li, unsigned int o, unsigned char mark)
{
    unsigned char j = 0, d = 0, c, a;
    while (j < n && d < HW - 1) {
        if (line[j] == '@' && j + 1 < n && line[j + 1] > ' ') {
            c = j + 1;
            a = d;
            if (line[c] == '{') {
                for (++c; c < n && line[c] != '}'; ++c)
                    if (d < HW - 1)
                        out[d++] = line[c];
                if (mark && nk < MAXK) {
                    k_tat[nk] = o + j + 2;
                    k_tlen[nk] = c - j - 2;
                }
                ++c;
            } else {
                while (c < n && line[c] > ' ' && line[c] != ',' && line[c] != '.' && line[c] != ')'
                       && line[c] != ':' && line[c] != ';') {
                    if (d < HW - 1)
                        out[d++] = line[c];
                    ++c;
                }
                if (mark && nk < MAXK) {
                    k_tat[nk] = o + j + 1;
                    k_tlen[nk] = c - j - 1;
                }
            }
            if (mark && nk < MAXK && k_tlen[nk] && k_tlen[nk] < 40) {
                k_line[nk] = li;
                k_col[nk] = a + 1;
                k_len[nk] = d - a;
                ++nk;
            }
            j = c;
            continue;
        }
        out[d++] = line[j++];
    }
    return d;
}

/* the page's lines and links */
static void layout(void)
{
    unsigned int o = 0, i;
    unsigned char n;
    nl = nk = 0;
    while (pg_at + o < pg_end && nl < MAXL) {
        lofs[nl] = o;
        n = pg_end - pg_at - o > 81 ? 81 : pg_end - pg_at - o;
        fget(cur_f, pg_at + o, line, n);
        for (i = 0; i < n && line[i] != 10; ++i)
            ;
        shown((unsigned char)i, tk_line, nl, o, 1);
        o += i + 1;
        ++nl;
    }
}

/* a page line as shown into tk_line (the headings and links bold, the
   chosen link reversed: their styles in lexcls) */
static void show_line(unsigned int i, unsigned char y)
{
    unsigned char n, j, k, f;
    memset(tk_line, ' ', 80);
    memset(lexcls, 0, 80);
    if (i < nl) {
        n = get_line(i);
        if (line[0] == '=' && line[1] == ' ') {     /* the heading */
            memcpy(line, line + 2, n - 2);
            n -= 2;
            memset(lexcls, 2, 80);
        }
        shown(n, tk_line + 1, i, 0, 0);
        for (k = 0; k < nk; ++k)
            if (k_line[k] == i)
                for (j = k_col[k]; j < k_col[k] + k_len[k] && j < HW; ++j)
                    lexcls[j] = k == ksel ? 3 : 2;
    }
    for (j = 0; j < HW; j = k) {
        f = lexcls[j];
        for (k = j + 1; k < HW && lexcls[k] == f; ++k)
            ;
        PutCards(tk_line + j, vb_font, j, k - j, TY + y * 8, f);
    }
}

/* the status bar (Sunroom, V149: vr_win_status, the UI font; its texts
   in main RAM: overlay 7's code reads them) */
static void bar(void)
{
    *tk_put_s(tk_put_s(tk_line, "Help: "), name) = 0;
    strcpy(IDE_OUT, "Esc closes    Tab a link    Return goes    Bksp back");
    vr_win_status(&tk_win, tk_line, IDE_OUT);
}

static void draw(void)
{
    unsigned char y;
    dispBufferOn = ST_WR_FORE;
    if (colour_on)
        ColorRect(0, HW, TROW, ROWS, 0);
    for (y = 0; y < ROWS; ++y)
        show_line(ptop + y, y);
    bar();
    sb_first = ptop;                    /* the scroll bar (Sunroom, V149) */
    sb_total = nl;
    XCALL(B_FMT, sb_draw);
}

/* the link ksel shown (the page scrolled to it) */
static void to_link(void)
{
    if (ksel >= nk)
        return;
    if (k_line[ksel] < ptop)
        ptop = k_line[ksel];
    else if (k_line[ksel] >= ptop + ROWS)
        ptop = k_line[ksel] - ROWS + 1;
}

static unsigned char open_page(unsigned char f)
{
    unsigned char g;
    if (!find_page(f)) {
        for (g = 0; g < HF_N; ++g)
            if (g != f) {
                if (find_page(g)) {
                    f = g;
                    goto found;
                }
                if (g != cur_f && fbank[g]) {   /* (not there: its banks back, so that the next */
                    BankFree(fbank[g]);         /* file has them: DECISIONS V99, MANUAL.HLP) */
                    fbank[g] = 0;
                }
            }
        return 0;
    }
found:
    cur_f = f;
    ptop = 0;
    layout();
    ksel = nk ? 0 : 0xFF;
    ide_log("IDE HELP ");
    ide_log(name);
    ide_logn(" ", nl);
    ide_logn(" ", nk);
    ide_log("\n");
    return 1;
}

/* the viewer up at help_req (in help_file) */
void help_show(void)
{
    char title[48];
    strcpy(name, help_req);
    if (!open_page(help_file)) {
        strcpy(title, "No help page: ");
        strcat(title, name);
        view_status_msg(title);
        if (!help_open)
            return;
    }
    if (!help_open) {
        help_open = 1;
        nh = 0;
        strcpy(title, "VeraBASIC help");
        vr_win_title(&tk_win, title);
    }
    draw();
}

static void close_help(void)
{
    help_open = 0;
    need_fix = 1;
    XCALL(B_VIEW, view_all);
}

/* a link followed: the page before kept */
static void follow(unsigned char k)
{
    unsigned char n;
    char keep[40];
    if (k >= nk)
        return;
    strcpy(keep, name);
    n = k_tlen[k];
    fget(cur_f, pg_at + k_tat[k], name, n);
    name[n] = 0;
    if (nh == 8) {
        memmove(hist[0], hist[1], 7 * 40);
        memmove(histf, histf + 1, 7);
        --nh;
    }
    strcpy(hist[nh], keep);
    histf[nh++] = cur_f;
    if (!open_page(cur_f)) {
        strcpy(name, keep);
        open_page(cur_f);
        --nh;
        Beep();
    }
    draw();
}

/* the viewer's keys (keyData 0: a press of the pointer) */
void help_key(void)
{
    unsigned char k = keyData, m = keyDataMods, i;
    unsigned int x, y;
    if (!keyData && !(pressFlag & SET_KEYPRESS)) {   /* a press */
        if (mouseData & 0x80)
            return;
        x = mouseXPos >> 3;
        y = mouseYPosW;
        if (y < TY || y >= TY + ROWS * 8)
            return;
        if (x >= HW) {                  /* the scroll bar: as the keys */
            sb_y = y;
            XCALL(B_FMT, sb_hit);
            k = sbk[sb_part];
            m = sb_part == VS_BACK || sb_part == VS_FWD ? KEYM_ARROW : 0;
            goto keys;
        }
        y = ptop + ((y - TY) >> 3);
        for (i = 0; i < nk; ++i)
            if (k_line[i] == y && x >= k_col[i] && x < k_col[i] + k_len[i]) {
                ksel = i;
                follow(i);
                return;
            }
        return;
    }
    keyData = 0;
keys:
    if (m & KEYM_ARROW) {
        if (k == KEY_UP && ptop)
            --ptop;
        else if (k == KEY_DOWN && ptop + ROWS < nl)
            ++ptop;
        else
            return;
        draw();
        return;
    }
    switch (k) {
    case KEY_ESC:
        close_help();
        return;
    case KEY_PGUP:
        ptop = ptop > ROWS - 1 ? ptop - (ROWS - 1) : 0;
        break;
    case KEY_PGDN:
        if (ptop + ROWS < nl)
            ptop += ROWS - 1;
        break;
    case KEY_TAB:
        if (!nk)
            return;
        if (m & 1)
            ksel = ksel && ksel != 0xFF ? ksel - 1 : nk - 1;
        else
            ksel = ksel + 1 < nk ? ksel + 1 : 0;
        to_link();
        break;
    case CR:
        follow(ksel);
        return;
    case 8:
        if (!nh)
            return;
        --nh;
        strcpy(name, hist[nh]);
        open_page(histf[nh]);
        break;
    case KEY_F1:
        strcpy(name, "Contents");
        open_page(HF_KEYWORDS);
        break;
    default:
        return;
    }
    draw();
}

