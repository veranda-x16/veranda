/* Veranda SDK: the standard Open and Save dialog (lib/veranda.lib;
   sdk/docs/GUIDE.md, section 6; Veranda Look 2, DECISIONS V79).

   A movable box in Veranda Look 2: a title band (drag it to move the
   box), the name field ("Save as:"; "Name:" when opening), the folder
   pop-up ("In:": the path's folders and the places Documents, Apps and
   the card, DECISIONS V71), the folder's folders and files by their long
   FAT names with kind badges (folders first, then files, by name
   regardless of case; ".." first below the top folder) and a scroll bar;
   New folder, a type filter (when the program gives one), Cancel and the
   default button (Save or Open, on the selection colour).

   Keys: up, down, PgUp, PgDn, Home, End move in the list; Return is the
   default button (on a folder: into it), Esc is Cancel; when opening a
   letter goes to the next name starting with it and Backspace up a
   folder; when saving letters and Backspace edit the name. The pointer:
   a click selects (when saving, a file's name goes into the field), a
   second click soon on the same one is the default button; the scroll
   bar pages; the wheel moves three names a notch. */
#ifndef VRCHOOSE_H
#define VRCHOOSE_H

#define VRF_OPEN 0              /* choose a file that exists */
#define VRF_SAVE 1              /* a name to save as (it may exist) */
#define VRF_NAME 63             /* the longest name, without its 0 */

/* The folder is curDirName ("/", "/Docs" ...: the path applications
   keep). With 1 the name is in name (64 bytes; in VRF_SAVE mode it is
   also what the field starts with), the folder chosen is in curDirName
   and is the current directory; 0: cancelled, nothing changed. title:
   the title band's text. Uses one RAM bank while it is open (up to 127
   entries a folder). The menus must be closed. Its routines run through
   vr_tramp (vr.h), so it may be compiled into a banked overlay (its
   source is in the SDK's src/; its BSS must stay in main RAM). */
unsigned char __fastcall__ vr_file(unsigned char mode, const char *title, char *name);

/* called every pass of the box's main loop (0: nothing): a test's
   player can watch for the program being idle */
extern void (*vr_file_hook)(void);

/* the file name given to a filter (0: every file shown): 1 to show it */
extern unsigned char (*vr_file_filter)(const char *name);

/* a type filter (0: none): its name, a colon, its extensions, as
   "Text files:TXT MD INI LOG"; the box starts with it on, and its button
   switches between it and "All files" */
extern const char *vr_file_types;

/* the longest name the field takes (VRF_NAME at most; a GEOS name: 16) */
extern unsigned char vr_file_max;

/* the box's place (its left card and top card row; vr_file_x = $FF:
   centred on the screen); a move sets them, so the next box opens there */
extern unsigned char vr_file_x, vr_file_y;

#endif
