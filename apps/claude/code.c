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
#include <scrap.h>
#include <vrnet.h>
#include "claude.h"
#ifdef ASK
#pragma code-name ("OVERLAY6")
#pragma rodata-name ("OVL6RO")
#pragma bss-name ("OVL6BSS")
#pragma data-name ("OVL6DATA")
#else
#pragma code-name ("OVERLAY5")
#pragma rodata-name ("OVL5RO")
#pragma bss-name ("OVL5BSS")
#pragma data-name ("OVL5DATA")
#endif

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

/*---------------------------------------------------------------- the blocks */

static const char *const l_tag[5] = { "text", "basic", "asm", "c", "python" };
static unsigned int scanned, cutb0, mrows;
static unsigned char mgen = 0xFF;

static unsigned char __fastcall__ lang_of(const char *t)
{
    if (!strcmp(t, "basic") || !strcmp(t, "bas") || !strcmp(t, "x16basic") || !strcmp(t, "commodore-basic")
        || !strcmp(t, "basicv2") || !strcmp(t, "c64basic"))
        return L_BAS;
    if (!strcmp(t, "asm") || !strcmp(t, "assembly") || !strcmp(t, "s") || !strcmp(t, "ca65") || !strcmp(t, "6502")
        || !strcmp(t, "65c02"))
        return L_ASM;
    if (!strcmp(t, "c") || !strcmp(t, "h"))
        return L_C;
    if (!strcmp(t, "python") || !strcmp(t, "py"))
        return L_PY;
    return L_TXT;
}

static void __fastcall__ drop_block(unsigned char i)
{
    memmove(&B[i], &B[i + 1], (nblk - i - 1) * sizeof B[0]);
    --nblk;
}

/* the end of the line from p (its line feed, or t1): the store a block at a
   time through cs_txt, memchr's speed */
static unsigned int __fastcall__ eol(unsigned int p, unsigned int t1)
{
    unsigned char k;
    char *q;
    while (p < t1) {
        k = 64;
        if (t1 - p < 64)
            k = t1 - p;
        st_copy(p, cs_txt, k);
        if ((q = memchr(cs_txt, '\n', k)) != 0)
            return p + (q - cs_txt);
        p += k;
    }
    return t1;
}

#define HD ((unsigned char *)line + 184)        /* (a line's first 12 bytes) */

/* message m's blocks (its text p .. t1) */
static void __fastcall__ scan_msg(unsigned int m, unsigned int p, unsigned int t1, unsigned char user)
{
    static unsigned int ls, le, pls;
    static unsigned char inb, c, i, n, k, num;
    static struct blk *b;
    pls = p;
    inb = 0;
    while (p < t1) {
        ls = p;
        le = eol(p, t1);
        k = le - ls > 12 ? 12 : le - ls;
        st_copy(ls, (char *)HD, k);
        if (k >= 3 && HD[0] == '`' && HD[1] == '`' && HD[2] == '`') {
            if (!inb) {
                if (nblk == NB)
                    drop_block(0);
                b = &B[nblk];
                memset(b, 0, sizeof *b);
                b->msg = m;
                b->a = ls;
                b->ca = le;             /* (not "le < t1 ? le + 1 : t1": cc65 took p for t1 there) */
                if (le < t1)
                    ++b->ca;
                for (i = 3, n = 0; i < k && n < sizeof b->tag - 1; ++i)
                    if (HD[i] != ' ')
                        b->tag[n++] = lower(HD[i]);
                b->lang = lang_of(b->tag);
                if (user)
                    b->fl = B_USER;
                /* "Attached file NAME:" the line before: the file's */
                if (user && pls < ls && ls - pls > 15) {
                    st_copy(pls, line, ls - pls > 60 ? 60 : ls - pls);
                    if (!memcmp(line, "Attached file ", 14)) {
                        for (i = 14, n = 0; i + 2 < ls - pls && n < sizeof b->name - 1; ++i)
                            b->name[n++] = line[i];
                        b->fl |= B_FILE;
                    }
                }
                inb = num = 1;
            } else {
                b->ce = ls;
                b->e = le;
                if (le < t1)
                    ++b->e;
                inb = 0;
                goto done;
            }
        } else if (inb) {
            ++b->lines;
            for (i = 0; i < k && HD[i] == ' '; ++i)
                ;
            if (i < k && (HD[i] < '0' || HD[i] > '9'))
                num = 0;
        }
        pls = ls;
        p = le + 1;
        continue;
    done:
        /* BASIC by its numbers; a reply's block in the attached file's language: its next version */
        if (b->lang == L_TXT && !b->tag[0] && num && b->lines)
            b->lang = L_BAS;
        if (!user)
            for (n = nblk; n--; )
                if (B[n].fl & B_FILE) {
                    if (B[n].lang == b->lang || (b->lang == L_TXT && !b->tag[0])) {
                        b->fl |= B_FILE;
                        b->lang = B[n].lang;
                        strcpy(b->name, B[n].name);
                    }
                    break;
                }
        ++nblk;
        pls = ls;
        p = le + 1;
    }
    if (inb) {                          /* (not closed: to the message's end) */
        inb = 0;
        b->ce = b->e = t1;
        le = ls = t1;
        p = t1 + 1;
        goto done;
    }
}

