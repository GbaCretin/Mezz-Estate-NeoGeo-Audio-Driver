	include "include/def.inc"
	include "include/macros.inc"

INSTRUMENTS equ instruments
ADPCMA_SFX  equ BANK0
MLM         equ MLM_header

; Dummy Z80 sound driver for Neo-Geo
; Implements a bare minimum working sound driver.
;==============================================================================;
; Things *not* found in this driver:
; * Sound playback
; * Coin sound (code $5F)
; * Eyecatch music (code $7F)
;==============================================================================;
	org &0000

; Start ($0000)
; Z80 program entry point.

Start:
	; disable interrupts and jump to the real beginning of the code
	di
	jp   EntryPoint

;==============================================================================;
; The Z80 has a number of interrupt vectors at the following locations:
; $0000, $0008, $0010, $0018, $0020, $0028, $0030, $0038

; $0000 and $0038 are reserved for the start location and IRQ, respectively.

; These vectors can be called via "rst n", where n is one of the locations in
; the above list (though only the lower byte, e.g. rst $08).
;==============================================================================;
	org &0008

; check_busy_flag ($0008)
; Continually checks the busy flag in Status 0 until it's clear.
; This routine is from smkdan's example M1 driver.

j_YM_reg_wait:
	jp YM_reg_wait

;==============================================================================;
	org &0010

; j_write45 ($0010)
; Jumps to a routine that writes the contents of de to ports 4 and 5.

j_write45:
	jp   write45

;==============================================================================;
	org &0018

; j_write67 ($0018)
; Jumps to a routine that writes the contents of de to ports 6 and 7.

j_write67:
	jp   write67

;==============================================================================;
; $0020 - unused
; $0028 - unused
; $0030 - unused
;==============================================================================;
	org &0038

; j_IRQ
; Disables interrupts and jumps to the real IRQ routine.

j_IRQ:
	di
	jp   IRQ

;==============================================================================;
; This section identifies the driver name, version, and author.
	ascii "MZS sound driver by GbaCretin"

;==============================================================================;
	org &0066

; NMI
NMI:
	out (DISABLE_NMI),a

	; save register state
	push ix
	push iy
	push hl
	push de
	push bc
	push af
		in a,(READ_68K)
		ld (com_68k_input),a ; backup 68k input

		ld a,(com_loading_arg)
		cp a,0                ; if com_loading_arg == 0
		ld a,(com_68k_input)
		jp z,NMI_load_command ;   load command
		jp NMI_load_argument  ; else load argument

NMI_end:
		xor a,a ; a = 0
		out (READ_68K),a  ; Clear the sound code by writing to port 0
		
		ld a,(com_68k_increment)
		inc a
		ld (com_68k_increment),a
		ld c,a

		ld a,(com_68k_input)
		add a,c

		out (ENABLE_NMI),a
		out (WRITE_68K),a ; Reply to the 68K
	; restore register state
	pop af
	pop bc
	pop de
	pop hl
	pop iy
	pop ix

	retn

; a: 68k input
NMI_load_command:
	; POSSIBLE OPT. remove this
	ld c,a ; backup 68k input into a

	; Load argument count into WRAM
	ld h,0
	ld l,a
	ld de,command_argc
	add hl,de
	ld a,(hl)
	ld (com_current_arg_index),a

	; If there are no arguments, just execute the
	; command
	cp a,0
	ld a,c ; get 68k input back into a
	jp z,NMI_execute_command

	ld (com_68k_command),a

	; If there are arguments, then the next 68k inputs
	; will be said arguments.
	ld a,&FF
	ld (com_loading_arg),a
	jp NMI_end

; a: 68k input
NMI_load_argument:
	ld c,a ; backup 68k input into c

	; Store argument into the argument buffer
	ld a,(com_current_arg_index)
	ld h,0
	ld l,a
	ld de,com_arg_buffer
	add hl,de
	dec hl
	ld (hl),c

	; decrement current argument index
	dec a
	ld (com_current_arg_index),a

	; if all arguments have been received, then
	; execute the command
	cp a,0
	ld a,(com_68k_command)
	jp z,NMI_execute_command

	jp NMI_end

NMI_execute_command:
	; Load command vector
	ld h,0
	ld l,a
	add hl,hl 
	ld de,command_vector
	add hl,de

	ld e,(hl)
	inc hl
	ld d,(hl)
	ex de,hl

	jp hl

