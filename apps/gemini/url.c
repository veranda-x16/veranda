/* Veranda Gemini: URLs (overlay 3; DECISIONS V118).

   An address typed (gemini:// put before a bare host), a link's URL
   resolved against the page's (RFC 3986, section 5.2: a scheme, an
   authority, an absolute or a relative path, a query alone, the dot
   segments removed; a fragment dropped), a redirect's against the URL
   that was asked, go's host and port for vrnet (1965 when none), the
   user's answer to a capsule's question percent-encoded as its query,
   the card's name for a download (the path's last segment); and the
   boxes for a reply that is not a page (4x, 5x, 6x and others).

   Web pages (V124): an http(s) address, typed or a link's, goes through
   NewsWaffle or the user's proxy, as web.c (overlay 4) decides; a web
   address's host is the proxy's (u_host).

   Everything here works on main RAM's buffers (cur, go, rel, gmeta,
   line, abuf, xf_name) and results (u_ret ..., main.c's); its own
   scratch is in this overlay's bank.

   MIT licence (see LICENSE). */
#include <veranda.h>
#include <string.h>
#include <vrnet.h>
#include <vrser.h>
#include "gemini.h"
#pragma code-name ("OVERLAY3")
#pragma rodata-name ("OVL3RO")
#pragma bss-name ("OVL3BSS")

static char base[URLMAX], t[URLMAX + 8], out[URLMAX + 8];

static unsigned char __fastcall__ lower(unsigned char c)
{
    return c >= 'A' && c <= 'Z' ? c + 32 : c;
}

static unsigned char __fastcall__ alpha(unsigned char c)
{
    c = lower(c);
    return c >= 'a' && c <= 'z';
}

/* the parts of a URL (pointers into it, lengths); has: which there are */
#define H_SCHEME 1
#define H_AUTH   2
#define H_QUERY  4
struct parts {
    const char *s, *a, *p, *q;
    unsigned int sn, an, pn, qn;
    unsigned char has;
};
static struct parts B, R;

static void __fastcall__ split(const char *u, struct parts *x)
{
    const char *e;
    memset(x, 0, sizeof *x);
    e = u;
    if (alpha(*e)) {
        while (alpha(*e) || (*e >= '0' && *e <= '9') || *e == '+' || *e == '-' || *e == '.')
            ++e;
        if (*e == ':') {
            x->s = u;
            x->sn = e - u;
            x->has = H_SCHEME;
            u = e + 1;
        }
    }
    if (u[0] == '/' && u[1] == '/') {
        u += 2;
        for (e = u; *e && *e != '/' && *e != '?' && *e != '#'; ++e)
            ;
        x->a = u;
        x->an = e - u;
        x->has |= H_AUTH;
        u = e;
    }
    for (e = u; *e && *e != '?' && *e != '#'; ++e)
        ;
    x->p = u;
    x->pn = e - u;
    u = e;
    if (*u == '?') {
        for (e = ++u; *e && *e != '#'; ++e)
            ;
        x->q = u;
        x->qn = e - u;
        x->has |= H_QUERY;
    }
}

/* the dot segments of the path in t removed, into out (RFC 3986, 5.2.4) */
static void dots(void)
{
    char *i = t, *o = out;
    char *k;
    while (*i) {
        if (!memcmp(i, "../", 3))
            i += 3;
        else if (!memcmp(i, "./", 2))
            i += 2;
        else if (!memcmp(i, "/./", 3))
            i += 2;
        else if (!strcmp(i, "/."))
            i[1] = 0;
        else if (!memcmp(i, "/../", 4) || !strcmp(i, "/..")) {
            if (i[3])
                i += 3;
            else {
                i += 2;
                *i = '/';               /* ("/.." at the end: "/") */
            }
            while (o > out && *--o != '/')
                ;
            *o = 0;
        } else if (!strcmp(i, ".") || !strcmp(i, ".."))
            *i = 0;
        else {
            k = i + 1;
            while (*k && *k != '/')
                ++k;
            while (i < k)
                *o++ = *i++;
            *o = 0;
        }
    }
    *o = 0;
}

static char *__fastcall__ cat(char *d, const char *s, unsigned int n)
{
    memcpy(d, s, n);
    d[n] = 0;
    return d + n;
}

