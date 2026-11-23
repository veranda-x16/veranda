/* VeraBASIC, the editor (DECISIONS V99): B_MK, File > Save program and
   File > Make application...

   Both start as Format does: the X16's tokenizer and prepare make the
   program's four records (ide_request(IR_FORMAT), ide_go keeps them in
   their runs: vt_recb, vt_size); the answer (B_CMD's fmt_answer) comes
   here with ide_make saying which:
     MK_PROG  the program document (docs/vbasic/FORMAT.md 7.1, as
              tools/vbasic.py build writes it): class "VeraBASIC V1.0",
              parent class "VBRun V1.0", records 0-3
     MK_APP   a standalone application (FORMAT.md 7.3, as tools/vbapp.py
              writes it, byte for byte but the date): VeraBASIC Run's file
              (/VERANDA/APPS, else the top folder) with the program after
              its 12 records, 8191 bytes a record behind an 80-byte header,
              and its info block and tile from the APP lines (read from
              the text here as vbapp.py reads them)
   The file goes where the Save dialog says (long names; an application
   starts in /VERANDA/APPS). The kernel reads names and buffers below
   $A000: they are in main RAM's scratch (ide.h: IDE_OUT, iobuf); this
   bank's own (B10BSS) holds the file's first three blocks while they are
   made.

   MIT licence (LICENSE). */
#include <string.h>
#include <vrchoose.h>
#include <vrpath.h>
#include "ide.h"

#pragma bss-name (push, "B10BSS")
static unsigned char hd[762];           /* blocks 0-2: the entry and tile, the info block, the record table */
static char a_name[64], a_class[13], a_ver[7], a_auth[20], a_desc[96], a_docs[17];
static unsigned char a_col, a_rows, a_stay, nd;
static unsigned int a_line;             /* the line an APP line's error is in */
static const char *a_err;
static unsigned char hb[80];            /* the program's header (record 12) */
static unsigned char tile[128];         /* TILE DATA's rows */
static unsigned char out, werr;
static unsigned int clen;               /* the application: bytes in the record being written */
static unsigned char li, ln;            /* lexbuf: the place, the line's length */
static char word[16];
static unsigned char str, slen, num;    /* the last item: a string's start and length, a number */
#pragma bss-name (pop)
/* main RAM's scratch (ide.h) that neither the Save dialog's variables
   (512-1199) nor a message box (ide_msga, ide_msgb) use */
#define NAME  ((char *)lexcls)          /* 64: the file's name (the dialog's) */
#define PATH  ((char *)ide_paper)       /* 80: a folder, Run's name; the dialog's title and filter */
#define keepdir XNAME                   /* 96: the document's folder (curDirName; XNAME, XSRC) */
#define tmpk  hd                       /* a piece of a record (iobuf is the writes'; hd is written by then) */

static const unsigned char icon[63] = {
    255, 255, 255, 128, 0, 1, 128, 0, 1, 128, 0, 1, 134, 0, 97, 134, 0, 97, 134, 0, 97, 131, 0, 193,
    131, 0, 193, 129, 129, 129, 129, 129, 129, 129, 129, 129, 128, 195, 1, 128, 195, 1, 128, 102, 1,
    128, 102, 1, 128, 60, 1, 128, 0, 1, 128, 0, 1, 128, 0, 1, 255, 255, 255 };
static const char sig[] = "PRG formatted GEOS file V1.0";
static const char *const colours[16] = { "PAPER", "INK", "CHROME", "SIDEBAR", "SELECT", "TITLE",
    "YELLOW", "RED", "GREEN", "PURPLE", "ORANGE", "CYAN", "SKY", "SKY2", "HILL", "DUSK" };

/*---------------------------------------------------------------
  writing
 ---------------------------------------------------------------*/
static void wr(const void *p, unsigned int n)
{
    unsigned int k;
    const unsigned char *s = p;
    while (n && !werr) {
        k = n > TK_IOBUF ? TK_IOBUF : n;
        memcpy(iobuf, s, k);
        if (FWrite(out, iobuf, k))
            werr = 1;
        s += k;
        n -= k;
    }
}

static void zeros(unsigned int n)
{
    unsigned int k;
    memset(iobuf, 0, TK_IOBUF);
    while (n && !werr) {
        k = n > TK_IOBUF ? TK_IOBUF : n;
        if (FWrite(out, iobuf, k))
            werr = 1;
        n -= k;
    }
}

