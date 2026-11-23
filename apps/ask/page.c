/* Veranda Ask: the Settings page, the plan's notice, the toolbar's and the
   status bar's texts, the first notes (overlay 4; DECISIONS V116).

   The Settings page (over the conversation): the server (two rows: a
   click, or Left and Right): the ChatGPT plan or an OpenAI API key.
     the plan      the account signed in; the PC's address (its sign-in
                   helper, tools/chatgpt_signin.py, port 8643) and the
                   6-digit code it shows: Return (or the button) is
                   "Continue with ChatGPT": the page closes and the
                   sign-in runs on the PC (its browser); the models of the
                   plan (from the sign-in: up to 8 rows, a click, Up and
                   Down)
     an API key    the key (typed or Ctrl+V; stars but its last 4) and
                   the model (typed: gpt-6.2-sol)
   Tab moves between the two fields, Return saves (or signs in, a code
   typed), Esc cancels (ASK.CFG read again).

   The plan's notice, the first time it is used (OpenAI's words): "You're
   using your ChatGPT plan / Eligible usage in this app uses your ChatGPT
   plan. Manage usage in your ChatGPT settings." and "Got it".

   MIT licence (see LICENSE). */
#include <veranda.h>
#include <string.h>
#include <theme.h>
#include "claude.h"
#pragma code-name ("OVERLAY4")
#pragma bss-name ("OVL4BSS")
#pragma rodata-name ("OVL4RO")

/*---------------------------------------------------------------- the first notes */

static void __fastcall__ note(const char *s)
{
    unsigned int n = strlen(s), k;
    if (!st_open(K_NOTE))
        return;
    for (; n; n -= k, s += k) {
        k = n > 128 ? 128 : n;
        memcpy(line, s, k);
        st_append(line, k);
    }
    st_close();
}

static const char welcome[] =
    "Welcome to Veranda Ask: a conversation with OpenAI's models through the Wi-Fi modem. "
    "Type below, Return "
    "sends; Esc stops a reply. Chats are saved as you go: Ctrl+L lists them. "
    "Settings > Conversation: Remember and Compact send less.";
static const char noplan[] =
    "To use your ChatGPT plan (Plus or Pro), sign in from a PC on your network: copy "
    "PC/chatgpt_signin.py from the SD card to it and run  python3 chatgpt_signin.py  there; "
    "it shows a code. Then Settings: the PC's address and the code, Continue with ChatGPT; "
    "the PC's browser opens OpenAI's sign-in. Or use an OpenAI API key: Settings, Server.";
static const char nokey[] =
    "To use an OpenAI API key (paid by the token), type or paste it in Settings, or put a "
    "line key=sk-... in /VERANDA/.SYSTEM/ASK.CFG on the SD card from a PC.";

void turn_hello(void)
{
    note(welcome);
    if (!C.key[0])
        note(C.srv ? nokey : noplan);
}

static const char sys_default[] =
    "You are talking with someone on a Commander X16, an 8-bit computer, through "
    "Veranda Ask. Its screen shows 74 columns of plain text and cannot show Markdown, "
    "emoji or most Unicode. Write plain ASCII text only: no Markdown headings, no * or ** "
    "for emphasis, no tables, no emoji. Keep paragraphs short, with a blank line between "
    "them; use simple dashes for lists. Put code in a fenced block: a line ``` with the "
    "language (```basic, ```asm, ```c), the code, then a line ```; the user can copy it or "
    "save it. Number every line of the X16's BASIC. Be concise unless asked for detail.";

/* (auth.c's, ASK.CFG read without system=) the built-in system prompt into its bank */
void sys_fill(void)
{
    unsigned int i, k;
    for (i = 0; i < sizeof sys_default - 1; i += k) {
        k = sizeof sys_default - 1 - i > 64 ? 64 : sizeof sys_default - 1 - i;
        memcpy(line, sys_default + i, k);
        bk_put(tbank, TB_SYS + i, line, k);
    }
    slen = sizeof sys_default - 1;
}

void cfg_load(void)
{
    ov5(a_load);
}

void cfg_save(void)
{
    ov5(a_save);
}

/*---------------------------------------------------------------- the toolbar, the status bar */

/* (V129: right of the Chats button, cards 43-79, as Veranda Claude's model;
   it was drawn from card 27, over Attach and Chats) */
void ask_bar(void)
{
    if (C.srv) {
        strcpy(line, "API key: ");
        strcat(line, C.mslug);
    } else if (!C.key[0])
        strcpy(line, "ChatGPT plan: not signed in");
    else {
        strcpy(line, "Using ChatGPT plan: ");
        strcat(line, C.mname);
    }
    put(43, TOOLY + 4, line, 36, 0);
}