/* rel resolved against base into go; u_ret U_* */
static void resolve(void)
{
    char *d = go;
    unsigned int n, qn, an;
    const char *q, *sc, *au;
    unsigned char sn, i, qhas;
    split(base, &B);
    split(rel, &R);
    u_ret = U_BAD;
    u_err = 1;
    if (!(R.has & H_SCHEME) && !(B.has & H_SCHEME))
        return;                         /* (a relative link on the bookmarks page) */
    t[0] = 0;
    if (R.pn >= URLMAX || B.pn >= URLMAX)
        return;
    qhas = R.has & H_QUERY;
    q = R.q;
    qn = R.qn;
    au = R.a;
    an = R.an;
    if (!(R.has & (H_SCHEME | H_AUTH))) {
        au = (B.has & H_AUTH) ? B.a : 0;
        an = B.an;
    }
    if (R.has & (H_SCHEME | H_AUTH)) {
        cat(t, R.p, R.pn);
    } else if (!R.pn) {
        cat(t, B.p, B.pn);
        if (!qhas) {
            qhas = B.has & H_QUERY;
            q = B.q;
            qn = B.qn;
        }
    } else if (R.p[0] == '/') {
        cat(t, R.p, R.pn);
    } else {
        if (B.pn + R.pn >= URLMAX) {
            u_err = 2;
            return;
        }
        if ((B.has & H_AUTH) && !B.pn)
            strcpy(t, "/");
        else {
            for (n = B.pn; n && B.p[n - 1] != '/'; --n)
                ;
            cat(t, B.p, n);
        }
        n = strlen(t);
        cat(t + n, R.p, R.pn);
    }
    dots();
    if (R.has & H_SCHEME) {
        sc = R.s;
        sn = R.sn;
    } else {
        sc = B.s;
        sn = B.sn;
        if (!(R.has & H_AUTH))
            au = B.a, an = B.an;
        else
            au = R.a, an = R.an;
    }
    if (sn > 10)
        return;
    for (i = 0; i < sn; ++i)
        t[i] = lower(sc[i]);
    t[sn] = 0;
    if (!strcmp(t, "gemini") && !out[0])
        strcpy(out, "/");               /* (gemini://host is gemini://host/) */
    if (strlen(out) + an + qn + sn + 6 >= URLMAX) {
        u_err = 2;
        return;
    }
    d = cat(d, t, sn);
    *d++ = ':';
    if ((R.has & H_AUTH) || (!(R.has & H_SCHEME) && (B.has & H_AUTH))) {
        *d++ = '/';
        *d++ = '/';
        for (i = 0; i < an; ++i)
            *d++ = lower(au[i]);
    }
    d = cat(d, out, strlen(out));
    if (qhas) {
        *d++ = '?';
        d = cat(d, q, qn);
    }
    *d = 0;
    u_ret = !strcmp(t, "gemini") ? U_GEM : !strcmp(t, "http") || !strcmp(t, "https") ? U_WEB
        : !strcmp(t, "gopher") ? U_GOPHER : !strcmp(t, "mailto") ? U_MAIL : U_OTHER;
}

/* resolve(), a web page sent its way */
static void rweb(void)
{
    resolve();
    if (u_ret == U_WEB)
        ov4(w_web);
}

void u_resolve(void)
{
    strcpy(base, cur);
    rweb();
}

/* abuf (typed) into go */
void u_typed(void)
{
    const char *s = abuf;
    while (*s == ' ')
        ++s;
    strncpy(rel, s, URLMAX - 1);
    rel[URLMAX - 1] = 0;
    for (s = rel + strlen(rel); s > rel && s[-1] == ' '; --s)
        ;
    rel[s - rel] = 0;
    base[0] = 0;
    if (!strstr(rel, "://") && strncmp(rel, "mailto:", 7)) {
        strcpy(base, "gemini://");      /* a bare host: a gemini one */
        if (strlen(rel) + 10 >= URLMAX)
            rel[URLMAX - 11] = 0;
        strcat(base, rel);
        strcpy(rel, base);
    }
    rweb();
}

/* go's host into t, lowercased */
static void host_of(const char *u)
{
    struct parts x;
    unsigned char n = 0, i;
    split(u, &x);
    for (i = 0; i < x.an && x.a[i] != ':' && n < HOSTMAX - 1; ++i)
        t[n++] = lower(x.a[i]);
    t[n] = 0;
}

void u_redirect(void)
{
    static char o[HOSTMAX];             /* (the old host) */
    strcpy(base, go);
    strcpy(rel, gmeta);
    host_of(go);
    strcpy(o, t);
    resolve();
    if (u_ret == U_BAD)
        return;
    host_of(go);
    u_moved = strcmp(o, t) != 0;
}

