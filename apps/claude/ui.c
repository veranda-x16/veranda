/* Veranda Claude: the interface (overlay 1, appBank: mapped for good;
   DECISIONS V114).

   The window (Veranda Look 3 "Sunroom", sdk vrwin.h; V149): the menu bar (the kernel's),
   the title band (card rows 2-3), the toolbar (4-5: New, Save,
   Settings, the model), the conversation (card rows 7-50: rows of 16
   pixels, 2 card rows each, so that each has its own colours; the
   X16's CP437 font in cs_draw's cells, cards 4-76), the scroll bar
   (Sunroom's, vr_scroll: cards 78-79; sbar.c in an overlay with room), the
   input box (51-57: three lines of 12 pixels, Send, which is Stop while
   a reply comes), the status bar (58-59: what is happening at its left;
   the model and the tokens, or the modem's state, at its right).

   A message's first row has its badge (cards 1-2: the user's on blue,
   Claude's on orange, a note's on yellow, a turn left out on red); the
   user's rows are on the sidebar's paper, Claude's on the page's; an
   empty row between two messages. While a reply comes the view follows
   it (unless it was scrolled back); before its first text, its row says
   "Thinking" (Opus thinks first: a pause of a few seconds).

   Keys: typing goes to the input box (Left, Right, Home, End,
   Backspace, Delete; Up and Down its lines, else the conversation);
   Return sends, Shift+Return a new line; Esc stops a reply (the part
   that came is kept); PgUp, PgDn, the wheel and the scroll bar scroll
   (its arrows a row, its track a page, its thumb dragged); Ctrl+V pastes
   the clipboard's text, Ctrl+N a new conversation, Ctrl+S saves it,
   Ctrl+Q quits.

   Veranda Ask (-DASK, DECISIONS V116): the same, its texts its own; the
   toolbar's model and the status bar's right (the plan's "Using ChatGPT
   plan", "Manage usage: chatgpt.com/settings/usage") from its overlay 4;
   a turn started by its overlay 5 (a renewal of the sign-in first, when
   the access token is known to have expired).

   MIT licence (see LICENSE). */
#include <veranda.h>
#include <vr.h>
#include <string.h>
#include <theme.h>
#include <vrnet.h>
#include <vrser.h>
#include <vrwin.h>
#include "claude.h"
#pragma code-name ("OVERLAY1")
#pragma rodata-name ("OVL1RO")

char msg[100];
unsigned char hl;
char right[64];
unsigned int v_top;
static unsigned char follow = 1, drawn_gen, dragging, lastnet = 0xFF;
static unsigned int tshow, tthink, drawn_rows;
static unsigned char wasbusy;
static unsigned int in_top;             /* the input's first line shown */

static const char busy_s[] = "A reply is coming: wait for it, or Stop (Esc).";
#define BUSY() (tstate != T_IDLE)
#define MAXTOP() (st_rows > BROWS ? st_rows - BROWS : 0)
#define RESERVE 12288u                  /* room kept for a reply (4096 tokens) */

/*---------------------------------------------------------------- the status bar */

static void where(void)
{
    unsigned char s = net_on ? net_state() : NET_OFF;
    lastnet = s;
    if (!net_on)
        strcpy(right, "No network card");
    else if (s == NET_FAULT)
        strcpy(right, "The modem does not answer");
    else if (s != NET_READY)
        strcpy(right, "Looking for the modem ...");
    else {
#ifdef ASK
        ov4(ask_right);
#else
        strcpy(right, model_name[C.model]);
        if (C.srv)
            strcat(right, " on my PC");        /* (Claude Code, the bridge: V115) */
#endif
    }
}

static void status2(void)
{
    win_status(msg, right);
}

void __fastcall__ ui_status(const char *s)
{
    if (s != msg)
        strncpy(msg, s, sizeof msg - 1);
    status2();
#ifdef CLAUDE_TEST
    strcpy(line, "CL STATUS ");
    strcat(line, msg);
    gt_log(line);
#endif
}

#ifdef CLAUDE_TEST
/* (V149) msg shown, for the test's overlay: through main.c's t_ui, which
   maps this overlay first (a direct call from another bank ran whatever
   that bank holds at this address) */
void t_status(void) { ui_status(msg); }
#endif

