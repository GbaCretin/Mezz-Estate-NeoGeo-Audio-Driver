fm_stop:
	push de
		ld de,(REG_FM_KEY_ON<<8) | FM_CH1
		rst RST_YM_WRITEA
		ld e,FM_CH2
		rst RST_YM_WRITEA
		ld e,FM_CH3
		rst RST_YM_WRITEA
		ld e,FM_CH4
		rst RST_YM_WRITEA
	pop de
	ret

; DOESN'T BACKUP REGISTERS
FM_irq:
	ld b,6

FM_irq_loop:
	; If the channel doesn't exist, 
	; skip to the next iteration
	ld a,b
	cp a,3
	jr z,FM_irq_loop_continue
	cp a,4
	jr z,FM_irq_loop_continue
	
FM_irq_loop_continue:
	djnz FM_irq_loop
	ret

; b: channel
; c: block<<3
; hl: f-number

; b: channel
; c: instrument
; resets the volume of all operators.
FM_load_instrument:
	push hl
	push de
	push af
	push bc
		;;;;;; Calculate pointer to instrument ;;;;;;
		ld h,0 
		ld l,c

		add hl,hl
		add hl,hl
		add hl,hl
		add hl,hl
		add hl,hl ; hl *= 32

		ld de,INSTRUMENTS
		add hl,de

		;;;;;; Set channel registers ;;;;;;
		ld d,REG_FM_CH13_FBALGO
		ld e,(hl)

		; if channel is even (is CH2 or CH4), then
		; increment REG_FM_CH13_FBALGO, this results
		; in REG_FM_CH24_FBALGO
		bit 0,b
		jp nz,FM_load_instrument_chnl_is_odd
		inc d

FM_load_instrument_chnl_is_odd:
		; if the channel is CH1 or CH2, then write to 
		; port A, else write to port B
		bit 2,b
		call z,port_write_a
		call nz,port_write_b

		; Set LRAMSPMS
		inc hl
		ld a,(hl)

		push hl
		push de
		push bc	
			; Convert FM channel to MLM channel
			; (result is in e)
			ld c,b
			ld b,0
			ld hl,FM_to_MLM_channel_LUT
			add hl,bc
			ld e,(hl)

			; Load panning
			ld d,0
			ld hl,MLM_channel_pannings
			add hl,de
			or a,(hl)
		pop bc
		pop de
		pop hl

		ld e,a

		inc d
		inc d
		inc d
		inc d

		bit 2,b
		call z,port_write_a
		call nz,port_write_b

		;;;;;; Set operator registers ;;;;;;
		inc hl
		
		ld a,b

		ld c,FM_OP1
		call FM_set_operator
		inc c
		call FM_set_operator
		inc c
		call FM_set_operator
		inc c
		call FM_set_operator
	pop bc
	pop af
	pop de
	pop hl
	ret

; [INPUT]
;   a: channel
;   c: operator
;   hl: source
; [OUTPUT]
;   hl: source+7
;   
;   resets the operator's volume
FM_set_operator:
	push de
	push bc
	push ix
		; Calculate FM_base_total_levels offset
		;
		;  base_total_level = 
		;    FM_base_total_levels + ch*4 + op
		push hl
		push af
			; load hl (source) in ix
			ex de,hl
			ld ixh,d
			ld ixl,e

			dec a
			sla a
			sla a
			ld d,0
			ld e,a
			ld hl,FM_base_total_levels
			add hl,de
			ld d,0
			ld e,c
			add hl,de

			ld a,(ix+1)
			ld (hl),a
		pop af
		pop hl

		; Lookup base register address
		push hl
			ld h,0
			ld l,c
			ld de,FM_op_base_address_LUT
			add hl,de
			ld d,(hl)

			; if channel is even (is CH2 or CH4), then
			; increment base register address.
			bit 0,a
			jp nz,FM_set_operator_chnl_is_odd
			inc d

FM_set_operator_chnl_is_odd:
		pop hl

		ld b,7

FM_set_operator_loop:
		ld e,(hl)

		bit 2,a
		call z,port_write_a
		call nz,port_write_b

		push af
			ld a,d
			add a,&10
			ld d,a
		pop af

		inc hl

		djnz FM_set_operator_loop
		; dec b
		; jr z,FM_set_operator_loop
	pop ix
	pop bc
	pop de
	ret

; b: channel
; c: -OOONNNN (Octave; Note)
FM_set_note:
	push hl
	push de
	push af
		; Lookup F-Number from FM_pitch_LUT
		; and store it into de
		ld a,c
		and a,&0F
		sla a
		ld h,0
		ld l,a
		ld de,FM_pitch_LUT
		add hl,de
		ld e,(hl)
		inc hl
		ld d,(hl)

		; Load block into c
		ld a,c
		srl a   ; -OOO---- -> --OOO---
		and a,%00111000
		ld c,a

		ex de,hl
		call FM_set_pitch
	pop af
	pop de
	pop hl
	ret