NMI_execute_command_end:
	; Tell the driver to wait for a command next.
	ld a,&00
	ld (com_loading_arg),a
	jp NMI_end

command_vector:
	; &00: NOP
	; &01: Slot switch
	; &03: Soft reset
	; &0B: Silence FM channels
	; &0C: Stop ADPCM-A samples
	; &0F: Play ADPCM-A sample (3 arguments)
	; &13: Set ADPCM-A master volume (1 argument)
	; &14: Set IRQ frequency (1 argument)
	; &15: Play SSG note (3 arguments)
	; &16: Play FM note (5 arguments)
	; &17: Play song (1 argument)
	dw command_nop,         command01_Setup,       command_nop,          command03_Setup
	dw command_nop,         command_nop,           command_nop,          command_nop
	dw command_nop,         command_nop,           command_stop_ssg,     command_silence_fm
	dw command_stop_adpcma, command_nop,           command_nop,          command_play_adpcma_sample
	dw command_nop,         command_nop,           command_nop,          command_set_adpcma_mvol
	dw command_set_irq_freq,command_play_ssg_note, command_play_FM_note, command_play_song

command_argc:
	db &00, &00, &00, &00, &00, &00, &00, &00
	db &00, &00, &00, &00, &00, &00, &00, &03
	db &00, &00, &00, &01, &01, &03, &05, &01

;==============================================================================;
; Real IRQ code
IRQ:
	di

	; save register state
	push af
	push bc
	push de
	push hl
	push ix
	push iy
		call MLM_irq
		call FM_irq
		call SSG_irq
		
.IRQ_end:
		; clear Timer B counter and
		; copy load timer value into
		; the counter
		ld d,REG_TIMER_CNT
		ld e,%00101010
		rst RST_YM_WRITEA

	; restore register state
	pop  iy
	pop  ix
	pop  hl
	pop  de
	pop  bc
	pop  af

	; enable interrupts and return
	ei
	ret

;==============================================================================;
; EntryPoint
; The entry point of the sound driver. Sets up the working conditions.
; wpset F800,1,w,wpdata==39
EntryPoint:
	ld   sp,0xFFFC  ; set the stack pointer to $FFFC ($FFFD-$FFFE is used elsewhere)
	im   1          ; set interrupt mode 1 (IRQ at $0038)
	out (ENABLE_NMI),a

	; clear RAM at $F800-$FFFF
	xor  a ; set A = 0
	ld   (0xF800),a ; write 0 to $F800
	ld   hl,0xF800  ; load $F800 (value to write) into hl
	ld   de,0xF801  ; load $F801 (beginning address) into de
	ld   bc,0x7FF   ; load $07FF (loop length) into bc
	ldir            ; write value from hl to address in de, increment de, decrement bc

	; stop and/or silence audio channels
	call ssg_Stop
	call fm_Stop
	call pcma_Stop
	call pcmb_Stop

	call SetDefaultBanks
	call set_defaults

	; Write 1 to port $C0
	; (Unsure of the purpose, but every working sound driver has this.)
	ld   a,1
	out  (0xC0),a

	ei ; enable interrupts on the Z80 side

	; Tell the 68k the driver is ready to get user
	; commands
	ld a,&39
	out (WRITE_68K),a

main_loop:
	halt
	jr main_loop

set_defaults:
	push af
	push de
	push bc
	push hl
		; Enable SSG Tone and disable noise
		ld de,REG_SSG_MIX_ENABLE<<8 | %00111000       
		rst RST_YM_WRITEA

		ld a,%11111000
		ld (ssg_mix_enable_flags),a

		; ADPCM-A master volume: 32/63
		ld de,REG_PA_MVOL<<8 | &3F
		rst RST_YM_WRITEB

		; ADPCM-A channel volumes: 31/31 LR
		ld de,REG_PA_CVOL<<8 | (31 | %11000000)
		rst RST_YM_WRITEB
		inc d
		rst RST_YM_WRITEB
		inc d
		rst RST_YM_WRITEB
		inc d
		rst RST_YM_WRITEB
		inc d
		rst RST_YM_WRITEB
		inc d
		rst RST_YM_WRITEB

		; Set ssg defaults
		ld b,3