void ask_right(void)
{
    if (C.srv)
        strcpy(right, C.mslug);
    else if (year < 26)                 /* (V129: an unset clock reads 1 January 2000) */
        strcpy(right, "Set the clock: click \"Set clock\" in the menu bar");
    else
        strcpy(right, C.key[0] ? "Manage usage: chatgpt.com/settings/usage" : "ChatGPT plan: not signed in");
}

/*---------------------------------------------------------------- the Settings page */

#define PY      48
#define SRVY    64
#define ACCY    104
#define F1Y     120
#define F2Y     136
#define SIGNY   160
#define MODY    184
#define BTNY    320
#define HELPY   344
#define FX      12
#define FW      66

static unsigned char pf;                /* the field typed into: 0 the address or the key, 1 the code or the model */
static unsigned char nm;                /* the plan's models (sl.nmod) */

static void __fastcall__ field_box(unsigned int y, unsigned char on)
{
    if (on)
        strcat(line, "_");
    put(FX + 1, y + 4, line, FW - 2, 0);
    theme_rect(FX, FW, y >> 3, 2, CHROME);
}

static void key_text(void)
{
    unsigned char k, i, w = FW - 3;
    unsigned int n = klen;
    if (!n) {
        strcpy(line, "(none: type or paste your API key here)");
        return;
    }
    k = n > 4 ? n - 4 : 0;
    if (k > w - 4)
        k = w - 4;
    for (i = 0; i < k; ++i)
        line[i] = '*';
    bk_get(tbank, TB_KEY + (n > 4 ? n - 4 : 0), line + k, n > 4 ? 4 : n);
    line[k + (n > 4 ? 4 : n)] = 0;
}

static void fields(void)
{
    if (C.srv) {
        key_text();
        field_box(F1Y, !pf);
        strcpy(line, C.mslug);
        field_box(F2Y, pf);
    } else {
        strcpy(line, !sg_addr[0] && pf ? "(the PC's address and port, e.g. 192.168.1.20:8643)" : sg_addr);
        field_box(F1Y, !pf);
        strcpy(line, sg_code);
        field_box(F2Y, pf);
    }
}

static void __fastcall__ radio(unsigned int y, unsigned char on, const char *a, const char *b)
{
    strcpy(line, on ? "(*) " : "( ) ");
    strcat(line, a);
    while (strlen(line) < 28)
        strcat(line, " ");
    strcat(line, b);
    put(FX + 1, y + 4, line, FW - 2, on && !hl);
    theme_rect(FX, FW, y >> 3, 2, on && hl ? hl : 0);
}

static void __fastcall__ model_row(unsigned char m)
{
    static char row[64], t[40];
    bk_get(tbank + tlive, TB_MOD + m * 64, line, 64);
    memcpy(row, line, 64);
    strcpy(t, row);
    radio(MODY + m * 16, m == C.model, row + 32, t);
}

static void account(void)
{
    char *p;
    if (sl.acc && sl.ref) {
        strcpy(line, "Signed in with ChatGPT");
        if (sl.login) {
            strcat(line, " as ");
            p = line + strlen(line);
            bk_get(tbank + tlive, TB_LOGIN, p, sl.login);
            p[sl.login] = 0;
        }
    } else
        strcpy(line, sl.cid ? "Not signed in (the sign-in has ended)" : "Not signed in");
    put(FX + 1, ACCY + 4, line, FW - 2, 0);
}

static const char *const help_plan[] = {
    "Sign in with ChatGPT uses your ChatGPT plan (Plus or Pro): eligible usage",
    "counts against it. On a PC on your network run  python3 chatgpt_signin.py",
    "(PC/chatgpt_signin.py on the SD card): it shows a code. Type the PC's",
    "address and the code, then Return (Continue with ChatGPT): the PC's browser",
    "signs in, and the tokens come here; the PC keeps no copy. They are kept as",
    "plain text in ASK.CFG: the card is yours to keep. The modem makes the TLS",
    "connection (Zimodem's ATCS) and does NOT check the certificate.",
    0
};
static const char *const help_api[] = {
    "An OpenAI API key (platform.openai.com, API keys) is paid by the token.",
    "Type or paste it (Ctrl+V), or put a line key=sk-... in",
    "/VERANDA/.SYSTEM/ASK.CFG on the SD card from a PC: it is kept there as",
    "plain text: anyone with the card can use it. Type the model's name",
    "(gpt-6.2-sol). The modem makes the TLS connection (Zimodem's ATCS) and",
    "does NOT check the server's certificate.",
    0
};

