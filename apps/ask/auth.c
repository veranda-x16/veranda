/* Veranda Ask: the settings, the sign-in's lines, the requests (overlay 5;
   DECISIONS V116).

   ASK.CFG in the system's data folder (/VERANDA/.SYSTEM), plain text, one
   setting a line (CR LF or LF; a PC can write it too):
       server=plan             or server=api: an OpenAI API key
       model=gpt-6.2-sol       the plan's model (a slug of the list below)
       apimodel=gpt-6.2-sol    the API key's model (typed)
       key=sk-...              the API key
       signin=192.168.1.20:8643  the PC's sign-in helper (tools/chatgpt_signin.py)
       host_id=urn:uuid:...    this X16's ext_agent_host_id (kept for good)
       client_id=oaiapp_...    the client_id OpenAI issued to it
       login=me@example.com    the account (the next sign-in's login_hint)
       expires=3600  got=...   the access token's life, when it came
                               (minutes since 2000 by the X16's clock)
       m=gpt-6.2-sol GPT-6.2 Sol   the plan's models, in the server's order (8)
       notice=1                the plan's notice was seen
       api=host:port auth=host:port tls=0   (tests: other servers, plain TCP)
       system=...              a system prompt of one's own (one line)
       access=eyJ...           the access token (about 2 KB)
       refresh=...             the refresh token (it rotates: each renewal
                               brings a new one, and the old one is dead)
   The tokens are plain text on the card (FAT has no permissions): the
   card is the user's to keep. Written to ASK.TMP first, then ASK.CFG
   deleted and ASK.TMP renamed (read: ASK.CFG, else ASK.TMP).

   The lines key=value come from three places, one parser (kv_feed): the
   file (into the live slot), the token endpoint's reply (parse.c makes
   its JSON lines) and the sign-in helper's reply (lines already), both
   into the other slot, kept (ask_commit) only when they came whole.
   Values that are long or secret go straight into the slot's bank.

   The requests, as net.c's parts (ask.h):
     a turn        POST /v1/responses to api.openai.com: Authorization:
                   Bearer (the access token, or the API key), the body
                   {"model", "instructions", "input": [the messages],
                   "store": false, "stream": true}
     the renewal   POST /api/accounts/oauth/token to auth.openai.com,
                   form-encoded: grant_type=refresh_token, client_id,
                   refresh_token, resource (no scope)
   (V131: tools/chatgpt_signin.py makes both byte for byte the same, for its
   --check from the PC; gate ask compares them.) A token cut when read (a
   value longer than its room) is dropped, not used.
     the sign-in   POST /x16/signin to the PC's helper (plain TCP):
                   code, host_id, client_id, login

   MIT licence (see LICENSE). */
#include <veranda.h>
#include <string.h>
#include <vrpath.h>
#include "claude.h"
#pragma code-name ("OVERLAY5")
#pragma rodata-name ("OVL5RO")
#pragma bss-name ("OVL5BSS")

#pragma data-name (push, "DATA")
static char f_cfg[] = "ASK.CFG";        /* (main RAM: the kernel reads them) */
static char f_tmp[] = "ASK.TMP";
#pragma data-name (pop)

static const char m_default[] = "gpt-6.2-sol";

static char api_host[HOSTMAX], auth_host[HOSTMAX];
static unsigned int api_port, auth_port;
static unsigned char a_tls, sys_own, mfirst;
static struct slot ws;                  /* the slot being filled */
static unsigned char wb;                /* its bank */
static unsigned char kv_src;            /* 0 the file, 1 a reply */
static char pslug[32];                  /* model= (the plan's) as read */
static char rb[80];                     /* a row, a number, a host (one thing at a time) */

/*---------------------------------------------------------------- small things */

static unsigned int __fastcall__ num(const char *v)
{
    unsigned int p = 0;
    while (*v >= '0' && *v <= '9')
        p = p < 6000 ? p * 10 + *v++ - '0' : (++v, 60000u);     /* (V129: no wrap: 864000 is 60000) */
    return p;
}