/*---------------------------------------------------------------- the toolbar */

void toolbar(void)
{
    dispBufferOn = ST_WR_FORE;
    SetPattern(0);
    WRectangle(0, TOOLY, 639, TOOLY + 14);
#ifdef ASK
    if (rqm) {
        ovq(rq_bar);                    /* (V199: a request's Send, Cancel; Use this, Try again) */
        return;
    }
#endif
    button(1, 6, TOOLY + 1, "New", 0);
    button(8, 6, TOOLY + 1, "Save", 0);
    button(15, 10, TOOLY + 1, "Settings", 0);
    button(26, 8, TOOLY + 1, "Attach", 0);
    button(35, 7, TOOLY + 1, "Chats", 0);
    if (att_on)
        put(43, TOOLY + 4, att_lbl, 36, 0);     /* ("Attached: NAME (n lines) [Remove]": code.c's) */
    else {
#ifdef ASK
        ov4(ask_bar);
#else
        strcpy(line, "Model: ");
        strcat(line, model_name[C.model]);
        put(43, TOOLY + 4, line, 36, 0);
#endif
    }
}

/*---------------------------------------------------------------- the conversation */

static const unsigned char badge_g[8] = { G_YOU, G_CLAUDE, G_NOTE, G_WARN, G_WARN, G_NONE, G_YOU, G_CLAUDE };
#ifdef ASK
static const unsigned char badge_c[8] = { SKY2, GREEN, YELLOW, RED, RED, 0, CHROME, CHROME };
#else
static const unsigned char badge_c[8] = { SKY2, ORANGE, YELLOW, RED, RED, 0, CHROME, CHROME };
#endif

static void __fastcall__ draw_row(unsigned char r)
{
    unsigned int i = v_top + r, y = BODYY + r * RH;
    unsigned char fl, k, cr = BROW + (r << 1), paper;
    if (i >= st_rows) {
        SetPattern(0);
        WRectangle(8, y, SBX * 8 - 1, y + RH - 1);
        if (hl)
            theme_rect(0, SBX, cr, 2, 0);
        return;
    }
    fl = row_get(i);
    k = fl & R_KIND;
    if (k == R_GAP) {
        SetPattern(0);
        WRectangle(8, y, SBX * 8 - 1, y + RH - 1);
        if (hl)
            theme_rect(0, SBX, cr, 2, 0);
        return;
    }
    if (fl & (R_FENCE | R_CEND)) {
        c_row = i;
        ovc(code_label);
    }                /* (a fence: its labels, V123) */
    cells(TX, y, TW, RH, 0);
    glyph(8 + 3, y, fl & R_FIRST ? badge_g[k] : G_NONE, RH, ((fl & R_FIRST) && !hl && k == R_USER ? GL_REV : 0) | (k >= R_CUSER ? GL_DIM : 0));
    if (!hl && (fl & R_CODE))
        WVerticalLine(0xFF, TX * 8 - 4, y, y + RH - 1);
    if (hl) {
        paper = k == R_USER || k == R_UNSENT || k == R_CUSER ? SIDEBAR : 0;
        theme_rect(0, 1, cr, 2, paper);
        theme_rect(1, 2, cr, 2, fl & R_FIRST ? badge_c[k] : paper);
        theme_rect(3, SBX - 4, cr, 2, fl & R_CODE ? CHROME : paper);   /* (card 77: the margin by the bar) */
    }
}

/* the scroll bar (V149: Sunroom's, sbar.c): the rows shown among all;
   drawn when its thumb moved (SB_FORCE: whatever it shows) */
static void bar_set(void)
{
    sbar.cx = SBX;
    sbar.cy = BROW;
    sbar.len = TRACK;
    sbar.vert = 1;
    sbar.first = v_top;
    sbar.shown = BROWS;
    sbar.total = st_rows;
}

static void __fastcall__ scrollbar(unsigned char force)
{
    bar_set();
    sb_r = force;
    ovsb(sb_draw);
}

static void page(void)
{
    unsigned char r;
    dispBufferOn = ST_WR_FORE;
#ifdef CLAUDE_TEST
    ++t_pages;
#endif
    for (r = 0; r < BROWS; ++r)
        draw_row(r);
    st_dirty = 0xFFFF;
    drawn_rows = st_rows;
    scrollbar(SB_FORCE);
}

