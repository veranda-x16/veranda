/* Veranda's folders on the card (DECISIONS V71), for programs.

   The layout (the paths are the API's, veranda.h: VR_SYSDIR ...):
       /VERANDA            VERANDA.PRG, VERANDA.SYS, RBOOT, SHELL.cvt
       /VERANDA/APPS       the applications and desk accessories
       /VERANDA/FONTS      the fonts
       /VERANDA/.SYSTEM    the system's data (hidden): settings, alarms,
                           the scraps, Note File, the albums, the trash
       /DOCUMENTS          the user's files
   Fallbacks: a card with no /VERANDA keeps everything in the root (as
   before V71; the gates' host folders); a card with no APPS (not set up
   yet) has its applications in /VERANDA. .SYSTEM and /DOCUMENTS are made
   when they are missing (only where /VERANDA exists). */
#ifndef VRPATH_H
#define VRPATH_H

#define VR_SYS  0       /* /VERANDA, else the root */
#define VR_DATA 1       /* /VERANDA/.SYSTEM (made), else /VERANDA, else the root */
#define VR_APPS 2       /* /VERANDA/APPS, else /VERANDA, else the root */
#define VR_DOCS 3       /* /DOCUMENTS (made, with /VERANDA), else the root */

/* Veranda Setup (in /VERANDA): it moves a card from the layout before V71
   into this one, once; its log in VR_DATADIR is the mark that it ran */
#define VR_SETUP     "Veranda Setup"
#define VR_SETUP_LOG "LAYOUT.LOG"

/* that folder made the current directory; its path (curDirName's form,
   "/" for the root). curDirName is not changed. */
const char *vr_cd(unsigned char where);

/* the program's working folder at its start: one the shell started
   without a document (opts = r0L at the start, ST_LD_DATA clear) from the
   system's folders or the root starts in /DOCUMENTS: curDirName set and
   made current, so its first Save and Open are there; one started with a
   document, or from a folder of the user's, stays (curDirName made
   current). Nothing changes on a card with no /VERANDA, or for a program
   the shell did not start (curDirName empty: AUTOSTART). */
void vr_home(unsigned char opts);

/* back to the program's working folder, curDirName (the root without
   one): after a visit to another folder */
void vr_cdback(void);

/* is path p (curDirName's form) the system folder or inside it? */
unsigned char vr_insys(const char *p);

#endif