; b: channel
; c: block<<3
; hl: f-number
FM_set_pitch:
	push de
	push af
		; Store the frequency number into 
		; FM_channel_fnums[channel]
		push bc
			ex de,hl
			ld h,0
			ld l,b
			ld bc,FM_channel_fnums
			add hl,hl
			add hl,bc
			ld (hl),e
			inc hl
			ld (hl),d
			ex de,hl
		pop bc

		; Store fblock into
		; FM_channel_fblocks[channel]
		push hl
		push de
			ld h,0
			ld l,b
			ld de,FM_channel_fblocks
			add hl,de
			ld (hl),c
		pop de
		pop hl

		; OR the f-number MSB and block together
		ld a,c
		or a,h
		ld h,a

		; ======== Write to F-Block ======== ;
		;   Calculate channel register address
		;    if channel is even (is CH2 or CH4), then
		;    increment REG_FM_CH13_FBLOCK, this results
		;    in REG_FM_CH24_FBLOCK
		ld d,REG_FM_CH13_FBLOCK
		bit 0,b
		jp nz,FM_set_note_chnl_is_odd
		inc d

FM_set_note_chnl_is_odd:
		;  if the channel is CH1 or CH2, then write to 
		;  port A, else write to port B
		ld e,h
		bit 2,b
		call z,port_write_a
		call nz,port_write_b

		; ======== Write to F-number ========;
		dec d
		dec d
		dec d
		dec d

		ld e,l
		bit 2,b
		call z,port_write_a
		call nz,port_write_b
	pop af
	pop de
	ret

; a: channel
; c: attenuator
FM_set_attenuator:
	push bc
	push hl
	push de
	push ix
		; Index FM_base_total_levels[ch][3]
		push af
			dec a
			sla a
			sla a
			ld d,0
			ld e,a
			ld hl,FM_base_total_levels+3
			add hl,de
		pop af

		ld b,4

FM_set_attenuator_loop:
		; ixl = TL * (127 - AT) / 127 + AT
		push hl
		push af
			ld a,127
			sub a,c

			push bc
				ld e,(hl)
				ld h,a
				call H_Times_E

				ld c,127
				call RoundHL_Div_C
			pop bc

			ld a,c
			add a,l
			
			ld ixl,a
		pop af
		pop hl

		; Lookup operator base address from
		; FM_op_base_address_LUT, then use it
		; to calculate the correct operator
		; register address and store it into d
		push bc
		push hl
		push af
			ld hl,FM_op_base_address_LUT
			ld d,0
			ld e,b
			add hl,de

			ld d,(hl)

			bit 0,a
			jr nz,FM_set_attenuator_loop_op_is_odd
			inc d

FM_set_attenuator_loop_op_is_odd:
			ld a,d
			add a,&10
			ld d,a
		pop af
		pop hl
		pop bc

		ld e,ixl
		bit 2,a
		call z,port_write_a
		call nz,port_write_b

		dec hl

		djnz FM_set_attenuator_loop
	pop ix
	pop de
	pop hl
	pop bc
	ret

; a: channel (MLM channels, from 6 to 9)
; c: panning (0: none, 64: right, 128: left, 192: both)
FM_set_panning:
	push hl
	push de
	push af
	push bc
		ld b,a ; backup channel into b

		; Load current channels's instrument into l
		ld h,0
		ld l,a
		ld de,MLM_channel_instruments
		add hl,de
		ld l,(hl)

		; Calculate pointer to instrument into hl
		ld h,0
		ld de,INSTRUMENTS
		add hl,hl
		add hl,hl
		add hl,hl
		add hl,hl
		add hl,hl ; hl *= 32
		add hl,de

		; Load AM_PMS value into a, then OR a
		; with panning (result is stored in e)
		inc hl
		ld a,(hl)
		or a,c
		ld e,a

		; Load correct FM channel into a
		ld a,b
		sub a,6
		ld h,0
		ld l,a
		ld bc,FM_channel_LUT
		add hl,bc
		ld a,(hl)

		; Write result to the correct 
		; FM register and port
		ld d,REG_FM_CH13_LRAMSPMS
		bit 0,a                      ; \ 
		jr nz,FM_set_panning_ch_odd  ;  | if (fm channel is even) reg++
		inc d                        ; /

FM_set_panning_ch_odd: 
		bit 2,a
		call z,port_write_a
		call nz,port_write_b            
	pop bc
	pop af
	pop de
	pop hl
	ret

; a: channel
FM_stop_channel:
	push af
	push de
		; Stop the OPNB FM channel
		ld d,REG_FM_KEY_ON
		and a,%00000111
		ld e,a
		rst RST_YM_WRITEA
	pop de
	pop af
	ret

FM_op_base_address_LUT:
	db &31,&39,&35,&3D

; to set the octave you just need to set "block".
; octave 0 = block 1, etc...
FM_pitch_LUT:
	;  C    C#   D    D#   E    F    F#   G
	dw 309, 327, 346, 367, 389, 412, 436, 462
	;  G#   A    A#   B
 	dw 490, 519, 550, 583

FM_channel_LUT:
	db FM_CH1, FM_CH2, FM_CH3, FM_CH4

FM_to_MLM_channel_LUT:
	;  /// CH1 CH2 /// /// CH3 CH4
	db 0,  6,  7,  0,  0,  8,  9