void code_reset(void)
{
    nblk = 0;
    scanned = 0;
    cutb0 = st_cutb;
    mgen = 0xFF;
}

/* the new messages' blocks found; every row's marks made again */
void code_scan(void)
{
    unsigned int a, nx, d, i, ra;
    unsigned char j, fl, nf;
    if (st_used < scanned || !st_used) {
        nblk = 0;
        scanned = 0;
        cutb0 = st_cutb;
    }
    if ((d = st_cutb - cutb0) != 0) {   /* (the oldest turns dropped: the blocks moved down) */
        cutb0 = st_cutb;
        for (j = 0; j < nblk; )
            if (B[j].a < d)
                drop_block(j);
            else {
                B[j].msg -= d;
                B[j].a -= d;
                B[j].ca -= d;
                B[j].ce -= d;
                B[j].e -= d;
                ++j;
            }
        scanned = scanned > d ? scanned - d : 0;
    }
    wa = 0xFFFF;
    for (a = scanned; a < st_used && a != st_cur; a = nx) {
        nx = st_msg(a);
        if (st_k == K_USER || st_k == K_CLAUDE || st_k == K_CUSER || st_k == K_CASST || st_k == K_UNSENT)
        {
            scan_msg(a, a + 3, nx, st_k == K_USER || st_k == K_CUSER || st_k == K_UNSENT);
        }
        scanned = nx;
    }
    /* the rows (in order, as the blocks are) */
    i = st_gen == mgen && st_rows >= mrows && mrows ? mrows - 1 : 0;      /* (the rows made since, unless they were all made again) */
    for (j = 0; i < st_rows; ++i) {
        ra = row_at(i);
        fl = row_fl;
        if ((fl & R_KIND) == R_GAP)
            continue;
        while (j < nblk && B[j].e <= ra)
            ++j;
        nf = fl & ~(R_CODE | R_FENCE | R_CEND);
        if (j < nblk && ra >= B[j].a) {
            nf |= R_CODE;
            if (ra == B[j].a)
                nf |= R_FENCE;
            else if (ra == B[j].ce && B[j].ce < B[j].e)
                nf |= R_CEND;
        }
        if (nf != fl)
            row_set(i, nf);
    }
    wa = 0xFFFF;                        /* (cs_txt is the rows' again) */
    mgen = st_gen;
    mrows = st_rows;
}

static unsigned char __fastcall__ block_at_row(unsigned int i)
{
    unsigned int ra = row_at(i);
    unsigned char j;
    if (!(row_fl & R_FENCE))
        return 0xFF;
    for (j = 0; j < nblk; ++j)
        if (B[j].a == ra)
            return j;
    return 0xFF;
}

/* a fence's row (c_row): the labels, or nothing (the closing one) */
#define LC_COPY 14
#define LC_SAVE 22
#define LC_PRG  33
void code_label(void)
{
    unsigned char j = block_at_row(c_row), n;
    struct blk *b;
    memset(cs_txt, ' ', TW);
    if (j == 0xFF)
        return;
    b = &B[j];
    cs_txt[0] = '`';
    cs_txt[1] = '`';
    cs_txt[2] = '`';
    memcpy(cs_txt + 3, b->tag[0] ? b->tag : l_tag[b->lang], strlen(b->tag[0] ? b->tag : l_tag[b->lang]));
    memcpy(cs_txt + LC_COPY, "[Copy]", 6);
    memcpy(cs_txt + LC_SAVE, "[Save...]", 9);
    if (b->lang == L_BAS)
        memcpy(cs_txt + LC_PRG, "[Save .PRG]", 11);
    strcpy(line, b->fl & B_FILE ? "(" : "");
    if (b->fl & B_FILE)
        strcat(line, b->name);
    else if (b->fl & B_SAVED) {
        strcpy(line, "(saved: ");
        strcat(line, b->name);
    } else if (b->fl & B_COPIED)
        strcpy(line, "(copied");
    if (line[0])
        strcat(line, ")");
    n = strlen(line);
    if (n > TW - 46)
        n = TW - 46;
    memcpy(cs_txt + 46, line, n);
}

/*---------------------------------------------------------------- copy */

static unsigned int ob_n;
static unsigned char sv_bad;