/* an authority (host[:port]) into ghost, gport: 0 bad */
static unsigned char __fastcall__ auth(const char *a, unsigned char an)
{
    unsigned char n = 0, i, c;
    unsigned int p = 0;
    for (i = 0; i < an && a[i] != ':'; ++i) {
        c = a[i];
        if (n == 61 || !(alpha(c) || (c >= '0' && c <= '9') || c == '.' || c == '-'))
            return 0;
        ghost[n++] = lower(c);
    }
    ghost[n] = 0;
    if (!n)
        return 0;
    if (i < an)
        for (++i; i < an; ++i) {
            c = a[i];
            if (c < '0' || c > '9')
                return 0;
            p = p * 10 + c - '0';
        }
    gport = p ? p : 1965;
    return 1;
}

void u_host(void)
{
    struct parts x;
    split(go, &x);
    if (go[0] == 'h') {                 /* (http, https: the proxy's, web.c's, into ghost first) */
        ov4(w_proxy);
        x.a = ghost;
        x.an = strlen(ghost);
    }
    u_ret = auth(x.a, x.an);
}

/* ghost (host[:port]) parsed in place (web.c's) */
void u_ghost(void)
{
    u_ret = auth(ghost, strlen(ghost));
}

static const char hexd[] = "0123456789ABCDEF";

void u_query(void)
{
    char *q = strchr(go, '?'), *d;
    const char *s;
    unsigned char c;
    if (!q)
        q = go + strlen(go);
    d = q;
    *d++ = '?';
    u_ret = 0;
    for (s = line; (c = *s) != 0; ++s) {
        if (d >= go + URLMAX - 4) {
            *q = 0;
            return;
        }
        if (alpha(c) || (c >= '0' && c <= '9') || c == '-' || c == '.' || c == '_' || c == '~')
            *d++ = c;
        else {
            *d++ = '%';
            *d++ = hexd[c >> 4];
            *d++ = hexd[c & 15];
        }
    }
    *d = 0;
    u_ret = 1;
}

static unsigned char __fastcall__ hexv(char c)
{
    c = lower(c);
    return c >= '0' && c <= '9' ? c - '0' : c >= 'a' && c <= 'f' ? c - 'a' + 10 : 0xFF;
}

/* go's file name for the card: the path's last segment (%XX decoded;
   FAT and CMDR-DOS: no , : = * ? " < > | \ /) */
void u_name(void)
{
    struct parts x;
    const char *s;
    unsigned char i = 0, a, b;
    unsigned int n;
    char c;
    split(go, &x);
    for (n = x.pn; n && x.p[n - 1] != '/'; --n)
        ;
    s = x.p + n;
    n = x.pn - n;
    while (n && i < 40) {
        c = *s++;
        --n;
        if (c == '%' && n >= 2 && (a = hexv(s[0])) != 0xFF && (b = hexv(s[1])) != 0xFF) {
            c = a * 16 + b;
            s += 2;
            n -= 2;
        }
        xf_name[i++] = strchr(",:=*?\"<>|\\/", c) || c < 32 || c > 126 ? '_' : c;
    }
    xf_name[i] = 0;
    if (!i || xf_name[0] == '.')
        strcpy(xf_name, "download.bin");
}

/* the boxes for a fetch that failed (gerr), a reply that is not a page */
static const char *const st4[] = { "Temporary failure.", "The server is unavailable.",
    "The capsule's program failed.", "A proxy failed.", "Slow down: try again later." };
static const char *const st5[] = { "Permanent failure.", "Not found.", "Gone: it is not there any more.",
    "Proxy request refused." };

/* (V138) why, short (after "Could not connect: "; the address on the
   box's second line); the modem's error by its code otherwise */
static const char *net_why(void)
{
    char *p;
    switch (gnet) {
    case NET_ERR: return "refused, or no such host.";
    case NET_ETIMEOUT: return "no answer.";
    case NET_ENOSOCK: return "no free connection.";
    }
    p = unum(strcpy(t, "the modem's error ") + 18, -gnet);
    strcpy(p, ".");
    return t;
}

static const char card[] = "(TexElec's Serial & ESP32 Network Card)";