static unsigned long __fastcall__ lnum(const char *v)
{
    unsigned long p = 0;
    while (*v >= '0' && *v <= '9')
        p = p * 10 + *v++ - '0';
    return p;
}

/* "host:port" into h (HOSTMAX), *p (when there is a port) */
static void __fastcall__ hostport(const char *v, char *h, unsigned int *p)
{
    const char *c = strchr(v, ':');
    unsigned char n = c ? c - v : strlen(v);
    if (n >= HOSTMAX)
        n = HOSTMAX - 1;
    memcpy(h, v, n);
    h[n] = 0;
    if (c && num(c + 1))
        *p = num(c + 1);
}

/*---------------------------------------------------------------- the lines key=value */

static char kk[12], sv[80];
static unsigned char kkn, svn, kst;     /* kst: 0 the key, 1 a value into a bank, 2 a short value, 3 skipped */
static unsigned char vb;
static unsigned int va, vn, vmax;
static unsigned char vw;                /* which length */

#define W_ACC 1
#define W_REF 2
#define W_CID 3
#define W_HID 4
#define W_LOG 5
#define W_KEY 6
#define W_SYS 7

static void kv_begin(void)
{
    kkn = svn = kst = 0;
    mfirst = 1;
}

static void __fastcall__ bank_val(unsigned char b, unsigned int a, unsigned int max, unsigned char w)
{
    vb = b;
    va = a;
    vmax = max;
    vw = w;
    vn = 0;
    kst = 1;
}

/* a key ended ('='): where its value goes */
static void kv_key(void)
{
    kk[kkn] = 0;
    kst = 2;
    svn = 0;
    if (!strcmp(kk, "access"))
        bank_val(wb, TB_ACC, ACCMAX, W_ACC);
    else if (!strcmp(kk, "refresh"))
        bank_val(wb, TB_REF, REFMAX, W_REF);
    else if (!strcmp(kk, "client_id"))
        bank_val(wb, TB_CID, CIDMAX, W_CID);
    else if (!strcmp(kk, "host_id"))
        bank_val(wb, TB_HID, HIDMAX, W_HID);
    else if (!strcmp(kk, "login"))
        bank_val(wb, TB_LOGIN, LOGMAX, W_LOG);
    else if (kv_src) {                  /* (a reply sets only the sign-in's own) */
        if (strcmp(kk, "expires") && strcmp(kk, "m") && strcmp(kk, "end") && strcmp(kk, "error"))
            kst = 3;
    } else if (!strcmp(kk, "key"))
        bank_val(tbank, TB_KEY, KEYMAX2, W_KEY);
    else if (!strcmp(kk, "system")) {
        bank_val(tbank, TB_SYS, SYSMAX2, W_SYS);
        sys_own = 1;
    }
}

/* a model of the plan's list: "slug name" */
static void model_line(void)
{
    char *sp = strchr(sv, ' ');
    if (mfirst) {
        mfirst = 0;
        ws.nmod = 0;
    }
    if (ws.nmod >= NMOD || !sv[0])
        return;
    memset(rb, 0, sizeof rb);
    if (sp)
        *sp++ = 0;
    strncpy(rb, sv, 30);
    strncpy(rb + 32, sp && *sp ? sp : sv, 31);
    memcpy(line, rb, 64);              /* (bk_put copies from main RAM) */
    bk_put(wb, TB_MOD + ws.nmod * 64, line, 64);
    ++ws.nmod;
}

