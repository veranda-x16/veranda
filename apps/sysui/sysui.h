/* sysui: the parts Disk Tools (apps/disktools) and About this X16
   (apps/about) share (DECISIONS V119), as apps/daui is the accessories':
   the Look 2 window with a toolbar of buttons, lines of text in the UI
   font, buttons in the body, the dialog boxes, numbers and sizes as text;
   the card as the DOS lists it (its name, the free space; the emulator's
   host folder) and as its sectors say (sd.s: the partition, FAT32's
   geometry, the CSD's capacity); a DOS command on the kernel's command
   channel (dos.s). MIT licence (see LICENSE). */
#ifndef SYSUI_H
#define SYSUI_H

#define RAMBANK (*(volatile unsigned char *)0)
#define BANKMEM ((unsigned char *)0xA000)

/*---------------------------------------------------------------- the window */
#define WIN_TOP   16            /* the title band */
#define TOOL_TOP  32            /* the toolbar: 2 card rows */
#define BODY_TOP  48            /* the body */
#define BODY_BOT  463
#define LINE_H    16            /* a line of the body */
#define VAL_X     216           /* a value's column (pixels) */

/* the window, its title */
void __fastcall__ ui_window(const char *title);
/* the status bar's left and right texts (either may be 0) */
void __fastcall__ ui_status(const char *left, const char *right);

/* toolbar buttons: x and width in cards; sel: the one shown chosen (a
   tab), 0xFF none */
struct btn { unsigned char x, w; const char *t; };
void __fastcall__ ui_toolbar(const struct btn *b, unsigned char n, unsigned char sel);
/* the toolbar button under pixel x, or 0xFF */
unsigned char __fastcall__ ui_tool_at(const struct btn *b, unsigned char n, unsigned int x);

/* the body cleared (lines y0 .. y1, pixels), its hot spots forgotten */
void __fastcall__ ui_clear(unsigned int y0, unsigned int y1);
/* text in the UI font at x, its 16-line band from y (bold: 1); its width */
unsigned int __fastcall__ ui_text(unsigned int x, unsigned int y, const char *s, unsigned char bold);
unsigned int __fastcall__ ui_width(const char *s, unsigned char bold);
/* a line of the body: the band from y cleared, label at 16, value at VAL_X */
void __fastcall__ ui_pair(unsigned int y, const char *label, const char *value);
/* a button in the body at pixel x, band y: a rounded frame round t; id is
   what ui_hot gives for a click on it; its right edge */
unsigned int __fastcall__ ui_button(unsigned int x, unsigned int y, const char *t, unsigned char id);
/* a hot spot (a clickable area) of the body */
void __fastcall__ ui_hot_add(unsigned int l, unsigned int t, unsigned int r, unsigned int b, unsigned char id);
unsigned char __fastcall__ ui_hot(unsigned int x, unsigned int y);
/* a rounded frame */
void __fastcall__ ui_rframe(unsigned int l, unsigned int t, unsigned int r, unsigned int b);

/*---------------------------------------------------------------- boxes */
void __fastcall__ ui_message(const char *a, const char *b);
/* OK (Return) or Cancel: 1 for OK */
unsigned char __fastcall__ ui_confirm(const char *a, const char *b);
/* buf (below $A000; its text the default) edited in a box: 0 cancelled */
unsigned char __fastcall__ ui_ask(const char *prompt, char *buf, unsigned char max);

/*---------------------------------------------------------------- numbers */
/* v in decimal at p; the end */
char *__fastcall__ ui_num(char *p, unsigned long v);
/* a size: "512 bytes", "4.5 KB", "12.3 MB", "1.9 GB" */
char *__fastcall__ ui_size(char *p, unsigned long v);
/* two digits */
char *__fastcall__ ui_dd(char *p, unsigned char v);
/* "0x" and 8 hex digits */
char *__fastcall__ ui_hex(char *p, unsigned long v, unsigned char digits);

/*---------------------------------------------------------------- the card */
struct card {
    unsigned char host;         /* the emulator's host folder (no FAT) */
    char label[18];             /* the DOS's name of it (the header) */
    unsigned long dfree;        /* the free KB the DOS lists (rounded to its unit) */
    unsigned char dunit;        /* the unit the DOS gave them in: 'K' 'M' 'G' ('B' blocks: the host) */
    /* from its sectors (sd_ok): */
    unsigned char sd_ok;
    unsigned char ptype;        /* the MBR's partition type, 0 none (no MBR) */
    unsigned char spc, nfats;
    unsigned int resv;
    unsigned long part_lba, part_sec;   /* the partition: first sector, sectors */
    unsigned long fat_lba, fatsz, data_lba;
    unsigned long nclus;        /* data clusters (2 .. nclus + 1) */
    unsigned long root;         /* the root folder's first cluster */
    unsigned long fsinfo_lba;
    unsigned long fsi_free;     /* FSInfo's free clusters, 0xFFFFFFFF unknown */
    unsigned long csd_kb;       /* the card's capacity in KB (its CSD register), 0 unknown */
    char vlabel[12];            /* the boot sector's label */
    char fstype[9];             /* the boot sector's "FAT32   " */
    char err[40];               /* why sd_ok is 0 */
};
extern struct card card;
/* everything read again (the root's listing, the card's sectors) */
void card_read(void);
/* the DOS's part alone: the root listed (the header, the footer) */
void card_dos(void);
/* a sector's 512 bytes (sd.s) */
extern unsigned long sd_lba;
extern unsigned char *sd_buf;
unsigned char sd_read(void);
unsigned char sd_csd(void);
extern unsigned char secbuf[512];

/* a DOS command (dos.s) */
unsigned char __fastcall__ dos_send(const char *s);
unsigned char __fastcall__ dos_reply(char *buf, unsigned char max);

/* little-endian words in a sector */
unsigned int __fastcall__ le16(const unsigned char *p);
unsigned long __fastcall__ le32(const unsigned char *p);

/* the clock as "2026-11-20 14:03:22" */
void __fastcall__ ui_clock(char *p);

/* the menu bar's lists under their items (vr_bar_end) and in the UI
   font's widths: lefts and rights of n vertical menus, the longest text
   of each; bx: each item's middle, bl: its left (a test clicks them) */
void __fastcall__ ui_menus(const char *const *names, unsigned char n, unsigned int **lefts,
                           unsigned int **rights, const char *const *longest, unsigned int *barright,
                           unsigned int *bx, unsigned int *bl);

#endif
