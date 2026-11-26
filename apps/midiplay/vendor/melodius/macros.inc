; Melodius's macros (github.com/mooinglemur/melodius, src/macros.inc at
; 3720fa5028c5df6d7ff3bfed1fb7a1413131fb82; MIT, Copyright (c) 2023
; MooingLemur: LICENSE). Veranda: the border-colour macros are empty (VERA's
; $9F2C is another register when DCSEL is not 0, and Veranda's main loop
; may have it so).
.ifndef macros_inc
macros_inc = 1

.include "x16.inc"

.macro MIDI_BORDER
    ; (Veranda: nothing; Melodius shows its timing in the border colour)
.endmacro

.macro KERNAL_BORDER
    ; (Veranda: nothing; Melodius shows its timing in the border colour)
.endmacro

.macro DONE_BORDER
    ; (Veranda: nothing; Melodius shows its timing in the border colour)
.endmacro

.macro API_BORDER
    ; (Veranda: nothing; Melodius shows its timing in the border colour)
.endmacro

.macro VIZ_BORDER
    ; (Veranda: nothing; Melodius shows its timing in the border colour)
.endmacro

.macro WAITVSYNC frames
.local endless
.local FRC
	jsr X16::Kernal::RDTIM
.ifnblank frames
	clc
	adc #frames
.endif
	sta FRC
endless:
	wai
	jsr X16::Kernal::RDTIM
	cmp #$ff
FRC = * -1
.ifnblank frames
	bne endless
.else
	beq endless
.endif
.endmacro

.endif