/* a short value ended */
static void kv_set(void)
{
    sv[svn] = 0;
    if (!strcmp(kk, "expires"))
        ws.expires = num(sv);
    else if (!strcmp(kk, "m"))
        model_line();
    else if (!strcmp(kk, "end"))
        kv_ok = !strcmp(sv, "ok");
    else if (!strcmp(kk, "error"))
        strncpy(p_emsg, sv, sizeof p_emsg - 1);
    else if (!strcmp(kk, "got"))
        ws.got = lnum(sv);
    else if (!strcmp(kk, "server"))
        C.srv = !strcmp(sv, "api");
    else if (!strcmp(kk, "model"))
        strncpy(pslug, sv, sizeof pslug - 1);
    else if (!strcmp(kk, "apimodel")) {
        strncpy(line, sv, SLUGMAX - 1);
        line[SLUGMAX - 1] = 0;
        bk_put(tbank, TB_AMOD, line, SLUGMAX);
    } else if (!strcmp(kk, "signin"))
        strncpy(sg_addr, sv, sizeof sg_addr - 1);
    else if (!strcmp(kk, "notice"))
        notice = sv[0] == '1';
    else if (!strcmp(kk, "api"))
        hostport(sv, api_host, &api_port);
    else if (!strcmp(kk, "auth"))
        hostport(sv, auth_host, &auth_port);
    else if (!strcmp(kk, "tls"))
        a_tls = sv[0] != '0';
    else if (!strcmp(kk, "remember"))   /* (V123: the conversation's options) */
        C.rem = sv[0] == 'a' ? RM_ALL : sv[1] == '0' ? RM_10 : sv[0] == '4' ? RM_4 : RM_ONE;
    else if (!strcmp(kk, "answers"))
        C.shorta = sv[0] == 's';
    else if (!strcmp(kk, "oldcode"))
        C.fullold = sv[0] == 'f';
    else if (!strcmp(kk, "compact"))
        C.autoc = sv[0] == 'a';
}

static void kv_eol(void)
{
    if (kst == 1) {
        switch (vw) {
        case W_ACC: ws.acc = vn; break;
        case W_REF: ws.ref = vn; break;
        case W_CID: ws.cid = vn; break;
        case W_HID: ws.hid = vn; break;
        case W_LOG: ws.login = vn; break;
        case W_KEY: klen = vn; break;
        case W_SYS: slen = vn; break;
        }
    } else if (kst == 2)
        kv_set();
    kkn = svn = kst = 0;
}

/* n bytes of buf (main RAM) */
static void __fastcall__ kv_feed(const char *buf, unsigned int n)
{
    unsigned int i, j, m;
    unsigned char c;
    for (i = 0; i < n; ++i) {
        c = buf[i];
        if (c == '\r')
            continue;
        if (c == '\n') {
            kv_eol();
            continue;
        }
        switch (kst) {
        case 0:
            if (c == '=')
                kv_key();
            else if (kkn < sizeof kk - 1)
                kk[kkn++] = c;
            else
                kst = 3;
            break;
        case 1:                         /* (a run of the value's bytes at once) */
            for (j = i; j < n && buf[j] != '\n' && buf[j] != '\r'; ++j)
                ;
            m = j - i;
            if (m > vmax - vn) {
                m = vmax - vn;
                if (vw <= W_REF)
                    kv_ovf |= vw;       /* (V129: told, not cut quietly) */
            }
            if (m) {
                bk_put(vb, va + vn, buf + i, m);
                vn += m;
            }
            i = j - 1;
            break;
        case 2:
            if (svn < sizeof sv - 1 && (svn || c != ' '))
                sv[svn++] = c;
            break;
        }
    }
}

/* net.c's: a reply's lines (dtext) into the slot being filled */
void kv_reply(void)
{
    kv_feed(dtext, dn);
}

/*---------------------------------------------------------------- the slots */

static void slot_out(void)
{
    memcpy(line, &ws, sizeof ws);
    bk_put(wb, TB_INFO, line, sizeof ws);
}

/* the other slot made the live one's copy (all but the tokens): a sign-in
   or a renewal fills it */