static void __fastcall__ scroll_to(long t)
{
    unsigned int m = MAXTOP();
    if (t > (long)m)
        t = m;
    if (t < 0)
        t = 0;
    follow = (unsigned int)t == m;
    if ((unsigned int)t == v_top)
        return;
    v_top = t;
    page();
}

/* what changed in the store, drawn */
static void body(void)
{
    unsigned int d = st_dirty, m, e;
    unsigned char r;
    if (drawn_gen != st_gen) {
        if (!BUSY())
            ovc(code_scan);             /* (the code blocks' rows marked again: V123) */
        drawn_gen = st_gen;
        d = 0;
        v_top = follow ? MAXTOP() : v_top > MAXTOP() ? MAXTOP() : v_top;
        page();
        return;
    }
    if (d == 0xFFFF)
        return;
    m = MAXTOP();
    if (follow && BUSY()) {             /* (a reply coming: half a page at once, the rows under it empty) */
        if (st_rows > v_top + BROWS) {
            v_top = st_rows - BROWS / 2;
            page();
            return;
        }
    } else if ((follow && v_top != m) || v_top > m) {
        v_top = m;
        page();
        return;
    }
    st_dirty = 0xFFFF;
    dispBufferOn = ST_WR_FORE;
    e = st_rows > drawn_rows ? st_rows : drawn_rows;    /* (rows past both were empty and are) */
    drawn_rows = st_rows;
    e = e <= v_top ? 0 : e - v_top >= BROWS ? BROWS : e - v_top;
    r = d <= v_top ? 0 : d - v_top >= BROWS ? BROWS : d - v_top;
    for (; r < e; ++r)
        draw_row(r);
    scrollbar(0);
}

/*---------------------------------------------------------------- the input box */

#define LMAX 40
#pragma bss-name (push, "OVL1BSS")
static unsigned int ls[LMAX];      /* its lines' starts (V149: this overlay's, main RAM's room) */
#pragma bss-name (pop)
static unsigned char nls, cl, cc;       /* lines, the cursor's line and column */

/* the input in lines: INTW characters, or to a line feed */
static void lines(void)
{
    unsigned int p = 0, q;
    unsigned char n, soft, nl;
    nls = 0;
    cl = cc = 0;
    for (;;) {
        ls[nls] = p;
        for (n = 0, q = p; n < INTW && q < in_len && inbuf[q] != '\n'; ++n)
            ++q;
        nl = q < in_len && inbuf[q] == '\n';
        soft = n == INTW && !nl;        /* (full: the cursor after it is on the next line) */
        if (in_cur >= p && (in_cur < q || (in_cur == q && !soft))) {
            cl = nls;
            cc = in_cur - p;
        }
        ++nls;
        if (nls == LMAX)
            break;
        if (nl)
            p = q + 1;
        else if (soft)
            p = q;
        else
            break;
    }
}

/* line t's length (the cursor's last column on it) */
static unsigned char __fastcall__ line_len(unsigned char t)
{
    unsigned int p = ls[t];
    unsigned char n;
    for (n = 0; n < INTW && p + n < in_len && inbuf[p + n] != '\n'; ++n)
        ;
    if (n == INTW && !(p + n < in_len && inbuf[p + n] == '\n'))
        --n;
    return n;
}

#ifdef ASK
static const char hint[] = "Type your question here: Return sends, Shift+Return a new line.";
static const char rhint[] = "Press Return to send (then to use the answer). Esc: cancel.";
#else
static const char hint[] = "Type to Claude here: Return sends, Shift+Return a new line.";
#endif

static void input(void)
{
    unsigned char k, n, i;
    unsigned int p, y;
    lines();
    if (cl < in_top)
        in_top = cl;
    if (cl >= in_top + INL)
        in_top = cl - INL + 1;
    dispBufferOn = ST_WR_FORE;
    for (k = 0; k < INL; ++k) {
        y = INTY + k * 12;
        n = 0;
        if (!in_len && !k) {
            strcpy(cs_txt, " ");
#ifdef ASK
            strcat(cs_txt, rqm ? rhint : hint);
#else
            strcat(cs_txt, hint);
#endif
            n = strlen(cs_txt);
        } else if (in_top + k < nls) {
            p = ls[in_top + k];
            while (n < INTW && p < in_len && inbuf[p] != '\n')
                cs_txt[n++] = inbuf[p++];
        }
        for (i = n; i < INTW; ++i)
            cs_txt[i] = ' ';
        cells(INTX, y, INTW, 12, 0);
        if (cl == in_top + k) {
            p = in_cur;
            cs_txt[0] = p < in_len && inbuf[p] != '\n' ? inbuf[p] : ' ';
            cells(INTX + cc, y, 1, 12, 1);
        }
    }
}