/* record n's bytes (its run of banks) out; fn: each piece goes there */
static void rec_out(unsigned char n, void (*fn)(unsigned int))
{
    unsigned int at, k, size = vt_size[n];
    for (at = 0; at < size; at += k) {
        k = size - at > TK_IOBUF ? TK_IOBUF : size - at;
        BankCopy((void *)(0xA000 + (at & 0x1FFF)), iobuf, k, vt_recb[n] + (unsigned char)(at >> 13), 0);
        fn(k);
    }
}

static void piece_doc(unsigned int k)
{
    if (!werr && FWrite(out, iobuf, k))
        werr = 1;
}

/* the application's records: 8191 bytes each, padded to 254-byte blocks
   (8382: 191 bytes of padding after a whole one) */
static void app_bytes(const unsigned char *p, unsigned int k)
{
    unsigned int m;
    while (k && !werr) {
        m = 8191 - clen;
        if (m > k)
            m = k;
        memcpy(iobuf, p, m);
        if (FWrite(out, iobuf, m))
            werr = 1;
        p += m;
        k -= m;
        clen += m;
        if (clen == 8191) {
            clen = 0;
            zeros(191);
        }
    }
}

static void piece_app(unsigned int k)
{
    memcpy(tmpk, iobuf, k);             /* (app_bytes writes through iobuf) */
    app_bytes(tmpk, k);
}

/* blocks of 254 bytes for n bytes */
static unsigned char blocks(unsigned int n)
{
    return (unsigned char)((n + 253) / 254);
}

/* a record table entry: n bytes */
static void entry(unsigned char *t, unsigned int n)
{
    unsigned char b = blocks(n);
    t[0] = b;
    t[1] = (unsigned char)(n - (b - 1) * 254 + 1);
}

/* the directory entry's name (16 characters, $A0 padded), date, size */
static void dir_entry(const char *nm, unsigned int nblk)
{
    unsigned char i;
    for (i = 0; i < 16; ++i)
        hd[3 + i] = *nm ? *nm++ : 0xA0;
    hd[23] = year + 100;
    hd[24] = month;
    hd[25] = day;
    hd[26] = hour;
    hd[27] = minutes;
    hd[28] = (unsigned char)nblk;
    hd[29] = (unsigned char)(nblk >> 8);
}

/* the file NAME (".cvt" added) in the folder curDirName: 1 open */
static unsigned char open_out(void)
{
    unsigned char n = strlen(NAME), h;
    if (n < 4 || (NAME[n - 4] != '.' || (NAME[n - 3] | 0x20) != 'c' || (NAME[n - 2] | 0x20) != 'v'
                  || (NAME[n - 1] | 0x20) != 't')) {
        if (n > 59)
            n = 59;
        strcpy(NAME + n, ".cvt");
    }
    ChDir((char *)curDirName);
    h = FOpen(NAME, 'r');
    if (h >= 2) {
        FClose(h);
        if (!yesno("Replace the file", NAME))
            return 0;
    }
    out = FOpen(NAME, 'w');
    if (out < 2) {
        message("Cannot write in this folder:", (char *)curDirName);
        return 0;
    }
    werr = 0;
    return 1;
}

static void close_out(void)
{
    if (FClose(out))
        werr = 1;
    if (werr) {
        FDelete(NAME);
        message("The file could not be written", "(is the card full?)");
    } else {
        strcpy(lexbuf, "Written: ");
        strcat(lexbuf, NAME);
        view_status_msg(lexbuf);
    }
}

/* the dialog: 1 a name chosen (NAME, curDirName) */
static unsigned char choose(const char *title)
{
    strcpy(PATH, title);                /* (B_DLG reads them: main RAM) */
    strcpy(PATH + 48, "Programs:CVT");
    file_types = PATH + 48;
    return file_dlg(VRF_SAVE, PATH, NAME);
}

/* the document's name without its extension into NAME */
static void base_name(void)
{
    unsigned char n;
    strcpy(NAME, docname[0] ? docname : "Untitled");
    n = strlen(NAME);
    if (n > 4 && NAME[n - 4] == '.')
        NAME[n - 4] = 0;
}

/*---------------------------------------------------------------
  Save program: the program document
 ---------------------------------------------------------------*/
