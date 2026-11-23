; Veranda: Commander X16 hardware, ROM entry points and emulator ports

.ifndef X16HW_INC
X16HW_INC = 1

; banking
ram_bank                =       $00
rom_bank                =       $01

; VERA
VERA_ADDR_L             =       $9F20
VERA_ADDR_M             =       $9F21
VERA_ADDR_H             =       $9F22   ; bit 0: address bit 16; bits 7-4: increment
VERA_DATA0              =       $9F23
VERA_DATA1              =       $9F24
VERA_CTRL               =       $9F25   ; bit 0: ADDRSEL, bits 6-1: DCSEL
VERA_IEN                =       $9F26
VERA_ISR                =       $9F27
VERA_IRQ_LINE_L         =       $9F28
VERA_DC_VIDEO           =       $9F29   ; DCSEL 0
VERA_DC_HSCALE          =       $9F2A
VERA_DC_VSCALE          =       $9F2B
VERA_DC_BORDER          =       $9F2C
VERA_DC_HSTART          =       $9F29   ; DCSEL 1
VERA_DC_HSTOP           =       $9F2A
VERA_DC_VSTART          =       $9F2B
VERA_DC_VSTOP           =       $9F2C
VERA_L0_CONFIG          =       $9F2D
VERA_L0_MAPBASE         =       $9F2E
VERA_L0_TILEBASE        =       $9F2F
VERA_L0_HSCROLL_L       =       $9F30
VERA_L0_HSCROLL_H       =       $9F31   ; bitmap mode: palette offset
VERA_L0_VSCROLL_L       =       $9F32
VERA_L0_VSCROLL_H       =       $9F33
VERA_L1_CONFIG          =       $9F34
VERA_L1_MAPBASE         =       $9F35
VERA_L1_TILEBASE        =       $9F36
AUDIO_CTRL              =       $9F3B   ; PCM: b7 FIFO full (read) / reset (write)
AUDIO_RATE              =       $9F3C   ; PCM: 0 holds the DAC
AUDIO_DATA              =       $9F3D
VERA_AFLOW              =       $08     ; IEN/ISR: the PCM FIFO under 1/4
VERA_LINEIRQ            =       $02     ; IEN/ISR: the line interrupt (IRQ_LINE)

VERA_FX_CTRL            =       $9F29   ; DCSEL 2 (VERA FX, firmware 0.3.1 and later)
VERA_FX_MULT            =       $9F2C   ; DCSEL 2
VERA_FX_CACHE           =       $9F29   ; DCSEL 6: the 32-bit cache, 4 bytes
VERA_VERSION            =       $9F29   ; DCSEL 63: "V", major, minor, patch

VERA_INC1               =       $10     ; ADDR_H: increment 1
VERA_INC2               =       $20     ; (the address steps by 2)

; VRAM (docs/PLAN.md 5.1)
VRAM_FG                 =       $00000  ; foreground, up to 640x480 at 1 bpp
VRAM_BG                 =       $09600  ; back screen
VRAM_SAVEUNDER          =       $12C00  ; menus and dialogs
VRAM_SPRITES            =       $16C00  ; 8 x 2 KB
VRAM_FREE               =       $1AC00
; the shell's tile desktop (DECISIONS V101): layer 0 in 4 bpp 8 x 8 tiles
; at $13000-$16BFF (the save-under's room, which menus and dialog boxes do
; not use then), its map the colour map's place
VRAM_TILES              =       $13000
TILE_TB                 =       (VRAM_TILES >> 11) << 2 ; L0_TILEBASE: $98 (8 x 8)
TILE_CFG                =       $62     ; L0_CONFIG: 64 x 128 entries, 4 bpp tiles
TILE_HIROW              =       14      ; palette row: a covered card's highlight
TILE_COVROW             =       15      ; palette row: a covered card's paper
TILE_SHADOW             =       160     ; a map row's byte 160 + x: card x's own palette
				; row (high nibble) and its covers (low) when covered
VRAM_TILECOV            =       $1EB00  ; the covers in place (the map's row 63, off the screen)
VRAM_TILEPAL            =       $12C00  ; the program's palette entries 32-255 (448 bytes)
				; while tile mode is on: ColorOff puts them back
; (V166) the canvas (ColorRect COLOR_CANVAS, kernel/c/canvas.s): in the 320
; mode layer 0 an 8 bpp bitmap at VRAM_CANVAS (320 x 240, over the back
; screen and the save-under's usual room), the 1 bpp screen on layer 1 over
; it; palette entries 16-255 as they were kept at VRAM_CANVPAL (480 bytes);
; the save-under stack in the colour map's room, VRAM_CANVUNDER
VRAM_CANVAS             =       $02800  ; - $153FF
CANVAS_TB               =       (VRAM_CANVAS >> 11) << 2 ; L0_TILEBASE: $14 (320 wide)
CANVAS_CFG              =       $07     ; L0_CONFIG: bitmap, 8 bpp
VRAM_CANVPAL            =       $15400  ; - $155DF
VRAM_CANVUNDER          =       $1AC00  ; - $1EBFF (VRAM_SAVEUNDER + $8000)
VRAM_PSG                =       $1F9C0  ; the PSG: 16 voices of 4 bytes
VRAM_PALETTE            =       $1FA00
VRAM_SPRATTR            =       $1FC00

; X16 ROM (KERNAL API)
k_memtop                =       $FF99
k_setmsg                =       $FF90
k_setlfs                =       $FFBA
k_setnam                =       $FFBD
k_open                  =       $FFC0
k_close                 =       $FFC3
k_chkin                 =       $FFC6
k_chkout                =       $FFC9
k_clrchn                =       $FFCC
k_chrin                 =       $FFCF
k_chrout                =       $FFD2
k_load                  =       $FFD5
k_save                  =       $FFD8
k_getin                 =       $FFE4
k_clall                 =       $FFE7
k_readst                =       $FFB7
k_rdtim                 =       $FFDE
k_enter_basic           =       $FF47
k_cint                  =       $FF81   ; the screen editor: screen_init, the NVRAM profile, cleared
k_screen_mode           =       $FF5F
k_mouse_config          =       $FF68
k_mouse_get             =       $FF6B
k_mouse_scan            =       $FF26
k_clock_get_date_time   =       $FF50
k_clock_set_date_time   =       $FF4D
k_kbdbuf_get_modifiers  =       $FEC0
k_kbdbuf_put            =       $FEC3
k_macptr                =       $FF44
k_mciout                =       $FEB1
k_memory_crc            =       $FEEA   ; r0 address, r1 count -> r2 the CRC-16 (in the mapped RAM bank)
k_restor                =       $FF8A   ; the ROM's vectors $0314-$0333 back
irqvec                  =       $0314
brkvec                  =       $0316   ; CBINV: the ROM jumps here on a BRK

; x16emu test ports (emulator only; harmless on hardware)
EMU_SAVE_ON_EXIT        =       $9FB4   ; 1: write dump.bin when the emulator stops
EMU_CLOCK               =       $9FB8   ; write: reset; read $9FB8 (latches), then $9FB9-$9FBB
EMU_STDOUT              =       $9FBB   ; a byte to the console
EMU_DETECT1             =       $9FBE   ; reads "1"
EMU_DETECT2             =       $9FBF   ; reads "6"

.endif