static void input_box(void)
{
    dispBufferOn = ST_WR_FORE;
    SetPattern(0);
    WRectangle(0, INY, 639, 463);
    WHorizontalLine(0xFF, 0, 639, INY);
    rframe(INTX * 8 - 5, INY + 5, (INTX + INTW) * 8 + 4, INY + 51);
#ifdef ASK
    button(SENDX, 7, INY + 19, BUSY() ? "Stop" : rqm == 2 ? "Use" : "Send", 0);
#else
    button(SENDX, 7, INY + 19, BUSY() ? "Stop" : "Send", 0);
#endif
    if (hl)
        theme_rect(0, 80, INY >> 3, 7, 0);
    input();
}

static void __fastcall__ insert(unsigned char c)
{
    if (in_len >= INMAX)
        return;
    memmove(inbuf + in_cur + 1, inbuf + in_cur, in_len - in_cur + 1);
    inbuf[in_cur++] = c;
    ++in_len;
}

static void clear_input(void)
{
    in_len = in_cur = in_top = 0;
    inbuf[0] = 0;
}

/*---------------------------------------------------------------- notes */

static void __fastcall__ note(const char *s)
{
    strcpy(line, s);
    st_add(K_NOTE, line, strlen(line));
}

/*---------------------------------------------------------------- a turn */

void page_all(void)
{
    dispBufferOn = ST_WR_FORE;
    SetPattern(0);
    WRectangle(0, 48, 639, 463);
    if (hl)
        theme_rect(0, 80, 6, 52, 0);
    toolbar();
    drawn_gen = st_gen - 1;
    body();
    input_box();
    where();
    status2();
}

static void send(void)
{
    if (BUSY()) {
        ui_status(busy_s);
        Beep();
        return;
    }
#ifdef ASK
    if (rqm) {                          /* (V199: a request's message, again: rq.c's) */
        rqa = RA_SEND;
        ovq(rq_do);
        if (c_ui) {
            ui_status(msg);
            return;
        }
        goto go;
    }
#endif
    if (!C.key[0]) {
#ifdef ASK
        ui_status(C.srv ? "There is no API key yet: Settings." : "Not signed in yet: Settings, Continue with ChatGPT.");
#else
        ui_status(C.srv ? "There is no bridge password yet: Settings." : "There is no API key yet: Settings.");
#endif
        ov4(pg_show);
        return;
    }
    if (!in_len && !att_on)
        return;
    if (!c_go) {
        ovv(c_presend);                 /* (compacted first, when it is long and Settings say so: V123) */
        if (c_go == 2) {
            wasbusy = 1;
            input_box();
            return;                     /* (this question goes after it: done()) */
        }
    }
    c_go = 0;
    st_prot = st_used;
    if (!st_room(RESERVE + in_len + 64)) {
        message("The conversation is full.", "Start a new one: File > New conversation.");
        return;
    }
    if (st_cutn)
        note("(The oldest turns were dropped to make room: Claude no longer sees them.)");
    st_prot = st_used;
    ovv(c_ask_user);                    /* (t_umsg: the question, the file attached after it) */
#ifdef ASK
go:
#endif
    if (t_umsg == NOMSG || !st_open(K_CLAUDE)) {
        message("The conversation is full.", "Start a new one: File > New conversation.");
        return;
    }
    t_rmsg = st_cur;
    st_prot = t_umsg;
    clear_input();
    follow = 1;
    ovv(plan);                          /* (what is sent: Remember, old code shortened, the model) */

#ifdef ASK
    ov5(ask_go);                        /* (the turn, or the sign-in renewed first) */
    if (!tgo)
        return;
#else
    if (!turn_start())
        return;                         /* (its end shown at the next pass) */
#endif
    strcpy(msg, "Connecting to ");
    strcat(msg, C.host);
    strcat(msg, C.tls ? " (TLS) ..." : " ...");
    ui_status(msg);
    wasbusy = 1;
    tthink = 0;
    input_box();
#ifdef ASK
    if (rqm)
        toolbar();                      /* (Stop) */
#endif
}
/* the turn ended: what it left (overlay 4), drawn */
static void done(void)
{
    msg[0] = 0;
#ifdef ASK
    if (!t_comp || rq != RQ_CHAT)       /* (a compaction's own end: code.c's; a renewal's: turn.c's) */
#else
    if (!t_comp)                        /* (a compaction's own end: code.c's) */
#endif
        ov2(turn_end);
    ovv(c_after);                       /* (the usage, the code blocks; a compaction's end: V123) */
    if (tstate != T_IDLE)
        return;                         /* (Ask: the turn sent again after a renewal) */
#ifdef ASK
    if (!rqm)                           /* (V199: a request's text is not kept) */
#endif
    ovh(h_save);                        /* (the chat saved: /DOCUMENTS/Chats) */
    wasbusy = 0;
#ifdef CLAUDE_TEST
    t_ov5(gt_turn);
#endif
    ui_status(msg);
    toolbar();
    input_box();
    where();
    status2();
    if (c_go == 1)
        send();                         /* (the question that waited for its compaction) */
}

