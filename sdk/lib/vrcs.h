/* Veranda's character set (DECISIONS V140): ISO-8859-16 (Latin-10) for
   every byte of text above $7F, in documents, the clipboard (the Text
   Scrap), the fonts and the keyboard.

   Bytes $20-$7E are ASCII; $A0-$FF are ISO-8859-16: Polish (Ą ą Ć ć Ę ę
   Ł ł Ń ń Ó ó Ś ś Ź ź Ż ż), German, French (with Œ œ Ÿ), Italian,
   Hungarian (Ő ő Ű ű), Romanian (Ș ș Ț ț Ă ă), Croatian and Slovenian
   (Č č Ć ć Đ đ Š š Ž ž), the euro and „ ” « ». 56 of its 96 upper
   characters are Latin-1's at the same place, all eight of Latin-9's own
   (€ Š š Ž ž Œ œ Ÿ) are Latin-9's, and the X16 ROM speaks it: its
   ISO-8859-16 8 x 8 glyphs are in ROM bank 6 and its Polish keyboard
   layout gives these codes. $80-$9F are not characters (C1 controls; a
   program may keep private glyphs there, never in a file).

   This file is the one table between the set and Unicode: every program
   that reads or writes UTF-8 (the network programs, Veranda Edit's import
   and export, Veranda Write's plain text) converts with it. On the PC,
   tools/vrcs.py is the same (Python's iso8859_16 codec).

   In veranda.lib (476 bytes and 3 of BSS), and as src/vrcs.s for an
   overlay of one's own (ca65 -D VRCS_OVL=n: its code and tables in
   OVERLAYn, the decoder's 3 bytes in BSS). MIT licence (see LICENSE). */
#ifndef VRCS_H
#define VRCS_H

#define CS_BAD  '?'             /* what an unknown character becomes */

/* c's Unicode code point (c below $A0: c itself) */
unsigned int __fastcall__ cs_uni(unsigned char c);

/* u's byte in the set; 0 when the set has none (u below $80: u itself;
   $80-$9F: 0) */
unsigned char __fastcall__ cs_byte(unsigned int u);

/* c as UTF-8 at out (1, 2 or 3 bytes, not 0-terminated) -> the count */
unsigned char __fastcall__ cs_utf8(unsigned char c, char *out);

/* UTF-8 decoded a byte at a time: 0 while a sequence goes on, else the
   code point (U+FFFD for a broken sequence or one past U+FFFF, which
   takes the sequence's bytes; a sequence cut short by a byte that starts
   another, or by ASCII, is dropped); cs_dec_reset() before a new text */
void cs_dec_reset(void);
unsigned int __fastcall__ cs_dec(unsigned char b);

/* a 0-terminated UTF-8 string made the set's bytes in place (a character
   the set has none of becomes CS_BAD) -> its new length */
unsigned int __fastcall__ cs_from8(char *s);

/* the keyboard (sdk/lib/vrkbd.s, DECISIONS V142): with the settings'
   Polish keyboard (PREFS_POLISH) the ROM's key map becomes "PL-PL", Polish
   (programmers): right Alt + a c e l n o s x z (Shift: capitals) types the
   letters above, and the kernel then reports neither Alt nor Ctrl with
   them; without it nothing changes. The shell calls it as it starts,
   Preferences after Save. vr_keymap: the ROM's keymap call. */
void vr_kbd(void);
void __fastcall__ vr_keymap(const char *name);

#endif
