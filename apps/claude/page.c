/* Veranda Claude: the settings and the Settings page (overlay 4; DECISIONS V114, V115).

   CLAUDE.CFG in the system's data folder (/VERANDA/.SYSTEM, vrpath.h's
   VR_DATA), plain text (CR LF or LF), so that it can be written on a
   PC too, one setting a line:
       server=api              or server=bridge: Claude Code on my PC
       key=sk-ant-...          the API key (kept as plain text)
       bridge=192.168.1.20:8642  the PC's address (tools/claude_bridge.py)
       bpass=...               the bridge's password (plain text too)
       model=claude-opus-5-5   claude-sonnet-5-5, claude-haiku-5-5
       host=api.anthropic.com  port=443   (the API's)
       tls=0                   (only for a test: plain TCP, no ATCS)
       system=...              a system prompt of one's own (one line)
       remember=all            10, 4 or 1: the messages sent (V123)
       answers=normal          short: a sentence more, max_tokens 1024
       oldcode=short           full: old code blocks sent whole
       compact=asked           auto: compacted when longer than 6 KB
   Missing: the API, no key, Claude Opus 5.5, api.anthropic.com:443 over
   the modem's TLS, the bridge at port 8642, the built-in system prompt.
   Both servers' settings are kept (this overlay's own), so switching
   back and forth loses nothing; C (main RAM) holds the chosen one's
   host, port, TLS and key, which net.c sends.

   The Settings page (over the conversation): the server (two rows: a
   click, or Left and Right), the bridge's address (Claude Code on my
   PC: typed), the API key or the bridge's password (typed, or Ctrl+V;
   shown as stars but its last 4 characters; Tab moves between the two
   fields), the model (three rows: a click, or Up and Down), Save and
   Cancel (Return, Esc: CLAUDE.CFG read again), and what to know.

   MIT licence (see LICENSE). */
#include <veranda.h>
#include <string.h>
#include <theme.h>
#include <vrpath.h>
#include "claude.h"
#pragma code-name ("OVERLAY4")
#pragma bss-name ("OVL4BSS")
#pragma rodata-name ("OVL4RO")

#pragma data-name (push, "DATA")
static char fname[] = "CLAUDE.CFG";     /* (main RAM: the kernel reads it) */
#pragma data-name (pop)

#define ADDRMAX (HOSTMAX + 6)

/*---------------------------------------------------------------- the first notes (turn.c's once) */

/* a note (s here, in this bank: copied through line, 128 bytes at a time) */
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
    "Welcome to Veranda Claude: Anthropic's Claude through the Wi-Fi modem. Type below, "
    "Return sends; Esc stops a reply. Chats are saved as you go: Ctrl+L lists them. "
    "Settings > Conversation: Remember and Compact send less.";
static const char nokey[] =
    "To talk to Claude you need an Anthropic API key: make one at console.anthropic.com "
    "(API keys), then type or paste it in Settings, or put a line key=sk-ant-... in "
    "/VERANDA/.SYSTEM/CLAUDE.CFG on the SD card from a PC. The API is paid by the token. "
    "Or use your claude.ai plan through Claude Code on your PC: Settings, Server.";
static const char nopass[] =
    "Claude Code on my PC: start the bridge on a PC where Claude Code is signed in "
    "(python3 claude_bridge.py --password ...; it is PC/claude_bridge.py on the SD card), "
    "then type the PC's address and that password in Settings.";

/* the first notes: what this is, and where a key comes from */
void turn_hello(void)
{
    note(welcome);
    if (!C.key[0])
        note(C.srv ? nopass : nokey);
}
static char cl[KEYMAX + 16];            /* a line of the file (system=: straight into C.sys) */
static unsigned int cn;
static unsigned char csys;              /* the line is system=... */
static char akey[KEYMAX + 1], ahost[HOSTMAX];   /* the API's */
static unsigned int aport;
static unsigned char atls;
static char bpass[KEYMAX + 1], baddr[ADDRMAX + 1];      /* the bridge's */

static unsigned char __fastcall__ fopen_cfg(unsigned char mode)
{
    unsigned char h;
    vr_cd(VR_DATA);
    h = FOpen((void *)fname, mode);
    if (h < 2 || h > 4)
        h = 0;
    else if (mode == 'r' && dosStatus >= 20) {
        FClose(h);                      /* (CMDR-DOS opens a file that is not there) */
        h = 0;
    }
    return h;
}

static unsigned char __fastcall__ is(const char *k)
{
    unsigned char n = strlen(k);
    return !strncmp(cl, k, n) && cl[n] == '=';
}

