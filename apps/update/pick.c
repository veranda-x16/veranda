/* Veranda Update: Update's questions before it fetches (V198's, moved
   from job.c to overlay 4 in V210 for the pack's room there): the
   dictionaries to get, and the room on the card. Called through main.c's
   wrappers (choose, room) with overlay 4 mapped. MIT licence (see
   LICENSE). */
#include <veranda.h>
#include <string.h>
#include "up.h"

#pragma code-name ("OVERLAY4")
#pragma rodata-name ("OVL4RO")      /* (the boxes and say() copy their strings below $A000) */
#pragma bss-name ("OVL4BSS")

static const char *__fastcall__ base_(const char *p)
{
    const char *s = strrchr(p, '/');
    return s ? s + 1 : p;
}

/* (V198) the dictionaries: which to get. The list's files go by their
   name's first part ("EN" for EN.DIC and EN.DIC.txt, its licence): a box
   for each part with something to fetch; a part not chosen is skipped
   (as a doc-sample is). 0: nothing chosen */
static char pk[8];

static unsigned char __fastcall__ part_of(const char *path, char *out)
{
    const char *b = base_(path);
    unsigned char n = 0;
    while (b[n] && b[n] != '.' && n < sizeof pk - 1) {
        out[n] = b[n];
        ++n;
    }
    out[n] = 0;
    return n;
}

unsigned char choose_o(void)
{
    static char q[8];
    static unsigned long sz;
    unsigned char i, j, any = 0;
    for (i = 0; i < nents; ++i) {
        ent_get(i);
        if (E.st != S_CHANGED && E.st != S_NEW)
            continue;
        part_of(E.path, pk);
        for (j = 0; j < i; ++j) {        /* (a part asked about already) */
            ent_get(j);
            if ((E.st == S_CHANGED || E.st == S_NEW || E.st == S_SKIP) && part_of(E.path, q) && !strcmp(q, pk))
                break;
        }
        if (j < i)
            continue;
        sz = 0;
        for (j = i; j < nents; ++j) {
            ent_get(j);
            if ((E.st == S_CHANGED || E.st == S_NEW) && part_of(E.path, q) && !strcmp(q, pk))
                sz += E.size;
        }
        strcpy(line, "Get the ");
        strcat(line, !strcmp(pk, "EN") ? "English" : !strcmp(pk, "PL") ? "Polish" : pk);
        strcat(line, " dictionary (");
        ui_size(line + strlen(line), sz);
        strcat(line, ")?");
        if (up_confirm(line, "With its licence. Cancel: not this one.")) {
            any = 1;
            continue;
        }
        for (j = i; j < nents; ++j) {   /* (not this one) */
            ent_get(j);
            if ((E.st == S_CHANGED || E.st == S_NEW) && part_of(E.path, q) && !strcmp(q, pk)) {
                if (E.st == S_CHANGED)
                    --nchanged;
                else
                    --nnew;
                tchanged -= E.size;
                if (E.ready)
                    --nready;
                E.st = S_SKIP;
                ++nskip;
                ent_put(j);
            }
        }
    }
    ui_list();
    if (!any) {
        checked = 0;                    /* (Check again to choose again) */
        say("No dictionary chosen: nothing fetched.");
        up_log("UP NONE CHOSEN", "");
    }
    return any;
}

/* (V198) room on the card for what is to come (in UPD, then moved into
   place: the old versions go to OLD on the same card), with 64 KB to
   spare; CalcBlksFree's blocks of 254 bytes (65,535 at most: 16 MB,
   enough to tell) */
unsigned char room_o(void)
{
    unsigned long f = (unsigned long)CalcBlksFree() * 254;
#ifdef UP_TEST
    if (t_free)
        f = (unsigned long)t_free << 10;
#endif
    if (f >= tfetch + 65536UL)
        return 1;
    strcpy(line, "Not enough room on the card: ");
    ui_size(line + strlen(line), tfetch + 65536UL);
    strcat(line, " needed, ");
    ui_size(line + strlen(line), f);
    strcat(line, " free.");
    up_log("UP NOROOM ", line);
    up_message(line, "Nothing was fetched; make room and try again.");
    say("Not enough room on the card: nothing fetched.");
    return 0;
}
