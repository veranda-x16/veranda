/* VeraBASIC, the editor (DECISIONS V93): B_FILE, the commands on the
   document (textkit's file.c and scrap.c are in this bank too), the menus'
   layout (Veranda Edit's menus.c), and the text given to the runtime's
   side: a run of banks the tokenizer reads (vbprep.s compile, _vt_inmem).

   MIT licence (LICENSE). */
#include <string.h>
#include "ide.h"

unsigned char export_ok;

void cmd_new(void) { m_new(); err_line = stop_line = 0; XCALL(B_VIEW, view_all); }
void cmd_open(void) { m_open(); err_line = stop_line = 0; XCALL(B_VIEW, view_all); }
void cmd_save(void) { m_save(); }
void cmd_saveas(void) { m_saveas(); }
void cmd_quit(void) { m_quit(); }
void cmd_cut(void) { m_cut(); }
void cmd_copy(void) { m_copy(); }
void cmd_paste(void) { m_paste(); }

/* the text (LF line ends) into a run of banks: vt_src, vt_srclen; the
   program's name for the run's title */
void cmd_export(void)
{
    unsigned long len = gb_len, at;
    unsigned int k;
    unsigned char n, b;
    export_ok = 0;
    if (len >= 0xFF00) {
        message("The program is too big for VeraBASIC", "(64 KB of text at most).");
        return;
    }
    n = (unsigned char)((len + 8191) >> 13);
    if (!n)
        n = 1;
    b = BankAlloc(n);
    if (!b) {
        message("There is not enough memory", "to check the program (RAM banks).");
        return;
    }
    for (at = 0; at < len; at += k) {   /* (TK_IOBUF divides a bank) */
        k = len - at > TK_IOBUF ? TK_IOBUF : (unsigned int)(len - at);
        gb_a = at;
        gb_n = k;
        gb_lp = iobuf;
        gb_read();
        BankCopy(iobuf, (void *)(0xA000 + ((unsigned int)at & 0x1FFF)), k, 0, b + (unsigned char)(at >> 13));
    }
    vt_src = b;
    vt_srclen = (unsigned int)len;
    strcpy(vb_docname, docname[0] ? docname : TK_UNTITLED);
    export_ok = 1;
}

/*---------------------------------------------------------------
  the menus' texts (Sunroom, V149): "\x1f" starts a group (the kernel's
  dotted line over the item), the key after a TAB (the kernel puts it at
  the list's right: only keys ide_key handles); copied into LOW's mi_text
  (the kernel reads the texts below $A000 and writes into them)
 ---------------------------------------------------------------*/
struct item { const char *text; unsigned char type; void *p; };
struct menuh { unsigned char top, bottom; unsigned int left, right; unsigned char flags; struct item i[1]; };
extern struct menuh mi_vb, mi_file, mi_edit, mi_search, mi_run, mi_help, mi_bar;
extern char mi_text[560];

#define G "\x1f"
static const char *const names[36] = {
    "New\tCtrl N", "Open...\tCtrl O", G "Save\tCtrl S", "Save as...\tCtrl Shift S",
    G "Save program...", "Make application...", G "Quit\tCtrl Q",
    "Undo\tCtrl Z", G "Cut\tCtrl X", "Copy\tCtrl C", "Paste\tCtrl V",
    "Select all\tCtrl A", G "Format\tCtrl Shift F", "Line numbers",
    "Find and replace...\tCtrl F", "Find next\tF3", "Replace, find next\tCtrl H",
    G "Go to line...\tCtrl L", "Next error\tF8",
    "Run\tCtrl R", "Check\tCtrl K", "Stop", "Output\tF5",
    G "Continue\tF6", "Step\tF7", "Step over\tF10", "Step out\tF11",
    G "Breakpoint\tF9", "Add a watch...\tCtrl W", G "Trace (TRON)", "The trace\tF12",
    "Help on the word\tF1", G "Contents", "Index", "Tutorial",
    "Error messages",
};
static struct menuh *const menus[5] = { &mi_file, &mi_edit, &mi_search, &mi_run, &mi_help };
static const unsigned char first[6] = { 0, 7, 14, 19, 31, 36 };

static unsigned int mi_at;

/* a text's width as the kernel lays a list out (shell/look3.c's mwidth) */
static unsigned int strw(const char *s)
{
    unsigned int w = 0;
    unsigned char c;
    while ((c = *s++) != 0)
        if (c == 9)
            w += 24;
        else if (c != 0x1F)
            w += GetCharWidth(c);
    return w;
}

static unsigned int build(unsigned char m)
{
    unsigned char i, a = first[m];
    unsigned int w, mx = 0;
    char *p;
    for (i = a; i < first[m + 1]; ++i) {
        p = mi_text + mi_at;
        strcpy(p, names[i]);
        menus[m]->i[i - a].text = p;
        mi_at += strlen(p) + 1;
        if ((w = strw(p)) > mx)
            mx = w;
    }
    return mx;
}

void cmd_layout(void)
{
    static struct menuh *const subs[6] = { &mi_vb, &mi_file, &mi_edit, &mi_search, &mi_run, &mi_help };
    unsigned int x = 0, w;
    unsigned char i;
    UseFont(FONT_UI);                   /* (the menus' font: theme_menus, V79) */
    mi_at = 0;
    for (i = 0; i < 6; ++i) {
        w = (i ? build(i - 1) : strw("About VeraBASIC")) + 8;
        subs[i]->left = x;
        subs[i]->right = x + w;
        barx[i] = x + 4;
        x += strw(mi_bar.i[i].text) + 8;
    }
    mi_bar.right = x + 64;              /* (past the kernel's bar end, V74) */
    UseSystemFont();
}