static void ob_flush(void)
{
    if (ob_n) {
        if (scrap_write(dtext, ob_n))
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

/* the text a .. e (a final line feed left out) to the scrap: CR line ends */
static unsigned char __fastcall__ to_scrap(unsigned int a, unsigned int e)
{
    if (e > a && sb(e - 1) == '\n')
        --e;
    sv_bad = 0;
    ob_n = 0;
    if (scrap_text_begin(e - a + 4))
        return 1;
    ob(SCRAP_NEWCARDSET);
    ob(9);
    ob(0);
    ob(0);
    for (; a < e; ++a)
        ob(sb(a) == '\n' ? 13 : latin(sb(a)));
    ob_flush();
    sv_bad |= scrap_close() != 0;
    return sv_bad;
}

static unsigned char last_block(void)
{
    unsigned char j = nblk;
    unsigned int k;
    code_scan();
    while (j--) {
        st_msg(B[j].msg);
        k = st_k;
        if (k != K_HIDDEN)
            return j;
    }
    return 0xFF;
}

/* file.c's: the last block (c_blk; 0xFF none) */
void c_last(void)
{
    c_blk = last_block();
}

static void __fastcall__ copy_block(unsigned char j)
{
    struct blk *b = &B[j];
    c_ui |= CU_STATUS;
    if (to_scrap(b->ca, b->ce)) {
        strcpy(msg, "The clipboard cannot be written.");
        return;
    }
    b->fl |= B_COPIED;
    strcpy(msg, "Copied to the clipboard: the code block, ");
    unum(msg + strlen(msg), b->lines);
    strcat(msg, b->lines == 1 ? " line." : " lines.");
    st_dirty = 0;                       /* (its label) */
}

void c_copy(void)
{
    unsigned char j = last_block();
    if (j == 0xFF) {
        c_ui |= CU_STATUS;
        strcpy(msg, "There is no code block in the conversation yet.");
        return;
    }
    copy_block(j);
}

/* the last reply, whole */
void c_reply(void)
{
    unsigned int a = 0, nx, r = NOMSG;
    for (; a < st_used; a = nx) {
        nx = st_msg(a);
        if (st_k == K_CLAUDE)
            r = a;
    }
    c_ui |= CU_STATUS;
    if (r == NOMSG) {
        strcpy(msg, "There is no reply yet.");
        return;
    }
    nx = st_msg(r);
    wa = 0xFFFF;
    if (to_scrap(r + 3, nx))
        strcpy(msg, "The clipboard cannot be written.");
    else
        strcpy(msg, "Copied to the clipboard: the last reply.");
}

void paste(void)
{
    if (!scrap_get_text(line, sizeof line))
        line[0] = 0;
}

/* Go to code block n */
void c_choose(void)
{
    unsigned int i;
    unsigned char n = 0, j;
    code_scan();
    if (!nblk) {
        c_ui |= CU_STATUS;
        strcpy(msg, "There is no code block in the conversation yet.");
        return;
    }
    unum(gph, nblk);
    strcpy(line, "Go to code block (1 to ");
    strcat(line, gph);
    strcat(line, "):");
    if (!ask(line, gph, 3))
        return;
    for (j = 0; gph[j] >= '0' && gph[j] <= '9'; ++j)
        n = n * 10 + gph[j] - '0';
    if (!n || n > nblk)
        return;
    for (i = 0; i < st_rows; ++i)
        if (row_at(i) == B[n - 1].a && (row_fl & R_FENCE)) {
            c_row = i > 2 ? i - 2 : 0;
            c_ui |= CU_GOTO;
            return;
        }
}

void code_click(void)
{
    unsigned char j;
    if (c_row >= st_rows || (j = block_at_row(c_row)) == 0xFF)
        return;
    c_blk = j;
    if (c_col >= LC_COPY && c_col < LC_COPY + 6)
        copy_block(j);
    else if (c_col >= LC_SAVE && c_col < LC_SAVE + 9) {
        c_prg = 0;
        ovs(c_saveblk);
    } else if (c_col >= LC_PRG && c_col < LC_PRG + 11 && B[j].lang == L_BAS) {
        c_prg = 1;
        ovs(c_saveblk);
    }
}


/* Code > Save last code block... (asked: a program, for BASIC) */
void c_save(void)
{
    c_blk = last_block();
    if (c_blk == 0xFF) {
        c_ui |= CU_STATUS;
        strcpy(msg, "There is no code block in the conversation yet.");
        return;
    }
    c_prg = 2;
    ovs(c_saveblk);
}

void c_about(void)
{
#ifdef ASK
    message("Veranda Ask 1.1, MIT licence.", "OpenAI's models through the Wi-Fi modem.");
#else
    message("Veranda Claude 1.1, MIT licence.", "Claude (Anthropic's API) through the Wi-Fi modem.");
#endif
}

void c_unattach(void)
{
    if (!yesno("Remove the attached file?", af_name))
        return;
    att_on = 0;
    c_ui |= CU_TOOL | CU_STATUS;
    strcpy(msg, "The file is no longer attached.");
}

