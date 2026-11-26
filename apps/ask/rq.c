/* Veranda Ask: a request from another program, "AI help on the selected
   text" (overlay 11, its own; DECISIONS V199;
   the protocol: docs/AIREQ.md).

   A program (Veranda Write) writes in /VERANDA/.SYSTEM:
     AI.IN      the text (ISO-8859-16, Veranda's set; CR, CR LF or LF at
                each paragraph's end; 8,192 bytes at most)
     AI.REQ     "AIREQ 1", "action <rewrite | shorten | grammar |
                translate-en | translate-pl | summarise | ask>",
                "question <text>" (ask), "back <its name>"
     START.REQ  "/VERANDA/APPS/Veranda Ask" (the desktop starts it, V198)
   and puts itself aside. Veranda Ask starts in request mode: AI.REQ and
   AI.IN are read and deleted, the conversation shows a note (what is
   asked, how many characters, the service and the model, that nothing
   goes before Send) and the message that would be sent; the toolbar has
   Send and Cancel. Nothing leaves the X16 before Send. The answer streams
   into the conversation (the preview); then Use this, Try again, Cancel.
   Use this writes AI.OUT (the answer: Veranda's set, CR at each
   paragraph's end) and AI.RES ("AIRES 1", "ok", ...); Cancel writes
   AI.RES "cancelled"; not set up (no sign-in, no API key: V201, only
   these), the network (no network card, no RAM banks for it, the modem
   silent: V201), a text too long, no text, a bad request: AI.RES
   "error <code>" and "message ...", after a box. Then the program named
   by "back" comes back (TaskCtl TASK_RESUME), else the desktop.

   In request mode the system prompt is rq_sys (auth.c sends it in place
   of the user's own), short answers do not apply, nothing is compacted
   and nothing is saved in Chats; only the request's message is sent.

   This bank is at $A000 while its code runs: nothing here calls ui.c
   (overlay 1); rqa and c_ui say what ui.c does after. What the kernel
   reads (names, buffers, a task's record) is in main RAM.

   MIT licence (see LICENSE). */
#include <veranda.h>
#include <string.h>
#include <vrpath.h>
#include <vrnet.h>
#include <vrser.h>
#include "claude.h"
#pragma code-name ("OVERLAY11")
#pragma rodata-name ("OVL11RO")
#pragma bss-name ("OVL11BSS")

#define NACT 7
#define A_ASK 6
#define FN dtext                        /* (a file's name: main RAM, the parser's, idle) */
#define QMAX 200

static const char *const a_word[NACT] = { "rewrite", "shorten", "grammar", "translate-en", "translate-pl",
    "summarise", "ask" };
static const char *const a_name[NACT] = { "Rewrite", "Shorten", "Fix grammar and spelling",
    "Translate into English", "Translate into Polish", "Summarise", "Ask about this text" };
static const char *const a_task[NACT] = {
    "Task: rewrite the text so that it reads clearly and naturally. Keep its meaning, its tone and about its length.",
    "Task: shorten the text to about half its length. Keep its main points and its tone.",
    "Task: correct the grammar, spelling and punctuation of the text. Change nothing else: keep its wording and style.",
    "Task: translate the text into English.",
    "Task: translate the text into Polish, with the Polish letters.",
    "Task: summarise the text in a few sentences, in the text's language.",
    "Task: answer the question below about the text, in the language of the question."
};

/* the system prompt of a request (auth.c's chat sends it: rq_sn bytes) */
const char rq_sys[] =
    "You are a writing assistant inside Veranda Write, a word processor on a Commander X16. "
    "The user's message has a task and a text between a line <<<TEXT and a line TEXT>>>. "
    "Return only the result: no introduction, no comment, no quotation marks around it, "
    "not the markers, no Markdown (no headings, no * or ** for emphasis, no tables, no code blocks). "
    "Keep the text's paragraphs: one line break between two paragraphs. "
    "Keep the text's language unless the task is to translate it. "
    "Use plain characters only (letters, also Polish ones, digits, punctuation); no emoji.";