static void pg_draw(void)
{
    unsigned char i;
    const char *const *h = C.srv ? help_api : help_plan;
    nm = sl.nmod;
    dispBufferOn = ST_WR_FORE;
    SetPattern(0);
    WRectangle(0, PY, 639, 463);
    theme_rect(0, 80, PY >> 3, 58 - (PY >> 3), 0);
    heading("Settings", "/VERANDA/.SYSTEM/ASK.CFG");
    put(2, SRVY + 4, "Server", 9, 0);
    radio(SRVY, !C.srv, "ChatGPT plan", "Sign in with ChatGPT: Plus or Pro");
    radio(SRVY + 16, C.srv, "OpenAI API key", "your own key, paid by the token");
    if (C.srv) {
        put(2, F1Y + 4, "API key", 9, 0);
        put(2, F2Y + 4, "Model", 9, 0);
    } else {
        put(2, ACCY + 4, "Account", 9, 0);
        account();
        put(2, F1Y + 4, "PC", 9, 0);
        put(2, F2Y + 4, "Code", 9, 0);
        button(FX, 26, SIGNY, "Continue with ChatGPT", 0);
        put(2, MODY + 4, "Model", 9, 0);
        if (!nm)
            put(FX + 1, MODY + 4, "(the plan's models come with the sign-in)", FW - 2, 0);
        for (i = 0; i < nm; ++i)
            model_row(i);
    }
    fields();
    button(2, 8, BTNY, "Save", 0);
    button(11, 8, BTNY, "Cancel", 0);
    button(20, 18, BTNY, "Conversation...", 0);    /* (V123: code.c's page) */
    WHorizontalLine(0xFF, 8, 631, HELPY - 8);
    for (i = 0; h[i]; ++i)
        put(2, HELPY + i * 14, h[i], 78, 0);
    put(2, HELPY + i * 14, C.srv ? "Return saves, Esc cancels; Left, Right: the server; Tab: the field." :
        "Return: Continue with ChatGPT (a code typed), else saves; Esc cancels; Tab.", 78, 0);
}

void pg_show(void)
{
    pf = 0;
    pg_on = 1;
    pg_saved = 0;
    sg_code[0] = 0;
    pg_draw();
#ifdef CLAUDE_TEST
    gt_log("CL SETTINGS SHOWN");
#endif
}

static void __fastcall__ pg_close(unsigned char save)
{
    if (save) {
        ov5(ask_models);
        cfg_save();
        pg_saved = 1;
    } else
        cfg_load();                     /* (as saved) */
    pg_on = 0;
}

/* Continue with ChatGPT: the sign-in through the PC */
static void signin(void)
{
    unsigned char i;
    for (i = 0; sg_code[i] >= '0' && sg_code[i] <= '9'; ++i)
        ;
    if (!sg_addr[0] || i != 6 || sg_code[6]) {
        Beep();
        pf = sg_addr[0] != 0;
        fields();
        return;
    }
    ov5(ask_models);
    cfg_save();
    pg_on = 0;
    pg_saved = 0;
    ov5(ask_signin);
    strcpy(msg, tgo ? "Signing in: finish in the browser on your PC (Esc cancels)." : "Not signed in.");
}

static void __fastcall__ choose(unsigned char m)
{
    unsigned char o = C.model;
    if (C.srv || m >= nm)
        return;
    C.model = m;
    ov5(ask_models);
    model_row(o);
    model_row(m);
}

static void __fastcall__ server(unsigned char s)
{
    if (s == C.srv)
        return;
    if (C.srv) {
        memcpy(line, C.mslug, SLUGMAX);
        bk_put(tbank, TB_AMOD, line, SLUGMAX);
    }
    C.srv = s;
    ov5(ask_models);
    pf = 0;
    pg_draw();
}

/* s's printable characters added to the field typed into */
static void __fastcall__ add(const char *s)
{
    unsigned char c, n;
    char *b;
    if (C.srv && !pf) {                 /* (the key: in its bank) */
        while ((c = *s++) != 0 && klen < KEYMAX2)
            if (c > 32 && c < 127) {
                bk_put(tbank, TB_KEY + klen, s - 1, 1);
                ++klen;
            } else if (c == '\r' || c == '\n')
                break;
        return;
    }
    b = C.srv ? C.mslug : pf ? sg_code : sg_addr;
    n = strlen(b);
    while ((c = *s++) != 0 && n < (C.srv ? SLUGMAX - 1 : pf ? 6 : HOSTMAX + 6))
        if (c > 32 && c < 127 && (!pf || C.srv || (c >= '0' && c <= '9')))
            b[n++] = c;
        else if (c == '\r' || c == '\n')
            break;
    b[n] = 0;
}