ep_ssg_loop:
		ld a,b
		dec a
		ld c,15
		call SSG_set_attenuator
		djnz ep_ssg_loop

		; Set fm defaults
		ld b,4
ep_fm_loop:
		; Set panning to CENTER (L on, R on)
		
		; Calculate MLM channel (6 to 9)
		; then set panning
		ld a,b
		add a,5
		ld c,%11000000
		call FM_set_panning

		; Load correct FM channel in a
		ld h,0
		ld l,b
		ld de,FM_channel_LUT
		dec hl
		add hl,de
		ld a,(hl)

		push bc
			ld b,a
			ld c,0
			call FM_load_instrument
		pop bc

		ld c,127
		call FM_set_attenuator

		djnz ep_fm_loop

		; Set timer B
		; IRQ should be raised every 1/60th of a second
		;    e = 256 - (t / 1152 * 4000000)
		;        256 - (1/60 / 1152 * 4000000)
		ld e,198                   
		call TMB_set_counter_load
	pop hl
	pop bc
	pop de
	pop af
	ret

	include "SSG.asm"
	include "timer.asm"
	include "utils.asm"
	include "commands.asm"
	include "adpcma.asm"
	include "math.asm"
	include "FM.asm"
	include "MLM.asm"

	org BANK3
	
MLM_header:
	dw MLM_song0-MLM_header ; song 0 offset
	dw MLM_song1-MLM_header ; song 1 offset
	dw MLM_song2-MLM_header ; song 2 offset
	dw MLM_song3-MLM_header ; song 3 offset
	dw MLM_song4-MLM_header ; song 4 offset
	dw MLM_song5-MLM_header ; song 5 offset
	dw MLM_song6-MLM_header ; song 6 offset
	dw MLM_song7-MLM_header ; song 7 offset
	dw MLM_song8-MLM_header ; song 8 offset
	dw MLM_song9-MLM_header ; song 9 offset
	dw MLM_song10-MLM_header ; song 10 offset
	dw MLM_song11-MLM_header ; song 11 offset
	dw MLM_song12-MLM_header ; song 12 offset

MLM_song0:
	; ADPCM-A channel offsets
	dw MLM_pa_data-MLM_header, 0, 0, 0, 0, 0
	; FM channel offsets
	dw 0, 0, 0, 0
	; SSG channel offsets
	dw 0, 0, 0

MLM_song1:
	; ADPCM-A channel offsets
	dw 0, MLM_pa_data-MLM_header, 0, 0, 0, 0
	; FM channel offsets
	dw 0, 0, 0, 0
	; SSG channel offsets
	dw 0, 0, 0

MLM_song2:
	; ADPCM-A channel offsets
	dw 0, 0, MLM_pa_data-MLM_header, 0, 0, 0
	; FM channel offsets
	dw 0, 0, 0, 0
	; SSG channel offsets
	dw 0, 0, 0

MLM_song3:
	; ADPCM-A channel offsets
	dw 0, 0, 0, MLM_pa_data-MLM_header, 0, 0
	; FM channel offsets
	dw 0, 0, 0, 0
	; SSG channel offsets
	dw 0, 0, 0

MLM_song4:
	; ADPCM-A channel offsets
	dw 0, 0, 0, 0, MLM_pa_data-MLM_header, 0
	; FM channel offsets
	dw 0, 0, 0, 0
	; SSG channel offsets
	dw 0, 0, 0

MLM_song5:
	; ADPCM-A channel offsets
	dw 0, 0, 0, 0, 0, MLM_pa_data-MLM_header
	; FM channel offsets
	dw 0, 0, 0, 0
	; SSG channel offsets
	dw 0, 0, 0

MLM_song6:
	; ADPCM-A channel offsets
	dw 0, 0, 0, 0, 0, 0
	; FM channel offsets
	dw MLM_fm_data-MLM_header, 0, 0, 0
	; SSG channel offsets
	dw 0, 0, 0

MLM_song7:
	; ADPCM-A channel offsets
	dw 0, 0, 0, 0, 0, 0
	; FM channel offsets
	dw 0, MLM_fm_data-MLM_header, 0, 0
	; SSG channel offsets
	dw 0, 0, 0

MLM_song8:
	; ADPCM-A channel offsets
	dw 0, 0, 0, 0, 0, 0
	; FM channel offsets
	dw 0, 0, MLM_fm_data-MLM_header, 0
	; SSG channel offsets
	dw 0, 0, 0

