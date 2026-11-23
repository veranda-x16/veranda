/* Veranda's folders on the card (vrpath.h; DECISIONS V71). MIT licence.
   Directory commands go from the root with paths relative to it (the
   emulator's host folder refuses them elsewhere: DECISIONS V61). */
#include <veranda.h>
#include <string.h>
#include "vrpath.h"

static const char root[] = "/";

/* folder p made, from the root; 0 if it opens after */
static unsigned char made(const char *p)
{
    ChDir((void *)root);
    MkDir((void *)(p + 1));
    return ChDir((void *)p);
}

const char *vr_cd(unsigned char where)
{
    const char *p = where == VR_DATA ? VR_DATADIR : where == VR_APPS ? VR_APPSDIR
                  : where == VR_DOCS ? VR_DOCSDIR : VR_SYSDIR;
    if (ChDir((void *)p) == 0)
        return p;
    if (where == VR_SYS || ChDir((void *)VR_SYSDIR)) {
        ChDir((void *)root);                    /* no /VERANDA: the root */
        return root;
    }
    if (where == VR_APPS)
        return VR_SYSDIR;               /* not set up: the applications here */
    if (made(p) == 0)
        return p;
    if (where == VR_DOCS) {
        ChDir((void *)root);
        return root;
    }
    ChDir((void *)VR_SYSDIR);
    return VR_SYSDIR;
}

void vr_cdback(void)
{
    char *c = (char *)curDirName;
    if (c[0] != '/' || ChDir(c))
        ChDir((void *)root);
}

unsigned char vr_insys(const char *p)
{
    return strncmp(p, VR_SYSDIR, sizeof VR_SYSDIR - 1) == 0
        && (p[sizeof VR_SYSDIR - 1] == 0 || p[sizeof VR_SYSDIR - 1] == '/');
}

void vr_home(unsigned char opts)
{
    char *c = (char *)curDirName;
    if (c[0] != '/' || ChDir((void *)VR_SYSDIR))
        return;                         /* not from the shell (AUTOSTART), no /VERANDA: as before V71 */
    if (!(opts & ST_LD_DATA) && (c[1] == 0 || vr_insys(c)))
        strcpy(c, vr_cd(VR_DOCS));
    else if (ChDir(c))
        strcpy(c, vr_cd(VR_DOCS));      /* (its folder is gone) */
}