static unsigned char act, ph, nbtn;     /* the action; the phase (P_*); the toolbar's buttons */
static unsigned char nre;               /* (V201) the modem started again at a Send */
static unsigned int um, tlen;           /* the request's message in the store; the text's bytes */
static char back[18];                   /* the program to bring back (its name) */
static unsigned char bx[3], bw[3], ba[3];
#define P_ASK   0                       /* the request shown: Send, Cancel */
#define P_SENT  1                       /* sent (a reply coming) */
#define P_READY 2                       /* an answer: Use this, Try again, Cancel */
#define P_FAIL  3                       /* not answered (or cut): Send again, Cancel */

/*---------------------------------------------------------------- files */

static unsigned char __fastcall__ fo(const char *name, unsigned char mode)
{
    unsigned char h;
    strcpy(FN, name);
    vr_cd(VR_DATA);
    h = FOpen(FN, mode);
    if (h < 2 || h > 4)
        return 0;
    if (mode == 'r' && dosStatus >= 20) {
        FClose(h);                      /* (CMDR-DOS opens a file that is not there) */
        return 0;
    }
    return h;
}

static void __fastcall__ del(const char *name)
{
    strcpy(FN, name);
    vr_cd(VR_DATA);
    FDelete(FN);
}

static unsigned char rh;                /* AI.RES */

static void __fastcall__ rl(const char *k, const char *v)
{
    strcpy(line, k);
    if (v) {
        strcat(line, " ");
        strncat(line, v, 120);
    }
    strcat(line, "\r\n");
    FWrite(rh, line, strlen(line));
}

/* AI.RES: "AIRES 1", the result; then the program back (else the desktop) */
static void __fastcall__ res_open(const char *r, const char *v)
{
    rh = fo("AI.RES", 'w');
    if (rh) {
        rl("AIRES", "1");
        rl(r, v);
    }
}

static void finish(void)
{
    unsigned char i;
    if (rh)
        FClose(rh);
    rh = 0;
    vr_cdback();
    turn_stop();
    net_stop();
#ifdef CLAUDE_TEST
    gt_log("CL RQ DONE");
#endif
    if (back[0])
        for (i = 0; i < TASK_MAX; ++i)
            if (!TaskCtl(TASK_INFO, i, line) && line[TR_STATE] && !strcmp(line + TR_NAME, back)) {
#ifdef CLAUDE_TEST
                gt_log("CL RQ BACK");
#endif
                TaskCtl(TASK_RESUME, i, 0);
            }
    EnterDeskTop();
}

/* an error: its box, AI.RES "error <code>", "message <a b>", back */
static void __fastcall__ fail(const char *code, const char *a, const char *b)
{
    message(a, b);
    res_open("error", code);
    if (rh) {
        strcpy(msg, a);
        strcat(msg, " ");
        strcat(msg, b);
        rl("message", msg);
    }
    finish();
}

/* (V201) not set up: only no sign-in (the plan) or no key (the API) */
static void not_set_up(void)
{
    if (C.srv)
        fail("not-set-up", "Veranda Ask has no OpenAI API key.", "Set one in Veranda Ask first.");
    fail("not-set-up", "Veranda Ask is not signed in.", "Sign in in Veranda Ask first.");
}

/* (V201) the network, not the sign-in: vrnet did not start (no UART on
   the card's ports, or no two RAM banks for it: a program aside holds
   them, the switcher in Fast mode), or the modem does not answer */
static void no_net(void)
{
    if (net_on)
        fail("network", "The modem does not answer.", "(TexElec's Serial & ESP32 Network Card)");
    if (ser_probe())
        fail("network", "Not enough memory for the network card", "(2 RAM banks): quit a program put aside.");
    fail("network", "No network card was found.", "Veranda Ask needs the Wi-Fi modem card.");
}

/*---------------------------------------------------------------- the request read */

static void __fastcall__ app(const char *s)
{
    strcpy(line, s);                    /* (st_append's text: main RAM) */
    st_append(line, strlen(line));
}

static char *__fastcall__ cnum(char *p, unsigned int v)
{
    if (v >= 1000) {
        p = unum(p, v / 1000);
        *p++ = ',';
        v %= 1000;
        *p++ = '0' + v / 100;
        *p++ = '0' + v / 10 % 10;
        *p++ = '0' + v % 10;
        *p = 0;
        return p;
    }
    return unum(p, v);
}