static void save_prog(void)
{
    unsigned char n, i, *t;
    unsigned int nb = 0;
    base_name();
    if (!choose("Save the program document as") || !open_out())
        return;
    memset(hd, 0, sizeof hd);
    hd[0] = 0x83;
    hd[21] = 1;
    hd[22] = 7;                         /* APPL_DATA */
    memcpy(hd + 30, sig, sizeof sig - 1);
    t = hd + 254 - 2;                   /* (the info block from its byte 2) */
    t[2] = 3;
    t[3] = 21;
    t[4] = 0xBF;
    memcpy(t + 5, icon, 63);
    t[68] = 0x83;
    t[69] = 7;
    t[70] = 1;
    memcpy(t + 77, "VeraBASIC   V1.0", 16);
    memcpy(t + 117, "VBRun       V1.0", 16);
    memcpy(t + 160, "A VeraBASIC program.", 20);
    for (i = 0; i < 4; ++i)
        if (vt_size[i]) {
            entry(hd + 508 + 2 * i, vt_size[i]);
            nb += hd[508 + 2 * i];
        } else
            hd[509 + 2 * i] = 0xFF;
    n = strlen(NAME) - 4;               /* the GEOS name: the file's, 16 characters */
    strcpy(PATH, NAME);
    PATH[n > 16 ? 16 : n] = 0;
    dir_entry(PATH, 2 + nb);
    wr(hd, 762);
    for (i = 0; i < 4; ++i)
        if (vt_size[i]) {
            rec_out(i, piece_doc);
            zeros(hd[508 + 2 * i] * 254 - vt_size[i]);
        }
    close_out();
}

/*---------------------------------------------------------------
  the APP lines (tools/vbapp.py app_lines, the same rules)
 ---------------------------------------------------------------*/
static const char e_app[] = "APP: NAME \"...\", CLASS \"...\", TILE SKY ...";
static const char e_tile[] = "TILE DATA: 32 rows of 32 \"#\" and \".\"";
static const char e_docs[] = "APP DOCUMENTS: up to 4 of 1-4 letters";
static const char e_name[] = "The name: 1-63 characters, no / : * ? = \"";