static void slot_prepare(void)
{
    unsigned int a, k;
    unsigned char lb = tbank + tlive;
    wb = tbank + (tlive ^ 1);
    for (a = TB_CID; a < TB_MOD + NMOD * 64; a += k) {
        k = TB_MOD + NMOD * 64 - a;
        if (k > 128)
            k = 128;
        bk_get(lb, a, line, k);
        bk_put(wb, a, line, k);
    }
    ws = sl;
    ws.acc = ws.ref = 0;
    ws.got = 0;
    kv_src = 1;
    kv_ok = kv_ovf = 0;
    kv_begin();
}

/* the plan's model chosen (row C.model) into C.mslug, C.mname; the API
   key's typed one */
void ask_models(void)
{
    if (C.srv) {
        bk_get(tbank, TB_AMOD, C.mslug, SLUGMAX);
        C.mslug[SLUGMAX - 1] = 0;
        if (!C.mslug[0])
            strcpy(C.mslug, m_default);
        strcpy(C.mname, C.mslug);
        C.key[0] = klen != 0;
        return;
    }
    C.key[0] = sl.ref && sl.cid;        /* (V129: a refresh token alone: the next turn renews first) */
    if (!sl.nmod) {
        strcpy(C.mslug, pslug[0] ? pslug : m_default);
        strcpy(C.mname, C.mslug);
        return;
    }
    if (C.model >= sl.nmod)
        C.model = 0;
    bk_get(tbank + tlive, TB_MOD + C.model * 64, line, 64);
    memcpy(rb, line, 64);
    strcpy(C.mslug, rb);
    strcpy(C.mname, rb + 32);
    strcpy(pslug, rb);
}

/*---------------------------------------------------------------- ASK.CFG */

static unsigned char __fastcall__ fopen_(char *name, unsigned char mode)
{
    unsigned char h;
    vr_cd(VR_DATA);
    h = FOpen((void *)name, mode);
    if (h < 2 || h > 4)
        h = 0;
    else if (mode == 'r' && dosStatus >= 20) {
        FClose(h);                      /* (CMDR-DOS opens a file that is not there) */
        h = 0;
    }
    return h;
}

void a_load(void)
{
    unsigned char h, k, i;
    C.srv = 0;
    C.model = 0;
    C.rem = C.shorta = C.fullold = C.autoc = 0;
    strcpy(api_host, "api.openai.com");
    strcpy(auth_host, "auth.openai.com");
    api_port = auth_port = 443;
    a_tls = 1;
    sys_own = notice = 0;
    klen = slen = 0;
    pslug[0] = sg_addr[0] = 0;
    memset(line, 0, SLUGMAX);
    bk_put(tbank, TB_AMOD, line, SLUGMAX);
    tlive = 0;
    wb = tbank;
    memset(&ws, 0, sizeof ws);
    kv_src = kv_ovf = 0;
    kv_begin();
    lg_rb = 0;                          /* (V129: the slots' banks filled again: no renewal's log kept) */
    h = fopen_(f_cfg, 'r');
    if (!h)
        h = fopen_(f_tmp, 'r');         /* (a write that stopped before its rename) */
    if (h) {
        for (;;) {
            k = FRead(h, rbuf, 128);
            kv_feed((char *)rbuf, k);
            if (k < 128)
                break;
        }
        kv_feed("\n", 1);
        FClose(h);
    }
    if (kv_ovf & W_ACC)                 /* (V131: a token cut is no token: a PC wrote one too long) */
        ws.acc = 0;
    if (kv_ovf & W_REF)
        ws.ref = 0;
    slot_out();
    sl = ws;
    if (!sys_own)
        ov4(sys_fill);                  /* (the built-in system prompt, into the bank: page.c's) */
    for (i = 0; i < sl.nmod; ++i) {     /* (model= chosen again) */
        bk_get(tbank, TB_MOD + i * 64, line, 32);
        memcpy(rb, line, 32);
        if (!strcmp(rb, pslug))
            C.model = i;
    }
    ask_models();
}

