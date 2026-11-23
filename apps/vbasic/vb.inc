; VeraBASIC Run: the runtime's constants (DECISIONS V86; the token format:
; docs/vbasic/FORMAT.md; the frames' sizes are tools/vbasic.py's too).
; MIT licence (LICENSE).

; VB_LOG: a test build (VB_TEST, IDE_TEST): the emulator's console and
; cycle counter ($9FB0-$9FBF) used; a release build has none of that code
; (V106: on hardware those addresses are an expansion card's, IO5)
.if .defined(VB_TEST) .or .defined(IDE_TEST)
VB_LOG  = 1
.endif

; the value types (as the symbol table's)
TY_F    = 0
TY_I    = 1
TY_S    = 2

; a cell's type byte (cell + 7): a variable's 8 bytes, value first
CT_TYPE = $03                   ; TY_*
CT_CONST = $10                  ; a built-in constant
CT_ARRAY = $20                  ; an array (bytes 0-2: its header in the array space; 5: dimensions, 0 not yet)
CT_FUNC = $40                   ; a FUNCTION (byte 0: its procedure)
CT_REF  = $80                   ; a BYREF or array parameter: bytes 0-2 the caller's cell (address, bank)

; strings: a string value in acc / on the value stack (a0-a4, aty = TY_S)
;   a4 = SK_LIT  a0 length, a1/a2 address, a3 bank (a literal: stays put)
;   a4 = SK_TMP  a0 length, a1 the temporary's slot (temps: its descriptor)
;   a4 = SK_VAR  a1/a2 the variable's cell, a3 its bank (0: main RAM)
SK_LIT  = 0
SK_TMP  = 1
SK_VAR  = 2

; the frames on the BASIC stack: their bytes, then [size lo, size hi, kind]
FK_GOSUB = 1
FK_FOR  = 2
FK_SELECT = 3
FK_TRY  = 4
FK_CALL = 5
FR_GOSUB = 6
FR_FOR  = 24
FR_SELECT = 11
FR_TRY  = 12
FR_CALL = 14                    ; + 8 a slot (+ the evaluator's saved stack for a FUNCTION)
STACKTOP = $C000 - 32

; the program's banks: an 8 KB bank holds 7936 bytes of record 1 from
; its start ($1F00 a bank) and the next bank's first 256 bytes after them,
; so that no line record crosses a bank (records are at most 255 bytes)
PSTRIDE = 31                    ; $1F00 / 256

; the console (apps/vbasic/main.c draws it)
CON_W   = 78
CON_H   = 54
CON_X   = 1                     ; card column of column 0
CON_Y   = 4                     ; card row of row 0

; the run states (vb_state)
VS_IDLE = 0
VS_RUN  = 1
VS_END  = 2                     ; ended (END, the last line, an error)
VS_BRK  = 3                     ; (the editor) stopped by the debugger: it goes on (DECISIONS V97)

VSTK    = 40 * 6                ; the value stack's bytes (6 a value)
NTEMP   = 32                    ; temporary strings

; the token tags (vbasic/gen/tokens.inc)
T_EOL   = $00
T_INTDEC = $01
T_INTHEX = $02
T_INTBIN = $03
T_FLOAT = $04
T_STRING = $05
T_VAR   = $06
T_LINEREF = $07
T_NAMEREF = $08
T_COMMENT = $09
T_DATA  = $0A
T_BLOCK = $0B
T_EXT   = $FF

; errors (tools/vbasic.py ERRORS)
E_STOP  = 1
E_SYNTAX = 2
E_RETURN = 3
E_DATA  = 4
E_ILLQ  = 5
E_OVER  = 6
E_MEM   = 7
E_LINE  = 8
E_SUBS  = 9
E_REDIM = 10
E_DIV0  = 11
E_NOTARR = 12
E_TYPE  = 13
E_LONG  = 14
E_COMPLEX = 15
E_STACK = 16
E_RESUME = 17
E_NEXT  = 18
E_ARGS  = 19
E_NOTYET = 20
E_NEWER = 21
E_NOSUB = 22
E_BYREF = 23
E_FONT  = 24                    ; (phase 3, DECISIONS V89)
E_NOWIN = 25
E_MENUS = 26
E_FNF   = 50                    ; (phase 4, DECISIONS V90: files and dialogs)
E_FMANY = 51
E_FNUM  = 52
E_FNOPEN = 53
E_FOPEN = 54
E_FMODE = 55
E_FEND  = 56
E_DISK  = 57
E_FEXIST = 58
E_PICT  = 59
E_DLG   = 60

; the core statements with a file handle (PRINT #, INPUT #, LINE INPUT #,
; GET #): run by overlay 6 as these second-page numbers (phase 4)
XP_PRINT = $F3
XP_INPUT = $F4
XP_GET  = $F5

; the ROM's maths library: ROM bank 4, its jump table (called, never copied)
FP_AYINT  = $FE00
FP_GIVAYF = $FE03
FP_FOUT   = $FE06
FP_FSUBT  = $FE15
FP_FADDT  = $FE1B
FP_FMULTT = $FE21
FP_FDIVT  = $FE27
FP_LOG    = $FE2A
FP_INT    = $FE2D
FP_SQR    = $FE30
FP_FPWRT  = $FE39
FP_EXP    = $FE3C
FP_COS    = $FE3F
FP_SIN    = $FE42
FP_TAN    = $FE45
FP_ATN    = $FE48
FP_ABS    = $FE4E
FP_SIGN   = $FE51
FP_FCOMP  = $FE54
FP_RND    = $FE57
FP_CONUPK = $FE5A
FP_MOVFM  = $FE63
FP_MOVMF  = $FE66
FP_MUL10  = $FE7B
FP_DIV10  = $FE7E
FAC       = $C3                 ; the library's zero page ($A9-$D3)
FACMO     = $C6                 ; ayint: the result's high byte, then its low
FBUFFR    = $0100               ; fout's text
IERROR    = $0300               ; BASIC's error vector: the library's errors
RNDX      = $03CE               ; the library's seed
MATHBANK  = 4

; the X16 ROM (bank 0: the KERNAL)
K_RDTIM   = $FFDE
K_KBDBUF_PUT = $FEC3
VERA_SCAN_L = $9F28             ; read: the scan line (bit 8: IEN bit 6)