static void __fastcall__ backspace(unsigned char all)
{
    char *b;
    if (C.srv && !pf) {
        klen = all || !klen ? 0 : klen - 1;
        return;
    }
    b = C.srv ? C.mslug : pf ? sg_code : sg_addr;
    if (all || !b[0])
        b[0] = 0;
    else
        b[strlen(b) - 1] = 0;
}

static unsigned char noticing;          /* the plan's notice is up */

static void notice_end(void)
{
    noticing = 0;
    notice = 1;
    pg_on = 0;
    pg_saved = 0;
    cfg_save();
}

void pg_key(void)
{
    unsigned char k = keyData;
    if (noticing) {
        if (k == 13 || k == KEY_ESC || k == ' ')
            notice_end();
        return;
    }
    if ((keyDataMods & 2) && k == 22) {         /* Ctrl+V */
        ovc(paste);
        add(line);
        fields();
        return;
    }
    if (keyDataMods & KEYM_ARROW) {
        if (k == KEY_UP && C.model)
            choose(C.model - 1);
        else if (k == KEY_DOWN)
            choose(C.model + 1);
        else if (k == KEY_LEFT || k == KEY_RIGHT)
            server(k == KEY_RIGHT);
        return;
    }
    switch (k) {
    case 13:
        if (!C.srv && sg_code[0])
            signin();
        else
            pg_close(1);
        return;
    case KEY_ESC: pg_close(0); return;
    case KEY_TAB:
        pf ^= 1;
        break;
    case 8:
        backspace(0);
        break;
    case KEY_DELETE:
        backspace(1);
        break;
    default:
        if (k > 32 && k < 127) {
            line[0] = k;
            line[1] = 0;
            add(line);
        } else
            return;
    }
    fields();
}

void pg_press(void)
{
    unsigned int y = mouseYPosW;
    unsigned char c = mouseXPos >> 3;
    if (noticing) {
        if (y >= 272 && y < 286 && c >= 34 && c < 46)
            notice_end();
        return;
    }
    if (y >= SRVY && y < SRVY + 32) {
        server((y - SRVY) >> 4);
        return;
    }
    if (y >= F1Y && y < F2Y + 16) {
        pf = y >= F2Y;
        fields();
        return;
    }
    if (!C.srv && y >= SIGNY && y < SIGNY + 14 && c >= FX && c < FX + 26) {
        signin();
        return;
    }
    if (!C.srv && y >= MODY && y < MODY + nm * 16) {
        choose((y - MODY) >> 4);
        return;
    }
    if (y >= BTNY && y < BTNY + 14) {
        if (c >= 2 && c < 10)
            pg_close(1);
        else if (c >= 11 && c < 19)
            pg_close(0);
        else if (c >= 20 && c < 38) {
            pg_close(1);
            ovv(c_conv);                /* (saved, then the Conversation page) */
        }
    }
}

/*---------------------------------------------------------------- the plan's notice */

/* (turn.c's, after the first sign-in: over the conversation, the input box left as it is) */
void notice_show(void)
{
    unsigned int l = 80, t = 136, r = 559, b = 295;
    dispBufferOn = ST_WR_FORE;
    SetPattern(0);
    WRectangle(l, t, r, b);
    if (hl)
        theme_rect(l >> 3, (r + 1 - l) >> 3, t >> 3, (b + 1 - t) >> 3, CHROME);
    rframe(l + 2, t + 2, r - 2, b - 2);
    UseFont(FONT_UI);
    currentMode = SET_BOLD;
    strcpy(line, "You're using your ChatGPT plan");
    WPutString(line, l + 24, t + 28);
    currentMode = 0;
    strcpy(line, "Eligible usage in this app uses your ChatGPT plan.");
    WPutString(line, l + 24, t + 56);
    strcpy(line, "Manage usage in your ChatGPT settings.");
    WPutString(line, l + 24, t + 72);
    strcpy(line, "(chatgpt.com/settings/usage)");
    WPutString(line, l + 24, t + 88);
    UseSystemFont();
    button(34, 12, 272, "Got it", 0);
    noticing = 1;
    pg_on = 1;
    st_dirty = 0xFFFF;                  /* (the rows that changed are drawn when it closes: page_all) */
    pg_saved = 0;
#ifdef CLAUDE_TEST
    gt_log("CL NOTICE SHOWN");
#endif
}
