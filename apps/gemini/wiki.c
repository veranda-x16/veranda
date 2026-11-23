/* Veranda Gemini: Wikipedia through Gemipedia (overlay 4; DECISIONS V128).

   Gemipedia (gemini://gemi.dev/cgi-bin/wp.cgi/, by Acidus, the author of
   NewsWaffle) is a public Gemini front end to Wikipedia. Its addresses,
   from its source (github.com/acidus99/Gemipedia at 00e7863,
   Gemipedia.Cgi/Program.cs SetPaths and ParseWikiLanguage, Gemipedia/
   RouteOptions.cs, Gemipedia.Cgi/RouteHandler.cs):
     .../wp.cgi/view?<title>      an article (ViewArticle: "the title
                                  doesn't need to be exact"; none found:
                                  a redirect to search?<the same>; no
                                  query: a 10, "Article Name?")
     .../wp.cgi/search?<words>    articles containing them (no query: 10)
     .../wp.cgi/featured          the featured article and the 25 most
                                  read, updated daily
     .../wp.cgi/ (or /welcome)    its front page
   another language's Wikipedia is a path segment after the route
   (AddLanguage: .../view/pl?<title>, .../featured/pl, .../welcome/pl; en
   has none), the query UrlEncode'd (our u_query's %-encoding decodes the
   same).

   Here: Go > Wikipedia... (Ctrl+W) asks "Look up in Wikipedia:" and opens
   view?<the text> in the language set; the address line's shortcut "wp
   <text>" or "w <text>" does the same ("wp" alone asks); a document of
   Veranda Gemini's (the package's Wikipedia launcher in APPS, its data
   "wp") is read at the start and typed into the address line as if by
   the user. File > Settings... asks the language (a code: en, pl, de
   ...); GEMINI.CFG "wplang=", and "wiki=" another Gemipedia's address
   (web.c reads and writes them).

   MIT licence (see LICENSE). */
#include <veranda.h>
#include <string.h>
#include "gemini.h"
#pragma code-name ("OVERLAY4")
#pragma rodata-name ("OVL4RO")
#pragma bss-name ("OVL4BSS")

char wlang[WLANGMAX + 1];               /* the language's code ("en") */
char wbase[WIKIMAX + 1];                /* Gemipedia's address, without the route */
static char wstart[64];                 /* the start document's line ("": none) */

/* the text in line looked up: go Gemipedia's view address with it as the
   query; u_ret U_GEM, U_BAD (too long) */
static void look(void)
{
    strcpy(go, wbase);
    strcat(go, "/view");
    if (strcmp(wlang, "en")) {
        strcat(go, "/");
        strcat(go, wlang);
    }
    ov3(u_query);
    if (u_ret)
        u_ret = U_GEM;
    else {
        strcpy(rel, line);
        u_err = 2;
        u_ret = U_BAD;
    }
}

/* Go > Wikipedia...: the box; u_ret U_GEM (go), U_NONE (cancelled, or
   nothing typed), U_BAD */
void k_ask(void)
{
    strcpy(line, "Look up in Wikipedia:");
    if (strcmp(wlang, "en")) {
        line[20] = 0;
        strcat(line, " (");
        strcat(line, wlang);
        strcat(line, "):");
    }
    rel[0] = 0;
    u_ret = U_NONE;
    if (!ask(line, rel, 90) || !rel[0])
        return;
    strcpy(line, rel);
    look();
}

/* the address line (abuf): "wp <text>", "w <text>" (any case) looked
   up, "wp" or "w" alone asks; u_ret as k_ask's, 0xFF not a shortcut */
void k_typed(void)
{
    const char *s = abuf;
    unsigned char n;
    while (*s == ' ')
        ++s;
    n = (s[0] | 0x20) == 'w' ? (s[1] | 0x20) == 'p' ? 2 : 1 : 0;
    u_ret = 0xFF;
    if (!n || (s[n] && s[n] != ' '))
        return;
    for (s += n; *s == ' '; ++s)
        ;
    if (!*s) {
        k_ask();
        return;
    }
    strcpy(line, s);
    for (n = strlen(line); n && line[n - 1] == ' '; --n)
        ;
    line[n] = 0;
    look();
}

/* (the start: ui_start, before the working folder is /DOCUMENTS) the
   document Veranda Gemini was started with (GetFile with ST_LD_DATA: a
   GEOS document of its class's, dataLongName, in curDirName: V48, V87):
   its data's first line, an address or a shortcut, kept for k_start */
void k_doc(void)
{
    unsigned char h, n, i;
    strcpy(line, (const char *)dataLongName);
    strcat(line, ".cvt");
    ChDir((char *)curDirName);
    h = FOpen(line, 'r');
    if (h < 2 || h > 4)
        return;
    FSeek(h, 508, 0);                   /* (a sequential GEOS file's data: docs/APPFORMAT.md) */
    n = FRead(h, line, sizeof wstart - 1);
    FClose(h);
    for (i = 0; i < n && line[i] != '\r' && line[i] != '\n' && line[i]; ++i)
        wstart[i] = line[i];
    wstart[i] = 0;
#ifdef GEMINI_TEST
    strcpy(msg, "GE START DOC ");
    strncat(msg, (const char *)dataLongName, 40);
    strcat(msg, "|");
    strcat(msg, wstart);
    gt_log(msg);
    msg[0] = 0;
#endif
}

/* (a few passes after the start) the start document's line into the
   address line: u_ret its length (0: none) */
void k_start(void)
{
    u_ret = 0;
    if (!wstart[0])
        return;
    strcpy(abuf, wstart);
    u_ret = alen = strlen(abuf);
    wstart[0] = 0;
}

/* (w_load) the defaults; then GEMINI.CFG's lines */
void k_init(void)
{
    memset(wlang, 0, sizeof wlang);     /* (an overlay's BSS is not cleared; strncpy leaves the end) */
    memset(wbase, 0, sizeof wbase);
    strcpy(wlang, "en");
    strcpy(wbase, WIKI_DEF);
    wstart[0] = 0;
}

/* (File > Settings...) the language asked: letters and dashes, 2 to
   WLANGMAX, lowercased; empty keeps it */
void k_setlang(void)
{
    unsigned char i, c;
    strcpy(line, "Wikipedia's language (now ");
    strcat(line, wlang);
    strcat(line, "): a code, such as en, pl, de or fr:");
    rel[0] = 0;
    if (!ask(line, rel, WLANGMAX) || !rel[0])
        return;
    for (i = 0; (c = rel[i]) != 0; ++i) {
        c |= 0x20;
        if ((c < 'a' || c > 'z') && c != '-')
            break;
        rel[i] = c;
    }
    if (c || i < 2) {
        message("That is not a language code:", rel);
        return;
    }
    strcpy(wlang, rel);
}
