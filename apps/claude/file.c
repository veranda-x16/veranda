/* Veranda Claude and Veranda Ask: code blocks, files, what a turn sends,
   compaction, the usage (a bank of its own: overlay 5 in Claude, 6 in
   Ask; DECISIONS V123).

   Code blocks: Markdown's fenced blocks (a line ``` with a language,
   the code, a line ```) in the conversation, found when a turn ends;
   their rows marked (R_CODE: shaded, or a rule at their left in
   Classic), the opening fence's row drawn as its labels: the language,
   [Copy], [Save...] and, for the X16's BASIC (the tag basic, bas,
   x16basic, commodore-basic, or numbered lines), [Save .PRG]: the
   program tokenized as the ROM's BASIC stores it (the ROM's crunch,
   ported: tools/x16basic.py is the host's reference), so that LOAD and
   RUN take it. The Code menu: the last block copied or saved, a block
   by its number shown, the last reply copied, a file attached.

   A file attached (the SDK's Open box): its text goes with the next
   question as a fenced block ("Attached file NAME:"): plain text
   (Latin-1), Veranda Write's CWRD (its text only), a tokenized BASIC
   .PRG (made text: the ROM's keywords, {XX} for the bytes with no plain
   form). A later reply's block in the same language is the file's next
   version: its [Save...] offers the file's own name and folder (a PRG
   tokenized again).

   What a turn sends (plan, before each): the Remember setting (the
   first message sent: all, the last 10 or 4 before the question, or the
   question alone, always from a user's message), max_tokens (short
   answers: 1024; a compaction: 500), the model (a compaction and
   Ctrl+Return: the cheapest), old code blocks shortened to one line
   (one saved or copied before the last reply, or two turns old; an
   attached file's older versions: only its newest is ever sent whole).
   The screen keeps everything; only the request changes.

   Compaction: one request to the cheapest model, the conversation and
   a request to summarise it; its answer kept as a message sent as the
   user's ("Summary of our conversation so far: ..."), a short reply
   after it (the turns alternate), the turns before it shown dimmed and
   no longer sent. Automatic (the Conversation page) when what is sent is
   longer than 6 KB.

   The usage: the last turn's tokens on the status bar, the
   conversation's on the Conversation page, with the API key an
   estimate in dollars (the prices below).

   This bank is at $A000 while its code runs, as appBank's ui.c is
   otherwise: nothing here calls ui.c; c_ui says what ui.c draws after.
   What the kernel reads (names, buffers, dialog texts) is in main RAM.

   MIT licence (see LICENSE). */
#include <veranda.h>
#include <string.h>
#include <theme.h>
#include <vrpath.h>
#include <vrnet.h>
#include <vrser.h>
#include "claude.h"
#ifdef ASK
#pragma code-name ("OVERLAY7")
#pragma rodata-name ("OVL7RO")
#pragma bss-name ("OVL7BSS")
#pragma data-name ("OVL7DATA")
#else
#pragma code-name ("OVERLAY6")
#pragma rodata-name ("OVL6RO")
#pragma bss-name ("OVL6BSS")
#pragma data-name ("OVL6DATA")
#endif
#include "basictok.h"

static const char *const l_ext[5] = { "CODE.TXT", "PROGRAM.BAS", "CODE.ASM", "CODE.C", "CODE.PY" };
static unsigned int af_lines, af_size;
static unsigned char at_last;


/*---------------------------------------------------------------- small helpers */

/* the store's bytes through a window (main RAM: cs_txt, which only drawing
   uses; code.c draws nothing while it reads) */
static unsigned int wa = 0xFFFF;
static unsigned char __fastcall__ sb(unsigned int a)
{
    if (a < wa || a >= wa + 64) {
        wa = a;
        st_copy(a, cs_txt, 64);         /* (past st_used: whatever is there, never read) */
    }
    return cs_txt[a - wa];
}

static unsigned char __fastcall__ lower(unsigned char c)
{
    return c >= 'A' && c <= 'Z' ? c + 32 : c;
}

/*---------------------------------------------------------------- output */

static unsigned int ob_n;
static unsigned char sv_h;
static unsigned char sv_bad;

static void ob_flush(void)
{
    if (ob_n) {
        if (FWrite(sv_h, dtext, ob_n))
            sv_bad = 1;
    }
    ob_n = 0;
}

