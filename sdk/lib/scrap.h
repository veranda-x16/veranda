/* Veranda's clipboard: GEOS's Text Scrap and Photo Scrap (lib/veranda.lib;
   docs/DECISIONS.md V54, docs/APPFORMAT.md "Scraps").

   A scrap is a GEOS file, sequential, of type SYSTEM, stored as a CVT
   file in the system folder: /VERANDA, or the root when there is no
   /VERANDA (where EnterDeskTop finds the desktop). The library finds the
   folder itself; an application does not change its directory for it.

   Text Scrap ("Text  Scrap": GEOS 2's name, with two spaces; class
   "Text  Scrap V2.0"): a word, the count of the bytes that follow, then
   GEOS text: characters 32-126, TAB (9), CR (13) ends a paragraph,
   PAGE_BREAK (12), and the escapes NEWCARDSET (23, the font id word, the
   style byte), ESC_RULER (17, 26 bytes of ruler), ESC_GRAPHICS (16, 4
   bytes). Veranda writes a NEWCARDSET first (BSW 9, plain, as geoWrite
   does at the start of a copy).

   Photo Scrap ("Photo Scrap", class "Photo Scrap V2.0"): the width in
   cards (1 byte), the height in rows (a word), the bitmap, width x height
   bytes in GEOS's compacted format (BitmapUp's); with colour, a byte a
   card after it (width x the card rows, row by row, compacted the same
   way): the ink in the high nibble, the paper in the low one (the C64's
   colour matrix order; Veranda's paper colours are palette entries 0-15,
   0 the normal paper).

   Every call returns 0 or an error (FILE_NOT_FOUND when there is no
   scrap, INCOMPATIBLE when it is not one, the DOS's errors), except the
   ones that return a length (0: none). One scrap is open at a time. */
#ifndef SCRAP_H
#define SCRAP_H

#define SCRAP_TEXT   0
#define SCRAP_PHOTO  1

/* ---- text ---- */

/* plain text (n bytes): '\n' (10) or CR (13) ends a paragraph, TAB stays,
   other control characters are dropped */
unsigned char __fastcall__ scrap_put_text(const char *s, unsigned int n);

/* GEOS text as it is (the caller's escapes; it should start with a
   NEWCARDSET) */
unsigned char __fastcall__ scrap_put_text_raw(const void *p, unsigned int n);

/* the text as plain characters into buf (at most max - 1, then a 0):
   the escapes dropped, CR (13) at the end of a paragraph, PAGE_BREAK as
   CR, TAB kept; the length (0: no text scrap) */
unsigned int __fastcall__ scrap_get_text(char *buf, unsigned int max);

/* the text with its escapes, as stored (at most max bytes); the length */
unsigned int __fastcall__ scrap_get_text_raw(void *buf, unsigned int max);

/* a text scrap of n bytes written in parts: scrap_text_begin(n), then
   scrap_write() of exactly n bytes of GEOS text in all (the NEWCARDSET
   is the caller's), then scrap_close() */
unsigned char __fastcall__ scrap_text_begin(unsigned int n);

/* ---- photo ---- */

/* a picture of w cards (1-80) by h rows: get(y, row) gives row y (w
   bytes, bit 7 the left pixel, 1 = ink); called twice for every row
   (the file's size is written first). colour(cx, cy) gives the card's
   colour byte (ink << 4 | paper), or colour = 0: black and white */
unsigned char scrap_put_photo(unsigned char w, unsigned int h,
                              void (*get)(unsigned int y, unsigned char *row),
                              unsigned char (*colour)(unsigned char cx, unsigned char cy));

/* the Photo Scrap's size (*w cards, *h rows) */
unsigned char __fastcall__ scrap_photo_size(unsigned char *w, unsigned int *h);

/* the picture: put(y, row) for every row (w bytes; the row is the
   library's), then, if it has colours, colour(cx, cy, c) for every card;
   returns 0, or an error (INCOMPATIBLE: the data ends early) */
unsigned char scrap_get_photo(void (*put)(unsigned int y, const unsigned char *row),
                              void (*colour)(unsigned char cx, unsigned char cy, unsigned char c));

/* ---- changes ---- */

/* 8 bytes that change when the scrap is written again: its date (year
   ... minute), a serial the library counts up at every write, its size;
   0, or FILE_NOT_FOUND (st all 0) */
unsigned char __fastcall__ scrap_stamp(unsigned char kind, unsigned char *st);

/* ---- the file itself ---- */

/* open a scrap for reading at its data: 1, or 0 (none, or not a scrap);
   scrap_read() then gives fewer bytes than asked at its end */
unsigned char __fastcall__ scrap_open(unsigned char kind);
/* create one for len bytes of data (the size goes into its entry) */
unsigned char __fastcall__ scrap_create(unsigned char kind, unsigned int len);
unsigned int __fastcall__ scrap_read(void *p, unsigned int n);
unsigned char __fastcall__ scrap_write(const void *p, unsigned int n);
unsigned char scrap_close(void);

/* GEOS text codes */
#define SCRAP_ESC_GRAPHICS  16
#define SCRAP_ESC_RULER     17
#define SCRAP_NEWCARDSET    23
#define SCRAP_PAGE_BREAK    12

#endif
