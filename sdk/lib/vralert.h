/* Veranda SDK: an alert in Veranda Look 3 "Sunroom" (lib/veranda.lib,
   its own object; DECISIONS V148): the program's icon at the left, a bold
   headline, a plain explanation under it (wrapped to the box, up to three
   lines), the buttons at the bottom right; the default one (OK, Yes) has
   the kernel's double frame (V146). A dialog box (DoDlgBox) 38 cards wide,
   card aligned, centred on the screen.

   Keys: Return is the default button (OK or Yes), Esc is Cancel (or No,
   or OK in a message).

   The icon: 32 x 32 pixels, 1 bit (128 bytes, 4 a row, bit 7 the left
   pixel, 1 ink), in main RAM. tools/vicon.py --alert writes it from the
   program's colour icon (icon.txt, V133) as a C source:
       python3 $(SDK)/tools/vicon.py --alert icon.txt alerticon.c
   which defines  const unsigned char vr_icon[128];  then, once:
       vr_alert_icon = vr_icon;
   With no icon (0) the text starts at the box's left.

   Its routines are called by the kernel through vr_tramp's slot 0 (vr.h),
   so this file may be compiled into a banked overlay (its source is in
   the SDK's src/); its BSS must stay in main RAM. The menus must be
   closed. */
#ifndef VRALERT_H
#define VRALERT_H

#define VA_OK       0           /* OK */
#define VA_YESNO    1           /* No, Yes */
#define VA_YNC      2           /* No ... Cancel, Yes */
#define VA_OKCANCEL 3           /* Cancel, OK */

extern const unsigned char *vr_alert_icon;

/* kind VA_...; head: the headline (one line, bold); text: the explanation
   (0 or "": none). Returns OK, YES, NO or CANCEL (veranda.h). */
unsigned char __fastcall__ vr_alert(unsigned char kind, const char *head, const char *text);

#endif