static void service(void)
{
    if (C.srv) {
        strcat(line, "an OpenAI API key, ");
        strcat(line, C.mslug);
    } else {
        strcat(line, "your ChatGPT plan, ");
        strcat(line, C.mname);
    }
}

/* AI.IN into the open message (Veranda's set: CR LF, CR, LF a line feed;
   TAB a space; other control characters and $7F-$9F dropped); 0: too long */
static unsigned char text_in(unsigned char h)
{
    unsigned int k, i, n;
    unsigned char c, cr = 0;
    tlen = 0;
    for (;;) {
        k = FRead(h, rbuf, 128);
        for (i = n = 0; i < k; ++i) {
            c = rbuf[i];
            if (c == '\n' && cr) {
                cr = 0;
                continue;
            }
            cr = c == '\r';
            if (cr)
                c = '\n';
            else if (c == '\t')
                c = ' ';
            else if ((c < 32 && c != '\n') || (c >= 0x7F && c < 0xA0))
                continue;
            line[n++] = c;
        }
        tlen += n;
        if (tlen > 8192)
            return 0;
        st_append(line, n);
        if (k < 128)
            return 1;
    }
}

/* at the start (ui_start's): AI.REQ read and deleted; rqm 1 when there
   is one: its note and its message in the store, msg the status bar's */
void rq_start(void)
{
    unsigned char h, i, v = 0;
    unsigned int n;
    char *p, *e, *q = 0;
    rqm = rqa = rh = ph = nbtn = nre = 0;
    act = 0xFF;
    back[0] = 0;
    rq_sn = sizeof rq_sys - 1;
    h = fo("AI.REQ", 'r');
    if (!h) {
        vr_cdback();
        return;
    }
    n = FRead(h, rbuf, 255);
    FClose(h);
    del("AI.REQ");
    rqm = 1;
    rbuf[n] = 0;
    for (p = (char *)rbuf; *p; p = e) {
        for (e = p; *e && *e != '\n' && *e != '\r'; ++e)
            ;
        if (*e)
            *e++ = 0;
        if (!strcmp(p, "AIREQ 1"))
            v = 1;
        else if (!memcmp(p, "action ", 7)) {
            if (!strcmp(p + 7, "summarize"))
                strcpy(p + 7, "summarise");
            for (i = 0; i < NACT; ++i)
                if (!strcmp(p + 7, a_word[i]))
                    act = i;
        } else if (!memcmp(p, "question ", 9))
            q = p + 9;
        else if (!memcmp(p, "back ", 5) && strlen(p + 5) < sizeof back)
            strcpy(back, p + 5);
    }
#ifdef CLAUDE_TEST
    strcpy(line, "CL RQ REQUEST ");
    strcat(line, act < NACT ? a_word[act] : "?");
    strcat(line, " back ");
    strcat(line, back);
    gt_log(line);
#endif
    h = fo("AI.IN", 'r');
    if (!v || act >= NACT || (act == A_ASK && (!q || !*q))) {
        if (h)
            FClose(h);
        del("AI.IN");
        fail("bad-request", "Veranda Ask cannot read this request", "(AI.REQ: AIREQ 1, an action it knows).");
    }
    if (!net_on)
        net_restart();                  /* (V201: as a turn does) */
    if (!net_on || !C.key[0]) {
        if (h)
            FClose(h);
        del("AI.IN");
        if (!C.key[0])
            not_set_up();
        no_net();
    }
    if (q && strlen(q) > QMAX)
        q[QMAX] = 0;
    /* the note: what is asked, what goes where */
    if (!st_open(K_NOTE))
        return;
    strcpy(line, back[0] ? back : "A program");
    strcat(line, " asks: ");
    strcat(line, a_name[act]);
    strcat(line, ". The message below goes to OpenAI (");
    service();
    strcat(line, ") only when you click Send. ");
    st_append(line, strlen(line));
    app("Cancel or Esc goes back with no change. Nothing of it is kept in Chats.");
    st_close();
    /* the message sent: the task, the question, the text between its markers */
    st_open(K_USER);
    um = st_cur;
    app(a_task[act]);
    if (act == A_ASK) {
        app("\nQuestion: ");
        for (p = q; *p; ++p)            /* (the question's control characters dropped) */
            if ((unsigned char)*p < 32 || ((unsigned char)*p >= 0x7F && (unsigned char)*p < 0xA0))
                *p = ' ';
        strcpy(line, q);
        st_append(line, strlen(line));
    }
    app("\n\n<<<TEXT\n");
    i = h ? text_in(h) : 1;
    if (h)
        FClose(h);
    del("AI.IN");
    if (!i) {
        st_clear();
        fail("too-long", "The text is too long for Veranda Ask:", "8,192 characters at most. Choose less.");
    }
    if (!tlen) {
        st_clear();
        fail("no-text", "There is no text to send.", "Choose some text first.");
    }
    app("\nTEXT>>>");
    st_close();
    vr_cdback();
    strcpy(msg, a_name[act]);
    strcat(msg, ": ");
    p = cnum(msg + strlen(msg), tlen);
    strcpy(p, " characters. Send, or Cancel (Esc).");
#ifdef CLAUDE_TEST
    strcpy(line, "CL RQ SHOWN ");
    unum(line + strlen(line), tlen);
    gt_log(line);
#endif
}