static void __fastcall__ ob(unsigned char c)
{
    dtext[ob_n++] = c;
    if (ob_n >= 200)
        ob_flush();
}

/* a byte of the font in Veranda's set ('?': a private glyph; V143) */
static unsigned char __fastcall__ latin(unsigned char c)
{
    return c == '\t' || (c >= 32 && c < 127) || c >= 0xA0 ? c : '?';
}

/*---------------------------------------------------------------- the ROM's BASIC: text to tokens and back */

/* (crunch's buffers: the line's PETSCII in line from tk_x, the tokens into
   rbuf from 4: fixed, so the code is short) */
#define IN ((unsigned char *)line)
static unsigned char tk_dores, tk_x, tk_y, tk_n;
static const unsigned char *tk_t;

static void __fastcall__ tk_out(unsigned char c)
{
    rbuf[4 + tk_y++] = c;
}

/* a keyword of table tk_t at IN[tk_x] (crunch's search: lower case as
   upper); tk_n counts the words passed; 1: found (tk_x past it) */
static unsigned char tk_match(void)
{
    unsigned char y = 0, i, j, c;
    while (tk_t[y]) {
        i = tk_x;
        j = y;
        for (;;) {
            c = IN[i];
            if (c >= 97 && c < 128)
                c -= 32;
            c -= tk_t[j];
            if (!c) {
                ++i;
                ++j;
                continue;
            }
            if (c == 0x80) {
                tk_x = i + 1;
                return 1;
            }
            break;
        }
        ++tk_n;
        while (!(tk_t[y] & 0x80))
            ++y;
        ++y;
    }
    return 0;
}

/* the line from IN[tk_x] crunched (the ROM's way) into rbuf + 4: tk_y bytes */
static void crunch(void)
{
    unsigned char c;
    tk_dores = 4;
    tk_y = 0;
    for (;;) {
        c = IN[tk_x];
        if (c >= 128) {
            ++tk_x;
            if (c == 0xFF)
                tk_out(c);
            continue;
        }
        if (!c)
            return;
        if (c == '"') {
            do
                tk_out(IN[tk_x++]);
            while (IN[tk_x] && IN[tk_x] != '"');
            if (!IN[tk_x])
                return;
            tk_out(IN[tk_x++]);
            continue;
        }
        if (c == ' ' || tk_dores & 0x40 || (c >= '0' && c < '<')) {
            tk_out(c);
            ++tk_x;
            if (c == ':')
                tk_dores = 0;
            continue;
        }
        if (c == '?') {
            tk_out(0x99);
            ++tk_x;
            continue;
        }
        tk_n = 0;
        tk_t = bt_v2;
        if (tk_match()) {
            tk_out(c = 0x80 | tk_n);
            if (c == 0x83)
                tk_dores = 0x49;
            if (c == 0x8F) {
                while (IN[tk_x])
                    tk_out(IN[tk_x++]);
                return;
            }
            continue;
        }
        tk_n = 0;
        tk_t = bt_x2;
        if (tk_match() || (tk_t = bt_x3, tk_match())) {
            tk_out(0xCE);
            tk_out(tk_n < BT_NSTAT ? 0x80 | tk_n : tk_n - BT_NSTAT + 0xD0);
            continue;
        }
        tk_out(c);
        ++tk_x;
        if (c == ':')
            tk_dores = 0;
    }
}

static unsigned char __fastcall__ hexv(unsigned char c)
{
    c = lower(c);
    return c >= '0' && c <= '9' ? c - '0' : c >= 'a' && c <= 'f' ? c - 'a' + 10 : 0xFF;
}

/* the store's line a .. e as PETSCII into IN (letters to $41-$5A, {XX},
   pi, a tab a space, the rest '?'); 0: too long */
static unsigned char __fastcall__ petscii(unsigned int a, unsigned int e)
{
    unsigned char n = 0, c, h, l;
    for (; a < e; ++a) {
        if (n >= 190)
            return 0;
        c = sb(a);
        if (c == '{' && a + 3 < e && sb(a + 3) == '}' && (h = hexv(sb(a + 1))) != 0xFF && (l = hexv(sb(a + 2))) != 0xFF) {
            c = h << 4 | l;
            a += 3;
        } else if (c >= 'a' && c <= 'z')
            c -= 32;
        else if (c == '\t')
            c = ' ';
        else if (c == 0x80)            /* (pi: the font's private $80, V143) */
            c = 0xFF;
        else if (c < 32 || c >= 127)
            c = '?';
        IN[n++] = c;
    }
    IN[n] = 0;
    return 1;
}

