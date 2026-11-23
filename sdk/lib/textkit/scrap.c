/* textkit (Veranda Edit, VeraBASIC): cut, copy and paste through GEOS's Text Scrap.

   The scrap is the GEOS file "Text  Scrap" (two spaces: geoWrite's name)
   in the system's data folder, /VERANDA/.SYSTEM (V71): a sequential CVT
   file of type SYSTEM, class "Text  Scrap V2.0", whose data is a word (the
   text's length) and the text: a NEWCARDSET escape first (23, the font's
   id, the style: BSW 9 plain), CR at each line's end. geoWrite reads and
   writes the same (its port: savetextscrap.inc, scantextscrap.inc).

   The file is the SDK's scrap library's (scrap.h, DECISIONS V54): the
   copy is written in parts (scrap_text_begin, scrap_write: the text is in
   RAM banks, longer than any buffer), the paste read in parts
   (scrap_open, scrap_read). Plain text in: on a paste the escapes
   (NEWCARDSET and its 3 bytes, a ruler and its 26, a picture and its 4)
   and the style codes go, CR and PAGE_BREAK become LF; the set's letters
   are kept both ways.
   (Veranda Edit: overlay 2.)

   MIT licence (see LICENSE). */
#include <string.h>
#include <scrap.h>
#include "tkapp.h"

#define MAXSCRAP 60000UL

/* a byte kept in a plain text scrap: the printable ones (Latin-1 too),
   TAB, the line ends */
static unsigned char keep(unsigned char c)
{
    return c >= 32 || c == 9 || c == 10;
}

/* the scrap: len bytes of plain text (LF line ends) that src gives in
   pieces (twice: counted, then written); 0 if written */
unsigned char edit_scrap_put(unsigned long len, scrap_src src, void (*rewind)(void))
{
    static const unsigned char cardset[4] = { SCRAP_NEWCARDSET, 9, 0, 0 };
    unsigned int n, i, o, total = 4;
    unsigned long left;
    unsigned char e;
    if (len > MAXSCRAP)
        len = MAXSCRAP;
    for (left = len; left; left -= n) {
        n = left > TK_IOBUF ? TK_IOBUF : (unsigned int)left;
        src(iobuf, n);
        for (i = 0; i < n; ++i)
            total += keep(iobuf[i]);
    }
    rewind();
    if ((e = scrap_text_begin(total)) != 0)
        return e;
    e = scrap_write(cardset, 4);
    for (left = len; left && !e; left -= n) {
        n = left > TK_IOBUF ? TK_IOBUF : (unsigned int)left;
        src(iobuf, n);
        for (i = o = 0; i < n; ++i)
            if (keep(iobuf[i]))
                iobuf[o++] = iobuf[i] == 10 ? 13 : iobuf[i];
        e = scrap_write(iobuf, o);
    }
    if (scrap_close() && !e)
        e = 1;
    return e;
}

/* the scrap's plain text to dst in pieces; the bytes given (0: none) */
unsigned long edit_scrap_get(scrap_dst dst)
{
    unsigned char c, skip = 0;
    unsigned int n, i, o, left = 0;
    unsigned long done = 0;
    if (!scrap_open(SCRAP_TEXT) || scrap_read(&left, 2) != 2)
        left = 0;
    while (left) {
        n = scrap_read(iobuf, left > TK_IOBUF ? TK_IOBUF : left);
        if (!n)
            break;
        left -= n;
        for (i = o = 0; i < n; ++i) {
            c = iobuf[i];
            if (skip) {
                --skip;
                continue;
            }
            switch (c) {
            case SCRAP_NEWCARDSET: skip = 3; continue;
            case SCRAP_ESC_RULER: skip = 26; continue;
            case SCRAP_ESC_GRAPHICS: skip = 4; continue;
            case CR: case SCRAP_PAGE_BREAK: c = 10; break;
            case 9: case 10: break;
            default:
                if (c < 32)
                    continue;           /* style codes */
            }
            iobuf[o++] = c;
        }
        if (o) {
            dst(iobuf, o);
            done += o;
        }
    }
    scrap_close();
    return done;
}

/*---------------------------------------------------------------
  the commands
 ---------------------------------------------------------------*/
static unsigned long from, from0;

static void copy_rewind(void)
{
    from = from0;
}

static void copy_src(unsigned char *buf, unsigned int n)
{
    gb_a = from;
    gb_n = n;
    gb_lp = buf;
    gb_read();
    from = gb_a;
}

void m_copy(void)
{
    if (!HAS_SEL())
        return;
    from = from0 = sel_lo();
    if (edit_scrap_put(sel_hi() - from, copy_src, copy_rewind))
        message("Cannot write the Text Scrap", "in the system folder.");
    else
        view_status_msg(sel_hi() - sel_lo() > MAXSCRAP ? "Copied (the first 60000 bytes)" : "Copied");
}

void m_cut(void)
{
    if (!HAS_SEL())
        return;
    m_copy();
    undo_step();
    ed_delete_sel();
}

static unsigned char paste_full;

static void paste_dst(const unsigned char *buf, unsigned int n)
{
    if (!paste_full && ed_insert(buf, n))
        paste_full = 1;
}

void m_paste(void)
{
    undo_step();
    if (HAS_SEL())
        ed_delete_sel();
    paste_full = 0;
    if (!edit_scrap_get(paste_dst))
        view_status_msg("The Text Scrap is empty");
}