/* v's printable part up to a space into d (n at most) */
static void __fastcall__ word(char *d, const char *v, unsigned char n)
{
    unsigned char i;
    for (i = 0; i < n && v[i] > 32 && v[i] < 127; ++i)
        d[i] = v[i];
    d[i] = 0;
}

static unsigned int __fastcall__ num(const char *v)
{
    unsigned int p = 0;
    while (*v >= '0' && *v <= '9')
        p = p * 10 + *v++ - '0';
    return p;
}

static void parse(void)
{
    char *v = strchr(cl, '=');
    unsigned char i;
    unsigned int p;
    if (!v)
        return;
    ++v;
    while (*v == ' ')
        ++v;
    if (is("key"))
        word(akey, v, KEYMAX);
    else if (is("bpass"))
        word(bpass, v, KEYMAX);
    else if (is("bridge"))
        word(baddr, v, ADDRMAX);
    else if (is("server"))
        C.srv = !strcmp(v, "bridge");
    else if (is("model")) {
        for (i = 0; i < MODELS; ++i)
            if (!strcmp(v, model_id[i]))
                C.model = i;
    } else if (is("host")) {
        strncpy(ahost, v, HOSTMAX - 1);
    } else if (is("port")) {
        if ((p = num(v)) != 0)
            aport = p;
    } else if (is("tls")) {
        atls = *v != '0';
    } else if (is("remember"))          /* (V123: the conversation's options) */
        C.rem = *v == 'a' ? RM_ALL : v[1] == '0' ? RM_10 : *v == '4' ? RM_4 : RM_ONE;
    else if (is("answers"))
        C.shorta = *v == 's';
    else if (is("oldcode"))
        C.fullold = *v == 'f';
    else if (is("compact"))
        C.autoc = *v == 'a';
}

/* the line's end */
static void eol(void)
{
    if (csys)
        C.sys[cn] = 0;
    else {
        cl[cn] = 0;
        if (cn)
            parse();
    }
    cn = csys = 0;
}

/* the chosen server's into C (the bridge: host:port, 8642 without a port) */
static void apply(void)
{
    char *p;
    unsigned int n;
    if (C.srv) {
        strcpy(C.key, bpass);
        strncpy(C.host, baddr, HOSTMAX - 1);
        C.host[HOSTMAX - 1] = 0;
        C.port = 8642;
        if ((p = strchr(C.host, ':')) != 0) {
            *p = 0;
            if ((n = num(p + 1)) != 0)
                C.port = n;
        }
        C.tls = 0;
    } else {
        strcpy(C.key, akey);
        strcpy(C.host, ahost);
        C.port = aport;
        C.tls = atls;
    }
}

void cfg_load(void)
{
    unsigned char h, k, i, c;
    memset(&C, 0, sizeof C);
    akey[0] = bpass[0] = baddr[0] = 0;
    strcpy(ahost, "api.anthropic.com");
    aport = 443;
    atls = 1;
    h = fopen_cfg('r');
    if (h) {
        cn = csys = 0;
        for (;;) {
            k = FRead(h, line, 64);
            for (i = 0; i < k; ++i) {
                c = line[i];
                if (c == '\r' || c == '\n')
                    eol();
                else if (csys) {
                    if (cn < SYSMAX && (cn || c != ' '))
                        C.sys[cn++] = c;
                } else if (cn < sizeof cl - 1) {
                    cl[cn++] = c;
                    if (cn == 7 && !strncmp(cl, "system=", 7))
                        csys = 1, cn = 0;
                }
            }
            if (k < 64)
                break;
        }
        eol();
        FClose(h);
    }
    apply();
}

static unsigned char __fastcall__ wr(unsigned char h, const char *s)
{
    strcpy(line, s);
    return FWrite(h, line, strlen(line)) != 0;
}

/* (k and v below $A000 or in this bank: copied through line) */
static unsigned char __fastcall__ wkv(unsigned char h, const char *k, const char *v)
{
    unsigned char bad = wr(h, k);
    unsigned int n = strlen(v), i, m;
    for (i = 0; i < n; i += m) {
        m = n - i > 190 ? 190 : n - i;
        memcpy(line, v + i, m);
        bad |= FWrite(h, line, m) != 0;
    }
    return bad | wr(h, "\r\n");
}

static const char *const rem_v[4] = { "all", "10", "4", "1" };