static unsigned char bad;
static const char *const rem_v[4] = { "all", "10", "4", "1" };

static void __fastcall__ wr(unsigned char h, const char *s, unsigned char n)
{
    memcpy(line, s, n);
    bad |= FWrite(h, line, n) != 0;
}

static void __fastcall__ wz(unsigned char h, const char *s)
{
    wr(h, s, strlen(s));
}

/* key=value (v below $A000 or here) */
static void __fastcall__ wkv(unsigned char h, const char *k, const char *v)
{
    wz(h, k);
    wz(h, v);
    wz(h, "\r\n");
}

/* key= and n bytes of bank b at a */
static void __fastcall__ wbk(unsigned char h, const char *k, unsigned char b, unsigned int a, unsigned int n)
{
    unsigned int i, m;
    wz(h, k);
    for (i = 0; i < n; i += m) {
        m = n - i > 192 ? 192 : n - i;
        bk_get(b, a + i, line, m);
        bad |= FWrite(h, line, m) != 0;
    }
    wz(h, "\r\n");
}

static void __fastcall__ whost(unsigned char h, const char *k, const char *host, unsigned int port, const char *def)
{
    if (!strcmp(host, def) && port == 443)
        return;
    strcpy(rb, host);
    strcat(rb, ":");
    unum(rb + strlen(rb), port);
    wkv(h, k, rb);
}

void a_save(void)
{
    unsigned char h, i, lb = tbank + tlive;
    bad = 0;
    if (C.srv) {                        /* (the API key's model, as typed) */
        memcpy(line, C.mslug, SLUGMAX);
        bk_put(tbank, TB_AMOD, line, SLUGMAX);
    }
    h = fopen_(f_tmp, 'w');
    if (!h) {
        cfg_err = sv_fail = 1;
        return;
    }
    wkv(h, "server=", C.srv ? "api" : "plan");
    wkv(h, "model=", pslug[0] ? pslug : m_default);
    bk_get(tbank, TB_AMOD, line, SLUGMAX);
    memcpy(rb, line, SLUGMAX);
    if (rb[0])
        wkv(h, "apimodel=", rb);
    if (sg_addr[0])
        wkv(h, "signin=", sg_addr);
    if (klen)
        wbk(h, "key=", tbank, TB_KEY, klen);
    if (sl.hid)
        wbk(h, "host_id=", lb, TB_HID, sl.hid);
    if (sl.cid)
        wbk(h, "client_id=", lb, TB_CID, sl.cid);
    if (sl.login)
        wbk(h, "login=", lb, TB_LOGIN, sl.login);
    if (sl.expires) {
        unum(rb, sl.expires);
        wkv(h, "expires=", rb);
    }
    if (sl.got) {
        unum(rb, sl.got);
        wkv(h, "got=", rb);
    }
    for (i = 0; i < sl.nmod; ++i) {
        bk_get(lb, TB_MOD + i * 64, line, 64);
        memcpy(rb, line, 64);
        strcat(rb, " ");
        strcat(rb, rb + 32);
        wkv(h, "m=", rb);
    }
    if (notice)
        wkv(h, "notice=", "1");
    wkv(h, "remember=", rem_v[C.rem]);  /* (V123) */
    wkv(h, "answers=", C.shorta ? "short" : "normal");
    wkv(h, "oldcode=", C.fullold ? "full" : "short");
    wkv(h, "compact=", C.autoc ? "auto" : "asked");
    whost(h, "api=", api_host, api_port, "api.openai.com");
    whost(h, "auth=", auth_host, auth_port, "auth.openai.com");
    if (!a_tls)
        wkv(h, "tls=", "0");
    if (sys_own)
        wbk(h, "system=", tbank, TB_SYS, slen);
    if (sl.acc)
        wbk(h, "access=", lb, TB_ACC, sl.acc);
    if (sl.ref)
        wbk(h, "refresh=", lb, TB_REF, sl.ref);
    bad |= FClose(h) != 0;
    if (!bad) {                         /* (the old one only now: then the new one takes its name) */
        vr_cd(VR_DATA);
        FDelete(f_cfg);
        bad = FRename(f_tmp, f_cfg) != 0;
    }
    cfg_err = sv_fail = bad;
#ifdef CLAUDE_TEST
    gt_log(bad ? "CL CFG WRITE FAILED" : "CL CFG WRITTEN");
#endif
}

