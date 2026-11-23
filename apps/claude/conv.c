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
#include "claude.h"
#ifdef ASK
#pragma code-name ("OVERLAY8")
#pragma rodata-name ("OVL8RO")
#pragma bss-name ("OVL8BSS")
#pragma data-name ("OVL8DATA")
#else
#pragma code-name ("OVERLAY7")
#pragma rodata-name ("OVL7RO")
#pragma bss-name ("OVL7BSS")
#pragma data-name ("OVL7DATA")
#endif

static const char *const l_tag[5] = { "text", "basic", "asm", "c", "python" };

/* v with thousands' commas */
static char *__fastcall__ cnum(char *p, unsigned long v)
{
    char t[12];
    unsigned char n = 0, i;
    unum(t, v);
    i = strlen(t);
    while (i) {
        *p++ = t[n++];
        if (--i && i % 3 == 0)
            *p++ = ',';
    }
    *p = 0;
    return p;
}

/*---------------------------------------------------------------- what a turn sends */

static unsigned char __fastcall__ kind_at(unsigned int a)
{
    st_msg(a);
    return st_k;
}

/* the text sent from g_from up to the open reply (its messages' lengths) */
static unsigned long sent_len(void)
{
    unsigned int a, nx;
    unsigned long n = 0;
    for (a = g_from; a < st_used && a != st_cur; a = nx) {
        nx = st_msg(a);
        if (SENT(st_k))
            n += st_n + 32;
    }
    return n;
}

static unsigned char sub_b[NSUB];       /* the shortened blocks' */

#ifdef ASK
/* (Ask) the model sent: the chosen one, or for a compaction and Ctrl+Return
   the plan's cheapest (a name with "nano", else "mini"; the API key's
   model is the only one) */
static void cheap(void)
{
    unsigned char i, b = tbank + tlive, best = 0xFF, k;
    strcpy(g_slug, C.mslug);
    if (C.srv || (!t_cheap && !t_comp))
        return;
    for (k = 0; k < 2 && best == 0xFF; ++k)
        for (i = 0; i < sl.nmod; ++i) {
            bk_get(b, TB_MOD + i * 64, line, 64);
            line[31] = 0;
            if (strstr(line, k ? "mini" : "nano")) {
                best = i;
                break;
            }
        }
    if (best != 0xFF) {
        bk_get(b, TB_MOD + best * 64, line, 64);
        line[SLUGMAX - 1] = 0;
        strcpy(g_slug, line);
    }
}
#endif

void plan(void)
{
    unsigned int a, nx, ring[10], last = NOMSG, prev = NOMSG, sz;
    unsigned char want, n = 0, h = 0, j, k, small;
    struct blk *b;
#ifdef ASK
    cheap();
#else
    g_model = t_cheap || t_comp ? M_HAIKU : C.model;
#endif
    strcpy(g_max, t_comp ? "500" : C.shorta ? "1024" : "4096");
    /* Remember: the first message sent */
    g_from = 0;
    if (!t_comp && C.rem) {
        want = C.rem == RM_10 ? 10 : C.rem == RM_4 ? 4 : 0;
        for (a = 0; a < t_umsg; a = nx) {
            nx = st_msg(a);
            if (SENT(st_k) && want) {
                ring[h] = a;
                h = (h + 1) % want;
                if (n < want)
                    ++n;
            }
        }
        g_from = t_umsg;
        if (n == want && want)
            g_from = ring[h];
        else if (want)
            g_from = 0;
        while (g_from < t_umsg && !USERK(kind_at(g_from)))
            g_from = st_msg(g_from);
    }
    /* old code shortened */
    nsub = 0;
    if (t_comp || C.fullold)
        return;
    ovc(code_scan);
    for (a = 0; a < t_umsg; a = nx) {
        nx = st_msg(a);
        if (st_k == K_CLAUDE) {
            prev = last;
            last = a;
        }
    }
    for (j = 0; j < nblk; ++j) {
        b = &B[j];
        if (b->a < g_from || b->msg >= t_umsg || !SENT(kind_at(b->msg)))
            continue;
        if (b->fl & B_FILE) {           /* (a file's older version: a newer one comes later) */
            for (k = j + 1; k < nblk && !((B[k].fl & B_FILE) && !strcmp(B[k].name, b->name)); ++k)
                ;
            if (k == nblk)
                continue;
        } else if (b->msg == last || !((b->fl & (B_SAVED | B_COPIED)) || (prev != NOMSG && b->a < prev)))
            continue;
        sz = b->e - b->a;
        if (sz < 48)
            continue;
        if (nsub == NSUB) {             /* (full: the smallest given up for a bigger one) */
            for (k = small = 0; k < NSUB; ++k)
                if (sub_e[k] - sub_a[k] < sub_e[small] - sub_a[small])
                    small = k;
            if (sub_e[small] - sub_a[small] >= sz)
                continue;
            k = small;
        } else
            k = nsub++;
        sub_a[k] = b->a;
        sub_e[k] = b->e;
        sub_b[k] = j;
    }
}