void cfg_save(void)
{
    unsigned char h = fopen_cfg('w'), bad;
    char port[8];
    cfg_err = 0;
    if (!h) {
        cfg_err = 1;
        return;
    }
    bad = wkv(h, "server=", C.srv ? "bridge" : "api");
    bad |= wkv(h, "key=", akey);
    if (baddr[0])
        bad |= wkv(h, "bridge=", baddr);
    if (bpass[0])
        bad |= wkv(h, "bpass=", bpass);
    bad |= wkv(h, "model=", model_id[C.model]);
    bad |= wkv(h, "host=", ahost);
    unum(port, aport);
    bad |= wkv(h, "port=", port);
    if (!atls)
        bad |= wkv(h, "tls=", "0");
    if (C.sys[0])
        bad |= wkv(h, "system=", C.sys);
    bad |= wkv(h, "remember=", rem_v[C.rem]);   /* (V123) */
    bad |= wkv(h, "answers=", C.shorta ? "short" : "normal");
    bad |= wkv(h, "oldcode=", C.fullold ? "full" : "short");
    bad |= wkv(h, "compact=", C.autoc ? "auto" : "asked");
    FClose(h);
    cfg_err = bad;
}

/*---------------------------------------------------------------- the Settings page */

#define PY      48
#define SRVY    72
#define ADRY    112
#define KEYY    136
#define MODY    176
#define BTNY    232
#define HELPY   264
#define FX      12
#define FW      66

static unsigned char pf;                /* the field typed into: 0 the key or password, 1 the address */

static const char *const blurb[MODELS] = {
    "the most capable",
    "fast and capable",
    "the fastest",
};

/* the field typed into, its room */
static char *fbuf(void)
{
    return pf ? baddr : C.srv ? bpass : akey;
}

static void key_field(void)
{
    char *s = C.srv ? bpass : akey;
    unsigned char n = strlen(s), i, k, w = FW - 2;
    char *p;
    if (!n)
        strcpy(line, C.srv ? "(none: the password the bridge was started with)" : "(none: type or paste your key here)");
    else {
        k = n > 4 ? n - 4 : 0;          /* (the stars, then the last 4) */
        if (n > w - 1)
            k = w - 1 - 4;
        for (i = 0; i < k; ++i)
            line[i] = '*';
        strcpy(line + k, s + (n > 4 ? n - 4 : 0));
    }
    if (!pf)
        strcat(line, "_");
    put(FX + 1, KEYY + 4, line, w, 0);
    theme_rect(FX, FW, KEYY >> 3, 2, CHROME);
    strcpy(line, "  ");
    p = unum(line + 2, n);
    strcpy(p, n == 1 ? " character" : " characters");
    strcat(line, n > 4 ? ", the last 4 shown. Ctrl+V pastes." :
           ". Ctrl+V pastes.");
    put(FX, KEYY + 20, line, 80 - FX, 0);
}

static void addr_field(void)
{
    char *p;
    if (C.srv) {
        strcpy(line, baddr[0] ? baddr : "(the PC's IP address and port, e.g. 192.168.1.20:8642)");
        if (pf)
            strcat(line, "_");
    } else {
        strcpy(line, ahost);
        strcat(line, ":");
        p = unum(line + strlen(line), aport);
        strcpy(p, atls ? "  (TLS by the modem)" : "  (plain TCP: tls=0)");
    }
    put(FX + 1, ADRY + 4, line, FW - 2, 0);
    theme_rect(FX, FW, ADRY >> 3, 2, C.srv ? CHROME : 0);
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
    static char mb[40];
    strcpy(mb, model_id[m]);
    while (strlen(mb) < 20)
        strcat(mb, " ");
    strcat(mb, blurb[m]);
    radio(MODY + m * 16, m == C.model, model_name[m], mb);
}

static const char *const help_api[] = {
    "Claude is Anthropic's AI model, through the Anthropic API. Make an API",
    "key at console.anthropic.com (Settings, API keys); it is paid by the token.",
    "A key is about 108 characters: you can also put a line key=sk-ant-...",
    "in /VERANDA/.SYSTEM/CLAUDE.CFG on the SD card from a PC. It is kept",
    "there as plain text: anyone with the card can use it.",
    "The X16 has no TLS: the Wi-Fi modem makes the encrypted connection",
    "(Zimodem's ATCS). It does NOT check the server's certificate. Zimodem",
    "firmware without ATCS cannot connect: Term's ATI shows its version.",
    0
};
static const char *const help_pc[] = {
    "Claude Code on my PC: your own Claude Code, signed in with your claude.ai",
    "plan, answers through the bridge, PC/claude_bridge.py on the SD card. On",
    "a PC where `claude` works, run:  python3 claude_bridge.py --password ...",
    "then type the PC's address (its IP, port 8642) and that password here.",
    "The password and the conversation cross your home network UNENCRYPTED",
    "(plain TCP, no TLS); both are kept as plain text in CLAUDE.CFG. The",
    "bridge runs Claude Code with every tool off: it only answers.",
    0
};