/*---------------------------------------------------------------- the toolbar */

static void __fastcall__ btn(unsigned char x, unsigned char w, const char *l, unsigned char a)
{
    button(x, w, TOOLY + 1, l, 0);
    bx[nbtn] = x;
    bw[nbtn] = w;
    ba[nbtn++] = a;
}

/* (toolbar()'s, its band cleared) the request's buttons; at a turn's end
   the phase (an answer to use, or not) and its status bar */
void rq_bar(void)
{
    unsigned char x;
    unsigned int n;
    if (ph == P_SENT && tstate == T_IDLE) {
        n = NOMSG;
        if (t_rmsg < st_used) {
            st_msg(t_rmsg);
            n = st_k == K_CLAUDE ? st_n : 0;
        }
        ph = rq == RQ_CHAT && p_status == 200 && p_ok && !p_inc && !p_errev && tend == TE_OK && n && n != NOMSG
             ? P_READY : P_FAIL;
        in_len = in_cur = 0;            /* (turn.c's text given back: not in request mode) */
        inbuf[0] = 0;
        strcpy(msg, ph == P_READY ? "Use this puts the answer in its place; Try again asks again."
                                  : "Not answered: Send tries again, or Cancel.");
        win_status(msg, right);
#ifdef CLAUDE_TEST
        strcpy(line, "CL RQ ANSWER ");
        unum(line + strlen(line), ph == P_READY ? n : 0);
        gt_log(line);
#endif
    }
    rqm = ph == P_READY ? 2 : 1;
    nbtn = 0;
    if (ph == P_READY) {
        btn(1, 10, "Use this", RA_USE);
        btn(12, 11, "Try again", RA_SEND);
        btn(24, 8, "Cancel", RA_CANCEL);
        x = 33;
    } else {
        btn(1, 8, tstate != T_IDLE ? "Stop" : "Send", tstate != T_IDLE ? RA_STOP : RA_SEND);
        btn(10, 8, "Cancel", RA_CANCEL);
        x = 19;
    }
    strcpy(line, a_name[act]);
    strcat(line, " - ");                /* (the service: in the note) */
    strcat(line, C.srv ? C.mslug : C.mname);
    put(x, TOOLY + 4, line, 79 - x, 0);
}

/* a click on the toolbar at card c_col (0xFF: the input box's button,
   the first one): rqa */
void rq_hit(void)
{
    unsigned char i, c = c_col;
    rqa = RA_NONE;
    if (c == 0xFF) {
        rqa = ba[0];
        return;
    }
    for (i = 0; i < nbtn; ++i)
        if (c >= bx[i] && c < bx[i] + bw[i])
            rqa = ba[i];
}

/* a key: rqa (RA_PASS: ui.c's own, the scrolling keys) */
void rq_key(void)
{
    unsigned char k = keyData, m = keyDataMods;
    rqa = RA_NONE;
    if (m & KEYM_ARROW || k == KEY_PGUP || k == KEY_PGDN)
        rqa = RA_PASS;
    else if (k == KEY_ESC)
        rqa = tstate != T_IDLE ? RA_STOP : RA_CANCEL;
    else if (m & 2) {
        if (k == 17)
            rqa = RA_CANCEL;            /* (Ctrl+Q: Quit, which is Cancel) */
    } else if (tstate != T_IDLE)
        ;
    else if (k == 13)
        rqa = ba[0];                    /* (Return: the first button) */
    else if ((k | 32) == 't' && ph == P_READY)
        rqa = RA_SEND;
}

