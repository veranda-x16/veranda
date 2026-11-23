/* Disk Tools: check.c's results, for checkui.c (DECISIONS V119). MIT
   licence (see LICENSE). */
#ifndef CHECK_H
#define CHECK_H

#define MAXF    64              /* fault lines kept (128 bytes each: a RAM bank) */
enum { S_IDLE, S_CHAIN, S_DIR, S_FAT, S_DONE };
extern unsigned char st, nobits, bm, nbm, sbank, fbank;
extern unsigned int nstack, nfault, nshown, n_toomany;
extern unsigned long n_dirs, n_files, n_lost, n_free, n_fatdiff, s_fat;

#endif