static unsigned int tk_line;            /* the error's line (1: the first) */
static const char *tk_err;

/* the block a .. e as a PRG: written (sv_h) or only checked (sv_h 0); 0: tk_err */
static unsigned char __fastcall__ tokenize(unsigned int a, unsigned int e)
{
    static unsigned int le, num, last, addr;
    static unsigned long lnum;
    static unsigned char k, any;
    last = any = 0;
    addr = 0x0801;
    tk_line = 0;
    if (sv_h) {
        ob(1);
        ob(8);
    }
    for (; a < e; a = le + 1) {
        ++tk_line;
        for (le = a; le < e && sb(le) != '\n'; ++le)
            ;
        tk_err = "is too long";
        if (!petscii(a, le))
            return 0;
        for (tk_x = 0; IN[tk_x] == ' '; ++tk_x)
            ;
        if (!IN[tk_x])
            continue;
        tk_err = "has no line number";
        if (IN[tk_x] < '0' || IN[tk_x] > '9')
            return 0;
        for (lnum = 0; (k = IN[tk_x]) == ' ' || (k >= '0' && k <= '9'); ++tk_x)
            if (k != ' ' && lnum < 100000ul)
                lnum = lnum * 10 + k - '0';
        tk_err = "has a number past 63999";
        if (lnum > 63999)
            return 0;
        num = lnum;
        tk_err = "comes after a higher number";
        if (any && num <= last)
            return 0;
        crunch();
        tk_err = "is too long";
        if (tk_y > 250)
            return 0;
        if (!tk_y)
            continue;
        any = 1;
        last = num;
        addr += 4 + tk_y + 1;
        if (sv_h) {
            rbuf[0] = addr;
            rbuf[1] = addr >> 8;
            rbuf[2] = num;
            rbuf[3] = num >> 8;
            rbuf[4 + tk_y] = 0;
            for (k = 0; k < 5 + tk_y; ++k)
                ob(rbuf[k]);
        }
    }
    if (!any) {
        tk_err = "(none has a number)";
        tk_line = 0;
        return 0;
    }
    if (sv_h) {
        ob(0);
        ob(0);
    }
    return 1;
}

/*---------------------------------------------------------------- save */

/* name (gph) in the folder: asked before it is replaced; the handle, 0: not written */
static unsigned char __fastcall__ open_new(unsigned char docs)
{
    unsigned char h, j;
    vr_cd(VR_DOCS);
    h = FOpen(gph, 'r');
    if (h >= 2 && h <= 4) {
        j = dosStatus < 20;
        FClose(h);
        if (j) {
            strcpy(line, "Replace ");
            strncat(line, gph, 40);
            strcat(line, "?");
            if (!yesno(line, docs ? "(it is in /DOCUMENTS already)" : "(the file you attached)"))
                return 0;
        }
    }
    h = FOpen(gph, 'w');
    if (h < 2 || h > 4) {
        message("The file cannot be written:", gph);
        return 0;
    }
    return h;
}

/* .BAS (or any) to .PRG */
static void prg_name(void)
{
    char *d = strrchr(gph, '.');
    if (d)
        *d = 0;
    if (strlen(gph) > 63 - 4)
        gph[63 - 4] = 0;
    strcat(gph, ".PRG");
}