MLM_song9:
	; ADPCM-A channel offsets
	dw 0, 0, 0, 0, 0, 0
	; FM channel offsets
	dw 0, 0, 0, MLM_fm_data-MLM_header
	; SSG channel offsets
	dw 0, 0, 0

MLM_song10:
	; ADPCM-A channel offsets
	dw 0, 0, 0, 0, 0, 0
	; FM channel offsets
	dw 0, 0, 0, 0
	; SSG channel offsets
	dw MLM_ssg_data-MLM_header, 0, 0

MLM_song11:
	; ADPCM-A channel offsets
	dw 0, 0, 0, 0, 0, 0
	; FM channel offsets
	dw 0, 0, 0, 0
	; SSG channel offsets
	dw 0, MLM_ssg_data-MLM_header, 0

MLM_song12:
	; ADPCM-A channel offsets
	dw 0, 0, 0, 0, 0, 0
	; FM channel offsets
	dw 0, 0, 0, 0
	; SSG channel offsets
	dw 0, 0, MLM_ssg_data-MLM_header

MLM_pa_data:
	;db 0 | (15<<1) | &80, 5
	;db &00
	
	; play note
	db &05, &1F, 0 ; Set Ch. Vol., volume, timing
	db &07, (&3F<<2) | 0, 0 ; (volume<<2) | timing msb, timing lsb
	db 0 | (15<<1) | &80, NOTE_C ; Sample MSB | (Timing<<1) | &80, Sample LSB
	db 0 | (15<<1) | &80, NOTE_CS
	db 0 | (15<<1) | &80, NOTE_D
	db 0 | (15<<1) | &80, NOTE_DS
	db 0 | (15<<1) | &80, NOTE_E
	db 0 | (15<<1) | &80, NOTE_F

	db &0C, 0, 0           ; Port. slide, should be skipped
	db &05, &17, 0         ; Set Ch. Vol., volume, timing
	db &06, PANNING_L | 0  ; Set Pan., panning | timing
	db &08, 2, 0           ; Set base time, base time, timing
	db &09, 227, 0         ; Set Timer B, Timer B, timing (timer every 120hz)
	db 0 | (15<<1) | &80, NOTE_FS
	db 0 | (15<<1) | &80, NOTE_G
	db 0 | (15<<1) | &80, NOTE_GS

	db &06, PANNING_R | 0 ; Set Pan.
	db 0 | (15<<1) | &80, NOTE_A
	db 0 | (15<<1) | &80, NOTE_AS
	db 0 | (15<<1) | &80, NOTE_B

MLM_pa_data_pos_jump:
	; Small position jump event, offset
	db &0A, MLM_pa_data_dest-(MLM_pa_data_pos_jump+2)

	db &47, &49, &95 ; garbage

MLM_pa_data_dest:
	db &01, 30       ; Note off, timing
	db &00            ; end of channel event list
	db 0 | (30<<1) | &80, NOTE_B ; C; shouldn't be played

MLM_fm_data:
	db &02, 1 ; Change instrument
	db &05, &7F-&7F, 0 ; Set Ch. Vol., volume, timing
	db 15 | &80, NOTE_C  | (3<<4)  ; timing | &80, note | (octave<<4)
	db 15 | &80, NOTE_CS | (3<<4)
	db 15 | &80, NOTE_D  | (3<<4)
	db 15 | &80, NOTE_DS | (3<<4) 
	db 15 | &80, NOTE_E  | (3<<4)
	db 0 | &80, NOTE_F  | (3<<4)
	db &0C, 4, 15       ; Port. slide, slide speed, timing

MLM_fm_data_pos_jump:
	db &0B ; Big position jump event
	dw MLM_fm_data_dest-(MLM_fm_data_pos_jump+3)

	ds 512 ; garbage

MLM_fm_data_dest:
	db &05, &7F-&78, 0 ; Set Ch. Vol., volume, timing
	db &06, PANNING_L | 0 ; Set Pan., panning | timing
	db 15 | &80, NOTE_FS | (3<<4)
	db 15 | &80, NOTE_G  | (3<<4) 
	db 15 | &80, NOTE_GS | (3<<4) 

	db &06, PANNING_R | 0 ; Set Pan., panning | timing
	db 15 | &80, NOTE_A  | (3<<4)
	db 15 | &80, NOTE_AS | (3<<4)
	db 15 | &80, NOTE_B  | (3<<4)

	db &01, 30 ; Note off, timing
	db &00 ; end of list
	db 30 | &80, 9 | (3<<4)  ; A4