static void pg_draw(void)
{
    unsigned char i;
    const char *const *h = C.srv ? help_pc : help_api;
    dispBufferOn = ST_WR_FORE;
    SetPattern(0);
    WRectangle(0, PY, 639, 463);
    theme_rect(0, 80, PY >> 3, 58 - (PY >> 3), 0);
    heading("Settings", "/VERANDA/.SYSTEM/CLAUDE.CFG");
    put(2, SRVY + 4, "Server", 9, 0);
    radio(SRVY, !C.srv, "Anthropic API", "your API key, paid by the token");
    radio(SRVY + 16, C.srv, "Claude Code on my PC", "your claude.ai plan, via the bridge");
    put(2, ADRY + 4, C.srv ? "Address" : "Host", 9, 0);
    addr_field();
    put(2, KEYY + 4, C.srv ? "Password" : "API key", 9, 0);
    key_field();
    put(2, MODY + 4, "Model", 9, 0);
    for (i = 0; i < MODELS; ++i)
        model_row(i);
    button(2, 8, BTNY, "Save", 0);
    button(11, 8, BTNY, "Cancel", 0);
    button(20, 18, BTNY, "Conversation...", 0);    /* (V123: code.c's page) */
    WHorizontalLine(0xFF, 8, 631, HELPY - 8);
    for (i = 0; h[i]; ++i)
        put(2, HELPY + i * 14, h[i], 78, 0);
    put(2, HELPY + i * 14, C.srv ? "Return saves, Esc cancels; Left, Right: server; Tab: field; Up, Down: model." :
        "Return saves, Esc cancels; Left, Right: the server; Up, Down: the model.", 78, 0);
}

void pg_show(void)
{
    pf = 0;
    pg_on = 1;
    pg_saved = 0;
    pg_draw();
#ifdef CLAUDE_TEST
    gt_log("CL SETTINGS SHOWN");
#endif
}

static void __fastcall__ pg_close(unsigned char save)
{
    if (save) {
        cfg_save();
        pg_saved = 1;
    } else
        cfg_load();                     /* (as saved) */
    apply();
    ovsb(model_marks);
    pg_on = 0;
}

static void __fastcall__ choose(unsigned char m)
{
    unsigned char o = C.model;
    if (m >= MODELS)
        return;
    C.model = m;
    model_row(o);
    model_row(m);
}

static void __fastcall__ server(unsigned char s)
{
    if (s == C.srv)
        return;
    C.srv = s;
    pf = s && !baddr[0];                /* (the address first, when there is none) */
    pg_draw();
}

static void __fastcall__ add(const char *s)
{
    char *b = fbuf();
    unsigned char n = strlen(b), c, max = pf ? ADDRMAX : KEYMAX;
    while ((c = *s++) != 0 && n < max)
        if (c > 32 && c < 127)
            b[n++] = c;
        else if (c == '\r' || c == '\n')
            break;
    b[n] = 0;
}

static void field(void)
{
    if (pf)
        addr_field();
    else
        key_field();
}

void pg_key(void)
{
    unsigned char k = keyData, n;
    char *b = fbuf();
    if ((keyDataMods & 2) && k == 22) {         /* Ctrl+V */
        ovc(paste);
        add(line);
        field();
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
    case 13: pg_close(1); return;
    case KEY_ESC: pg_close(0); return;
    case KEY_TAB:
        if (C.srv) {
            pf ^= 1;
            addr_field();
            key_field();
        }
        return;
    case 8:
        n = strlen(b);
        if (n)
            b[n - 1] = 0;
        break;
    case KEY_DELETE:
        b[0] = 0;
        break;
    default:
        if (k > 32 && k < 127) {
            line[0] = k;
            line[1] = 0;
            add(line);
        } else
            return;
    }
    field();
}

void pg_press(void)
{
    unsigned int y = mouseYPosW;
    unsigned char c = mouseXPos >> 3;
    if (y >= SRVY && y < SRVY + 32) {
        server((y - SRVY) >> 4);
        return;
    }
    if (C.srv && y >= ADRY && y < KEYY + 16) {
        pf = y < KEYY;
        addr_field();
        key_field();
        return;
    }
    if (y >= MODY && y < MODY + MODELS * 16) {
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
