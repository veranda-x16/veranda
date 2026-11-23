/* Veranda's font picker (lib/veranda.lib, fontpick.s; DECISIONS V62).
   MIT licence (see LICENSE).

   FontPick opens a dialog box: the installed fonts (FontList: "System",
   "Veranda UI", then the fonts folder /VERANDA/FONTS), the chosen font's
   point sizes (FontSizes), a preview in that font and size, OK and
   Cancel. It starts on fp->name and fp->size (an empty name: the first
   font). On OK it returns OK with the choice in fp->name and fp->size and
   the font loaded: fp->handle for UseFont (FONT_NONE if it could not be
   loaded); else CANCEL, fp unchanged. The program's own font is the
   current one again afterwards.

   From assembly: a/x = the address of a struct fontpick, jsr FontPick;
   a = OK or CANCEL. The box uses uiFont's font for its lists, as other
   dialog boxes do. It needs about 1.5 KB of the program's memory. */
#ifndef FONTPICK_H
#define FONTPICK_H

struct fontpick {
    char name[32];              /* FONT_NAME_LEN: the font's name */
    unsigned char size;         /* its point size */
    unsigned char handle;       /* out: LoadFont's handle */
};

unsigned char __fastcall__ FontPick(struct fontpick *fp);

#endif