MLM_ssg_data:
	db &05, &0F, 0 ; Set Ch. Vol., volume, timing
	db 15 | &80, (1*12) + NOTE_C ; timing | &80, (octave-2)*12 + note
	db 15 | &80, (1*12) + NOTE_CS
	db 15 | &80, (1*12) + NOTE_D
	db 15 | &80, (1*12) + NOTE_DS
	db 15 | &80, (1*12) + NOTE_E 
	db 15 | &80, (1*12) + NOTE_F
	db &0C, 0, 0           ; Port. slide, should be skipped

	db &05, &0B, 10 ; Set Ch. Vol., volume, timing 
	db 15 | &80, (1*12) + NOTE_FS
	db 15 | &80, (1*12) + NOTE_G 
	db 15 | &80, (1*12) + NOTE_GS 
	db 15 | &80, (1*12) + NOTE_A 
	db 15 | &80, (1*12) + NOTE_AS 
	db 15 | &80, (1*12) + NOTE_B

	db &01, 30 ; Note off, timing
	db &00

	org BANK2
instruments:
	;============= Instrument 0 ============== ;
	; SSG
	;;;;       Volume Macro Metadata        ;;;;
	db &20           ; Macro size (in nibbles)
	db &FF           ; Loop point (&FF = no loop)
	dw vol_macro     ; Pointer to macro
	db SSG_MIX_TONE  ; mix
	ds 27            ; padding

	;============= Instrument 1 ============== ;
	; FM
	; Channel regs
	db 4 | (4<<3)             ; ALGO | (FB<<3)
	db 0 | (0<<4)             ; PMS | (AMS<<4) 
	; Operator 1 regs
	db 1 | (0<<4)             ; MUL | (DT<<4)
	db 7                      ; Total Level
	db 31 | (0<<6)            ; AR | (KS<<6)
	db 9 | (0<<7)             ; DR | (AM<<7)
	db 15                     ; Sustain Rate [RS]
	db 15 | (15<<4)           ; RR | (SL<<4)
	db 0                      ; SSG-EG
	; Operator 2 regs
	db 1 | (0<<4)             ; MUL | (DT<<4)
	db 8                      ; Total Level
	db 31 | (0<<6)            ; AR | (KS<<6)
	db 9  | (0<<7)            ; DR | (AM<<7)
	db 15                     ; Sustain Rate [RS]
	db 15 | (15<<4)           ; RR | (SL<<4)
	db 0                      ; SSG-EG
	; Operator 3 regs
	db 0 | (0<<4)             ; MUL | (DT<<4)
	db 36                     ; Total Level
	db 31 | (0<<6)            ; AR | (KS<<6)
	db 10 | (0<<7)            ; DR | (AM<<7)
	db 15                     ; Sustain Rate [RS]
	db 15 | (15<<4)            ; RR | (SL<<4)
	db 0                      ; SSG-EG
	; Operator 4 regs
	db 1 | (0<<4)             ; MUL | (DT<<4)
	db 17                     ; Total Level
	db 31 | (0<<6)            ; AR | (KS<<6)
	db 9 | (0<<7)             ; DR | (AM<<7)
	db 15                     ; Sustain Rate [RS]
	db 15 | (15<<4)           ; RR | (SL<<4)
	db 0                      ; SSG-EG
	; padding
	ds 2
	
	org BANK1
vol_macro:
	; Since it's a volume macro, each
	; nibble is one value.
	db &FF,&EE,&DD,&CC,&BB,&AA,&99,&88
	db &77,&66,&55,&44,&33,&22,&11,&00

;arp_macro:
;	; Each value is a single signed byte
;	db 0,0,0,0, 1,1,1,1,     2,2,2,2,     1,1,1,1
;	db 0,0,0,0, -1,-1,-1,-1, -2,-2,-2,-2, -1,-1-1,-1

	org BANK0
PA_sample_LUT:
	binary "adpcma_sample_lut.bin"

	include "z80ram.asm"