static void __fastcall__ save_block(unsigned char j, unsigned char prg)
{
    struct blk *b = &B[j];
    unsigned char h, file = (b->fl & B_FILE) && !strncmp(b->name, af_name, sizeof b->name - 1);
    unsigned int a, e = b->ce;
    char *p;
    if (prg && b->lang != L_BAS)
        prg = 0;
    if (file && af_prg && b->lang == L_BAS)
        prg = 1;                        /* (a .PRG attached: saved back as one) */
    wa = 0xFFFF;
    if (prg) {
        sv_h = 0;
        if (!tokenize(b->ca, b->ce)) {
            strcpy(line, "Not a BASIC program: line ");
            unum(line + strlen(line), tk_line);
            if (!tk_line)
                strcpy(line, "Not a BASIC program:");
            message(line, tk_err);
            return;
        }
    }
    strcpy(gph, file ? af_name : l_ext[b->lang]);
    if (prg && !file)
        prg_name();
    if (!ask(prg ? "Save the program (tokenized, .PRG) as:" : file ? "Save the code back to its file as:" :
             "Save the code to /DOCUMENTS as:", gph, 63) || !gph[0])
        return;
    if (prg && !strchr(gph, '.'))
        strcat(gph, ".PRG");
    file = file && !strcmp(gph, af_name);
    h = open_new(!file);
    if (!h)
        return;
    sv_h = h;
    sv_bad = 0;
    ob_n = 0;
    if (prg)
        tokenize(b->ca, b->ce);
    else {
        if (e > b->ca && sb(e - 1) == '\n')
            --e;
        for (a = b->ca; a < e; ++a)
            if (sb(a) == '\n') {
                ob('\r');
                ob('\n');
            } else
                ob(latin(sb(a)));
        if (e > b->ca) {
            ob('\r');
            ob('\n');
        }
    }
    ob_flush();
    sv_bad |= FClose(h) != 0;
    sv_h = 0;
    c_ui |= CU_STATUS;
    if (sv_bad) {
        message("The file cannot be written:", gph);
        return;
    }
    b->fl |= B_SAVED;
    if (!(b->fl & B_FILE))
        strncpy(b->name, gph, sizeof b->name - 1);
    strcpy(msg, "Saved ");
    p = msg + 6;
    if (!file) {
        strcpy(p, "to /DOCUMENTS/");
        p += 14;
    }
    strncpy(p, gph, 40);
    p[40] = 0;
    strcat(msg, prg ? " (a program: LOAD and RUN it)." : ".");
    st_dirty = 0;
}

/* code.c's [Save...] and [Save .PRG]: block c_blk (c_prg) */
void c_saveblk(void)
{
    save_block(c_blk, c_prg == 2 ? B[c_blk].lang == L_BAS && yesno("Save it as a program (.PRG) that", "the X16's BASIC can LOAD and RUN?") : c_prg);
}

/* a PRG's bytes as text, a byte at a time (dt_byte), into ob's output */
static unsigned char dt_st, dt_q, dt_rem, dt_esc;
static unsigned int dt_num;
static unsigned char dt_bad;
static void (*dt_out)(unsigned char c);

static void __fastcall__ dt_s(const char *s)
{
    while (*s)
        dt_out(*s++);
}

static void __fastcall__ dt_hex(unsigned char c)
{
    static const char hx[] = "0123456789ABCDEF";
    dt_out('{');
    dt_out(hx[c >> 4]);
    dt_out(hx[c & 15]);
    dt_out('}');
}

/* the word of token t (ext: the byte after $CE) */
static void __fastcall__ dt_word(const unsigned char *t, unsigned char i)
{
    unsigned char y = 0;
    while (i--) {
        while (!(t[y] & 0x80))
            ++y;
        ++y;
    }
    while (!(t[y] & 0x80))
        dt_out(t[y++]);
    dt_out(t[y] & 0x7F);
}

static void __fastcall__ dt_byte(unsigned char c)
{
    char nb_[8];
    switch (dt_st) {
    case 0: dt_bad = c != 1; ++dt_st; return;
    case 1: dt_bad |= c != 8; ++dt_st; return;
    case 2: dt_num = c; ++dt_st; return;           /* (the link: only whether it is 0 matters) */
    case 3:
        if (!dt_num && !c) {
            dt_st = 9;                  /* (the end) */
            return;
        }
        ++dt_st;
        return;
    case 4: dt_num = c; ++dt_st; return;
    case 5:
        dt_num |= c << 8;
        unum(nb_, dt_num);
        dt_s(nb_);
        dt_out(' ');
        dt_q = dt_rem = dt_esc = 0;
        ++dt_st;
        return;
    case 6:
        if (dt_esc) {
            dt_esc = 0;
            if (c >= 0xD0 && c - 0xD0 < 15)
                dt_word(bt_x3, c - 0xD0 + BT_NSTAT - 44);
            else if (c >= 0x80 && c - 0x80 < 44)
                dt_word(bt_x2, c - 0x80);
            else if (c >= 0x80 && c - 0x80 < BT_NSTAT)
                dt_word(bt_x3, c - 0x80 - 44);
            else {
                dt_hex(0xCE);
                dt_byte(c);
            }
            return;
        }
        if (!c) {
            dt_out('\n');
            dt_st = 2;
            return;
        }
        if (c == '"')
            dt_q ^= 1;
        if (c >= 0x80 && c != 0xFF && !dt_q && !dt_rem) {
            if (c == 0xCE) {
                dt_esc = 1;
                return;
            }
            if (c <= 0xCB) {
                dt_word(bt_v2, c - 0x80);
                dt_rem = c == 0x8F;
                return;
            }
        }
        if (c == 0xFF)
            dt_out(0x80);
        else if (c >= 32 && c <= 0x5F)
            dt_out(c);
        else if (c >= 0x7C && c <= 0x7E)
            dt_out(c);
        else
            dt_hex(c);
        return;
    }
}

