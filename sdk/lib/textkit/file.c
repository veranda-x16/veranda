/* textkit (Veranda Edit, VeraBASIC): files. A text file is read into the gap buffer in 1 KB
   pieces, its line ends turned into LF (buf.s's gb_append); the kind is
   the first line end's (LF, CR LF or CR) and is written back on saving.
   Saving writes the whole text to ~VEDIT.TMP in the document's folder,
   then the old file goes and the new one takes its name (a whole file on
   the card at every moment). With TK_UTF8 (Veranda Edit, V143) a UTF-8
   file is decoded into the set and saved as UTF-8 again (u8.c); a file
   that is not read again byte by byte.

   The document's folder is curDirName (the shell's path, which the
   chooser changes); the current directory is kept there, except while
   the system folder is visited (the scrap, desk accessories).
   (Veranda Edit: overlay 2.)

   MIT licence (see LICENSE). */
#include <string.h>
#include <vrchoose.h>
#include "tkapp.h"

char docname[64];
unsigned char eol;
static const char tmpname[] = TK_TMPNAME;

void doc_new(void)
{
    tx_new(0, 0);
    doc_reset();
    undo_clear();
    docname[0] = 0;
    eol = 0;
#ifdef TK_UTF8
    tk_enc = 1;
#endif
}

/* the kind of line end in iobuf[0 .. n): the first LF decides (CR LF or
   LF: a lone CR before it is a character of the line); with no LF, CR if
   there is one; 255: none yet. (One more byte is read after a CR at the
   end.) */
static unsigned char find_eol(unsigned char h, unsigned int *n)
{
    unsigned int i;
    unsigned char cr = 0;
    if (iobuf[*n - 1] == 13 && *n < TK_IOBUF && FRead(h, iobuf + *n, 1) == 1)
        ++*n;
    for (i = 0; i < *n; ++i) {
        if (iobuf[i] == 10)
            return i && iobuf[i - 1] == 13 ? 1 : 0;
        if (iobuf[i] == 13)
            cr = 1;
    }
    return cr ? 2 : 255;
}

unsigned char doc_load(const char *name)
{
    static char nm[64];
    unsigned char h, e;
    unsigned int n;
    unsigned long size;
#ifdef TK_UTF8
    unsigned char raw = 0;
#endif
    strncpy(nm, name, 63);
#ifdef TK_UTF8
again:
#endif
    T_RESET();
    h = FOpen(nm, 'r');
    if (h < 2) {
        message("Cannot open", nm);
        return 1;
    }
    size = FSize(h);
    size |= (unsigned long)r1 << 16;
    if (dosStatus != 7)
        size = 0;
    if (tx_new(size + 4096, 1)) {
        FClose(h);
        doc_new();
        message("There is not enough memory for", nm);
        return 1;
    }
    gb_r = 0;
    gb_crst = 0;
    gb_mode = 0;
    e = 255;
#ifdef TK_UTF8
    u8_start(raw);
#endif
    while ((n = FRead(h, iobuf, TK_IOBUF - 1)) != 0) {
        if (e == 255) {
            e = find_eol(h, &n);
            if (e != 255)
                gb_mode = e;
        }
#ifdef TK_UTF8
        n = u8_in(n);
        if (u8_bad) {
            FClose(h);
            raw = 1;
            goto again;
        }
#endif
        if (tx_tail(n)) {
            FClose(h);
            doc_new();
            message("There is not enough memory for", nm);
            return 1;
        }
        gb_lp = iobuf;
        gb_n = n;
        gb_append();
    }
#ifdef TK_UTF8
    if (!u8_end() && !raw) {
        FClose(h);
        raw = 1;
        goto again;
    }
#endif
    tx_tail(1);
    gb_flush();
    FClose(h);
    T_LOG("load");
    doc_reset();
    undo_clear();
    nlines = gb_r + 1;
    eol = gb_mode;
    strcpy(docname, nm);
    return 0;
}

unsigned char doc_save(void)
{
    unsigned char h, e = 0;
    unsigned int n;
    T_RESET();
    doc_dir();
    h = FOpen(tmpname, 'w');
    if (h < 2) {
        message("Cannot write in this folder:", (char *)curDirName);
        return 1;
    }
    gb_mode = eol;
    gb_a = 0;
    while (!e) {
        gb_lp = iobuf;
#ifdef TK_UTF8
        gb_n = u8_gbn();
#else
        gb_n = TK_IOBUF;
#endif
        n = gb_export();
        if (!n)
            break;
#ifdef TK_UTF8
        n = u8_out(n);
#endif
        e = FWrite(h, iobuf, n);
    }
    if (FClose(h))
        e = 1;
    if (e) {
        FDelete(tmpname);
        message("The text could not be written", "(is the card full?)");
        return 1;
    }
    FDelete(docname);
    if (FRename(tmpname, docname)) {
        message("Saved as ~VEDIT.TMP: cannot rename it to", docname);
        return 1;
    }
    T_LOG("save");
    modified = 0;
    undo_saved();
    bars_dirty |= B_STATUS | B_TITLE;
    view_status_msg("Saved");
    return 0;
}

/* the changes kept or dropped first: 1 go on, 0 stop */
unsigned char ask_discard(void)
{
    static char b[40];
    unsigned char r;
    if (!modified)
        return 1;
    strncpy(b, docname[0] ? docname : "Untitled", sizeof b - 2);
    strcat(b, "?");
    r = yesnocancel("Save the changes to", b);
    if (r == NO)
        return 1;
    if (r != YES)
        return 0;
    if (!docname[0]) {
        m_saveas();
        return !modified;
    }
    return !doc_save();
}

void m_quit(void)
{
    if (ask_discard())
        EnterDeskTop();
}

/* the document the shell opened the program with: its whole name
   (dataLongName, API 5: DECISIONS V82; dataFileName holds its short form
   when it is longer than 16) */
void m_startdoc(void)
{
    doc_dir();
    doc_load((char *)dataLongName);
}

void m_new(void)
{
    if (ask_discard())
        doc_new();
}

void m_open(void)
{
    static char name[64];
    if (!ask_discard())
        return;
    name[0] = 0;
    if (file_dlg(VRF_OPEN, TK_OPEN_TITLE, name)) {
        doc_load(name);
    }
}

void m_save(void)
{
    if (!docname[0])
        m_saveas();
    else
        doc_save();
}

void m_saveas(void)
{
    static char name[64];
    unsigned char h;
    strcpy(name, docname[0] ? docname : TK_UNTITLED);
    for (;;) {
        if (!file_dlg(VRF_SAVE, TK_SAVE_TITLE, name))
            return;
        h = FOpen(name, 'r');
        if (h < 2)
            break;
        FClose(h);
        if (yesno("Replace the file", name))
            break;
    }
    strcpy(docname, name);
    doc_save();
}