/*---------------------------------------------------------------- what is done */

/* the answer (the reply at t_rmsg) into AI.OUT: a line feed is CR, the
   private glyphs ($80-$9F) '?'; the markers, if the model sent them back,
   and blank lines at its ends left out; its bytes */
static unsigned char __fastcall__ at(unsigned int a)
{
    st_copy(a, (char *)rbuf, 1);        /* (st_rd leaves the store's bank mapped: not from here) */
    return rbuf[0];
}

static unsigned int out_write(unsigned char h)
{
    unsigned int a, e, k, i, n = 0;
    unsigned char c;
    st_msg(t_rmsg);
    a = t_rmsg + 3;
    e = a + st_n;
    if (st_n >= 8) {
        st_copy(a, (char *)rbuf, 8);
        if (!memcmp(rbuf, "<<<TEXT\n", 8))
            a += 8;
        st_copy(e - 8, (char *)rbuf, 8);
        if (!memcmp(rbuf + 1, "TEXT>>>", 7))
            e -= 7;
    }
    for (;;) {                          /* (blank lines and spaces at both ends) */
        while (a < e && ((c = at(a)) == '\n' || c == ' '))
            ++a;
        if (a < e && ((c = at(e - 1)) == '\n' || c == ' '))
            --e;
        else
            break;
    }
    while (a < e) {
        k = e - a > 128 ? 128 : e - a;
        st_copy(a, (char *)rbuf, k);
        for (i = 0; i < k; ++i) {
            c = rbuf[i];
            if (c == '\n')
                c = '\r';
            else if (c >= 0x80 && c < 0xA0)
                c = '?';
            else if (c < 32 && c != '\t')
                c = ' ';
            rbuf[i] = c;
        }
        FWrite(h, rbuf, k);
        a += k;
        n += k;
    }
    return n;
}

/* ui.c's, rqa: RA_SEND (the request's message to be sent again: t_umsg;
   c_ui 1: not now, msg says why), RA_USE, RA_CANCEL (the files written,
   the program back: never returns) */
void rq_do(void)
{
    unsigned char h;
    unsigned int a, nx, n;
    c_ui = 0;
    if (rqa == RA_SEND) {
        if (!C.key[0])
            not_set_up();               /* (the sign-in ended meanwhile) */
        h = net_on ? net_state() : NET_OFF;
        if ((h == NET_FAULT || h == NET_OFF) && !nre) {
            nre = 1;                    /* (V201: once, as a turn does: the modem looked for again) */
            net_restart();
            h = NET_SYNC;
        }
        if (h == NET_FAULT || h == NET_OFF || !net_on)
            no_net();
        if (h != NET_READY) {
            strcpy(msg, "Looking for the modem: Send again in a moment.");
            c_ui = 1;
            return;
        }
        st_kind(um, K_USER);            /* (left out by a turn that failed) */
        a = st_msg(um);
        while (st_used > a) {           /* (what came after it: the last answer, notes) */
            for (nx = a; (n = st_msg(nx)) < st_used; nx = n)
                ;
            st_cur = nx;
            st_drop_last();
        }
        t_umsg = um;
        ph = P_SENT;
        return;
    }
    if (rqa == RA_USE && ph == P_READY) {
        h = fo("AI.OUT", 'w');
        n = h ? out_write(h) : 0;
        if (!h || FClose(h)) {
            del("AI.OUT");
            fail("write", "The answer cannot be written", "(/VERANDA/.SYSTEM/AI.OUT).");
        }
        res_open("ok", 0);
        if (rh) {
            rl("action", a_word[act]);
            rl("service", C.srv ? "api" : "plan");
            rl("model", g_slug);
            unum(msg, n);
            rl("bytes", msg);
        }
        finish();
    }
    del("AI.OUT");
    res_open("cancelled", 0);
    finish();
}