/* the placeholder of the shortened block ph_i, in gph (JSON as it is: no quotes) */
void ph_make(void)
{
    struct blk *b = &B[sub_b[ph_i]];
    char *p;
    unsigned char i;
    strcpy(gph, "[");
    if (b->fl & B_FILE) {
        strcat(gph, b->name);
        strcat(gph, ", older version, ");
    } else
        strcat(gph, "code block: ");
    p = unum(gph + strlen(gph), b->lines);
    strcpy(p, b->lines == 1 ? " line" : " lines");
    if (!(b->fl & B_FILE) && (b->fl & B_SAVED)) {
        strcat(gph, ", saved as ");
        strcat(gph, b->name);
    }
    strcat(gph, "]\\n");
    for (i = 1; gph[i + 2]; ++i)
        if (gph[i] == '"' || gph[i] == '\\' || gph[i] < 32 || gph[i] >= 127)
            gph[i] = '_';
}

/*---------------------------------------------------------------- compaction */

static const char c_inst[] =
    "Summarise our conversation so far in at most 150 words, so that you can go on from the "
    "summary alone. Keep every decision made, the names of files, and any code still under "
    "discussion (the code itself, short). Plain text, no preamble.";
static const char c_pre[] = "Summary of our conversation so far: ";
static const char c_ack[] = "Thank you: I have the summary and will go on from it.";