void u_fail(void)
{
    unsigned char s = gstatus, k = s % 10;
    const char *a = 0;
    char *p = out;
    switch (gerr) {
    case GE_BADHDR:
        message("That is not a Gemini server's reply.", ghost);
        return;
    case GE_NET:                        /* (V138: why, and the address that failed, cut) */
        strcpy(out, greply ? "Connection lost: " : "Could not connect: ");
        strcat(out, net_why());
        strncpy(base, go, 48);
        base[48] = 0;
        if (strlen(go) > 48)
            strcat(base, "...");
        message(out, base);
        return;
    case GE_TIMEOUT:
        message("The server stopped sending.", "(nothing for 30 seconds: the connection was closed)");
        return;
    case GE_EMPTY:
        message("The server closed the connection", "without sending anything.");
        return;
    case GE_LOCAL:
        message("The file on the card failed:", xf_name);
        return;
    case GE_MODEM:
        message("The modem does not answer.", card);
        return;
    case GE_NOCARD:
        message("No network card was found.", card);
        return;
    case GE_STATUS:
        break;
    default:
        return;
    }
    if (s / 10 == 4)
        a = k < 5 ? st4[k] : st4[0];
    else if (s / 10 == 5)
        a = k < 4 ? st5[k] : s == 59 ? "Bad request." : st5[0];
    else if (s / 10 == 6) {
        message("This capsule asks for a client certificate:", "Veranda Gemini has none (not supported).");
        return;
    } else
        a = "A reply Veranda Gemini does not know.";
    p = unum(p, s);
    *p++ = ' ';
    strcpy(p, a);
    message(out, gmeta[0] ? gmeta : "(the server gave no reason)");
}

/* the font's upper half's Unicode (V143: $80-$9F the private glyphs, CP437's
   pi, square, root, shades, blocks and box lines; $A0-$FF Veranda's set,
   ISO-8859-16) into the font's bank at $BB00, for doc.c's folding */
#pragma rodata-name (push, "OVL5RO")    /* (main's V143: overlay 3's room; copied from overlay 5's bank) */
static const unsigned int cp437u[128] = {
    0x03C0, 0x25A0, 0x221A, 0x2591, 0x2592, 0x2593, 0x2502, 0x2524,
    0x2510, 0x2514, 0x2534, 0x252C, 0x251C, 0x2500, 0x253C, 0x2518,
    0x250C, 0x2588, 0x2584, 0x258C, 0x2590, 0x2580, 0x2551, 0x2550,
    0x2554, 0x2557, 0x255A, 0x255D, 0x2560, 0x2563, 0x2566, 0x2569,
    0x00A0, 0x0104, 0x0105, 0x0141, 0x20AC, 0x201E, 0x0160, 0x00A7,
    0x0161, 0x00A9, 0x0218, 0x00AB, 0x0179, 0x00AD, 0x017A, 0x017B,
    0x00B0, 0x00B1, 0x010C, 0x0142, 0x017D, 0x201D, 0x00B6, 0x00B7,
    0x017E, 0x010D, 0x0219, 0x00BB, 0x0152, 0x0153, 0x0178, 0x017C,
    0x00C0, 0x00C1, 0x00C2, 0x0102, 0x00C4, 0x0106, 0x00C6, 0x00C7,
    0x00C8, 0x00C9, 0x00CA, 0x00CB, 0x00CC, 0x00CD, 0x00CE, 0x00CF,
    0x0110, 0x0143, 0x00D2, 0x00D3, 0x00D4, 0x0150, 0x00D6, 0x015A,
    0x0170, 0x00D9, 0x00DA, 0x00DB, 0x00DC, 0x0118, 0x021A, 0x00DF,
    0x00E0, 0x00E1, 0x00E2, 0x0103, 0x00E4, 0x0107, 0x00E6, 0x00E7,
    0x00E8, 0x00E9, 0x00EA, 0x00EB, 0x00EC, 0x00ED, 0x00EE, 0x00EF,
    0x0111, 0x0144, 0x00F2, 0x00F3, 0x00F4, 0x0151, 0x00F6, 0x015B,
    0x0171, 0x00F9, 0x00FA, 0x00FB, 0x00FC, 0x0119, 0x021B, 0x00FF
};
#pragma rodata-name (pop)

void u_load(void)
{
    BankCopy((void *)cp437u, (void *)0xBB00, sizeof cp437u, bOv5, doc_bank + DOCBANKS + 1);
    ov4(w_load);                        /* (the web's settings) */
}

/*---------------------------------------------------------------- (from ui.c: the boxes) */

/* go (resolved: u_ret) somewhere that is not Gemini: where it leads */
void u_where(void)
{
    static const char *const what[] = { "", "Web pages are off (File > Settings...):",
        "A Gopher page: Veranda Gopher can open it.", "An e-mail address:",
        "Veranda Gemini cannot open this kind of address:" };
    if (u_ret == U_NONE)
        return;
    if (u_ret == U_BAD) {
        message(u_err == 2 ? "That address is too long for Veranda Gemini:" : "That is not an address:", rel);
        return;
    }
    message(what[u_ret], u_ret == U_MAIL ? go + 7 : go);
}