/*---------------------------------------------------------------- a file attached */

static unsigned char cw_st, cw_skip;
static unsigned long cw_n;
static unsigned char cw_hdr[8];
static unsigned char cw_i, cw_text;
static unsigned char at_cr;
static unsigned int at_n, at_lines;
static unsigned char at_store, at_bad;

/* a character of the text made (CP437): counted, or into the store */
static void __fastcall__ at_out(unsigned char c)
{
    ++at_n;
    at_last = c;
    if (c == '\n')
        ++at_lines;
    if (at_store) {
        dtext[ob_n++] = c;
        if (ob_n >= 200) {
            if (!st_append(dtext, ob_n))
                at_bad = 1;
            ob_n = 0;
        }
    }
}

/* a Latin-1 byte of a text file (CR, LF, CR LF: a line feed) */
static void __fastcall__ at_text(unsigned char c)
{
    if (c == '\n' && at_cr) {
        at_cr = 0;
        return;
    }
    at_cr = c == '\r';
    if (c == '\r' || c == '\n')
        at_out('\n');
    else if (c == '\t' || (c >= 32 && c < 127))
        at_out(c);
    else if (c >= 160)
        at_out(c);                      /* (Veranda's set, V143) */
}

/* a byte of a CWRD file: its TEXT chunk's characters, without the codes */
static void __fastcall__ at_cwr(unsigned char c)
{
    if (cw_st == 0) {                   /* the header, then a chunk's tag and length */
        cw_hdr[cw_i++] = c;
        if (cw_i == 8) {
            cw_i = 0;
            if (!cw_text) {             /* (the file's header: CWRD 1.x) */
                cw_text = 1;
                if (memcmp(cw_hdr, "CWRD", 4) || cw_hdr[4] != 1)
                    at_bad = 1;
                return;
            }
            cw_n = cw_hdr[4] | (unsigned long)cw_hdr[5] << 8 | (unsigned long)cw_hdr[6] << 16 | (unsigned long)cw_hdr[7] << 24;
            if (!memcmp(cw_hdr, "END ", 4))
                cw_st = 3;
            else
                cw_st = memcmp(cw_hdr, "TEXT", 4) ? 1 : 2;
            if (!cw_n && cw_st < 3)
                cw_st = 0;
        }
        return;
    }
    if (cw_st == 3)
        return;
    if (cw_st == 2) {
        if (cw_skip)
            --cw_skip;
        else if (c >= 0x10 && c <= 0x17)
            cw_skip = 2;
        else if (c >= 0x18 && c <= 0x1F)
            cw_skip = 4;
        else if (c == 0x0D)
            at_out('\n');
        else if (c == 9 || (c >= 32 && c < 127))
            at_out(c);
        else if (c >= 0xA0)
            at_out(c);
    }
    if (!--cw_n)
        cw_st = 0;
}

static void __fastcall__ at_prg(unsigned char c)
{
    dt_byte(c);
}

