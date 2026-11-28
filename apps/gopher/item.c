/* Veranda Gopher: items and addresses (main RAM; DECISIONS V109).

   A menu's line (RFC 1436: the kind's character, the text, a tab, the
   selector, a tab, the host, a tab, the port; Gopher+'s fields after
   them ignored) shown with its mark and parsed when it is followed; a
   text's line shown with its tabs expanded; an address typed in the
   address line, gopher://host[:port]/Tselector (RFC 4266; "gopher://"
   and everything after the host may be left out; %XX decoded, so a
   search's query can follow its selector as %09query), and the address
   of a place made again for the address line; the card's name for a
   download (the selector's last part).

   MIT licence (see LICENSE). */
#include <veranda.h>
#include <string.h>
#include "gopher.h"

char abuf[SELMAX + HOSTMAX + 16];
unsigned char alen;

static unsigned char lower(unsigned char c)
{
    return c >= 'A' && c <= 'Z' ? c + 32 : c;
}

/* the address of l into abuf: gopher://host[:port]/Tselector (a tab as %09) */
void __fastcall__ addr_of(const struct loc *l)
{
    char *p = abuf, c;
    const char *s;
    if (!l->host[0]) {
        abuf[0] = 0;
        alen = 0;
        return;
    }
    strcpy(p, "gopher://");
    strcat(p, l->host);
    p += strlen(p);
    if (l->port != 70) {
        *p++ = ':';
        p = unum(p, l->port);
    }
    *p++ = '/';
    if (l->type != '1' || l->sel[0]) {
        *p++ = l->type;
        for (s = l->sel; (c = *s) != 0 && p < abuf + sizeof abuf - 4; ++s) {
            if (c == '\t') {
                memcpy(p, "%09", 3);
                p += 3;
            } else
                *p++ = c;
        }
    }
    *p = 0;
    alen = p - abuf;
}

/* line i as shown into row (0-terminated; control characters as '?':
   cs_draw takes it as it is): a text's line, WRAPW characters, its tabs
   expanded; a menu's item text, MTW characters (its kind's glyph is
   ui.c's), and its kind: the item's type, 'i' a line that is not an
   item, 0 nothing (an empty line, past the end) */
static const char cut[] = "--- Cut here: longer than 64 KB (File > Download saves all of it) ---";

unsigned char __fastcall__ render(unsigned int i)
{
    unsigned char n, c, col = 0, k;
    memset(row, ' ', WRAPW);
    row[WRAPW] = 0;
    if (i >= doc_lines) {
        if (i == doc_lines + 1 && doc_full && doc_done)
            memcpy(row, cut, sizeof cut - 1);
        return 0;
    }
    n = doc_line(i);
    if (doc_menu) {
        row[MTW] = 0;
        c = ln[0];
        if (!n)
            return 0;
        if (!strchr(ln, '\t'))
            c = 'i';                    /* (not an item: shown as text) */
        for (k = 1; k < n && ln[k] != '\t' && col < MTW; ++k)
            row[col++] = ln[k] < 32 ? '?' : ln[k];
        return c;
    }
    for (k = 0; k < n && col < WRAPW; ++k) {
        c = ln[k];
        if (c == '\t') {
            col = (col | 7) + 1;
            continue;
        }
        row[col++] = c < 32 ? '?' : c;
    }
    return 0;
}

unsigned char __fastcall__ selectable(unsigned int i)
{
    unsigned char t;
    if (!doc_menu || i >= doc_lines)
        return 0;
    t = doc_type(i);
    return t && t != 'i' && t != '3' && t != '\r' && t != '\n';
}

/* a file name for the card from the selector's last part (FAT and
   CMDR-DOS: no , : = * ? " < > | \ /) */
void card_name(void)
{
    const char *s = go.sel, *p;
    unsigned char i;
    char c;
    p = strrchr(s, '/');
    if (p)
        s = p + 1;
    for (i = 0; s[i] && s[i] != '\t' && i < 40; ++i) {
        c = s[i];
        xf_name[i] = strchr(",:=*?\"<>|\\/", c) || c < 32 || c > 126 ? '_' : c;
    }
    xf_name[i] = 0;
    if (!i || xf_name[0] == '.')
        strcpy(xf_name, "download.bin");
}

unsigned char ishttp(void)
{
    return !memcmp(go.sel, "URL:", 4);
}

/* the selected item's line parsed into go and gtitle; 0: not an item */
unsigned char __fastcall__ item(unsigned int i)
{
    unsigned char n, k = 1, f = 0, j;
    char *d;
    const char *s;
    unsigned int port = 0;
    if (!selectable(i))
        return 0;
    n = doc_line(i);
    go.type = ln[0];
    memset(go.host, 0, sizeof go.host);
    memset(go.sel, 0, sizeof go.sel);
    j = 0;
    for (; k < n && ln[k] != '\t'; ++k)
        if (j < TITLEMAX - 1)
            gtitle[j++] = ln[k];
    gtitle[j] = 0;
    while (k < n && f < 3) {
        ++k;                            /* (the tab) */
        ++f;
        d = f == 1 ? go.sel : f == 2 ? go.host : 0;
        j = 0;
        for (; k < n && ln[k] != '\t'; ++k) {
            if (f == 3) {
                if (ln[k] >= '0' && ln[k] <= '9')
                    port = port * 10 + ln[k] - '0';
            } else if (f == 1 && ln[k] == MSEL) {   /* (V230: doc.c's) the page's own selector */
                for (s = cur.sel; *s && j < SELMAX - 1; )
                    d[j++] = *s++;
            } else if (j < (f == 1 ? SELMAX - 1 : HOSTMAX - 1))
                d[j++] = ln[k];
        }
    }
    go.port = port ? port : 70;
    if (!go.host[0] && cur.host[0]) {   /* (no host: the page's server) */
        strcpy(go.host, cur.host);
        go.port = cur.port;
    }
    return 1;
}

static unsigned char __fastcall__ hexv(char c)
{
    c = lower(c);
    return c >= '0' && c <= '9' ? c - '0' : c >= 'a' && c <= 'f' ? c - 'a' + 10 : 0xFF;
}

/* abuf into go: [gopher://]host[:port][/T[selector]] (%XX decoded); 0: no host */
unsigned char parse(void)
{
    const char *s = abuf;
    unsigned char n = 0, a, b;
    unsigned int port = 0;
    while (*s == ' ')
        ++s;
    for (a = 0; a < 9 && lower(s[a]) == "gopher://"[a]; ++a)
        ;
    if (a == 9)
        s += 9;
    memset(&go, 0, sizeof go);
    while (*s && *s != ':' && *s != '/' && *s != ' ' && n < HOSTMAX - 1)
        go.host[n++] = *s++;
    if (!n)
        return 0;
    if (*s == ':')
        for (++s; *s >= '0' && *s <= '9'; ++s)
            port = port * 10 + *s - '0';
    go.port = port ? port : 70;
    go.type = '1';
    if (*s == '/' && s[1]) {
        go.type = s[1];
        s += 2;
        for (n = 0; *s && n < SELMAX - 1; ++s) {
            if (*s == '%' && (a = hexv(s[1])) != 0xFF && (b = hexv(s[2])) != 0xFF) {
                go.sel[n++] = a * 16 + b;
                s += 2;
            } else
                go.sel[n++] = *s;
        }
    }
    strncpy(gtitle, go.host, TITLEMAX - 1);
    return 1;
}