static void __fastcall__ c_start(unsigned char mode)
{
    unsigned int a, nx;
    unsigned char any = 0;
    for (a = 0; a < st_used; a = nx) {
        nx = st_msg(a);
        if (SENT(st_k))
            any = 1;
    }
    c_ui |= CU_STATUS;
    if (!any) {
        strcpy(msg, "There is nothing to compact yet.");
        return;
    }
    st_prot = st_used;
    if (!st_room(4096 + sizeof c_inst)) {
        strcpy(msg, "No room to compact: File > New conversation.");
        return;
    }
    st_prot = st_used;
    memcpy(rbuf, c_inst, sizeof c_inst - 1);
    t_umsg = st_add(K_CINST, (char *)rbuf, sizeof c_inst - 1);
    if (t_umsg == NOMSG || !st_open(K_SUM)) {
        strcpy(msg, "No room to compact: File > New conversation.");
        return;
    }
    t_rmsg = st_cur;
    st_prot = t_umsg;
    strcpy(line, c_pre);
    st_append(line, sizeof c_pre - 1);
    t_comp = mode;
    plan();
#ifdef ASK
    ov5(ask_go);
    if (!tgo) {
#else
    if (!turn_start()) {
#endif
        st_drop_last();
        st_mark(t_umsg, K_HIDDEN);
        t_comp = 0;
        strcpy(msg, "The compaction could not start.");
        return;
    }
#ifdef ASK
    strcpy(msg, "Compacting the conversation (the cheapest model) ...");
#else
    strcpy(msg, "Compacting the conversation (Claude Haiku 5.5) ...");
#endif
}

void c_compact(void)
{
    c_start(1);
}

/* send's: compacted first when it is long (the Conversation page's setting) */
void c_presend(void)
{
    g_from = 0;
    if (!C.autoc || sent_len() + in_len < 6144)
        return;
    c_start(2);
    if (t_comp)
        c_go = 2;
}

/*---------------------------------------------------------------- after a turn */

#ifndef ASK
/* the prices, dollars per million tokens times 1000: input, output, a cache
   write (5 minutes: 1.25 times the input), a cache read. Anthropic's
   list prices for these models as of November 2026 (platform.claude.com's
   pricing: Opus 5.5 $4 / $20, Sonnet 5.5 $2 / $10, Haiku 5.5 $0.10 /
   $0.50; cache reads $0.20, $0.10 and 0.1 times the input for Haiku);
   an estimate only: the bill is Anthropic's */
static const unsigned int price[MODELS][4] = {
    { 4000, 20000, 5000, 200 },
    { 2000, 10000, 2500, 100 },
    { 100, 500, 125, 10 },
};
#endif
static unsigned long u_last;            /* the last turn's estimate (millionths of a dollar) */

static void usage(void)
{
#ifndef ASK
    const unsigned int *pr = price[g_model];
    unsigned long c;
#endif
    if (!p_in && !p_out)
        return;
    ++u_turns;
#ifdef ASK
    u_in += p_in;                       /* (OpenAI's input_tokens: the cached ones in it) */
    u_cached += p_cache;
    u_last = 0;
#else
    u_in += p_in + p_cache + p_cw;      /* (Anthropic's input_tokens: without the cache's) */
    u_cached += p_cache;
    c = (p_in * pr[0] + 500) / 1000 + (p_out * pr[1] + 500) / 1000 + (p_cw * pr[2] + 500) / 1000
        + (p_cache * pr[3] + 500) / 1000;
    u_last = C.srv ? 0 : c;
    u_cost += u_last;
#endif
    u_out += p_out;
}

static char *__fastcall__ dollars(char *p, unsigned long u)
{
    unsigned long f = (u % 1000000 + 50) / 100;
    *p++ = '$';
    p = unum(p, u / 1000000 + f / 10000);
    f %= 10000;
    *p++ = '.';
    *p++ = '0' + f / 1000;
    *p++ = '0' + f / 100 % 10;
    *p++ = '0' + f / 10 % 10;
    *p++ = '0' + f % 10;
    *p = 0;
    return p;
}

/* the last turn's tokens after the status bar's text (msg) */
static void tokens(void)
{
    char *p = msg + strlen(msg);
    if (!p_in && !p_out)
        return;
    if (p > msg + 44)
        p = msg + 44;
    if (p != msg) {
        strcpy(p, "  ");
        p += 2;
    }
    strcpy(p, "in ");
#ifdef ASK
    p = cnum(p + 3, p_in);
#else
    p = cnum(p + 3, p_in + p_cache + p_cw);
#endif
    if (p_cache) {
        strcpy(p, " (cached ");
        p = cnum(p + 9, p_cache);
        strcpy(p, ")");
        ++p;
    }
    strcpy(p, " out ");
    p = cnum(p + 5, p_out);
    if (u_last) {
        strcpy(p, ", ");
        dollars(p + 2, u_last);
    }
}

static void comp_end(void)
{
    unsigned int a, nx;
    unsigned char ok = p_status == 200 && p_text && tend == TE_OK;
    char *p;
    tdone = 0;                          /* (turn.c's turn_end does it for a turn) */
#ifdef ASK
    ok = ok && p_ok;
#endif
    if (ok) {
        st_close();
        for (a = 0; a < t_umsg; a = nx) {
            nx = st_msg(a);
            if (USERK(st_k))
                st_mark(a, K_CUSER);
            else if (st_k == K_CLAUDE)
                st_mark(a, K_CASST);
        }
        st_mark(t_umsg, K_HIDDEN);
        strcpy(line, c_ack);
        st_add(K_CLAUDE, line, sizeof c_ack - 1);
        strcpy(line, "(Compacted: the turns above, dimmed, are no longer sent; the summary and its answer stand for them.)");
        st_add(K_NOTE, line, strlen(line));
        st_relayout();
        g_from = 0;
        strcpy(msg, "Compacted: what is sent is now ");
        p = cnum(msg + strlen(msg), sent_len());
        strcpy(p, " bytes.");
        tokens();
    } else {
        if (st_cur != NOMSG)
            st_drop_last();
        st_mark(t_umsg, K_HIDDEN);
        strcpy(msg, "The compaction did not work: nothing changed.");
        if (p_status && p_status != 200) {
            strcpy(line, "The summary's request was refused (");
            unum(line + strlen(line), p_status);
            strcat(line, "):");
            message(line, p_emsg);
        } else if (tend != TE_OK && tend != TE_STOP)
            message("The compaction did not work:", "the connection failed (nothing changed).");
    }
    st_prot = st_used;
    if (t_comp == 2)
        c_go = 1;                       /* (the question that waited: now) */
    t_comp = 0;
}

void c_after(void)
{
    if (tstate != T_IDLE)
        return;
    if (p_status == 200)
        usage();
    if (t_comp) {
        comp_end();
        return;
    }
    ovc(code_scan);
    if (p_status == 200 && tbody > 8192 && C.rem == RM_ALL)    /* (V149: alone, the status bar shows 63 characters) */
        strcpy(msg, "Long conversation: each question resends it. New starts fresh.");
    else if (p_status == 200)
        tokens();
}

void c_newconv(void)
{
    ovc(code_reset);
    h_seq = 0;                          /* (the next save: a new chat) */
    u_in = u_cached = u_out = u_cost = u_last = 0;
    u_turns = 0;
    att_on = 0;
}

/*---------------------------------------------------------------- the Conversation page (pg_on 2) */

#define CVY   72
static const char *const rem_t[4] = { "everything", "the last 10 messages", "the last 4 messages", "only the question" };
static unsigned char cv_keep[4];

static void __fastcall__ cv_row(unsigned char r)
{
    unsigned int y = CVY + r * 24;
    static const char *const lab[4] = { "Remember", "Answers", "Old code", "Compact" };
    put(2, y + 4, lab[r], 10, 0);
    strcpy(line, "<");
    switch (r) {
    case 0: strcat(line, rem_t[C.rem]); break;
    case 1: strcat(line, C.shorta ? "short (a sentence more in the system prompt, max_tokens 1024)" : "normal (max_tokens 4096)"); break;
    case 2: strcat(line, C.fullold ? "sent whole every time" : "shortened: sent as one line once saved, copied or 2 turns old"); break;
    case 3: strcat(line, C.autoc ? "when what is sent is longer than 6 KB" : "only when asked (Settings > Compact conversation)"); break;
    }
    strcat(line, ">");
    put(13, y + 4, line, 66, !hl);
    theme_rect(12, 67, y >> 3, 2, hl ? hl : 0);
}

static void cv_draw(void)
{
    unsigned char i;
    char *p;
    dispBufferOn = ST_WR_FORE;
    SetPattern(0);
    WRectangle(0, 48, 639, 463);
    theme_rect(0, 80, 6, 52, 0);
#ifdef ASK
    heading("Conversation", "/VERANDA/.SYSTEM/ASK.CFG");
#else
    heading("Conversation", "/VERANDA/.SYSTEM/CLAUDE.CFG");
#endif
    for (i = 0; i < 4; ++i)
        cv_row(i);
    button(2, 8, 176, "Save", 0);
    button(11, 8, 176, "Cancel", 0);
    button(20, 18, 176, "Compact now", 0);
    WHorizontalLine(0xFF, 8, 631, 200);
    strcpy(line, "This conversation: ");
    p = unum(line + strlen(line), u_turns);
    strcpy(p, u_turns == 1 ? " turn; in " : " turns; in ");
    p = cnum(p + strlen(p), u_in);
    strcpy(p, " tokens (cached ");
    p = cnum(p + 16, u_cached);
    strcpy(p, "), out ");
    p = cnum(p + 7, u_out);
    if (u_cost) {
        strcpy(p, "; about ");
        dollars(p + 8, u_cost);
    }
    put(2, 212, line, 78, 0);
    strcpy(line, "The last request: ");
    p = cnum(line + 18, tbody);
    strcpy(p, " bytes. What is sent now (the Remember setting): about ");
    g_from = 0;
    p = cnum(p + strlen(p), sent_len());
    strcpy(p, " bytes.");
    put(2, 228, line, 78, 0);
    put(2, 252, "Every question sends the conversation again: the API keeps nothing between", 78, 0);
    put(2, 266, "requests. A long conversation costs more each turn. Remember sends less;", 78, 0);
    put(2, 280, "Compact replaces the old turns by a short summary (the cheapest model writes", 78, 0);
    put(2, 294, "it); File > New starts fresh. Ctrl+Return sends one question to the cheapest", 78, 0);
#ifdef ASK
    put(2, 308, "model. The plan's usage shows no money: only tokens.", 78, 0);
#else
    put(2, 308, "model (Claude Haiku 5.5). Dollars: an estimate from the list prices.", 78, 0);
#endif
    put(2, 336, "Click a setting (or 1-4) to change it; Return saves, Esc cancels.", 78, 0);
}

void c_conv(void)
{
    memcpy(cv_keep, &C.rem, 4);
    pg_on = 2;
    pg_saved = 0;
    cv_draw();
#ifdef CLAUDE_TEST
    gt_log("CL CONV SHOWN");
#endif
}

static void __fastcall__ cv_set(unsigned char r)
{
    switch (r) {
    case 0: C.rem = (C.rem + 1) & 3; break;
    case 1: C.shorta ^= 1; break;
    case 2: C.fullold ^= 1; break;
    case 3: C.autoc ^= 1; break;
    }
    cv_row(r);
}

static void __fastcall__ cv_close(unsigned char save)
{
    if (save) {
        ov4(cfg_save);
        pg_saved = 1;
    } else
        memcpy(&C.rem, cv_keep, 4);
    pg_on = 0;
}

void cv_key(void)
{
    unsigned char k = keyData;
    if (k >= '1' && k <= '4')
        cv_set(k - '1');
    else if (k == 13)
        cv_close(1);
    else if (k == KEY_ESC)
        cv_close(0);
}

void cv_press(void)
{
    unsigned int y = mouseYPosW;
    unsigned char c = mouseXPos >> 3;
    if (y >= CVY && y < CVY + 96 && c >= 12) {
        cv_set((y - CVY) / 24);
        return;
    }
    if (y >= 176 && y < 190) {
        if (c >= 2 && c < 10)
            cv_close(1);
        else if (c >= 11 && c < 19)
            cv_close(0);
        else if (c >= 20 && c < 38) {
            cv_close(1);
            c_ui |= CU_ALL;
            c_start(1);
        }
    }
}

/* send's: the question, the file after it */
void c_ask_user(void)
{
    if (!att_on) {
        t_umsg = st_add(K_USER, inbuf, in_len);
        return;
    }
    t_umsg = NOMSG;
    if (!st_room(12288u + in_len + ATTMAX / 2 + 256)) {
        message("The conversation is full.", "Start a new one: File > New conversation.");
        return;
    }
    st_prot = st_used;
    if (!st_open(K_USER))
        return;
    t_umsg = st_cur;
    line[0] = 0;
    if (in_len) {
        st_append(inbuf, in_len);
        strcpy(line, "\n\n");         /* (the texts from main RAM: st_append maps the store's banks) */
    }
    strcat(line, "Attached file ");
    strcat(line, af_name);
    strcat(line, ":\n```");
    strcat(line, l_tag[af_lang]);
    strcat(line, "\n");
    st_append(line, strlen(line));
    ovs(at_store1);
    strcpy(line, "\n```");
    st_append(line + !c_blk, 4 - !c_blk);
    st_close();
    att_on = 0;
}