/* the file attached read and made text: counted (at_store 0) or into the open message */
static unsigned char __fastcall__ at_read(unsigned char store)
{
    unsigned char h, i, n;
    vr_cd(VR_DOCS);
    h = FOpen(gph, 'r');                /* (the name: copied below $A000 first) */
    if (h < 2 || h > 4 || dosStatus >= 20) {
        if (h >= 2 && h <= 4)
            FClose(h);
        return 0;
    }
    at_store = store;
    at_n = at_lines = 0;
    at_bad = at_cr = 0;
    cw_st = cw_i = cw_text = cw_skip = 0;
    dt_st = 0;
    dt_out = at_out;
    ob_n = 0;
    for (;;) {
        n = FRead(h, rbuf, 64);
        for (i = 0; i < n; ++i)
            if (af_kind == AK_PRG)
                at_prg(rbuf[i]);
            else if (af_kind == AK_CWR)
                at_cwr(rbuf[i]);
            else
                at_text(rbuf[i]);
        if (n < 64 || at_n > ATTMAX || at_bad || (af_kind == AK_PRG && (dt_bad || dt_st == 9)))
            break;
    }
    FClose(h);
    if (af_kind == AK_PRG && dt_bad)
        at_bad = 1;
    if (at_store && ob_n && !st_append(dtext, ob_n))
        at_bad = 1;
    ob_n = 0;
    return !at_bad;
}

static void lbl(void)
{
    char *p;
    strcpy(att_lbl, "Attached: ");
    strncat(att_lbl, af_name, 20);
    p = att_lbl + strlen(att_lbl);
    strcpy(p, " (");
    p = unum(p + 2, af_lines);
    strcpy(p, af_lines == 1 ? " line) [Remove]" : " lines) [Remove]");
}

void c_attach(void)
{
    char *x;
    unsigned char h;
    if (!att_on)
        strcpy(gph, af_name);
    if (!ask("Attach a file from /DOCUMENTS (its name):", gph, 63) || !gph[0])
        return;
    c_ui |= CU_TOOL | CU_STATUS;
    vr_cd(VR_DOCS);
    strcpy(af_name, gph);
    x = strrchr(af_name, '.');
    strcpy(line, x ? x + 1 : "");
    for (h = 0; line[h]; ++h)
        line[h] = lower(line[h]);
    af_lang = !strcmp(line, "bas") || !strcmp(line, "prg") ? L_BAS : !strcmp(line, "asm") || !strcmp(line, "s")
              || !strcmp(line, "inc") ? L_ASM : !strcmp(line, "c") || !strcmp(line, "h") ? L_C : !strcmp(line, "py") ? L_PY : L_TXT;
    af_kind = AK_TEXT;
    h = FOpen(gph, 'r');
    if (h >= 2 && h <= 4) {
        if (dosStatus < 20 && FRead(h, rbuf, 4) == 4) {
            if (!memcmp(rbuf, "CWRD", 4))
                af_kind = AK_CWR;
            else if (rbuf[0] == 1 && rbuf[1] == 8 && !strcmp(line, "prg"))
                af_kind = AK_PRG;
        }
        FClose(h);
    }
    af_prg = af_kind == AK_PRG;
    if (!at_read(0)) {
        att_on = 0;
        message(af_kind == AK_PRG ? "This .PRG is not a BASIC program:" : "The file cannot be read:", af_name);
        strcpy(msg, "Nothing attached.");
        return;
    }
    if (at_n > ATTMAX) {
        att_on = 0;
        message("The file is too big to attach:", "(it would not leave the conversation room enough).");
        strcpy(msg, "Nothing attached.");
        return;
    }
    af_size = at_n;
    af_lines = at_lines + (at_n && at_last != '\n');
    att_on = 1;
    lbl();
    strcpy(msg, "Attached ");
    strncat(msg, af_name, 30);
    strcat(msg, ": it goes with your next question.");
}


/* conv.c's c_ask_user: the file into the open message (at_n, at_lines) */
void at_store1(void)
{
    strcpy(gph, af_name);
    at_read(1);
    c_blk = at_n && at_last != '\n';  /* (its last line has no line feed) */
}

/*---------------------------------------------------------------- (ui.c's, for room) */

/* the reply's row says "Thinking" until its first text */
void thinking(void)
{
    unsigned int i = st_rows - 1, s;
    unsigned char n;
    if (i < v_top || i >= v_top + BROWS)
        return;
    s = (ser_frames - tt0) / 60;
    n = (ser_frames >> 4) & 3;
    strcpy(cs_txt, "Thinking");
    strcat(cs_txt, &"...."[3 - n]);
    strcat(cs_txt, "    (");
    unum(cs_txt + strlen(cs_txt), s);
    strcat(cs_txt, " s)");
    for (n = strlen(cs_txt); n < TW; ++n)
        cs_txt[n] = ' ';
    dispBufferOn = ST_WR_FORE;
    cells(TX, BODYY + (i - v_top) * RH, TW, RH, 0);
}