static unsigned char is_alpha(unsigned char c)
{
    return (c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z') || c == '_';
}

static unsigned char is_digit(unsigned char c)
{
    return c >= '0' && c <= '9';
}

static void blanks(void)
{
    while (li < ln && (lexbuf[li] == ' ' || lexbuf[li] == 9))
        ++li;
}

/* the next item: 's' a string (its start in lexbuf: str, length slen), 'w'
   a word (word), 'n' a number (num), ',', or 0 at the end (a comment) */
static unsigned char item(void)
{
    unsigned char c, n;
    blanks();
    if (li >= ln)
        return 0;
    c = lexbuf[li];
    if (c == '"') {
        str = ++li;
        while (li < ln && lexbuf[li] != '"')
            ++li;
        if (li >= ln) {
            a_err = e_app;
            return 0;
        }
        slen = li++ - str;
        return 's';
    }
    if (c == ',') {
        ++li;
        return ',';
    }
    if (c == '\'')
        return 0;
    if (is_digit(c)) {
        num = 0;
        while (li < ln && is_digit(lexbuf[li]))
            num = num * 10 + lexbuf[li++] - '0';
        return 'n';
    }
    if (is_alpha(c)) {
        n = 0;
        while (li < ln && (is_alpha(c = lexbuf[li]) || is_digit(c))) {
            if (c >= 'a' && c <= 'z')
                c -= 32;
            if (n < 15)
                word[n++] = c;
            ++li;
        }
        word[n] = 0;
        if (!strcmp(word, "REM"))
            return 0;
        return 'w';
    }
    a_err = e_app;
    return 0;
}


/* a string item into to (most characters at most) */
static unsigned char take(char *to, unsigned char most)
{
    if (item() != 's' || slen > most) {
        a_err = e_app;
        return 0;
    }
    memcpy(to, lexbuf + str, slen);
    to[slen] = 0;
    return 1;
}

/* the APP words; the first five take a string, into these, this long */
static const char *const words[9] = { "NAME", "CLASS", "VERSION", "AUTHOR", "DESCRIPTION",
    "DOCUMENTS", "TILE", "STAY", "CLASSIC" };
static char *const field[5] = { a_name, a_class, a_ver, a_auth, a_desc };
static const unsigned char most[5] = { 63, 12, 6, 19, 95 };

static unsigned char find(const char *const *list, unsigned char n)
{
    unsigned char i;
    for (i = 0; i < n; ++i)
        if (!strcmp(word, list[i]))
            return i;
    return 0xFF;
}

static void app_line(void)
{
    unsigned char k, i, w;
    for (;;) {
        if (item() != 'w' || (w = find(words, 9)) == 0xFF) {
            a_err = e_app;
            return;
        }
        if (w < 5) {
            if (!take(field[w], most[w]))
                return;
        } else if (w == 5) {            /* DOCUMENTS e$ [, e$] ... */
            for (;;) {
                if (nd >= 4 || !take(a_docs + 4 * nd, 4) || !slen) {
                    a_err = e_docs;
                    return;
                }
                for (i = 0; i < 4; ++i) {
                    k = a_docs[4 * nd + i];
                    if (!k)
                        for (; i < 4; ++i)
                            a_docs[4 * nd + i] = ' ';
                    else if (k >= 'a' && k <= 'z')
                        a_docs[4 * nd + i] = k - 32;
                    else if (!(is_digit(k) || (k >= 'A' && k <= 'Z')))
                        a_err = e_docs;
                }
                a_docs[4 * ++nd] = 0;
                if (a_err)
                    return;
                k = li;                 /* (another string after a comma?) */
                if (item() == ',' && item() == 's') {
                    li = str - 1;
                    continue;
                }
                li = k;
                break;
            }
        } else if (w == 6) {            /* TILE colour */
            a_col = 0xFF;
            k = item();
            if (k == 'w')
                a_col = find(colours, 16);
            else if (k == 'n' && num < 16)
                a_col = num;
            if (a_col == 0xFF) {
                a_err = e_app;
                return;
            }
        } else if (w == 7)
            a_stay = 4;
        k = item();
        if (!k)
            return;
        if (k != ',') {
            a_err = e_app;
            return;
        }
    }
}

/* TILE DATA "row", "row" ...: into the tile's bitmap */
static void tile_line(void)
{
    unsigned char k, i, *b;
    do {
        if (item() != 's' || slen != 32 || a_rows >= 32) {
            a_err = e_tile;
            return;
        }
        b = tile + 4 * a_rows++;
        memset(b, 0, 4);
        for (i = 0; i < 32; ++i) {
            k = lexbuf[str + i];
            if (k == '#')
                b[i >> 3] |= 0x80 >> (i & 7);
            else if (k != '.')
                a_err = e_tile;
        }
    } while ((k = item()) == ',' && !a_err);
    if (k)
        a_err = e_tile;
}

/* the whole text's APP lines; 0 and a box on an error */
static unsigned char app_lines(void)
{
    unsigned long ls = 0;
    unsigned int n, k;
    base_name();
    strcpy(a_name, NAME);
    a_class[0] = a_auth[0] = a_desc[0] = a_docs[0] = 0;
    strcpy(a_ver, "1.0");
    a_col = 0xFF;
    a_rows = a_stay = nd = 0;
    a_err = 0;
    for (a_line = 1; ls < gb_len && !a_err; ++a_line) {
        gb_a = ls;
        gb_n = 256;
        gb_lp = lexbuf;
        n = gb_read();
        for (k = 0; k < n && lexbuf[k] != 10; ++k)
            ;
        ls += k + 1;
        ln = (unsigned char)k;
        li = 0;
        blanks();
        while (li < ln && is_digit(lexbuf[li]))
            ++li;
        k = item();
        a_err = 0;
        if (k != 'w')
            continue;
        if (!strcmp(word, "APP"))
            app_line();
        else if (!strcmp(word, "TILE")) {
            if (item() == 'w' && !strcmp(word, "DATA"))
                tile_line();
            else
                a_err = 0;
        } else
            a_err = 0;
    }
    if (a_err)
        --a_line;
    else {
        a_line = 0;
        if (!a_class[0])                /* (none given: the name's first 12) */
            memcpy(a_class, a_name, 12), a_class[12] = 0;
        if (!a_name[0])
            a_err = e_name;
        for (k = 0; a_name[k]; ++k)
            if (strchr("/:*?=\"", a_name[k]))
                a_err = e_name;
        if (a_rows && a_rows != 32)
            a_err = e_tile;
    }
    if (a_err) {
        strcpy(PATH, "Make application: ");
        if (a_line)
            tk_put_ul(tk_put_s(PATH + 18, "line "), a_line);
        message(PATH, a_err);
        return 0;
    }
    return 1;
}

/*---------------------------------------------------------------
  Make application
 ---------------------------------------------------------------*/
static const char runname[] = "VeraBASIC Run.cvt";

static void make_app(void)
{
    unsigned char rin, i, nc, *t;
    unsigned int nb = 0, k;
    unsigned long len, at;
    unsigned int got;
    if (!app_lines())
        return;
    /* VeraBASIC Run's file: /VERANDA/APPS (else /VERANDA, the top folder) */
    strcpy(PATH, runname);
    sys_dir();
    rin = FOpen(PATH, 'r');
    if (rin < 2) {
        PATH[0] = '/';
        PATH[1] = 0;
        ChDir(PATH);
        strcpy(PATH, runname);
        rin = FOpen(PATH, 'r');
    }
    if (rin < 2) {
        doc_dir();
        message("VeraBASIC Run is needed to make an application", "(in /VERANDA/APPS).");
        return;
    }
    for (k = 0; k < 762; k += got) {
        got = FRead(rin, iobuf, 762 - k > TK_IOBUF ? TK_IOBUF : 762 - k);
        if (!got)
            break;
        memcpy(hd + k, iobuf, got);
    }
    t = hd + 508;
    if (k < 762 || hd[21] != 1 || memcmp(hd + 254 + 135, "VRND", 4) || t[24] || t[25] || !t[22]) {
        FClose(rin);
        doc_dir();
        message("This VeraBASIC Run cannot be used", "to make an application.");
        return;
    }
    for (i = 0; i < 12; ++i)
        nb += t[2 * i];
    /* the name and the folder (/VERANDA/APPS first) */
    strcpy(keepdir, (char *)curDirName);
    strcpy((char *)curDirName, vr_cd(VR_APPS));
    strcpy(NAME, a_name);
    if (!choose("Make the application as") || !open_out()) {
        FClose(rin);
        strcpy((char *)curDirName, keepdir);
        doc_dir();
        return;
    }
    /* the header of the program's records (record 12) */
    memset(hb, 0, sizeof hb);
    memcpy(hb, "VBAP", 4);
    hb[4] = 1;
    BankCopy((void *)0xA002, iobuf, 1, vt_recb[0], 0);    /* (its token format) */
    hb[5] = iobuf[0];
    len = 80;
    for (i = 0; i < 4; ++i) {
        hb[6 + 2 * i] = (unsigned char)vt_size[i];
        hb[7 + 2 * i] = vt_size[i] >> 8;
        len += vt_size[i];
    }
    strcpy((char *)hb + 16, a_name);
    /* the record table: the program's records after Run's 12 */
    nc = (unsigned char)((len + 8190) / 8191);
    if (12 + nc > 127) {
        FClose(rin);
        FClose(out);
        FDelete(NAME);
        strcpy((char *)curDirName, keepdir);
        doc_dir();
        message("The program is too big", "for an application.");
        return;
    }
    for (i = 0, at = len; i < nc; ++i, at -= 8191) {
        entry(t + 24 + 2 * i, at > 8191 ? 8191 : (unsigned int)at);
        nb += t[24 + 2 * i];
    }
    /* the info block: class, author, flags, documents, description */
    t = hd + 254 - 2;
    memset(t + 77, 0, 40);
    memset(t + 144, 0, 112);
    strcpy((char *)t + 77, a_class);
    k = strlen(a_class);
    memset(t + 77 + k, ' ', 12 - k);
    t[89] = 'V';
    strcpy((char *)t + 90, a_ver);
    t[90 + strlen(a_ver)] = 0;
    strcpy((char *)t + 97, a_auth);
    t[143] = 1 | 2 | a_stay;
    memcpy(t + 144, a_docs, 4 * nd);
    strcpy((char *)t + 160, a_desc);
    /* the tile, the directory entry */
    if (a_col != 0xFF)
        hd[96] = a_col;
    if (a_rows)
        memcpy(hd + 97, tile, 128);
    dir_entry(a_name, 2 + nb);
    wr(hd, 762);
    /* Run's records as they are */
    len = 0;
    for (i = 0; i < 12; ++i)
        len += hd[508 + 2 * i];
    len *= 254;
    while (len && !werr) {
        k = FRead(rin, iobuf, len > TK_IOBUF ? TK_IOBUF : (unsigned int)len);
        if (!k) {
            werr = 1;
            break;
        }
        if (FWrite(out, iobuf, k))
            werr = 1;
        len -= k;
    }
    FClose(rin);
    /* the program: its header, its four records, 8191 bytes a record */
    clen = 0;
    app_bytes(hb, 80);
    for (i = 0; i < 4; ++i)
        rec_out(i, piece_app);
    if (clen)
        zeros(blocks(clen) * 254 - clen);
    close_out();
    strcpy((char *)curDirName, keepdir);
    doc_dir();
}

/* the answer to IR_FORMAT for one of them: the records written, then given back */
void mk_answer(void)
{
    unsigned char b;
    if (ide_make == 1)
        save_prog();
    else
        make_app();
    ide_make = 0;
    for (b = 0; b < 4; ++b)
        if (vt_recb[b]) {
            BankFree(vt_recb[b]);
            vt_recb[b] = 0;
        }
}
