// BackTrak Raster Sync
// Copyright (C) 2026 8BitGuru <the8bitguru@gmail.com>

.filenamespace brs_raster_sync

// Initialise backtracker raster sync
Backtrack_Initialisation:
.pc = * "Backtrack Initialisation"
{
            sei                                             // [2]      disable IRQ
            ldx #$10000000                                  // [2]      set NTSC flag bit

            // set backtrack IRQ handler
			lda #<Backtrack_IRQ								// [2]		get IRQ handler address lo-byte
			sta vic20.os_vars.IRQVECL						// [4]		set IRQ vector lo-byte
			lda #>Backtrack_IRQ								// [2]		get IRQ handler address hi-byte
			sta vic20.os_vars.IRQVECH						// [4]		set IRQ vector hi-byte

			// check for PAL or NTSC
			ldy #7											// [2]		set cycle timer table index (NTSC)
			lda #1											// [2]		raster compare line (#2, register counts in twos)
wait2:		cmp vic20.vic.VCRASTER							// [4]		check for raster line
			bne wait2										// [3/2]	loop until we hit it
wait268:	lda vic20.vic.VCRASTER							// [4]		get current raster line
			beq timer_init		    						// [3/2]	video mode is NTSC if we find line 0 before line 268
			cmp #134										// [2]		look for line 268 for PAL
			bne wait268										// [3/2]	loop until we find 0 or 268

			// copy VIA cycle timer values for video mode (PAL/NTSC)
			ldy #3											// [2]		set cycle timer table index (PAL)
            ldx #0                                          // [2]      set PAL flag bit
timer_init: stx brs_runtime_memory.Backtrack_Lock_State  	// [3]		stash PAL/NTSC flag bit in ZP
        	ldx #3											// [2]		cycle timer value byte count
timer_copy:	lda brs_static_data.Backtrack_Timer_Values,y	// [4]		get cycle timer byte
			sta brs_runtime_memory.Backtrack_IRQ_Timer_Lo,x // [4]		stash in zero-page
			dey												// [2]		decrement table index
			dex												// [2]		decrement counter
			bpl timer_copy									// [3/2]	loop until done

			// set VIA timer for backtrack IRQ
			lda brs_runtime_memory.Backtrack_IRQ_Timer_Lo	// [3]		get IRQ timer lo-byte
			sta vic20.via2.V2T1LL							// [4]		set VIA2 timer #1 counter lo-latch
			lda brs_runtime_memory.Backtrack_IRQ_Timer_Hi	// [3]		get IRQ timer hi-byte
			sta vic20.via2.V2T1LH							// [4]		set VIA2 timer #1 counter hi-latch

            // set loop counter in ZP for PAL/NTSC
            ldy #182                                        // [2]      PAL inner count
			lda brs_runtime_memory.Backtrack_Lock_State  	// [3]		get PAL/NTSC flag bit
            bcc set_count                                   // [2/3]    set PAL count
            ldy #140                                        // [2]      NTSC inner count
set_count:	sty brs_runtime_memory.Backtrack_IRQ_Timer_Hi   // [4]		stash inner loop count

			// sync to raster line 0 or 1
			inx												// [2]		.X = 0
			stx brs_runtime_memory.Backtrack_Lock_State  	// [3]		set backtrack sync state (0=tracking)
wait0:		cpx vic20.vic.VCRASTER							// [4]		check for raster line
			bne wait0										// [3/2]	loop until we hit it
            cli												// [2]		enable backtrack IRQ

spinwait:
// this only works for PAL - rework to get loop values from static data and place into ZP so cycles remain constant
            ldx #24                 // [2]   PAL outer count (NTSC: #5)
sw_outer:   ldy brs_runtime_memory.Backtrack_IRQ_Timer_Hi                // [2]   PAL inner count (NTSC: #674)
sw_inner:   dey                     // [2]
            bne sw_inner            // [3/2]
            bit $9124               // [4]   PAL payload: BIT abs (NTSC: bit $xx = BIT zp [3])
            dex                     // [2]
            bne sw_outer            // [3/2]

            // NOP runout - IRQ fires somewhere in here
            // PAL: 12 NOPs (24 cycles), NTSC: 11 NOPs (22 cycles)
            nop                     // [2]
            nop                     // [2]
            nop                     // [2]
            nop                     // [2]
            nop                     // [2]
            nop                     // [2]
            nop                     // [2]
            nop                     // [2]
            nop                     // [2]
            nop                     // [2]
            nop                     // [2]
            nop                     // [2]   PAL only (omit for NTSC)

            // IRQ did not fire - should not reach here
            jmp spinwait            // [3]   error: restart sync
}


// Backtrack IRQ handler
// Fires once per frame during backtracking phase checking if we're still on line 0/1
// If so, just return and let the timer reload for the next frame
// If not we're on the last line of the previous frame
// 23 cycles including 7-cycle hardware IRQ delay
Backtrack_IRQ:
.pc = * "Backtrack IRQ"
{
            bit vic20.via2.V2T1CL      						// [4]      acknowledge IRQ
            lda vic20.vic.VCRASTER  						// [4]      check raster line
            bne Backtrack_Sync         						// [3/2]    not line 0/1 so establish raster sync
            rti                     						// [6]      still on line 0/1
}


// Backtrack raster sync lock
Backtrack_Sync:
.pc = * "Backtrack Sync"
{
// locked:
//             ldx #5                  // [2]   PAL outer count (NTSC: #32)
// bw_outer:   ldy #883                // [2]   PAL inner count (NTSC: #104)
// bw_inner:   dey                     // [2]
//             bne bw_inner            // [3/2]
//             nop                     // [2]   PAL payload (NTSC: bit $xx)
//             dex                     // [2]
//             bne bw_outer            // [3/2]

//             // load locked timer values from ZP and arm timer
//             lda TIMER_LO_LOCKED     // [3]   PAL: $60 (22112), NTSC: $1D (16925)
//             sta $9126               // [4]   VIA2 T1 latch lo
//             lda TIMER_HI_LOCKED     // [3]   PAL: $56, NTSC: $42
//             sta $9127               // [4]   VIA2 T1 latch hi - arms timer

            rti                     // [56]   lands on cycle 0 of line 0
}