/* a renewal or a sign-in came whole: its slot is the live one now, ASK.CFG
   written before the new tokens are used */
void ask_commit(void)
{
    unsigned char i;
    ws.got = now_min();
    slot_out();
    tlive ^= 1;
    sl = ws;
    C.model = 0;
    for (i = 0; i < sl.nmod; ++i) {
        bk_get(tbank + tlive, TB_MOD + i * 64, line, 32);
        memcpy(rb, line, 32);
        if (!strcmp(rb, pslug))
            C.model = i;
    }
    if (!C.srv)
        ask_models();
    ovl(clk_check);                     /* (V129: a fresh token expired by the clock: the clock is wrong) */
    a_save();
}

/* a renewal's terminal error: the tokens are dead (the host and client
   ids kept: the next sign-in uses them) */
void ask_forget(void)
{
    wb = tbank + tlive;
    ws = sl;
    ws.acc = ws.ref = 0;
    slot_out();
    sl = ws;
    ask_models();
    a_save();
}

/*---------------------------------------------------------------- the requests */

static unsigned char np;

static void __fastcall__ part(unsigned char b, unsigned char fl, unsigned int a, unsigned int n)
{
    struct part *p = &parts[np++];
    p->bank = b;
    p->fl = fl;
    p->a = a;
    p->n = n;
}

/* this overlay's text (its bank, an offset in it) */
static void __fastcall__ text(const char *s)
{
    part(bOv5, P_RAW, (unsigned int)s - 0xA000, strlen(s));
}

static const char ua[] = "\r\nUser-Agent: VerandaAsk/1.0 (Commander X16)\r\nAccept-Encoding: identity\r\n"
    "Content-Type: application/";
static const char cl_[] = "\r\nContent-Length: ";
static const char conn[] = "\r\nConnection: close\r\n\r\n";

/* the request line, Host, User-Agent, Content-Type's start (its rest s),
   Accept, Authorization */
static void __fastcall__ head(const char *req, const char *ctype)
{
    np = lg_ap = 0;
    text(req);
    part(0, P_RAW, (unsigned int)C.host, PZ);
    part(0, P_RAW, (unsigned int)hport, PZ);
    text(ua);
    text(ctype);
}

static void __fastcall__ head_end(void)
{
    text(cl_);
    part(0, P_RAW, (unsigned int)hlen_s, PZ);
    text(conn);
    pbody = np;
}

static void __fastcall__ to(const char *h, unsigned int p, unsigned char tls)
{
    strcpy(C.host, h);
    C.port = p;
    C.tls = tls;
}

static void chat(void)
{
    unsigned char lb = tbank + tlive;
    rq = RQ_CHAT;
    to(api_host, api_port, a_tls);
    head("POST /v1/responses HTTP/1.1\r\nHost: ", "json\r\nAccept: text/event-stream\r\nAuthorization: Bearer ");
    lg_ap = np;                         /* (V131: its length and sum in ASK.LOG) */
    if (C.srv)
        part(tbank, P_RAW, TB_KEY, klen);
    else
        part(lb, P_RAW, TB_ACC, sl.acc);
    head_end();
    text("{\"model\":\"");
    part(0, P_JSON, (unsigned int)g_slug, strlen(g_slug));     /* (V123: the cheapest for a compaction, Ctrl+Return) */
    text("\",\"instructions\":\"");
    part(tbank, P_JSON, TB_SYS, slen);
    if (C.shorta && !t_comp)
        part(0, P_RAW, (unsigned int)short_s, PZ);
    text("\",\"input\":[");
    part(PB_MSGS, 0, 0, 0);
    text(",\"store\":false,\"stream\":true}");
    nparts = np;
}

