; Veranda resident core: the system icons of dialog boxes (tools/mkicons.py)
; Resident: bank G draws them (DoIcons' BitmapUp) and cannot see bank U.

.export IconOK, IconCancel, IconYes, IconNo, IconOpen, IconDisk

.segment "RODATA"

.include "sysicons.inc"