/*---------------------------------------------------------------- every pass */

void ui_tick(void)
{
    signed char w;
    unsigned int f, lim;
    unsigned char s;
    char *p;
    if (pg_on)
        return;
    asm("sei");
    w = (signed char)mouseWheel;
    mouseWheel = 0;
    asm("cli");
    if (w && !menuNumber)
        scroll_to((long)v_top + 3 * w);
    if (dragging) {
        if (mouseData & 0x80)
            dragging = 0;
        else {
            f = mouseYPosW < BODYY + 24 ? 0 : mouseYPosW - BODYY - 24;  /* (the arrow, half a thumb) */
            lim = st_rows;
            if (lim > BROWS)
                scroll_to((long)f * (lim - BROWS) / (TRACK * 8 - 48));
        }
    }
#ifdef CLAUDE_TEST
    f = ser_frames;
    body();
    t_fb += ser_frames - f;
#else
    body();
#endif
    if (tdone) {
        done();
        body();
        return;
    }
    if (BUSY()) {
#ifdef ASK
        if (!p_text && rq == RQ_CHAT && tstate >= T_SEND && ser_frames - tthink >= 15) {
#else
        if (!p_text && tstate >= T_SEND && ser_frames - tthink >= 15) {
#endif
            tthink = ser_frames;
            ovs(thinking);
        }
        if (ser_frames - tshow < 20)
            return;
        tshow = ser_frames;
        if (tstate == T_SEND && ttx) {
            strcpy(msg, "Sending: ");
            p = unum(msg + strlen(msg), ttx);
            strcpy(p, " of ");
            p = unum(p + 4, tbody);
            strcpy(p, " bytes ...");
        } else if (tstate == T_RECV || (tstate == T_SEND && trx)) {
#ifdef ASK
            if (rq != RQ_CHAT) {
                strcpy(msg, rq == RQ_SIGNIN ? "Signing in: finish in the browser on your PC ... " : "Renewing the sign-in ... ");
                p = unum(msg + strlen(msg), (ser_frames - tt0) / 60);
                strcpy(p, rq == RQ_SIGNIN ? " s   (Esc cancels)" : " s");
            } else if (!p_text) {
                strcpy(msg, "Thinking ... ");
                p = unum(msg + strlen(msg), (ser_frames - tt0) / 60);
                strcpy(p, " s   (Esc stops)");
            } else {
                strcpy(msg, "Writing ... ");
                p = unum(msg + strlen(msg), p_text);
                strcpy(p, " characters   (Esc stops)");
            }
#else
            if (!p_text) {
                strcpy(msg, "Claude is thinking ... ");
                p = unum(msg + strlen(msg), (ser_frames - tt0) / 60);
                strcpy(p, " s   (Esc stops)");
            } else {
                strcpy(msg, "Claude is writing ... ");
                p = unum(msg + strlen(msg), p_text);
                strcpy(p, " characters   (Esc stops)");
            }
#endif
        } else
            return;
        status2();
        return;
    }
    s = net_on ? net_state() : NET_OFF;
    if (s != lastnet) {
        where();
        status2();
    }
}

/*---------------------------------------------------------------- the menus' actions */


void m_quit(void)
{
    GotoFirstMenu();
    if (BUSY() && !yesno("A reply is still coming.", "Quit anyway?"))
        return;
    turn_stop();
#ifdef ASK
    if (rqm) {                          /* (V199: AI.RES written, the program that asked back) */
        if (rqa != RA_USE)
            rqa = RA_CANCEL;
        ovq(rq_do);
    }
#endif
    net_stop();
    EnterDeskTop();
}

void m_new(void)
{
    GotoFirstMenu();
#ifdef ASK
    if (rqm)
        return;
#endif
    if (BUSY()) {
        ui_status("A reply is coming: Stop it first (Esc).");
        return;
    }
    st_clear();
    p_in = p_out = p_cache = 0;
    ovv(c_newconv);
    note("A new conversation.");
    follow = 1;
    page_all();
    ui_status("A new conversation.");
}

void m_save(void)
{
    GotoFirstMenu();
    if (!ask("Save the conversation to /DOCUMENTS as:", sv_name, 38) || !sv_name[0])
        return;
    ov2(conv_save);
    if (sv_err == 1)
        message("The file cannot be written:", sv_name);
    else if (!sv_err) {
        strcpy(msg, "Saved to /DOCUMENTS/");
        strcat(msg, sv_name);
        ui_status(msg);
    }
}

void m_settings(void)
{
    GotoFirstMenu();
    if (BUSY()) {
        ui_status(busy_s);
        return;
    }
    ov4(pg_show);
}

#ifndef ASK
static void __fastcall__ set_model(unsigned char m)
{
    GotoFirstMenu();
    if (BUSY()) {
        ui_status(busy_s);
        return;
    }
    C.model = m;
    ov4(cfg_save);
    ovsb(model_marks);
    toolbar();
    where();
    strcpy(msg, "The model: ");
    strcat(msg, model_name[m]);
    ui_status(msg);
}

void m_opus(void) { set_model(M_OPUS); }
void m_sonnet(void) { set_model(M_SONNET); }
void m_haiku(void) { set_model(M_HAIKU); }
#endif

/* V123: code.c's commands (its bank at $A000 while they run, so they
   draw nothing of this overlay's: c_ui says what is to be drawn after) */
static void __fastcall__ c_run(unsigned char b, void (*f)(void))
{
    c_ui = 0;
    ovb(b, f);
    if (c_ui & CU_ALL)
        page_all();
    if (c_ui & CU_TOOL)
        toolbar();
    if (c_ui & CU_GOTO)
        scroll_to(c_row);
    if (c_ui & CU_NEW)
        m_new();
    if (c_ui & CU_STATUS)
        ui_status(msg);
    if (BUSY()) {                       /* (a compaction started) */
        wasbusy = 1;
        tthink = 0;
        input_box();
    }
}

static void __fastcall__ code_do(unsigned char b, void (*f)(void))
{
    GotoFirstMenu();
#ifdef ASK
    if (rqm)
        return;
#endif
    if (BUSY()) {
        ui_status(busy_s);
        return;
    }
    c_run(b, f);
}

void m_ccopy(void) { code_do(bCode, c_copy); }
void m_csave(void) { code_do(bFiles, c_save); }
void m_cgo(void) { code_do(bCode, c_choose); }
void m_crep(void) { code_do(bCode, c_reply); }
void m_catt(void) { code_do(bFiles, c_attach); }
void m_compact(void) { code_do(bConv, c_compact); }
void m_conv(void) { code_do(bConv, c_conv); }
void m_about(void) { code_do(bCode, c_about); }
void m_chats(void) { code_do(bHist, h_page); }

/*---------------------------------------------------------------- input */

static void pg_done(void)
{
    if (pg_on)
        return;
    page_all();
    if (pg_saved) {
        pg_saved = 0;
#ifdef ASK
        if (cfg_err)
            message("ASK.CFG cannot be written.", "(the settings are in /VERANDA/.SYSTEM)");
        else if (tstate == T_IDLE)
            ui_status(!C.key[0] ? "Settings saved (not signed in, no key yet)." : "Settings saved. Type below.");
#else
        if (cfg_err)
            message("CLAUDE.CFG cannot be written.", "(the settings are in /VERANDA/.SYSTEM)");
        else
            ui_status(!C.key[0] ? "Settings saved (no key or password yet)." :
                      C.srv ? "Settings saved: Claude Code on my PC. Type below." : "Settings saved. Type to Claude below.");
#endif
    }
}

#ifdef ASK
/* (V199) a request's button or key (rqa) */
static void r_act(void)
{
    if (rqa == RA_SEND)
        send();
    else if (rqa == RA_STOP)
        turn_stop();
    else if (rqa >= RA_USE)
        m_quit();
}
#endif

static void press(void)
{
    unsigned int x = mouseXPos, y = mouseYPosW;
    unsigned char c = x >> 3;
    if (mouseData & 0x80)
        return;
#if defined(CLAUDE_TEST) && !defined(ASK)     /* (V199, Ask: overlay 1's room; no check reads it) */
    strcpy(line, "CL PRESS ");
    unum(line + 9, x);
    strcat(line, " ");
    unum(line + strlen(line), y);
    gt_log(line);
#endif
    if (pg_on) {
        if (pg_on == 3)
            c_run(bHist, h_press);      /* (the Chats page: V123) */
        else if (pg_on == 2)
            ovv(cv_press);              /* (the Conversation page: V123) */
        else
            ov4(pg_press);
        pg_done();
        return;
    }
    if (y >= TOOLY && y < TOOLY + 15) {
#ifdef ASK
        if (rqm) {
            c_col = c;
            ovq(rq_hit);
            r_act();
            return;
        }
#endif
        if (c >= 1 && c < 7)
            m_new();
        else if (c >= 8 && c < 14)
            m_save();
        else if (c >= 15 && c < 25)
            m_settings();
        else if (c >= 26 && c < 34)
            m_catt();
        else if (c >= 35 && c < 42)
            m_chats();
        else if (c >= 43 && att_on)
            code_do(bCode, c_unattach);
        return;
    }
    if (y >= INY + 19 && y < INY + 33 && c >= SENDX && c < SENDX + 7) {
        if (BUSY())
            turn_stop();
#ifdef ASK
        else if (rqm) {
            c_col = 0xFF;
            ovq(rq_hit);
            r_act();
        }
#endif
        else
            send();
        return;
    }
    if (x >= SBX * 8 && y >= BODYY && y < BODYY + TRACK * 8) {
        bar_set();
        ovsb(sb_hit);
        switch (sb_r) {
        case VS_BACK: scroll_to((long)v_top - 1); break;
        case VS_FWD: scroll_to((long)v_top + 1); break;
        case VS_PGBACK: scroll_to((long)v_top - (BROWS - 1)); break;
        case VS_PGFWD: scroll_to((long)v_top + (BROWS - 1)); break;
        case VS_THUMB: dragging = 1;
        }
    }
    else if (y >= BODYY && y < BODYY + BROWS * RH && c >= TX && !BUSY()) {
        c_row = v_top + (y - BODYY) / RH;       /* (a code block's labels: V123) */
        c_col = c - TX;
        c_run(bCode, code_click);
    }
}

static void __fastcall__ line_move(signed char by)
{
    unsigned char t = cl + by, n;
    if (by < 0 && !cl)
        return;
    if (t >= nls)
        return;
    n = line_len(t);
    in_cur = ls[t] + (cc < n ? cc : n);
}

static void key(void)
{
    unsigned char k = keyData, m = keyDataMods, c;
    if (pg_on) {
        if (pg_on == 3)
            c_run(bHist, h_key);
        else if (pg_on == 2)
            ovv(cv_key);
        else
            ov4(pg_key);
        pg_done();
        return;
    }
#ifdef ASK
    if (rqm) {                          /* (V199: a request's keys, rq.c's; the scrolling keys below) */
        ovq(rq_key);
        if (rqa != RA_PASS) {
            r_act();
            return;
        }
    }
#endif
    if (m & 2) {                        /* Ctrl */
        switch (k) {
        case 22:                        /* V */
            ovc(paste);
            for (k = 0; line[k]; ++k) {
                c = line[k];
                if (c == '\r')
                    c = '\n';
                if (c == '\n' && line[k + 1] == '\n' && line[k] == '\r')
                    continue;
                if (c == '\n' || (c >= 32 && c < 127) || c >= 0xA0)
                    insert(c);          /* (the Text Scrap: Veranda's set) */
            }
            break;
        case 14: m_new(); return;       /* N */
        case 17:                        /* Q (V149; not Ctrl+Down: KEY_DOWN is 17) */
            if (!(m & KEYM_ARROW))
                m_quit();
            return;
        case 19: m_save(); return;      /* S */
        case 11: m_ccopy(); return;     /* K: the last code block copied (V123) */
        case 12: m_chats(); return;     /* L: the Chats page */
        case 5: m_csave(); return;      /* E: saved */
        case 1:                         /* Shift+A: a file attached */
            if (m & 1)
                m_catt();
            return;
        case 13:                        /* Return: this question to the cheap model */
            t_cheap = 1;
            send();
            t_cheap = 0;
            return;
        default: return;
        }
        input();
        return;
    }
    if (m & KEYM_ARROW) {
        switch (k) {
        case KEY_LEFT: if (in_cur) --in_cur; break;
        case KEY_RIGHT: if (in_cur < in_len) ++in_cur; break;
        case KEY_UP:
            if (nls > 1 && cl)
                line_move(-1);
            else
                scroll_to((long)v_top - 1);
            break;
        case KEY_DOWN:
            if (nls > 1 && cl + 1 < nls)
                line_move(1);
            else
                scroll_to((long)v_top + 1);
            break;
        }
        input();
        return;
    }
    switch (k) {
    case 13:
        if (m & 1)
            insert('\n');
        else {
            send();
            return;
        }
        break;
    case 8:
        if (!in_cur)
            return;
        --in_cur;
        /* (on: Delete's) */
    case KEY_DELETE:
        if (in_cur >= in_len)
            return;
        memmove(inbuf + in_cur, inbuf + in_cur + 1, in_len - in_cur);
        --in_len;
        break;
    case KEY_HOME: in_cur = 0; break;
    case KEY_END: in_cur = in_len; break;
    case KEY_PGUP: scroll_to((long)v_top - (BROWS - 1)); return;
    case KEY_PGDN: scroll_to((long)v_top + (BROWS - 1)); return;
    case KEY_ESC:
        if (BUSY())
            turn_stop();
        else
            scroll_to(30000);
        return;
    default:
        if (k >= 32 && k < 127)
            insert(k);
        else if (k >= 160 && !(m & 4))
            insert(k);                  /* (V143: Veranda's set, as the font has it;
                                           right Alt's Polish letters too) */
        else
            return;
    }
    input();
}


void ui_start(void)
{
    dispBufferOn = ST_WR_FORE;
    SetPattern(0);
    WRectangle(0, 0, 639, 15);
    theme_load();
    theme_palette();
#ifdef ASK
    strcpy(line, "Veranda Ask");
#else
    strcpy(line, "Veranda Claude");
#endif
    win_all(line);
    theme_menus();
    ovsb(menus);
    hl = theme_none() ? 0 : theme.hilite ? theme.hilite : SELECT;
    ov4(cfg_load);
    ovsb(model_marks);
    DoMenu((void *)&mbar, 0);
#ifdef ASK
    strcpy(sv_name, "ASK.TXT");
#else
    strcpy(sv_name, "CLAUDE.TXT");
#endif
    st_clear();
#ifdef ASK
    ovq(rq_start);                      /* (V199: another program's request, AI.REQ: rqm) */
    if (!rqm)
#endif
    ov4(turn_hello);
    page_all();
    otherPressVec = VR_FN(press);
    keyVector = VR_FN(key);
#ifdef ASK
    if (rqm)
        ui_status(msg);
    else if (!C.key[0]) {
        ui_status(C.srv ? "No API key yet: Settings." : "Not signed in yet: Settings.");
        ov4(pg_show);
    } else
        ui_status("Type below; Return sends.");
#else
    if (!C.key[0]) {
        ui_status("No key or password yet: Settings.");
        ov4(pg_show);
    } else
        ui_status(C.srv ? "Claude Code on my PC: type below; Return sends." : "Type to Claude below; Return sends.");
#endif
}