static void renew(void)
{
    unsigned char lb = tbank + tlive;
    slot_prepare();
    rq = RQ_REFRESH;
    t_cancel = 0;
    to(auth_host, auth_port, a_tls);
    head("POST /api/accounts/oauth/token HTTP/1.1\r\nHost: ", "x-www-form-urlencoded\r\nAccept: application/json");
    head_end();
    text("grant_type=refresh_token&client_id=");
    part(lb, P_URL, TB_CID, sl.cid);
    text("&refresh_token=");
    lg_ap = np;
    part(lb, P_URL, TB_REF, sl.ref);
    text("&resource=https%3A%2F%2Fapi.openai.com%2Fv1");
    nparts = np;
}

/* send's: the turn; with the plan, the access token renewed first when a
   clock to trust says it has expired (due), or when only its refresh
   token was kept (V129) */
void ask_go(void)
{
    t_retry = 0;
    ovl(tok_due);
    if (!C.srv && (!sl.acc || t_due)) {
        t_retry = 1;                    /* (a 401 after a fresh token: sign in again, no loop) */
        renew();
    } else
        chat();
    tgo = turn_start();
}

/* turn.c's: a 401: the renewal, then the turn again */
void ask_renew(void)
{
    t_retry = 1;
    renew();
    tgo = turn_start();
}

void ask_again(void)
{
    chat();
    tgo = turn_start();
}

/* page.c's: the sign-in through the PC's helper (sg_addr, sg_code) */
void ask_signin(void)
{
    unsigned char lb = tbank + tlive;
    unsigned int p = 8643;
    slot_prepare();
    rq = RQ_SIGNIN;
    hostport(sg_addr, rb, &p);
    to(rb, p, 0);
    head("POST /x16/signin HTTP/1.1\r\nHost: ", "x-www-form-urlencoded\r\nAccept: text/plain");
    head_end();
    text("code=");
    part(0, P_URL, (unsigned int)sg_code, strlen(sg_code));
    text("&host_id=");
    part(lb, P_URL, TB_HID, sl.hid);
    text("&client_id=");
    part(lb, P_URL, TB_CID, sl.cid);
    text("&login=");
    part(lb, P_URL, TB_LOGIN, sl.login);
    nparts = np;
    tgo = turn_start();
}

/* turn.c's: did the slot being filled get its tokens (a sign-in: and its
   client_id)? A renewal's (V129): whatever came whole is kept, as the
   server has rotated the refresh token already: a new access token with
   the old refresh token when no new one came (or it was cut, or too long),
   a new refresh token alone when the access token was too long or cut;
   r_why says what was not kept */
void ask_whole(void)
{
    unsigned int a, k;
    r_why = 0;
    if (rq != RQ_REFRESH) {
        tgo = ws.acc && ws.ref && ws.cid;
        return;
    }
    if (kv_ovf & W_ACC) {
        ws.acc = 0;
        r_why = R_ACCLONG;
    } else if (!ws.acc)
        r_why = p_gz ? R_GZ : p_jok ? R_NOACC : R_CUT;
    if (kv_ovf & W_REF)
        ws.ref = 0;
    if (!ws.ref && ws.acc) {            /* (the old refresh token into the slot filled) */
        r_why = kv_ovf & W_REF ? R_REFLONG : p_jok ? R_NOREF : R_REFCUT;
        for (a = 0; a < sl.ref; a += k) {
            k = sl.ref - a > 128 ? 128 : sl.ref - a;
            bk_get(tbank + tlive, TB_REF + a, line, k);
            bk_put(wb, TB_REF + a, line, k);
        }
        ws.ref = sl.ref;
    }
    tgo = p_status == 200 && ws.ref;
}