/* a 1x: the capsule's question in a box (its answer in rel, below
   $A000), sent as go's query; u_ret 1: fetch go, msg says so */
void u_input(void)
{
    rel[0] = 0;
    strcpy(line, gmeta[0] ? gmeta : "The capsule asks:");
    if (gstatus == 11)
        strcat(line, " (it shows as you type)");
    u_ret = 0;
    if (!ask(line, rel, 90)) {
        strcpy(msg, "Not answered.");
        u_ret = 2;
        return;
    }
    strcpy(line, rel);
    u_query();
    if (!u_ret) {
        message("The answer is too long for this address.", "");
        return;
    }
    strcpy(msg, "Asking ");
    strncat(msg, ghost, 60);
    strcat(msg, " ...");
}

/* a 3x: followed (5 at most; another host asked about); u_ret 1: fetch
   go, 2: msg says why not */
void u_redir(void)
{
    u_ret = 0;
    if (++redirs > 5) {
        message("The capsule redirects more than 5 times:", "Veranda Gemini stopped.");
        return;
    }
    u_redirect();
    if (u_ret != U_GEM) {
        if (u_ret == U_BAD)
            strcpy(rel, gmeta);
        u_where();
        u_ret = 0;
        return;
    }
    if (u_moved) {
        u_host();
        strcpy(line, "Go to ");
        strncat(line, ghost, 40);
        strcat(line, "?");
        if (!yesno("The capsule sends you to another host.", line)) {
            strcpy(msg, "Not followed.");
            u_ret = 2;
            return;
        }
    }
    strcpy(msg, "Redirected to ");
    strncat(msg, go, 80);
    u_ret = 1;
}

/* (V138) a connection that failed before any byte of the reply came
   (the modem's TLS connection refused, as the ESP32 does when it is
   short of memory, or broken at once): once more, a second later (ui.c's
   tick); u_ret 1 */
void u_retry(void)
{
    u_ret = 0;
    if (greply || rtry)
        return;
    rtry = 1;
    rt_t = ser_frames;
    strcpy(msg, "Trying ");
    strcat(msg, ghost);
    strcat(msg, " again ...");
    win_status(msg, right);
#ifdef GEMINI_TEST
    gt_log("GE RETRY");
#endif
    u_ret = 1;
}

/* a body that is not a page: "Download?" (not asked for File >
   Download), "Replace?", on to the file; u_ret 1: msg says so */
void u_save(void)
{
    u_ret = 0;
    if (!gdl && !memcmp(gmeta, "image/", 6))
        gdl = 2;                        /* (V138: a link that answers with a picture: as a picture's) */
    if (gdl == 2) {                     /* (a picture asked for, V125: PNG shown, others saved) */
        if (!memcmp(gmeta, "image/png", 9)) {
            strcpy(xf_name, "the picture (image/png)");
            goto save;
        }
        if (!memcmp(gmeta, "image/jpeg", 10))
            strcpy(line, "JPEG can't be shown here: save it, or use");
        else {
            strcpy(line, "This can't be shown here (");
            strncat(line, gmeta, 20);
            strcat(line, ").");
        }
        if (!yesno(line, !memcmp(gmeta, "image/jpeg", 10) ? "the private proxy. Save it to /DOCUMENTS?" : "Save it to /DOCUMENTS?")) {
            g_cancel();
            return;
        }
        gdl = 1;
    }
    u_name();
    if (!gdl) {
        strcpy(line, "Download ");
        strcat(line, xf_name);
        strcat(line, " (");
        strncat(line, gmeta[0] ? gmeta : "a file", 24);
        strcat(line, ")");
        if (!yesno(line, "to /DOCUMENTS?")) {
            g_cancel();
            return;
        }
        gdl = 1;                        /* (net.c's g_save set it before V125) */
    }
    if (xf_exists(xf_name)) {
        strcpy(line, xf_name);
        strcat(line, " is in /DOCUMENTS already.");
        if (!yesno(line, "Replace it?")) {
            g_cancel();
            return;
        }
    }
save:
    if (!g_save())
        return;
    strcpy(msg, "Downloading ");
    strcat(msg, xf_name);
    strcat(msg, " ...");
    u_ret = 1;
}

